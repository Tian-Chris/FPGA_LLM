#!/usr/bin/env python3
"""Diagnose attention pipeline: check Q/K/V and attn_concat before PROJ."""

import os
import sys
import random
import math

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.test_top import (
    MODEL_DIM, NUM_HEADS, HEAD_DIM, F_DIM, BT, TILE_SIZE, WE, SEED,
    ACT_BASE, WEIGHT_BASE, LAYER_SIZE,
    ACT_EMBED_OFFSET, ACT_Q_OFFSET,
    ACT_ATTN_OFFSET, ACT_TEMP_OFFSET, ACT_FFN_OFFSET,
    KV_BASE, KV_V_OFFSET,
    MODEL_STRIDE, F_STRIDE,
    URAM_COL_WORDS,
    generate_weights,
    extract_int16_from_256bit,
    compute_golden,
    int16, int8,
    MM_SHIFT_QKV, MM_SHIFT_PROJ,
    tiled_matmul_int16,
)

TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")


def signed16(v):
    v = v & 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


def read_hex_dump(filepath):
    words = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                words.append(int(line, 16))
    return words


def extract_matrix_from_hbm(hbm_words, base_addr, num_rows, stride, num_cols):
    mat = []
    for r in range(num_rows):
        row = []
        for w in range((num_cols + WE - 1) // WE):
            addr = base_addr + r * stride + w
            word_val = hbm_words[addr] if addr < len(hbm_words) else 0
            for e in range(WE):
                col = w * WE + e
                if col < num_cols:
                    row.append(extract_int16_from_256bit(word_val, e))
        mat.append(row)
    return mat


def compare_brief(golden_mat, rtl_mat, name, num_cols, show_rows=0):
    total = match = 0
    first_mis = None
    for r in range(len(golden_mat)):
        for c in range(min(num_cols, len(golden_mat[r]), len(rtl_mat[r]) if r < len(rtl_mat) else 0)):
            gv = golden_mat[r][c] & 0xFFFF
            rv = rtl_mat[r][c] & 0xFFFF
            total += 1
            if gv == rv:
                match += 1
            elif first_mis is None:
                first_mis = (r, c, gv, rv)

    pct = 100.0 * match / total if total > 0 else 0
    print(f"  {name}: {match}/{total} match ({pct:.1f}%)", end="")
    if first_mis:
        r, c, gv, rv = first_mis
        print(f"  first_mis: [{r}][{c}] golden={gv:04x}({signed16(gv)}) rtl={rv:04x}({signed16(rv)})")
    else:
        print("  PERFECT")

    if show_rows > 0:
        for r in range(min(show_rows, len(golden_mat))):
            gc = [signed16(golden_mat[r][c]) for c in range(min(8, num_cols))]
            rc = [signed16(rtl_mat[r][c]) for c in range(min(8, num_cols))]
            print(f"    row[{r}] golden: {gc}")
            print(f"    row[{r}] rtl:    {rc}")
    return match, total


def main():
    weights = generate_weights(seed=SEED)
    rng = random.Random(SEED + 2)
    embed_int8 = [[rng.randint(-2, 1) for _ in range(MODEL_DIM)] for _ in range(BT)]
    g = compute_golden(embed_int8, weights)

    flush_before_proj = read_hex_dump(os.path.join(TEST_DATA_DIR, "flush_before_proj.hex"))

    print("=== Attention Pipeline Comparison (flush HBM before step 4) ===\n")

    # Q at ACT_Q_OFFSET — but attention output was flushed here too!
    # After attention, head 0 attn_out overwrites Q space, head 1 overwrites Q+HEAD_WORDS
    # So ACT_Q now has attn_concat, not Q.

    # Check attn_concat at ACT_Q
    rtl_attn_concat = extract_matrix_from_hbm(
        flush_before_proj, ACT_BASE + ACT_Q_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
    compare_brief(g['attn_out'], rtl_attn_concat, "attn_concat @ ACT_Q", MODEL_DIM, show_rows=3)

    # K still at ACT_K? (may have been partially overwritten by attention operations)
    rtl_k = extract_matrix_from_hbm(
        flush_before_proj, KV_BASE, BT, MODEL_STRIDE, MODEL_DIM)
    compare_brief(g['K'], rtl_k, "K @ KV_BASE (may be overwritten)", MODEL_DIM, show_rows=2)

    # V still at KV_BASE + KV_V_OFFSET?
    rtl_v = extract_matrix_from_hbm(
        flush_before_proj, KV_BASE + KV_V_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
    compare_brief(g['V'], rtl_v, "V @ KV_BASE + KV_V_OFFSET (may be overwritten)", MODEL_DIM, show_rows=2)

    # LN1 output at ACT_TEMP
    rtl_ln1 = extract_matrix_from_hbm(
        flush_before_proj, ACT_BASE + ACT_TEMP_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
    compare_brief(g['ln1_out'], rtl_ln1, "LN1 @ ACT_TEMP", MODEL_DIM, show_rows=2)

    # Check: if attn_concat is wrong, compute PROJ with RTL attn_concat
    # to see if PROJ matmul itself is correct
    print("\n--- Cross-check: matmul(RTL_attn_concat, W_o) vs RTL_proj ---")
    from verify.golden.common import int8 as i8
    W_o_int16 = [[int16(i8(v)) for v in row] for row in weights['W_o']]
    rtl_attn_signed = [[signed16(v) for v in row] for row in rtl_attn_concat]
    expected_proj = tiled_matmul_int16(rtl_attn_signed, W_o_int16, TILE_SIZE, acc_shift=MM_SHIFT_PROJ)

    from verify.test_top import read_hex_dump as rhd
    uram_proj_words = read_hex_dump(os.path.join(TEST_DATA_DIR, "uram_after_proj.hex"))
    from verify.test_top import extract_matrix_from_uram
    rtl_proj = extract_matrix_from_uram(uram_proj_words, 0, BT, MODEL_STRIDE, URAM_COL_WORDS)

    compare_brief(expected_proj, [[signed16(v) for v in row] for row in rtl_proj],
                   "matmul(RTL_attn, W_o) vs RTL_proj", MODEL_DIM, show_rows=2)

    # Check attention scores for head 0 at ACT_ATTN
    # Scores are at ACT_ATTN, softmax overwrites them, so this has softmax output
    # Actually, attention_score -> URAM, then flush to ACT_ATTN for softmax
    # But scores are flushed per head... need to think about where things end up

    print("\n--- Attention sub-steps ---")
    # Softmax probs for head 0 should be at ACT_ATTN (after softmax flush, head 0)
    # Actually this gets overwritten by head 1's scores/softmax
    # Let me check if scores/probs for head 1 are still there
    HEAD_WORDS = HEAD_DIM // WE  # 2

    # Check what's at ACT_ATTN
    rtl_attn_area = extract_matrix_from_hbm(
        flush_before_proj, ACT_BASE + ACT_ATTN_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
    # This should have the LAST thing flushed there — softmax probs for head 1
    # Actually, scores are flushed to ACT_ATTN, softmax reads from URAM
    # Let me just show what's there
    print(f"  ACT_ATTN area row[0][:8]: {[signed16(rtl_attn_area[0][c]) for c in range(8)]}")
    print(f"  ACT_ATTN area row[1][:8]: {[signed16(rtl_attn_area[1][c]) for c in range(8)]}")


if __name__ == "__main__":
    main()
