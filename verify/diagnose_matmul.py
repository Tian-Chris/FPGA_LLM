#!/usr/bin/env python3
"""Diagnose golden matmul accumulation order vs RTL sequential MAC.
Only checks a few specific elements to keep runtime manageable."""
import numpy as np
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

MODEL_DIM = 1024
F_DIM = 4096
TILE_SIZE = 32
BT = 32
SEED = 42

from verify.test_top_1k import generate_weights, compute_golden, tiled_matmul_fp16_numpy

rng_embed = np.random.RandomState(SEED + 2)
embed_fp16 = rng_embed.uniform(-0.5, 0.5, (BT, MODEL_DIM)).astype(np.float16)
embed_fp16_bits = embed_fp16.view(np.uint16).astype(int).tolist()

weights = generate_weights(seed=SEED)

print("Running golden model...")
g = compute_golden(embed_fp16_bits, weights)

# LN2 output as FP16 bit patterns → FP32
ln2_bits = np.array(g['ln2_out'], dtype=np.uint16)
wffn1_bits = np.array(weights['W_ffn1'], dtype=np.uint16)
ln2_fp32 = ln2_bits.view(np.float16).astype(np.float32)
wffn1_fp32 = wffn1_bits.view(np.float16).astype(np.float32)

# Golden FFN1 from test (uses numpy @)
golden_ffn1 = np.array(g['ffn1'], dtype=np.uint16)

print("\n" + "=" * 60)
print("Matmul accumulation order comparison (selected elements)")
print("=" * 60)

# Check specific (row, col) pairs
check_points = [(0,0), (0,1), (0,2), (0,3), (0,32), (0,160), (0,1600),
                (1,0), (1,1), (1,2), (1,3), (1,32), (1,160), (1,1600),
                (2,0), (2,1), (3,0), (3,1),
                (15,0), (31,0)]

for (i, j) in check_points:
    # Sequential MAC (matches RTL)
    acc = np.float32(0.0)
    for k in range(MODEL_DIM):
        prod = np.float32(ln2_fp32[i, k] * wffn1_fp32[k, j])
        acc = np.float32(acc + prod)
    seq_fp16 = np.float16(acc)
    seq_hex = f"{seq_fp16.view(np.uint16):04x}"

    # Numpy golden
    golden_hex = f"{golden_ffn1[i, j]:04x}"
    golden_val = float(golden_ffn1[i, j].view(np.float16))

    # Also try numpy @ on just this row×col
    np_val = np.float32(ln2_fp32[i:i+1, :] @ wffn1_fp32[:, j:j+1])[0, 0]
    np_fp16 = np.float16(np_val)
    np_hex = f"{np_fp16.view(np.uint16):04x}"

    diff = float(seq_fp16) - golden_val
    print(f"  [{i:2d},{j:4d}]: golden={golden_hex} ({golden_val:+10.4f})  "
          f"seq_mac={seq_hex} ({float(seq_fp16):+10.4f})  "
          f"np_dot={np_hex} ({float(np_fp16):+10.4f})  "
          f"diff_seq_golden={diff:+.6f}")

# Quick full-row comparison for rows 0 and 1
print("\n--- Full row comparison (numpy vs seq MAC) ---")
for row in [0, 1]:
    # Sequential MAC for full row
    seq_row = np.zeros(F_DIM, dtype=np.float16)
    for j in range(F_DIM):
        acc = np.float32(0.0)
        for k in range(MODEL_DIM):
            acc = np.float32(acc + np.float32(ln2_fp32[row, k] * wffn1_fp32[k, j]))
        seq_row[j] = np.float16(acc)

    golden_row = golden_ffn1[row].view(np.float16)
    abs_diff = np.abs(seq_row.astype(np.float64) - golden_row.astype(np.float64))
    exact = np.sum(seq_row.view(np.uint16) == golden_ffn1[row])
    print(f"  Row {row}: exact_match={exact}/{F_DIM} max_abs_diff={abs_diff.max():.6f} "
          f"mean_abs_diff={abs_diff.mean():.6f}")
