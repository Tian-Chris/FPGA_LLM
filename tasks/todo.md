# FPGA LLM — Task Tracker

## Completed

### Task A: RTL Fixes
- [x] A1. Connect URAM `clear` signal to FSM (pulse on `start`)
- [x] A2. Add configurable right-shift to matmul_engine accumulator output
- [x] A3. Skip S_OUTPUT_COPY — S_NEXT_STEP goes directly to S_DONE

### Task B: Full-Sized GPT-2 Co-Simulation
- [x] B0. K-chunk accumulation + URAM accum mode
- [x] B0a. ReLU 16-bit dim overflow — row-by-row S_ACT_RUN
- [x] B0b. `make test-small` ALL CHECKS PASSED
- [x] B0c. `make test-1k` ALL CHECKS PASSED
- [x] B1. Multi-layer prefill test — `make test-multi` ALL CHECKS PASSED (2, 3, and 24 layers)
- [x] B2. DMA mirror bug fix in testbenches
- [ ] B4. Multi-layer decode test — `NUM_LAYERS=2 make test-multi` (prefill + 2 decode tokens)
  - L0 prefill/dec1/dec2 all pass, L1 prefill/dec2 pass
  - **BUG**: L1_K_dec1 & L1_V_dec1 mismatch — FSM flush writes K to row cache_len_r but comparison reads row BT
  - Debugging: off-by-one in flush address vs golden comparison address

---

## ► Active: Full GPT-2 Token Co-Simulation

End-to-end: real GPT-2 weights → N-layer RTL → ln_f + unembed + argmax → token ID → compare to PyTorch reference.

Final layers (ln_f + unembed + argmax) run on CPU (host.cpp pattern):
- RTL INT16 res2 → cast to float (no scale) → ln_f (FP32, eps=1e-5) → wte^T matmul (FP32) → argmax

- [x] E1. Load real GPT-2 weights (quantized INT8 for RTL, FP32 for ln_f/unembed)
- [x] E2. Add ln_f + unembed + argmax to Python golden model
- [x] E3. Apply same pipeline to RTL final res2 output
- [x] E4. Compare token IDs (RTL vs golden) — `make test-token` ALL TOKENS MATCH (2 layers)
- [ ] E5. Scale to NUM_LAYERS=24 (full GPT-2 medium, ~19M HBM words)
- [ ] E6. Multi-token autoregressive decode loop

---

## Backlog

### Task B (remaining)
- [x] B3. Fix decode mode attention mismatches — one-shot `_sent` flags in FSM (was: alternating start signals caused softmax double-fire)

### Task C: host.cpp Fixes
- [ ] C1. Read prefill output from ACT_EMBED via partial FROM_DEVICE sync
- [ ] C2. Read decode output from ACT_EMBED via partial FROM_DEVICE sync
- [ ] C3. Decode loop: full TO_DEVICE sync (XRT partial sync broken on U280)
- [ ] C4. Remove stale output buffer debug dumps

### Task D: Resynthesize & FPGA Test
- [ ] D1. Resynth with URAM clear + matmul shift fixes
- [ ] D2. Test on FPGA: deterministic output (same input → same output)
- [ ] D3. Test on FPGA: meaningful text generation (not saturated garbage)
- [ ] D4. Test decode loop: multiple tokens without hang

---

## Test Commands Reference

| Command | Description |
|---------|-------------|
| `make cosim` | Unit-level co-sim: matmul, softmax, layernorm, activation, residual_add |
| `make test-small` | Single-layer sim with SIM_SMALL params (MODEL_DIM=32) |
| `make test-1k` | Single-layer sim with full-size params (MODEL_DIM=1024) |
| `make test-decode` | Single-layer prefill(8) + decode(1) verification |
| `make test-multi` | Multi-layer prefill (default NUM_LAYERS=24) |
| `NUM_LAYERS=2 make test-multi` | 2-layer prefill + 2 decode tokens (~3 min) |
| `NUM_LAYERS=24 make test-multi` | Full 24-layer prefill + 2 decode tokens (~15 min) |
| `make test-token` | End-to-end token prediction (real GPT-2 weights → token ID) |

**Latency sweep**: `HBM_LAT=10 URAM_LAT=2 make test-1k` (override HBM/URAM read latency)

---

## Future
- Chunked Prefill
- Use DDR
