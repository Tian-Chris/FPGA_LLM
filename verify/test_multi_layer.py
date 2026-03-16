#!/usr/bin/env python3
"""Multi-layer GPT-2 co-simulation test.

Extends test_top_1k.py to run NUM_LAYERS encoder layers, verifying the FSM
layer loop, URAM clear, weight base advancement, and end-to-end data flow.

Key differences from test_top_1k.py (single-layer):
  - Generates weights for multiple layers
  - Packs all layers' weights into weight HBM at layer_idx * LAYER_SIZE offsets
  - DMA HBM gets ALL layers' LN params
  - Golden model loops over layers with correct skip connections
  - SIM_HBM_DEPTH = 2^21 to fit 2+ layers of weights + activations
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

from verify.test_top import (
    pack_int16_to_256bit, pack_int8_to_256bit_as_int16,
    write_hex_file, pack_matrix_int8_as_int16, pack_matrix_int16,
    pack_ln_params,
    read_hex_dump, extract_int16_from_256bit,
    extract_matrix_from_hbm, extract_matrix_from_uram,
    compare_matrices, hex16,
)

from verify.test_top_1k import tiled_matmul_int16_numpy, _transpose

# ---------------------------------------------------------------------------
# Parameters (production dimensions, multi-layer)
# ---------------------------------------------------------------------------
MODEL_DIM     = 1024
NUM_HEADS     = 16
HEAD_DIM      = MODEL_DIM // NUM_HEADS   # 64
SCALE_SHIFT   = math.ceil(math.log2(HEAD_DIM)) >> 1  # 3
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
BUS_ELEMS = 16
WE = BUS_ELEMS
URAM_ROWS = 1024
URAM_COLS = 4096
URAM_COL_WORDS = URAM_COLS // BUS_ELEMS  # 256

NUM_LAYERS = int(os.environ.get('NUM_LAYERS', '2'))
# SIM_HBM_DEPTH computed after LAYER_SIZE is defined (below)

SEED = 42

# Matmul accumulator right-shift constants (must match defines.vh)
MM_SHIFT_QKV       = 7
MM_SHIFT_PROJ      = 7
MM_SHIFT_FFN1      = 7
MM_SHIFT_FFN2      = 9
MM_SHIFT_ATT_SCORE = 3
MM_SHIFT_ATT_OUT   = 4

# ---------------------------------------------------------------------------
# HBM Memory Layout
# ---------------------------------------------------------------------------
LAYER_WQ_OFFSET   = 0
LAYER_WK_OFFSET   = MODEL_DIM * MODEL_DIM // WE
LAYER_WV_OFFSET   = 2 * MODEL_DIM * MODEL_DIM // WE
LAYER_WO_OFFSET   = 3 * MODEL_DIM * MODEL_DIM // WE
LAYER_FFN1_OFFSET = 4 * MODEL_DIM * MODEL_DIM // WE
LAYER_FFN2_OFFSET = LAYER_FFN1_OFFSET + MODEL_DIM * F_DIM // WE
LAYER_LN1_OFFSET  = LAYER_FFN2_OFFSET + F_DIM * MODEL_DIM // WE
LAYER_LN2_OFFSET  = LAYER_LN1_OFFSET + 2 * MODEL_DIM // WE
LAYER_SIZE        = LAYER_LN2_OFFSET + 2 * MODEL_DIM // WE

MODEL_STRIDE = MODEL_DIM // WE   # 64
F_STRIDE     = F_DIM // WE       # 256

WEIGHT_BASE = 0
ACT_BASE    = NUM_LAYERS * LAYER_SIZE

ACT_EMBED_OFFSET = 0
ACT_Q_OFFSET     = MAX_SEQ_LEN * MODEL_DIM // WE
ACT_ATTN_OFFSET  = 4 * MAX_SEQ_LEN * MODEL_DIM // WE
ACT_TEMP_OFFSET  = 5 * MAX_SEQ_LEN * MODEL_DIM // WE
ACT_FFN_OFFSET   = ACT_Q_OFFSET  # reuse Q space (free after attention)

# KV cache: separate per-layer region in HBM
KV_V_OFFSET   = MAX_SEQ_LEN * MODEL_DIM // WE              # 8192
KV_LAYER_SIZE = 2 * MAX_SEQ_LEN * MODEL_DIM // WE          # 16384
KV_BASE       = ACT_BASE + 6 * MAX_SEQ_LEN * MODEL_DIM // WE  # after activation scratch

# Auto-size HBM depth: must fit weights + activations + KV cache for all layers
_KV_REGION = NUM_LAYERS * KV_LAYER_SIZE
_MIN_DEPTH = NUM_LAYERS * LAYER_SIZE + 6 * MAX_SEQ_LEN * MODEL_DIM // WE + _KV_REGION + 10000
SIM_HBM_DEPTH = 1 << max(21, _MIN_DEPTH.bit_length())

# Directories
TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
RTL_DIR       = os.path.join(PROJECT_ROOT, "rtl")
TB_DIR        = os.path.join(PROJECT_ROOT, "tb")
OBJ_DIR       = os.path.join(PROJECT_ROOT, "obj_dir")

GOLDEN_OUT = os.path.join(PROJECT_ROOT, "verify", "llm_golden_multi.txt")
RTL_OUT    = os.path.join(PROJECT_ROOT, "verify", "llm_rtl_multi.txt")

RTL_ALL = [
    "bram_controller.v", "mac_unit.v", "agu.v", "matmul_engine.v",
    "mem_arbiter.v", "tiling_engine.v", "softmax.v", "layernorm.v",
    "activation.v", "residual_add.v", "quant_layer.v", "host_interface.v",
    "positional_embedding.v", "fsm_controller.v", "sim_hbm_port.v",
    "uram_accum_buf.v", "tile_loader.v", "uram_flush.v", "act_dma.v",
    "uram_nm_adapter.v", "top_level.v",
]


def write_sparse_hex(filepath, mem_dict):
    """Write sparse hex file with @addr directives (avoids allocating full-depth list)."""
    with open(filepath, 'w') as f:
        for addr in sorted(mem_dict.keys()):
            word = mem_dict[addr]
            if word != '0' * 64:
                f.write(f"@{addr:08x} {word}\n")


# ---------------------------------------------------------------------------
# Weight Generation (multiple layers)
# ---------------------------------------------------------------------------

def generate_weights(num_layers, seed=42):
    """Generate INT8 weights for num_layers encoder layers.

    Uses the same RNG sequence as test_top_1k.py for layer 0, then extends
    for subsequent layers.
    """
    rng = random.Random(seed)

    def rand_mat(rows, cols):
        return [[rng.randint(-4, 3) for _ in range(cols)] for _ in range(rows)]

    def rand_vec(dim):
        return [rng.randint(-4, 3) for _ in range(dim)]

    # Frontend projection (consumes RNG state, same as test_top_1k.py)
    _W_proj = rand_mat(INPUT_DIM, MODEL_DIM)

    layers = []
    for layer_idx in range(num_layers):
        w = {}
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
        layers.append(w)

    return layers


# ---------------------------------------------------------------------------
# Golden Model (Multi-Layer)
# ---------------------------------------------------------------------------

def compute_one_layer(x_int16, weights, layer_idx):
    """Run one encoder layer of the GPT-2 pre-norm golden model.

    x_int16: input activations [BT x MODEL_DIM] as INT16
    Returns: (res2, intermediates_dict)
    """
    g = {}
    prefix = f"L{layer_idx}"

    # LN1
    print(f"    [{prefix}] LN1...")
    ln1_out = []
    for t in range(BT):
        normed = layernorm_golden(
            x_int16[t], weights['gamma1'], weights['beta1'], MODEL_DIM
        )
        ln1_out.append(normed)
    g[f'{prefix}_ln1'] = ln1_out

    # QKV
    print(f"    [{prefix}] QKV matmuls...")
    Q = tiled_matmul_int16_numpy(ln1_out, weights['W_q'], TILE_SIZE)
    K = tiled_matmul_int16_numpy(ln1_out, weights['W_k'], TILE_SIZE)
    V = tiled_matmul_int16_numpy(ln1_out, weights['W_v'], TILE_SIZE)
    g[f'{prefix}_K'] = K
    g[f'{prefix}_V'] = V

    # Multi-head attention
    print(f"    [{prefix}] Attention ({NUM_HEADS} heads)...")
    attn_concat = [[0] * MODEL_DIM for _ in range(BT)]

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

    # Output projection
    print(f"    [{prefix}] Output projection...")
    attn_proj = tiled_matmul_int16_numpy(attn_concat, weights['W_o'], TILE_SIZE)

    # Residual1 = x + attn_proj (skip connection from layer input)
    print(f"    [{prefix}] Residual 1...")
    residual1 = [residual_add_golden(x_int16[t], attn_proj[t]) for t in range(BT)]
    g[f'{prefix}_res1'] = residual1

    # LN2
    print(f"    [{prefix}] LN2...")
    ln2_out = []
    for t in range(BT):
        normed = layernorm_golden(
            residual1[t], weights['gamma2'], weights['beta2'], MODEL_DIM
        )
        ln2_out.append(normed)

    # FFN1
    print(f"    [{prefix}] FFN1 (1024x4096)...")
    ffn1 = tiled_matmul_int16_numpy(ln2_out, weights['W_ffn1'], TILE_SIZE)

    # ReLU
    print(f"    [{prefix}] ReLU...")
    ffn_act = [[relu_golden(v) for v in row] for row in ffn1]

    # FFN2
    print(f"    [{prefix}] FFN2 (4096x1024)...")
    ffn2 = tiled_matmul_int16_numpy(ffn_act, weights['W_ffn2'], TILE_SIZE)

    # Residual2 = res1 + ffn2 (skip connection from res1)
    print(f"    [{prefix}] Residual 2...")
    residual2 = [residual_add_golden(residual1[t], ffn2[t]) for t in range(BT)]
    g[f'{prefix}_res2'] = residual2

    return residual2, g


def compute_golden(embed_int8, layer_weights):
    """Run full multi-layer golden model."""
    all_intermediates = {}

    # Convert embeddings to INT16
    x = [[int16(int8(v)) for v in row] for row in embed_int8]
    all_intermediates['embed_int16'] = x

    for layer_idx in range(NUM_LAYERS):
        print(f"  === Layer {layer_idx} ===")
        x, layer_g = compute_one_layer(x, layer_weights[layer_idx], layer_idx)
        all_intermediates.update(layer_g)

    all_intermediates['final_output'] = x
    return all_intermediates


# ---------------------------------------------------------------------------
# Golden Model — Decode (Single Token with KV Cache)
# ---------------------------------------------------------------------------

def compute_golden_decode_layer(x_row, weights, layer_idx, K_cache, V_cache, cache_len):
    """Run one encoder layer in decode mode (BT=1, with KV cache).

    Args:
        x_row: 1D list [MODEL_DIM] — single token input
        weights: weight dict for this layer
        layer_idx: layer index (for logging)
        K_cache, V_cache: list-of-lists [cache_len × MODEL_DIM]
        cache_len: number of previously cached KV rows

    Returns: (res2_row, K_new_row, V_new_row)
    """
    embed = [x_row]  # 1 × MODEL_DIM
    cache_total = cache_len + 1

    # LN1
    ln1_out = [layernorm_golden(embed[0], weights['gamma1'], weights['beta1'], MODEL_DIM)]

    # Debug: print LN1 input and output for layer 1
    if layer_idx == 1:
        print(f"    [DBG] L1 decode LN1 input[:16] = {embed[0][:16]}")
        print(f"    [DBG] L1 decode LN1 output[:16] = {ln1_out[0][:16]}")

    # QKV projections (single token)
    Q = tiled_matmul_int16_numpy(ln1_out, weights['W_q'], TILE_SIZE)
    K_new = tiled_matmul_int16_numpy(ln1_out, weights['W_k'], TILE_SIZE)
    V_new = tiled_matmul_int16_numpy(ln1_out, weights['W_v'], TILE_SIZE)

    # Full K/V = cache ++ new
    K_full = K_cache + K_new  # cache_len+1 rows
    V_full = V_cache + V_new

    # Multi-head attention with full cache
    attn_concat = [[0] * MODEL_DIM]
    for h in range(NUM_HEADS):
        Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q]
        K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K_full]
        V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V_full]

        K_h_T = _transpose(K_h)
        scores_h = tiled_matmul_int16_numpy(Q_h, K_h_T, TILE_SIZE)  # 1 × cache_total

        # Causal mask: row_idx = cache_len allows cols 0..cache_len
        probs_h = [softmax_golden(scores_h[0], scale_shift=SCALE_SHIFT,
                                  row_idx=cache_len)]

        attn_h = tiled_matmul_int16_numpy(probs_h, V_h, TILE_SIZE)  # 1 × HEAD_DIM

        for d in range(HEAD_DIM):
            attn_concat[0][h*HEAD_DIM + d] = attn_h[0][d]

    # Output projection
    attn_proj = tiled_matmul_int16_numpy(attn_concat, weights['W_o'], TILE_SIZE)

    # Residual 1 = layer_input + proj
    residual1 = [residual_add_golden(embed[0], attn_proj[0])]

    # LN2
    ln2_out = [layernorm_golden(residual1[0], weights['gamma2'], weights['beta2'], MODEL_DIM)]

    # FFN1
    ffn1 = tiled_matmul_int16_numpy(ln2_out, weights['W_ffn1'], TILE_SIZE)

    # ReLU
    ffn_act = [[relu_golden(v) for v in row] for row in ffn1]

    # FFN2
    ffn2 = tiled_matmul_int16_numpy(ffn_act, weights['W_ffn2'], TILE_SIZE)

    # Residual 2 = residual1 + ffn2
    residual2 = [residual_add_golden(residual1[0], ffn2[0])]

    return residual2[0], K_new[0], V_new[0]


def compute_golden_decode(embed_row, layer_weights, kv_caches, cache_len):
    """Run single-token decode through all layers.

    Args:
        embed_row: 1D list [MODEL_DIM] — decode token embedding (INT16)
        layer_weights: list of weight dicts per layer
        kv_caches: list of (K_cache, V_cache) per layer
        cache_len: number of previously cached KV rows

    Returns: (output_row, updated_kv_caches, k_new_rows, v_new_rows)
    """
    x = embed_row
    new_caches = []
    k_news = []
    v_news = []

    for layer_idx in range(NUM_LAYERS):
        K_cache, V_cache = kv_caches[layer_idx]
        print(f"    [decode] Layer {layer_idx} (cache_len={cache_len})...")
        res2, k_new, v_new = compute_golden_decode_layer(
            x, layer_weights[layer_idx], layer_idx, K_cache, V_cache, cache_len)

        new_caches.append((K_cache + [k_new], V_cache + [v_new]))
        k_news.append(k_new)
        v_news.append(v_new)
        x = res2

    return x, new_caches, k_news, v_news


# ---------------------------------------------------------------------------
# HBM Hex File Generation (Multi-Layer)
# ---------------------------------------------------------------------------

def generate_decode_embed_hex(embed_int16_row, filename):
    """Pack a 1×MODEL_DIM INT16 embedding into MODEL_STRIDE 256-bit words and write hex."""
    words = []
    for w_idx in range(MODEL_STRIDE):
        elems = embed_int16_row[w_idx * WE : (w_idx + 1) * WE]
        words.append(pack_int16_to_256bit(elems))
    write_hex_file(os.path.join(TEST_DATA_DIR, filename), words)
    print(f"    Written {filename} ({len(words)} words)")


def generate_hex_files(layer_weights, embed_int8, decode_embeds=None):
    """Generate hex files for multi-layer testbench."""
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    # Weight HBM: all layers packed at layer_idx * LAYER_SIZE
    print("    Packing weight HBM (multi-layer)...")
    wgt_mem = {}

    for layer_idx in range(NUM_LAYERS):
        w = layer_weights[layer_idx]
        base = WEIGHT_BASE + layer_idx * LAYER_SIZE

        pack_matrix_int8_as_int16(w['W_q'], MODEL_DIM, MODEL_DIM,
                                  base + LAYER_WQ_OFFSET, MODEL_STRIDE, wgt_mem)
        pack_matrix_int8_as_int16(w['W_k'], MODEL_DIM, MODEL_DIM,
                                  base + LAYER_WK_OFFSET, MODEL_STRIDE, wgt_mem)
        pack_matrix_int8_as_int16(w['W_v'], MODEL_DIM, MODEL_DIM,
                                  base + LAYER_WV_OFFSET, MODEL_STRIDE, wgt_mem)
        pack_matrix_int8_as_int16(w['W_o'], MODEL_DIM, MODEL_DIM,
                                  base + LAYER_WO_OFFSET, MODEL_STRIDE, wgt_mem)
        pack_matrix_int8_as_int16(w['W_ffn1'], MODEL_DIM, F_DIM,
                                  base + LAYER_FFN1_OFFSET, F_STRIDE, wgt_mem)
        pack_matrix_int8_as_int16(w['W_ffn2'], F_DIM, MODEL_DIM,
                                  base + LAYER_FFN2_OFFSET, MODEL_STRIDE, wgt_mem)
        pack_ln_params(w['gamma1'], w['beta1'],
                       base + LAYER_LN1_OFFSET, wgt_mem)
        pack_ln_params(w['gamma2'], w['beta2'],
                       base + LAYER_LN2_OFFSET, wgt_mem)

    print(f"    Writing weight hex file ({len(wgt_mem)} non-zero words)...")
    write_sparse_hex(os.path.join(TEST_DATA_DIR, "hbm_wgt_multi.hex"), wgt_mem)

    # Activation HBM: INT8 embeddings sign-extended to INT16
    print("    Packing activation HBM...")
    act_mem = {}
    embed_int16 = [[int16(int8(v)) for v in row] for row in embed_int8]
    pack_matrix_int16(embed_int16, BT, MODEL_DIM,
                      ACT_BASE + ACT_EMBED_OFFSET, MODEL_STRIDE, act_mem)

    print("    Writing activation hex file...")
    write_sparse_hex(os.path.join(TEST_DATA_DIR, "hbm_act_multi.hex"), act_mem)

    # DMA HBM: LN params for ALL layers + initial embeddings
    print("    Packing DMA HBM (multi-layer LN params)...")
    dma_mem = {}

    for layer_idx in range(NUM_LAYERS):
        w = layer_weights[layer_idx]
        base = WEIGHT_BASE + layer_idx * LAYER_SIZE
        pack_ln_params(w['gamma1'], w['beta1'],
                       base + LAYER_LN1_OFFSET, dma_mem)
        pack_ln_params(w['gamma2'], w['beta2'],
                       base + LAYER_LN2_OFFSET, dma_mem)

    pack_matrix_int16(embed_int16, BT, MODEL_DIM,
                      ACT_BASE + ACT_EMBED_OFFSET, MODEL_STRIDE, dma_mem)

    print("    Writing DMA hex file...")
    write_sparse_hex(os.path.join(TEST_DATA_DIR, "hbm_dma_multi.hex"), dma_mem)

    # Decode embed hex files (if decode embeds provided)
    if decode_embeds:
        for i, de in enumerate(decode_embeds, 1):
            generate_decode_embed_hex(de, f"decode_embed_{i}.hex")

    print(f"  HBM hex files written ({NUM_LAYERS} layers, depth={SIM_HBM_DEPTH})")


# ---------------------------------------------------------------------------
# Golden File Writer
# ---------------------------------------------------------------------------

def write_golden(g):
    """Write golden values summary."""
    with open(GOLDEN_OUT, 'w') as f:
        f.write("=" * 60 + "\n")
        f.write(f"MULTI-LAYER TEST - GOLDEN REFERENCE ({NUM_LAYERS} layers)\n")
        f.write("=" * 60 + "\n")
        f.write(f"Config: BT={BT}, MODEL_DIM={MODEL_DIM}, F_DIM={F_DIM}, "
                f"NUM_HEADS={NUM_HEADS}, NUM_LAYERS={NUM_LAYERS}\n")
        f.write(f"WEIGHT_BASE={WEIGHT_BASE}, ACT_BASE={ACT_BASE}, LAYER_SIZE={LAYER_SIZE}\n\n")

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

        f.write("\n--- Input Embeddings ---\n")
        write_mat_summary('embed_int16', g['embed_int16'])

        for layer_idx in range(NUM_LAYERS):
            prefix = f"L{layer_idx}"
            f.write(f"\n{'='*40}\n")
            f.write(f"  Layer {layer_idx}\n")
            f.write(f"{'='*40}\n")

            for key, name in [
                (f'{prefix}_ln1', 'LN1 output'),
                (f'{prefix}_res1', 'Residual 1'),
                (f'{prefix}_res2', 'Residual 2'),
            ]:
                if key in g:
                    f.write(f"\n--- {name} ---\n")
                    write_mat_summary(key, g[key])

        f.write(f"\n--- Final Output (Layer {NUM_LAYERS-1} res2) ---\n")
        write_mat_summary('final_output', g['final_output'])

    print(f"  Golden written: {GOLDEN_OUT}")


# ---------------------------------------------------------------------------
# Testbench (reuses tb_top_1k.v with different hex files and params)
# ---------------------------------------------------------------------------

def write_testbench():
    """Write a multi-layer testbench with 3 phases: prefill + 2 decode tokens."""
    tb_path = os.path.join(TB_DIR, "tb_top_multi.v")
    TOTAL_KV_ROWS = SEQ_LEN + 2  # prefill rows + 2 decode rows
    with open(tb_path, 'w') as f:
        f.write(f"""`timescale 1ns / 1ps

`include "defines.vh"

// Multi-layer integration test — 3 phases:
//   Phase 1: Prefill (BT={SEQ_LEN}, decode_mode=0)
//   Phase 2: Decode token 1 (BT=1, decode_mode=1, cache_len={SEQ_LEN})
//   Phase 3: Decode token 2 (BT=1, decode_mode=1, cache_len={SEQ_LEN+1})

module tb_top_multi;

    parameter HBM_RD_LATENCY  = 2;
    parameter URAM_RD_LATENCY = 1;

    localparam AXI_AW = 32;
    localparam AXI_DW = 32;
    localparam TB_HBM_DEPTH = {SIM_HBM_DEPTH};

    localparam SEQ_LEN = {SEQ_LEN};
    localparam BATCH   = {BATCH};

    localparam WE              = 16;
    localparam URAM_COL_WORDS_L = 64;
    localparam URAM_COL_WORDS_HW = 256;
    localparam URAM_ROWS_L     = 1024;

    localparam MODEL_STRIDE_L = 64;
    localparam TOTAL_KV_ROWS  = {TOTAL_KV_ROWS};

    localparam WEIGHT_BASE = {WEIGHT_BASE};
    localparam ACT_BASE    = {ACT_BASE};
    localparam KV_BASE     = {KV_BASE};
    localparam OUTPUT_BASE = 32'h8000;

    reg clk, rst_n;

    reg  [AXI_AW-1:0]    s_axi_awaddr;
    reg                   s_axi_awvalid;
    wire                  s_axi_awready;
    reg  [AXI_DW-1:0]    s_axi_wdata;
    reg  [AXI_DW/8-1:0]  s_axi_wstrb;
    reg                   s_axi_wvalid;
    wire                  s_axi_wready;
    wire [1:0]            s_axi_bresp;
    wire                  s_axi_bvalid;
    reg                   s_axi_bready;
    reg  [AXI_AW-1:0]    s_axi_araddr;
    reg                   s_axi_arvalid;
    wire                  s_axi_arready;
    wire [AXI_DW-1:0]    s_axi_rdata;
    wire [1:0]            s_axi_rresp;
    wire                  s_axi_rvalid;
    reg                   s_axi_rready;
    wire                  irq_done;

    integer fi;
    integer dump_row, dump_col;
    integer dump_addr;
    integer dump_fd;
    integer mirror_r, mirror_c, mirror_addr;

    // Decode embed temp arrays
    reg [255:0] decode_embed_1 [0:MODEL_STRIDE_L-1];
    reg [255:0] decode_embed_2 [0:MODEL_STRIDE_L-1];
    integer de_i;

    initial clk = 0;
    always #5 clk = ~clk;

    diffusion_transformer_top #(
        .AXI_ADDR_WIDTH (AXI_AW),
        .AXI_DATA_WIDTH (AXI_DW),
        .SIM_HBM_DEPTH  (TB_HBM_DEPTH),
        .HBM_RD_LATENCY (HBM_RD_LATENCY),
        .URAM_RD_LATENCY(URAM_RD_LATENCY)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .irq_done       (irq_done)
    );

    task axi_write;
        input [AXI_AW-1:0] addr;
        input [AXI_DW-1:0] data;
        begin
            @(negedge clk);
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = data;
            s_axi_wstrb   = 4'hF;
            s_axi_wvalid  = 1'b1;
            s_axi_bready  = 1'b1;
            @(posedge clk); @(negedge clk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
            @(posedge clk); @(posedge clk);
            while (!s_axi_bvalid) @(posedge clk);
            @(posedge clk); @(negedge clk);
            s_axi_bready = 1'b0;
        end
    endtask

    integer uram_r, uram_c, uram_src;
    localparam URAM_EMBED_SRC = ACT_BASE;

    // =========================================================================
    // HBM + URAM Preloading
    // =========================================================================
    initial begin
        #1;
        $readmemh("verify/test_data/hbm_wgt_multi.hex", dut.u_hbm_pf_wgt.mem);
        $readmemh("verify/test_data/hbm_act_multi.hex", dut.u_hbm_pf_wgt.mem);
        $readmemh("verify/test_data/hbm_wgt_multi.hex", dut.u_hbm_pf_act.mem);
        $readmemh("verify/test_data/hbm_act_multi.hex", dut.u_hbm_pf_act.mem);
        $readmemh("verify/test_data/hbm_dma_multi.hex", dut.u_hbm_dma.mem);

        // Load decode embed arrays
        $readmemh("verify/test_data/decode_embed_1.hex", decode_embed_1);
        $readmemh("verify/test_data/decode_embed_2.hex", decode_embed_2);

        for (uram_r = 0; uram_r < SEQ_LEN; uram_r = uram_r + 1) begin
            for (uram_c = 0; uram_c < MODEL_STRIDE_L; uram_c = uram_c + 1) begin
                uram_src = URAM_EMBED_SRC + uram_r * MODEL_STRIDE_L + uram_c;
                dut.u_uram.mem[uram_r * URAM_COL_WORDS_HW + uram_c] =
                    dut.u_hbm_pf_act.mem[uram_src];
            end
        end

        $display("[%0t] tb_top_multi: HBM + URAM preloading complete", $time);
        $fflush();
    end

    // =========================================================================
    // Main Test Sequence: 3 Phases
    // =========================================================================
    initial begin
        $display("[%0t] tb_top_multi: simulation starting (3-phase decode test)", $time);
        $fflush();

        rst_n = 0;
        s_axi_awaddr  = 0; s_axi_awvalid = 0;
        s_axi_wdata   = 0; s_axi_wstrb   = 0; s_axi_wvalid = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0; s_axi_arvalid = 0; s_axi_rready = 0;

        #100;
        rst_n = 1;
        #100;

        // ============ PHASE 1: PREFILL ============
        $display("[%0t] === PHASE 1: PREFILL (seq=%0d, decode=0) ===", $time, SEQ_LEN);
        $fflush();
        axi_write(32'h08, BATCH);
        axi_write(32'h0C, SEQ_LEN);
        axi_write(32'h10, WEIGHT_BASE);
        axi_write(32'h14, ACT_BASE);
        axi_write(32'h18, OUTPUT_BASE);
        axi_write(32'h24, KV_BASE);
        axi_write(32'h1C, 32'd0);       // decode_mode = 0
        axi_write(32'h20, 32'd0);       // cache_len = 0

        axi_write(32'h00, 32'h1);       // START

        while (dut.u_fsm.state != S_DONE) @(posedge clk);
        $display("[%0t] PREFILL DONE", $time);
        $fflush();
        @(posedge clk); @(posedge clk);

        // ============ INJECT DECODE EMBED 1 ============
        for (de_i = 0; de_i < MODEL_STRIDE_L; de_i = de_i + 1) begin
            dut.u_hbm_pf_act.mem[ACT_BASE + de_i]  = decode_embed_1[de_i];
            dut.u_hbm_pf_wgt.mem[ACT_BASE + de_i]  = decode_embed_1[de_i];
            dut.u_hbm_dma.mem[ACT_BASE + de_i]      = decode_embed_1[de_i];
            dut.u_hbm_flush.mem[ACT_BASE + de_i]    = decode_embed_1[de_i];
            dut.u_uram.mem[0 * URAM_COL_WORDS_HW + de_i] = decode_embed_1[de_i];
        end
        $display("[%0t] Injected decode_embed_1", $time);
        $fflush();

        // ============ PHASE 2: DECODE TOKEN 1 ============
        $display("[%0t] === PHASE 2: DECODE TOKEN 1 (cache_len=%0d) ===", $time, SEQ_LEN);
        $fflush();
        axi_write(32'h0C, 32'd1);            // seq_len = 1
        axi_write(32'h1C, 32'd1);            // decode_mode = 1
        axi_write(32'h20, SEQ_LEN);          // cache_len = {SEQ_LEN}

        axi_write(32'h00, 32'h1);            // START

        while (dut.u_fsm.state != S_DONE) @(posedge clk);
        $display("[%0t] DECODE TOKEN 1 DONE", $time);
        $fflush();
        @(posedge clk); @(posedge clk);

        // Debug: dump decode 1 output (URAM row 0) and ACT_BASE row 0 from flush HBM
        dump_fd = $fopen("verify/test_data/dec1_output_dump.hex", "w");
        if (dump_fd != 0) begin
            $fwrite(dump_fd, "URAM_ROW0:\\n");
            for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                $fwrite(dump_fd, "%064h\\n",
                        dut.u_uram.mem[0 * URAM_COL_WORDS_HW + dump_col]);
            end
            $fwrite(dump_fd, "FLUSH_ACT_BASE_ROW0:\\n");
            for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                dump_addr = ACT_BASE + dump_col;
                $fwrite(dump_fd, "%064h\\n",
                        dut.u_hbm_flush.mem[dump_addr]);
            end
            // Also dump L1 K cache row 32 (first 2 words)
            $fwrite(dump_fd, "L1_K_ROW32:\\n");
            for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                dump_addr = KV_BASE + 1 * {KV_LAYER_SIZE} + 32 * MODEL_STRIDE_L + dump_col;
                $fwrite(dump_fd, "%064h\\n", dut.u_hbm_flush.mem[dump_addr]);
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped decode 1 intermediate output", $time);
            $fflush();
        end

        // Debug: display L1 K[32] first word from flush HBM
        $display("[%0t] DBG L1_K_row32_after_dec1: %h", $time,
                 dut.u_hbm_flush.mem[KV_BASE + 1 * {KV_LAYER_SIZE} + 32 * MODEL_STRIDE_L]);
        $fflush();

        // ============ INJECT DECODE EMBED 2 ============
        for (de_i = 0; de_i < MODEL_STRIDE_L; de_i = de_i + 1) begin
            dut.u_hbm_pf_act.mem[ACT_BASE + de_i]  = decode_embed_2[de_i];
            dut.u_hbm_pf_wgt.mem[ACT_BASE + de_i]  = decode_embed_2[de_i];
            dut.u_hbm_dma.mem[ACT_BASE + de_i]      = decode_embed_2[de_i];
            dut.u_hbm_flush.mem[ACT_BASE + de_i]    = decode_embed_2[de_i];
            dut.u_uram.mem[0 * URAM_COL_WORDS_HW + de_i] = decode_embed_2[de_i];
        end
        $display("[%0t] Injected decode_embed_2", $time);
        $fflush();

        // ============ PHASE 3: DECODE TOKEN 2 ============
        $display("[%0t] === PHASE 3: DECODE TOKEN 2 (cache_len=%0d) ===", $time, SEQ_LEN + 1);
        $fflush();
        axi_write(32'h20, SEQ_LEN + 1);      // cache_len = {SEQ_LEN + 1}

        axi_write(32'h00, 32'h1);            // START

        while (dut.u_fsm.state != S_DONE) @(posedge clk);
        $display("[%0t] DECODE TOKEN 2 DONE", $time);
        $fflush();

        $display("[%0t] TEST PASSED: All 3 phases completed", $time);
        $fflush();

        // ============ DUMP RESULTS ============

        // URAM dump (row 0 = decode token 2 output)
        dump_fd = $fopen("verify/test_data/uram_multi_dump.hex", "w");
        if (dump_fd != 0) begin
            for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                $fwrite(dump_fd, "%064h\\n",
                        dut.u_uram.mem[0 * URAM_COL_WORDS_HW + dump_col]);
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped URAM (1 row, %0d words)", $time, MODEL_STRIDE_L);
            $fflush();
        end

        // Sparse flush HBM dump:
        //   - Final decode output: ACT_BASE row 0 (1 row)
        //   - Per-layer KV caches: TOTAL_KV_ROWS rows (prefill + 2 decode)
        dump_fd = $fopen("verify/test_data/hbm_flush_multi_dump.hex", "w");
        if (dump_fd != 0) begin
            // Final output: ACT_BASE row 0 only (decode token 2 output)
            for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                dump_addr = ACT_BASE + dump_col;
                $fwrite(dump_fd, "@%08h %064h\\n", dump_addr,
                        dut.u_hbm_flush.mem[dump_addr]);
            end

            // Per-layer KV caches: all rows including decode rows
            for (fi = 0; fi < {NUM_LAYERS}; fi = fi + 1) begin
                // K cache (TOTAL_KV_ROWS rows)
                for (dump_row = 0; dump_row < TOTAL_KV_ROWS; dump_row = dump_row + 1) begin
                    for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                        dump_addr = KV_BASE + fi * {KV_LAYER_SIZE} + dump_row * MODEL_STRIDE_L + dump_col;
                        $fwrite(dump_fd, "@%08h %064h\\n", dump_addr,
                                dut.u_hbm_flush.mem[dump_addr]);
                    end
                end
                // V cache (TOTAL_KV_ROWS rows)
                for (dump_row = 0; dump_row < TOTAL_KV_ROWS; dump_row = dump_row + 1) begin
                    for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                        dump_addr = KV_BASE + fi * {KV_LAYER_SIZE} + {KV_V_OFFSET} + dump_row * MODEL_STRIDE_L + dump_col;
                        $fwrite(dump_fd, "@%08h %064h\\n", dump_addr,
                                dut.u_hbm_flush.mem[dump_addr]);
                    end
                end
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped sparse flush HBM (KV %0d rows/layer + decode output)", $time, TOTAL_KV_ROWS);
            $fflush();
        end

        #100;
        $finish;
    end

    // Compact FSM logging — phase + layer boundaries
    reg [4:0] prev_state;
    reg [7:0] prev_layer;
    initial begin prev_state = 0; prev_layer = 0; end

    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.u_fsm.layer_cnt !== prev_layer && dut.u_fsm.state != 0) begin
                $display("[%0t] === Layer %0d started (decode=%0d) ===",
                         $time, dut.u_fsm.layer_cnt, dut.u_fsm.decode_r);
                $display("[%0t] DBG_LAYER_CHG: layer=%0d decode=%0d w0=%h w5=%h w10=%h w20=%h w40=%h w63=%h",
                         $time, dut.u_fsm.layer_cnt, dut.u_fsm.decode_r,
                         dut.u_uram.mem[0], dut.u_uram.mem[5],
                         dut.u_uram.mem[10], dut.u_uram.mem[20],
                         dut.u_uram.mem[40], dut.u_uram.mem[63]);
                $fflush();
                prev_layer <= dut.u_fsm.layer_cnt;
            end
            prev_state <= dut.u_fsm.state;
        end
    end

    // Flush-to-Load Memory Mirroring
    reg uf_done_prev;
    reg [27:0] saved_flush_base;
    reg [27:0] saved_flush_stride;
    reg [9:0]  saved_flush_rows;
    reg [7:0]  saved_flush_cols;
    reg        flush_params_valid;

    initial begin
        uf_done_prev = 0;
        saved_flush_base = 0;
        saved_flush_stride = 0;
        saved_flush_rows = 0;
        saved_flush_cols = 0;
        flush_params_valid = 0;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.u_fsm.uram_flush_start) begin
                saved_flush_base   <= dut.u_fsm.uram_flush_hbm_base;
                saved_flush_stride <= dut.u_fsm.uram_flush_hbm_stride;
                saved_flush_rows   <= dut.u_fsm.uram_flush_num_rows;
                saved_flush_cols   <= dut.u_fsm.uram_flush_num_col_words;
                flush_params_valid <= 1'b1;
            end

            uf_done_prev <= dut.uf_done;
            if (dut.uf_done && !uf_done_prev && flush_params_valid) begin
                $display("[%0t] MIRROR: base=0x%08h rows=%0d cols=%0d stride=%0d layer=%0d step=%0d cache_len=%0d qkv=%0d data0=%h",
                         $time, saved_flush_base, saved_flush_rows, saved_flush_cols,
                         saved_flush_stride, dut.u_fsm.layer_cnt, dut.u_fsm.step_idx,
                         dut.u_fsm.cache_len_r, dut.u_fsm.qkv_phase,
                         dut.u_hbm_flush.mem[saved_flush_base]);
                for (mirror_r = 0; mirror_r <= saved_flush_rows; mirror_r = mirror_r + 1) begin
                    for (mirror_c = 0; mirror_c <= saved_flush_cols; mirror_c = mirror_c + 1) begin
                        mirror_addr = saved_flush_base + mirror_r * saved_flush_stride + mirror_c;
                        dut.u_hbm_pf_act.mem[mirror_addr] = dut.u_hbm_flush.mem[mirror_addr];
                        dut.u_hbm_pf_wgt.mem[mirror_addr] = dut.u_hbm_flush.mem[mirror_addr];
                        dut.u_hbm_dma.mem[mirror_addr]    = dut.u_hbm_flush.mem[mirror_addr];
                    end
                end
                // Debug: show first word at ACT_BASE after res2 flush
                if (saved_flush_base == ACT_BASE) begin
                    $display("[%0t] DBG_FLUSH_ACT: word0=%h word1=%h layer=%0d step=%0d",
                             $time,
                             dut.u_hbm_flush.mem[ACT_BASE],
                             dut.u_hbm_flush.mem[ACT_BASE+1],
                             dut.u_fsm.layer_cnt, dut.u_fsm.step_idx);
                end
                flush_params_valid <= 1'b0;
            end
        end
    end

    // HBM write probe: watch L1 K dec1 row (detect overwrites)
    localparam L1_K_DEC1_ADDR = KV_BASE + {KV_LAYER_SIZE} + {SEQ_LEN} * MODEL_STRIDE_L;
    reg [255:0] prev_l1k_dec1_word0;
    initial prev_l1k_dec1_word0 = 256'd0;
    always @(posedge clk) begin
        if (dut.u_hbm_flush.mem[L1_K_DEC1_ADDR] !== prev_l1k_dec1_word0) begin
            $display("[%0t] HBM_PROBE: L1_K_dec1[0] changed to %h (was %h) layer=%0d step=%0d",
                     $time, dut.u_hbm_flush.mem[L1_K_DEC1_ADDR], prev_l1k_dec1_word0,
                     dut.u_fsm.layer_cnt, dut.u_fsm.step_idx);
            prev_l1k_dec1_word0 <= dut.u_hbm_flush.mem[L1_K_DEC1_ADDR];
        end
    end

    // Timeout watchdog (scaled with layers, 3 phases)
    initial begin
        #{NUM_LAYERS * 800}000000000;
        $display("[%0t] ERROR: Simulation timeout!", $time);
        $fflush();
        $display("  FSM state: %0d", dut.u_fsm.state);
        $display("  Layer: %0d", dut.u_fsm.layer_cnt);
        $display("  Step idx: %0d", dut.u_fsm.step_idx);
        $display("  TEST FAILED: timeout");
        $fflush();
        $finish;
    end

endmodule
""")
    print(f"  Testbench written: {tb_path}")
    return tb_path


# ---------------------------------------------------------------------------
# Compile & Run
# ---------------------------------------------------------------------------

def write_verilator_flags():
    """Write verilator flags file for multi-layer test."""
    flags_path = os.path.join(PROJECT_ROOT, "scripts", "verilator_multi.f")
    with open(flags_path, 'w') as f:
        f.write("// Verilator flags for multi-layer test\n")
        f.write("+incdir+rtl\n")
        f.write("-DSIM_1K\n")
        f.write("--x-assign 0\n")
        f.write("--x-initial 0\n")
        f.write("-Wno-fatal\n")
        f.write("--timing\n")
        f.write("-j 0\n")
    return flags_path


def compile_design(tb_path, flags_path):
    """Compile with Verilator for multi-layer."""
    rtl_paths = [os.path.join(RTL_DIR, f) for f in RTL_ALL]

    cmd = (["verilator", "--binary", "-f", flags_path,
            f"-DSIM_NUM_LAYERS={NUM_LAYERS}",
            tb_path]
           + rtl_paths + ["--top-module", "tb_top_multi"])

    print(f"  Compiling with Verilator (NUM_ENC_LAYERS={NUM_LAYERS})...")
    result = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  COMPILE FAILED:\n{result.stderr[:5000]}")
        return False
    print("  Compilation OK.")
    return True


def run_simulation():
    """Run the compiled simulation, streaming output to avoid buffering."""
    binary = os.path.join(OBJ_DIR, "Vtb_top_multi")
    if not os.path.exists(binary):
        print(f"  ERROR: binary not found: {binary}")
        return False

    print(f"  Running simulation ({NUM_LAYERS} layers, may take a while)...")
    try:
        proc = subprocess.Popen([binary], cwd=PROJECT_ROOT,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True)

        passed = False
        for line in proc.stdout:
            line = line.rstrip()
            if any(k in line for k in ["Layer", "TEST", "ERROR", "Dumped",
                                        "DONE", "finish", "Simulation",
                                        "PHASE", "PREFILL", "DECODE", "Injected",
                                        "DBG", "MIRROR", "[LN", "QKV_MM", "HBM_PROBE"]):
                print(f"    {line}")
            if "TEST PASSED" in line:
                passed = True
        proc.wait(timeout=NUM_LAYERS * 600)
    except subprocess.TimeoutExpired:
        proc.kill()
        print(f"  FAIL: Simulation timed out ({NUM_LAYERS * 600}s)")
        return False

    # Clean up hex files after sim completes (free ~3 GB disk)
    for fn in ["hbm_wgt_multi.hex", "hbm_act_multi.hex", "hbm_dma_multi.hex",
                "decode_embed_1.hex", "decode_embed_2.hex"]:
        p = os.path.join(TEST_DATA_DIR, fn)
        if os.path.exists(p):
            os.remove(p)
            print(f"    Freed disk: removed {fn}")

    if not passed:
        print("  FAIL: TEST PASSED not in simulation output")
        return False
    return True


# ---------------------------------------------------------------------------
# RTL Dump Comparison
# ---------------------------------------------------------------------------

def read_sparse_hex_dump(filepath):
    """Read a sparse hex dump with @addr lines into a dict {addr: int_value}."""
    words = {}
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('@'):
                parts = line.split()
                addr = int(parts[0][1:], 16)
                words[addr] = int(parts[1], 16)
            elif line:
                # Sequential format fallback (shouldn't happen for sparse)
                pass
    return words


def extract_matrix_from_sparse_hbm(word_dict, base_addr, rows, stride, cols):
    """Extract INT16 matrix from sparse HBM dict (same as extract_matrix_from_hbm but dict-based)."""
    from verify.test_top import extract_int16_from_256bit
    BUS_EL = 16
    mat = []
    for r in range(rows):
        row = []
        for c in range(cols):
            word_idx = c // BUS_EL
            elem_idx = c % BUS_EL
            addr = base_addr + r * stride + word_idx
            word_val = word_dict.get(addr, 0)
            val = extract_int16_from_256bit(word_val, elem_idx)
            # Convert to signed
            if val >= 0x8000:
                val -= 0x10000
            row.append(val)
        mat.append(row)
    return mat


def compare_rtl_output(g, decode_results=None):
    """Read RTL dumps and compare against golden model.

    Args:
        g: golden intermediates dict (prefill)
        decode_results: optional dict with decode golden data:
            'dec1_k_news': list of 1D K_new rows per layer (decode token 1)
            'dec1_v_news': list of 1D V_new rows per layer
            'dec2_k_news': list of 1D K_new rows per layer (decode token 2)
            'dec2_v_news': list of 1D V_new rows per layer
            'decode_output': 1D list [MODEL_DIM] (final decode token 2 output)
    """
    flush_path = os.path.join(TEST_DATA_DIR, "hbm_flush_multi_dump.hex")
    uram_path  = os.path.join(TEST_DATA_DIR, "uram_multi_dump.hex")

    if not os.path.exists(flush_path):
        print("  ERROR: flush dump file not found")
        return False

    flush_words = read_sparse_hex_dump(flush_path)

    total_ok = total_mis = 0

    with open(RTL_OUT, 'w') as f:
        f.write("=" * 60 + "\n")
        f.write(f"MULTI-LAYER DECODE TEST ({NUM_LAYERS} layers) - RTL vs GOLDEN\n")
        f.write("=" * 60 + "\n\n")

        # Per-layer KV cache comparison — prefill rows (0..BT-1)
        for layer_idx in range(NUM_LAYERS):
            layer_kv = KV_BASE + layer_idx * KV_LAYER_SIZE
            prefix = f'L{layer_idx}'

            # K cache (prefill rows)
            k_key = f'{prefix}_K'
            if k_key in g:
                f.write(f"\n--- Layer {layer_idx} K cache (prefill, {BT} rows) ---\n")
                rtl_k = extract_matrix_from_sparse_hbm(
                    flush_words, layer_kv, BT, MODEL_STRIDE, MODEL_DIM)
                ok, mis = compare_matrices(g[k_key], rtl_k, f'{prefix}_K_prefill', f)
                total_ok += ok; total_mis += mis

            # V cache (prefill rows)
            v_key = f'{prefix}_V'
            if v_key in g:
                f.write(f"\n--- Layer {layer_idx} V cache (prefill, {BT} rows) ---\n")
                rtl_v = extract_matrix_from_sparse_hbm(
                    flush_words, layer_kv + KV_V_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
                ok, mis = compare_matrices(g[v_key], rtl_v, f'{prefix}_V_prefill', f)
                total_ok += ok; total_mis += mis

        # Decode KV rows and output
        if decode_results:
            # Decode token 1: K/V at row SEQ_LEN (= BT)
            f.write(f"\n{'='*40}\n  DECODE TOKEN 1 KV ROWS (row {BT})\n{'='*40}\n")
            for layer_idx in range(NUM_LAYERS):
                layer_kv = KV_BASE + layer_idx * KV_LAYER_SIZE
                prefix = f'L{layer_idx}'

                # K row at index BT
                golden_k = [decode_results['dec1_k_news'][layer_idx]]  # wrap as 1-row matrix
                rtl_k = extract_matrix_from_sparse_hbm(
                    flush_words, layer_kv + BT * MODEL_STRIDE, 1, MODEL_STRIDE, MODEL_DIM)
                f.write(f"\n--- Layer {layer_idx} K_new (row {BT}) ---\n")
                ok, mis = compare_matrices(golden_k, rtl_k, f'{prefix}_K_dec1', f)
                total_ok += ok; total_mis += mis

                # V row at index BT
                golden_v = [decode_results['dec1_v_news'][layer_idx]]
                rtl_v = extract_matrix_from_sparse_hbm(
                    flush_words, layer_kv + KV_V_OFFSET + BT * MODEL_STRIDE,
                    1, MODEL_STRIDE, MODEL_DIM)
                f.write(f"\n--- Layer {layer_idx} V_new (row {BT}) ---\n")
                ok, mis = compare_matrices(golden_v, rtl_v, f'{prefix}_V_dec1', f)
                total_ok += ok; total_mis += mis

            # Decode token 2: K/V at row SEQ_LEN+1 (= BT+1)
            f.write(f"\n{'='*40}\n  DECODE TOKEN 2 KV ROWS (row {BT+1})\n{'='*40}\n")
            for layer_idx in range(NUM_LAYERS):
                layer_kv = KV_BASE + layer_idx * KV_LAYER_SIZE
                prefix = f'L{layer_idx}'

                golden_k = [decode_results['dec2_k_news'][layer_idx]]
                rtl_k = extract_matrix_from_sparse_hbm(
                    flush_words, layer_kv + (BT+1) * MODEL_STRIDE, 1, MODEL_STRIDE, MODEL_DIM)
                f.write(f"\n--- Layer {layer_idx} K_new (row {BT+1}) ---\n")
                ok, mis = compare_matrices(golden_k, rtl_k, f'{prefix}_K_dec2', f)
                total_ok += ok; total_mis += mis

                golden_v = [decode_results['dec2_v_news'][layer_idx]]
                rtl_v = extract_matrix_from_sparse_hbm(
                    flush_words, layer_kv + KV_V_OFFSET + (BT+1) * MODEL_STRIDE,
                    1, MODEL_STRIDE, MODEL_DIM)
                f.write(f"\n--- Layer {layer_idx} V_new (row {BT+1}) ---\n")
                ok, mis = compare_matrices(golden_v, rtl_v, f'{prefix}_V_dec2', f)
                total_ok += ok; total_mis += mis

            # Decode token 1 intermediate output (if dump exists)
            dec1_dump_path = os.path.join(TEST_DATA_DIR, "dec1_output_dump.hex")
            if os.path.exists(dec1_dump_path) and 'dec1_output' in decode_results:
                f.write(f"\n{'='*40}\n  DECODE TOKEN 1 OUTPUT (intermediate)\n{'='*40}\n")
                # Read the debug dump
                dec1_words = []
                with open(dec1_dump_path, 'r') as df:
                    for dline in df:
                        dline = dline.strip()
                        if dline and not dline.endswith(':'):
                            dec1_words.append(int(dline, 16))
                # First MODEL_STRIDE words = URAM row 0
                if len(dec1_words) >= MODEL_STRIDE:
                    rtl_dec1_uram = extract_matrix_from_uram(
                        dec1_words[:MODEL_STRIDE], 0, 1, MODEL_STRIDE, MODEL_STRIDE)
                    golden_dec1 = [decode_results['dec1_output']]
                    f.write("\n--- Decode 1 output (URAM row 0) ---\n")
                    ok, mis = compare_matrices(golden_dec1, rtl_dec1_uram,
                                               'dec1_output_uram', f)
                    total_ok += ok; total_mis += mis
                # Next MODEL_STRIDE words = flush HBM ACT_BASE row 0
                if len(dec1_words) >= 2 * MODEL_STRIDE:
                    rtl_dec1_flush = extract_matrix_from_uram(
                        dec1_words[MODEL_STRIDE:2*MODEL_STRIDE], 0, 1,
                        MODEL_STRIDE, MODEL_STRIDE)
                    f.write("\n--- Decode 1 output (flush HBM ACT_BASE) ---\n")
                    ok, mis = compare_matrices(golden_dec1, rtl_dec1_flush,
                                               'dec1_output_flush', f)
                    total_ok += ok; total_mis += mis

            # Decode token 2 final output: ACT_BASE row 0
            f.write(f"\n{'='*40}\n  DECODE TOKEN 2 FINAL OUTPUT\n{'='*40}\n")
            golden_dec_out = [decode_results['decode_output']]  # 1-row matrix
            rtl_dec_out = extract_matrix_from_sparse_hbm(
                flush_words, ACT_BASE + ACT_EMBED_OFFSET, 1, MODEL_STRIDE, MODEL_DIM)
            f.write("\n--- Decode output (flush HBM @ ACT_BASE row 0) ---\n")
            ok, mis = compare_matrices(golden_dec_out, rtl_dec_out, 'decode_output_flush', f)
            total_ok += ok; total_mis += mis

            # URAM row 0 = decode token 2 output
            if os.path.exists(uram_path):
                uram_words = read_hex_dump(uram_path)
                f.write("\n--- Decode output (URAM row 0) ---\n")
                rtl_uram = extract_matrix_from_uram(
                    uram_words, 0, 1, MODEL_STRIDE, MODEL_STRIDE)
                ok, mis = compare_matrices(golden_dec_out, rtl_uram, 'decode_output_uram', f)
                total_ok += ok; total_mis += mis
        else:
            # Prefill-only mode: compare final output (all BT rows)
            f.write("\n--- Final Output: Last layer res2 (flush HBM @ ACT_EMBED) ---\n")
            rtl_final = extract_matrix_from_sparse_hbm(
                flush_words, ACT_BASE + ACT_EMBED_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
            ok, mis = compare_matrices(g['final_output'], rtl_final, 'final_output_flush', f)
            total_ok += ok; total_mis += mis

            if os.path.exists(uram_path):
                uram_words = read_hex_dump(uram_path)
                f.write("\n--- URAM Contents (should be final layer res2) ---\n")
                rtl_uram = extract_matrix_from_uram(
                    uram_words, 0, BT, MODEL_STRIDE, MODEL_STRIDE)
                ok, mis = compare_matrices(g['final_output'], rtl_uram, 'final_output_uram', f)
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

MULTI_INTERMEDIATES = [
    "hbm_wgt_multi.hex", "hbm_act_multi.hex", "hbm_dma_multi.hex",
    "hbm_flush_multi_dump.hex", "uram_multi_dump.hex",
    "decode_embed_1.hex", "decode_embed_2.hex",
]


def cleanup_intermediates():
    """Remove previous run's hex/dump files to prevent disk bloat."""
    for fn in MULTI_INTERMEDIATES:
        p = os.path.join(TEST_DATA_DIR, fn)
        if os.path.exists(p):
            os.remove(p)
            print(f"    Cleaned up {fn}")


def main():
    data_only = '--data-only' in sys.argv
    prefill_only = '--prefill-only' in sys.argv

    # Clean previous intermediates first (these can be 3+ GB)
    cleanup_intermediates()

    print("=" * 60)
    print(f"  Multi-Layer GPT-2 Decode Test ({NUM_LAYERS} layers)")
    print(f"  Phases: prefill(BT={BT}) + decode_1(BT=1) + decode_2(BT=1)")
    print(f"  MODEL_DIM={MODEL_DIM}, F_DIM={F_DIM}")
    print(f"  NUM_HEADS={NUM_HEADS}, HEAD_DIM={HEAD_DIM}, TILE_SIZE={TILE_SIZE}")
    print(f"  WEIGHT_BASE={WEIGHT_BASE}, ACT_BASE={ACT_BASE}, LAYER_SIZE={LAYER_SIZE}")
    print(f"  SIM_HBM_DEPTH={SIM_HBM_DEPTH}")
    print("=" * 60)

    # Verify HBM depth is sufficient (must fit KV cache for all layers)
    min_depth = max(ACT_BASE + ACT_TEMP_OFFSET + BT * MODEL_STRIDE,
                    KV_BASE + NUM_LAYERS * KV_LAYER_SIZE)
    if SIM_HBM_DEPTH < min_depth:
        print(f"  ERROR: SIM_HBM_DEPTH ({SIM_HBM_DEPTH}) < required ({min_depth})")
        sys.exit(1)

    # Generate weights
    print(f"\n  Generating weights for {NUM_LAYERS} layers...")
    layer_weights = generate_weights(NUM_LAYERS, seed=SEED)

    rng = random.Random(SEED + 2)
    embed_int8 = [
        [rng.randint(-2, 1) for _ in range(MODEL_DIM)]
        for _ in range(BT)
    ]

    # Generate 2 decode token embeddings (INT8 → INT16)
    DECODE_SEED = SEED + 100
    rng_dec = random.Random(DECODE_SEED)
    decode_embed_1_int16 = [int16(int8(rng_dec.randint(-2, 1))) for _ in range(MODEL_DIM)]
    decode_embed_2_int16 = [int16(int8(rng_dec.randint(-2, 1))) for _ in range(MODEL_DIM)]

    # Run prefill golden model
    print("\n  Running prefill golden model...")
    g = compute_golden(embed_int8, layer_weights)
    write_golden(g)

    # Extract KV caches from prefill golden for decode
    kv_caches_after_prefill = []
    for layer_idx in range(NUM_LAYERS):
        prefix = f'L{layer_idx}'
        kv_caches_after_prefill.append((g[f'{prefix}_K'], g[f'{prefix}_V']))

    # Run decode golden model (token 1)
    print("\n  Running decode golden model (token 1, cache_len={})...".format(BT))
    dec1_out, kv_caches_after_dec1, dec1_k_news, dec1_v_news = \
        compute_golden_decode(decode_embed_1_int16, layer_weights,
                              kv_caches_after_prefill, cache_len=BT)

    # Run decode golden model (token 2)
    print("\n  Running decode golden model (token 2, cache_len={})...".format(BT + 1))
    dec2_out, kv_caches_after_dec2, dec2_k_news, dec2_v_news = \
        compute_golden_decode(decode_embed_2_int16, layer_weights,
                              kv_caches_after_dec1, cache_len=BT + 1)

    decode_results = {
        'dec1_k_news': dec1_k_news,
        'dec1_v_news': dec1_v_news,
        'dec1_output': dec1_out,  # last layer's res2 from decode 1
        'dec2_k_news': dec2_k_news,
        'dec2_v_news': dec2_v_news,
        'decode_output': dec2_out,
    }

    # Generate hex files (including decode embeds)
    print("\n  Generating HBM hex files...")
    generate_hex_files(layer_weights, embed_int8,
                       decode_embeds=[decode_embed_1_int16, decode_embed_2_int16])

    if data_only:
        print("\n  --data-only: skipping compile/run")
        return

    # Write testbench and flags
    tb_path = write_testbench()
    flags_path = write_verilator_flags()

    # Compile
    if not compile_design(tb_path, flags_path):
        sys.exit(1)

    # Run
    if not run_simulation():
        sys.exit(1)

    # Compare
    passed = compare_rtl_output(g, decode_results=decode_results)
    if not passed:
        sys.exit(1)

    print("\nDone.")


if __name__ == "__main__":
    main()
