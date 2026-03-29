#!/usr/bin/env python3
"""Check if numpy int32 matmul overflow differs from RTL 32-bit wrapping at K=1024."""

import numpy as np
import os, sys, random

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.test_top_1k import (
    MODEL_DIM, TILE_SIZE, SEED, BT, WE,
    MM_SHIFT_QKV, MM_SHIFT_PROJ, MM_SHIFT_FFN1, MM_SHIFT_FFN2,
    generate_weights, _to_int16_array,
    tiled_matmul_int16_numpy,
)
from verify.golden.layernorm import layernorm_golden
from verify.golden.common import int8


def tiled_matmul_int16_wrapping(mat_a, mat_b, tile_size, acc_shift=0):
    """Same as tiled_matmul_int16_numpy but forces INT32 wrapping (matching RTL)."""
    A = _to_int16_array(mat_a)
    B = _to_int16_array(mat_b)
    M, K = A.shape
    _, N = B.shape
    result = np.zeros((M, N), dtype=np.int16)

    for ti in range(0, M, tile_size):
        te = min(ti + tile_size, M)
        for tj in range(0, N, tile_size):
            je = min(tj + tile_size, N)
            # Manual accumulation in int32 with wrapping
            tile_a = A[ti:te, :]  # (rows, K) int32
            tile_b = B[:, tj:je]  # (K, cols) int32
            rows = te - ti
            cols = je - tj
            acc = np.zeros((rows, cols), dtype=np.int32)
            for k in range(K):
                prod = tile_a[:, k:k+1].astype(np.int32) * tile_b[k:k+1, :].astype(np.int32)
                acc = (acc + prod).astype(np.int32)  # wraps on overflow
            if acc_shift > 0:
                acc = acc >> acc_shift
            result[ti:te, tj:je] = np.clip(acc, -32768, 32767).astype(np.int16)

    return result.astype(int).tolist()


def main():
    print(f"K={MODEL_DIM}, TILE_SIZE={TILE_SIZE}, BT={BT}")
    print(f"int32 max = {np.iinfo(np.int32).max}, min = {np.iinfo(np.int32).min}")

    # Generate same weights and inputs as test
    weights = generate_weights(seed=SEED)
    rng = random.Random(SEED + 2)
    embed_int8 = [[rng.randint(-2, 1) for _ in range(MODEL_DIM)] for _ in range(BT)]

    # LN1 (same as golden)
    gamma1 = [int8(v) for v in weights['gamma1']]
    beta1 = [int8(v) for v in weights['beta1']]
    embed_int16 = [[int8(v) & 0xFFFF for v in row] for row in embed_int8]
    ln1_out = [layernorm_golden(embed_int16[t], gamma1, beta1, MODEL_DIM) for t in range(BT)]

    # Check QKV matmul: numpy vs wrapping
    print("\n--- QKV matmul comparison ---")
    Q_numpy = tiled_matmul_int16_numpy(ln1_out, weights['W_q'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)
    Q_wrap = tiled_matmul_int16_wrapping(ln1_out, weights['W_q'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)

    # Check accumulation range
    A = _to_int16_array(ln1_out)
    B = _to_int16_array(weights['W_q'])
    test_acc = A[0:1, :].astype(np.int64) @ B[:, 0:1].astype(np.int64)
    print(f"  Sample acc[0][0] (int64): {test_acc[0,0]}")
    print(f"  As int32 (wrapped):      {np.int32(test_acc[0,0])}")
    print(f"  Fits int32?              {np.iinfo(np.int32).min <= test_acc[0,0] <= np.iinfo(np.int32).max}")

    # Check max accumulation magnitude across all elements
    full_acc_64 = A.astype(np.int64) @ B.astype(np.int64)
    print(f"  Max acc magnitude: {np.abs(full_acc_64).max()}")
    overflows = np.sum(
        (full_acc_64 > np.iinfo(np.int32).max) | (full_acc_64 < np.iinfo(np.int32).min)
    )
    print(f"  Elements overflowing int32: {overflows}/{full_acc_64.size}")

    # Compare results
    mismatches = 0
    for r in range(BT):
        for c in range(MODEL_DIM):
            if Q_numpy[r][c] != Q_wrap[r][c]:
                mismatches += 1
                if mismatches <= 5:
                    print(f"  MISMATCH [{r}][{c}]: numpy={Q_numpy[r][c]}, wrap={Q_wrap[r][c]}")
    print(f"  QKV mismatches: {mismatches}/{BT*MODEL_DIM}")

    # Check all matmul stages
    for name, w_key, shift in [
        ("W_q", 'W_q', MM_SHIFT_QKV),
        ("W_k", 'W_k', MM_SHIFT_QKV),
        ("W_v", 'W_v', MM_SHIFT_QKV),
        ("W_ffn1", 'W_ffn1', MM_SHIFT_FFN1),
    ]:
        An = _to_int16_array(ln1_out)
        Bn = _to_int16_array(weights[w_key])
        acc64 = An.astype(np.int64) @ Bn.astype(np.int64)
        ov = np.sum((acc64 > np.iinfo(np.int32).max) | (acc64 < np.iinfo(np.int32).min))
        print(f"  {name}: max_acc={np.abs(acc64).max()}, overflows={ov}/{acc64.size}")

    # Quick check: does numpy int32 @ int32 actually use int64?
    a32 = np.array([[np.iinfo(np.int32).max]], dtype=np.int32)
    b32 = np.array([[2]], dtype=np.int32)
    c = a32 @ b32
    print(f"\n  numpy int32 @ int32 result dtype: {c.dtype}")
    print(f"  int32_max * 2 = {c[0,0]} (should be {2*np.iinfo(np.int32).max} if int64)")


if __name__ == "__main__":
    main()
