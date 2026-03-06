#!/usr/bin/env python3
"""Production-scale full pipeline test: GPT-2 pre-norm at MODEL_DIM=1024.

Exercises the complete pipeline (LN1 -> QKV -> attention -> proj -> res1 ->
LN2 -> FFN1 -> act -> FFN2 -> res2) at production dimensions:
  MODEL_DIM=1024, F_DIM=4096, NUM_HEADS=16, NUM_ENGINES=6, TILE_SIZE=32

Key differences from test_top.py (SIM_SMALL):
  - Numpy-accelerated INT16 tiled matmul for speed
  - 6 engines, URAM stride=256, HBM depth=2^20
  - 16-head attention with HEAD_DIM=64
  - SEQ_LEN=32 to keep sim time manageable
"""

import math
import os
import sys
import random
import subprocess
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.golden.common import int8, int16, int32, saturate_int16
from verify.golden.softmax import softmax_golden
from verify.golden.layernorm import layernorm_golden
from verify.golden.activation import relu_golden
from verify.golden.residual_add import residual_add_golden

# Import reusable hex packing/extraction functions from test_top.py
from verify.test_top import (
    pack_int16_to_256bit, pack_int8_to_256bit_as_int16,
    write_hex_file, pack_matrix_int8_as_int16, pack_matrix_int16,
    pack_ln_params,
    read_hex_dump, extract_int16_from_256bit,
    extract_matrix_from_hbm, extract_matrix_from_uram,
    compare_matrices, hex16,
)

# ---------------------------------------------------------------------------
# Production Parameters (must match defines.vh without SIM_SMALL)
# ---------------------------------------------------------------------------
MODEL_DIM     = 1024
NUM_HEADS     = 16
HEAD_DIM      = MODEL_DIM // NUM_HEADS   # 64
SCALE_SHIFT   = math.ceil(math.log2(HEAD_DIM)) >> 1  # $clog2(64) >> 1 = 3
F_DIM         = 4096
INPUT_DIM     = 64
MAX_SEQ_LEN   = 128
MAX_BATCH     = 1
TILE_SIZE     = 32
NUM_ENGINES   = 6

SEQ_LEN = 32
BATCH   = 1
BT      = BATCH * SEQ_LEN   # 32

DATA_W = 16
BUS_ELEMS = 16       # 256 / 16
URAM_ROWS = 1024
URAM_COLS = 4096
URAM_COL_WORDS = URAM_COLS // BUS_ELEMS  # 256

SIM_HBM_DEPTH = 1048576  # 2^20

SEED = 42

# ---------------------------------------------------------------------------
# HBM Memory Layout (word-addressed, 256-bit words)
# Must match fsm_controller.v localparams for production
# ---------------------------------------------------------------------------
WE = BUS_ELEMS  # 16

# Per-layer weight offsets (in 256-bit words)
LAYER_WQ_OFFSET   = 0                                              # 0
LAYER_WK_OFFSET   = MODEL_DIM * MODEL_DIM // WE                    # 65536
LAYER_WV_OFFSET   = 2 * MODEL_DIM * MODEL_DIM // WE                # 131072
LAYER_WO_OFFSET   = 3 * MODEL_DIM * MODEL_DIM // WE                # 196608
LAYER_FFN1_OFFSET = 4 * MODEL_DIM * MODEL_DIM // WE                # 262144
LAYER_FFN2_OFFSET = LAYER_FFN1_OFFSET + MODEL_DIM * F_DIM // WE    # 524288
LAYER_LN1_OFFSET  = LAYER_FFN2_OFFSET + F_DIM * MODEL_DIM // WE    # 786432
LAYER_LN2_OFFSET  = LAYER_LN1_OFFSET + 2 * MODEL_DIM // WE         # 786560
LAYER_SIZE        = LAYER_LN2_OFFSET + 2 * MODEL_DIM // WE          # 786688

# Strides (in 256-bit words)
MODEL_STRIDE = MODEL_DIM // WE   # 64
F_STRIDE     = F_DIM // WE       # 256

# Base addresses
WEIGHT_BASE = 0
ACT_BASE    = LAYER_SIZE   # 786688

# Activation offsets (in 256-bit words from ACT_BASE)
ACT_EMBED_OFFSET = 0
ACT_Q_OFFSET     = MAX_SEQ_LEN * MODEL_DIM // WE      # 8192
ACT_K_OFFSET     = 2 * MAX_SEQ_LEN * MODEL_DIM // WE  # 16384
ACT_V_OFFSET     = 3 * MAX_SEQ_LEN * MODEL_DIM // WE  # 24576
ACT_ATTN_OFFSET  = 4 * MAX_SEQ_LEN * MODEL_DIM // WE  # 32768
ACT_TEMP_OFFSET  = 5 * MAX_SEQ_LEN * MODEL_DIM // WE  # 40960
ACT_FFN_OFFSET   = 0

# Directories
TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
RTL_DIR       = os.path.join(PROJECT_ROOT, "rtl")
TB_DIR        = os.path.join(PROJECT_ROOT, "tb")
OBJ_DIR       = os.path.join(PROJECT_ROOT, "obj_dir")

GOLDEN_OUT = os.path.join(PROJECT_ROOT, "verify", "llm_golden_1k.txt")
RTL_OUT    = os.path.join(PROJECT_ROOT, "verify", "llm_rtl_1k.txt")

RTL_ALL = [
    "bram_controller.v", "mac_unit.v", "agu.v", "matmul_engine.v",
    "mem_arbiter.v", "tiling_engine.v", "softmax.v", "layernorm.v",
    "activation.v", "residual_add.v", "quant_layer.v", "host_interface.v",
    "positional_embedding.v", "fsm_controller.v", "sim_hbm_port.v",
    "uram_accum_buf.v", "tile_loader.v", "uram_flush.v", "act_dma.v",
    "uram_nm_adapter.v", "top_level.v",
]


# ---------------------------------------------------------------------------
# Numpy-Accelerated Tiled Matmul (bit-exact with RTL)
# ---------------------------------------------------------------------------

def _to_int16_array(mat):
    """Convert 2D list of Python ints to np.int32 array with INT16 semantics.

    Handles both signed (-4) and unsigned (65532) representations of INT16.
    """
    arr = np.array(mat, dtype=np.int64)
    # Mask to 16 bits, then sign-extend
    arr = arr & 0xFFFF
    arr = np.where(arr >= 0x8000, arr - 0x10000, arr)
    return arr.astype(np.int32)


def tiled_matmul_int16_numpy(mat_a, mat_b, tile_size):
    """Numpy-accelerated tiled matmul with INT16 inputs.

    Per tile: INT16 x INT16 -> INT32 accumulation across full K dimension,
    then saturate to INT16. This matches the RTL's matmul_engine.

    Input: 2D lists of INT16 values (signed or unsigned representation).
    Returns: list-of-lists with signed INT16 values.
    """
    A = _to_int16_array(mat_a)
    B = _to_int16_array(mat_b)
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

    # Return as signed Python ints (consistent with matmul_golden)
    return result.astype(int).tolist()


def _transpose(mat):
    rows = len(mat)
    cols = len(mat[0])
    return [[mat[r][c] for r in range(rows)] for c in range(cols)]


# ---------------------------------------------------------------------------
# Weight Generation
# ---------------------------------------------------------------------------

def generate_weights(seed=42):
    """Generate INT8 weights for one encoder layer.

    Use small range [-4, 3] to avoid INT32 overflow during accumulation.
    Must consume RNG state in the same order as test_top.py for seed compatibility.
    """
    rng = random.Random(seed)

    def rand_mat(rows, cols):
        return [[rng.randint(-4, 3) for _ in range(cols)] for _ in range(rows)]

    def rand_vec(dim):
        return [rng.randint(-4, 3) for _ in range(dim)]

    w = {}
    # Frontend projection (consumes RNG state, same as test_top.py)
    w['W_proj'] = rand_mat(INPUT_DIM, MODEL_DIM)

    # Encoder layer 0
    w['W_q']    = rand_mat(MODEL_DIM, MODEL_DIM)
    w['W_k']    = rand_mat(MODEL_DIM, MODEL_DIM)
    w['W_v']    = rand_mat(MODEL_DIM, MODEL_DIM)
    w['W_o']    = rand_mat(MODEL_DIM, MODEL_DIM)
    w['W_ffn1'] = rand_mat(MODEL_DIM, F_DIM)
    w['W_ffn2'] = rand_mat(F_DIM, MODEL_DIM)
    w['gamma1'] = rand_vec(MODEL_DIM)
    w['beta1']  = rand_vec(MODEL_DIM)
    w['gamma2'] = rand_vec(MODEL_DIM)
    w['beta2']  = rand_vec(MODEL_DIM)

    return w


# ---------------------------------------------------------------------------
# Golden Model (Production-Scale Full Pipeline)
# ---------------------------------------------------------------------------

def compute_golden(embed_int8, weights):
    """Run the full encoder layer golden model for GPT-2 pre-norm architecture.

    GPT-2 Pre-Norm ordering:
      LN1 -> QKV -> attention -> proj -> residual1 -> LN2 -> FFN1 -> act -> FFN2 -> residual2
    """
    g = {}
    g['embed_int8'] = embed_int8

    # Embed stored as INT16 in HBM (sign-extended from INT8)
    embed_int16 = [[int16(int8(v)) for v in row] for row in embed_int8]
    g['embed_int16'] = embed_int16

    # ------------------------------------------------------------------
    # Step 0: LN1 (reads embeddings from URAM, params from LN1 weights)
    # ------------------------------------------------------------------
    print("    LN1...")
    ln1_out = []
    for t in range(BT):
        normed = layernorm_golden(
            embed_int16[t], weights['gamma1'], weights['beta1'], MODEL_DIM
        )
        ln1_out.append(normed)
    g['ln1_out'] = ln1_out

    # ------------------------------------------------------------------
    # Step 2: QKV projections (read from ACT_TEMP = ln1_out)
    # ------------------------------------------------------------------
    print("    QKV matmuls...")
    Q = tiled_matmul_int16_numpy(ln1_out, weights['W_q'], TILE_SIZE)
    K = tiled_matmul_int16_numpy(ln1_out, weights['W_k'], TILE_SIZE)
    V = tiled_matmul_int16_numpy(ln1_out, weights['W_v'], TILE_SIZE)
    g['Q'] = Q
    g['K'] = K
    g['V'] = V

    # ------------------------------------------------------------------
    # Step 3: Multi-head attention (16 heads, HEAD_DIM=64)
    # ------------------------------------------------------------------
    print("    Attention (16 heads)...")
    attn_concat = [[0] * MODEL_DIM for _ in range(BT)]
    all_scores = []
    all_probs  = []

    for h in range(NUM_HEADS):
        Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q]
        K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K]
        V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V]

        K_h_T = _transpose(K_h)
        scores_h = tiled_matmul_int16_numpy(Q_h, K_h_T, TILE_SIZE)

        probs_h = [softmax_golden(scores_h[t], scale_shift=SCALE_SHIFT, row_idx=t)
                   for t in range(BT)]

        attn_h = tiled_matmul_int16_numpy(probs_h, V_h, TILE_SIZE)

        for t in range(BT):
            for d in range(HEAD_DIM):
                attn_concat[t][h*HEAD_DIM + d] = attn_h[t][d]

        all_scores.append(scores_h)
        all_probs.append(probs_h)

    g['scores'] = all_scores[0]
    g['probs_uint16'] = all_probs[0]
    g['attn_out'] = attn_concat

    # ------------------------------------------------------------------
    # Step 4: Output projection
    # ------------------------------------------------------------------
    print("    Output projection...")
    attn_proj = tiled_matmul_int16_numpy(attn_concat, weights['W_o'], TILE_SIZE)
    g['attn_proj'] = attn_proj

    # ------------------------------------------------------------------
    # Step 5: Residual1 = proj + original embeddings
    # ------------------------------------------------------------------
    print("    Residual 1...")
    residual1 = [residual_add_golden(embed_int16[t], attn_proj[t]) for t in range(BT)]
    g['residual1'] = residual1

    # ------------------------------------------------------------------
    # Step 7: LN2 (reads residual1 from URAM, params from LN2 weights)
    # ------------------------------------------------------------------
    print("    LN2...")
    ln2_out = []
    for t in range(BT):
        normed = layernorm_golden(
            residual1[t], weights['gamma2'], weights['beta2'], MODEL_DIM
        )
        ln2_out.append(normed)
    g['ln2_out'] = ln2_out

    # ------------------------------------------------------------------
    # Step 9: FFN1 (read from ACT_TEMP = ln2_out)
    # ------------------------------------------------------------------
    print("    FFN1 (1024x4096)...")
    ffn1 = tiled_matmul_int16_numpy(ln2_out, weights['W_ffn1'], TILE_SIZE)
    g['ffn1'] = ffn1

    # ------------------------------------------------------------------
    # Step 10: ReLU
    # ------------------------------------------------------------------
    print("    ReLU...")
    ffn_act = [[relu_golden(v) for v in row] for row in ffn1]
    g['ffn_act'] = ffn_act

    # ------------------------------------------------------------------
    # Step 12: FFN2
    # ------------------------------------------------------------------
    print("    FFN2 (4096x1024)...")
    ffn2 = tiled_matmul_int16_numpy(ffn_act, weights['W_ffn2'], TILE_SIZE)
    g['ffn2'] = ffn2

    # ------------------------------------------------------------------
    # Step 13: Residual2 = ffn2 + original embeddings
    # ------------------------------------------------------------------
    print("    Residual 2...")
    residual2 = [residual_add_golden(embed_int16[t], ffn2[t]) for t in range(BT)]
    g['residual2'] = residual2

    return g


# ---------------------------------------------------------------------------
# HBM Hex File Generation
# ---------------------------------------------------------------------------

def generate_hex_files(weights, embed_int8):
    """Generate hex files for testbench $readmemh preloading."""
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    # Weight HBM: INT8 weights sign-extended to INT16
    print("    Packing weight HBM...")
    wgt_mem = {}

    pack_matrix_int8_as_int16(weights['W_q'], MODEL_DIM, MODEL_DIM,
                              WEIGHT_BASE + LAYER_WQ_OFFSET, MODEL_STRIDE, wgt_mem)
    pack_matrix_int8_as_int16(weights['W_k'], MODEL_DIM, MODEL_DIM,
                              WEIGHT_BASE + LAYER_WK_OFFSET, MODEL_STRIDE, wgt_mem)
    pack_matrix_int8_as_int16(weights['W_v'], MODEL_DIM, MODEL_DIM,
                              WEIGHT_BASE + LAYER_WV_OFFSET, MODEL_STRIDE, wgt_mem)
    pack_matrix_int8_as_int16(weights['W_o'], MODEL_DIM, MODEL_DIM,
                              WEIGHT_BASE + LAYER_WO_OFFSET, MODEL_STRIDE, wgt_mem)
    pack_matrix_int8_as_int16(weights['W_ffn1'], MODEL_DIM, F_DIM,
                              WEIGHT_BASE + LAYER_FFN1_OFFSET, F_STRIDE, wgt_mem)
    pack_matrix_int8_as_int16(weights['W_ffn2'], F_DIM, MODEL_DIM,
                              WEIGHT_BASE + LAYER_FFN2_OFFSET, MODEL_STRIDE, wgt_mem)

    # LN params
    pack_ln_params(weights['gamma1'], weights['beta1'],
                   WEIGHT_BASE + LAYER_LN1_OFFSET, wgt_mem)
    pack_ln_params(weights['gamma2'], weights['beta2'],
                   WEIGHT_BASE + LAYER_LN2_OFFSET, wgt_mem)

    print("    Writing weight hex file...")
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_wgt_1k_full.hex"),
                   [wgt_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # Activation HBM: INT8 embeddings sign-extended to INT16
    print("    Packing activation HBM...")
    act_mem = {}
    embed_int16 = [[int16(int8(v)) for v in row] for row in embed_int8]
    pack_matrix_int16(embed_int16, BT, MODEL_DIM,
                      ACT_BASE + ACT_EMBED_OFFSET, MODEL_STRIDE, act_mem)

    print("    Writing activation hex file...")
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_act_1k_full.hex"),
                   [act_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # DMA HBM: LN params + embeddings (for residual add reads)
    print("    Packing DMA HBM...")
    dma_mem = {}

    pack_ln_params(weights['gamma1'], weights['beta1'],
                   WEIGHT_BASE + LAYER_LN1_OFFSET, dma_mem)
    pack_ln_params(weights['gamma2'], weights['beta2'],
                   WEIGHT_BASE + LAYER_LN2_OFFSET, dma_mem)

    pack_matrix_int16(embed_int16, BT, MODEL_DIM,
                      ACT_BASE + ACT_EMBED_OFFSET, MODEL_STRIDE, dma_mem)

    print("    Writing DMA hex file...")
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_dma_1k_full.hex"),
                   [dma_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    print(f"  HBM hex files written to {TEST_DATA_DIR}/hbm_{{wgt,act,dma}}_1k_full.hex")


# ---------------------------------------------------------------------------
# Golden File Writer
# ---------------------------------------------------------------------------

def write_golden(g):
    """Write golden intermediate values to text file (summary only for 1024)."""
    with open(GOLDEN_OUT, 'w') as f:
        f.write("=" * 60 + "\n")
        f.write("PRODUCTION 1K INTEGRATION TEST - GOLDEN REFERENCE (GPT-2 Pre-Norm)\n")
        f.write("=" * 60 + "\n")
        f.write(f"Config: BT={BT}, MODEL_DIM={MODEL_DIM}, F_DIM={F_DIM}, "
                f"NUM_HEADS={NUM_HEADS}, HEAD_DIM={HEAD_DIM}\n")
        f.write(f"WEIGHT_BASE={WEIGHT_BASE}, ACT_BASE={ACT_BASE}\n")
        f.write(f"LAYER_SIZE={LAYER_SIZE}\n\n")

        # Write only first 4 rows of each stage (1024 cols is too wide for full dump)
        def write_mat_summary(name, mat, max_rows=4, max_cols=32):
            rows = len(mat)
            cols = len(mat[0])
            f.write(f"  {name}  [{rows}x{cols}]\n")
            for i in range(min(max_rows, rows)):
                vals = "  ".join(hex16(v) for v in mat[i][:max_cols])
                suffix = " ..." if cols > max_cols else ""
                f.write(f"    row[{i}]: {vals}{suffix}\n")
            if rows > max_rows:
                f.write(f"    ... ({rows - max_rows} more rows)\n")

        for stage, name in [
            ('embed_int16', 'Input embeddings (INT16)'),
            ('ln1_out', 'LN1 output'),
            ('Q', 'Q projection'),
            ('K', 'K projection'),
            ('V', 'V projection'),
            ('attn_out', 'Attention output'),
            ('attn_proj', 'Output projection'),
            ('residual1', 'Residual 1'),
            ('ln2_out', 'LN2 output'),
            ('ffn1', 'FFN1 output'),
            ('ffn_act', 'ReLU output'),
            ('ffn2', 'FFN2 output'),
            ('residual2', 'Residual 2'),
        ]:
            f.write(f"\n--- {name} ---\n")
            write_mat_summary(stage, g[stage])

    print(f"  Golden written: {GOLDEN_OUT}")


# ---------------------------------------------------------------------------
# Compile & Run
# ---------------------------------------------------------------------------

def compile_design():
    """Compile with Verilator using production 1K flags."""
    tb_path = os.path.join(TB_DIR, "tb_top_1k.v")
    rtl_paths = [os.path.join(RTL_DIR, f) for f in RTL_ALL]
    verilator_f = os.path.join(PROJECT_ROOT, "scripts", "verilator_1k.f")

    cmd = (["verilator", "--binary", "-f", verilator_f, tb_path]
           + rtl_paths + ["--top-module", "tb_top_1k"])

    print("  Compiling with Verilator (production 1K, no SIM_SMALL)...")
    result = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  COMPILE FAILED:\n{result.stderr[:5000]}")
        return False
    print("  Compilation OK.")
    return True


def run_simulation():
    """Run the compiled simulation."""
    binary = os.path.join(OBJ_DIR, "Vtb_top_1k")
    if not os.path.exists(binary):
        print(f"  ERROR: binary not found: {binary}")
        return False

    print("  Running simulation (production 1K, may take several minutes)...")
    try:
        result = subprocess.run([binary], cwd=PROJECT_ROOT,
                                capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        print("  FAIL: Simulation timed out (600s)")
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

def compare_rtl_output(g):
    """Read RTL dumps and compare against golden model."""
    uram_path  = os.path.join(TEST_DATA_DIR, "uram_1k_full_dump.hex")
    flush_path = os.path.join(TEST_DATA_DIR, "hbm_flush_1k_full_dump.hex")

    if not os.path.exists(flush_path):
        print("  ERROR: flush dump file not found")
        return False

    flush_words = read_hex_dump(flush_path)

    total_ok = total_mis = 0

    with open(RTL_OUT, 'w') as f:
        f.write("=" * 60 + "\n")
        f.write("PRODUCTION 1K INTEGRATION TEST - RTL vs GOLDEN COMPARISON\n")
        f.write("=" * 60 + "\n\n")

        # Check final output: residual2 in flush HBM at ACT_BASE + ACT_EMBED_OFFSET
        f.write("--- Final Output: Residual 2 (flush HBM) ---\n")
        rtl_res2 = extract_matrix_from_hbm(
            flush_words, ACT_BASE + ACT_EMBED_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_matrices(g['residual2'], rtl_res2, 'residual2_flush', f)
        total_ok += ok; total_mis += mis

        # Check URAM contents (should be residual2)
        if os.path.exists(uram_path):
            uram_words = read_hex_dump(uram_path)
            f.write("\n--- URAM Contents (should be residual2) ---\n")
            # TB dump uses HW stride but dumps only MODEL_STRIDE cols per row,
            # so the dump file has col_words_total = MODEL_STRIDE (contiguous)
            rtl_uram_res2 = extract_matrix_from_uram(
                uram_words, 0, BT, MODEL_STRIDE, MODEL_STRIDE)
            ok, mis = compare_matrices(g['residual2'], rtl_uram_res2, 'residual2_uram', f)
            total_ok += ok; total_mis += mis

        f.write("\n" + "=" * 60 + "\n")
        total = total_ok + total_mis
        f.write(f"SUMMARY: {total_ok}/{total} elements match\n")
        if total_mis == 0:
            f.write("ALL CHECKS PASSED\n")
        else:
            f.write(f"MISMATCHES: {total_mis} element(s) differ\n")

    print(f"  RTL comparison written: {RTL_OUT}")
    if total_mis == 0:
        print("  ALL CHECKS PASSED")
        return True
    else:
        print(f"  {total_mis} element(s) mismatched (see {RTL_OUT})")
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    data_only = '--data-only' in sys.argv

    print("=" * 60)
    print("  Production 1K Full Pipeline Test (GPT-2 Pre-Norm)")
    print(f"  BT={BT}, MODEL_DIM={MODEL_DIM}, F_DIM={F_DIM}")
    print(f"  NUM_HEADS={NUM_HEADS}, HEAD_DIM={HEAD_DIM}, TILE_SIZE={TILE_SIZE}")
    print(f"  NUM_ENGINES={NUM_ENGINES}")
    print(f"  WEIGHT_BASE={WEIGHT_BASE}, ACT_BASE={ACT_BASE}, LAYER_SIZE={LAYER_SIZE}")
    print(f"  SIM_HBM_DEPTH={SIM_HBM_DEPTH}")
    print("=" * 60)

    # Generate weights and embeddings
    print("\n  Generating weights...")
    weights = generate_weights(seed=SEED)

    rng = random.Random(SEED + 2)
    embed_int8 = [
        [rng.randint(-2, 1) for _ in range(MODEL_DIM)]
        for _ in range(BT)
    ]

    # Run golden model
    print("\n  Running golden model...")
    g = compute_golden(embed_int8, weights)
    write_golden(g)

    # Generate hex files for testbench
    print("\n  Generating HBM hex files (this may take a while for 1M-depth HBMs)...")
    generate_hex_files(weights, embed_int8)

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
    passed = compare_rtl_output(g)
    if not passed:
        sys.exit(1)

    print("\nDone.")


if __name__ == "__main__":
    main()
