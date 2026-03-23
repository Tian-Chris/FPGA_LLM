#!/usr/bin/env python3
"""Production-scale 1024x1024 single matmul test.

Generates random INT8 weights (W_q) and INT8 embeddings (1024x1024),
computes golden Q = tiled_matmul_int8(embed, W_q), packs HBM hex files,
compiles and runs the RTL simulation (no -DSIM_SMALL, SINGLE_MATMUL=1),
then compares RTL dump output against the golden model.

Address layout:
  weight_base = 0         -> W_q: addresses 0..65535 (1024 rows x 64 words, stride=64)
  act_base    = 65536     -> embed: addresses 65536..131071 (1024 rows x 64 words)
  flush dest  = 73728     -> Q output: act_base + ACT_Q_OFFSET (65536 + 8192)
  SIM_HBM_DEPTH = 262144  (2^18)
"""

import os
import sys
import random
import subprocess
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.golden.common import int8, int16, int32, saturate_int16

# Import reusable functions from test_top.py
from verify.test_top import (
    pack_int16_to_256bit, pack_int8_to_256bit_as_int16,
    write_hex_file, pack_matrix_int8_as_int16, pack_matrix_int16,
    read_hex_dump, extract_int16_from_256bit,
    extract_matrix_from_hbm, extract_matrix_from_uram,
    compare_matrices, hex16,
)

# ---------------------------------------------------------------------------
# Production Parameters (must match defines.vh without SIM_SMALL)
# ---------------------------------------------------------------------------
MODEL_DIM     = 1024
TILE_SIZE     = 32
NUM_ENGINES   = 6
MAX_SEQ_LEN   = 128

DATA_W = 16
BUS_ELEMS = 16       # 256 / 16
WE = BUS_ELEMS

# URAM params for production (only MODEL_DIM cols used for this matmul)
URAM_ROWS      = 1024
URAM_COL_WORDS = MODEL_DIM // BUS_ELEMS  # 64

# HBM address layout
MODEL_STRIDE = MODEL_DIM // WE   # 64 words per row
WEIGHT_BASE  = 0
ACT_BASE     = 65536              # W_q occupies 0..65535

# ACT_Q_OFFSET from fsm_controller.v
ACT_Q_OFFSET = MAX_SEQ_LEN * MODEL_DIM // WE  # 128 * 1024 / 16 = 8192
FLUSH_BASE   = ACT_BASE + ACT_Q_OFFSET         # 73728

SIM_HBM_DEPTH = 262144  # 2^18

SEED = 42

# Directories
TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
RTL_DIR       = os.path.join(PROJECT_ROOT, "rtl")
TB_DIR        = os.path.join(PROJECT_ROOT, "tb")
OBJ_DIR       = os.path.join(PROJECT_ROOT, "obj_dir")

RTL_ALL = [
    "bram_controller.v", "mac_unit.v", "agu.v", "matmul_engine.v",
    "mem_arbiter.v", "tiling_engine.v", "softmax.v", "layernorm.v",
    "activation.v", "residual_add.v", "quant_layer.v", "host_interface.v",
    "positional_embedding.v", "fsm_controller.v", "sim_hbm.v",
    "debug_writer.v",
    "uram_accum_buf.v", "tile_loader.v", "uram_flush.v", "act_dma.v",
    "uram_nm_adapter.v", "top_level.v",
]


# ---------------------------------------------------------------------------
# Numpy-Accelerated Tiled Matmul (bit-exact with RTL)
# ---------------------------------------------------------------------------

def tiled_matmul_int8_numpy(mat_a_int8, mat_b_int8, tile_size):
    """Numpy-accelerated tiled matmul matching RTL behavior exactly.

    Per tile: INT8 inputs sign-extended to INT16, INT32 accumulation across
    full K dimension, then saturate to INT16. This matches the RTL's
    matmul_engine which accumulates across all K-tiles before output.

    Values are small enough (max ~8192 per element) that INT32 never overflows,
    so we can use numpy matmul directly in INT32.
    """
    A = np.array(mat_a_int8, dtype=np.int8).astype(np.int32)
    B = np.array(mat_b_int8, dtype=np.int8).astype(np.int32)
    M, K = A.shape
    _, N = B.shape

    result = np.zeros((M, N), dtype=np.int16)

    for ti in range(0, M, tile_size):
        te = min(ti + tile_size, M)
        for tj in range(0, N, tile_size):
            je = min(tj + tile_size, N)
            # Full K accumulation in INT32 via matmul
            acc = A[ti:te, :] @ B[:, tj:je]
            # Saturate to INT16
            result[ti:te, tj:je] = np.clip(acc, -32768, 32767).astype(np.int16)

    return result.tolist()


# ---------------------------------------------------------------------------
# Generate Data
# ---------------------------------------------------------------------------

def generate_data(seed=42):
    """Generate random INT8 weight matrix W_q and INT8 embeddings, both 1024x1024."""
    rng = random.Random(seed)

    W_q = [[rng.randint(-4, 3) for _ in range(MODEL_DIM)] for _ in range(MODEL_DIM)]

    rng2 = random.Random(seed + 2)
    embed = [[rng2.randint(-2, 1) for _ in range(MODEL_DIM)] for _ in range(MODEL_DIM)]

    return W_q, embed


# ---------------------------------------------------------------------------
# HBM Hex File Generation
# ---------------------------------------------------------------------------

def generate_hex_files(W_q, embed):
    """Generate hex files for testbench $readmemh preloading."""
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    # Weight HBM: W_q at address 0, stride=MODEL_STRIDE
    wgt_mem = {}
    pack_matrix_int8_as_int16(W_q, MODEL_DIM, MODEL_DIM,
                              WEIGHT_BASE, MODEL_STRIDE, wgt_mem)
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_wgt_1k.hex"),
                   [wgt_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # Activation HBM: embeddings at ACT_BASE, stride=MODEL_STRIDE
    act_mem = {}
    embed_int16 = [[int16(int8(v)) for v in row] for row in embed]
    pack_matrix_int16(embed_int16, MODEL_DIM, MODEL_DIM,
                      ACT_BASE, MODEL_STRIDE, act_mem)
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_act_1k.hex"),
                   [act_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    print(f"  HBM hex files written to {TEST_DATA_DIR}/hbm_{{wgt,act}}_1k.hex")


# ---------------------------------------------------------------------------
# Compile & Run
# ---------------------------------------------------------------------------

def compile_design():
    """Compile with Verilator using production flags (no SIM_SMALL)."""
    tb_path = os.path.join(TB_DIR, "tb_top_matmul1k.v")
    rtl_paths = [os.path.join(RTL_DIR, f) for f in RTL_ALL]
    verilator_f = os.path.join(PROJECT_ROOT, "scripts", "verilator_prod.f")

    cmd = (["verilator", "--binary", "-f", verilator_f, tb_path]
           + rtl_paths + ["--top-module", "tb_top_matmul1k"])

    print("  Compiling with Verilator (production, no SIM_SMALL)...")
    result = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  COMPILE FAILED:\n{result.stderr[:5000]}")
        return False
    print("  Compilation OK.")
    return True


def run_simulation():
    """Run the compiled simulation."""
    binary = os.path.join(OBJ_DIR, "Vtb_top_matmul1k")
    if not os.path.exists(binary):
        print(f"  ERROR: binary not found: {binary}")
        return False

    print("  Running simulation...")
    try:
        result = subprocess.run([binary], cwd=PROJECT_ROOT,
                                capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        print("  FAIL: Simulation timed out (300s)")
        return False

    for line in result.stdout.splitlines():
        print(f"    {line}")

    if "TEST PASSED" not in result.stdout:
        print("  FAIL: TEST PASSED not in simulation output")
        if result.stderr:
            print(f"  stderr: {result.stderr[:2000]}")
        return False
    return True


# ---------------------------------------------------------------------------
# RTL Dump Comparison
# ---------------------------------------------------------------------------

def compare_rtl_output(golden_Q):
    """Read RTL dumps and compare against golden model."""
    uram_path  = os.path.join(TEST_DATA_DIR, "uram_1k_dump.hex")
    flush_path = os.path.join(TEST_DATA_DIR, "hbm_flush_1k_dump.hex")

    if not os.path.exists(flush_path):
        print("  ERROR: flush dump file not found")
        return False

    flush_words = read_hex_dump(flush_path)

    total_ok = total_mis = 0

    # Check Q output in flush HBM at FLUSH_BASE
    print("\n  --- Flush HBM: Q at address %d ---" % FLUSH_BASE)
    rtl_Q_flush = extract_matrix_from_hbm(
        flush_words, FLUSH_BASE, MODEL_DIM, MODEL_STRIDE, MODEL_DIM)

    class DummyFile:
        def __init__(self): self.lines = []
        def write(self, s): self.lines.append(s)

    f_out = DummyFile()
    ok, mis = compare_matrices(golden_Q, rtl_Q_flush, 'Q_flush', f_out)
    total_ok += ok
    total_mis += mis
    for line in f_out.lines:
        print(f"  {line}", end='')

    # Also check URAM dump if available
    if os.path.exists(uram_path):
        uram_words = read_hex_dump(uram_path)
        print("\n  --- URAM: Q (should match) ---")
        rtl_Q_uram = extract_matrix_from_uram(
            uram_words, 0, MODEL_DIM, URAM_COL_WORDS, URAM_COL_WORDS)
        f_out2 = DummyFile()
        ok, mis = compare_matrices(golden_Q, rtl_Q_uram, 'Q_uram', f_out2)
        total_ok += ok
        total_mis += mis
        for line in f_out2.lines:
            print(f"  {line}", end='')

    total = total_ok + total_mis
    print(f"\n  SUMMARY: {total_ok}/{total} elements match")
    if total_mis == 0:
        print("  ALL CHECKS PASSED")
        return True
    else:
        print(f"  MISMATCHES: {total_mis} element(s) differ")
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    data_only = '--data-only' in sys.argv

    print("=" * 60)
    print("  Production-Scale 1024x1024 Single Matmul Test")
    print(f"  MODEL_DIM={MODEL_DIM}, TILE_SIZE={TILE_SIZE}, NUM_ENGINES={NUM_ENGINES}")
    print(f"  WEIGHT_BASE={WEIGHT_BASE}, ACT_BASE={ACT_BASE}, FLUSH_BASE={FLUSH_BASE}")
    print(f"  SIM_HBM_DEPTH={SIM_HBM_DEPTH}")
    print("=" * 60)

    # Generate data
    W_q, embed = generate_data(seed=SEED)

    # Run golden model (numpy-accelerated, bit-exact with RTL)
    print("\n  Running golden model (1024x1024 tiled matmul, numpy)...")
    golden_Q = tiled_matmul_int8_numpy(embed, W_q, TILE_SIZE)
    print(f"  Golden Q computed: {len(golden_Q)}x{len(golden_Q[0])}")

    # Generate hex files
    print("  Generating HBM hex files...")
    generate_hex_files(W_q, embed)

    if data_only:
        print("\n  --data-only: skipping compile/run")
        return

    # Compile
    if not compile_design():
        sys.exit(1)

    # Run
    if not run_simulation():
        sys.exit(1)

    # Compare
    passed = compare_rtl_output(golden_Q)
    if not passed:
        sys.exit(1)

    print("\nDone.")


if __name__ == "__main__":
    main()
