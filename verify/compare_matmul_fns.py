#!/usr/bin/env python3
"""Compare tiled_matmul_int16 (manual) vs tiled_matmul_int16_numpy for 1k inputs."""

import os, sys, random
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.test_top_1k import (
    MODEL_DIM, F_DIM, TILE_SIZE, SEED, BT, HEAD_DIM, NUM_HEADS, SCALE_SHIFT,
    MM_SHIFT_QKV, MM_SHIFT_PROJ, MM_SHIFT_FFN1, MM_SHIFT_FFN2,
    MM_SHIFT_ATT_SCORE, MM_SHIFT_ATT_OUT,
    generate_weights, tiled_matmul_int16_numpy, _transpose,
)
from verify.test_top import tiled_matmul_int16  # manual version
from verify.golden.layernorm import layernorm_golden
from verify.golden.softmax import softmax_golden
from verify.golden.common import int8


def compare_mats(a, b, name, max_show=10):
    """Compare two list-of-lists matrices."""
    total = mis = 0
    diffs = []
    for r in range(len(a)):
        for c in range(len(a[0])):
            total += 1
            av = a[r][c] & 0xFFFF
            bv = b[r][c] & 0xFFFF
            if av != bv:
                mis += 1
                d = (a[r][c] & 0xFFFF) - (b[r][c] & 0xFFFF)
                if d > 32767: d -= 65536
                if d < -32768: d += 65536
                diffs.append(d)
                if mis <= max_show:
                    print(f"    [{r}][{c}]: manual={a[r][c]}, numpy={b[r][c]}, diff={d}")
    if mis > 0:
        print(f"  {name}: {mis}/{total} MISMATCHES")
        import statistics
        print(f"    diff stats: min={min(diffs)}, max={max(diffs)}, "
              f"mean={statistics.mean(diffs):.2f}, median={statistics.median(diffs)}")
    else:
        print(f"  {name}: {total}/{total} PERFECT MATCH")
    return mis


def main():
    print(f"Comparing manual vs numpy matmul at K={MODEL_DIM}")
    weights = generate_weights(seed=SEED)
    rng = random.Random(SEED + 2)
    embed_int8 = [[rng.randint(-2, 1) for _ in range(MODEL_DIM)] for _ in range(BT)]

    # LN1
    gamma1 = [int8(v) for v in weights['gamma1']]
    beta1 = [int8(v) for v in weights['beta1']]
    embed_int16 = [[int8(v) & 0xFFFF for v in row] for row in embed_int8]
    ln1_out = [layernorm_golden(embed_int16[t], gamma1, beta1, MODEL_DIM) for t in range(BT)]

    # QKV with both methods
    print("\n--- QKV matmuls ---")
    for name, key in [("W_q", 'W_q'), ("W_k", 'W_k'), ("W_v", 'W_v')]:
        r_np = tiled_matmul_int16_numpy(ln1_out, weights[key], TILE_SIZE, acc_shift=MM_SHIFT_QKV)
        r_man = tiled_matmul_int16(ln1_out, weights[key], TILE_SIZE, acc_shift=MM_SHIFT_QKV)
        compare_mats(r_man, r_np, name)

    # Full attention pipeline with manual method
    Q = tiled_matmul_int16(ln1_out, weights['W_q'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)
    K = tiled_matmul_int16(ln1_out, weights['W_k'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)
    V = tiled_matmul_int16(ln1_out, weights['W_v'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)

    Q_np = tiled_matmul_int16_numpy(ln1_out, weights['W_q'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)
    K_np = tiled_matmul_int16_numpy(ln1_out, weights['W_k'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)
    V_np = tiled_matmul_int16_numpy(ln1_out, weights['W_v'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)

    print("\n--- Attention scores (head 0) ---")
    Q_h = [row[0:HEAD_DIM] for row in Q]
    K_h = [row[0:HEAD_DIM] for row in K]
    K_h_T = _transpose(K_h)
    scores_man = tiled_matmul_int16(Q_h, K_h_T, TILE_SIZE, acc_shift=MM_SHIFT_ATT_SCORE)
    scores_np = tiled_matmul_int16_numpy(Q_h, K_h_T, TILE_SIZE, acc_shift=MM_SHIFT_ATT_SCORE)
    compare_mats(scores_man, scores_np, "scores_h0")

    # Now check: does OP_MATMUL_T in RTL match _transpose + matmul?
    # In test_top.py, scores = Q_h * K_h^T using _transpose
    # But the RTL does OP_MATMUL_T which is Q_h * K_h^T computed differently
    # Actually: OP_MATMUL_T means A×B^T in hardware, where B is stored row-major
    # The RTL reads K from ACT_K_OFFSET which has K row-major, then transposes internally
    # Golden uses _transpose to get K_h_T, then A×K_h_T
    # These should give the same result. Let's verify K layout is the same.

    print("\n--- Softmax + attention output (head 0) ---")
    probs = [softmax_golden(scores_np[t], scale_shift=SCALE_SHIFT, row_idx=t)
             for t in range(BT)]
    V_h = [row[0:HEAD_DIM] for row in V_np]
    attn_man = tiled_matmul_int16(probs, V_h, TILE_SIZE, acc_shift=MM_SHIFT_ATT_OUT)
    attn_np = tiled_matmul_int16_numpy(probs, V_h, TILE_SIZE, acc_shift=MM_SHIFT_ATT_OUT)
    compare_mats(attn_man, attn_np, "attn_out_h0")

    # Full pipeline: build concat, project, res1
    print("\n--- Full attention pipeline comparison ---")
    from verify.golden.residual_add import residual_add_golden

    # Using numpy throughout (same as test_top_1k)
    attn_concat_np = [[0] * MODEL_DIM for _ in range(BT)]
    for h in range(NUM_HEADS):
        Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q_np]
        K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K_np]
        V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V_np]
        K_h_T = _transpose(K_h)
        sc = tiled_matmul_int16_numpy(Q_h, K_h_T, TILE_SIZE, acc_shift=MM_SHIFT_ATT_SCORE)
        pr = [softmax_golden(sc[t], scale_shift=SCALE_SHIFT, row_idx=t) for t in range(BT)]
        ao = tiled_matmul_int16_numpy(pr, V_h, TILE_SIZE, acc_shift=MM_SHIFT_ATT_OUT)
        for t in range(BT):
            for d in range(HEAD_DIM):
                attn_concat_np[t][h*HEAD_DIM + d] = ao[t][d]

    # Using manual throughout (same as test_top)
    attn_concat_man = [[0] * MODEL_DIM for _ in range(BT)]
    for h in range(NUM_HEADS):
        Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q]
        K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K]
        V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V]
        K_h_T = _transpose(K_h)
        sc = tiled_matmul_int16(Q_h, K_h_T, TILE_SIZE, acc_shift=MM_SHIFT_ATT_SCORE)
        pr = [softmax_golden(sc[t], scale_shift=SCALE_SHIFT, row_idx=t) for t in range(BT)]
        ao = tiled_matmul_int16(pr, V_h, TILE_SIZE, acc_shift=MM_SHIFT_ATT_OUT)
        for t in range(BT):
            for d in range(HEAD_DIM):
                attn_concat_man[t][h*HEAD_DIM + d] = ao[t][d]

    compare_mats(attn_concat_man, attn_concat_np, "attn_concat (manual vs numpy)")

    proj_np = tiled_matmul_int16_numpy(attn_concat_np, weights['W_o'], TILE_SIZE, acc_shift=MM_SHIFT_PROJ)
    proj_man = tiled_matmul_int16(attn_concat_man, weights['W_o'], TILE_SIZE, acc_shift=MM_SHIFT_PROJ)
    compare_mats(proj_man, proj_np, "proj (manual vs numpy)")

    embed_s = [[int8(v) for v in row] for row in embed_int8]
    embed16 = [[e & 0xFFFF for e in row] for row in embed_s]
    res1_np = [residual_add_golden(embed16[t], proj_np[t]) for t in range(BT)]
    res1_man = [residual_add_golden(embed16[t], proj_man[t]) for t in range(BT)]
    compare_mats(res1_man, res1_np, "res1 (manual vs numpy)")

    # LN2
    from verify.golden.layernorm import layernorm_golden as ln_g
    ln2_np = [ln_g(res1_np[t], weights['gamma2'], weights['beta2'], MODEL_DIM) for t in range(BT)]
    ln2_man = [ln_g(res1_man[t], weights['gamma2'], weights['beta2'], MODEL_DIM) for t in range(BT)]
    compare_mats(ln2_man, ln2_np, "ln2 (manual vs numpy)")

    # FFN1
    ffn1_np = tiled_matmul_int16_numpy(ln2_np, weights['W_ffn1'], TILE_SIZE, acc_shift=MM_SHIFT_FFN1)
    ffn1_man = tiled_matmul_int16(ln2_man, weights['W_ffn1'], TILE_SIZE, acc_shift=MM_SHIFT_FFN1)
    compare_mats(ffn1_man, ffn1_np, "ffn1 (manual vs numpy)")

    print("\n--- Cross-check: test_top manual golden vs RTL ---")
    print("  If manual==numpy above and numpy!=RTL (from diagnose_1k), then RTL is wrong")
    print("  If manual!=numpy above, then the golden model choice matters")


if __name__ == "__main__":
    main()
