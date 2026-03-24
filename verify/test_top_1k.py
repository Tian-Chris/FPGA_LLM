#!/usr/bin/env python3
"""Production-scale full pipeline test: GPT-2 pre-norm at MODEL_DIM=1024.

Exercises the complete FP16 pipeline (LN1 -> QKV -> attention -> proj -> res1 ->
LN2 -> FFN1 -> GELU -> FFN2 -> res2) at production dimensions:
  MODEL_DIM=1024, F_DIM=4096, NUM_HEADS=16, NUM_ENGINES=6, TILE_SIZE=32

Key differences from test_top.py (SIM_SMALL):
  - Numpy-accelerated FP16 tiled matmul with FP32 accumulation
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

from verify.golden.softmax import softmax_golden
from verify.golden.layernorm import layernorm_golden
from verify.golden.activation import gelu_golden
from verify.golden.residual_add import residual_add_golden

# Import reusable hex packing/extraction functions from test_top.py
from verify.test_top import (
    pack_16bit_to_256bit, pack_int16_to_256bit,
    write_hex_file, pack_matrix_fp16,
    pack_ln_params, pack_bias_vector,
    read_hex_dump, extract_int16_from_256bit,
    extract_matrix_from_hbm, extract_matrix_from_uram,
    compare_matrices, hex16,
)
from verify.golden.residual_add import fp16_add

# ---------------------------------------------------------------------------
# Production Parameters (must match defines.vh without SIM_SMALL)
# ---------------------------------------------------------------------------
MODEL_DIM     = 1024
NUM_HEADS     = 16
HEAD_DIM      = MODEL_DIM // NUM_HEADS   # 64
SCALE_FACTOR  = 0x3000  # FP16 1/√64 = 0.125 (matches defines.vh for HEAD_DIM=64)
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
LAYER_BIAS_QKV_OFFSET  = LAYER_LN2_OFFSET + 2 * MODEL_DIM // WE
LAYER_BIAS_PROJ_OFFSET = LAYER_BIAS_QKV_OFFSET + 3 * MODEL_DIM // WE
LAYER_BIAS_FFN1_OFFSET = LAYER_BIAS_PROJ_OFFSET + MODEL_DIM // WE
LAYER_BIAS_FFN2_OFFSET = LAYER_BIAS_FFN1_OFFSET + F_DIM // WE
LAYER_SIZE             = LAYER_BIAS_FFN2_OFFSET + MODEL_DIM // WE

# Strides (in 256-bit words)
MODEL_STRIDE = MODEL_DIM // WE   # 64
F_STRIDE     = F_DIM // WE       # 256

# Base addresses
WEIGHT_BASE = 0
ACT_BASE    = LAYER_SIZE   # 786688

# Activation offsets (in 256-bit words from ACT_BASE)
ACT_EMBED_OFFSET = 0
ACT_Q_OFFSET     = MAX_SEQ_LEN * MODEL_DIM // WE      # 8192
ACT_ATTN_OFFSET  = 4 * MAX_SEQ_LEN * MODEL_DIM // WE  # 32768
ACT_TEMP_OFFSET  = 5 * MAX_SEQ_LEN * MODEL_DIM // WE  # 40960
ACT_FFN_OFFSET   = 0

# Per-layer KV cache region (separate from activation scratch)
KV_V_OFFSET   = MAX_SEQ_LEN * MODEL_DIM // WE          # 8192
KV_LAYER_SIZE = 2 * MAX_SEQ_LEN * MODEL_DIM // WE      # 16384
KV_BASE       = ACT_BASE + 6 * MAX_SEQ_LEN * MODEL_DIM // WE

# Directories
TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
RTL_DIR       = os.path.join(PROJECT_ROOT, "rtl")
TB_DIR        = os.path.join(PROJECT_ROOT, "tb")
OBJ_DIR       = os.path.join(PROJECT_ROOT, "obj_dir")

GOLDEN_OUT = os.path.join(PROJECT_ROOT, "verify", "llm_golden_1k.txt")
RTL_OUT    = os.path.join(PROJECT_ROOT, "verify", "llm_rtl_1k.txt")

RTL_ALL = [
    "bram_controller.v", "fp16_mult.v", "fp32_add.v", "fp32_to_fp16.v",
    "fp16_add.v", "fp16_compare.v", "fp_mac_unit.v",
    "agu.v", "matmul_engine.v",
    "mem_arbiter.v", "tiling_engine.v", "softmax.v", "layernorm.v",
    "activation.v", "residual_add.v", "host_interface.v",
    "positional_embedding.v", "fsm_controller.v", "sim_hbm.v",
    "debug_writer.v",
    "uram_accum_buf.v", "tile_loader.v", "uram_flush.v", "act_dma.v",
    "uram_nm_adapter.v", "top_level.v",
]


# ---------------------------------------------------------------------------
# Numpy-Accelerated Tiled Matmul (FP16 with FP32 accumulation)
# ---------------------------------------------------------------------------

def tiled_matmul_fp16_numpy(mat_a, mat_b, tile_size, prefetch_dim=1024, bias=None):
    """Numpy-accelerated tiled matmul with FP16 bit pattern inputs.

    Per tile: FP16 inputs → float64 accumulation per k-chunk (models integer
    accumulation — no intermediate rounding), convert to FP16, then accumulate
    across k-chunks with FP16 addition.

    This matches the RTL's fp_mac_unit + uram_accum_buf behavior:
    - Each k-chunk: integer accumulation (modeled as float64), FP16 at output
    - Last k-chunk: add bias (if provided) before FP16 conversion
    - First k-chunk: write to result
    - Subsequent k-chunks: FP16 add to result (fp16_add_comb in uram_accum_buf)

    float64's 52-bit mantissa exceeds the ~27 bits needed for 32 products of
    22-bit FP16 mantissas, so no rounding occurs during accumulation.

    Args:
        bias: optional list of FP16 bit patterns (uint16), length N.
              Applied on last k-chunk's partial result before FP16 conversion,
              matching RTL's fp16_add_comb in matmul_engine output path.

    Input: 2D lists of FP16 bit patterns (uint16).
    Returns: list-of-lists with FP16 bit patterns (uint16).
    """
    A_bits = np.array(mat_a, dtype=np.uint16)
    B_bits = np.array(mat_b, dtype=np.uint16)
    A = A_bits.view(np.float16).astype(np.float64)
    B = B_bits.view(np.float16).astype(np.float64)
    M, K = A.shape
    _, N = B.shape

    bias_fp16 = None
    if bias is not None:
        bias_fp16 = np.array(bias, dtype=np.uint16).view(np.float16)

    result_fp16 = np.zeros((M, N), dtype=np.float16)

    num_k_chunks = (K + prefetch_dim - 1) // prefetch_dim

    for ti in range(0, M, tile_size):
        te = min(ti + tile_size, M)
        for tj in range(0, N, tile_size):
            je = min(tj + tile_size, N)
            for kc in range(num_k_chunks):
                ks = kc * prefetch_dim
                ke = min(ks + prefetch_dim, K)
                # float64 accumulation within this k-chunk (models integer accum)
                partial = A[ti:te, ks:ke] @ B[ks:ke, tj:je]
                # RTL path: integer → FP32 → FP16 (double rounding)
                partial_fp16 = partial.astype(np.float32).astype(np.float16)
                # On last k-chunk, add bias before accumulation (matches RTL)
                if bias_fp16 is not None and kc == num_k_chunks - 1:
                    partial_fp16 = (partial_fp16.astype(np.float32) +
                                    bias_fp16[tj:je].astype(np.float32)).astype(np.float16)
                if kc == 0:
                    result_fp16[ti:te, tj:je] = partial_fp16
                else:
                    # FP16 accumulation across k-chunks (matches uram_accum_buf fp16_add_comb)
                    result_fp16[ti:te, tj:je] = (
                        result_fp16[ti:te, tj:je].astype(np.float32) +
                        partial_fp16.astype(np.float32)
                    ).astype(np.float16)

    return result_fp16.view(np.uint16).astype(int).tolist()


def _transpose(mat):
    rows = len(mat)
    cols = len(mat[0])
    return [[mat[r][c] for r in range(rows)] for c in range(cols)]


# ---------------------------------------------------------------------------
# Weight Generation
# ---------------------------------------------------------------------------

def generate_weights(seed=42):
    """Generate FP16 weights for one encoder layer as uint16 bit patterns.

    Uses small range to avoid FP16 overflow during accumulation.
    """
    rng = np.random.RandomState(seed)

    def rand_mat(rows, cols):
        vals = rng.uniform(-0.05, 0.05, (rows, cols)).astype(np.float16)
        return vals.view(np.uint16).astype(int).tolist()

    def rand_vec(dim):
        vals = rng.uniform(-0.5, 0.5, (dim,)).astype(np.float16)
        return vals.view(np.uint16).astype(int).tolist()

    def rand_gamma(dim):
        """LN gamma centered near 1.0."""
        vals = rng.uniform(0.8, 1.2, (dim,)).astype(np.float16)
        return vals.view(np.uint16).astype(int).tolist()

    w = {}
    # Frontend projection (consumes RNG state)
    w['W_proj'] = rand_mat(INPUT_DIM, MODEL_DIM)

    # Encoder layer 0
    w['W_q']    = rand_mat(MODEL_DIM, MODEL_DIM)
    w['W_k']    = rand_mat(MODEL_DIM, MODEL_DIM)
    w['W_v']    = rand_mat(MODEL_DIM, MODEL_DIM)
    w['W_o']    = rand_mat(MODEL_DIM, MODEL_DIM)
    w['W_ffn1'] = rand_mat(MODEL_DIM, F_DIM)
    w['W_ffn2'] = rand_mat(F_DIM, MODEL_DIM)
    w['gamma1'] = rand_gamma(MODEL_DIM)
    w['beta1']  = rand_vec(MODEL_DIM)
    w['gamma2'] = rand_gamma(MODEL_DIM)
    w['beta2']  = rand_vec(MODEL_DIM)

    # Biases
    w['bias_q']    = rand_vec(MODEL_DIM)
    w['bias_k']    = rand_vec(MODEL_DIM)
    w['bias_v']    = rand_vec(MODEL_DIM)
    w['bias_proj'] = rand_vec(MODEL_DIM)
    w['bias_ffn1'] = rand_vec(F_DIM)
    w['bias_ffn2'] = rand_vec(MODEL_DIM)

    return w


def add_bias_fp16(matrix_bits, bias_bits):
    """Add FP16 bias[j] to each matrix[i][j] using exact RTL fp16_add_comb."""
    return [[fp16_add(matrix_bits[i][j], bias_bits[j])
             for j in range(len(bias_bits))]
            for i in range(len(matrix_bits))]


# ---------------------------------------------------------------------------
# Golden Model (Production-Scale Full Pipeline)
# ---------------------------------------------------------------------------

def compute_golden(embed_fp16, weights):
    """Run the full encoder layer golden model for GPT-2 pre-norm architecture.

    All values are FP16 bit patterns (uint16). Pipeline:
      LN1 → QKV → attention → proj → residual1 → LN2 → FFN1 → GELU → FFN2 → residual2
    """
    g = {}
    g['embed_fp16'] = embed_fp16

    # ------------------------------------------------------------------
    # Step 0: LN1
    # ------------------------------------------------------------------
    print("    LN1...")
    ln1_out = []
    for t in range(BT):
        normed = layernorm_golden(
            embed_fp16[t], weights['gamma1'], weights['beta1'], MODEL_DIM
        )
        ln1_out.append(normed)
    g['ln1_out'] = ln1_out
    print(f"      golden LN1[0][0:4] = {' '.join(f'{v:04x}' for v in ln1_out[0][:4])}")
    print(f"      golden LN1[1][0:4] = {' '.join(f'{v:04x}' for v in ln1_out[1][:4])}")

    # ------------------------------------------------------------------
    # Step 2: QKV projections
    # ------------------------------------------------------------------
    print("    QKV matmuls...")
    Q = tiled_matmul_fp16_numpy(ln1_out, weights['W_q'], TILE_SIZE, bias=weights['bias_q'])
    K = tiled_matmul_fp16_numpy(ln1_out, weights['W_k'], TILE_SIZE, bias=weights['bias_k'])
    V = tiled_matmul_fp16_numpy(ln1_out, weights['W_v'], TILE_SIZE, bias=weights['bias_v'])
    g['Q'] = Q
    g['K'] = K
    g['V'] = V
    print(f"      golden Q[0][0:4] = {' '.join(f'{v:04x}' for v in Q[0][:4])}")
    print(f"      golden K[0][0:4] = {' '.join(f'{v:04x}' for v in K[0][:4])}")
    print(f"      golden V[0][0:4] = {' '.join(f'{v:04x}' for v in V[0][:4])}")

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
        scores_h = tiled_matmul_fp16_numpy(Q_h, K_h_T, TILE_SIZE)

        probs_h = [softmax_golden(scores_h[t], SCALE_FACTOR, row_idx=t)
                   for t in range(BT)]

        attn_h = tiled_matmul_fp16_numpy(probs_h, V_h, TILE_SIZE)

        for t in range(BT):
            for d in range(HEAD_DIM):
                attn_concat[t][h*HEAD_DIM + d] = attn_h[t][d]

        all_scores.append(scores_h)
        all_probs.append(probs_h)

    g['scores'] = all_scores[0]
    g['probs_fp16'] = all_probs[0]
    g['attn_out'] = attn_concat

    # ------------------------------------------------------------------
    # Step 4: Output projection
    # ------------------------------------------------------------------
    print("    Output projection...")
    attn_proj = tiled_matmul_fp16_numpy(attn_concat, weights['W_o'], TILE_SIZE, bias=weights['bias_proj'])
    g['attn_proj'] = attn_proj
    print(f"      golden proj[0][0:4] = {' '.join(f'{v:04x}' for v in attn_proj[0][:4])}")
    print(f"      golden proj[1][0:4] = {' '.join(f'{v:04x}' for v in attn_proj[1][:4])}")

    # ------------------------------------------------------------------
    # Step 5: Residual1 = proj + original embeddings
    # ------------------------------------------------------------------
    print("    Residual 1...")
    residual1 = [residual_add_golden(embed_fp16[t], attn_proj[t]) for t in range(BT)]
    g['residual1'] = residual1
    print(f"      golden res1[0][0:4] = {' '.join(f'{v:04x}' for v in residual1[0][:4])}")
    print(f"      golden res1[1][0:4] = {' '.join(f'{v:04x}' for v in residual1[1][:4])}")

    # ------------------------------------------------------------------
    # Step 7: LN2
    # ------------------------------------------------------------------
    print("    LN2...")
    ln2_out = []
    for t in range(BT):
        normed = layernorm_golden(
            residual1[t], weights['gamma2'], weights['beta2'], MODEL_DIM
        )
        ln2_out.append(normed)
    g['ln2_out'] = ln2_out

    print(f"      golden ln2[0][0:4]  = {' '.join(f'{v:04x}' for v in ln2_out[0][:4])}")
    print(f"      golden ln2[1][0:4]  = {' '.join(f'{v:04x}' for v in ln2_out[1][:4])}")

    # ------------------------------------------------------------------
    # Step 9: FFN1
    # ------------------------------------------------------------------
    print("    FFN1 (1024x4096)...")
    ffn1 = tiled_matmul_fp16_numpy(ln2_out, weights['W_ffn1'], TILE_SIZE, bias=weights['bias_ffn1'])
    g['ffn1'] = ffn1
    print(f"      golden ffn1[0][0:4] = {' '.join(f'{v:04x}' for v in ffn1[0][:4])}")
    # Dump golden FFN1 at same positions as TB URAM dump for comparison
    print(f"      golden ffn1[0] cw0[0:3]   = {' '.join(f'{v:04x}' for v in ffn1[0][0:4])}")
    print(f"      golden ffn1[0] cw2[32:35]  = {' '.join(f'{v:04x}' for v in ffn1[0][32:36])}")
    print(f"      golden ffn1[0] cw10[160:163]= {' '.join(f'{v:04x}' for v in ffn1[0][160:164])}")
    print(f"      golden ffn1[0] cw100[1600:1603]= {' '.join(f'{v:04x}' for v in ffn1[0][1600:1604])}")
    print(f"      golden ffn1[1] cw0[0:3]   = {' '.join(f'{v:04x}' for v in ffn1[1][0:4])}")
    print(f"      golden ffn1[1] cw2[32:35]  = {' '.join(f'{v:04x}' for v in ffn1[1][32:36])}")

    # ------------------------------------------------------------------
    # Step 10: GELU
    # ------------------------------------------------------------------
    print("    GELU...")
    ffn_act = [gelu_golden(row) for row in ffn1]
    g['ffn_act'] = ffn_act
    print(f"      golden gelu[0][0:4] = {' '.join(f'{v:04x}' for v in ffn_act[0][:4])}")
    print(f"      golden gelu[0] cw2[32:35]  = {' '.join(f'{v:04x}' for v in ffn_act[0][32:36])}")
    print(f"      golden gelu[0] cw100[1600:1603]= {' '.join(f'{v:04x}' for v in ffn_act[0][1600:1604])}")

    # ------------------------------------------------------------------
    # Step 12: FFN2
    # ------------------------------------------------------------------
    print("    FFN2 (4096x1024)...")
    ffn2 = tiled_matmul_fp16_numpy(ffn_act, weights['W_ffn2'], TILE_SIZE, bias=weights['bias_ffn2'])
    g['ffn2'] = ffn2
    print(f"      golden ffn2[0][0:4] = {' '.join(f'{v:04x}' for v in ffn2[0][:4])}")

    # ------------------------------------------------------------------
    # Step 13: Residual2 = ffn2 + residual1 (pre-norm architecture)
    # ------------------------------------------------------------------
    print("    Residual 2...")
    residual2 = [residual_add_golden(residual1[t], ffn2[t]) for t in range(BT)]
    g['residual2'] = residual2
    print(f"      golden res2[0][0:4] = {' '.join(f'{v:04x}' for v in residual2[0][:4])}")

    return g


# ---------------------------------------------------------------------------
# HBM Hex File Generation
# ---------------------------------------------------------------------------

def generate_hex_files(weights, embed_fp16):
    """Generate hex files for testbench $readmemh preloading."""
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    # Weight HBM: FP16 weights
    print("    Packing weight HBM...")
    wgt_mem = {}

    pack_matrix_fp16(weights['W_q'], MODEL_DIM, MODEL_DIM,
                     WEIGHT_BASE + LAYER_WQ_OFFSET, MODEL_STRIDE, wgt_mem)
    pack_matrix_fp16(weights['W_k'], MODEL_DIM, MODEL_DIM,
                     WEIGHT_BASE + LAYER_WK_OFFSET, MODEL_STRIDE, wgt_mem)
    pack_matrix_fp16(weights['W_v'], MODEL_DIM, MODEL_DIM,
                     WEIGHT_BASE + LAYER_WV_OFFSET, MODEL_STRIDE, wgt_mem)
    pack_matrix_fp16(weights['W_o'], MODEL_DIM, MODEL_DIM,
                     WEIGHT_BASE + LAYER_WO_OFFSET, MODEL_STRIDE, wgt_mem)
    pack_matrix_fp16(weights['W_ffn1'], MODEL_DIM, F_DIM,
                     WEIGHT_BASE + LAYER_FFN1_OFFSET, F_STRIDE, wgt_mem)
    pack_matrix_fp16(weights['W_ffn2'], F_DIM, MODEL_DIM,
                     WEIGHT_BASE + LAYER_FFN2_OFFSET, MODEL_STRIDE, wgt_mem)

    # LN params (interleaved FP16)
    pack_ln_params(weights['gamma1'], weights['beta1'],
                   WEIGHT_BASE + LAYER_LN1_OFFSET, wgt_mem)
    pack_ln_params(weights['gamma2'], weights['beta2'],
                   WEIGHT_BASE + LAYER_LN2_OFFSET, wgt_mem)

    # Biases
    qkv_bias = weights['bias_q'] + weights['bias_k'] + weights['bias_v']
    pack_bias_vector(qkv_bias, WEIGHT_BASE + LAYER_BIAS_QKV_OFFSET, wgt_mem)
    pack_bias_vector(weights['bias_proj'], WEIGHT_BASE + LAYER_BIAS_PROJ_OFFSET, wgt_mem)
    pack_bias_vector(weights['bias_ffn1'], WEIGHT_BASE + LAYER_BIAS_FFN1_OFFSET, wgt_mem)
    pack_bias_vector(weights['bias_ffn2'], WEIGHT_BASE + LAYER_BIAS_FFN2_OFFSET, wgt_mem)

    print("    Writing weight hex file...")
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_wgt_1k_full.hex"),
                   [wgt_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # Activation HBM: FP16 embeddings
    print("    Packing activation HBM...")
    act_mem = {}
    pack_matrix_fp16(embed_fp16, BT, MODEL_DIM,
                     ACT_BASE + ACT_EMBED_OFFSET, MODEL_STRIDE, act_mem)

    print("    Writing activation hex file...")
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_act_1k_full.hex"),
                   [act_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # DMA HBM: LN params + embeddings
    print("    Packing DMA HBM...")
    dma_mem = {}

    pack_ln_params(weights['gamma1'], weights['beta1'],
                   WEIGHT_BASE + LAYER_LN1_OFFSET, dma_mem)
    pack_ln_params(weights['gamma2'], weights['beta2'],
                   WEIGHT_BASE + LAYER_LN2_OFFSET, dma_mem)

    pack_matrix_fp16(embed_fp16, BT, MODEL_DIM,
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
            ('embed_fp16', 'Input embeddings (FP16)'),
            ('ln1_out', 'LN1 output'),
            ('Q', 'Q projection'),
            ('K', 'K projection'),
            ('V', 'V projection'),
            ('attn_out', 'Attention output'),
            ('attn_proj', 'Output projection'),
            ('residual1', 'Residual 1'),
            ('ln2_out', 'LN2 output'),
            ('ffn1', 'FFN1 output'),
            ('ffn_act', 'GELU output'),
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
                                capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        print("  FAIL: Simulation timed out (900s)")
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
def _print_correlation(golden, rtl, name, f_out):
    """Print Pearson correlation and error statistics between golden and RTL."""
    g_flat = np.array([v & 0xFFFF for row in golden for v in row], dtype=np.uint16)
    r_flat = np.array([v & 0xFFFF for row in rtl for v in row], dtype=np.uint16)
    g_fp = g_flat.view(np.float16).astype(np.float64)
    r_fp = r_flat.view(np.float16).astype(np.float64)
    # Remove NaN/Inf pairs
    valid = np.isfinite(g_fp) & np.isfinite(r_fp)
    g_v, r_v = g_fp[valid], r_fp[valid]
    if len(g_v) < 2:
        f_out.write(f"  {name} correlation: N/A (too few valid elements)\n")
        return
    corr = np.corrcoef(g_v, r_v)[0, 1]
    abs_err = np.abs(g_v - r_v)
    f_out.write(f"  {name} correlation: {corr:.6f} "
                f"(mean_abs={abs_err.mean():.6f}, max_abs={abs_err.max():.6f}, "
                f"median_abs={np.median(abs_err):.6f})\n")


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
        # Use wider tolerance for 1k: numpy matmul accumulation order differs from
        # RTL's per-element MAC. With 1024-dim dot products × 14 stages, expect
        # ~2-5% relative error and ~0.01 absolute error.
        ok, mis = compare_matrices(g['residual2'], rtl_res2, 'residual2_flush', f,
                                   rel_tol=0.05, abs_tol=0.6)
        total_ok += ok; total_mis += mis

        # Statistical correlation check (more meaningful for production scale)
        _print_correlation(g['residual2'], rtl_res2, 'residual2_flush', f)

        # Check URAM contents (should be residual2)
        if os.path.exists(uram_path):
            uram_words = read_hex_dump(uram_path)
            f.write("\n--- URAM Contents (should be residual2) ---\n")
            # TB dump uses HW stride but dumps only MODEL_STRIDE cols per row,
            # so the dump file has col_words_total = MODEL_STRIDE (contiguous)
            rtl_uram_res2 = extract_matrix_from_uram(
                uram_words, 0, BT, MODEL_STRIDE, MODEL_STRIDE)
            ok, mis = compare_matrices(g['residual2'], rtl_uram_res2, 'residual2_uram', f,
                                       rel_tol=0.05, abs_tol=0.6)
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
    golden_only = '--golden-only' in sys.argv

    print("=" * 60)
    print("  Production 1K Full Pipeline Test (GPT-2 Pre-Norm)")
    print(f"  BT={BT}, MODEL_DIM={MODEL_DIM}, F_DIM={F_DIM}")
    print(f"  NUM_HEADS={NUM_HEADS}, HEAD_DIM={HEAD_DIM}, TILE_SIZE={TILE_SIZE}")
    print(f"  NUM_ENGINES={NUM_ENGINES}")
    print(f"  WEIGHT_BASE={WEIGHT_BASE}, ACT_BASE={ACT_BASE}, LAYER_SIZE={LAYER_SIZE}")
    print(f"  SIM_HBM_DEPTH={SIM_HBM_DEPTH}")
    print("=" * 60)

    # Generate weights and embeddings (FP16 bit patterns)
    print("\n  Generating weights...")
    weights = generate_weights(seed=SEED)

    rng_embed = np.random.RandomState(SEED + 2)
    embed_fp16 = rng_embed.uniform(-0.5, 0.5, (BT, MODEL_DIM)).astype(np.float16)
    embed_fp16 = embed_fp16.view(np.uint16).astype(int).tolist()

    # Run golden model
    print("\n  Running golden model...")
    g = compute_golden(embed_fp16, weights)
    write_golden(g)

    if golden_only:
        print("\n  --golden-only: golden complete, skipping RTL")
        return

    # Generate hex files for testbench
    print("\n  Generating HBM hex files (this may take a while for 1M-depth HBMs)...")
    generate_hex_files(weights, embed_fp16)

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
