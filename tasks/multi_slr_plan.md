# Multi-SLR Engine Scaling Plan: 2 → 6 Engines

## Current State
- 2 engines, all SLR0: 42% LUTs, 72% DSPs (2063), 80% URAM (256), 89% CLB
- HBM physically connects to SLR0 on U280
- Build achieves 148 MHz (target 200)

## Resource Budget per SLR (U280)

| Resource | SLR0  | SLR1  | SLR2  |
|----------|-------|-------|-------|
| DSPs     | 2880  | 3072  | 3072  |
| URAMs    | 320   | 320   | 320   |
| LUTs     | ~440K | ~432K | ~432K |

Each engine costs ~1024 DSPs (MAC units) + ~128 URAMs (accum buffer).

## Critical Issue: DSP Recovery

Current build uses 2063 DSPs with only 2 engines (2x1024=2048 MAC DSPs). The remaining ~15 DSPs come from address math multiplications being inferred as DSP48E2.

BUT if we scale to 6 engines naively: 6x1024 = 6144 MAC DSPs alone. Total U280 has 9024 DSPs. With address math DSPs eliminated via `(* use_dsp = "no" *)`, we get:
- 6 engines: ~6144 + ~200 (platform/misc) = 6344 of 9024 (70%) -- feasible!

## Proposed SLR Assignment

| SLR  | Engines   | DSPs      | URAMs | Other                        |
|------|-----------|-----------|-------|------------------------------|
| SLR0 | 0, 1      | 2048+misc | ~128  | FSM, tiling_engine, LN, SM, tile_loaders, HBM |
| SLR1 | 2, 3      | 2048      | 256   | uram_accum_buf              |
| SLR2 | 4, 5      | 2048      | ~128  |                              |

## Data Flow & SLR Crossings

### What crosses SLR boundaries:

1. **Tiling engine commands** (SLR0 → SLR1/SLR2): ~150 bits/engine (cmd_valid, op, m/k/n, bases, strides)
2. **URAM writes** (all SLRs → SLR1 where uram_accum_buf lives): ~276 bits/engine (wr_en, addr, data)
3. **HBM AXI ports**: Platform handles crossbar routing; each port ~300 bits

SLL budget: 23,040 per boundary. Current ~10,500 (45%). Adding ~3000 for new engines → ~13,500 (58%). Safe.

### HBM Bandwidth Risk
6 activation loaders on HBM[4] (one bank, 14.4 GB/s). Peak demand: 6 x 32B x 150MHz = 28.8 GB/s.
**Mitigation:** Spread across HBM[4:5].

## Implementation Phases

### Phase 1: DSP Recovery (prerequisite, low risk)

Add `(* use_dsp = "no" *)` to non-MAC multiplications:
- `rtl/tiling_engine.v` — address calculations
- `rtl/uram_accum_buf.v` — write arbiter address mux
- `rtl/matmul_engine.v` (matmul_controller) — HBM address math
- `rtl/uram_flush.v` — address calculations
- `rtl/fsm_controller.v` — base address offset calculations

**Verify:** Rebuild with 2 engines, confirm DSP count drops. Confirm timing still meets.

### Phase 2a: Scale to 4 Engines (medium risk, recommended first)

This stays within SLR0+SLR1, avoids SLR2 complexity.

1. `defines.vh`: Change `NUM_ENGINES = 2` → `NUM_ENGINES = 4`
2. `fpga_kernel.v`: Add 4 more m_axi ports (hbm02-03 wgt, hbm08-09 act)
3. `top_level.v`: Generate loop already scales. Add FPGA_TARGET port wiring for engines 2-3.
4. `kernel.xml`: Add 4 more port/arg entries (sequential IDs)
5. `connectivity.cfg`: Add HBM mappings for 4 new ports
6. `build.tcl`: Add new ports to clock association + address space loops
7. `host.cpp`: Update kernel() calls with additional buffer args

**Estimated DSPs:** 4096 + ~200 = 4296 of 9024 (47.6%) — comfortable.

### Phase 2b: Scale to 6 Engines + SLR Constraints (higher risk)

1. `defines.vh`: `NUM_ENGINES = 6`
2. Add 4 more m_axi ports for engines 4-5
3. Create `fpga/slr_constraints.tcl`:
   ```tcl
   create_pblock pblock_eng01
   resize_pblock pblock_eng01 -add {SLR0}
   add_cells_to_pblock pblock_eng01 [get_cells -hier -regex {.*gen_eng\[0\].*|.*gen_eng\[1\].*}]
   set_property IS_SOFT TRUE [get_pblocks pblock_eng01]

   create_pblock pblock_eng23
   resize_pblock pblock_eng23 -add {SLR1}
   add_cells_to_pblock pblock_eng23 [get_cells -hier -regex {.*gen_eng\[2\].*|.*gen_eng\[3\].*}]
   set_property IS_SOFT TRUE [get_pblocks pblock_eng23]

   create_pblock pblock_eng45
   resize_pblock pblock_eng45 -add {SLR2}
   add_cells_to_pblock pblock_eng45 [get_cells -hier -regex {.*gen_eng\[4\].*|.*gen_eng\[5\].*}]
   set_property IS_SOFT TRUE [get_pblocks pblock_eng45]

   # URAM accum buffer in SLR1
   add_cells_to_pblock pblock_eng23 [get_cells -hier -regex {.*u_uram.*}]
   ```
4. Apply via: `--vivado.prop run.impl_1.STEPS.PLACE_DESIGN.TCL.PRE=slr_constraints.tcl`
5. May need explicit SLR crossing pipeline registers if auto-pipelining fails

### Phase 3: Timing Optimization

- Add SLR pipeline registers in RTL if Vivado auto-pipelining insufficient
- `--vivado.prop run.impl_1.STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE=AggressiveExplore`
- HBM bandwidth: spread activation across HBM[4:5]
- May need to accept 150 MHz target

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| DSP overflow | HIGH | Phase 1 must succeed first |
| SLL congestion at SLR boundary | MEDIUM | 14 AXI ports → ~13K/23K SLLs (56%) |
| URAM write arbiter contention (6 engines, 1 port) | MEDIUM | 5-cycle worst-case stall, ~10-15% throughput reduction |
| HBM bandwidth saturation | MEDIUM | Spread across 2 HBM banks |
| Timing closure | HIGH | May need to lower to 150 MHz target |
| Platform AXI crossbar scaling (14 master ports) | LOW | Within U280 32-channel limit |

## Files to Modify

- `rtl/defines.vh` — NUM_ENGINES, HBM channel count
- `rtl/top_level.v` — FPGA_TARGET port wiring, SLR pipe registers
- `fpga/rtl/fpga_kernel.v` — m_axi port declarations
- `fpga/kernel.xml` — port and arg entries (sequential IDs!)
- `fpga/connectivity.cfg` — HBM bank mappings
- `fpga/build.tcl` — clock/address space loops
- `fpga/Makefile` — SLR constraint TCL path
- `fpga/host.cpp` — kernel() invocation args
