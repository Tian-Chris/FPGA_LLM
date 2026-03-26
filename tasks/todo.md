# FPGA Diagnostic Test Strategy

## Problem
Simulation passes perfectly but FPGA produces wrong results (near-zero correlation with golden across ALL activation regions). Need systematic first-principles validation.

## What We Know
- **Works**: HBM read/write (embeddings + first weight word verified), kernel completes, activation buffer has non-zero data, simulation passes all 15 steps (>0.999 correlation)
- **Broken**: LN1 output (step 0) already wrong, V(KV) completely zero, K(KV) negative correlation, URAM debug flush reads ALL zeros, values ~6-15x too large

## Top Hypotheses
1. **URAM read latency mismatch**: 67 Mbit → ~64 URAMs cascaded. Vivado may add cycles. RTL assumes RD_LATENCY=1.
2. **Unknown sim-vs-synthesis behavioral difference**

---

## Phase 1: Diagnostic Test Kernel — COMPLETE

### RTL Changes (all verified in simulation)
- [x] `defines.vh`: Added 7 test state constants (S_TEST_DISPATCH..S_TEST_REG_CHK)
- [x] `vitis_control.v`: Added max_steps (0x70) + test_mode (0x78) registers
- [x] `host_interface.v`: Added matching registers at 0x30/0x34
- [x] `top_level.v`: Wired new signals, added test_active mux for nm_adapter + act_dma
- [x] `fsm_controller.v`: All test states implemented, max_steps check in S_NEXT_STEP
- [x] `tb/tb_top_diag.v`: Testbench for diagnostic modes
- [x] `verify/test_diag.py`: Python verification (builds + runs + checks all tests)
- [x] `Makefile`: `test-diag` target added

### Test Results (all pass in sim)
- [x] test_mode=12: Register readback — PASS
- [x] test_mode=1:  HBM echo pattern — PASS
- [x] test_mode=5:  URAM write + flush — PASS
- [x] test_mode=6:  URAM latency probe — PASS (measured=2 = RD_LATENCY(1)+1 for NBA)
- [x] test_mode=7:  Multi-row URAM — PASS

### Bug Found & Fixed
- `top_level.v` test_active mux was missing `fsm_nm_addr_offset` addition on test write addresses (nm_adapter always wrote to row 0)

## Phase 1B: Regression
- [ ] `make test-1k` still passes (running)
- [ ] `make test-decode` still passes

## Phase 2: FPGA Build + Run Diagnostics
- [ ] Build: `make package && make link-prod` on server
- [ ] Run test_mode=12: verify register plumbing
- [ ] Run test_mode=1: verify HBM write path
- [ ] Run test_mode=5: verify URAM write+flush
- [ ] Run test_mode=6: **KEY TEST** — measure actual URAM read latency on hardware
- [ ] Run test_mode=7: verify URAM cascade addressing
- [ ] Host test program: needs `--test` CLI mode in host.cpp

## Phase 3: Step-by-Step Golden Comparison (after Phase 2)
Using max_steps:
- [ ] max_steps=1 (LN1), compare act buffer against golden LN1 output
- [ ] If wrong: check LN param loading
- [ ] If correct: increment until mismatch appears

## Phase 4: Fix and Verify
- If URAM latency: override URAM_RD_LATENCY in fpga_kernel.v, rebuild
- If computation: targeted fix based on which step diverges

---

## Test Commands Reference

| Command | Description |
|---------|-------------|
| `make test-diag` | All diagnostic tests (builds 5 sims) |
| `python3 verify/test_diag.py 6` | Single diagnostic test |
| `make test-1k` | Full-size single-layer regression |
| `make test-decode` | Prefill(8) + decode(1) |
| `make test-multi` | Multi-layer prefill + decode |
| `HBM_LAT=10 URAM_LAT=2 make test-1k` | Latency sweep |
