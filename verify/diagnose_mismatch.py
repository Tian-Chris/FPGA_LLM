#!/usr/bin/env python3
"""Diagnose where golden model and RTL diverge using intermediate dumps."""

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


def extract_matrix_from_uram(uram_words, base_row, num_rows, num_col_words, col_words_total):
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

    print("=== Intermediate Dump Comparison ===\n")

    # 1. URAM after step 4 (proj matmul) — should have attn_proj
    path = os.path.join(TEST_DATA_DIR, "uram_after_proj.hex")
    if os.path.exists(path):
        uram_proj = read_hex_dump(path)
        rtl_proj = extract_matrix_from_uram(uram_proj, 0, BT, MODEL_STRIDE, URAM_COL_WORDS)
        compare_brief(g['attn_proj'], rtl_proj, "attn_proj (URAM after step 4)", MODEL_DIM, show_rows=2)
    else:
        print("  uram_after_proj.hex not found")

    # 2. URAM after step 5 (res1) — should have residual1
    path = os.path.join(TEST_DATA_DIR, "uram_after_res1.hex")
    if os.path.exists(path):
        uram_res1 = read_hex_dump(path)
        rtl_res1 = extract_matrix_from_uram(uram_res1, 0, BT, MODEL_STRIDE, URAM_COL_WORDS)
        compare_brief(g['residual1'], rtl_res1, "residual1 (URAM after step 5)", MODEL_DIM, show_rows=2)
    else:
        print("  uram_after_res1.hex not found")

    # 3. URAM after step 12 (FFN2 matmul) — should have FFN2 output
    path = os.path.join(TEST_DATA_DIR, "uram_after_ffn2.hex")
    if os.path.exists(path):
        uram_ffn2 = read_hex_dump(path)
        rtl_ffn2 = extract_matrix_from_uram(uram_ffn2, 0, BT, MODEL_STRIDE, URAM_COL_WORDS)
        compare_brief(g['ffn2'], rtl_ffn2, "ffn2 (URAM after step 12)", MODEL_DIM, show_rows=2)
    else:
        print("  uram_after_ffn2.hex not found")

    # 4. DMA before step 13 — should have res1 at ACT_EMBED
    path = os.path.join(TEST_DATA_DIR, "dma_before_res2.hex")
    if os.path.exists(path):
        dma_pre = read_hex_dump(path)
        rtl_dma_res1 = extract_matrix_from_hbm(dma_pre, ACT_BASE + ACT_EMBED_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
        compare_brief(g['residual1'], rtl_dma_res1, "res1 in DMA before step 13", MODEL_DIM, show_rows=2)

        # Also check if DMA has original embeddings (no mirror)
        embed_int16 = [[int16(int8(v)) for v in row] for row in embed_int8]
        compare_brief(embed_int16, rtl_dma_res1, "embed in DMA before step 13?", MODEL_DIM)
    else:
        print("  dma_before_res2.hex not found")

    # 5. Final res2
    flush_words = read_hex_dump(os.path.join(TEST_DATA_DIR, "hbm_flush_dump.hex"))
    rtl_res2 = extract_matrix_from_hbm(flush_words, ACT_BASE + ACT_EMBED_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
    compare_brief(g['residual2'], rtl_res2, "res2 (final flush HBM)", MODEL_DIM, show_rows=2)

    # 6. Compute what res2 SHOULD be from RTL intermediates
    if os.path.exists(os.path.join(TEST_DATA_DIR, "uram_after_ffn2.hex")) and \
       os.path.exists(os.path.join(TEST_DATA_DIR, "dma_before_res2.hex")):
        print("\n--- Cross-check: RTL_ffn2 + RTL_dma_skip vs RTL_res2 ---")
        from verify.golden.residual_add import residual_add_golden
        expected_res2 = [residual_add_golden(
            [signed16(rtl_dma_res1[t][c]) for c in range(MODEL_DIM)],
            [signed16(rtl_ffn2[t][c]) for c in range(MODEL_DIM)]
        ) for t in range(BT)]
        compare_brief(expected_res2, [[signed16(rtl_res2[t][c]) for c in range(MODEL_DIM)] for t in range(BT)],
                       "expected(dma+ffn2) vs actual res2", MODEL_DIM, show_rows=2)


if __name__ == "__main__":
    main()
