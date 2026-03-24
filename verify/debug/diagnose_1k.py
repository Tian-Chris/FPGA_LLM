#!/usr/bin/env python3
"""Diagnostic script for 1K production test mismatches.

Reads the RTL dump files (flush HBM, URAM, DMA HBM) and compares each
available pipeline stage against the golden model to pinpoint where
divergence first appears.

Flush HBM final state (after all mirroring):
  ACT_EMBED  -> residual2 (step 14 overwrites step 6's res1)
  ACT_TEMP   -> LN2 output (step 8 overwrites step 1's LN1)
  ACT_Q/FFN  -> ffn_act (step 11 overwrites step 3's attn_out)
  ACT_K      -> K projection (survives, not overwritten)
  ACT_V      -> V projection (survives, not overwritten)
  ACT_ATTN   -> last head's attention scores (overwritten each head)

URAM final state: residual2 (step 13 result, before flush)

DMA HBM: original embeddings + LN params, then res1 mirrored over
          ACT_EMBED at step 6, then res2 mirrored over at step 14.

Usage:
  python3 verify/diagnose_1k.py
"""

import math
import os
import sys
import random
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.golden.common import int8, int16, int32, saturate_int16
from verify.golden.softmax import softmax_golden
from verify.golden.layernorm import layernorm_golden
from verify.golden.activation import relu_golden
from verify.golden.residual_add import residual_add_golden

from verify.test_top import (
    read_hex_dump, extract_int16_from_256bit,
    extract_matrix_from_hbm, extract_matrix_from_uram,
    hex16,
)

# Import the numpy-accelerated tiled matmul from the 1k test
from verify.test_top_1k import (
    tiled_matmul_int16_numpy, generate_weights, compute_golden,
    MODEL_DIM, NUM_HEADS, HEAD_DIM, SCALE_SHIFT, F_DIM, INPUT_DIM,
    MAX_SEQ_LEN, TILE_SIZE, NUM_ENGINES, SEQ_LEN, BATCH, BT,
    DATA_W, BUS_ELEMS, URAM_ROWS, URAM_COLS, URAM_COL_WORDS,
    SIM_HBM_DEPTH, SEED,
    MM_SHIFT_QKV, MM_SHIFT_PROJ, MM_SHIFT_FFN1, MM_SHIFT_FFN2,
    MM_SHIFT_ATT_SCORE, MM_SHIFT_ATT_OUT,
    WEIGHT_BASE, ACT_BASE,
    LAYER_WQ_OFFSET, LAYER_WK_OFFSET, LAYER_WV_OFFSET, LAYER_WO_OFFSET,
    LAYER_FFN1_OFFSET, LAYER_FFN2_OFFSET, LAYER_LN1_OFFSET, LAYER_LN2_OFFSET,
    LAYER_SIZE,
    MODEL_STRIDE, F_STRIDE,
    ACT_EMBED_OFFSET, ACT_Q_OFFSET,
    ACT_ATTN_OFFSET, ACT_TEMP_OFFSET, ACT_FFN_OFFSET,
    KV_BASE, KV_V_OFFSET,
)

WE = BUS_ELEMS  # 16

TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")


# ---------------------------------------------------------------------------
# Signed comparison helper
# ---------------------------------------------------------------------------
def to_signed16(val):
    """Convert unsigned 16-bit to signed."""
    val = val & 0xFFFF
    return val - 0x10000 if val >= 0x8000 else val


def compare_stage(golden_mat, rtl_mat, name, max_detail=20):
    """Compare two matrices element-by-element. Print summary and first mismatches.

    Returns (match_count, mismatch_count).
    """
    rows_g = len(golden_mat)
    cols_g = len(golden_mat[0]) if rows_g else 0
    rows_r = len(rtl_mat)
    cols_r = len(rtl_mat[0]) if rows_r else 0

    if rows_g != rows_r or cols_g != cols_r:
        print(f"  {name}: SHAPE MISMATCH golden [{rows_g}x{cols_g}] vs rtl [{rows_r}x{cols_r}]")
        return 0, rows_g * cols_g

    ok = 0
    mis = 0
    diffs = []

    for r in range(rows_g):
        for c in range(cols_g):
            gv = golden_mat[r][c] & 0xFFFF
            rv = rtl_mat[r][c] & 0xFFFF
            if gv == rv:
                ok += 1
            else:
                mis += 1
                gs = to_signed16(gv)
                rs = to_signed16(rv)
                diff = rs - gs
                if len(diffs) < max_detail:
                    diffs.append((r, c, gs, rs, diff))

    total = ok + mis
    if mis == 0:
        print(f"  {name}: PASS ({total} elements match)")
    else:
        print(f"  {name}: FAIL ({mis}/{total} mismatches)")

        # Compute diff statistics
        all_diffs = []
        for r in range(rows_g):
            for c in range(cols_g):
                gv = golden_mat[r][c] & 0xFFFF
                rv = rtl_mat[r][c] & 0xFFFF
                if gv != rv:
                    all_diffs.append(to_signed16(rv) - to_signed16(gv))

        all_diffs_arr = np.array(all_diffs)
        print(f"    Diff stats: min={all_diffs_arr.min()}, max={all_diffs_arr.max()}, "
              f"mean={all_diffs_arr.mean():.2f}, median={np.median(all_diffs_arr):.1f}, "
              f"std={all_diffs_arr.std():.2f}")

        # Show histogram of diff values
        unique_vals, counts = np.unique(all_diffs_arr, return_counts=True)
        if len(unique_vals) <= 20:
            print(f"    Diff distribution:")
            for v, c in zip(unique_vals, counts):
                print(f"      diff={v:+d}: {c} occurrences")
        else:
            print(f"    Diff distribution ({len(unique_vals)} unique values, showing top 10):")
            top_idx = np.argsort(-counts)[:10]
            for i in top_idx:
                print(f"      diff={unique_vals[i]:+d}: {counts[i]} occurrences")

        # Show first few mismatches
        print(f"    First {len(diffs)} mismatches:")
        for r, c, gs, rs, diff in diffs:
            print(f"      [{r:3d}][{c:4d}]: golden={gs:6d} (0x{gs & 0xFFFF:04x})  "
                  f"rtl={rs:6d} (0x{rs & 0xFFFF:04x})  diff={diff:+d}")

    return ok, mis


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 70)
    print("  1K Production Test Diagnostic — Stage-by-Stage Comparison")
    print("=" * 70)
    print(f"  BT={BT}, MODEL_DIM={MODEL_DIM}, F_DIM={F_DIM}, "
          f"NUM_HEADS={NUM_HEADS}, HEAD_DIM={HEAD_DIM}")
    print(f"  ACT_BASE={ACT_BASE}, LAYER_SIZE={LAYER_SIZE}")
    print()

    # ------------------------------------------------------------------
    # Check dump files exist
    # ------------------------------------------------------------------
    flush_path = os.path.join(TEST_DATA_DIR, "hbm_flush_1k_full_dump.hex")
    uram_path  = os.path.join(TEST_DATA_DIR, "uram_1k_full_dump.hex")
    dma_path   = os.path.join(TEST_DATA_DIR, "hbm_dma_1k_dump.hex")

    for path, label in [(flush_path, "flush HBM"), (uram_path, "URAM"), (dma_path, "DMA HBM")]:
        if os.path.exists(path):
            print(f"  Found {label} dump: {path}")
        else:
            print(f"  WARNING: {label} dump not found: {path}")

    if not os.path.exists(flush_path):
        print("\n  FATAL: flush HBM dump required. Run the simulation first.")
        sys.exit(1)

    # ------------------------------------------------------------------
    # Generate golden model
    # ------------------------------------------------------------------
    print("\n  Generating golden model...")
    weights = generate_weights(seed=SEED)

    rng = random.Random(SEED + 2)
    embed_int8 = [
        [rng.randint(-2, 1) for _ in range(MODEL_DIM)]
        for _ in range(BT)
    ]

    g = compute_golden(embed_int8, weights)
    print("  Golden model complete.\n")

    # ------------------------------------------------------------------
    # Read RTL dumps
    # ------------------------------------------------------------------
    print("  Reading flush HBM dump...")
    flush_words = read_hex_dump(flush_path)
    print(f"    {len(flush_words)} words read")

    uram_words = None
    if os.path.exists(uram_path):
        print("  Reading URAM dump...")
        uram_words = read_hex_dump(uram_path)
        print(f"    {len(uram_words)} words read")

    dma_words = None
    if os.path.exists(dma_path):
        print("  Reading DMA HBM dump...")
        dma_words = read_hex_dump(dma_path)
        print(f"    {len(dma_words)} words read")

    # ------------------------------------------------------------------
    # Stage-by-stage comparison
    # ------------------------------------------------------------------
    print("\n" + "=" * 70)
    print("  STAGE-BY-STAGE COMPARISON")
    print("=" * 70)

    total_ok = 0
    total_mis = 0

    # ---- Stage 0: Embeddings (check DMA HBM - but mirroring overwrites) ----
    # DMA HBM has res2 written over ACT_EMBED at step 14, so original
    # embeddings are NOT available. We can only verify via URAM pre-state.
    # Skip this stage — embeddings are the input, assumed correct.
    print("\n--- Stage 0: Input Embeddings ---")
    print("  (Input data — not independently verifiable from post-run dumps)")
    print("  (Original embeddings overwritten by res2 flush in all HBM ports)")

    # ---- Stage 1: LN1 output ----
    # LN1 is flushed to ACT_TEMP at step 1, but step 8 overwrites with LN2.
    # NOT available in final flush HBM.
    print("\n--- Stage 1: LN1 Output ---")
    print("  NOT available: ACT_TEMP overwritten by LN2 flush (step 8)")

    # ---- Stage 2a: Q projection ----
    # Q is flushed to ACT_Q at step 2 (qkv_phase=0), but then attn_out
    # per-head is flushed to ACT_Q at step 3, and finally ffn_act at step 11
    # (ACT_FFN = ACT_Q). NOT available.
    print("\n--- Stage 2a: Q Projection ---")
    print("  NOT available: ACT_Q overwritten by attn_out (step 3) then ffn_act (step 11)")

    # ---- Stage 2b: K projection ----
    # K is flushed to ACT_K at step 2. NOT overwritten by anything later.
    # AVAILABLE in flush HBM!
    print("\n--- Stage 2b: K Projection ---")
    rtl_K = extract_matrix_from_hbm(
        flush_words, KV_BASE, BT, MODEL_STRIDE, MODEL_DIM)
    ok, mis = compare_stage(g['K'], rtl_K, "K_projection")
    total_ok += ok; total_mis += mis

    # ---- Stage 2c: V projection ----
    # V is flushed to ACT_V at step 2. NOT overwritten.
    # AVAILABLE in flush HBM!
    print("\n--- Stage 2c: V Projection ---")
    rtl_V = extract_matrix_from_hbm(
        flush_words, KV_BASE + KV_V_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
    ok, mis = compare_stage(g['V'], rtl_V, "V_projection")
    total_ok += ok; total_mis += mis

    # ---- Stage 3: Attention ----
    # Attention scores for last head only at ACT_ATTN (overwritten per head).
    # Attn_out concatenated is flushed per-head to ACT_Q, but then ACT_FFN
    # overwrites it. NOT available.
    print("\n--- Stage 3: Attention Output (concatenated) ---")
    print("  NOT available: ACT_Q overwritten by ffn_act (step 11)")

    # ---- Stage 3 partial: Last head's attention scores ----
    # The last head (head 15) scores are at ACT_ATTN with stride seq_words.
    seq_words = (SEQ_LEN + WE - 1) // WE  # 2
    print("\n--- Stage 3 partial: Last Head Attention Scores ---")
    rtl_last_scores = extract_matrix_from_hbm(
        flush_words, ACT_BASE + ACT_ATTN_OFFSET, BT, seq_words, SEQ_LEN)
    last_head = NUM_HEADS - 1
    ok, mis = compare_stage(g['scores'], rtl_last_scores,
                            f"attn_scores_head{last_head}")
    total_ok += ok; total_mis += mis
    # Note: g['scores'] is head 0, but flush HBM has the last head.
    # We need to recompute golden for last head.
    print("  NOTE: golden 'scores' is head 0; flush HBM has head 15 (last head).")
    print("  Re-checking with correct head...")

    # Recompute last head scores from golden Q, K
    Q_last = [row[last_head*HEAD_DIM:(last_head+1)*HEAD_DIM] for row in g['Q']]
    K_last = [row[last_head*HEAD_DIM:(last_head+1)*HEAD_DIM] for row in g['K']]
    K_last_T = [[K_last[r][c] for r in range(BT)] for c in range(HEAD_DIM)]
    scores_last = tiled_matmul_int16_numpy(Q_last, K_last_T, TILE_SIZE,
                                           acc_shift=MM_SHIFT_ATT_SCORE)
    ok, mis = compare_stage(scores_last, rtl_last_scores,
                            f"attn_scores_head{last_head}_corrected")
    total_ok += ok; total_mis += mis

    # ---- Stage 4: Output Projection ----
    # PROJ result goes to URAM (S_MM_RUN), then residual1 is computed
    # on top of it. PROJ result itself is NOT flushed to HBM.
    print("\n--- Stage 4: Output Projection ---")
    print("  NOT available: result stays in URAM, consumed by residual1")

    # ---- Stage 5: Residual 1 ----
    # Flushed to ACT_EMBED at step 6, but step 14 overwrites with res2.
    # NOT available.
    print("\n--- Stage 5: Residual 1 ---")
    print("  NOT available: ACT_EMBED overwritten by res2 flush (step 14)")

    # ---- Stage 6: LN2 output ----
    # Flushed to ACT_TEMP at step 8. NOT overwritten after that.
    # AVAILABLE in flush HBM!
    print("\n--- Stage 6: LN2 Output ---")
    rtl_ln2 = extract_matrix_from_hbm(
        flush_words, ACT_BASE + ACT_TEMP_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
    ok, mis = compare_stage(g['ln2_out'], rtl_ln2, "LN2_output")
    total_ok += ok; total_mis += mis

    # ---- Stage 7: FFN1 output ----
    # FFN1 result goes to URAM, then ReLU is applied on top.
    # NOT flushed to HBM separately. NOT available.
    print("\n--- Stage 7: FFN1 Output ---")
    print("  NOT available: result stays in URAM, consumed by ReLU")

    # ---- Stage 8: ReLU (ffn_act) ----
    # Flushed to ACT_FFN (= ACT_Q) at step 11.
    # BUT step 12 (FFN2) reads from ACT_FFN, and the FFN2 result goes
    # to URAM. ACT_FFN itself is NOT overwritten after step 11.
    # AVAILABLE in flush HBM!
    print("\n--- Stage 8: ReLU Output (ffn_act) ---")
    rtl_ffn_act = extract_matrix_from_hbm(
        flush_words, ACT_BASE + ACT_FFN_OFFSET, BT, F_STRIDE, F_DIM)
    ok, mis = compare_stage(g['ffn_act'], rtl_ffn_act, "ffn_act_relu")
    total_ok += ok; total_mis += mis

    # ---- Stage 9: FFN2 output ----
    # FFN2 result goes to URAM, then residual2 is computed on top.
    # NOT flushed to HBM separately. NOT available.
    print("\n--- Stage 9: FFN2 Output ---")
    print("  NOT available: result stays in URAM, consumed by residual2")

    # ---- Stage 10: Residual 2 (final output) ----
    # Flushed to ACT_EMBED at step 14. AVAILABLE in flush HBM!
    # Also in URAM at end of simulation.
    print("\n--- Stage 10: Residual 2 (FINAL OUTPUT) — Flush HBM ---")
    rtl_res2_flush = extract_matrix_from_hbm(
        flush_words, ACT_BASE + ACT_EMBED_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
    ok, mis = compare_stage(g['residual2'], rtl_res2_flush, "residual2_flush")
    total_ok += ok; total_mis += mis

    # Also check URAM
    if uram_words is not None:
        print("\n--- Stage 10: Residual 2 (FINAL OUTPUT) — URAM ---")
        rtl_res2_uram = extract_matrix_from_uram(
            uram_words, 0, BT, MODEL_STRIDE, MODEL_STRIDE)
        ok, mis = compare_stage(g['residual2'], rtl_res2_uram, "residual2_uram")
        total_ok += ok; total_mis += mis

        # Check: do URAM and flush HBM agree with each other?
        print("\n--- Cross-check: Flush HBM vs URAM (residual2) ---")
        ok_cross, mis_cross = compare_stage(rtl_res2_flush, rtl_res2_uram,
                                            "flush_vs_uram")

    # ---- DMA HBM cross-check ----
    if dma_words is not None:
        print("\n--- DMA HBM: Residual 2 (mirrored from flush) ---")
        rtl_res2_dma = extract_matrix_from_hbm(
            dma_words, ACT_BASE + ACT_EMBED_OFFSET, BT, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_stage(g['residual2'], rtl_res2_dma, "residual2_dma")
        total_ok += ok; total_mis += mis

        # Check if DMA still has original LN params (these should NOT be overwritten)
        print("\n--- DMA HBM: LN1 gamma/beta (should be original) ---")
        ln1_gamma_golden = weights['gamma1']
        ln1_beta_golden  = weights['beta1']
        # LN params packed as: gamma row then beta row, each MODEL_DIM/WE words
        ln1_base = WEIGHT_BASE + LAYER_LN1_OFFSET
        gamma_words_count = MODEL_DIM // WE
        dma_gamma = []
        for w in range(gamma_words_count):
            addr = ln1_base + w
            word_val = dma_words[addr] if addr < len(dma_words) else 0
            for e in range(WE):
                col = w * WE + e
                if col < MODEL_DIM:
                    dma_gamma.append(to_signed16(extract_int16_from_256bit(word_val, e)))
        match_g = sum(1 for a, b in zip(ln1_gamma_golden, dma_gamma) if int16(int8(a)) == b)
        print(f"  LN1 gamma: {match_g}/{MODEL_DIM} match")

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    print("\n" + "=" * 70)
    print("  DIAGNOSIS SUMMARY")
    print("=" * 70)
    total = total_ok + total_mis
    print(f"  Total elements checked: {total}")
    print(f"  Matches:    {total_ok}")
    print(f"  Mismatches: {total_mis}")
    print()

    print("  Available stages in flush HBM (not overwritten):")
    print("    K projection      @ KV_BASE")
    print("    V projection      @ KV_BASE + KV_V_OFFSET")
    print("    Last head scores  @ ACT_BASE + ACT_ATTN_OFFSET")
    print("    LN2 output        @ ACT_BASE + ACT_TEMP_OFFSET")
    print("    ffn_act (ReLU)    @ ACT_BASE + ACT_FFN_OFFSET")
    print("    residual2 (final) @ ACT_BASE + ACT_EMBED_OFFSET")
    print()
    print("  Stages NOT available (overwritten or never flushed):")
    print("    Input embeddings, LN1, Q, attn_out, proj, res1, FFN1, FFN2")
    print()
    print("  To isolate divergence further:")
    print("    - If K,V match but res2 doesn't -> bug is in attention or later")
    print("    - If LN2 matches but ffn_act doesn't -> bug is in FFN1 or ReLU")
    print("    - If ffn_act matches but res2 doesn't -> bug is in FFN2 or residual2")
    print("    - If K,V mismatch -> bug is in LN1 or QKV matmul")


if __name__ == "__main__":
    main()
