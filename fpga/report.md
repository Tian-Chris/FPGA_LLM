# Synthesis Failure Report — 2026-03-05

## Error
```
ERROR: [VPL 8-6038] cannot resolve hierarchical name for the item 'gen_eng' [top_level.v:743]
```
Vivado synthesis failed because `gen_eng[2]` and `gen_eng[3]` were referenced in the `FPGA_TARGET` port wiring, but only `gen_eng[0]` and `gen_eng[1]` exist after `NUM_ENGINES` was lowered from 4 to 2.

## Root Cause
The commit "lowered engine count" changed `NUM_ENGINES = 2` in `defines.vh`, but the FPGA-specific port declarations and wiring (hardcoded for 4 engines) were not updated to match. The generate block `gen_eng` only creates indices `[0:N_ENG-1]`, so with `N_ENG=2`, indices 2 and 3 don't exist.

## Fix Applied
Removed all engine 2/3 AXI infrastructure (hbm02, hbm03, hbm08, hbm09) across 5 files:

| File | Change |
|------|--------|
| `rtl/top_level.v` | Removed wgt2/3, act2/3 port declarations + gen_eng[2]/[3] assigns |
| `fpga/rtl/fpga_kernel.v` | Removed hbm02/03/08/09 ports, wire arrays `[0:3]`→`[0:1]`, instantiation, macro calls |
| `fpga/kernel.xml` | Removed 4 port entries + 4 arg entries |
| `fpga/connectivity.cfg` | Removed 4 sp mapping lines |
| `fpga/build.tcl` | Removed hbm02/03/08/09 from both foreach port lists |

Design went from 10 AXI master ports to 6 (2 wgt + 2 act + flush + DMA).

---

# SLR0 Congestion Analysis (4-Engine Build)

## The Problem
From the placed utilization reports of the previous 4-engine build:

| Resource | SLR0 | SLR1 | SLR2 |
|----------|------|------|------|
| CLB | **99.42%** | 68.43% | 42.73% |
| LUT | 55.10% | 42.52% | 30.53% |
| FF | 52.86% | 28.16% | 16.27% |
| DSP | 71.63% | 64.58% | 68.88% |
| F7 Mux | 22.14% | 12.53% | 7.90% |
| F8 Mux | 15.22% | 3.31% | 2.84% |
| LUT-RAM | 5.97% | 1.93% | 0.77% |
| SRL | 2.84% | 0.06% | 0.36% |

SLR0 is at **99.42% CLB** — essentially unroutable. Anything above ~85% CLB causes severe routing congestion.

## What's Consuming SLR0

The HBM memory controller and PHY are hard silicon, but the **AXI crossbar switch that connects kernel ports to HBM channels is synthesized in FPGA fabric in SLR0**. The placed netlist shows 15 `bd_85ad_interconnect*` instances — each a full AXI interconnect IP with arbitration, FIFOs, address decoders, and pipeline registers — all in SLR0.

With the 4-engine config (10 AXI ports) and `HBM[0:3]` fan-out on each weight port:
- Each of the 4 HBM weight channels needed a 5+ input crossbar mux (4 wgt ports + DMA)
- Total estimated crossbar paths: ~27
- This manifests as the massive LUT-RAM (interconnect FIFOs), SRL (pipeline stages), F7/F8 mux, and register counts in SLR0

## Why Per-Engine Dedicated Ports Don't Scale

Current architecture: each engine gets its own weight AXI port and activation AXI port. Port count = `2 × N_ENG + 2` (flush + DMA). This means:

| Engines | AXI Ports | Crossbar Paths (est.) |
|---------|-----------|----------------------|
| 2 | 6 | ~15 |
| 4 | 10 | ~27 |
| 6 | 14 | ~39 |

Each port adds ~300 wires of AXI infrastructure, a full interconnect IP block in SLR0, and crossbar paths for every HBM channel it maps to. SLR0 fills up fast.

---

# Proposed Architecture: RTL Arbiter with Decoupled Engine/Port Scaling

## Concept
Replace per-engine AXI ports with a lightweight RTL arbiter that multiplexes N engines onto M HBM ports, where M is fixed regardless of engine count.

```
                          YOUR RTL (any SLR)              SLR0
                     ┌─────────────────────┐     ┌──────────────────┐
  Engine 0 ──┐       │                     │     │                  │
  Engine 1 ──┤───────│  Sequential Arbiter │─────│ AXI port 0 ─ HBM[0]
  Engine 2 ──┤       │  (round-robin mux)  │     │ AXI port 1 ─ HBM[1]
  Engine 3 ──┤       │                     │     │ AXI port 2 ─ HBM[2]
  Engine 4 ──┤       │  ~500 LUTs, lives   │     │ AXI port 3 ─ HBM[3]
  Engine 5 ──┘       │  wherever engines   │     │                  │
                     │  are placed         │     │ (1:1 mapping,    │
                     └─────────────────────┘     │  no crossbar)    │
                                                 └──────────────────┘
                     + same pattern for act ports
```

## Why This Works

**Arbiter overhead is negligible.** The tiling engine already dispatches tiles to engines sequentially (1 per cycle). After dispatch, each engine spends hundreds to thousands of cycles fetching a tile (~64 AXI burst reads for a 32×32 tile) and then computing (32×32×K MAC operations). The arbiter adds 1-2 cycles of switching latency — less than 1% overhead. Engines are mostly computing, not waiting on memory.

**The arbiter is cheap.** It only needs to handle simple sequential burst reads — no AXI ID reordering, no write channel, no clock domain crossing, no outstanding transaction tracking. This is ~500 LUTs in your RTL vs tens of thousands of LUTs per Vitis interconnect instance.

**The arbiter lives in your SLR, not SLR0.** The Vitis crossbar is forced into SLR0 next to the HBM hard IP. Your arbiter is just regular RTL that Vivado places wherever the engines are.

## Comparison

| | Current (per-engine ports) | Arbiter approach |
|---|---|---|
| Port count | 2 × N_ENG + 2 | **Fixed (e.g. 4 wgt + 2 act + flush + DMA = 8, or fewer)** |
| SLR0 crossbar | Grows with engines, wide fan-out | **Fixed, 1:1 mapping, no fan-out** |
| Bandwidth scaling | Add ports | Add ports (independent of engines) |
| Compute scaling | Add engines (but also adds ports) | **Add engines (ports unchanged)** |
| Arbiter cost | N/A | ~500 LUTs in engine SLR |
| Bandwidth per port | 14.4 GB/s (256-bit @ 450MHz) | Same |
| Peak concurrent reads | N_ENG | M (number of ports) |
| Actual throughput loss | — | <5% (engines mostly computing) |

## Key Insight
Engine count becomes a compute knob. Port count becomes a bandwidth knob. They scale independently. You can run 6 engines on 4 weight ports without any crossbar explosion in SLR0.

## Status
- 2-engine / 6-port build kicked off 2026-03-05 (immediate fix, no RTL changes needed)
- Arbiter is a future optimization if more engines are needed or if 6 ports still causes SLR0 congestion
