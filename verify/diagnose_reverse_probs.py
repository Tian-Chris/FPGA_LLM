#!/usr/bin/env python3
"""Reverse-engineer what softmax probs the RTL must be using."""

import os, sys, random
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.test_top_1k import (
    MODEL_DIM, TILE_SIZE, SEED, BT, HEAD_DIM, NUM_HEADS, WE,
    MM_SHIFT_QKV, MM_SHIFT_ATT_SCORE, MM_SHIFT_ATT_OUT, SCALE_SHIFT,
    generate_weights, tiled_matmul_int16_numpy, _transpose,
)
from verify.golden.layernorm import layernorm_golden
from verify.golden.softmax import softmax_golden, compute_exp, normalize
from verify.golden.common import int8, int16, uint32

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

    h = 0
    Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q]
    K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K]
    V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V]
    K_h_T = _transpose(K_h)

    scores = tiled_matmul_int16_numpy(Q_h, K_h_T, TILE_SIZE, acc_shift=MM_SHIFT_ATT_SCORE)

    print("=== V_h values ===")
    for t in range(min(5, BT)):
        print(f"  V_h[{t}][:8]: {[signed16(V_h[t][d]) for d in range(8)]}")

    print()
    print("=== Golden scores for head 0 ===")
    for t in range(min(8, BT)):
        sc = [signed16(scores[t][j]) for j in range(min(10, BT))]
        print(f"  scores[{t}][:10]: {sc}")

    # Compute golden probs for row 3
    t = 3
    print(f"\n=== Softmax analysis for row {t} ===")
    raw_scores = [signed16(scores[t][j]) for j in range(BT)]
    scaled = [int16(int16(x) >> SCALE_SHIFT) for x in raw_scores]
    print(f"  Raw scores[:8]: {raw_scores[:8]}")
    print(f"  Scaled (>>3)[:8]: {scaled[:8]}")

    # With mask
    mask_max = max(scaled[j] for j in range(t+1))
    no_mask_max = max(scaled)
    print(f"  Max (masked, idx 0..{t}): {mask_max}")
    print(f"  Max (no mask): {no_mask_max}")

    # Compute exp for each position with CORRECT masking
    for mask_row in [t]:
        exp_vals = []
        exp_sum = 0
        for j in range(BT):
            if j > mask_row:
                exp_vals.append(0)
            else:
                e = compute_exp(scaled[j], mask_max)
                exp_vals.append(e)
                exp_sum += e
        print(f"\n  mask={mask_row}: exp_vals[:10] = {exp_vals[:10]}")
        print(f"  exp_sum = {exp_sum} (0x{exp_sum:X})")
        probs = [normalize(e, exp_sum) for e in exp_vals]
        print(f"  probs[:10] = {probs[:10]}")
        prob_sum = sum(probs)
        print(f"  prob_sum = {prob_sum}")

    # Now check: what if the scores were ALL the same (e.g., all 5 or all 6)?
    print(f"\n=== What if scores were uniform? ===")
    for uniform_score in [5, 6, 0]:
        uniform_scores = [uniform_score] * BT
        probs = softmax_golden(uniform_scores, scale_shift=SCALE_SHIFT, row_idx=t)
        # Compute attn_out with these probs
        attn_out = [0] * 8
        for d in range(8):
            acc = 0
            for j in range(BT):
                acc += signed16(probs[j]) * signed16(V_h[j][d])
            attn_out[d] = int16(acc >> MM_SHIFT_ATT_OUT)
        print(f"  uniform_score={uniform_score}: probs[:5]={probs[:5]}, attn[:4]={attn_out[:4]}")

    # Read the RTL probs from HBM (ACT_ATTN_OFFSET) if available
    # The probs are flushed to ACT_ATTN_OFFSET before attn_out matmul
    # But we don't have a dump of that... let me check what we DO have

    # Let's try to reverse-engineer: given RTL attn_out and V_h, what probs were used?
    print(f"\n=== Reverse-engineering RTL probs ===")
    # Read RTL attn_concat
    path = os.path.join(TEST_DATA_DIR, "hbm_attn_concat_1k.hex")
    hbm_words = read_hex_dump(path)
    rtl_row = []
    for cw in range(HEAD_DIM // WE):
        w = hbm_words[t * MODEL_COL_WORDS + h * (HEAD_DIM // WE) + cw]
        for e in range(WE):
            rtl_row.append(extract_int16_from_256bit(w, e))
    print(f"  RTL attn_out[{t}] head {h} [:8]: {rtl_row[:8]}")

    # attn_out[d] = sum(prob[j] * V_h[j][d]) >> 4
    # So sum(prob[j] * V_h[j][d]) = attn_out[d] << 4  (approximately)
    # If we assume uniform probs = p for positions 0..t, then:
    #   attn_out[d] ≈ (p * sum(V_h[j][d] for j in 0..t)) >> 4
    for d in [0, 1]:
        V_sum = sum(signed16(V_h[j][d]) for j in range(t+1))
        print(f"  d={d}: sum(V[0..{t}][{d}]) = {V_sum}")
        if V_sum != 0:
            # rtl_attn[d] = (prob * V_sum) >> 4
            # prob = (rtl_attn[d] << 4) / V_sum
            implied_prob = (rtl_row[d] << MM_SHIFT_ATT_OUT) / V_sum
            print(f"    Implied prob = ({rtl_row[d]} << {MM_SHIFT_ATT_OUT}) / {V_sum} = {implied_prob:.1f}")
            # With mask=3 (4 positions), uniform prob = 65535/4 = 16383
            # With mask=3 but wrong scores: prob could be anything

    # Let me try: what if nm_row_cnt was offset by 1? i.e., softmax for
    # row 3 actually reads scores from URAM row 2 (due to off-by-one in nm_addr_offset)
    print(f"\n=== What if nm_addr_offset is off by ±1 row? ===")
    for offset in [-1, 0, 1]:
        src_row = t + offset
        if src_row < 0 or src_row >= BT:
            continue
        probs = softmax_golden(scores[src_row], scale_shift=SCALE_SHIFT, row_idx=t)
        attn_out = [0] * 8
        for d in range(8):
            acc = 0
            for j in range(BT):
                acc += signed16(probs[j]) * signed16(V_h[j][d])
            attn_out[d] = int16(acc >> MM_SHIFT_ATT_OUT)
        match = sum(1 for d in range(HEAD_DIM) if (int16(attn_out[d]) & 0xFFFF) == (rtl_row[d] & 0xFFFF))
        print(f"  offset={offset:+d} (scores[{src_row}]): match={match}/{HEAD_DIM}  attn[:4]={[signed16(attn_out[d]) for d in range(4)]}")


if __name__ == "__main__":
    main()
