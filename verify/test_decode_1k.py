#!/usr/bin/env python3
"""KV Cache Decode Mode test: prefill (8 tokens) then decode (1 new token).

Two-phase golden model:
  Phase 1: Full GPT-2 pre-norm pipeline with BT=8 (prefill)
  Phase 2: Single-token forward pass reusing K/V cache from phase 1

Verifies the decode pass output (1 row of residual2) against the golden model.
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

from verify.test_top_1k import (
    tiled_matmul_int16_numpy, _transpose, generate_weights,
)

# ---------------------------------------------------------------------------
# Parameters (must match defines.vh SIM_1K)
# ---------------------------------------------------------------------------
MODEL_DIM     = 1024
NUM_HEADS     = 16
HEAD_DIM      = MODEL_DIM // NUM_HEADS   # 64
SCALE_SHIFT   = math.ceil(math.log2(HEAD_DIM)) >> 1  # 3
F_DIM         = 4096
INPUT_DIM     = 64
MAX_SEQ_LEN   = 128
TILE_SIZE     = 32
NUM_ENGINES   = 6

PREFILL_LEN   = 8
BATCH         = 1
BT_PREFILL    = BATCH * PREFILL_LEN  # 8
BT_DECODE     = 1

DATA_W = 16
BUS_ELEMS = 16
URAM_ROWS = 1024
URAM_COLS = 4096
URAM_COL_WORDS = URAM_COLS // BUS_ELEMS  # 256

SIM_HBM_DEPTH = 1048576  # 2^20

SEED = 42
DECODE_EMBED_SEED = 99

# ---------------------------------------------------------------------------
# HBM Memory Layout (must match fsm_controller.v)
# ---------------------------------------------------------------------------
WE = BUS_ELEMS
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
ACT_BASE    = LAYER_SIZE

ACT_EMBED_OFFSET = 0
ACT_Q_OFFSET     = MAX_SEQ_LEN * MODEL_DIM // WE
ACT_ATTN_OFFSET  = 4 * MAX_SEQ_LEN * MODEL_DIM // WE
ACT_TEMP_OFFSET  = 5 * MAX_SEQ_LEN * MODEL_DIM // WE
ACT_FFN_OFFSET   = 0

# Per-layer KV cache region
KV_V_OFFSET   = MAX_SEQ_LEN * MODEL_DIM // WE
KV_LAYER_SIZE = 2 * MAX_SEQ_LEN * MODEL_DIM // WE
KV_BASE       = ACT_BASE + 6 * MAX_SEQ_LEN * MODEL_DIM // WE

# Directories
TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
RTL_DIR       = os.path.join(PROJECT_ROOT, "rtl")
TB_DIR        = os.path.join(PROJECT_ROOT, "tb")
OBJ_DIR       = os.path.join(PROJECT_ROOT, "obj_dir")

GOLDEN_OUT = os.path.join(PROJECT_ROOT, "verify", "llm_golden_decode.txt")
RTL_OUT    = os.path.join(PROJECT_ROOT, "verify", "llm_rtl_decode.txt")

RTL_ALL = [
    "bram_controller.v", "mac_unit.v", "agu.v", "matmul_engine.v",
    "mem_arbiter.v", "tiling_engine.v", "softmax.v", "layernorm.v",
    "activation.v", "residual_add.v", "quant_layer.v", "host_interface.v",
    "positional_embedding.v", "fsm_controller.v", "sim_hbm_port.v",
    "uram_accum_buf.v", "tile_loader.v", "uram_flush.v", "act_dma.v",
    "uram_nm_adapter.v", "top_level.v",
]


# ---------------------------------------------------------------------------
# Golden Model — Prefill Phase
# ---------------------------------------------------------------------------

def compute_golden_prefill(embed_int8, weights):
    """Run full GPT-2 pre-norm pipeline for prefill (BT=PREFILL_LEN)."""
    g = {}
    embed_int16 = [[int16(int8(v)) for v in row] for row in embed_int8]
    g['embed_int16'] = embed_int16

    # LN1
    print("    [prefill] LN1...")
    ln1_out = []
    for t in range(BT_PREFILL):
        normed = layernorm_golden(
            embed_int16[t], weights['gamma1'], weights['beta1'], MODEL_DIM
        )
        ln1_out.append(normed)
    g['ln1_out'] = ln1_out

    # QKV
    print("    [prefill] QKV matmuls...")
    Q = tiled_matmul_int16_numpy(ln1_out, weights['W_q'], TILE_SIZE)
    K = tiled_matmul_int16_numpy(ln1_out, weights['W_k'], TILE_SIZE)
    V = tiled_matmul_int16_numpy(ln1_out, weights['W_v'], TILE_SIZE)
    g['Q'] = Q
    g['K'] = K
    g['V'] = V

    # Multi-head attention
    print("    [prefill] Attention (16 heads)...")
    attn_concat = [[0] * MODEL_DIM for _ in range(BT_PREFILL)]
    for h in range(NUM_HEADS):
        Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q]
        K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K]
        V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V]

        K_h_T = _transpose(K_h)
        scores_h = tiled_matmul_int16_numpy(Q_h, K_h_T, TILE_SIZE)
        probs_h = [softmax_golden(scores_h[t], scale_shift=SCALE_SHIFT, row_idx=t)
                   for t in range(BT_PREFILL)]
        attn_h = tiled_matmul_int16_numpy(probs_h, V_h, TILE_SIZE)

        for t in range(BT_PREFILL):
            for d in range(HEAD_DIM):
                attn_concat[t][h*HEAD_DIM + d] = attn_h[t][d]

    g['attn_out'] = attn_concat

    # Output projection
    print("    [prefill] Output projection...")
    attn_proj = tiled_matmul_int16_numpy(attn_concat, weights['W_o'], TILE_SIZE)
    g['attn_proj'] = attn_proj

    # Residual 1
    print("    [prefill] Residual 1...")
    residual1 = [residual_add_golden(embed_int16[t], attn_proj[t]) for t in range(BT_PREFILL)]
    g['residual1'] = residual1

    # LN2
    print("    [prefill] LN2...")
    ln2_out = []
    for t in range(BT_PREFILL):
        normed = layernorm_golden(
            residual1[t], weights['gamma2'], weights['beta2'], MODEL_DIM
        )
        ln2_out.append(normed)
    g['ln2_out'] = ln2_out

    # FFN1
    print("    [prefill] FFN1...")
    ffn1 = tiled_matmul_int16_numpy(ln2_out, weights['W_ffn1'], TILE_SIZE)
    g['ffn1'] = ffn1

    # ReLU
    print("    [prefill] ReLU...")
    ffn_act = [[relu_golden(v) for v in row] for row in ffn1]
    g['ffn_act'] = ffn_act

    # FFN2
    print("    [prefill] FFN2...")
    ffn2 = tiled_matmul_int16_numpy(ffn_act, weights['W_ffn2'], TILE_SIZE)
    g['ffn2'] = ffn2

    # Residual 2
    print("    [prefill] Residual 2...")
    residual2 = [residual_add_golden(embed_int16[t], ffn2[t]) for t in range(BT_PREFILL)]
    g['residual2'] = residual2

    return g


# ---------------------------------------------------------------------------
# Golden Model — Decode Phase
# ---------------------------------------------------------------------------

def compute_golden_decode(new_embed_int16, K_cache, V_cache, weights):
    """Run single-token decode with KV cache from prefill.

    Args:
        new_embed_int16: 1D list, new token embedding (MODEL_DIM)
        K_cache: list of lists, PREFILL_LEN × MODEL_DIM
        V_cache: list of lists, PREFILL_LEN × MODEL_DIM
        weights: weight dict

    Returns:
        dict with all intermediate values including residual2 (1 × MODEL_DIM)
    """
    g = {}
    embed = [new_embed_int16]  # 1 × MODEL_DIM (wrap in list for matmul)
    g['embed_int16'] = embed
    cache_total = PREFILL_LEN + 1  # 9

    # LN1
    print("    [decode] LN1...")
    ln1_out = [layernorm_golden(embed[0], weights['gamma1'], weights['beta1'], MODEL_DIM)]
    g['ln1_out'] = ln1_out

    # QKV projections (single token)
    print("    [decode] QKV matmuls...")
    Q_new = tiled_matmul_int16_numpy(ln1_out, weights['W_q'], TILE_SIZE)
    K_new = tiled_matmul_int16_numpy(ln1_out, weights['W_k'], TILE_SIZE)
    V_new = tiled_matmul_int16_numpy(ln1_out, weights['W_v'], TILE_SIZE)
    g['Q'] = Q_new
    g['K_new'] = K_new
    g['V_new'] = V_new

    # Full K/V = cache ++ new
    K_full = K_cache + K_new  # 9 rows
    V_full = V_cache + V_new  # 9 rows
    g['K_full'] = K_full
    g['V_full'] = V_full

    # Multi-head attention with full cache
    print("    [decode] Attention (16 heads, cache_total=%d)..." % cache_total)
    attn_concat = [[0] * MODEL_DIM]

    for h in range(NUM_HEADS):
        Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q_new]      # 1 × HEAD_DIM
        K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K_full]     # 9 × HEAD_DIM
        V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V_full]     # 9 × HEAD_DIM

        K_h_T = _transpose(K_h)   # HEAD_DIM × 9
        scores_h = tiled_matmul_int16_numpy(Q_h, K_h_T, TILE_SIZE)   # 1 × 9

        # Causal mask: row_idx = PREFILL_LEN (= cache_len_r) allows cols 0..PREFILL_LEN
        probs_h = [softmax_golden(scores_h[0], scale_shift=SCALE_SHIFT,
                                  row_idx=PREFILL_LEN)]

        attn_h = tiled_matmul_int16_numpy(probs_h, V_h, TILE_SIZE)   # 1 × HEAD_DIM

        for d in range(HEAD_DIM):
            attn_concat[0][h*HEAD_DIM + d] = attn_h[0][d]

    g['attn_out'] = attn_concat

    # Output projection
    print("    [decode] Output projection...")
    attn_proj = tiled_matmul_int16_numpy(attn_concat, weights['W_o'], TILE_SIZE)
    g['attn_proj'] = attn_proj

    # Residual 1 = new_embed + proj
    print("    [decode] Residual 1...")
    residual1 = [residual_add_golden(embed[0], attn_proj[0])]
    g['residual1'] = residual1

    # LN2
    print("    [decode] LN2...")
    ln2_out = [layernorm_golden(residual1[0], weights['gamma2'], weights['beta2'], MODEL_DIM)]
    g['ln2_out'] = ln2_out

    # FFN1
    print("    [decode] FFN1...")
    ffn1 = tiled_matmul_int16_numpy(ln2_out, weights['W_ffn1'], TILE_SIZE)
    g['ffn1'] = ffn1

    # ReLU
    print("    [decode] ReLU...")
    ffn_act = [[relu_golden(v) for v in row] for row in ffn1]
    g['ffn_act'] = ffn_act

    # FFN2
    print("    [decode] FFN2...")
    ffn2 = tiled_matmul_int16_numpy(ffn_act, weights['W_ffn2'], TILE_SIZE)
    g['ffn2'] = ffn2

    # Residual 2 = new_embed + ffn2
    print("    [decode] Residual 2...")
    residual2 = [residual_add_golden(embed[0], ffn2[0])]
    g['residual2'] = residual2

    return g


# ---------------------------------------------------------------------------
# HBM Hex File Generation
# ---------------------------------------------------------------------------

def generate_hex_files(weights, embed_int8, new_embed_int8):
    """Generate hex files for both prefill and decode phases."""
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    # Weight HBM (same as test_top_1k)
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
    pack_ln_params(weights['gamma1'], weights['beta1'],
                   WEIGHT_BASE + LAYER_LN1_OFFSET, wgt_mem)
    pack_ln_params(weights['gamma2'], weights['beta2'],
                   WEIGHT_BASE + LAYER_LN2_OFFSET, wgt_mem)

    print("    Writing weight hex file...")
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_wgt_decode.hex"),
                   [wgt_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # Activation HBM (PREFILL_LEN rows of embeddings)
    print("    Packing activation HBM...")
    act_mem = {}
    embed_int16 = [[int16(int8(v)) for v in row] for row in embed_int8]
    pack_matrix_int16(embed_int16, BT_PREFILL, MODEL_DIM,
                      ACT_BASE + ACT_EMBED_OFFSET, MODEL_STRIDE, act_mem)

    print("    Writing activation hex file...")
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_act_decode.hex"),
                   [act_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # DMA HBM (LN params + embeddings for residual add)
    print("    Packing DMA HBM...")
    dma_mem = {}
    pack_ln_params(weights['gamma1'], weights['beta1'],
                   WEIGHT_BASE + LAYER_LN1_OFFSET, dma_mem)
    pack_ln_params(weights['gamma2'], weights['beta2'],
                   WEIGHT_BASE + LAYER_LN2_OFFSET, dma_mem)
    pack_matrix_int16(embed_int16, BT_PREFILL, MODEL_DIM,
                      ACT_BASE + ACT_EMBED_OFFSET, MODEL_STRIDE, dma_mem)

    print("    Writing DMA hex file...")
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_dma_decode.hex"),
                   [dma_mem.get(a, '0' * 64) for a in range(SIM_HBM_DEPTH)])

    # Decode new token embedding (1 row = MODEL_STRIDE words)
    print("    Packing decode embedding...")
    new_embed_int16 = [int16(int8(v)) for v in new_embed_int8]
    embed_words = []
    for w_idx in range(MODEL_STRIDE):
        elems = new_embed_int16[w_idx * WE : (w_idx + 1) * WE]
        embed_words.append(pack_int16_to_256bit(elems))

    write_hex_file(os.path.join(TEST_DATA_DIR, "decode_new_embed.hex"), embed_words)

    print(f"  Hex files written to {TEST_DATA_DIR}/")
    return new_embed_int16


# ---------------------------------------------------------------------------
# Compile & Run
# ---------------------------------------------------------------------------

def compile_design():
    """Compile with Verilator using decode flags."""
    tb_path = os.path.join(TB_DIR, "tb_top_decode.v")
    rtl_paths = [os.path.join(RTL_DIR, f) for f in RTL_ALL]
    verilator_f = os.path.join(PROJECT_ROOT, "scripts", "verilator_decode.f")

    cmd = (["verilator", "--binary", "-f", verilator_f, tb_path]
           + rtl_paths + ["--top-module", "tb_top_decode"])

    print("  Compiling with Verilator (decode mode)...")
    result = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  COMPILE FAILED:\n{result.stderr[:5000]}")
        return False
    print("  Compilation OK.")
    return True


def run_simulation():
    """Run the compiled simulation."""
    binary = os.path.join(OBJ_DIR, "Vtb_top_decode")
    if not os.path.exists(binary):
        print(f"  ERROR: binary not found: {binary}")
        return False

    print("  Running simulation (prefill + decode, may take a few minutes)...")
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

def compare_rtl_output(g_prefill, g_decode):
    """Read RTL dumps and compare decode output against golden."""
    flush_path = os.path.join(TEST_DATA_DIR, "hbm_flush_decode_dump.hex")
    uram_path  = os.path.join(TEST_DATA_DIR, "uram_decode_dump.hex")
    prefill_flush_path = os.path.join(TEST_DATA_DIR, "hbm_flush_prefill_dump.hex")

    if not os.path.exists(flush_path):
        print("  ERROR: decode flush dump file not found")
        return False

    flush_words = read_hex_dump(flush_path)

    total_ok = total_mis = 0

    with open(RTL_OUT, 'w') as f:
        f.write("=" * 60 + "\n")
        f.write("DECODE MODE TEST - RTL vs GOLDEN COMPARISON\n")
        f.write("=" * 60 + "\n\n")

        # --- Verify prefill K/V cache in flush HBM ---
        f.write("--- Prefill K cache (flush HBM) ---\n")
        rtl_k_cache = extract_matrix_from_hbm(
            flush_words, KV_BASE, BT_PREFILL, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_matrices(g_prefill['K'], rtl_k_cache, 'prefill_K_cache', f)
        total_ok += ok; total_mis += mis

        f.write("\n--- Prefill V cache (flush HBM) ---\n")
        rtl_v_cache = extract_matrix_from_hbm(
            flush_words, KV_BASE + KV_V_OFFSET, BT_PREFILL, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_matrices(g_prefill['V'], rtl_v_cache, 'prefill_V_cache', f)
        total_ok += ok; total_mis += mis

        # --- Verify decode K/V appended at row PREFILL_LEN ---
        f.write("\n--- Decode K_new at row %d (flush HBM) ---\n" % PREFILL_LEN)
        rtl_k_new = extract_matrix_from_hbm(
            flush_words, KV_BASE + PREFILL_LEN * MODEL_STRIDE,
            1, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_matrices(g_decode['K_new'], rtl_k_new, 'decode_K_new', f)
        total_ok += ok; total_mis += mis

        f.write("\n--- Decode V_new at row %d (flush HBM) ---\n" % PREFILL_LEN)
        rtl_v_new = extract_matrix_from_hbm(
            flush_words, KV_BASE + KV_V_OFFSET + PREFILL_LEN * MODEL_STRIDE,
            1, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_matrices(g_decode['V_new'], rtl_v_new, 'decode_V_new', f)
        total_ok += ok; total_mis += mis

        # --- Verify decode final output (residual2) ---
        f.write("\n--- Decode Residual 2 (flush HBM at ACT_EMBED) ---\n")
        rtl_res2 = extract_matrix_from_hbm(
            flush_words, ACT_BASE + ACT_EMBED_OFFSET, 1, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_matrices(g_decode['residual2'], rtl_res2, 'decode_res2_flush', f)
        total_ok += ok; total_mis += mis

        # URAM check
        if os.path.exists(uram_path):
            uram_words = read_hex_dump(uram_path)
            f.write("\n--- Decode Residual 2 (URAM row 0) ---\n")
            rtl_uram_res2 = extract_matrix_from_uram(
                uram_words, 0, 1, MODEL_STRIDE, MODEL_STRIDE)
            ok, mis = compare_matrices(g_decode['residual2'], rtl_uram_res2,
                                       'decode_res2_uram', f)
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
# Golden File Writer
# ---------------------------------------------------------------------------

def write_golden(g_prefill, g_decode):
    """Write golden intermediate values for debugging."""
    with open(GOLDEN_OUT, 'w') as f:
        f.write("=" * 60 + "\n")
        f.write("DECODE MODE TEST - GOLDEN REFERENCE\n")
        f.write("=" * 60 + "\n")
        f.write(f"PREFILL_LEN={PREFILL_LEN}, MODEL_DIM={MODEL_DIM}, "
                f"NUM_HEADS={NUM_HEADS}, HEAD_DIM={HEAD_DIM}\n\n")

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

        f.write("--- PREFILL ---\n")
        for stage, name in [
            ('embed_int16', 'Embeddings'), ('K', 'K cache'), ('V', 'V cache'),
            ('residual2', 'Prefill res2'),
        ]:
            write_mat_summary(name, g_prefill[stage])

        f.write("\n--- DECODE ---\n")
        for stage, name in [
            ('embed_int16', 'New token'), ('ln1_out', 'LN1'),
            ('Q', 'Q_new'), ('K_new', 'K_new'), ('V_new', 'V_new'),
            ('attn_out', 'Attn output'), ('attn_proj', 'Proj'),
            ('residual1', 'Res1'), ('ln2_out', 'LN2'),
            ('ffn1', 'FFN1'), ('ffn2', 'FFN2'),
            ('residual2', 'Decode res2 (FINAL)'),
        ]:
            write_mat_summary(name, g_decode[stage])

    print(f"  Golden written: {GOLDEN_OUT}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    data_only = '--data-only' in sys.argv

    print("=" * 60)
    print("  Decode Mode Test (Prefill + Decode)")
    print(f"  PREFILL_LEN={PREFILL_LEN}, MODEL_DIM={MODEL_DIM}, F_DIM={F_DIM}")
    print(f"  NUM_HEADS={NUM_HEADS}, HEAD_DIM={HEAD_DIM}, TILE_SIZE={TILE_SIZE}")
    print(f"  WEIGHT_BASE={WEIGHT_BASE}, ACT_BASE={ACT_BASE}")
    print("=" * 60)

    # Generate weights (same seed as test_top_1k)
    print("\n  Generating weights...")
    weights = generate_weights(seed=SEED)

    # Prefill embeddings (8 tokens)
    rng = random.Random(SEED + 2)
    embed_int8 = [
        [rng.randint(-2, 1) for _ in range(MODEL_DIM)]
        for _ in range(BT_PREFILL)
    ]

    # New decode token embedding (different seed)
    rng_dec = random.Random(DECODE_EMBED_SEED)
    new_embed_int8 = [rng_dec.randint(-2, 1) for _ in range(MODEL_DIM)]

    # Run prefill golden
    print("\n  Running prefill golden model...")
    g_prefill = compute_golden_prefill(embed_int8, weights)

    # Run decode golden (uses K/V cache from prefill)
    print("\n  Running decode golden model...")
    new_embed_int16 = [int16(int8(v)) for v in new_embed_int8]
    g_decode = compute_golden_decode(
        new_embed_int16,
        K_cache=g_prefill['K'],
        V_cache=g_prefill['V'],
        weights=weights,
    )

    write_golden(g_prefill, g_decode)

    # Generate hex files
    print("\n  Generating HBM hex files...")
    generate_hex_files(weights, embed_int8, new_embed_int8)

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
    passed = compare_rtl_output(g_prefill, g_decode)
    if not passed:
        sys.exit(1)

    print("\nDone.")


if __name__ == "__main__":
    main()
