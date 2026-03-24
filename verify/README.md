# Verification Test Suite

## Test Hierarchy

Tests are organized in three tiers. When making changes, work bottom-up:
edit golden first, verify it still produces correct output, then modify RTL to match.

### Tier 1: PyTorch FP32 Reference (Ultimate Ground Truth)

These use PyTorch + transformers to run real GPT-2 and produce the "correct answer."
Requires `python3.11` (which has torch/transformers installed).

| File | What it does | Command |
|------|-------------|---------|
| `fp32_baseline.py` | Runs GPT-2-medium in PyTorch FP32, compares with golden model output | `make test-pytorch` |

### Tier 2: Golden Model (Python, No RTL)

Pure-Python models that match RTL behavior bit-for-bit. These can be run independently
to verify algorithmic correctness before touching RTL. Uses `python3` (numpy only).

| File | What it does | Command |
|------|-------------|---------|
| `test_golden_intacc.py` | Compares FP32 vs integer accumulation golden models | `make test-golden` |
| `golden/matmul_engine.py` | Bit-exact golden matmul (used by cosim) | via `make cosim` |
| `golden/softmax.py` | Bit-exact golden softmax | via `make cosim` |
| `golden/layernorm.py` | Bit-exact golden layernorm | via `make cosim` |
| `golden/activation.py` | Bit-exact golden GELU activation | via `make cosim` |
| `golden/residual_add.py` | Bit-exact golden residual add | via `make cosim` |
| `golden/fp_primitives.py` | FP16/FP32 arithmetic primitives + test vector generation | via `make cosim` |
| `golden/common.py` | Shared fixed-point helpers (clamp, int8/16/32, saturate) | library |

### Tier 3: RTL Co-simulation (Golden vs Verilator)

These compile RTL with Verilator, feed identical inputs to both golden and RTL,
then compare outputs bit-for-bit.

| File | What it does | Command |
|------|-------------|---------|
| `run_cosim.py` | Module-level cosim driver (matmul, softmax, LN, etc.) | `make cosim` |
| `test_top.py` | Full pipeline, small dimensions (SIM_SMALL) | `make test-small` |
| `test_top_1k.py` | Full pipeline, production dimensions (1024), 1 layer | `make test-1k` |
| `test_matmul1k.py` | Matmul-only at production dimensions | `make test-matmul1k` |
| `test_decode_1k.py` | Prefill + decode mode at production dimensions | `make test-decode` |
| `test_multi_layer.py` | Multi-layer (default 2) at production dimensions | `make test-multi` |
| `test_token_cosim.py` | End-to-end: real GPT-2 weights → golden+RTL → token comparison | `make test-token` |

### Supporting Files

| File / Directory | Purpose |
|-----------------|---------|
| `hex_utils.py` | Hex file read/write helpers for cosim data exchange |
| `tb_cosim/` | Verilog testbench wrappers for module-level cosim |
| `test_data/` | Generated hex files consumed by Verilator testbenches |
| `test_top_frontproj.py` | Legacy frontend projection test (pre-FP16) |
| `debug/` | Diagnostic scripts for investigating specific issues |
| `logs/` | Golden/RTL output logs from previous test runs |

## Quick Reference

```bash
# Tier 1: PyTorch reference (needs python3.11)
make test-pytorch                              # FP32 baseline comparison

# Tier 2: Golden-only (no RTL compilation, fast iteration)
make test-golden                               # 2-layer integer accum comparison
make test-golden-24                            # 24-layer full model
make test-golden-1k                            # Full pipeline golden, production dims
make test-golden-multi                         # Multi-layer golden (prefill + decode)
make test-golden-token                         # Real weights golden, 2 layers
make test-golden-token-24                      # Real weights golden, 24 layers

# All tests above support --golden-only flag to skip RTL:
#   python3 verify/test_top_1k.py --golden-only
#   python3 verify/test_multi_layer.py --golden-only
#   python3 verify/test_token_cosim.py --golden-only

# Tier 3: RTL cosim (compiles Verilator, 1-2 layers only)
make cosim                                     # All module-level cosims
make cosim-matmul                              # Matmul module only
make cosim-softmax                             # Softmax module only
make cosim-layernorm                           # LayerNorm module only
make cosim-activation                          # Activation module only
make cosim-residual_add                        # Residual add module only
make cosim-fp-primitives                       # FP16/FP32 primitive ops

make test-small                                # Full pipeline, small dims
make test-1k                                   # Full pipeline, production dims, 1 layer
make test-matmul1k                             # Matmul only, production dims
make test-decode                               # Prefill + decode mode
make test-multi                                # Multi-layer (NUM_LAYERS=2)
make test-token                                # Real weights → token output

# Typical workflow for RTL changes:
# 1. Edit golden model
# 2. make test-golden          → verify golden still correct
# 3. Edit RTL
# 4. make cosim-<module>       → verify RTL matches golden
# 5. make test-1k              → full pipeline sanity check
# 6. make test-multi           → multi-layer regression
```

## Weight Files

Tests expect weight files in `fpga/data/`:
- `weights.bin` — 24 layers, inline biases (787264 words/layer)
- `embed.bin` — Vocabulary + position embeddings + ln_f parameters

Export with: `python3.11 scripts/export_gpt2.py --model gpt2-medium --output-dir fpga/data`
