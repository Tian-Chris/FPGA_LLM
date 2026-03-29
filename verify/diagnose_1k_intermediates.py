#!/usr/bin/env python3
"""Compare intermediate URAM dumps from 1k test against golden model."""

import os, sys, random
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.test_top_1k import (
    MODEL_DIM, F_DIM, TILE_SIZE, SEED, BT, HEAD_DIM, NUM_HEADS, WE,
    MM_SHIFT_QKV, MM_SHIFT_PROJ, MM_SHIFT_FFN1, MM_SHIFT_FFN2,
    MM_SHIFT_ATT_SCORE, MM_SHIFT_ATT_OUT, SCALE_SHIFT,
    generate_weights, tiled_matmul_int16_numpy, _transpose,
    ACT_BASE, ACT_EMBED_OFFSET, MODEL_STRIDE,
    URAM_COL_WORDS,
)
from verify.golden.layernorm import layernorm_golden
from verify.golden.softmax import softmax_golden
from verify.golden.residual_add import residual_add_golden
from verify.golden.common import int8, int16

TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")

# URAM layout: row r, col word c -> index r * URAM_COL_WORDS_HW + c
# But our dump uses MODEL_DIM/WE = 64 col words per row (only the used portion)
MODEL_COL_WORDS = MODEL_DIM // WE  # 64
F_COL_WORDS = F_DIM // WE  # 256


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


def extract_matrix_from_uram_dump(uram_words, num_rows, num_col_words, dump_col_words):
    """Extract matrix from URAM dump. dump_col_words is cols stored per row in dump file."""
    mat = []
    for r in range(num_rows):
        row = []
        for cw in range(num_col_words):
            word_idx = r * dump_col_words + cw
            word_val = uram_words[word_idx] if word_idx < len(uram_words) else 0
            for e in range(WE):
                row.append(extract_int16_from_256bit(word_val, e))
        mat.append(row)
    return mat


def compare_brief(golden_mat, rtl_mat, name, num_cols, show_rows=3, show_cols=8):
    total = match = 0
    diffs = []
    first_mis = None
    for r in range(len(golden_mat)):
        for c in range(num_cols):
            gv = golden_mat[r][c]
            rv = rtl_mat[r][c]
            total += 1
            if (gv & 0xFFFF) == (rv & 0xFFFF):
                match += 1
            else:
                d = signed16(rv) - signed16(gv)
                diffs.append(d)
                if first_mis is None:
                    first_mis = (r, c, gv, rv)

    pct = 100.0 * match / total if total > 0 else 0
    mis = total - match
    print(f"  {name}: {match}/{total} match ({pct:.1f}%), {mis} mismatches")
    if diffs:
        import statistics
        print(f"    diff stats: min={min(diffs)}, max={max(diffs)}, "
              f"mean={statistics.mean(diffs):.2f}, median={statistics.median(diffs)}")
    if first_mis and show_rows > 0:
        r, c, gv, rv = first_mis
        print(f"    first mismatch: [{r}][{c}] golden={signed16(gv)} rtl={signed16(rv)}")
        for r in range(min(show_rows, len(golden_mat))):
            gc = [signed16(golden_mat[r][c]) for c in range(min(show_cols, num_cols))]
            rc = [signed16(rtl_mat[r][c]) for c in range(min(show_cols, num_cols))]
            print(f"    row[{r}] golden: {gc}")
            print(f"    row[{r}] rtl:    {rc}")
    elif not diffs:
        print(f"    PERFECT MATCH")
    return match, total


def relu_golden(v):
    s = signed16(v)
    return max(0, s)


def main():
    print("=" * 70)
    print("  1K Intermediate URAM Dump Comparison")
    print("=" * 70)

    # Generate golden
    weights = generate_weights(seed=SEED)
    rng = random.Random(SEED + 2)
    embed_int8 = [[rng.randint(-2, 1) for _ in range(MODEL_DIM)] for _ in range(BT)]

    gamma1 = [int8(v) for v in weights['gamma1']]
    beta1 = [int8(v) for v in weights['beta1']]
    embed_int16 = [[int8(v) for v in row] for row in embed_int8]
    ln1_out = [layernorm_golden(embed_int16[t], gamma1, beta1, MODEL_DIM) for t in range(BT)]

    # QKV
    Q = tiled_matmul_int16_numpy(ln1_out, weights['W_q'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)
    K = tiled_matmul_int16_numpy(ln1_out, weights['W_k'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)
    V = tiled_matmul_int16_numpy(ln1_out, weights['W_v'], TILE_SIZE, acc_shift=MM_SHIFT_QKV)

    # Attention
    print("\n  Computing golden attention...")
    attn_concat = [[0] * MODEL_DIM for _ in range(BT)]
    for h in range(NUM_HEADS):
        Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q]
        K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K]
        V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in V]
        K_h_T = _transpose(K_h)
        sc = tiled_matmul_int16_numpy(Q_h, K_h_T, TILE_SIZE, acc_shift=MM_SHIFT_ATT_SCORE)
        pr = [softmax_golden(sc[t], scale_shift=SCALE_SHIFT, row_idx=t) for t in range(BT)]
        ao = tiled_matmul_int16_numpy(pr, V_h, TILE_SIZE, acc_shift=MM_SHIFT_ATT_OUT)
        for t in range(BT):
            for d in range(HEAD_DIM):
                attn_concat[t][h*HEAD_DIM + d] = ao[t][d]

    # Projection
    attn_proj = tiled_matmul_int16_numpy(attn_concat, weights['W_o'], TILE_SIZE, acc_shift=MM_SHIFT_PROJ)

    # Residual1
    residual1 = [residual_add_golden(embed_int16[t], attn_proj[t]) for t in range(BT)]

    # LN2
    gamma2 = [int8(v) for v in weights['gamma2']]
    beta2 = [int8(v) for v in weights['beta2']]
    ln2_out = [layernorm_golden(residual1[t], gamma2, beta2, MODEL_DIM) for t in range(BT)]

    # FFN1
    ffn1 = tiled_matmul_int16_numpy(ln2_out, weights['W_ffn1'], TILE_SIZE, acc_shift=MM_SHIFT_FFN1)

    # ReLU
    ffn_act = [[relu_golden(v) for v in row] for row in ffn1]

    # FFN2
    ffn2 = tiled_matmul_int16_numpy(ffn_act, weights['W_ffn2'], TILE_SIZE, acc_shift=MM_SHIFT_FFN2)

    # Residual2
    residual2 = [residual_add_golden(residual1[t], ffn2[t]) for t in range(BT)]

    # =====================================================================
    # Compare with RTL URAM dumps
    # =====================================================================
    print("\n" + "=" * 70)
    print("  Stage Comparisons")
    print("=" * 70)

    # After step 3: attn_concat from flush HBM at ACT_Q_OFFSET
    path = os.path.join(TEST_DATA_DIR, "hbm_attn_concat_1k.hex")
    if os.path.exists(path):
        print(f"\n--- After Step 3: Attention Concat (flush HBM @ ACT_Q) ---")
        hbm_words = read_hex_dump(path)
        # Dump is BT rows × MODEL_STRIDE words, stored linearly
        rtl_attn = []
        for r in range(BT):
            row = []
            for cw in range(MODEL_COL_WORDS):
                word_val = hbm_words[r * MODEL_COL_WORDS + cw] if (r * MODEL_COL_WORDS + cw) < len(hbm_words) else 0
                for e in range(WE):
                    row.append(extract_int16_from_256bit(word_val, e))
            rtl_attn.append(row)
        compare_brief(attn_concat, rtl_attn, "attn_concat", MODEL_DIM)
    else:
        print(f"\n  hbm_attn_concat_1k.hex not found")

    # After step 4: projection result in URAM (BT rows × MODEL_DIM cols)
    path = os.path.join(TEST_DATA_DIR, "uram_after_proj_1k.hex")
    if os.path.exists(path):
        print(f"\n--- After Step 4: Projection (URAM) ---")
        uram = read_hex_dump(path)
        rtl_proj = extract_matrix_from_uram_dump(uram, BT, MODEL_COL_WORDS, MODEL_COL_WORDS)
        compare_brief(attn_proj, rtl_proj, "attn_proj", MODEL_DIM)
    else:
        print(f"\n  uram_after_proj_1k.hex not found")

    # After step 5: res1 in URAM
    path = os.path.join(TEST_DATA_DIR, "uram_after_res1_1k.hex")
    if os.path.exists(path):
        print(f"\n--- After Step 5: Residual 1 (URAM) ---")
        uram = read_hex_dump(path)
        rtl_res1 = extract_matrix_from_uram_dump(uram, BT, MODEL_COL_WORDS, MODEL_COL_WORDS)
        compare_brief(residual1, rtl_res1, "residual1", MODEL_DIM)

        # Cross-check: does RTL res1 match embed + RTL proj?
        if os.path.exists(os.path.join(TEST_DATA_DIR, "uram_after_proj_1k.hex")):
            print("\n  Cross-check: embed + RTL_proj vs RTL_res1")
            rtl_proj2 = extract_matrix_from_uram_dump(
                read_hex_dump(os.path.join(TEST_DATA_DIR, "uram_after_proj_1k.hex")),
                BT, MODEL_COL_WORDS, MODEL_COL_WORDS)
            expected_res1 = [residual_add_golden(embed_int16[t], [signed16(v) for v in rtl_proj2[t]])
                             for t in range(BT)]
            compare_brief(expected_res1, rtl_res1, "embed+RTL_proj vs RTL_res1", MODEL_DIM,
                          show_rows=2)
    else:
        print(f"\n  uram_after_res1_1k.hex not found")

    # After step 9: FFN1 result in URAM (BT rows × F_DIM cols)
    # Dump now uses full HW stride (256 col words per row)
    URAM_COL_WORDS_HW = 256
    path = os.path.join(TEST_DATA_DIR, "uram_after_ffn1_1k.hex")
    if os.path.exists(path):
        print(f"\n--- After Step 9: FFN1 (URAM, full F_DIM width) ---")
        uram = read_hex_dump(path)
        rtl_ffn1 = extract_matrix_from_uram_dump(uram, BT, F_COL_WORDS, URAM_COL_WORDS_HW)
        compare_brief(ffn1, rtl_ffn1, "ffn1", F_DIM, show_rows=2, show_cols=16)
    else:
        print(f"\n  uram_after_ffn1_1k.hex not found")

    # After step 10: ReLU result in URAM (BT rows × F_DIM cols)
    path = os.path.join(TEST_DATA_DIR, "uram_after_relu_1k.hex")
    if os.path.exists(path):
        print(f"\n--- After Step 10: ReLU (URAM, full F_DIM width) ---")
        uram = read_hex_dump(path)
        rtl_relu = extract_matrix_from_uram_dump(uram, BT, F_COL_WORDS, URAM_COL_WORDS_HW)
        compare_brief(ffn_act, rtl_relu, "relu", F_DIM, show_rows=2, show_cols=16)
    else:
        print(f"\n  uram_after_relu_1k.hex not found")

    # After step 12: FFN2 result in URAM (BT rows × MODEL_DIM cols)
    path = os.path.join(TEST_DATA_DIR, "uram_after_ffn2_1k.hex")
    if os.path.exists(path):
        print(f"\n--- After Step 12: FFN2 (URAM) ---")
        uram = read_hex_dump(path)
        rtl_ffn2 = extract_matrix_from_uram_dump(uram, BT, MODEL_COL_WORDS, MODEL_COL_WORDS)
        compare_brief(ffn2, rtl_ffn2, "ffn2", MODEL_DIM)
    else:
        print(f"\n  uram_after_ffn2_1k.hex not found")

    # Final: res2 in URAM
    path = os.path.join(TEST_DATA_DIR, "uram_1k_full_dump.hex")
    if os.path.exists(path):
        print(f"\n--- Final: Residual 2 (URAM) ---")
        uram = read_hex_dump(path)
        rtl_res2 = extract_matrix_from_uram_dump(uram, BT, MODEL_COL_WORDS, MODEL_COL_WORDS)
        compare_brief(residual2, rtl_res2, "residual2", MODEL_DIM)


if __name__ == "__main__":
    main()
