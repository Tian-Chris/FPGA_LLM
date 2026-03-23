#!/usr/bin/env python3
"""Analyze whether we're over-shifting due to outliers.

For each matmul in layer 0, compare:
  - Auto-calibrated shift (fits max_abs into INT16)
  - Percentile-based shift (fits 99.9% of values, allows some saturation)
  - The correlation with FP32 at each shift level
"""

import os, sys, math
import numpy as np
import torch
from transformers import GPT2LMHeadModel, GPT2Tokenizer

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.golden.layernorm import layernorm_golden
from verify.test_token_cosim import (
    load_embed_bin, load_weights_bin, compute_embeddings,
    _to_s16, BT, WE, MODEL_DIM, NUM_HEADS, HEAD_DIM, TILE_SIZE,
)

PROMPT = "The meaning of life is"


def corr(a, b):
    a, b = a.flatten().astype(np.float64), b.flatten().astype(np.float64)
    if a.std() < 1e-10 or b.std() < 1e-10:
        return 0.0
    return float(np.corrcoef(a, b)[0, 1])


def int16_matmul_raw(mat_a, mat_b):
    """Full INT64 matmul, return raw unshifted result."""
    A = _to_s16(mat_a).astype(np.int64)
    B = _to_s16(mat_b).astype(np.int64)
    return A @ B


def analyze_shift(raw_result, fp32_result, label, num_tokens):
    """Try different shifts and show correlation + saturation tradeoff."""
    raw = raw_result[:num_tokens].astype(np.float64)
    fp = fp32_result[:num_tokens].astype(np.float64)

    max_abs = int(np.max(np.abs(raw)))
    auto_shift = max(0, max_abs.bit_length() - 15)

    print(f"\n  {label}:")
    print(f"    max_abs={max_abs:,}  auto_shift={auto_shift}")

    # Distribution analysis
    abs_vals = np.abs(raw.flatten())
    for p in [90, 95, 99, 99.5, 99.9, 99.99, 100]:
        pval = np.percentile(abs_vals, p)
        shift_needed = max(0, int(pval).bit_length() - 15)
        print(f"    p{p:>6.2f}: max_abs={int(pval):>12,}  shift_needed={shift_needed}")

    # Try each shift from auto_shift-4 to auto_shift and show correlation
    print(f"\n    {'Shift':>5s}  {'Correlation':>11s}  {'Saturated':>12s}  {'Sat%':>6s}")
    for shift in range(max(0, auto_shift - 5), auto_shift + 1):
        shifted = raw / (2 ** shift)  # floating point to avoid int overflow
        clipped = np.clip(shifted, -32768, 32767)
        sat_count = int(np.sum(np.abs(shifted) > 32767))
        total = shifted.size
        # Correlation with FP32
        r = corr(fp, clipped)
        marker = " <-- auto" if shift == auto_shift else ""
        print(f"    {shift:5d}  {r:11.4f}  {sat_count:>12,}  {100*sat_count/total:5.2f}%{marker}")


def main():
    print("Loading GPT-2-medium...")
    tokenizer = GPT2Tokenizer.from_pretrained('gpt2-medium')
    model = GPT2LMHeadModel.from_pretrained('gpt2-medium')
    model.eval()
    sd = model.state_dict()

    token_ids = tokenizer.encode(PROMPT)
    num_tokens = len(token_ids)
    print(f"Prompt: \"{PROMPT}\" → {token_ids}")

    # FP32 reference
    wte = sd["transformer.wte.weight"].numpy()
    wpe = sd["transformer.wpe.weight"].numpy()
    fp_embed = np.array([wte[tid] + wpe[s] for s, tid in enumerate(token_ids)])

    ln1_w = sd["transformer.h.0.ln_1.weight"].numpy()
    ln1_b = sd["transformer.h.0.ln_1.bias"].numpy()
    fp_ln1 = np.zeros_like(fp_embed)
    for t in range(num_tokens):
        row = fp_embed[t]
        mean = row.mean()
        var = ((row - mean) ** 2).mean()
        fp_ln1[t] = (row - mean) / np.sqrt(var + 1e-5) * ln1_w + ln1_b

    c_attn_w = sd["transformer.h.0.attn.c_attn.weight"].numpy()
    c_attn_b = sd["transformer.h.0.attn.c_attn.bias"].numpy()
    fp_qkv = fp_ln1 @ c_attn_w + c_attn_b
    fp_Q = fp_qkv[:, :MODEL_DIM]
    fp_K = fp_qkv[:, MODEL_DIM:2*MODEL_DIM]
    fp_V = fp_qkv[:, 2*MODEL_DIM:]

    # INT16 pipeline
    embed_data = load_embed_bin(os.path.join(PROJECT_ROOT, "fpga/data/embed.bin"))
    layer_weights = load_weights_bin(
        os.path.join(PROJECT_ROOT, "fpga/data/weights.bin"), 1)
    w = layer_weights[0]

    embed_int16, _ = compute_embeddings(embed_data['wte'], embed_data['wpe'], token_ids)
    embed_int16 = embed_int16 + [[0] * MODEL_DIM] * (BT - num_tokens)

    # LN1
    i16_ln1 = []
    for t in range(BT):
        normed = layernorm_golden(embed_int16[t], w['gamma1'], w['beta1'], MODEL_DIM)
        i16_ln1.append(normed)

    # Raw (unshifted) QKV matmul
    print("\n" + "=" * 70)
    print("  SHIFT ANALYSIS: Layer 0 QKV Matmul")
    print("=" * 70)

    raw_Q = int16_matmul_raw(i16_ln1, w['W_q'])
    raw_K = int16_matmul_raw(i16_ln1, w['W_k'])
    raw_V = int16_matmul_raw(i16_ln1, w['W_v'])

    analyze_shift(raw_Q, fp_Q, "W_q matmul", num_tokens)
    analyze_shift(raw_K, fp_K, "W_k matmul", num_tokens)
    analyze_shift(raw_V, fp_V, "W_v matmul", num_tokens)

    # Also check: correlation of LN1 output
    i16_ln1_arr = _to_s16(i16_ln1).astype(np.float32)
    r_ln1 = corr(fp_ln1, i16_ln1_arr[:num_tokens])
    print(f"\n  Reference: LN1 correlation = {r_ln1:.4f}")

    # Check: what's the best possible correlation if we had infinite precision?
    # i.e., use FP64 matmul with our quantized weights
    W_q_f64 = _to_s16(w['W_q']).astype(np.float64)
    ln1_f64 = _to_s16(i16_ln1).astype(np.float64)
    ideal_Q = (ln1_f64[:num_tokens] @ W_q_f64)
    r_ideal = corr(fp_Q, ideal_Q)
    print(f"  Ideal (no shift, FP64 matmul with INT16 weights): Q corr = {r_ideal:.4f}")
    print(f"  This is the CEILING — shift can only make it worse")


if __name__ == "__main__":
    main()
