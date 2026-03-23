#!/usr/bin/env python3
"""Pinpoint where INT16 diverges from FP32 within a single layer.

Runs layer 0 of GPT-2-medium in both FP32 and our INT16 pipeline,
comparing after each sub-operation:
  LN1 → QKV → Attention → Proj → Res1 → LN2 → FFN1 → ReLU → FFN2 → Res2

Usage:
  python3.11 verify/fp32_layer_debug.py
"""

import os, sys, math
import numpy as np
import torch
from transformers import GPT2LMHeadModel, GPT2Tokenizer

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.golden.common import int8, int16, int32, saturate_int16
from verify.golden.softmax import softmax_golden
from verify.golden.layernorm import layernorm_golden
from verify.test_top_1k import _transpose
from verify.test_token_cosim import (
    load_embed_bin, load_weights_bin, compute_embeddings,
    _to_s16, tiled_matmul_int64_autoscale, adaptive_residual_add,
    TILE_SIZE, SCALE_SHIFT, BT, WE, MODEL_DIM, NUM_HEADS, HEAD_DIM, F_DIM,
)

PROMPT = "The meaning of life is"


def corr(a, b):
    """Pearson correlation between flattened arrays."""
    a, b = a.flatten().astype(np.float64), b.flatten().astype(np.float64)
    if a.std() < 1e-10 or b.std() < 1e-10:
        return 0.0
    return float(np.corrcoef(a, b)[0, 1])


def report(label, fp32_val, int16_val, num_tokens):
    """Print correlation for a sub-operation."""
    fp = fp32_val[:num_tokens].flatten() if len(fp32_val.shape) > 1 else fp32_val.flatten()
    i16 = int16_val[:num_tokens].flatten() if len(int16_val.shape) > 1 else int16_val.flatten()
    r = corr(fp.astype(np.float64), i16.astype(np.float64))
    fp_std = fp.std()
    i16_std = i16.std()
    status = "OK" if r > 0.9 else ("WARN" if r > 0.5 else "** BAD **")
    print(f"  {label:>25s}: corr={r:.4f}  fp32_std={fp_std:.2f}  "
          f"int16_std={i16_std:.1f}  {status}")
    return r


def main():
    print("Loading GPT-2-medium...")
    tokenizer = GPT2Tokenizer.from_pretrained('gpt2-medium')
    model = GPT2LMHeadModel.from_pretrained('gpt2-medium')
    model.eval()
    sd = model.state_dict()

    token_ids = tokenizer.encode(PROMPT)
    num_tokens = len(token_ids)
    print(f"Prompt: \"{PROMPT}\" → {token_ids} ({num_tokens} tokens)")

    # ===== FP32 Layer 0 step by step =====
    print("\n--- FP32 Layer 0 (step-by-step) ---")

    # Embedding
    wte = sd["transformer.wte.weight"].numpy()
    wpe = sd["transformer.wpe.weight"].numpy()
    fp_embed = np.zeros((num_tokens, MODEL_DIM), dtype=np.float32)
    for s, tid in enumerate(token_ids):
        fp_embed[s] = wte[tid] + wpe[s]

    # LN1
    ln1_w = sd["transformer.h.0.ln_1.weight"].numpy()
    ln1_b = sd["transformer.h.0.ln_1.bias"].numpy()
    fp_ln1 = np.zeros_like(fp_embed)
    for t in range(num_tokens):
        row = fp_embed[t]
        mean = row.mean()
        var = ((row - mean) ** 2).mean()
        fp_ln1[t] = (row - mean) / np.sqrt(var + 1e-5) * ln1_w + ln1_b
    print(f"  FP32 LN1: range=[{fp_ln1.min():.4f}, {fp_ln1.max():.4f}], "
          f"std={fp_ln1.std():.4f}")

    # QKV — GPT-2 Conv1D: weight is (in, out), bias is (out,)
    c_attn_w = sd["transformer.h.0.attn.c_attn.weight"].numpy()  # (1024, 3072)
    c_attn_b = sd["transformer.h.0.attn.c_attn.bias"].numpy()    # (3072,)
    fp_qkv = fp_ln1 @ c_attn_w + c_attn_b
    fp_Q = fp_qkv[:, :MODEL_DIM]
    fp_K = fp_qkv[:, MODEL_DIM:2*MODEL_DIM]
    fp_V = fp_qkv[:, 2*MODEL_DIM:]
    print(f"  FP32 Q: range=[{fp_Q.min():.2f}, {fp_Q.max():.2f}], std={fp_Q.std():.4f}")

    # Multi-head attention
    fp_attn_out = np.zeros((num_tokens, MODEL_DIM), dtype=np.float32)
    for h in range(NUM_HEADS):
        s, e = h * HEAD_DIM, (h+1) * HEAD_DIM
        Q_h = fp_Q[:, s:e]
        K_h = fp_K[:, s:e]
        V_h = fp_V[:, s:e]
        scores = Q_h @ K_h.T / np.sqrt(HEAD_DIM)
        # Causal mask
        mask = np.triu(np.ones((num_tokens, num_tokens)), k=1) * (-1e9)
        scores = scores + mask
        probs = np.exp(scores - scores.max(axis=-1, keepdims=True))
        probs = probs / probs.sum(axis=-1, keepdims=True)
        fp_attn_out[:, s:e] = probs @ V_h
    print(f"  FP32 Attn: range=[{fp_attn_out.min():.4f}, {fp_attn_out.max():.4f}]")

    # Output projection
    c_proj_w = sd["transformer.h.0.attn.c_proj.weight"].numpy()
    c_proj_b = sd["transformer.h.0.attn.c_proj.bias"].numpy()
    fp_proj = fp_attn_out @ c_proj_w + c_proj_b

    # Residual 1
    fp_res1 = fp_embed + fp_proj
    print(f"  FP32 Res1: range=[{fp_res1.min():.2f}, {fp_res1.max():.2f}]")

    # LN2
    ln2_w = sd["transformer.h.0.ln_2.weight"].numpy()
    ln2_b = sd["transformer.h.0.ln_2.bias"].numpy()
    fp_ln2 = np.zeros_like(fp_res1)
    for t in range(num_tokens):
        row = fp_res1[t]
        mean = row.mean()
        var = ((row - mean) ** 2).mean()
        fp_ln2[t] = (row - mean) / np.sqrt(var + 1e-5) * ln2_w + ln2_b

    # FFN
    fc_w = sd["transformer.h.0.mlp.c_fc.weight"].numpy()
    fc_b = sd["transformer.h.0.mlp.c_fc.bias"].numpy()
    fp_ffn1 = np.maximum(0, fp_ln2 @ fc_w + fc_b)  # GELU in real GPT-2, ReLU in ours

    proj2_w = sd["transformer.h.0.mlp.c_proj.weight"].numpy()
    proj2_b = sd["transformer.h.0.mlp.c_proj.bias"].numpy()
    fp_ffn2 = fp_ffn1 @ proj2_w + proj2_b

    # Residual 2
    fp_res2 = fp_res1 + fp_ffn2
    print(f"  FP32 Res2: range=[{fp_res2.min():.2f}, {fp_res2.max():.2f}]")

    # ===== INT16 Layer 0 step by step =====
    print("\n--- INT16 Layer 0 (step-by-step) ---")

    embed_data = load_embed_bin(os.path.join(PROJECT_ROOT, "fpga/data/embed.bin"))
    layer_weights = load_weights_bin(
        os.path.join(PROJECT_ROOT, "fpga/data/weights.bin"), 1)
    w = layer_weights[0]

    embed_int16, embed_scale = compute_embeddings(
        embed_data['wte'], embed_data['wpe'], token_ids)
    # Pad to BT=32
    embed_int16 = embed_int16 + [[0] * MODEL_DIM] * (BT - num_tokens)

    i16_embed = _to_s16(embed_int16).astype(np.float32)

    # LN1
    i16_ln1 = []
    for t in range(BT):
        normed = layernorm_golden(
            embed_int16[t], w['gamma1'], w['beta1'], MODEL_DIM)
        i16_ln1.append(normed)
    i16_ln1_arr = _to_s16(i16_ln1).astype(np.float32)

    # QKV
    i16_Q, sq = tiled_matmul_int64_autoscale(i16_ln1, w['W_q'], TILE_SIZE, label="Q")
    i16_K, sk = tiled_matmul_int64_autoscale(i16_ln1, w['W_k'], TILE_SIZE, label="K")
    i16_V, sv = tiled_matmul_int64_autoscale(i16_ln1, w['W_v'], TILE_SIZE, label="V")
    i16_Q_arr = _to_s16(i16_Q).astype(np.float32)
    i16_K_arr = _to_s16(i16_K).astype(np.float32)

    # Attention
    q_max = int(np.max(np.abs(_to_s16(i16_Q))))
    k_max = int(np.max(np.abs(_to_s16(i16_K))))
    TARGET_QK = 5792
    qk_shift = 0
    while (q_max >> qk_shift) > TARGET_QK or (k_max >> qk_shift) > TARGET_QK:
        qk_shift += 1
    print(f"  qk_pre_shift={qk_shift}")

    Q_sc = (_to_s16(i16_Q) >> qk_shift).astype(int).tolist()
    K_sc = (_to_s16(i16_K) >> qk_shift).astype(int).tolist()

    i16_attn = [[0] * MODEL_DIM for _ in range(BT)]
    for h in range(NUM_HEADS):
        Q_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in Q_sc]
        K_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in K_sc]
        V_h = [row[h*HEAD_DIM:(h+1)*HEAD_DIM] for row in i16_V]
        K_h_T = _transpose(K_h)
        scores_h, _ = tiled_matmul_int64_autoscale(Q_h, K_h_T, TILE_SIZE)
        probs_h = [softmax_golden(scores_h[t], scale_shift=SCALE_SHIFT, row_idx=t)
                   for t in range(BT)]
        attn_h, _ = tiled_matmul_int64_autoscale(probs_h, V_h, TILE_SIZE)
        for t in range(BT):
            for d in range(HEAD_DIM):
                i16_attn[t][h*HEAD_DIM + d] = attn_h[t][d]
    i16_attn_arr = _to_s16(i16_attn).astype(np.float32)

    # Output proj
    i16_proj, _ = tiled_matmul_int64_autoscale(i16_attn, w['W_o'], TILE_SIZE, label="proj")

    # Res1
    i16_res1 = []
    for t in range(BT):
        row, _ = adaptive_residual_add(embed_int16[t], i16_proj[t])
        i16_res1.append(row)
    i16_res1_arr = _to_s16(i16_res1).astype(np.float32)

    # LN2
    i16_ln2 = []
    for t in range(BT):
        normed = layernorm_golden(
            i16_res1[t], w['gamma2'], w['beta2'], MODEL_DIM)
        i16_ln2.append(normed)
    i16_ln2_arr = _to_s16(i16_ln2).astype(np.float32)

    # FFN1
    i16_ffn1, _ = tiled_matmul_int64_autoscale(i16_ln2, w['W_ffn1'], TILE_SIZE, label="FFN1")
    i16_ffn_act = [[max(0, v) for v in row] for row in i16_ffn1]

    # FFN2
    i16_ffn2, _ = tiled_matmul_int64_autoscale(i16_ffn_act, w['W_ffn2'], TILE_SIZE, label="FFN2")

    # Res2
    i16_res2 = []
    for t in range(BT):
        row, _ = adaptive_residual_add(i16_res1[t], i16_ffn2[t])
        i16_res2.append(row)
    i16_res2_arr = _to_s16(i16_res2).astype(np.float32)

    # ===== Per-stage correlation =====
    print("\n" + "=" * 70)
    print("  PER-STAGE CORRELATION: FP32 vs INT16")
    print("=" * 70)
    report("Embedding", fp_embed, i16_embed[:num_tokens], num_tokens)
    report("After LN1", fp_ln1, i16_ln1_arr[:num_tokens], num_tokens)
    report("Q (after QKV matmul)", fp_Q, i16_Q_arr[:num_tokens], num_tokens)
    report("After Attention", fp_attn_out, i16_attn_arr[:num_tokens], num_tokens)
    report("After Residual 1", fp_res1, i16_res1_arr[:num_tokens], num_tokens)
    report("After LN2", fp_ln2[:num_tokens], i16_ln2_arr[:num_tokens], num_tokens)
    report("After Residual 2", fp_res2, i16_res2_arr[:num_tokens], num_tokens)

    # Also check: what if we compare FP32 LN1 output vs INT16 LN1 output
    # accounting for scale difference?
    print("\n  NOTE: INT16 LN uses INT8 gamma/beta + 256-entry rsqrt LUT")
    print("  NOTE: FP32 uses GELU activation, INT16 uses ReLU")


if __name__ == "__main__":
    main()
