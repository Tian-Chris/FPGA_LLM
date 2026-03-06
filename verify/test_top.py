#!/usr/bin/env python3
"""SIM_SMALL integration test: full attention + FFN pipeline with HBM architecture.

Generates random weights and input activations, runs the golden model matching
the RTL's HBM data path (INT16 preserved between stages, no INT8 truncation),
writes hex files for testbench preloading, compiles and runs the simulation,
then compares RTL dump output against golden intermediates.

Key HBM architecture differences from BRAM:
  - INT16 preserved between matmul stages (no INT8 truncation via BRAM reads)
  - Softmax UINT16 output written natively to URAM (no zero-extension)
  - LayerNorm INT16 output written natively to URAM (no zero-extension)
  - Both residual adds read original embeddings from DMA HBM
  - act_base != 0 to separate weight/activation address spaces in sim HBMs
"""

import math
import os
import sys
import random
import struct
import subprocess

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.golden.common import int8, int16, int32, saturate_int16
from verify.golden.matmul_engine import matmul_golden
from verify.golden.softmax import softmax_golden
from verify.golden.layernorm import layernorm_golden
from verify.golden.activation import relu_golden
from verify.golden.residual_add import residual_add_golden

# ---------------------------------------------------------------------------
# SIM_SMALL Parameters (must match defines.vh under SIM_SMALL)
# ---------------------------------------------------------------------------
MODEL_DIM     = 64
NUM_HEADS     = 2
HEAD_DIM      = MODEL_DIM // NUM_HEADS   # 32
SCALE_SHIFT   = math.ceil(math.log2(HEAD_DIM)) >> 1  # $clog2(HEAD_DIM) >> 1
F_DIM         = 128
INPUT_DIM     = 64
MAX_SEQ_LEN   = 32
MAX_BATCH     = 1
NUM_ENC       = 1
TILE_SIZE     = 32
NUM_ENGINES   = 2

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
# HBM Memory Layout (word-addressed, 256-bit words, 16 INT16 elements each)
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
LAYER_SIZE        = LAYER_LN2_OFFSET + 2 * MODEL_DIM // WE       # 520

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
ACT_K_OFFSET     = 2 * MAX_SEQ_LEN * MODEL_DIM // WE
ACT_V_OFFSET     = 3 * MAX_SEQ_LEN * MODEL_DIM // WE
ACT_ATTN_OFFSET  = 4 * MAX_SEQ_LEN * MODEL_DIM // WE
ACT_TEMP_OFFSET  = 5 * MAX_SEQ_LEN * MODEL_DIM // WE       # LN staging for pre-norm
ACT_FFN_OFFSET   = 0

# Directories
TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
RTL_DIR       = os.path.join(PROJECT_ROOT, "rtl")
TB_DIR        = os.path.join(PROJECT_ROOT, "tb")
OBJ_DIR       = os.path.join(PROJECT_ROOT, "obj_dir")

GOLDEN_OUT = os.path.join(PROJECT_ROOT, "verify", "llm_golden.txt")
RTL_OUT    = os.path.join(PROJECT_ROOT, "verify", "llm_rtl.txt")

RTL_ALL = [
    "bram_controller.v", "mac_unit.v", "agu.v", "matmul_engine.v",
    "mem_arbiter.v", "tiling_engine.v", "softmax.v", "layernorm.v",
    "activation.v", "residual_add.v", "quant_layer.v", "host_interface.v",
    "positional_embedding.v", "fsm_controller.v", "sim_hbm_port.v",
    "uram_accum_buf.v", "tile_loader.v", "uram_flush.v", "act_dma.v",
    "uram_nm_adapter.v", "top_level.v",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def hex16(val):
    return f"{val & 0xFFFF:04x}"


def pack_int16_to_256bit(elements):
    """Pack up to 16 INT16 values into a 256-bit hex string (little-endian element order).

    Element 0 occupies bits [15:0], element 1 occupies bits [31:16], etc.
    The hex string represents the full 256-bit value with MSB on the left.
    """
    word = 0
    for i, v in enumerate(elements):
        word |= (v & 0xFFFF) << (i * 16)
    return f"{word:064x}"


def pack_int8_to_256bit_as_int16(elements):
    """Pack up to 16 INT8 values sign-extended to INT16 into a 256-bit hex string."""
    int16_vals = [int16(int8(v)) for v in elements]
    return pack_int16_to_256bit(int16_vals)


def write_hex_file(filepath, words):
    """Write a list of 64-char hex strings (256-bit words) to a file with @addr directives."""
    with open(filepath, 'w') as f:
        for addr, word in enumerate(words):
            if word != '0' * 64:
                f.write(f"@{addr:08x} {word}\n")


def pack_matrix_int8_as_int16(mat, rows, cols, base_addr, stride, mem):
    """Pack INT8 matrix (sign-extended to INT16) into 256-bit HBM words.

    Row r is stored at HBM word addresses [base_addr + r*stride .. base_addr + r*stride + cols/WE - 1].
    """
    for r in range(rows):
        for w in range(cols // WE):
            elements = []
            for e in range(WE):
                col = w * WE + e
                if col < cols:
                    elements.append(int16(int8(mat[r][col])))
                else:
                    elements.append(0)
            addr = base_addr + r * stride + w
            mem[addr] = pack_int16_to_256bit(elements)


def pack_matrix_int16(mat, rows, cols, base_addr, stride, mem):
    """Pack INT16 matrix into 256-bit HBM words."""
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
            mem[addr] = pack_int16_to_256bit(elements)


def pack_ln_params(gamma, beta, base_addr, mem):
    """Pack LN gamma/beta pairs into 256-bit words.

    Each 16-bit element = {beta[7:0], gamma[7:0]}.
    """
    dim = len(gamma)
    for w in range(dim // WE):
        elements = []
        for e in range(WE):
            idx = w * WE + e
            if idx < dim:
                g = gamma[idx] & 0xFF
                b = beta[idx] & 0xFF
                elements.append((b << 8) | g)
            else:
                elements.append(0)
        addr = base_addr + w
        mem[addr] = pack_int16_to_256bit(elements)


# ---------------------------------------------------------------------------
# Weight Generation (matches transformer.py generate_random_weights)
# ---------------------------------------------------------------------------

def generate_weights(seed=42):
    """Generate INT8 weights for one encoder layer.

    Use small range [-4, 3] to avoid saturation through the pipeline:
    - QKV: embed[-2,1] * weight[-4,3] * 32 dims = max 256 per element
    - Scores: Q[-256,255] * K[-256,255] * 32 dims = max 2M (fits INT32, saturates INT16)
    - Softmax: produces [0, 255] UINT8 -> UINT16
    - Attn_out: probs[0,255] * V[-256,255] * 4 seqs = max 260K -> saturates to INT16
    For full saturation avoidance, gamma/beta also kept small.
    """
    rng = random.Random(seed)

    def rand_mat(rows, cols):
        return [[rng.randint(-4, 3) for _ in range(cols)] for _ in range(rows)]

    def rand_vec(dim):
        return [rng.randint(-4, 3) for _ in range(dim)]

    w = {}
    # Frontend projection (unused in our test, but consumes RNG state)
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
# Tiled Matmul (INT16 inputs, matching HBM architecture)
# ---------------------------------------------------------------------------

def tiled_matmul_int16(mat_a, mat_b, tile_size):
    """Tiled matmul with INT16 inputs (no INT8 truncation).

    Matches the HBM architecture where tile_loader provides full INT16 data.
    """
    M = len(mat_a)
    K = len(mat_a[0])
    N = len(mat_b[0])

    result = [[0] * N for _ in range(M)]

    for ti in range(0, M, tile_size):
        rows = min(tile_size, M - ti)
        for tj in range(0, N, tile_size):
            cols = min(tile_size, N - tj)

            # INT16 inputs (no int8 truncation!)
            tile_a = [[int16(mat_a[ti + r][k]) for k in range(K)] for r in range(rows)]
            tile_b = [[int16(mat_b[k][tj + c]) for c in range(cols)] for k in range(K)]

            # matmul_golden does INT16*INT16 -> INT32 accum -> INT16 saturate
            tile_c = matmul_golden(tile_a, tile_b, rows)

            for r in range(rows):
                for c in range(cols):
                    result[ti + r][tj + c] = tile_c[r][c]

    return result


def tiled_matmul_int8(mat_a_int8, mat_b_int8, tile_size):
    """Tiled matmul with INT8 inputs (for first matmul where inputs are actually INT8).

    Inputs are INT8 range, sign-extended to INT16 for multiplication.
    This matches the initial QKV where embeddings and weights are both INT8 in HBM,
    read as INT16 (sign-extended).
    """
    M = len(mat_a_int8)
    K = len(mat_a_int8[0])
    N = len(mat_b_int8[0])

    result = [[0] * N for _ in range(M)]

    for ti in range(0, M, tile_size):
        rows = min(tile_size, M - ti)
        for tj in range(0, N, tile_size):
            cols = min(tile_size, N - tj)

            # INT8 sign-extended to INT16 (matches HBM storage)
            tile_a = [[int16(int8(mat_a_int8[ti + r][k])) for k in range(K)] for r in range(rows)]
            tile_b = [[int16(int8(mat_b_int8[k][tj + c])) for c in range(cols)] for k in range(K)]

            tile_c = matmul_golden(tile_a, tile_b, rows)

            for r in range(rows):
                for c in range(cols):
                    result[ti + r][tj + c] = tile_c[r][c]

    return result


def _transpose(mat):
    rows = len(mat)
    cols = len(mat[0])
    return [[mat[r][c] for r in range(rows)] for c in range(cols)]


# ---------------------------------------------------------------------------
# Golden Model (HBM architecture)
# ---------------------------------------------------------------------------

def compute_golden(embed_int8, weights):
    """Run the full encoder layer golden model for GPT-2 pre-norm architecture.

    GPT-2 Pre-Norm ordering:
      LN1 → QKV → attention → proj → residual1 → LN2 → FFN1 → act → FFN2 → residual2

    Key architecture notes:
    - LN1 reads embeddings from URAM (preloaded), writes LN output back to URAM
    - LN output flushed to ACT_TEMP for QKV matmul input
    - Residual1: proj + original embeddings
    - LN2 reads residual1 from URAM, writes to URAM, flushed to ACT_TEMP
    - Residual2: ffn2 + embed (DMA HBM still has original embeddings)
    """
    g = {}
    g['embed_int8'] = embed_int8

    # Embed stored as INT16 in HBM (sign-extended from INT8)
    embed_int16 = [[int16(int8(v)) for v in row] for row in embed_int8]
    g['embed_int16'] = embed_int16

    # ------------------------------------------------------------------
    # Step 0: LN1 (reads embeddings from URAM, params from LN1 weights)
    # ------------------------------------------------------------------
    ln1_out = []
    for t in range(BT):
        normed = layernorm_golden(
            embed_int16[t], weights['gamma1'], weights['beta1'], MODEL_DIM
        )
        ln1_out.append(normed)
    g['ln1_out'] = ln1_out

    # Step 1: flush LN1 → ACT_TEMP (then QKV reads from ACT_TEMP)

    # ------------------------------------------------------------------
    # Step 2: QKV projections (read from ACT_TEMP = ln1_out)
    # ln1_out is INT16 (native LN output), weights are INT8 sign-extended
    # ------------------------------------------------------------------
    Q = tiled_matmul_int16(ln1_out, weights['W_q'], TILE_SIZE)
    K = tiled_matmul_int16(ln1_out, weights['W_k'], TILE_SIZE)
    V = tiled_matmul_int16(ln1_out, weights['W_v'], TILE_SIZE)
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
        scores_h = tiled_matmul_int16(Q_h, K_h_T, TILE_SIZE)

        probs_h = [softmax_golden(scores_h[t], scale_shift=SCALE_SHIFT, row_idx=t)
                   for t in range(BT)]

        attn_h = tiled_matmul_int16(probs_h, V_h, TILE_SIZE)

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
    attn_proj = tiled_matmul_int16(attn_concat, weights['W_o'], TILE_SIZE)
    g['attn_proj'] = attn_proj

    # ------------------------------------------------------------------
    # Step 5: Residual1 = proj + original embeddings
    # proj from URAM, embed from DMA HBM (original INT16 embeddings)
    # ------------------------------------------------------------------
    residual1 = [residual_add_golden(embed_int16[t], attn_proj[t]) for t in range(BT)]
    g['residual1'] = residual1

    # Step 6: flush residual1 → ACT_EMBED

    # ------------------------------------------------------------------
    # Step 7: LN2 (reads residual1 from URAM, params from LN2 weights)
    # ------------------------------------------------------------------
    ln2_out = []
    for t in range(BT):
        normed = layernorm_golden(
            residual1[t], weights['gamma2'], weights['beta2'], MODEL_DIM
        )
        ln2_out.append(normed)
    g['ln2_out'] = ln2_out

    # Step 8: flush LN2 → ACT_TEMP

    # ------------------------------------------------------------------
    # Step 9: FFN1 (read from ACT_TEMP = ln2_out)
    # ------------------------------------------------------------------
    ffn1 = tiled_matmul_int16(ln2_out, weights['W_ffn1'], TILE_SIZE)
    g['ffn1'] = ffn1

    # ------------------------------------------------------------------
    # Step 10: ReLU
    # ------------------------------------------------------------------
    ffn_act = [[relu_golden(v) for v in row] for row in ffn1]
    g['ffn_act'] = ffn_act

    # Step 11: flush act → ACT_FFN

    # ------------------------------------------------------------------
    # Step 12: FFN2
    # ------------------------------------------------------------------
    ffn2 = tiled_matmul_int16(ffn_act, weights['W_ffn2'], TILE_SIZE)
    g['ffn2'] = ffn2

    # ------------------------------------------------------------------
    # Step 13: Residual2 = ffn2 + original embeddings
    # ffn2 from URAM, embed from DMA HBM (original embeddings, never updated)
    # ------------------------------------------------------------------
    residual2 = [residual_add_golden(embed_int16[t], ffn2[t]) for t in range(BT)]
    g['residual2'] = residual2

    # Step 14: flush residual2 → ACT_EMBED
    # Step 15: BT_END

    return g


# ---------------------------------------------------------------------------
# HBM Hex File Generation
# ---------------------------------------------------------------------------

def generate_hex_files(weights, embed_int8):
    """Generate hex files for testbench $readmemh preloading."""
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    # Weight HBM: INT8 weights sign-extended to INT16
    wgt_mem = {}

    # W_q at LAYER_WQ_OFFSET, stride=MODEL_STRIDE
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

    # LN1 params at LAYER_LN1_OFFSET
    pack_ln_params(weights['gamma1'], weights['beta1'],
                   WEIGHT_BASE + LAYER_LN1_OFFSET, wgt_mem)
    # LN2 params at LAYER_LN2_OFFSET
    pack_ln_params(weights['gamma2'], weights['beta2'],
                   WEIGHT_BASE + LAYER_LN2_OFFSET, wgt_mem)

    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_wgt.hex"),
                   [wgt_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # Activation HBM: INT8 embeddings sign-extended to INT16
    act_mem = {}
    embed_int16 = [[int16(int8(v)) for v in row] for row in embed_int8]
    pack_matrix_int16(embed_int16, BT, MODEL_DIM,
                      ACT_BASE + ACT_EMBED_OFFSET, MODEL_STRIDE, act_mem)

    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_act.hex"),
                   [act_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # DMA HBM: LN params (weight space) + embeddings (activation space)
    dma_mem = {}

    # LN1 params at layer_wgt_base + LAYER_LN1_OFFSET
    pack_ln_params(weights['gamma1'], weights['beta1'],
                   WEIGHT_BASE + LAYER_LN1_OFFSET, dma_mem)
    # LN2 params at layer_wgt_base + LAYER_LN2_OFFSET
    pack_ln_params(weights['gamma2'], weights['beta2'],
                   WEIGHT_BASE + LAYER_LN2_OFFSET, dma_mem)

    # Embeddings at act_base + ACT_EMBED_OFFSET
    pack_matrix_int16(embed_int16, BT, MODEL_DIM,
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
            ('embed_int16', 'Input embeddings (INT16)'),
            ('ln1_out', 'LN1 output (pre-norm)'),
            ('Q', 'Q projection'),
            ('K', 'K projection'),
            ('V', 'V projection'),
            ('scores', 'Attention scores'),
            ('probs_uint16', 'Softmax probs (UINT16)'),
            ('attn_out', 'Attention output'),
            ('attn_proj', 'Output projection'),
            ('residual1', 'Residual 1 (embed + proj)'),
            ('ln2_out', 'LN2 output (pre-norm)'),
            ('ffn1', 'FFN1 output'),
            ('ffn_act', 'ReLU output'),
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
    """Read a hex dump file (one 64-char hex per line) into a list of ints."""
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


def compare_matrices(golden, rtl, name, f_out):
    """Compare two matrices element-by-element. Return (ok, mismatch) counts."""
    ok = mis = 0
    rows_g = len(golden)
    cols_g = len(golden[0]) if rows_g > 0 else 0
    rows_r = len(rtl)
    cols_r = len(rtl[0]) if rows_r > 0 else 0

    if rows_g != rows_r or cols_g != cols_r:
        f_out.write(f"  {name}: SHAPE MISMATCH golden [{rows_g}x{cols_g}] vs rtl [{rows_r}x{cols_r}]\n")
        return 0, rows_g * cols_g

    for r in range(rows_g):
        for c in range(cols_g):
            gv = golden[r][c] & 0xFFFF
            rv = rtl[r][c] & 0xFFFF
            if gv == rv:
                ok += 1
            else:
                mis += 1
                if mis <= 120:  # Limit verbose output
                    f_out.write(f"  {name} [{r}][{c}]: golden={gv:04x} rtl={rv:04x} MISMATCH\n")

    f_out.write(f"  {name}: {ok}/{ok+mis} match\n")
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

        # Check intermediate stages from flush HBM
        # After QKV flush, Q is at ACT_BASE + ACT_Q_OFFSET (but gets overwritten by later flushes)
        # We can only check what's in flush HBM at the END of simulation
        # The last flush is FFN_RES_FL which writes residual2 at ACT_BASE + ACT_EMBED_OFFSET

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

    # Generate weights and embeddings
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
    print("  Generating HBM hex files...")
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
    write_rtl_comparison(g)
    print("\nDone.")


if __name__ == "__main__":
    main()
