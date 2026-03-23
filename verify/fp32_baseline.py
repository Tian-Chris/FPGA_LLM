#!/usr/bin/env python3
"""FP32 GPT-2-medium baseline vs our INT16 pipeline.

Runs the same prompt through:
1. HuggingFace GPT-2-medium (FP32, ground truth)
2. Our INT16 pipeline (INT8 weights, INT16 activations, auto-calibrated shifts)

Compares layer-by-layer to find where divergence starts.

Usage:
  python3.11 verify/fp32_baseline.py
  NUM_LAYERS=24 python3.11 verify/fp32_baseline.py
"""

import os
import sys
import math
import struct
import numpy as np
import torch
from transformers import GPT2LMHeadModel, GPT2Tokenizer

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
MODEL_DIM = 1024
NUM_HEADS = 16
HEAD_DIM  = MODEL_DIM // NUM_HEADS
F_DIM     = 4096
PROMPT    = "The meaning of life is"
NUM_LAYERS = int(os.environ.get('NUM_LAYERS', '24'))

# ---------------------------------------------------------------------------
# FP32 Reference: run GPT-2-medium with hooks to capture intermediates
# ---------------------------------------------------------------------------

def run_fp32_reference(prompt, num_layers):
    """Run GPT-2-medium in FP32 and capture per-layer residual stream."""
    print("  Loading GPT-2-medium (FP32)...")
    tokenizer = GPT2Tokenizer.from_pretrained('gpt2-medium')
    model = GPT2LMHeadModel.from_pretrained('gpt2-medium')
    model.eval()

    token_ids = tokenizer.encode(prompt)
    print(f"  Prompt: \"{prompt}\"")
    print(f"  Tokens: {token_ids} ({len(token_ids)} tokens)")

    input_ids = torch.tensor([token_ids])

    # Capture hidden states at each layer
    with torch.no_grad():
        outputs = model(input_ids, output_hidden_states=True)

    # outputs.hidden_states[0] = embedding output
    # outputs.hidden_states[i] = output of layer i-1 (after both residual adds)
    # outputs.hidden_states[num_layers] = final hidden state (before ln_f)
    logits = outputs.logits[0]  # [seq_len, vocab_size]

    # Next-token predictions
    pred_tokens = torch.argmax(logits, dim=-1).tolist()
    pred_text = tokenizer.decode(pred_tokens)

    print(f"\n  FP32 predicted tokens: {pred_tokens}")
    print(f"  FP32 decoded: \"{prompt}\" → \"{pred_text}\"")

    # Top-5 for last position
    last_logits = logits[-1]
    top5_vals, top5_ids = torch.topk(last_logits, 5)
    print(f"\n  FP32 next-token (pos {len(token_ids)-1}) top-5:")
    for val, tid in zip(top5_vals, top5_ids):
        tok_str = tokenizer.decode([tid.item()])
        print(f"    {tid.item():6d} ({tok_str!r:>12s}): logit={val.item():.2f}")

    # Extract hidden states
    hidden_states = {}
    for i in range(min(num_layers + 1, len(outputs.hidden_states))):
        hs = outputs.hidden_states[i][0].numpy()  # [seq_len, model_dim]
        hidden_states[i] = hs
        if i == 0:
            label = "embedding"
        else:
            label = f"after layer {i-1}"
        rng = f"[{hs.min():.4f}, {hs.max():.4f}]"
        std = f"std={hs.std():.4f}"
        print(f"  hidden[{i:2d}] ({label:>16s}): range={rng}, {std}")

    return {
        'token_ids': token_ids,
        'pred_tokens': pred_tokens,
        'logits': logits.numpy(),
        'hidden_states': hidden_states,
        'tokenizer': tokenizer,
    }


# ---------------------------------------------------------------------------
# INT16 Pipeline: Load our exported weights and run the rescaled golden model
# ---------------------------------------------------------------------------

def run_int16_pipeline(prompt, token_ids, num_layers):
    """Run our INT16 pipeline with auto-calibrated shifts."""
    # Import our golden model
    from verify.golden.common import int8, int16, int32, saturate_int16
    from verify.golden.softmax import softmax_golden
    from verify.golden.layernorm import layernorm_golden
    from verify.golden.activation import relu_golden
    from verify.test_top_1k import _transpose
    from verify.test_token_cosim import (
        load_embed_bin, load_weights_bin, compute_embeddings,
        compute_one_layer_rescaled, apply_final_pipeline,
        _to_s16, tiled_matmul_int64_autoscale, adaptive_residual_add,
        TILE_SIZE, SCALE_SHIFT, BT, WE,
        LAYER_SIZE, MAX_SEQ_LEN,
    )

    DATA_DIR = os.path.join(PROJECT_ROOT, "fpga", "data")
    embed_path = os.path.join(DATA_DIR, "embed.bin")
    weights_path = os.path.join(DATA_DIR, "weights.bin")

    for p in [embed_path, weights_path]:
        if not os.path.exists(p):
            print(f"  ERROR: {p} not found")
            return None

    # Load data
    embed_data = load_embed_bin(embed_path)
    layer_weights = load_weights_bin(weights_path, num_layers)

    # Compute embeddings
    embed_int16, embed_scale = compute_embeddings(
        embed_data['wte'], embed_data['wpe'], token_ids)
    embed_int16 = embed_int16 + [[0] * MODEL_DIM] * (BT - len(token_ids))

    # Run rescaled golden model, capture per-layer output
    import verify.test_multi_layer as tml
    old_bt, old_nl = tml.BT, tml.NUM_LAYERS
    tml.BT = BT
    tml.NUM_LAYERS = num_layers

    layer_outputs = {}
    layer_outputs[0] = np.array(embed_int16[:len(token_ids)], dtype=np.float32)

    x = embed_int16
    try:
        for layer_idx in range(num_layers):
            print(f"  === Layer {layer_idx} ===")
            x, shifts = compute_one_layer_rescaled(
                x, layer_weights[layer_idx], layer_idx, calibrate=True)
            # Store as float for comparison
            x_arr = _to_s16(x[:len(token_ids)])
            layer_outputs[layer_idx + 1] = x_arr.astype(np.float32)
    finally:
        tml.BT, tml.NUM_LAYERS = old_bt, old_nl

    # Final pipeline
    tokens = apply_final_pipeline(
        x[:len(token_ids)],
        embed_data['ln_f_gamma'], embed_data['ln_f_beta'],
        embed_data['wte'])

    return {
        'pred_tokens': tokens,
        'layer_outputs': layer_outputs,
        'embed_scale': embed_scale,
    }


# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------

def cosine_similarity(a, b):
    """Cosine similarity between two vectors."""
    dot = np.sum(a * b)
    norm_a = np.sqrt(np.sum(a * a))
    norm_b = np.sqrt(np.sum(b * b))
    if norm_a < 1e-10 or norm_b < 1e-10:
        return 0.0
    return dot / (norm_a * norm_b)


def compare_pipelines(fp32_result, int16_result, num_tokens):
    """Compare FP32 and INT16 hidden states layer by layer."""
    print("\n" + "=" * 70)
    print("  LAYER-BY-LAYER COMPARISON: FP32 vs INT16")
    print("=" * 70)
    print(f"  {'Layer':>5s}  {'Cosine Sim':>10s}  {'Correlation':>11s}  "
          f"{'FP32 std':>10s}  {'INT16 std':>10s}  {'Note':s}")

    fp32_hs = fp32_result['hidden_states']
    int16_lo = int16_result['layer_outputs']
    embed_scale = int16_result['embed_scale']

    for layer_idx in sorted(set(fp32_hs.keys()) & set(int16_lo.keys())):
        fp32_vals = fp32_hs[layer_idx][:num_tokens].flatten()
        int16_vals = int16_lo[layer_idx][:num_tokens].flatten()

        # For embedding layer, INT16 values are scaled — rescale for comparison
        # After layer 0, INT16 values are in arbitrary scale due to shifts
        cos = cosine_similarity(fp32_vals, int16_vals)

        # Pearson correlation (scale-invariant)
        if np.std(fp32_vals) > 1e-10 and np.std(int16_vals) > 1e-10:
            corr = np.corrcoef(fp32_vals, int16_vals)[0, 1]
        else:
            corr = 0.0

        fp32_std = np.std(fp32_vals)
        int16_std = np.std(int16_vals)

        note = ""
        if layer_idx == 0:
            note = "(embedding)"
        elif corr < 0.5:
            note = "** LOW CORRELATION **"
        elif corr < 0.8:
            note = "* degraded *"

        print(f"  {layer_idx:5d}  {cos:10.4f}  {corr:11.4f}  "
              f"{fp32_std:10.4f}  {int16_std:10.1f}  {note}")

    # Token comparison
    print("\n" + "=" * 70)
    print("  TOKEN COMPARISON")
    print("=" * 70)
    fp32_tokens = fp32_result['pred_tokens'][:num_tokens]
    int16_tokens = int16_result['pred_tokens'][:num_tokens]
    tokenizer = fp32_result['tokenizer']

    matches = 0
    for i in range(num_tokens):
        fp32_t = fp32_tokens[i]
        int16_t = int16_tokens[i]
        match = "OK" if fp32_t == int16_t else "MISS"
        if fp32_t == int16_t:
            matches += 1
        fp32_str = tokenizer.decode([fp32_t])
        int16_str = tokenizer.decode([int16_t])
        print(f"  pos[{i}]: fp32={fp32_t:6d} ({fp32_str!r:>10s})  "
              f"int16={int16_t:6d} ({int16_str!r:>10s})  {match}")

    print(f"\n  Match rate: {matches}/{num_tokens} "
          f"({100*matches/num_tokens:.0f}%)")

    # What FP32 GPT-2 actually predicts as next token
    next_fp32 = fp32_tokens[-1]
    next_int16 = int16_tokens[-1]
    print(f"\n  FP32 next token: {next_fp32} ({tokenizer.decode([next_fp32])!r})")
    print(f"  INT16 next token: {next_int16} ({tokenizer.decode([next_int16])!r})")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 70)
    print(f"  FP32 Baseline vs INT16 Pipeline ({NUM_LAYERS} layers)")
    print(f"  Prompt: \"{PROMPT}\"")
    print("=" * 70)

    # Step 1: FP32 reference
    print("\n--- FP32 Reference (GPT-2-medium) ---")
    fp32_result = run_fp32_reference(PROMPT, NUM_LAYERS)
    num_tokens = len(fp32_result['token_ids'])

    # Step 2: INT16 pipeline
    print("\n--- INT16 Pipeline (auto-calibrated shifts + adaptive residual) ---")
    int16_result = run_int16_pipeline(PROMPT, fp32_result['token_ids'], NUM_LAYERS)

    if int16_result is None:
        print("  INT16 pipeline failed — missing weight files")
        sys.exit(1)

    # Step 3: Compare
    compare_pipelines(fp32_result, int16_result, num_tokens)


if __name__ == "__main__":
    main()
