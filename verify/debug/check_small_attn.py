#!/usr/bin/env python3
"""Check SIM_SMALL attention intermediates to verify softmax behavior."""

import os, sys, random
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.test_top import (
    MODEL_DIM, NUM_HEADS, HEAD_DIM, BT, TILE_SIZE, WE, SEED,
    MM_SHIFT_ATT_SCORE, MM_SHIFT_ATT_OUT, SCALE_SHIFT,
    tiled_matmul_int16, generate_weights,
)
from verify.golden.layernorm import layernorm_golden
from verify.golden.softmax import softmax_golden
from verify.golden.common import int8, int16


def main():
    print(f"SIM_SMALL: MODEL_DIM={MODEL_DIM}, HEAD_DIM={HEAD_DIM}, NUM_HEADS={NUM_HEADS}")
    print(f"BT={BT}, TILE_SIZE={TILE_SIZE}, WE={WE}")
    print(f"MM_SHIFT_ATT_SCORE={MM_SHIFT_ATT_SCORE}, SCALE_SHIFT={SCALE_SHIFT}")

    weights = generate_weights(seed=SEED)
    rng = random.Random(SEED + 2)
    embed_int8 = [[rng.randint(-2, 1) for _ in range(MODEL_DIM)] for _ in range(BT)]

    # LN1
    gamma1 = [int8(v) for v in weights['gamma1']]
    beta1 = [int8(v) for v in weights['beta1']]
    embed_int16 = [[int8(v) & 0xFFFF for v in row] for row in embed_int8]
    ln1_out = [layernorm_golden(embed_int16[t], gamma1, beta1, MODEL_DIM) for t in range(BT)]

    # QKV
    Q = tiled_matmul_int16(ln1_out, weights['W_q'], TILE_SIZE, acc_shift=7)
    K = tiled_matmul_int16(ln1_out, weights['W_k'], TILE_SIZE, acc_shift=7)
    V = tiled_matmul_int16(ln1_out, weights['W_v'], TILE_SIZE, acc_shift=7)

    print(f"\nQ[0][:8]: {Q[0][:8]}")
    print(f"Q[1][:8]: {Q[1][:8]}")
    print(f"K[0][:8]: {K[0][:8]}")
    print(f"V[0][:8]: {V[0][:8]}")

    # Attention head 0
    h = 0
    Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q]
    K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K]
    V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V]

    # Compute K_h^T
    K_h_T = [[K_h[r][c] for r in range(BT)] for c in range(HEAD_DIM)]

    # Scores
    scores_h = tiled_matmul_int16(Q_h, K_h_T, TILE_SIZE, acc_shift=MM_SHIFT_ATT_SCORE)
    print(f"\n--- Scores for head 0 ---")
    for t in range(BT):
        print(f"  scores[{t}]: {scores_h[t]}")

    # Softmax with correct scores
    print(f"\n--- Softmax probs (golden, correct scores) ---")
    probs_golden = [softmax_golden(scores_h[t], scale_shift=SCALE_SHIFT, row_idx=t)
                    for t in range(BT)]
    for t in range(BT):
        print(f"  probs[{t}]: {probs_golden[t]}")

    # Softmax with wrong scores (zeros, as RTL would read)
    print(f"\n--- Softmax probs (RTL wrong mapping: zeros) ---")
    zero_scores = [0] * BT
    probs_zeros = [softmax_golden(zero_scores, scale_shift=SCALE_SHIFT, row_idx=t)
                   for t in range(BT)]
    for t in range(BT):
        print(f"  probs_wrong[{t}]: {probs_zeros[t]}")

    # Attention output with correct probs
    attn_golden = tiled_matmul_int16(probs_golden, V_h, TILE_SIZE, acc_shift=MM_SHIFT_ATT_OUT)
    print(f"\n--- Attention output head 0 (correct probs) ---")
    for t in range(BT):
        print(f"  attn[{t}]: {attn_golden[t][:8]}")

    # Attention output with wrong probs
    attn_wrong = tiled_matmul_int16(probs_zeros, V_h, TILE_SIZE, acc_shift=MM_SHIFT_ATT_OUT)
    print(f"\n--- Attention output head 0 (wrong probs from zeros) ---")
    for t in range(BT):
        print(f"  attn_wrong[{t}]: {attn_wrong[t][:8]}")

    # Compare
    print(f"\n--- Comparison: correct vs wrong probs ---")
    for t in range(BT):
        diffs = [attn_golden[t][d] - attn_wrong[t][d] for d in range(HEAD_DIM)]
        max_diff = max(abs(d) for d in diffs)
        print(f"  row {t}: max_diff={max_diff}, first diffs={diffs[:8]}")


if __name__ == "__main__":
    main()
