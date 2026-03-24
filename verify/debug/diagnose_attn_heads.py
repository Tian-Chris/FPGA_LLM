#!/usr/bin/env python3
"""Diagnose which attention heads mismatch and where the divergence starts."""

import os, sys, random
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.test_top_1k import (
    MODEL_DIM, F_DIM, TILE_SIZE, SEED, BT, HEAD_DIM, NUM_HEADS, WE,
    MM_SHIFT_QKV, MM_SHIFT_ATT_SCORE, MM_SHIFT_ATT_OUT, SCALE_SHIFT,
    generate_weights, tiled_matmul_int16_numpy, _transpose,
    ACT_BASE, ACT_EMBED_OFFSET, URAM_COL_WORDS,
)
from verify.golden.layernorm import layernorm_golden
from verify.golden.softmax import softmax_golden
from verify.golden.common import int8, int16

TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
MODEL_COL_WORDS = MODEL_DIM // WE
HEAD_WORDS = HEAD_DIM // WE


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


def extract_int16_from_256bit(word, elem_idx):
    return signed16((word >> (elem_idx * 16)) & 0xFFFF)


def main():
    print(f"HEAD_DIM={HEAD_DIM}, NUM_HEADS={NUM_HEADS}, BT={BT}, TILE_SIZE={TILE_SIZE}")
    print(f"MM_SHIFT_ATT_SCORE={MM_SHIFT_ATT_SCORE}, SCALE_SHIFT={SCALE_SHIFT}")
    print(f"HEAD_WORDS={HEAD_WORDS}, MODEL_COL_WORDS={MODEL_COL_WORDS}")

    # Generate golden
    weights = generate_weights(seed=SEED)
    rng = random.Random(SEED + 2)
    embed_int8 = [[rng.randint(-2, 1) for _ in range(MODEL_DIM)] for _ in range(BT)]
    gamma1 = [int8(v) for v in weights['gamma1']]
    beta1 = [int8(v) for v in weights['beta1']]
    embed_int16 = [[int8(v) for v in row] for row in embed_int8]
    ln1_out = [layernorm_golden(embed_int16[t], gamma1, beta1, MODEL_DIM) for t in range(BT)]

    Q = tiled_matmul_int16_numpy(ln1_out, weights['W_q'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)
    K = tiled_matmul_int16_numpy(ln1_out, weights['W_k'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)
    V = tiled_matmul_int16_numpy(ln1_out, weights['W_v'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)

    # Read RTL attn_concat from HBM dump
    path = os.path.join(TEST_DATA_DIR, "hbm_attn_concat_1k.hex")
    if not os.path.exists(path):
        print(f"ERROR: {path} not found")
        return

    hbm_words = read_hex_dump(path)
    rtl_attn_concat = []
    for r in range(BT):
        row = []
        for cw in range(MODEL_COL_WORDS):
            word_val = hbm_words[r * MODEL_COL_WORDS + cw] if (r * MODEL_COL_WORDS + cw) < len(hbm_words) else 0
            for e in range(WE):
                row.append(extract_int16_from_256bit(word_val, e))
        rtl_attn_concat.append(row)

    # Compare per-head
    print("\n" + "=" * 60)
    print("  Per-Head Attention Comparison")
    print("=" * 60)

    for h in range(NUM_HEADS):
        Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q]
        K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K]
        V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V]
        K_h_T = _transpose(K_h)

        scores = tiled_matmul_int16_numpy(Q_h, K_h_T, TILE_SIZE, acc_shift=MM_SHIFT_ATT_SCORE)
        probs = [softmax_golden(scores[t], scale_shift=SCALE_SHIFT, row_idx=t) for t in range(BT)]
        attn_out = tiled_matmul_int16_numpy(probs, V_h, TILE_SIZE, acc_shift=MM_SHIFT_ATT_OUT)

        # Compare this head's output against RTL attn_concat
        match = mis = 0
        max_diff = 0
        for t in range(BT):
            for d in range(HEAD_DIM):
                golden_v = attn_out[t][d] & 0xFFFF
                rtl_v = rtl_attn_concat[t][h*HEAD_DIM + d] & 0xFFFF
                if golden_v == rtl_v:
                    match += 1
                else:
                    mis += 1
                    diff = abs(signed16(golden_v) - signed16(rtl_v))
                    if diff > max_diff:
                        max_diff = diff

        total = match + mis
        if mis == 0:
            print(f"  Head {h:2d}: PERFECT MATCH ({total} elements)")
        else:
            print(f"  Head {h:2d}: {mis}/{total} mismatches, max_diff={max_diff}")
            # Show first mismatching row
            for t in range(BT):
                row_mis = sum(1 for d in range(HEAD_DIM)
                              if (attn_out[t][d] & 0xFFFF) != (rtl_attn_concat[t][h*HEAD_DIM+d] & 0xFFFF))
                if row_mis > 0:
                    print(f"    First bad row={t}: {row_mis}/{HEAD_DIM} mismatches")
                    gc = [signed16(attn_out[t][d]) for d in range(min(8, HEAD_DIM))]
                    rc = [signed16(rtl_attn_concat[t][h*HEAD_DIM+d]) for d in range(min(8, HEAD_DIM))]
                    print(f"      golden: {gc}")
                    print(f"      rtl:    {rc}")
                    break

    # Also check: are scores non-zero?
    print("\n" + "=" * 60)
    print("  Score Magnitudes by Head")
    print("=" * 60)
    for h in range(NUM_HEADS):
        Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q]
        K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K]
        K_h_T = _transpose(K_h)
        scores = tiled_matmul_int16_numpy(Q_h, K_h_T, TILE_SIZE, acc_shift=MM_SHIFT_ATT_SCORE)
        all_vals = [signed16(scores[t][c]) for t in range(BT) for c in range(BT)]
        nonzero = sum(1 for v in all_vals if v != 0)
        max_abs = max(abs(v) for v in all_vals)
        print(f"  Head {h:2d}: nonzero={nonzero}/{len(all_vals)}, max_abs={max_abs}")


if __name__ == "__main__":
    main()
