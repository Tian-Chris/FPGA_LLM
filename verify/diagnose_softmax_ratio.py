#!/usr/bin/env python3
"""Investigate the 3/4 ratio in attention output mismatches.

Computes golden softmax for specific rows with varying mask boundaries
to find which mask produces the RTL output values.
"""

import os, sys, random
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.test_top_1k import (
    MODEL_DIM, TILE_SIZE, SEED, BT, HEAD_DIM, NUM_HEADS, WE,
    MM_SHIFT_QKV, MM_SHIFT_ATT_SCORE, MM_SHIFT_ATT_OUT, SCALE_SHIFT,
    generate_weights, tiled_matmul_int16_numpy, _transpose,
)
from verify.golden.layernorm import layernorm_golden
from verify.golden.softmax import softmax_golden
from verify.golden.common import int8, int16

TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
MODEL_COL_WORDS = MODEL_DIM // WE


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

    # Read RTL attn_concat
    path = os.path.join(TEST_DATA_DIR, "hbm_attn_concat_1k.hex")
    hbm_words = read_hex_dump(path)
    rtl_attn = []
    for r in range(BT):
        row = []
        for cw in range(MODEL_COL_WORDS):
            word_val = hbm_words[r * MODEL_COL_WORDS + cw] if (r * MODEL_COL_WORDS + cw) < len(hbm_words) else 0
            for e in range(WE):
                row.append(extract_int16_from_256bit(word_val, e))
        rtl_attn.append(row)

    # Analyze head 0 in detail
    h = 0
    Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q]
    K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K]
    V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V]
    K_h_T = _transpose(K_h)

    scores = tiled_matmul_int16_numpy(Q_h, K_h_T, TILE_SIZE, acc_shift=MM_SHIFT_ATT_SCORE)

    print(f"Head {h}, SCALE_SHIFT={SCALE_SHIFT}")
    print()

    # For each row that mismatches, try different mask boundaries
    for t in [3, 5, 7, 10]:
        print(f"=== Row {t} ===")
        print(f"  Scores[{t}][:10]: {[signed16(scores[t][j]) for j in range(10)]}")

        # Compute probs with different mask boundaries
        for mask_row in [t-1, t, t+1, t+2, None]:
            probs = softmax_golden(scores[t], scale_shift=SCALE_SHIFT, row_idx=mask_row)
            attn_out = [0] * HEAD_DIM
            for d in range(HEAD_DIM):
                acc = 0
                for j in range(BT):
                    acc += signed16(probs[j]) * signed16(V_h[j][d])
                attn_out[d] = int16(acc >> MM_SHIFT_ATT_OUT)

            # Compare with RTL
            rtl_row = rtl_attn[t][h*HEAD_DIM:(h+1)*HEAD_DIM]
            match = sum(1 for d in range(HEAD_DIM) if (attn_out[d] & 0xFFFF) == (rtl_row[d] & 0xFFFF))
            label = f"mask={mask_row}" if mask_row is not None else "mask=None(no causal)"
            if match > 0:
                print(f"  {label}: match={match}/{HEAD_DIM}  probs[:5]={[probs[j] for j in range(5)]}  attn[:4]={[signed16(attn_out[d]) for d in range(4)]}")
            else:
                print(f"  {label}: match=0/{HEAD_DIM}")

        print(f"  RTL attn[:4]: {[signed16(rtl_attn[t][h*HEAD_DIM+d]) for d in range(4)]}")
        print()

    # Also check: what if we compute attn_out using tiled_matmul instead of manual loop?
    print("=== Checking tiled_matmul attn_out vs manual for row 3 ===")
    probs_all = [softmax_golden(scores[t], scale_shift=SCALE_SHIFT, row_idx=t) for t in range(BT)]
    attn_tiled = tiled_matmul_int16_numpy(probs_all, V_h, TILE_SIZE, acc_shift=MM_SHIFT_ATT_OUT)
    for t in [3]:
        print(f"  Row {t} tiled: {[signed16(attn_tiled[t][d]) for d in range(8)]}")
        # Manual
        attn_manual = [0] * HEAD_DIM
        for d in range(HEAD_DIM):
            acc = 0
            for j in range(BT):
                acc += signed16(probs_all[t][j]) * signed16(V_h[j][d])
            attn_manual[d] = int16(acc >> MM_SHIFT_ATT_OUT)
        print(f"  Row {t} manual: {[signed16(attn_manual[d]) for d in range(8)]}")
        print(f"  Row {t} RTL:    {[signed16(rtl_attn[t][h*HEAD_DIM+d]) for d in range(8)]}")


if __name__ == "__main__":
    main()
