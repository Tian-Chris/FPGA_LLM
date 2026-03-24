#!/usr/bin/env python3
"""Standalone golden model comparison: FP32 accumulation vs integer accumulation.

Loads real GPT-2 weights, runs the golden model with both matmul strategies,
compares token outputs. No RTL required.

Usage:
  python3 verify/test_golden_intacc.py                    # 2 layers
  NUM_LAYERS=24 python3 verify/test_golden_intacc.py      # full model
"""

import os
import sys
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.test_token_cosim import (
    load_embed_bin, load_weights_bin, load_biases_from_weights,
    compute_embeddings, apply_final_pipeline,
    _fp16_to_fp32_vec, _fp32_to_fp16_bits_mat, _fp32_to_fp16_bits_vec,
    _matmul_fp16_io_fp32_accum, _add_bias_fp16, _add_bias_f32,
    _softmax_fp32,
    MODEL_DIM, NUM_HEADS, HEAD_DIM, F_DIM, WORD_BYTES, WE,
    DATA_DIR, MODEL_STRIDE, F_STRIDE, LAYER_SIZE,
    LAYER_WQ_OFFSET, LAYER_WK_OFFSET, LAYER_WV_OFFSET, LAYER_WO_OFFSET,
    LAYER_FFN1_OFFSET, LAYER_FFN2_OFFSET, LAYER_LN1_OFFSET, LAYER_LN2_OFFSET,
)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
NUM_LAYERS = int(os.environ.get('NUM_LAYERS', '2'))
SEQ_LEN = 32
BATCH = 1
BT = SEQ_LEN

DEFAULT_PROMPT = "The meaning of life is"
DEFAULT_TOKEN_IDS = [464, 3616, 286, 1204, 318]



# ---------------------------------------------------------------------------
# Integer Accumulation Matmul (numpy float64 — models no intermediate rounding)
# ---------------------------------------------------------------------------

def _matmul_fp16_io_intacc(A_bits, B_bits):
    """FP16 inputs, integer accumulation (via float64), FP16 output.

    float64 has 52-bit mantissa, far more than needed for 32 products of
    22-bit mantissas. This means no rounding during accumulation — only
    at the final FP16 conversion. This matches RTL integer accumulation
    behavior where the accumulator is wider than any individual product.
    """
    A = np.array(A_bits, dtype=np.uint16).view(np.float16).astype(np.float64)
    B = np.array(B_bits, dtype=np.uint16).view(np.float16).astype(np.float64)
    C = A @ B  # float64 accumulation — no intermediate rounding
    return C.astype(np.float16).view(np.uint16).astype(int).tolist()


def _add_bias_intacc(matrix_bits, bias_bits):
    """Add FP16 bias[j] to each matrix[i][j] via float64. Returns FP16 bit patterns."""
    mat = np.array(matrix_bits, dtype=np.uint16).view(np.float16).astype(np.float64)
    bias = np.array(bias_bits, dtype=np.uint16).view(np.float16).astype(np.float64)
    result = mat + bias[np.newaxis, :]
    return _fp32_to_fp16_bits_mat(result.astype(np.float32))


# ---------------------------------------------------------------------------
# One-layer compute functions (two variants)
# ---------------------------------------------------------------------------

def compute_one_layer_fp32accum(x_fp16, weights, layer_idx):
    """One layer using FP32 accumulation (current golden behavior)."""
    prefix = f"L{layer_idx}"
    scale = 1.0 / np.sqrt(HEAD_DIM)

    # LN1
    gamma1 = _fp16_to_fp32_vec(weights['gamma1'])
    beta1 = _fp16_to_fp32_vec(weights['beta1'])
    x_f32 = np.array([_fp16_to_fp32_vec(row) for row in x_fp16])
    mean = x_f32.mean(axis=1, keepdims=True)
    var = ((x_f32 - mean) ** 2).mean(axis=1, keepdims=True)
    ln1_f32 = (x_f32 - mean) / np.sqrt(var + 1e-5) * gamma1 + beta1
    ln1_fp16 = _fp32_to_fp16_bits_mat(ln1_f32)

    # QKV (FP32 accum)
    Q = _matmul_fp16_io_fp32_accum(ln1_fp16, weights['W_q'])
    K = _matmul_fp16_io_fp32_accum(ln1_fp16, weights['W_k'])
    V = _matmul_fp16_io_fp32_accum(ln1_fp16, weights['W_v'])
    qkv_bias = weights['qkv_bias']
    Q = _add_bias_fp16(Q, qkv_bias[:MODEL_DIM])
    K = _add_bias_fp16(K, qkv_bias[MODEL_DIM:2*MODEL_DIM])
    V = _add_bias_fp16(V, qkv_bias[2*MODEL_DIM:])

    # Attention (FP32 internal)
    Q_f32 = np.array([_fp16_to_fp32_vec(row) for row in Q])
    K_f32 = np.array([_fp16_to_fp32_vec(row) for row in K])
    V_f32 = np.array([_fp16_to_fp32_vec(row) for row in V])
    attn_concat_f32 = np.zeros((BT, MODEL_DIM), dtype=np.float32)
    for h in range(NUM_HEADS):
        sl = slice(h*HEAD_DIM, (h+1)*HEAD_DIM)
        scores = Q_f32[:, sl] @ K_f32[:, sl].T
        probs = np.array([_softmax_fp32(scores[t], scale, row_idx=t) for t in range(BT)])
        attn_concat_f32[:, sl] = probs @ V_f32[:, sl]
    attn_fp16 = _fp32_to_fp16_bits_mat(attn_concat_f32)

    # Output projection (FP32 accum)
    attn_proj = _matmul_fp16_io_fp32_accum(attn_fp16, weights['W_o'])
    attn_proj = _add_bias_fp16(attn_proj, weights['proj_bias'])

    # Residual 1
    res1_f32 = x_f32 + np.array([_fp16_to_fp32_vec(row) for row in attn_proj])
    res1_fp16 = _fp32_to_fp16_bits_mat(res1_f32)

    # LN2
    gamma2 = _fp16_to_fp32_vec(weights['gamma2'])
    beta2 = _fp16_to_fp32_vec(weights['beta2'])
    r1_f32 = np.array([_fp16_to_fp32_vec(row) for row in res1_fp16])
    mean2 = r1_f32.mean(axis=1, keepdims=True)
    var2 = ((r1_f32 - mean2) ** 2).mean(axis=1, keepdims=True)
    ln2_f32 = (r1_f32 - mean2) / np.sqrt(var2 + 1e-5) * gamma2 + beta2
    ln2_fp16 = _fp32_to_fp16_bits_mat(ln2_f32)

    # FFN1 (FP32 accum) + bias + GELU
    ffn1 = _matmul_fp16_io_fp32_accum(ln2_fp16, weights['W_ffn1'])
    ffn1 = _add_bias_fp16(ffn1, weights['ffn1_bias'])
    ffn1_f32 = np.array([_fp16_to_fp32_vec(row) for row in ffn1])
    gelu_f32 = 0.5 * ffn1_f32 * (1.0 + np.tanh(
        np.sqrt(2.0 / np.pi) * (ffn1_f32 + 0.044715 * ffn1_f32**3)))
    ffn_act_fp16 = _fp32_to_fp16_bits_mat(gelu_f32)

    # FFN2 (FP32 accum) + bias
    ffn2 = _matmul_fp16_io_fp32_accum(ffn_act_fp16, weights['W_ffn2'])
    ffn2 = _add_bias_fp16(ffn2, weights['ffn2_bias'])

    # Residual 2
    res2_f32 = np.array([_fp16_to_fp32_vec(row) for row in res1_fp16]) + \
               np.array([_fp16_to_fp32_vec(row) for row in ffn2])
    res2_fp16 = _fp32_to_fp16_bits_mat(res2_f32)
    return res2_fp16


def compute_one_layer_intacc(x_fp16, weights, layer_idx):
    """One layer using integer accumulation (float64 matmul, no intermediate rounding)."""
    prefix = f"L{layer_idx}"
    scale = 1.0 / np.sqrt(HEAD_DIM)

    # LN1 (same — FP32 internal, this is layernorm not matmul)
    gamma1 = _fp16_to_fp32_vec(weights['gamma1'])
    beta1 = _fp16_to_fp32_vec(weights['beta1'])
    x_f32 = np.array([_fp16_to_fp32_vec(row) for row in x_fp16])
    mean = x_f32.mean(axis=1, keepdims=True)
    var = ((x_f32 - mean) ** 2).mean(axis=1, keepdims=True)
    ln1_f32 = (x_f32 - mean) / np.sqrt(var + 1e-5) * gamma1 + beta1
    ln1_fp16 = _fp32_to_fp16_bits_mat(ln1_f32)

    # QKV (integer accum)
    Q = _matmul_fp16_io_intacc(ln1_fp16, weights['W_q'])
    K = _matmul_fp16_io_intacc(ln1_fp16, weights['W_k'])
    V = _matmul_fp16_io_intacc(ln1_fp16, weights['W_v'])
    qkv_bias = weights['qkv_bias']
    Q = _add_bias_intacc(Q, qkv_bias[:MODEL_DIM])
    K = _add_bias_intacc(K, qkv_bias[MODEL_DIM:2*MODEL_DIM])
    V = _add_bias_intacc(V, qkv_bias[2*MODEL_DIM:])

    # Attention (FP32 internal — same as before, softmax is not matmul)
    Q_f32 = np.array([_fp16_to_fp32_vec(row) for row in Q])
    K_f32 = np.array([_fp16_to_fp32_vec(row) for row in K])
    V_f32 = np.array([_fp16_to_fp32_vec(row) for row in V])
    attn_concat_f32 = np.zeros((BT, MODEL_DIM), dtype=np.float32)
    for h in range(NUM_HEADS):
        sl = slice(h*HEAD_DIM, (h+1)*HEAD_DIM)
        scores = Q_f32[:, sl] @ K_f32[:, sl].T
        probs = np.array([_softmax_fp32(scores[t], scale, row_idx=t) for t in range(BT)])
        attn_concat_f32[:, sl] = probs @ V_f32[:, sl]
    attn_fp16 = _fp32_to_fp16_bits_mat(attn_concat_f32)

    # Output projection (integer accum)
    attn_proj = _matmul_fp16_io_intacc(attn_fp16, weights['W_o'])
    attn_proj = _add_bias_intacc(attn_proj, weights['proj_bias'])

    # Residual 1
    res1_f32 = x_f32 + np.array([_fp16_to_fp32_vec(row) for row in attn_proj])
    res1_fp16 = _fp32_to_fp16_bits_mat(res1_f32)

    # LN2
    gamma2 = _fp16_to_fp32_vec(weights['gamma2'])
    beta2 = _fp16_to_fp32_vec(weights['beta2'])
    r1_f32 = np.array([_fp16_to_fp32_vec(row) for row in res1_fp16])
    mean2 = r1_f32.mean(axis=1, keepdims=True)
    var2 = ((r1_f32 - mean2) ** 2).mean(axis=1, keepdims=True)
    ln2_f32 = (r1_f32 - mean2) / np.sqrt(var2 + 1e-5) * gamma2 + beta2
    ln2_fp16 = _fp32_to_fp16_bits_mat(ln2_f32)

    # FFN1 (integer accum) + bias + GELU
    ffn1 = _matmul_fp16_io_intacc(ln2_fp16, weights['W_ffn1'])
    ffn1 = _add_bias_intacc(ffn1, weights['ffn1_bias'])
    ffn1_f32 = np.array([_fp16_to_fp32_vec(row) for row in ffn1])
    gelu_f32 = 0.5 * ffn1_f32 * (1.0 + np.tanh(
        np.sqrt(2.0 / np.pi) * (ffn1_f32 + 0.044715 * ffn1_f32**3)))
    ffn_act_fp16 = _fp32_to_fp16_bits_mat(gelu_f32)

    # FFN2 (integer accum) + bias
    ffn2 = _matmul_fp16_io_intacc(ffn_act_fp16, weights['W_ffn2'])
    ffn2 = _add_bias_intacc(ffn2, weights['ffn2_bias'])

    # Residual 2
    res2_f32 = np.array([_fp16_to_fp32_vec(row) for row in res1_fp16]) + \
               np.array([_fp16_to_fp32_vec(row) for row in ffn2])
    res2_fp16 = _fp32_to_fp16_bits_mat(res2_f32)
    return res2_fp16


# ---------------------------------------------------------------------------
# Comparison Utilities
# ---------------------------------------------------------------------------

def compare_fp16_matrices(name, mat_a, mat_b, max_rows=4, max_cols=16):
    """Compare two FP16 bit-pattern matrices, report element match rate."""
    total = 0
    exact = 0
    close = 0  # within 1 ULP
    max_diff = 0.0

    for i in range(len(mat_a)):
        for j in range(len(mat_a[0])):
            total += 1
            a_bits = mat_a[i][j]
            b_bits = mat_b[i][j]
            if a_bits == b_bits:
                exact += 1
                close += 1
            else:
                a_f = float(np.uint16(a_bits).view(np.float16))
                b_f = float(np.uint16(b_bits).view(np.float16))
                diff = abs(a_f - b_f)
                if diff > max_diff:
                    max_diff = diff
                if abs(a_bits - b_bits) <= 1:
                    close += 1

    pct_exact = 100.0 * exact / total if total > 0 else 0
    pct_close = 100.0 * close / total if total > 0 else 0
    print(f"  {name}: {exact}/{total} exact ({pct_exact:.1f}%), "
          f"{close}/{total} within 1 ULP ({pct_close:.1f}%), max_diff={max_diff:.6f}")
    return pct_exact


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    num_layers = NUM_LAYERS
    token_ids = DEFAULT_TOKEN_IDS
    num_tokens = len(token_ids)
    prompt_text = DEFAULT_PROMPT

    weights_path = os.path.join(DATA_DIR, "weights.bin")
    embed_path = os.path.join(DATA_DIR, "embed.bin")

    for p in [weights_path, embed_path]:
        if not os.path.exists(p):
            print(f"ERROR: Missing {p}")
            print(f"  Run: python3.11 scripts/export_gpt2.py --model gpt2-medium --output-dir fpga/data")
            sys.exit(1)

    print(f"=" * 60)
    print(f"Integer Accumulation Golden Model Test ({num_layers} layers)")
    print(f"=" * 60)
    print(f"  Prompt: \"{prompt_text}\"")
    print(f"  Tokens: {token_ids}")

    # Load weights (inline biases, LAYER_SIZE={LAYER_SIZE})
    print(f"\n  Loading embed.bin...")
    embed_data = load_embed_bin(embed_path)

    print(f"  Loading weights.bin ({num_layers} layers, inline biases)...")
    layer_weights = load_weights_bin(weights_path, num_layers)

    print(f"  Extracting inline biases...")
    with open(weights_path, 'rb') as f:
        wgt_data = f.read(num_layers * LAYER_SIZE * WORD_BYTES)
    layer_biases = load_biases_from_weights(wgt_data, num_layers)
    for i in range(num_layers):
        layer_weights[i].update(layer_biases[i])

    # Compute embeddings
    print(f"\n  Computing FP16 embeddings...")
    embed_fp16_real = compute_embeddings(
        embed_data['wte'], embed_data['wpe'], token_ids)
    embed_fp16 = embed_fp16_real + [[0] * MODEL_DIM] * (BT - num_tokens)

    # -----------------------------------------------------------------------
    # Run FP32 accumulation golden model
    # -----------------------------------------------------------------------
    print(f"\n{'='*60}")
    print(f"  Running FP32 accumulation golden ({num_layers} layers)...")
    print(f"{'='*60}")
    x_fp32acc = embed_fp16[:]
    for layer_idx in range(num_layers):
        print(f"  === Layer {layer_idx} (FP32 accum) ===")
        x_fp32acc = compute_one_layer_fp32accum(x_fp32acc, layer_weights[layer_idx], layer_idx)

    fp32acc_tokens = apply_final_pipeline(
        x_fp32acc[:num_tokens], embed_data['ln_f_gamma'], embed_data['ln_f_beta'],
        embed_data['wte'])
    print(f"\n  FP32 accum tokens: {fp32acc_tokens}")

    # -----------------------------------------------------------------------
    # Run integer accumulation golden model
    # -----------------------------------------------------------------------
    print(f"\n{'='*60}")
    print(f"  Running integer accumulation golden ({num_layers} layers)...")
    print(f"{'='*60}")
    x_intacc = embed_fp16[:]
    for layer_idx in range(num_layers):
        print(f"  === Layer {layer_idx} (int accum) ===")
        x_intacc = compute_one_layer_intacc(x_intacc, layer_weights[layer_idx], layer_idx)

    intacc_tokens = apply_final_pipeline(
        x_intacc[:num_tokens], embed_data['ln_f_gamma'], embed_data['ln_f_beta'],
        embed_data['wte'])
    print(f"\n  Int accum tokens: {intacc_tokens}")

    # -----------------------------------------------------------------------
    # Compare results
    # -----------------------------------------------------------------------
    print(f"\n{'='*60}")
    print(f"  COMPARISON RESULTS")
    print(f"{'='*60}")

    # Token comparison
    token_match = sum(1 for a, b in zip(fp32acc_tokens, intacc_tokens) if a == b)
    print(f"\n  Token match: {token_match}/{num_tokens}")
    print(f"  FP32 accum tokens: {fp32acc_tokens}")
    print(f"  Int  accum tokens: {intacc_tokens}")

    # Per-element comparison of final output
    print(f"\n  Final layer output (res2) comparison:")
    compare_fp16_matrices("final_output", x_fp32acc, x_intacc)

    # Try to decode tokens
    try:
        from transformers import GPT2Tokenizer
        tokenizer = GPT2Tokenizer.from_pretrained('gpt2')
        fp32_text = tokenizer.decode(fp32acc_tokens)
        intacc_text = tokenizer.decode(intacc_tokens)
        print(f"\n  FP32 accum: \"{prompt_text}\" → \"{fp32_text}\"")
        print(f"  Int  accum: \"{prompt_text}\" → \"{intacc_text}\"")
    except ImportError:
        print(f"\n  (transformers not installed — skipping token decode)")

    # Summary
    print(f"\n{'='*60}")
    if token_match == num_tokens:
        print(f"  PASS: All {num_tokens} tokens match between FP32 and integer accumulation")
    else:
        print(f"  INFO: {token_match}/{num_tokens} tokens match "
              f"(differences expected — integer accum is more precise)")
        print(f"        Both should produce coherent text at 24 layers.")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
