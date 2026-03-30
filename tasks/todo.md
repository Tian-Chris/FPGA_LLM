# FPGA Debug: HBM Protocol Analysis & Fix Plan

## Background
Simulation passes but FPGA produces wrong results. Diagnostic test modes (1, 5, 6, 7, 12) are implemented in RTL and pass in sim. Phase 1 (diagnostic RTL) is complete. Focus is now on HBM protocol compliance and getting tests running on real hardware.

---

## HBM Research Findings: RTL vs Alveo U280

### U280 HBM2 Hardware Specs
- 8 GB total (2×4 GB stacks), 32 pseudo-channels, 256 MB each
- 32 hardened AXI3 slave ports, 256-bit data width
- **AXI3 protocol** (not AXI4): max burst = 16 beats (ARLEN/AWLEN ≤ 15)
- 4 KB address boundary: bursts must not cross
- Internal crossbar: 8× segmented 4×4 switches (aligned access = lowest latency)
- AXI clock: 450 MHz hardened, user logic typically 100-150 MHz
- Peak bandwidth: 460 GB/s (all 32 ports)

### What fpga_kernel.v Already Handles
The FPGA wrapper correctly provides:
- Address conversion: 28-bit word addr → 33-bit byte addr (<<5 shift)
- ARSIZE/AWSIZE = 5 (32 bytes for 256-bit bus)
- ARBURST/AWBURST = 2'b01 (INCR)
- ARCACHE/AWCACHE, ARPROT/AWPROT, ARLOCK/AWLOCK, ARQOS/AWQOS tied off
- WSTRB = all-ones (full 256-bit writes)
- Unused read/write channels tied off on one-directional ports

### CRITICAL Issue 1: AXI3 Burst Length Violation
**Modules**: `hbm_prefetch.v`, `uram_flush.v`
**Problem**: Both use 8-bit ARLEN/AWLEN and issue bursts up to 255 beats. U280 HBM is AXI3 with max 16 beats.
- `hbm_prefetch.v` line 139: `m_axi_arlen <= num_col_words_r - 1` (up to 63 for 1024-dim)
- `uram_flush.v` line 162: `m_axi_awlen <= num_col_words_r` (up to 64 for 1024-dim)
- Vitis MAY auto-insert a protocol converter for RTL kernels, but this is NOT guaranteed
- If no converter: HBM controller truncates, returns SLVERR, or hangs

**Fix**: Add burst splitter logic — loop issuing ≤16-beat sub-bursts per row.

### CRITICAL Issue 2: uram_flush AWLEN Off-By-One
**Module**: `uram_flush.v` line 162
**Problem**: `m_axi_awlen <= num_col_words_r` but AXI convention is N beats → AWLEN = N-1.
- `hbm_prefetch.v` correctly does `arlen = num_col_words - 1`
- `uram_flush.v` does `awlen = num_col_words` (requests N+1 beats, sends only N)
- HBM slave waits for the extra beat forever → **transaction hangs**

**Fix**: `m_axi_awlen <= num_col_words_r - 1`

### CRITICAL Issue 3: 4KB Address Boundary Crossing
**Modules**: `hbm_prefetch.v`, `uram_flush.v`
**Problem**: No alignment checks. At 32 bytes/word, 4KB = 128 words. Bursts starting mid-boundary can cross.
- `hbm_prefetch`: arbitrary `hbm_addr_r` + burst of `num_col_words` words
- `uram_flush`: `hbm_addr_r + stride` lands anywhere

**Fix**: Burst splitter must also check `words_to_4kb = 128 - addr[6:0]` and split at boundary.

### MEDIUM Issue 4: Crossbar Segment Awareness
- DMA port (P3) maps to HBM[0:5], crossing two 4-channel switch segments
- Weight port maps to HBM[0:3] = single segment (optimal)
- Not a correctness issue but affects latency/throughput

### LOW Issue 5: RRESP/BRESP Not Checked
- All three AXI modules ignore error responses
- Silent data corruption if HBM returns SLVERR/DECERR
- Should at minimum flag errors for debug

### act_dma.v — Clean
- Uses single-beat bursts (ARLEN=0, AWLEN=0) — no AXI3 violation
- No 4KB boundary risk for single beats

---

## Current Test Infrastructure

### RTL Test Modes (in fsm_controller.v)
Set via `test_mode` control register (offset 0x78 in vitis_control.v):

| Mode | State | Tests | HBM Path | AXI3 Safe? |
|------|-------|-------|----------|------------|
| 1 | S_TEST_ECHO | Write 8×256b pattern to HBM | debug_writer (single-beat) | YES |
| 5 | S_TEST_URAM_WR/FL | Write URAM + flush to HBM | uram_flush (multi-beat burst) | **NO** |
| 6 | S_TEST_LATENCY | URAM latency measurement | debug_writer (single-beat) | YES |
| 7 | S_TEST_MULTI_ROW | 4-row URAM write + checkpoint read | debug_writer (single-beat) | YES |
| 12 | S_TEST_REG_CHK | Dump FSM registers to HBM | debug_writer (single-beat) | YES |

### GAP: No Host Program for Test Modes
- `host.cpp` — production inference only, no test_mode support
- `host_emu.cpp` — minimal hw_emu, no test_mode support
- `test_mode` register exists in vitis_control.v but neither host writes to it
- **Need**: test host that writes test_mode register, launches kernel, reads/verifies output

---

## Fix Plan

### Priority 1: Off-by-one fix (1 line)
- [ ] `uram_flush.v` line 162: change `num_col_words_r` to `num_col_words_r - 1`
- [ ] Verify sim still passes (`make test-diag`, `make test-1k`)

### Priority 2: Write test host
- [ ] New `fpga/host_test.cpp` that:
  - Accepts `--test N` CLI arg for test_mode
  - Writes test_mode to AXI-Lite register offset 0x78
  - Launches kernel, waits for completion
  - Reads output buffer and verifies expected patterns per mode
  - Runs modes 12 → 1 → 5 in sequence for full validation
- [ ] Add `make host-test` and `make run-test` targets to fpga/Makefile

### Priority 3: Burst splitter for hbm_prefetch
- [ ] Add FSM sub-loop: split each row into ≤16-beat bursts
- [ ] Check 4KB boundary: `words_to_4kb = 128 - addr[6:0]`, take min(remaining, 16, words_to_4kb)
- [ ] Track col_word offset for URAM writes across sub-bursts
- [ ] Verify: `make test-1k` (exercises 64-word rows that will now split into 4×16)

### Priority 4: Burst splitter for uram_flush
- [ ] Same pattern: split write bursts into ≤16 beats with 4KB boundary check
- [ ] Track beat counter and WLAST across sub-bursts
- [ ] Verify: `make test-diag` mode 5, `make test-1k`

### Priority 5: RRESP/BRESP error flagging
- [ ] Add error registers in hbm_prefetch, uram_flush, act_dma
- [ ] Wire to debug registers readable via AXI-Lite
- [ ] Non-blocking: just flag, don't halt

---

## FPGA Test Run Plan (after fixes)

1. Build: `make package && make link-prod`
2. Run test_mode=12: verify register plumbing works
3. Run test_mode=1: verify single-beat HBM writes
4. Run test_mode=5: verify uram_flush path (now with burst splitter)
5. Run test_mode=6: measure actual URAM read latency on hardware
6. Run test_mode=7: verify multi-row URAM addressing
7. If all pass: run normal inference with max_steps=1, compare against golden

## Step-Debug Strategy (after tests pass)
- max_steps=1 (LN1 only), compare activation buffer vs golden
- Increment max_steps until mismatch appears
- Use debug trace (0xCC headers) to track FSM execution

---

## Test Commands Reference

| Command | Description |
|---------|-------------|
| `make test-diag` | All diagnostic tests in sim |
| `python3 verify/test_diag.py N` | Single diagnostic test |
| `make test-1k` | Full-size single-layer regression |
| `make test-decode` | Prefill(8) + decode(1) |
| `make test-multi` | Multi-layer prefill + decode |
| `HBM_LAT=10 URAM_LAT=2 make test-1k` | Latency sweep |

---

## Future Considerations

### W4A16 Quantization (INT4 Weights, FP16 Activations)
- **What**: Store weights as INT4 in HBM (packed 2/byte), dequantize to FP16 before MAC
- **Why**: 4x reduction in HBM bandwidth for weights — the main bottleneck in LLM inference
- **Method**: AWQ (Activation-Aware Weight Quantization) — best quality at 4-bit, MLSys 2024 Best Paper
- **Implementation**: Add dequant unit between HBM/URAM and MAC inputs: `fp16 = (int4 - zero_point) * scale` per group of 128
- **Impact**: Existing FP16 MAC array unchanged. Only new logic is the dequant front-end
- **Bonus**: Storing INT4 in URAM doubles effective URAM capacity for weight tiles
- **Quality**: ~2-4% perplexity increase vs FP16 — negligible in practice

### Chunk Prefetching
- **What**: Proactive loading of weight/KV tiles from HBM into URAM ahead of computation
- **Double buffering**: Ping-pong URAM banks — Bank A feeds compute while Bank B prefetches next tile from HBM. Swap roles each phase. Hides HBM latency when T_mem < T_comp
- **Tiling**: Partition large weight matrices into tiles that fit URAM. Tile size depends on URAM capacity and systolic array dimensions
- **HBM multi-channel**: Distribute reads across HBM channels (e.g., ch0-9 weights, ch10-19 KV cache) to maximize bandwidth utilization. Use aligned ≥32KB bursts
- **KV cache prefetch**: Liveness-driven — track per-block use counts, prefetch when use_count > 0 and URAM has space, evict when use_count hits 0 (see FAST-Prefill paper)
- **FSM-controlled**: FPGA prefetch is software-scheduled via FSM, not hardware prefetcher. Decouple prefetch FSM from compute via FIFO
- **Key papers**: FlightLLM (double-buffer overlap), FAST-Prefill (liveness-driven KV cache), TerEffic (hybrid URAM/BRAM), GLITCHES (burst merging, 1.2x speedup)

### TurboQuant KV Cache Compression (Google, ICLR 2026)
- **What**: 3-bit KV cache quantization with zero accuracy loss, 6x memory reduction
- **Method**: Two-stage — (1) PolarQuant: random orthogonal rotation concentrates vector distribution, then per-coordinate scalar quantization. (2) QJL: 1-bit residual correction eliminates quantization bias
- **Key property**: Data-oblivious — no calibration or training needed, just deploy
- **Theory**: Distortion only 2.7x from information-theoretic lower bound
- **Hardware fit**: Rotation can use Hadamard transform (additions/subtractions only, no multiplies). Scalar quantization and 1-bit correction are trivial logic
- **Combined with W4A16**: INT4 weights from HBM + 3-bit KV cache = massive effective memory expansion for both weights and context length
- **Paper**: arXiv 2504.19874
