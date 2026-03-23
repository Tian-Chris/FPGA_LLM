#!/usr/bin/env python3
"""SIM_SMALL integration test: full attention + FFN pipeline with HBM architecture.

Generates random FP16 weights and input activations, runs the golden model
matching the RTL's FP16 data path (FP16×FP16→FP32 accumulation, FP16 output),
writes hex files for testbench preloading, compiles and runs the simulation,
then compares RTL dump output against golden intermediates.

Datapath: FP16 weights, FP16 activations, FP32 accumulation, GELU activation.
"""

import math
import os
import sys
import random
import struct
import subprocess
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.golden.matmul_engine import matmul_golden
from verify.golden.softmax import softmax_golden
from verify.golden.layernorm import layernorm_golden
from verify.golden.activation import gelu_golden
from verify.golden.residual_add import residual_add_golden, fp16_add

# ---------------------------------------------------------------------------
# SIM_SMALL Parameters (must match defines.vh under SIM_SMALL)
# ---------------------------------------------------------------------------
MODEL_DIM     = 64
NUM_HEADS     = 2
HEAD_DIM      = MODEL_DIM // NUM_HEADS   # 32
SCALE_FACTOR  = 0x31A8  # FP16 1/√32 ≈ 0.1768 (matches defines.vh for HEAD_DIM=32)
F_DIM         = 128
INPUT_DIM     = 64
MAX_SEQ_LEN   = 32
MAX_BATCH     = 1
NUM_ENC       = 1
TILE_SIZE     = 32
NUM_ENGINES   = 1

SEQ_LEN = 32
BATCH   = 1
BT      = BATCH * SEQ_LEN   # 32

DATA_W = 16
BUS_ELEMS = 16       # 256 / 16
URAM_ROWS = 32
URAM_COLS = 128
URAM_COL_WORDS = URAM_COLS // BUS_ELEMS  # 8

SIM_HBM_DEPTH = 4096

SEED = 42

# ---------------------------------------------------------------------------
# HBM Memory Layout (word-addressed, 256-bit words, 16 FP16 elements each)
# Must match fsm_controller.v localparams
# ---------------------------------------------------------------------------
WE = BUS_ELEMS  # 16

# Per-layer weight offsets (in 256-bit words)
LAYER_WQ_OFFSET   = 0
LAYER_WK_OFFSET   = MODEL_DIM * MODEL_DIM // WE            # 64
LAYER_WV_OFFSET   = 2 * MODEL_DIM * MODEL_DIM // WE        # 128
LAYER_WO_OFFSET   = 3 * MODEL_DIM * MODEL_DIM // WE        # 192
LAYER_FFN1_OFFSET = 4 * MODEL_DIM * MODEL_DIM // WE        # 256
LAYER_FFN2_OFFSET = LAYER_FFN1_OFFSET + MODEL_DIM * F_DIM // WE  # 384
LAYER_LN1_OFFSET  = LAYER_FFN2_OFFSET + F_DIM * MODEL_DIM // WE  # 512
LAYER_LN2_OFFSET  = LAYER_LN1_OFFSET + 2 * MODEL_DIM // WE      # 516
# Bias offsets (after LN2 params)
LAYER_BIAS_QKV_OFFSET  = LAYER_LN2_OFFSET + 2 * MODEL_DIM // WE  # 524
LAYER_BIAS_PROJ_OFFSET = LAYER_BIAS_QKV_OFFSET + 3 * MODEL_DIM // WE  # 536
LAYER_BIAS_FFN1_OFFSET = LAYER_BIAS_PROJ_OFFSET + MODEL_DIM // WE     # 540
LAYER_BIAS_FFN2_OFFSET = LAYER_BIAS_FFN1_OFFSET + F_DIM // WE         # 548
LAYER_SIZE             = LAYER_BIAS_FFN2_OFFSET + MODEL_DIM // WE     # 552

# Strides (in 256-bit words)
MODEL_STRIDE = MODEL_DIM // WE   # 2
F_STRIDE     = F_DIM // WE       # 4

# Base addresses
WEIGHT_BASE = 0
ACT_BASE    = LAYER_SIZE   # 520

# Activation offsets (in 256-bit words from ACT_BASE)
# Q/K/V/ATTN must NOT overlap with EMBED (embeddings read for all 3 QKV phases)
ACT_EMBED_OFFSET = 0
ACT_Q_OFFSET     = MAX_SEQ_LEN * MODEL_DIM // WE
ACT_ATTN_OFFSET  = 4 * MAX_SEQ_LEN * MODEL_DIM // WE
ACT_TEMP_OFFSET  = 5 * MAX_SEQ_LEN * MODEL_DIM // WE       # LN staging for pre-norm
ACT_FFN_OFFSET   = 0

# Per-layer KV cache region (separate from activation scratch)
KV_V_OFFSET   = MAX_SEQ_LEN * MODEL_DIM // WE
KV_LAYER_SIZE = 2 * MAX_SEQ_LEN * MODEL_DIM // WE
KV_BASE       = ACT_BASE + 6 * MAX_SEQ_LEN * MODEL_DIM // WE

# Directories
TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
RTL_DIR       = os.path.join(PROJECT_ROOT, "rtl")
TB_DIR        = os.path.join(PROJECT_ROOT, "tb")
OBJ_DIR       = os.path.join(PROJECT_ROOT, "obj_dir")

GOLDEN_OUT = os.path.join(PROJECT_ROOT, "verify", "llm_golden.txt")
RTL_OUT    = os.path.join(PROJECT_ROOT, "verify", "llm_rtl.txt")

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
# Helpers
# ---------------------------------------------------------------------------

def hex16(val):
    return f"{val & 0xFFFF:04x}"


def float_to_fp16_bits(val):
    """Convert a Python float to FP16 bit pattern (uint16)."""
    return int(np.float16(val).view(np.uint16))


def pack_16bit_to_256bit(elements):
    """Pack up to 16 16-bit values into a 256-bit hex string (little-endian element order).

    Element 0 occupies bits [15:0], element 1 occupies bits [31:16], etc.
    The hex string represents the full 256-bit value with MSB on the left.
    """
    word = 0
    for i, v in enumerate(elements):
        word |= (v & 0xFFFF) << (i * 16)
    return f"{word:064x}"


# Legacy alias — imported by test_top_1k.py and test_multi_layer.py
pack_int16_to_256bit = pack_16bit_to_256bit


def write_hex_file(filepath, words):
    """Write a list of 64-char hex strings (256-bit words) to a file with @addr directives."""
    with open(filepath, 'w') as f:
        for addr, word in enumerate(words):
            if word != '0' * 64:
                f.write(f"@{addr:08x} {word}\n")


def pack_matrix_fp16(mat, rows, cols, base_addr, stride, mem):
    """Pack FP16 matrix (uint16 bit patterns) into 256-bit HBM words.

    Row r is stored at HBM word addresses [base_addr + r*stride .. base_addr + r*stride + cols/WE - 1].
    """
    for r in range(rows):
        for w in range(cols // WE):
            elements = []
            for e in range(WE):
                col = w * WE + e
                if col < cols:
                    elements.append(mat[r][col] & 0xFFFF)
                else:
                    elements.append(0)
            addr = base_addr + r * stride + w
            mem[addr] = pack_16bit_to_256bit(elements)


# Legacy aliases for imports
pack_matrix_int8_as_int16 = pack_matrix_fp16
pack_matrix_int16 = pack_matrix_fp16


def pack_bias_vector(bias, base_addr, mem):
    """Pack a 1D bias vector into consecutive 256-bit words at base_addr."""
    dim = len(bias)
    for w in range(dim // WE):
        elements = [bias[w * WE + e] & 0xFFFF for e in range(WE)]
        mem[base_addr + w] = pack_16bit_to_256bit(elements)


def pack_ln_params(gamma, beta, base_addr, mem):
    """Pack LN gamma/beta as interleaved FP16: gamma[0], beta[0], gamma[1], beta[1], ...

    Each value is a separate FP16 (uint16). Total = 2*dim values = 2*dim/WE words.
    """
    dim = len(gamma)
    interleaved = []
    for i in range(dim):
        interleaved.append(gamma[i] & 0xFFFF)
        interleaved.append(beta[i] & 0xFFFF)
    words = 2 * dim // WE
    for w in range(words):
        elements = interleaved[w * WE:(w + 1) * WE]
        addr = base_addr + w
        mem[addr] = pack_16bit_to_256bit(elements)


# ---------------------------------------------------------------------------
# Weight Generation (FP16 bit patterns)
# ---------------------------------------------------------------------------

def generate_weights(seed=42):
    """Generate FP16 weights for one encoder layer as uint16 bit patterns.

    Uses small range to avoid FP16 overflow through the pipeline.
    """
    rng = np.random.RandomState(seed)

    def rand_mat(rows, cols):
        vals = rng.uniform(-0.05, 0.05, (rows, cols)).astype(np.float16)
        return vals.view(np.uint16).astype(int).tolist()

    def rand_vec(dim):
        vals = rng.uniform(-0.5, 0.5, (dim,)).astype(np.float16)
        return vals.view(np.uint16).astype(int).tolist()

    def rand_gamma(dim):
        """LN gamma centered near 1.0 (typical for trained models)."""
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

    # Biases (small range, like weights)
    w['bias_q']    = rand_vec(MODEL_DIM)
    w['bias_k']    = rand_vec(MODEL_DIM)
    w['bias_v']    = rand_vec(MODEL_DIM)
    w['bias_proj'] = rand_vec(MODEL_DIM)
    w['bias_ffn1'] = rand_vec(F_DIM)
    w['bias_ffn2'] = rand_vec(MODEL_DIM)

    return w


# ---------------------------------------------------------------------------
# Tiled Matmul (FP16 bit patterns, matching RTL fp_mac_unit)
# ---------------------------------------------------------------------------

def tiled_matmul_fp16(mat_a, mat_b, tile_size):
    """Tiled matmul with FP16 bit pattern inputs.

    FP16×FP16 → FP32 accumulation → FP16 output.
    Uses matmul_golden which already implements this.
    """
    return matmul_golden(mat_a, mat_b, tile_size)


def add_bias_fp16(matrix_bits, bias_bits):
    """Add FP16 bias[j] to each matrix[i][j] using exact RTL fp16_add_comb."""
    return [[fp16_add(matrix_bits[i][j], bias_bits[j])
             for j in range(len(bias_bits))]
            for i in range(len(matrix_bits))]


def _transpose(mat):
    rows = len(mat)
    cols = len(mat[0])
    return [[mat[r][c] for r in range(rows)] for c in range(cols)]


# ---------------------------------------------------------------------------
# Golden Model (HBM architecture)
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
    ln1_out = []
    for t in range(BT):
        normed = layernorm_golden(
            embed_fp16[t], weights['gamma1'], weights['beta1'], MODEL_DIM
        )
        ln1_out.append(normed)
    g['ln1_out'] = ln1_out

    # ------------------------------------------------------------------
    # Step 2: QKV projections
    # ------------------------------------------------------------------
    Q = add_bias_fp16(tiled_matmul_fp16(ln1_out, weights['W_q'], TILE_SIZE), weights['bias_q'])
    K = add_bias_fp16(tiled_matmul_fp16(ln1_out, weights['W_k'], TILE_SIZE), weights['bias_k'])
    V = add_bias_fp16(tiled_matmul_fp16(ln1_out, weights['W_v'], TILE_SIZE), weights['bias_v'])
    g['Q'] = Q
    g['K'] = K
    g['V'] = V

    # ------------------------------------------------------------------
    # Step 3: Multi-head attention
    # ------------------------------------------------------------------
    attn_concat = [[0] * MODEL_DIM for _ in range(BT)]
    all_scores = []
    all_probs  = []

    for h in range(NUM_HEADS):
        Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q]
        K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K]
        V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V]

        K_h_T = _transpose(K_h)
        scores_h = tiled_matmul_fp16(Q_h, K_h_T, TILE_SIZE)

        probs_h = [softmax_golden(scores_h[t], SCALE_FACTOR, row_idx=t)
                   for t in range(BT)]

        attn_h = tiled_matmul_fp16(probs_h, V_h, TILE_SIZE)

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
    attn_proj = add_bias_fp16(tiled_matmul_fp16(attn_concat, weights['W_o'], TILE_SIZE), weights['bias_proj'])
    g['attn_proj'] = attn_proj

    # ------------------------------------------------------------------
    # Step 5: Residual1 = proj + original embeddings
    # ------------------------------------------------------------------
    residual1 = [residual_add_golden(embed_fp16[t], attn_proj[t]) for t in range(BT)]
    g['residual1'] = residual1

    # ------------------------------------------------------------------
    # Step 7: LN2
    # ------------------------------------------------------------------
    ln2_out = []
    for t in range(BT):
        normed = layernorm_golden(
            residual1[t], weights['gamma2'], weights['beta2'], MODEL_DIM
        )
        ln2_out.append(normed)
    g['ln2_out'] = ln2_out

    # ------------------------------------------------------------------
    # Step 9: FFN1
    # ------------------------------------------------------------------
    ffn1 = add_bias_fp16(tiled_matmul_fp16(ln2_out, weights['W_ffn1'], TILE_SIZE), weights['bias_ffn1'])
    g['ffn1'] = ffn1

    # ------------------------------------------------------------------
    # Step 10: GELU
    # ------------------------------------------------------------------
    ffn_act = [gelu_golden(row) for row in ffn1]
    g['ffn_act'] = ffn_act

    # ------------------------------------------------------------------
    # Step 12: FFN2
    # ------------------------------------------------------------------
    ffn2 = add_bias_fp16(tiled_matmul_fp16(ffn_act, weights['W_ffn2'], TILE_SIZE), weights['bias_ffn2'])
    g['ffn2'] = ffn2

    # ------------------------------------------------------------------
    # Step 13: Residual2 = ffn2 + residual1
    # In GPT-2 Pre-Norm: residual2 = residual1 + FFN(LN2(residual1))
    # The RTL reads the skip connection from DMA at ACT_EMBED, which was
    # overwritten with residual1 by the flush at step 6.
    # ------------------------------------------------------------------
    residual2 = [residual_add_golden(residual1[t], ffn2[t]) for t in range(BT)]
    g['residual2'] = residual2

    return g


# ---------------------------------------------------------------------------
# HBM Hex File Generation
# ---------------------------------------------------------------------------

def generate_hex_files(weights, embed_fp16):
    """Generate hex files for testbench $readmemh preloading."""
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    # Weight HBM: FP16 weights
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

    # Bias vectors (QKV concatenated, then proj, ffn1, ffn2)
    qkv_bias = weights['bias_q'] + weights['bias_k'] + weights['bias_v']
    pack_bias_vector(qkv_bias, WEIGHT_BASE + LAYER_BIAS_QKV_OFFSET, wgt_mem)
    pack_bias_vector(weights['bias_proj'], WEIGHT_BASE + LAYER_BIAS_PROJ_OFFSET, wgt_mem)
    pack_bias_vector(weights['bias_ffn1'], WEIGHT_BASE + LAYER_BIAS_FFN1_OFFSET, wgt_mem)
    pack_bias_vector(weights['bias_ffn2'], WEIGHT_BASE + LAYER_BIAS_FFN2_OFFSET, wgt_mem)

    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_wgt.hex"),
                   [wgt_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # Activation HBM: FP16 embeddings
    act_mem = {}
    pack_matrix_fp16(embed_fp16, BT, MODEL_DIM,
                     ACT_BASE + ACT_EMBED_OFFSET, MODEL_STRIDE, act_mem)

    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_act.hex"),
                   [act_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # DMA HBM: LN params (weight space) + embeddings (activation space)
    dma_mem = {}

    pack_ln_params(weights['gamma1'], weights['beta1'],
                   WEIGHT_BASE + LAYER_LN1_OFFSET, dma_mem)
    pack_ln_params(weights['gamma2'], weights['beta2'],
                   WEIGHT_BASE + LAYER_LN2_OFFSET, dma_mem)

    pack_matrix_fp16(embed_fp16, BT, MODEL_DIM,
                     ACT_BASE + ACT_EMBED_OFFSET, MODEL_STRIDE, dma_mem)

    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_dma.hex"),
                   [dma_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    print(f"  HBM hex files written to {TEST_DATA_DIR}/hbm_{{wgt,act,dma}}.hex")


# ---------------------------------------------------------------------------
# Golden File Writer
# ---------------------------------------------------------------------------

def write_golden(g):
    """Write golden intermediate values to text file."""
    with open(GOLDEN_OUT, 'w') as f:
        f.write("=" * 60 + "\n")
        f.write("SIM_SMALL INTEGRATION TEST — GOLDEN REFERENCE (GPT-2 Pre-Norm)\n")
        f.write("=" * 60 + "\n")
        f.write(f"Config: BT={BT}, MODEL_DIM={MODEL_DIM}, F_DIM={F_DIM}, "
                f"NUM_HEADS={NUM_HEADS}, HEAD_DIM={HEAD_DIM}\n")
        f.write(f"WEIGHT_BASE={WEIGHT_BASE}, ACT_BASE={ACT_BASE}\n")
        f.write(f"LAYER_SIZE={LAYER_SIZE}\n\n")

        def write_mat(name, mat, fmt='int16'):
            rows = len(mat)
            cols = len(mat[0])
            f.write(f"  {name}  [{rows}x{cols}]\n")
            for i, row in enumerate(mat):
                vals = "  ".join(hex16(v) for v in row)
                f.write(f"    row[{i}]: {vals}\n")

        for stage, name in [
            ('embed_fp16', 'Input embeddings (FP16)'),
            ('ln1_out', 'LN1 output (pre-norm)'),
            ('Q', 'Q projection'),
            ('K', 'K projection'),
            ('V', 'V projection'),
            ('scores', 'Attention scores'),
            ('probs_fp16', 'Softmax probs (FP16)'),
            ('attn_out', 'Attention output'),
            ('attn_proj', 'Output projection'),
            ('residual1', 'Residual 1 (embed + proj)'),
            ('ln2_out', 'LN2 output (pre-norm)'),
            ('ffn1', 'FFN1 output'),
            ('ffn_act', 'GELU output'),
            ('ffn2', 'FFN2 output'),
            ('residual2', 'Residual 2 (embed + ffn2)'),
        ]:
            f.write(f"\n--- {name} ---\n")
            write_mat(stage, g[stage])

    print(f"  Golden written: {GOLDEN_OUT}")


# ---------------------------------------------------------------------------
# Compile & Run
# ---------------------------------------------------------------------------

def compile_design():
    """Compile with Verilator using SIM_SMALL flags."""
    tb_path = os.path.join(TB_DIR, "tb_top.v")
    rtl_paths = [os.path.join(RTL_DIR, f) for f in RTL_ALL]
    verilator_f = os.path.join(PROJECT_ROOT, "scripts", "verilator_small.f")

    cmd = (["verilator", "--binary", "-f", verilator_f, tb_path]
           + rtl_paths + ["--top-module", "tb_top"])

    print("  Compiling with Verilator (SIM_SMALL)...")
    result = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  COMPILE FAILED:\n{result.stderr[:5000]}")
        return False
    print("  Compilation OK.")
    return True


def run_simulation():
    """Run the compiled simulation."""
    binary = os.path.join(OBJ_DIR, "Vtb_top")
    if not os.path.exists(binary):
        print(f"  ERROR: binary not found: {binary}")
        return False

    print("  Running simulation...")
    try:
        result = subprocess.run([binary], cwd=PROJECT_ROOT,
                                capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        print("  FAIL: Simulation timed out (60s)")
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

def read_hex_dump(filepath):
    """Read a hex dump file into a list of ints.

    Supports two formats:
      - Plain: one 64-char hex value per line
      - Sparse: @ADDR DATA  (address + space + hex value)
    For sparse format, fills gaps with zeros.
    """
    # Peek at file to detect format
    with open(filepath, 'r') as f:
        first_line = ''
        for first_line in f:
            first_line = first_line.strip()
            if first_line:
                break

    if first_line.startswith('@'):
        # Sparse format: @addr data — preserve absolute addressing
        entries = {}
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or not line.startswith('@'):
                    continue
                parts = line.split(None, 1)
                addr = int(parts[0][1:], 16)  # strip '@'
                val = int(parts[1], 16)
                entries[addr] = val
        if not entries:
            return []
        max_addr = max(entries)
        words = [0] * (max_addr + 1)
        for addr, val in entries.items():
            words[addr] = val
        return words
    else:
        # Plain format
        words = []
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    words.append(int(line, 16))
        return words


def extract_int16_from_256bit(word_val, element_idx):
    """Extract a 16-bit element from a 256-bit word."""
    return (word_val >> (element_idx * 16)) & 0xFFFF


def extract_matrix_from_uram(uram_words, base_row, num_rows, num_col_words, col_words_total):
    """Extract a matrix of INT16 values from URAM dump.

    URAM layout: mem[row * col_words_total + col_word] = 256-bit word
    Each 256-bit word has 16 INT16 elements.
    """
    mat = []
    for r in range(num_rows):
        row = []
        for cw in range(num_col_words):
            word_idx = (base_row + r) * col_words_total + cw
            word_val = uram_words[word_idx] if word_idx < len(uram_words) else 0
            for e in range(WE):
                row.append(extract_int16_from_256bit(word_val, e))
        mat.append(row)
    return mat


def extract_matrix_from_hbm(hbm_words, base_addr, num_rows, stride, num_cols):
    """Extract a matrix of INT16 values from HBM dump."""
    mat = []
    words_per_row = (num_cols + WE - 1) // WE
    for r in range(num_rows):
        row = []
        for w in range(words_per_row):
            addr = base_addr + r * stride + w
            word_val = hbm_words[addr] if addr < len(hbm_words) else 0
            for e in range(WE):
                col = w * WE + e
                if col < num_cols:
                    row.append(extract_int16_from_256bit(word_val, e))
        mat.append(row)
    return mat


def _fp16_close(a_bits, b_bits, rel_tol=0.01, abs_tol=0.002):
    """Check if two FP16 bit patterns are close enough.

    Returns (is_close, rel_err, abs_err).
    Uses hybrid tolerance: match if abs_err <= abs_tol OR rel_err <= rel_tol.
    This prevents false mismatches on tiny values near zero where relative
    error is meaningless (e.g. 0.0 vs -0.001).
    """
    a = float(np.uint16(a_bits).view(np.float16))
    b = float(np.uint16(b_bits).view(np.float16))
    if np.isnan(a) or np.isnan(b):
        return False, float('inf'), float('inf')
    if a == b:
        return True, 0.0, 0.0
    abs_err = abs(a - b)
    mag = max(abs(a), abs(b), 1e-10)
    rel_err = abs_err / mag
    close = (abs_err <= abs_tol) or (rel_err <= rel_tol)
    return close, rel_err, abs_err


def compare_matrices(golden, rtl, name, f_out, rel_tol=0.01, abs_tol=0.002):
    """Compare two matrices element-by-element with hybrid tolerance.

    Uses both relative and absolute tolerance.
    An element matches if EITHER tolerance is satisfied.
    """
    ok = mis = exact = 0
    rows_g = len(golden)
    cols_g = len(golden[0]) if rows_g > 0 else 0
    rows_r = len(rtl)
    cols_r = len(rtl[0]) if rows_r > 0 else 0

    if rows_g != rows_r or cols_g != cols_r:
        f_out.write(f"  {name}: SHAPE MISMATCH golden [{rows_g}x{cols_g}] vs rtl [{rows_r}x{cols_r}]\n")
        return 0, rows_g * cols_g

    max_rel = 0.0
    max_abs = 0.0
    for r in range(rows_g):
        for c in range(cols_g):
            gv = golden[r][c] & 0xFFFF
            rv = rtl[r][c] & 0xFFFF
            if gv == rv:
                ok += 1
                exact += 1
            else:
                close, rel_err, abs_err = _fp16_close(gv, rv, rel_tol=rel_tol, abs_tol=abs_tol)
                max_rel = max(max_rel, rel_err)
                max_abs = max(max_abs, abs_err)
                if close:
                    ok += 1
                else:
                    mis += 1
                    if mis <= 200:
                        f_out.write(f"  {name} [{r}][{c}]: golden={gv:04x} rtl={rv:04x} MISMATCH (rel={rel_err:.4f} abs={abs_err:.6f})\n")

    total = ok + mis
    f_out.write(f"  {name}: {ok}/{total} match ({exact} exact, max_rel={max_rel:.6f}, max_abs={max_abs:.6f}, tol={rel_tol})\n")
    return ok, mis


def write_rtl_comparison(g):
    """Read RTL dumps and compare against golden model."""
    uram_path = os.path.join(TEST_DATA_DIR, "uram_dump.hex")
    flush_path = os.path.join(TEST_DATA_DIR, "hbm_flush_dump.hex")

    if not os.path.exists(uram_path) or not os.path.exists(flush_path):
        print("  ERROR: dump files not found")
        return

    uram_words = read_hex_dump(uram_path)
    flush_words = read_hex_dump(flush_path)

    total_ok = total_mis = 0

    with open(RTL_OUT, 'w') as f:
        f.write("=" * 60 + "\n")
        f.write("SIM_SMALL INTEGRATION TEST — RTL vs GOLDEN COMPARISON\n")
        f.write("=" * 60 + "\n\n")

        # The final state after S_FFN_RES_FL is the flushed residual2 in flush HBM
        # at ACT_BASE + ACT_EMBED_OFFSET

        # Check final output: residual2 in flush HBM
        f.write("--- Final Output: Residual 2 (flush HBM) ---\n")
        rtl_res2 = extract_matrix_from_hbm(
            flush_words, ACT_BASE + ACT_EMBED_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_matrices(g['residual2'], rtl_res2, 'residual2', f)
        total_ok += ok; total_mis += mis

        # Check intermediate stages that survive in flush HBM at end of simulation
        # Q is overwritten by attn_concat heads, so compare attn_concat instead
        # K survives at KV_BASE, V survives at KV_BASE + KV_V_OFFSET
        # Proj survives at ACT_BASE + ACT_ATTN_OFFSET
        # LN2 survives at ACT_BASE + ACT_TEMP_OFFSET

        f.write("\n--- Intermediate: K (KV cache) ---\n")
        rtl_K = extract_matrix_from_hbm(
            flush_words, KV_BASE, BT, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_matrices(g['K'], rtl_K, 'K', f)
        total_ok += ok; total_mis += mis

        f.write("\n--- Intermediate: V (KV cache) ---\n")
        rtl_V = extract_matrix_from_hbm(
            flush_words, KV_BASE + KV_V_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_matrices(g['V'], rtl_V, 'V', f)
        total_ok += ok; total_mis += mis

        f.write("\n--- Intermediate: LN2 (at ACT_TEMP_OFFSET) ---\n")
        rtl_ln2 = extract_matrix_from_hbm(
            flush_words, ACT_BASE + ACT_TEMP_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_matrices(g['ln2_out'], rtl_ln2, 'ln2_out', f)
        total_ok += ok; total_mis += mis

        # Check URAM contents (final state = residual2 before flush, or cleared)
        # After FFN_RES_FL completes, URAM still has residual2 data
        f.write("\n--- URAM Contents (should be residual2) ---\n")
        rtl_uram_res2 = extract_matrix_from_uram(
            uram_words, 0, BT, MODEL_STRIDE, URAM_COL_WORDS)
        ok, mis = compare_matrices(g['residual2'], rtl_uram_res2, 'uram_residual2', f)
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
    else:
        print(f"  {total_mis} element(s) mismatched (see {RTL_OUT})")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    data_only = '--data-only' in sys.argv

    print("=" * 60)
    print("  SIM_SMALL Integration Test (HBM Architecture)")
    print(f"  BT={BT}, MODEL_DIM={MODEL_DIM}, F_DIM={F_DIM}, TILE_SIZE={TILE_SIZE}")
    print(f"  WEIGHT_BASE={WEIGHT_BASE}, ACT_BASE={ACT_BASE}, LAYER_SIZE={LAYER_SIZE}")
    print("=" * 60)

    # Generate weights and embeddings (FP16 bit patterns)
    weights = generate_weights(seed=SEED)

    rng_embed = np.random.RandomState(SEED + 2)
    embed_fp16 = rng_embed.uniform(-0.5, 0.5, (BT, MODEL_DIM)).astype(np.float16)
    embed_fp16 = embed_fp16.view(np.uint16).astype(int).tolist()

    # Run golden model
    print("\n  Running golden model...")
    g = compute_golden(embed_fp16, weights)
    write_golden(g)

    # Generate hex files for testbench
    print("  Generating HBM hex files...")
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
    write_rtl_comparison(g)
    print("\nDone.")


if __name__ == "__main__":
    main()
