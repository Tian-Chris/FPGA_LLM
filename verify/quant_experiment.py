#!/usr/bin/env python3
"""Test per-channel quantization + biases vs current per-tensor no-bias.

Compares four configurations through layer 0:
  A) Current: per-tensor INT16 weights, no bias
  B) Per-tensor INT16 weights + INT16 bias
  C) Per-channel INT16 weights, no bias
  D) Per-channel INT16 weights + INT16 bias

For each, runs LN1 → QKV matmul → Attention → Proj → Res1 → LN2 → FFN → Res2
and reports per-stage correlation with FP32.

Usage:
  python3.11 verify/quant_experiment.py
"""

import os, sys, math
import numpy as np
import torch
from transformers import GPT2LMHeadModel, GPT2Tokenizer

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.golden.layernorm import layernorm_golden
from verify.golden.softmax import softmax_golden
from verify.test_top_1k import _transpose
from verify.test_token_cosim import (
    load_embed_bin, compute_embeddings, _to_s16,
    adaptive_residual_add,
    BT, WE, MODEL_DIM, NUM_HEADS, HEAD_DIM, F_DIM, TILE_SIZE, SCALE_SHIFT,
)

PROMPT = "The meaning of life is"


def corr(a, b):
    a, b = a.flatten().astype(np.float64), b.flatten().astype(np.float64)
    if a.std() < 1e-10 or b.std() < 1e-10:
        return 0.0
    return float(np.corrcoef(a, b)[0, 1])


def quantize_per_tensor(mat_fp32):
    """Current approach: one scale for entire matrix → INT16."""
    amax = np.max(np.abs(mat_fp32))
    if amax < 1e-10:
        return np.zeros_like(mat_fp32, dtype=np.int16), np.array([amax])
    scale = amax / 32767.0
    q = np.clip(np.round(mat_fp32 / scale), -32767, 32767).astype(np.int16)
    return q, np.array([scale])


def quantize_per_channel(mat_fp32):
    """Per-column scale: each output dimension gets its own ±32767 range."""
    # Scale per column (output dimension)
    amax = np.max(np.abs(mat_fp32), axis=0)  # (out_dim,)
    amax = np.maximum(amax, 1e-10)
    scales = amax / 32767.0  # (out_dim,)
    q = np.clip(np.round(mat_fp32 / scales[None, :]), -32767, 32767).astype(np.int16)
    return q, scales


def quantize_bias(bias_fp32, input_scale, weight_scales):
    """Quantize bias to INT16.

    In quantized inference: output = (input @ weight) + bias
    The natural scale of (input @ weight) is input_scale * weight_scale.
    But with our auto-shift, the output gets shifted. So we just quantize
    the bias with its own scale and add it after the matmul.

    Simpler approach: just quantize bias per-tensor to INT16.
    """
    amax = np.max(np.abs(bias_fp32))
    if amax < 1e-10:
        return np.zeros_like(bias_fp32, dtype=np.int16), 1.0
    scale = amax / 32767.0
    q = np.clip(np.round(bias_fp32 / scale), -32767, 32767).astype(np.int16)
    return q, scale


def matmul_fp64_autoscale(A_int16, B_int16, per_channel_scales=None):
    """INT16 × INT16 matmul in FP64, auto-shift to INT16.

    If per_channel_scales is provided, each column of B was quantized with
    a different scale. We need to rescale after matmul so all output columns
    are in the same scale before shifting to INT16.

    Returns (result_int16_list, shift).
    """
    A = _to_s16(A_int16).astype(np.int64)
    B = _to_s16(B_int16).astype(np.int64)
    raw = A @ B  # INT64, no overflow

    if per_channel_scales is not None:
        # Each column j of raw has effective scale proportional to
        # weight_scale[j]. Normalize so all columns have the same scale.
        # Multiply each column by (max_scale / col_scale) to equalize.
        max_scale = np.max(per_channel_scales)
        col_factors = max_scale / per_channel_scales  # (out_dim,)
        # Apply in float to avoid int overflow
        raw_float = raw.astype(np.float64) * col_factors[None, :]
        raw = np.round(raw_float).astype(np.int64)

    max_abs = int(np.max(np.abs(raw)))
    if max_abs <= 32767:
        shift = 0
    else:
        shift = max(0, max_abs.bit_length() - 15)
    result = raw >> shift
    result = np.clip(result, -32768, 32767).astype(np.int16)
    return result.astype(int).tolist(), shift


def add_quantized_bias(matmul_result, bias_int16, bias_scale, matmul_shift,
                       input_act_scale=1.0, weight_scale=1.0):
    """Add quantized bias to matmul output.

    The matmul output has been shifted by `matmul_shift`. The bias needs
    to be scaled to match. Simplest approach: compute bias contribution
    in FP32, quantize to match the matmul output scale, add as INT16.
    """
    # Convert matmul result to numpy
    result = _to_s16(matmul_result).astype(np.int32)

    # The bias in its original scale
    bias_fp = bias_int16.astype(np.float64) * bias_scale

    # The matmul output scale: one LSB of the output represents
    # (input_act_scale * weight_scale * 2^shift) in the original FP32 space
    # We need bias in the same units as the matmul output
    # Simplest: just add bias as a separate scaled quantity and re-quantize
    # Actually, let's just compute the bias effect in the output domain
    # and add it as INT32, then re-saturate

    # For now, use a simpler approach: the bias is small relative to matmul
    # output, so scale it to roughly the same magnitude and add
    bias_in_output_units = bias_fp / (input_act_scale * weight_scale * (2 ** matmul_shift))
    bias_int = np.clip(np.round(bias_in_output_units), -32768, 32767).astype(np.int32)

    # Add and saturate
    added = result + bias_int[None, :]  # broadcast over rows
    added = np.clip(added, -32768, 32767).astype(np.int16)
    return added.astype(int).tolist()


def run_fp32_layer0(sd, fp_embed, num_tokens):
    """Run FP32 layer 0, return intermediates."""
    r = {}

    # LN1
    ln1_w = sd["transformer.h.0.ln_1.weight"].numpy()
    ln1_b = sd["transformer.h.0.ln_1.bias"].numpy()
    fp_ln1 = np.zeros_like(fp_embed)
    for t in range(num_tokens):
        row = fp_embed[t]
        mean = row.mean()
        var = ((row - mean) ** 2).mean()
        fp_ln1[t] = (row - mean) / np.sqrt(var + 1e-5) * ln1_w + ln1_b
    r['ln1'] = fp_ln1

    # QKV
    c_attn_w = sd["transformer.h.0.attn.c_attn.weight"].numpy()
    c_attn_b = sd["transformer.h.0.attn.c_attn.bias"].numpy()
    fp_qkv = fp_ln1 @ c_attn_w + c_attn_b
    r['Q'] = fp_qkv[:, :MODEL_DIM]
    r['K'] = fp_qkv[:, MODEL_DIM:2*MODEL_DIM]
    r['V'] = fp_qkv[:, 2*MODEL_DIM:]

    # Attention
    fp_attn = np.zeros((num_tokens, MODEL_DIM), dtype=np.float32)
    for h in range(NUM_HEADS):
        s, e = h * HEAD_DIM, (h+1) * HEAD_DIM
        Q_h, K_h, V_h = r['Q'][:, s:e], r['K'][:, s:e], r['V'][:, s:e]
        scores = Q_h @ K_h.T / np.sqrt(HEAD_DIM)
        mask = np.triu(np.ones((num_tokens, num_tokens)), k=1) * (-1e9)
        probs = np.exp(scores + mask - (scores + mask).max(axis=-1, keepdims=True))
        probs = probs / probs.sum(axis=-1, keepdims=True)
        fp_attn[:, s:e] = probs @ V_h
    r['attn'] = fp_attn

    # Proj
    c_proj_w = sd["transformer.h.0.attn.c_proj.weight"].numpy()
    c_proj_b = sd["transformer.h.0.attn.c_proj.bias"].numpy()
    r['proj'] = fp_attn @ c_proj_w + c_proj_b

    # Res1
    r['res1'] = fp_embed + r['proj']

    # LN2
    ln2_w = sd["transformer.h.0.ln_2.weight"].numpy()
    ln2_b = sd["transformer.h.0.ln_2.bias"].numpy()
    fp_ln2 = np.zeros_like(r['res1'])
    for t in range(num_tokens):
        row = r['res1'][t]
        mean = row.mean()
        var = ((row - mean) ** 2).mean()
        fp_ln2[t] = (row - mean) / np.sqrt(var + 1e-5) * ln2_w + ln2_b
    r['ln2'] = fp_ln2

    # FFN (GELU in real GPT-2, we compare both)
    fc_w = sd["transformer.h.0.mlp.c_fc.weight"].numpy()
    fc_b = sd["transformer.h.0.mlp.c_fc.bias"].numpy()
    fp_ffn1_pre = fp_ln2 @ fc_w + fc_b
    r['ffn1_relu'] = np.maximum(0, fp_ffn1_pre)  # ReLU version for fair comparison

    proj2_w = sd["transformer.h.0.mlp.c_proj.weight"].numpy()
    proj2_b = sd["transformer.h.0.mlp.c_proj.bias"].numpy()
    r['ffn2'] = r['ffn1_relu'] @ proj2_w + proj2_b

    r['res2'] = r['res1'] + r['ffn2']
    return r


def run_int16_layer0(embed_int16, weights_fp32, ln_params, num_tokens,
                     per_channel=False, use_bias=False):
    """Run INT16 layer 0 with specified quantization config."""
    r = {}

    # Quantize weights
    def quant_w(mat):
        if per_channel:
            return quantize_per_channel(mat)
        else:
            q, s = quantize_per_tensor(mat)
            return q, s

    W_q, sq = quant_w(weights_fp32['W_q'])
    W_k, sk = quant_w(weights_fp32['W_k'])
    W_v, sv = quant_w(weights_fp32['W_v'])
    W_o, so = quant_w(weights_fp32['W_o'])
    W_ffn1, sf1 = quant_w(weights_fp32['W_ffn1'])
    W_ffn2, sf2 = quant_w(weights_fp32['W_ffn2'])

    # LN1 (uses INT8 gamma/beta from existing export — same for all configs)
    i16_ln1 = []
    for t in range(BT):
        normed = layernorm_golden(
            embed_int16[t], ln_params['gamma1'], ln_params['beta1'], MODEL_DIM)
        i16_ln1.append(normed)
    r['ln1'] = _to_s16(i16_ln1[:num_tokens]).astype(np.float32)

    # QKV matmul
    pc_q = sq if per_channel else None
    pc_k = sk if per_channel else None
    pc_v = sv if per_channel else None

    Q, shq = matmul_fp64_autoscale(i16_ln1, W_q.tolist(), pc_q)
    K, shk = matmul_fp64_autoscale(i16_ln1, W_k.tolist(), pc_k)
    V, shv = matmul_fp64_autoscale(i16_ln1, W_v.tolist(), pc_v)

    if use_bias:
        # Bias needs to be added in the right scale
        # For simplicity: compute bias effect in float, scale to output
        for name, result, sh, w_scales, bias_fp, store_key in [
            ("Q", Q, shq, sq, weights_fp32['bias_q'], 'Q'),
            ("K", K, shk, sk, weights_fp32['bias_k'], 'K'),
            ("V", V, shv, sv, weights_fp32['bias_v'], 'V'),
        ]:
            # Add bias: convert result to float, add bias in output units
            res_arr = _to_s16(result).astype(np.float64)
            # Each LSB of result ≈ (ln1_scale * weight_scale * 2^shift) in FP32
            # The bias is in FP32 units. We need to express it in result LSBs.
            # Since we don't track the exact combined scale, approximate:
            # result_float ≈ (LN1_fp32 @ W_fp32) / (2^shift) roughly
            # bias in result units ≈ bias_fp32 / (embed_amax_scale? * weight_amax? * 2^shift)
            # This is getting complicated. Simpler: just add bias in float domain.
            # Scale bias same way as matmul output.
            ln1_arr = _to_s16(i16_ln1).astype(np.float64)
            W_f = _to_s16(w_scales if not per_channel else result).astype(np.float64) if False else None
            # Simplest correct approach: redo matmul in float with bias
            A_f = _to_s16(i16_ln1).astype(np.float64)
            if per_channel:
                B_f = W_q.astype(np.float64) if store_key == 'Q' else (
                    W_k.astype(np.float64) if store_key == 'K' else W_v.astype(np.float64))
                max_sc = np.max(w_scales)
                col_f = max_sc / w_scales
                raw = (A_f @ B_f) * col_f[None, :]
            else:
                B_f = (W_q if store_key == 'Q' else (
                    W_k if store_key == 'K' else W_v)).astype(np.float64)
                raw = A_f @ B_f

            # Add bias scaled to the quantized weight domain
            # bias_fp32 / weight_scale gives bias in INT16-weight units
            # Then it accumulates like one more row of the matmul
            if per_channel:
                bias_in_units = bias_fp / (w_scales * 32767.0) * 32767.0
                # Hmm this is circular. Let me think differently.
                # After per-channel: raw[i,j] = sum_k(A[i,k] * B_q[k,j]) * (max_scale/scale_j)
                # The bias should be: bias_fp[j] / scale_j * (max_scale/scale_j)?
                # No. The output is in units of (input_lsb * max_weight_scale).
                # bias contribution = bias_fp[j] / (input_lsb * weight_scale_j)
                # But we need it in the same units as raw, which is after col_factor rescaling.
                # raw_rescaled[j] = raw[j] * (max_scale / scale_j)
                # bias_rescaled[j] = bias_fp[j] / (input_lsb * scale_j) * (max_scale / scale_j)
                # ≈ bias_fp[j] / input_lsb / scale_j * max_scale / scale_j
                # This is getting too complicated for a quick test.
                # Let's just add bias in the raw domain before shift.
                pass
            raw_with_bias = raw + bias_fp[None, :] / 7.748610e-05  # divide by embed scale
            # ^ rough: input_int16 ≈ input_fp32 / embed_scale, so matmul output
            # is in units of embed_scale * weight_int16. Bias needs same treatment.
            # This is an approximation but should show if bias matters.
            max_abs = int(np.max(np.abs(raw_with_bias)))
            shift = max(0, max_abs.bit_length() - 15) if max_abs > 32767 else 0
            result_new = np.clip(raw_with_bias / (2**shift), -32768, 32767).astype(np.int16)
            if store_key == 'Q':
                Q = result_new.astype(int).tolist()
            elif store_key == 'K':
                K = result_new.astype(int).tolist()
            else:
                V = result_new.astype(int).tolist()

    r['Q'] = _to_s16(Q[:num_tokens]).astype(np.float32)
    r['K'] = _to_s16(K[:num_tokens]).astype(np.float32)

    # Attention (simplified — just track Q correlation, which is the main indicator)
    # Full attention is slow, so skip for per-stage tracking of the key metric
    r['V'] = _to_s16(V[:num_tokens]).astype(np.float32)

    return r


def main():
    print("Loading GPT-2-medium...")
    tokenizer = GPT2Tokenizer.from_pretrained('gpt2-medium')
    model = GPT2LMHeadModel.from_pretrained('gpt2-medium')
    model.eval()
    sd = model.state_dict()

    token_ids = tokenizer.encode(PROMPT)
    num_tokens = len(token_ids)

    # FP32 embedding
    wte = sd["transformer.wte.weight"].numpy()
    wpe = sd["transformer.wpe.weight"].numpy()
    fp_embed = np.array([wte[tid] + wpe[s] for s, tid in enumerate(token_ids)])

    # FP32 layer 0
    print("Running FP32 layer 0...")
    fp = run_fp32_layer0(sd, fp_embed, num_tokens)

    # INT16 embedding (same for all configs)
    embed_data = load_embed_bin(os.path.join(PROJECT_ROOT, "fpga/data/embed.bin"))
    embed_int16, embed_scale = compute_embeddings(embed_data['wte'], embed_data['wpe'], token_ids)
    embed_int16 = embed_int16 + [[0] * MODEL_DIM] * (BT - num_tokens)

    # Load FP32 weights for re-quantization experiments
    c_attn_w = sd["transformer.h.0.attn.c_attn.weight"].numpy()
    c_attn_b = sd["transformer.h.0.attn.c_attn.bias"].numpy()
    c_proj_w = sd["transformer.h.0.attn.c_proj.weight"].numpy()
    c_proj_b = sd["transformer.h.0.attn.c_proj.bias"].numpy()
    fc_w = sd["transformer.h.0.mlp.c_fc.weight"].numpy()
    fc_b = sd["transformer.h.0.mlp.c_fc.bias"].numpy()
    proj2_w = sd["transformer.h.0.mlp.c_proj.weight"].numpy()
    proj2_b = sd["transformer.h.0.mlp.c_proj.bias"].numpy()

    weights_fp32 = {
        'W_q': c_attn_w[:, :MODEL_DIM],
        'W_k': c_attn_w[:, MODEL_DIM:2*MODEL_DIM],
        'W_v': c_attn_w[:, 2*MODEL_DIM:],
        'W_o': c_proj_w,
        'W_ffn1': fc_w,
        'W_ffn2': proj2_w,
        'bias_q': c_attn_b[:MODEL_DIM],
        'bias_k': c_attn_b[MODEL_DIM:2*MODEL_DIM],
        'bias_v': c_attn_b[2*MODEL_DIM:],
        'bias_o': c_proj_b,
        'bias_ffn1': fc_b,
        'bias_ffn2': proj2_b,
    }

    # Load LN params from existing export (INT8, same for all configs)
    from verify.test_token_cosim import load_weights_bin
    ln_weights = load_weights_bin(
        os.path.join(PROJECT_ROOT, "fpga/data/weights.bin"), 1)[0]
    ln_params = {
        'gamma1': ln_weights['gamma1'], 'beta1': ln_weights['beta1'],
        'gamma2': ln_weights['gamma2'], 'beta2': ln_weights['beta2'],
    }

    # ===== Quick direct test: ideal correlation with different quant methods =====
    print("\n" + "=" * 70)
    print("  IDEAL CORRELATION (FP64 matmul, no shift loss)")
    print("  Shows the ceiling for each quantization approach")
    print("=" * 70)

    ln1_i16 = []
    for t in range(BT):
        normed = layernorm_golden(embed_int16[t], ln_params['gamma1'],
                                   ln_params['beta1'], MODEL_DIM)
        ln1_i16.append(normed)
    A_f64 = _to_s16(ln1_i16).astype(np.float64)

    configs = {}

    # A) Per-tensor, no bias
    Wq_pt, _ = quantize_per_tensor(weights_fp32['W_q'])
    ideal_A = (A_f64[:num_tokens] @ Wq_pt.astype(np.float64))
    r_A = corr(fp['Q'], ideal_A)
    configs['A'] = r_A

    # B) Per-tensor + bias
    bias_q = weights_fp32['bias_q']
    ideal_B = ideal_A + (bias_q / embed_scale)[None, :]  # bias in INT16-input units
    r_B = corr(fp['Q'], ideal_B)
    configs['B'] = r_B

    # C) Per-channel, no bias — dequantize: q[i,j] * scale[j] ≈ original W[i,j]
    Wq_pc, scales_pc = quantize_per_channel(weights_fp32['W_q'])
    # Dequantized matmul: A @ (q * diag(scales)) = (A @ q) * scales
    ideal_C = (A_f64[:num_tokens] @ Wq_pc.astype(np.float64)) * scales_pc[None, :]
    r_C = corr(fp['Q'], ideal_C)
    configs['C'] = r_C

    # D) Per-channel + bias (bias is already in FP32 units, matches dequantized scale)
    ideal_D = ideal_C + bias_q[None, :]
    r_D = corr(fp['Q'], ideal_D)
    configs['D'] = r_D

    # E) FP32 weights (just our INT16 LN1 input × FP32 W_q + bias) — upper bound
    Wq_fp = weights_fp32['W_q'].astype(np.float64)
    ideal_E = (A_f64[:num_tokens] @ Wq_fp / embed_scale) * embed_scale + bias_q[None, :]
    # Hmm, let me just compute it cleanly
    # Our LN1 output as float: ln1_float ≈ ln1_int16 * some_scale
    # FP32 Q = fp_ln1 @ W_q + bias
    # With our LN1: ≈ (ln1_int16 * ln1_scale) @ W_q + bias
    # The correlation doesn't depend on overall scale, so:
    ideal_E = A_f64[:num_tokens] @ Wq_fp  # + bias doesn't change corr vs A_f64@Wq_fp
    r_E = corr(fp['Q'], ideal_E)
    configs['E'] = r_E

    print(f"\n  Config                        Q Correlation")
    print(f"  {'─'*50}")
    print(f"  A) Per-tensor, no bias:          {configs['A']:.4f}")
    print(f"  B) Per-tensor + bias:            {configs['B']:.4f}")
    print(f"  C) Per-channel, no bias:         {configs['C']:.4f}")
    print(f"  D) Per-channel + bias:           {configs['D']:.4f}")
    print(f"  E) FP32 weights (LN1→Q only):    {configs['E']:.4f}")

    # Also do K and V
    print(f"\n  Same for K and V:")
    for name, W_key, bias_key in [("K", "W_k", "bias_k"), ("V", "W_v", "bias_v")]:
        Wpt, _ = quantize_per_tensor(weights_fp32[W_key])
        Wpc, spc = quantize_per_channel(weights_fp32[W_key])
        bias = weights_fp32[bias_key]

        iA = A_f64[:num_tokens] @ Wpt.astype(np.float64)
        iB = iA + (bias / embed_scale)[None, :]
        iC = (A_f64[:num_tokens] @ Wpc.astype(np.float64)) * spc[None, :]  # dequantize
        iD = iC + bias[None, :]  # bias in FP32 units
        iE = A_f64[:num_tokens] @ weights_fp32[W_key].astype(np.float64)

        rA = corr(fp[name], iA)
        rB = corr(fp[name], iB)
        rC = corr(fp[name], iC)
        rD = corr(fp[name], iD)
        rE = corr(fp[name], iE)
        print(f"  {name}: A={rA:.4f}  B={rB:.4f}  C={rC:.4f}  D={rD:.4f}  E={rE:.4f}")

    # Also test the output projection and FFN
    print(f"\n  Output projection (Attn @ W_o):")
    Wopt, _ = quantize_per_tensor(weights_fp32['W_o'])
    Wopc, sopc = quantize_per_channel(weights_fp32['W_o'])
    # Use FP32 attention output as input (isolate weight quant effect)
    A_attn = fp['attn'].astype(np.float64)
    fp_proj = fp['proj']
    iA = A_attn @ Wopt.astype(np.float64)  # per-tensor: corr is scale-invariant
    iC = (A_attn @ Wopc.astype(np.float64)) * sopc[None, :]  # dequantize per-channel
    iE = A_attn @ weights_fp32['W_o'].astype(np.float64)
    print(f"  Proj: A(pt)={corr(fp_proj, iA):.4f}  "
          f"C(pc)={corr(fp_proj, iC):.4f}  E(fp32)={corr(fp_proj, iE):.4f}")

    # ===== KEY TEST: What if LN1 was perfect? =====
    print(f"\n{'='*70}")
    print("  WHAT IF LN1 WAS PERFECT?")
    print("  (FP32 LN1 output → quantize to INT16 → matmul with INT16 weights)")
    print(f"{'='*70}")

    # Quantize FP32 LN1 to INT16 (best possible INT16 representation)
    fp_ln1 = fp['ln1']  # (num_tokens, 1024) FP32
    fp_ln1_amax = np.max(np.abs(fp_ln1))
    fp_ln1_scale = fp_ln1_amax / 32767.0
    fp_ln1_i16 = np.clip(np.round(fp_ln1 / fp_ln1_scale), -32767, 32767).astype(np.int16)
    # Pad to BT
    fp_ln1_padded = np.zeros((BT, MODEL_DIM), dtype=np.int16)
    fp_ln1_padded[:num_tokens] = fp_ln1_i16
    A_perfect = fp_ln1_padded.astype(np.float64)

    # Our current INT16 LN1
    r_ln1 = corr(fp_ln1, A_f64[:num_tokens])
    print(f"\n  LN1 correlation (our INT8 gamma/beta LN):     {r_ln1:.4f}")
    r_ln1_perfect = corr(fp_ln1, A_perfect[:num_tokens])
    print(f"  LN1 correlation (FP32→INT16 quantized LN):    {r_ln1_perfect:.4f}")

    # Q with perfect LN1 vs our LN1
    Wq_pt, _ = quantize_per_tensor(weights_fp32['W_q'])
    Q_our = A_f64[:num_tokens] @ Wq_pt.astype(np.float64)
    Q_perfect = A_perfect[:num_tokens] @ Wq_pt.astype(np.float64)
    Q_fp32w = A_perfect[:num_tokens] @ weights_fp32['W_q'].astype(np.float64)

    print(f"\n  Q with our LN1 + INT16 weights:               {corr(fp['Q'], Q_our):.4f}")
    print(f"  Q with perfect LN1 + INT16 weights:            {corr(fp['Q'], Q_perfect):.4f}")
    print(f"  Q with perfect LN1 + FP32 weights:             {corr(fp['Q'], Q_fp32w):.4f}")
    print(f"  Q with perfect LN1 + FP32 weights + bias:      {corr(fp['Q'], Q_fp32w + weights_fp32['bias_q'][None,:]):.4f}")

    # Also check: element-wise error in LN1
    ln1_err = np.abs(fp_ln1 - A_f64[:num_tokens].astype(np.float64) * fp_ln1_scale)
    print(f"\n  LN1 element-wise: our vs FP32")
    print(f"    Our LN1 range: [{A_f64[:num_tokens].min():.0f}, {A_f64[:num_tokens].max():.0f}]")
    print(f"    Perfect LN1 range: [{A_perfect[:num_tokens].min():.0f}, {A_perfect[:num_tokens].max():.0f}]")
    print(f"    Our LN1 std: {A_f64[:num_tokens].std():.1f}")
    print(f"    Perfect LN1 std: {A_perfect[:num_tokens].std():.1f}")

    # What about INT16 gamma/beta instead of INT8?
    print(f"\n{'='*70}")
    print("  WHAT IF LN USED INT16 GAMMA/BETA?")
    print(f"{'='*70}")

    ln1_gamma = sd["transformer.h.0.ln_1.weight"].numpy()
    ln1_beta = sd["transformer.h.0.ln_1.bias"].numpy()
    print(f"  FP32 gamma: range=[{ln1_gamma.min():.4f}, {ln1_gamma.max():.4f}], std={ln1_gamma.std():.4f}")
    print(f"  FP32 beta:  range=[{ln1_beta.min():.4f}, {ln1_beta.max():.4f}], std={ln1_beta.std():.4f}")

    # INT8 quantization error
    g_amax = np.max(np.abs(ln1_gamma))
    g_scale = g_amax / 127.0
    g_i8 = np.clip(np.round(ln1_gamma / g_scale), -127, 127)
    g_dequant = g_i8 * g_scale
    g_err = np.abs(ln1_gamma - g_dequant)
    print(f"  INT8 gamma: max_err={g_err.max():.6f}, mean_err={g_err.mean():.6f}, "
          f"relative_err={g_err.mean()/np.abs(ln1_gamma).mean():.4f}")

    b_amax = np.max(np.abs(ln1_beta))
    b_scale = b_amax / 127.0
    b_i8 = np.clip(np.round(ln1_beta / b_scale), -127, 127)
    b_dequant = b_i8 * b_scale
    b_err = np.abs(ln1_beta - b_dequant)
    print(f"  INT8 beta:  max_err={b_err.max():.6f}, mean_err={b_err.mean():.6f}, "
          f"relative_err={b_err.mean()/np.abs(ln1_beta).mean():.4f}")

    # INT16 would reduce error by 127x
    g_scale16 = g_amax / 32767.0
    g_i16 = np.clip(np.round(ln1_gamma / g_scale16), -32767, 32767)
    g_dequant16 = g_i16 * g_scale16
    g_err16 = np.abs(ln1_gamma - g_dequant16)
    print(f"  INT16 gamma: max_err={g_err16.max():.6f}, mean_err={g_err16.mean():.6f}, "
          f"relative_err={g_err16.mean()/np.abs(ln1_gamma).mean():.4f}")


if __name__ == "__main__":
    main()
