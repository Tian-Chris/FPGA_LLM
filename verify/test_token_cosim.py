#!/usr/bin/env python3
"""End-to-end token co-simulation: real GPT-2 FP16 weights → RTL → token ID.

Loads real GPT-2 weights from binary files (exported by scripts/export_gpt2.py),
computes real embeddings, runs the golden model + RTL simulation, then applies
the CPU-side final pipeline (ln_f → unembed → argmax) to produce token IDs.

Compares golden vs RTL token output — the ultimate correctness check.

Usage:
  python3 verify/test_token_cosim.py                    # 2 layers, default prompt
  NUM_LAYERS=24 python3 verify/test_token_cosim.py      # full model
  python3 verify/test_token_cosim.py --prompt "Hello"   # custom prompt (needs transformers)
"""

import argparse
import os
import struct
import sys
import subprocess
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.golden.softmax import softmax_golden
from verify.golden.layernorm import layernorm_golden
from verify.golden.activation import gelu_golden
from verify.golden.residual_add import residual_add_golden

from verify.test_top import (
    pack_matrix_fp16,
    read_hex_dump,
    extract_matrix_from_hbm, extract_matrix_from_uram,
    compare_matrices, hex16,
)

from verify.test_top_1k import tiled_matmul_fp16_numpy, _transpose

from verify.test_multi_layer import (
    compute_one_layer, write_verilator_flags,
)

from verify.parse_debug_trace import parse_trace_file, print_trace

# ---------------------------------------------------------------------------
# Parameters (production dimensions)
# ---------------------------------------------------------------------------
MODEL_DIM     = 1024
NUM_HEADS     = 16
HEAD_DIM      = MODEL_DIM // NUM_HEADS   # 64
SCALE_FACTOR  = 0x3000  # FP16 1/√64 = 0.125 (matches defines.vh)
F_DIM         = 4096
MAX_SEQ_LEN   = 128
TILE_SIZE     = 32
NUM_ENGINES   = 6

DATA_W = 16
BUS_ELEMS = 16
WE = BUS_ELEMS
WORD_BYTES = 32

# HBM layout constants (must match scripts/export_gpt2.py)
LAYER_WQ_OFFSET   = 0
LAYER_WK_OFFSET   = MODEL_DIM * MODEL_DIM // WE
LAYER_WV_OFFSET   = 2 * MODEL_DIM * MODEL_DIM // WE
LAYER_WO_OFFSET   = 3 * MODEL_DIM * MODEL_DIM // WE
LAYER_FFN1_OFFSET = 4 * MODEL_DIM * MODEL_DIM // WE
LAYER_FFN2_OFFSET = LAYER_FFN1_OFFSET + MODEL_DIM * F_DIM // WE
LAYER_LN1_OFFSET  = LAYER_FFN2_OFFSET + F_DIM * MODEL_DIM // WE
LAYER_LN2_OFFSET  = LAYER_LN1_OFFSET + 2 * MODEL_DIM // WE
LAYER_BIAS_QKV_OFFSET  = LAYER_LN2_OFFSET + 2 * MODEL_DIM // WE
LAYER_BIAS_PROJ_OFFSET = LAYER_BIAS_QKV_OFFSET + 3 * MODEL_DIM // WE
LAYER_BIAS_FFN1_OFFSET = LAYER_BIAS_PROJ_OFFSET + MODEL_DIM // WE
LAYER_BIAS_FFN2_OFFSET = LAYER_BIAS_FFN1_OFFSET + F_DIM // WE
LAYER_SIZE             = LAYER_BIAS_FFN2_OFFSET + MODEL_DIM // WE

MODEL_STRIDE = MODEL_DIM // WE   # 64
F_STRIDE     = F_DIM // WE       # 256

# Paths
DATA_DIR      = os.path.join(PROJECT_ROOT, "fpga", "data")
TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
RTL_DIR       = os.path.join(PROJECT_ROOT, "rtl")
TB_DIR        = os.path.join(PROJECT_ROOT, "tb")
OBJ_DIR       = os.path.join(PROJECT_ROOT, "obj_dir")

GOLDEN_OUT = os.path.join(PROJECT_ROOT, "verify", "llm_golden_token.txt")
RTL_OUT    = os.path.join(PROJECT_ROOT, "verify", "llm_rtl_token.txt")

# Fixed sequence length (must match test_multi_layer's proven BT=32 config)
# Shorter prompts are zero-padded; we only use the first num_tokens positions.
SEQ_LEN = 32
BATCH   = 1
BT      = SEQ_LEN  # Fixed at 32 for RTL compatibility

# Default prompt: "The meaning of life is"
# Token IDs from GPT-2 BPE tokenizer (hardcoded to avoid tokenizer dependency)
DEFAULT_PROMPT = "The meaning of life is"
DEFAULT_TOKEN_IDS = [464, 3616, 286, 1204, 318]

RTL_ALL = [
    "bram_controller.v", "fp16_mult.v", "fp32_add.v", "fp32_to_fp16.v",
    "fp16_add.v", "fp16_compare.v", "fp_mac_unit.v",
    "agu.v", "matmul_engine.v",
    "mem_arbiter.v", "tiling_engine.v", "softmax.v", "layernorm.v",
    "activation.v", "residual_add.v", "host_interface.v",
    "positional_embedding.v", "fsm_controller.v", "sim_hbm.v",
    "debug_writer.v",
    "uram_accum_buf.v", "tile_loader.v", "uram_flush.v", "act_dma.v",
    "uram_nm_adapter.v", "top_level.v",
]


# ---------------------------------------------------------------------------
# FP32-Internal Golden Model (for 24-layer accuracy)
# ---------------------------------------------------------------------------
# The standard golden model (compute_one_layer) matches RTL precision exactly:
# FP16 softmax scale/diff, FP16 residual adds, etc. This is correct for RTL
# comparison but accumulates too much error at 24 layers for coherent text.
#
# compute_one_layer_fp32 does all internal computation in FP32, only converting
# to FP16 at matmul I/O (matching RTL's FP16×FP16→FP32 accumulation→FP16 output)
# and at layer boundaries. This produces coherent text and serves as the
# "ideal" reference for the FP16 hardware pipeline.

def _fp16_to_fp32_vec(bits_list):
    """Convert list of FP16 bit patterns to FP32 numpy array."""
    return np.array(bits_list, dtype=np.uint16).view(np.float16).astype(np.float32)

def _fp32_to_fp16_bits_vec(arr):
    """Convert FP32 numpy array (1D) to list of FP16 bit patterns."""
    return arr.astype(np.float16).view(np.uint16).astype(int).tolist()

def _fp32_to_fp16_bits_mat(arr2d):
    """Convert FP32 numpy array (2D) to list-of-lists of FP16 bit patterns."""
    fp16 = arr2d.astype(np.float16).view(np.uint16).astype(int)
    return [fp16[i].tolist() for i in range(fp16.shape[0])]

def _matmul_fp16_io_fp32_accum(A_bits, B_bits):
    """Matmul with FP16 inputs, FP32 accumulation, FP16 output.
    Matches RTL's fp_mac_unit behavior (no tiling artifacts)."""
    A = np.array(A_bits, dtype=np.uint16).view(np.float16).astype(np.float32)
    B = np.array(B_bits, dtype=np.uint16).view(np.float16).astype(np.float32)
    C = A @ B
    return C.astype(np.float16).view(np.uint16).astype(int).tolist()

def _add_bias_fp16(matrix_bits, bias_bits):
    """Add FP16 bias[j] to each matrix[i][j]. Returns list-of-lists of FP16 bit patterns."""
    mat = np.array(matrix_bits, dtype=np.uint16).view(np.float16).astype(np.float32)
    bias = np.array(bias_bits, dtype=np.uint16).view(np.float16).astype(np.float32)
    result = mat + bias[np.newaxis, :]
    return _fp32_to_fp16_bits_mat(result)

def _add_bias_f32(mat_f32, bias_bits):
    """Add FP16 bias (converted to FP32) to FP32 matrix. Returns FP32 array."""
    bias = np.array(bias_bits, dtype=np.uint16).view(np.float16).astype(np.float32)
    return mat_f32 + bias[np.newaxis, :]

def _softmax_fp32(scores_fp32, scale, row_idx=None):
    """FP32 softmax with causal mask. Returns FP32 array."""
    scaled = scores_fp32 * scale
    if row_idx is not None:
        scaled[row_idx+1:] = -1e9
    max_val = np.max(scaled)
    exp_vals = np.exp(scaled - max_val)
    if row_idx is not None:
        exp_vals[row_idx+1:] = 0.0
    return exp_vals / np.sum(exp_vals)

def compute_one_layer_fp32(x_fp16, weights, layer_idx):
    """One Pre-Norm layer with FP32 internal arithmetic.

    Matmul: FP16 input → FP32 accum → FP16 output (matches RTL)
    LayerNorm, softmax, residual, GELU: FP32 (more precise than RTL)
    Inter-layer storage: FP16 (matches RTL)
    """
    g = {}
    prefix = f"L{layer_idx}"
    scale = 1.0 / np.sqrt(HEAD_DIM)  # 0.125

    # --- LN1 (FP32 internal, matches RTL's FP32 layernorm) ---
    print(f"    [{prefix}] LN1...")
    gamma1 = _fp16_to_fp32_vec(weights['gamma1'])
    beta1  = _fp16_to_fp32_vec(weights['beta1'])
    x_f32 = np.array([_fp16_to_fp32_vec(row) for row in x_fp16])
    mean = x_f32.mean(axis=1, keepdims=True)
    var = ((x_f32 - mean) ** 2).mean(axis=1, keepdims=True)
    ln1_f32 = (x_f32 - mean) / np.sqrt(var + 1e-5) * gamma1 + beta1
    ln1_fp16 = _fp32_to_fp16_bits_mat(ln1_f32)

    # --- QKV matmuls (FP16 I/O, FP32 accum — matches RTL) + bias ---
    print(f"    [{prefix}] QKV matmuls...")
    Q = _matmul_fp16_io_fp32_accum(ln1_fp16, weights['W_q'])
    K = _matmul_fp16_io_fp32_accum(ln1_fp16, weights['W_k'])
    V = _matmul_fp16_io_fp32_accum(ln1_fp16, weights['W_v'])
    # Split QKV bias (3072) into Q/K/V portions (1024 each)
    qkv_bias = weights['qkv_bias']
    Q = _add_bias_fp16(Q, qkv_bias[:MODEL_DIM])
    K = _add_bias_fp16(K, qkv_bias[MODEL_DIM:2*MODEL_DIM])
    V = _add_bias_fp16(V, qkv_bias[2*MODEL_DIM:])
    g[f'{prefix}_K'] = K
    g[f'{prefix}_V'] = V

    # --- Multi-head attention (FP32 internal for score/softmax) ---
    print(f"    [{prefix}] Attention ({NUM_HEADS} heads)...")
    # Convert Q,K,V to FP32 for attention computation
    Q_f32 = np.array([_fp16_to_fp32_vec(row) for row in Q])
    K_f32 = np.array([_fp16_to_fp32_vec(row) for row in K])
    V_f32 = np.array([_fp16_to_fp32_vec(row) for row in V])

    attn_concat_f32 = np.zeros((BT, MODEL_DIM), dtype=np.float32)
    for h in range(NUM_HEADS):
        sl = slice(h*HEAD_DIM, (h+1)*HEAD_DIM)
        Qh = Q_f32[:, sl]
        Kh = K_f32[:, sl]
        Vh = V_f32[:, sl]
        scores = Qh @ Kh.T  # FP32 matmul
        probs = np.array([_softmax_fp32(scores[t], scale, row_idx=t) for t in range(BT)])
        attn_h = probs @ Vh  # FP32 matmul
        attn_concat_f32[:, sl] = attn_h

    # Convert attention output to FP16 for projection matmul
    attn_fp16 = _fp32_to_fp16_bits_mat(attn_concat_f32)

    # --- Output projection (FP16 I/O, FP32 accum) + bias ---
    print(f"    [{prefix}] Output projection...")
    attn_proj = _matmul_fp16_io_fp32_accum(attn_fp16, weights['W_o'])
    attn_proj = _add_bias_fp16(attn_proj, weights['proj_bias'])

    # --- Residual1 (FP32 add, then FP16 store) ---
    print(f"    [{prefix}] Residual 1...")
    res1_f32 = x_f32 + np.array([_fp16_to_fp32_vec(row) for row in attn_proj])
    res1_fp16 = _fp32_to_fp16_bits_mat(res1_f32)
    g[f'{prefix}_res1'] = res1_fp16

    # --- LN2 (FP32 internal) ---
    print(f"    [{prefix}] LN2...")
    gamma2 = _fp16_to_fp32_vec(weights['gamma2'])
    beta2  = _fp16_to_fp32_vec(weights['beta2'])
    r1_f32 = np.array([_fp16_to_fp32_vec(row) for row in res1_fp16])
    mean2 = r1_f32.mean(axis=1, keepdims=True)
    var2 = ((r1_f32 - mean2) ** 2).mean(axis=1, keepdims=True)
    ln2_f32 = (r1_f32 - mean2) / np.sqrt(var2 + 1e-5) * gamma2 + beta2
    ln2_fp16 = _fp32_to_fp16_bits_mat(ln2_f32)

    # --- FFN1 (FP16 I/O, FP32 accum) + bias ---
    print(f"    [{prefix}] FFN1 (1024x4096)...")
    ffn1 = _matmul_fp16_io_fp32_accum(ln2_fp16, weights['W_ffn1'])
    ffn1 = _add_bias_fp16(ffn1, weights['ffn1_bias'])

    # --- GELU (FP32 computation) ---
    print(f"    [{prefix}] GELU...")
    ffn1_f32 = np.array([_fp16_to_fp32_vec(row) for row in ffn1])
    # GELU tanh approximation: 0.5 * x * (1 + tanh(sqrt(2/π) * (x + 0.044715 * x^3)))
    gelu_f32 = 0.5 * ffn1_f32 * (1.0 + np.tanh(
        np.sqrt(2.0 / np.pi) * (ffn1_f32 + 0.044715 * ffn1_f32**3)))
    ffn_act_fp16 = _fp32_to_fp16_bits_mat(gelu_f32)

    # --- FFN2 (FP16 I/O, FP32 accum) + bias ---
    print(f"    [{prefix}] FFN2 (4096x1024)...")
    ffn2 = _matmul_fp16_io_fp32_accum(ffn_act_fp16, weights['W_ffn2'])
    ffn2 = _add_bias_fp16(ffn2, weights['ffn2_bias'])

    # --- Residual2 (FP32 add, then FP16 store) ---
    print(f"    [{prefix}] Residual 2...")
    res2_f32 = np.array([_fp16_to_fp32_vec(row) for row in res1_fp16]) + \
               np.array([_fp16_to_fp32_vec(row) for row in ffn2])
    res2_fp16 = _fp32_to_fp16_bits_mat(res2_f32)
    g[f'{prefix}_res2'] = res2_fp16

    return res2_fp16, g


# ---------------------------------------------------------------------------
# Binary File Loaders
# ---------------------------------------------------------------------------

def load_embed_bin(path):
    """Load embed.bin: header + wte + wpe + ln_f params.

    Returns dict with keys: vocab_size, model_dim, max_pos, wte, wpe,
    ln_f_gamma, ln_f_beta (all numpy arrays, FP32).
    """
    with open(path, 'rb') as f:
        header = struct.unpack('<IIII', f.read(16))
        vocab_size, model_dim, max_pos, _ = header

        wte = np.frombuffer(f.read(vocab_size * model_dim * 4), dtype=np.float32)
        wte = wte.reshape(vocab_size, model_dim)

        wpe = np.frombuffer(f.read(max_pos * model_dim * 4), dtype=np.float32)
        wpe = wpe.reshape(max_pos, model_dim)

        ln_f_gamma = np.frombuffer(f.read(model_dim * 4), dtype=np.float32).copy()
        ln_f_beta = np.frombuffer(f.read(model_dim * 4), dtype=np.float32).copy()

    return {
        'vocab_size': vocab_size, 'model_dim': model_dim, 'max_pos': max_pos,
        'wte': wte, 'wpe': wpe,
        'ln_f_gamma': ln_f_gamma, 'ln_f_beta': ln_f_beta,
    }


def load_weights_bin(path, num_layers):
    """Load first num_layers from weights.bin (FP16 format).

    Each layer occupies LAYER_SIZE * WORD_BYTES bytes in HBM layout.
    Weight matrices are FP16 (uint16 bit patterns).
    LN params are interleaved FP16: [gamma[0], beta[0], gamma[1], beta[1], ...].

    Returns list of weight dicts compatible with compute_one_layer().
    """
    layer_bytes = LAYER_SIZE * WORD_BYTES
    total_read = num_layers * layer_bytes

    with open(path, 'rb') as f:
        raw = f.read(total_read)

    if len(raw) < total_read:
        raise ValueError(f"weights.bin too small: {len(raw)} < {total_read} bytes "
                         f"(need {num_layers} layers)")

    layers = []
    for layer_idx in range(num_layers):
        base = layer_idx * layer_bytes
        w = {}

        def read_weight_matrix(offset, rows, cols, stride):
            """Read FP16 weight matrix from HBM layout as uint16 bit patterns."""
            mat = []
            words_per_row = cols // WE
            for r in range(rows):
                row = []
                for ww in range(words_per_row):
                    word_offset = base + (offset + r * stride + ww) * WORD_BYTES
                    elements = np.frombuffer(
                        raw[word_offset:word_offset + WORD_BYTES], dtype=np.uint16)
                    row.extend(int(e) for e in elements)
                mat.append(row)
            return mat

        def read_ln_params(offset):
            """Read LN gamma/beta from interleaved FP16 format.

            Layout: [gamma[0], beta[0], gamma[1], beta[1], ...] as FP16 uint16.
            Total = 2*MODEL_DIM values = 2*MODEL_DIM/WE words.
            """
            gamma = []
            beta = []
            ln_words = 2 * MODEL_DIM // WE  # 128 words
            for ww in range(ln_words):
                word_offset = base + (offset + ww) * WORD_BYTES
                elements = np.frombuffer(
                    raw[word_offset:word_offset + WORD_BYTES], dtype=np.uint16)
                # 16 FP16 values per word, interleaved: g0,b0,g1,b1,...
                for i in range(0, len(elements), 2):
                    gamma.append(int(elements[i]))
                    beta.append(int(elements[i + 1]))
            return gamma, beta

        w['W_q']    = read_weight_matrix(LAYER_WQ_OFFSET, MODEL_DIM, MODEL_DIM, MODEL_STRIDE)
        w['W_k']    = read_weight_matrix(LAYER_WK_OFFSET, MODEL_DIM, MODEL_DIM, MODEL_STRIDE)
        w['W_v']    = read_weight_matrix(LAYER_WV_OFFSET, MODEL_DIM, MODEL_DIM, MODEL_STRIDE)
        w['W_o']    = read_weight_matrix(LAYER_WO_OFFSET, MODEL_DIM, MODEL_DIM, MODEL_STRIDE)
        w['W_ffn1'] = read_weight_matrix(LAYER_FFN1_OFFSET, MODEL_DIM, F_DIM, F_STRIDE)
        w['W_ffn2'] = read_weight_matrix(LAYER_FFN2_OFFSET, F_DIM, MODEL_DIM, MODEL_STRIDE)
        w['gamma1'], w['beta1'] = read_ln_params(LAYER_LN1_OFFSET)
        w['gamma2'], w['beta2'] = read_ln_params(LAYER_LN2_OFFSET)

        layers.append(w)
        print(f"    Layer {layer_idx}: loaded "
              f"(W_q[0][:8]={[f'0x{v:04x}' for v in w['W_q'][0][:8]]})")

    return layers


def load_biases_from_weights(wgt_data, num_layers):
    """Extract biases from inline weights data (biases stored at LAYER_BIAS_*_OFFSET).

    Returns list of dicts with keys: qkv_bias, proj_bias, ffn1_bias, ffn2_bias.
    """
    def read_bias_vector(layer_base_word, offset_words, num_elements):
        """Read a bias vector from weight buffer at given word offset."""
        start_byte = (layer_base_word + offset_words) * WORD_BYTES
        num_words = num_elements // WE
        end_byte = start_byte + num_words * WORD_BYTES
        raw = wgt_data[start_byte:end_byte]
        return np.frombuffer(raw, dtype=np.uint16).copy()

    biases = []
    for layer_idx in range(num_layers):
        layer_base = layer_idx * LAYER_SIZE

        qkv  = read_bias_vector(layer_base, LAYER_BIAS_QKV_OFFSET,  3 * MODEL_DIM)
        proj = read_bias_vector(layer_base, LAYER_BIAS_PROJ_OFFSET, MODEL_DIM)
        ffn1 = read_bias_vector(layer_base, LAYER_BIAS_FFN1_OFFSET, F_DIM)
        ffn2 = read_bias_vector(layer_base, LAYER_BIAS_FFN2_OFFSET, MODEL_DIM)

        biases.append({
            'qkv_bias':  [int(e) for e in qkv],
            'proj_bias': [int(e) for e in proj],
            'ffn1_bias': [int(e) for e in ffn1],
            'ffn2_bias': [int(e) for e in ffn2],
        })

        if layer_idx == 0:
            b_qkv_f = qkv.view(np.float16).astype(np.float32)
            print(f"    Layer 0 biases: qkv_bias[:4]={b_qkv_f[:4]}, "
                  f"proj_bias[:4]={proj.view(np.float16).astype(np.float32)[:4]}")

    return biases


# ---------------------------------------------------------------------------
# Embedding Computation (matching host.cpp FP16 path)
# ---------------------------------------------------------------------------

def compute_embeddings(wte, wpe, token_ids, start_pos=0):
    """Compute FP16 embeddings from token IDs, matching host.cpp.

    Returns list of lists [seq_len x MODEL_DIM] with FP16 uint16 bit patterns.
    """
    seq_len = len(token_ids)
    embed_fp32 = np.zeros((seq_len, MODEL_DIM), dtype=np.float32)

    for s, tid in enumerate(token_ids):
        pos = start_pos + s
        embed_fp32[s] = wte[tid] + wpe[pos]

    # Convert FP32 → FP16 (matching host.cpp)
    embed_fp16 = embed_fp32.astype(np.float16)
    embed_bits = embed_fp16.view(np.uint16)

    print(f"    Embedding FP32 range: [{embed_fp32.min():.4f}, {embed_fp32.max():.4f}]")
    print(f"    Row 0 FP32[:8]: {embed_fp32[0, :8]}")
    print(f"    Row 0 FP16[:8]: {[f'0x{v:04x}' for v in embed_bits[0, :8]]}")

    return embed_bits.astype(int).tolist()


# ---------------------------------------------------------------------------
# Final Pipeline: ln_f → unembed → argmax (matching host.cpp)
# ---------------------------------------------------------------------------

def apply_final_pipeline(res2_fp16, ln_f_gamma, ln_f_beta, wte):
    """Apply CPU-side final pipeline to FP16 output, matching host.cpp.

    For each sequence position:
      1. Cast FP16 → float
      2. LayerNorm (FP32, eps=1e-5)
      3. Matmul with wte^T → logits
      4. Argmax → token ID

    Returns list of token IDs (one per sequence position).
    """
    tokens = []
    for row_idx, row in enumerate(res2_fp16):
        # Cast FP16 bit patterns to float32
        hidden = np.array(row, dtype=np.uint16).view(np.float16).astype(np.float32)

        # LayerNorm (eps=1e-5)
        mean = np.mean(hidden)
        var = np.mean((hidden - mean) ** 2)
        inv_std = 1.0 / np.sqrt(var + 1e-5)
        normed = (hidden - mean) * inv_std * ln_f_gamma + ln_f_beta

        # Unembed: normed @ wte.T → logits, then argmax
        logits = normed @ wte.T
        token_id = int(np.argmax(logits))
        tokens.append(token_id)

        if row_idx < 3 or row_idx == len(res2_fp16) - 1:
            print(f"    pos[{row_idx}]: mean={mean:.2f} var={var:.2f} "
                  f"top_logit={logits[token_id]:.2f} → token {token_id}")

    return tokens


# ---------------------------------------------------------------------------
# HBM Hex File Generation (from binary files)
# ---------------------------------------------------------------------------

def generate_hex_files_from_binary(weights_path, embed_fp16, num_layers,
                                   bt, sim_hbm_depth, weight_base, act_base):
    """Generate hbm_multi.hex from weights.bin + embeddings.

    The generated testbench (write_testbench) reads a single combined sparse hex
    file: hbm_multi.hex. This function packs weights, LN params, and embeddings
    into one sparse dict, then writes it with @addr directives.
    """
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    layer_bytes = LAYER_SIZE * WORD_BYTES
    total_weight_bytes = num_layers * layer_bytes

    # Read raw weight bytes
    with open(weights_path, 'rb') as f:
        weight_raw = f.read(total_weight_bytes)

    # Combined HBM: weights + LN params + embeddings in one dict
    hbm_mem = {}

    # Weight + LN param words from binary
    print("    Packing weight HBM from binary...")
    for layer_idx in range(num_layers):
        layer_base_byte = layer_idx * layer_bytes
        hbm_word_base = weight_base + layer_idx * LAYER_SIZE
        for word_idx in range(LAYER_SIZE):
            byte_offset = layer_base_byte + word_idx * WORD_BYTES
            chunk = weight_raw[byte_offset:byte_offset + WORD_BYTES]
            if any(b != 0 for b in chunk):
                hex_str = ''.join(f'{b:02x}' for b in reversed(chunk))
                hbm_mem[hbm_word_base + word_idx] = hex_str

    # Activation embeddings (at ACT_BASE)
    print("    Packing FP16 embeddings...")
    pack_matrix_fp16(embed_fp16, bt, MODEL_DIM,
                     act_base + 0, MODEL_STRIDE, hbm_mem)

    # Write single sparse hex file
    print(f"    Writing hbm_multi.hex ({len(hbm_mem)} non-zero words)...")
    with open(os.path.join(TEST_DATA_DIR, "hbm_multi.hex"), 'w') as f:
        for addr in sorted(hbm_mem.keys()):
            word = hbm_mem[addr]
            if word != '0' * 64:
                f.write(f"@{addr:08x} {word}\n")

    # Placeholder decode embed files (testbench $readmemh needs them)
    for fn in ["decode_embed_1.hex", "decode_embed_2.hex"]:
        path = os.path.join(TEST_DATA_DIR, fn)
        if not os.path.exists(path):
            with open(path, 'w') as f:
                for i in range(MODEL_STRIDE):
                    f.write('0' * 64 + '\n')

    print(f"  HBM hex files written ({num_layers} layers, depth={sim_hbm_depth})")


# ---------------------------------------------------------------------------
# Testbench, Compile, Run (reuse from test_multi_layer with patched globals)
# ---------------------------------------------------------------------------

def write_token_testbench(bt, seq_len, batch, sim_hbm_depth,
                          weight_base, act_base, kv_base, num_layers):
    """Write prefill-only testbench for token co-sim (no decode phases)."""
    tb_path = os.path.join(TB_DIR, "tb_top_multi.v")
    with open(tb_path, 'w') as f:
        f.write(f"""`timescale 1ns / 1ps

`include "defines.vh"

// Token co-sim testbench — prefill only (no decode phases)
module tb_top_multi;

    parameter HBM_RD_LATENCY  = 2;
    parameter URAM_RD_LATENCY = 1;

    localparam AXI_AW = 32;
    localparam AXI_DW = 32;
    localparam TB_HBM_DEPTH = {sim_hbm_depth};
    localparam SEQ_LEN = {seq_len};
    localparam BATCH   = {batch};
    localparam WE              = 16;
    localparam URAM_COL_WORDS_L = 64;
    localparam URAM_COL_WORDS_HW = 256;
    localparam URAM_ROWS_L     = 1024;
    localparam MODEL_STRIDE_L = 64;
    localparam WEIGHT_BASE = {weight_base};
    localparam ACT_BASE    = {act_base};
    localparam KV_BASE     = {kv_base};
    localparam OUTPUT_BASE = 32'h8000;
    localparam DEBUG_BASE  = TB_HBM_DEPTH - 512;

    reg clk, rst_n;
    reg  [AXI_AW-1:0]    s_axi_awaddr;
    reg                   s_axi_awvalid;
    wire                  s_axi_awready;
    reg  [AXI_DW-1:0]    s_axi_wdata;
    reg  [AXI_DW/8-1:0]  s_axi_wstrb;
    reg                   s_axi_wvalid;
    wire                  s_axi_wready;
    wire [1:0]            s_axi_bresp;
    wire                  s_axi_bvalid;
    reg                   s_axi_bready;
    reg  [AXI_AW-1:0]    s_axi_araddr;
    reg                   s_axi_arvalid;
    wire                  s_axi_arready;
    wire [AXI_DW-1:0]    s_axi_rdata;
    wire [1:0]            s_axi_rresp;
    wire                  s_axi_rvalid;
    reg                   s_axi_rready;
    wire                  irq_done;

    integer dump_row, dump_col, dump_addr, dump_fd;

    initial clk = 0;
    always #5 clk = ~clk;

    diffusion_transformer_top #(
        .AXI_ADDR_WIDTH (AXI_AW),
        .AXI_DATA_WIDTH (AXI_DW),
        .SIM_HBM_DEPTH  (TB_HBM_DEPTH),
        .HBM_RD_LATENCY (HBM_RD_LATENCY),
        .URAM_RD_LATENCY(URAM_RD_LATENCY)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .irq_done(irq_done)
    );

    task axi_write;
        input [AXI_AW-1:0] addr;
        input [AXI_DW-1:0] data;
        begin
            @(negedge clk);
            s_axi_awaddr = addr; s_axi_awvalid = 1'b1;
            s_axi_wdata = data; s_axi_wstrb = 4'hF; s_axi_wvalid = 1'b1;
            s_axi_bready = 1'b1;
            @(posedge clk); @(negedge clk);
            s_axi_awvalid = 1'b0; s_axi_wvalid = 1'b0;
            @(posedge clk); @(posedge clk);
            while (!s_axi_bvalid) @(posedge clk);
            @(posedge clk); @(negedge clk);
            s_axi_bready = 1'b0;
        end
    endtask

    integer uram_r, uram_c, uram_src;
    localparam URAM_EMBED_SRC = ACT_BASE;

    // HBM + URAM preloading
    initial begin
        #1;
        $readmemh("verify/test_data/hbm_multi.hex", dut.u_hbm.mem);
        for (uram_r = 0; uram_r < SEQ_LEN; uram_r = uram_r + 1) begin
            for (uram_c = 0; uram_c < MODEL_STRIDE_L; uram_c = uram_c + 1) begin
                uram_src = URAM_EMBED_SRC + uram_r * MODEL_STRIDE_L + uram_c;
                dut.u_uram.mem[uram_r * URAM_COL_WORDS_HW + uram_c] = dut.u_hbm.mem[uram_src];
            end
        end
        $display("[%0t] HBM + URAM preloading complete", $time);
        $fflush();
    end

    // Main test: prefill only
    initial begin
        rst_n = 0;
        s_axi_awaddr = 0; s_axi_awvalid = 0;
        s_axi_wdata = 0; s_axi_wstrb = 0; s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0; s_axi_arvalid = 0; s_axi_rready = 0;
        #100; rst_n = 1; #100;

        $display("[%0t] === PREFILL (seq=%0d, layers={num_layers}) ===", $time, SEQ_LEN);
        $fflush();
        axi_write(32'h08, BATCH);
        axi_write(32'h0C, SEQ_LEN);
        axi_write(32'h10, WEIGHT_BASE);
        axi_write(32'h14, ACT_BASE);
        axi_write(32'h18, OUTPUT_BASE);
        axi_write(32'h24, KV_BASE);
        axi_write(32'h1C, 32'd0);       // decode_mode = 0
        axi_write(32'h20, 32'd0);       // cache_len = 0
        axi_write(32'h28, {num_layers});
        axi_write(32'h2C, DEBUG_BASE);

        axi_write(32'h00, 32'h1);       // START

        while (dut.u_fsm.state != 5'd15) @(posedge clk);  // S_DONE=15
        $display("[%0t] PREFILL DONE", $time);
        $fflush();

        $display("[%0t] TEST PASSED: Prefill completed", $time);
        $fflush();

        // URAM dump
        dump_fd = $fopen("verify/test_data/uram_multi_dump.hex", "w");
        if (dump_fd != 0) begin
            for (dump_row = 0; dump_row < {bt}; dump_row = dump_row + 1) begin
                for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                    $fwrite(dump_fd, "%064h\\n",
                            dut.u_uram.mem[dump_row * URAM_COL_WORDS_HW + dump_col]);
                end
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped URAM (%0d rows)", $time, {bt});
            $fflush();
        end

        // HBM dump (sparse — ACT region)
        dump_fd = $fopen("verify/test_data/hbm_flush_multi_dump.hex", "w");
        if (dump_fd != 0) begin
            for (dump_row = 0; dump_row < {bt}; dump_row = dump_row + 1) begin
                for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                    dump_addr = ACT_BASE + dump_row * MODEL_STRIDE_L + dump_col;
                    $fwrite(dump_fd, "@%08h %064h\\n", dump_addr, dut.u_hbm.mem[dump_addr]);
                end
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped HBM ACT region", $time);
            $fflush();
        end

        // Debug trace dump
        dump_fd = $fopen("verify/test_data/debug_trace_multi.hex", "w");
        if (dump_fd != 0) begin
            for (dump_addr = DEBUG_BASE; dump_addr < DEBUG_BASE + 512; dump_addr = dump_addr + 1) begin
                if (dut.u_hbm.mem[dump_addr] != 256'd0) begin
                    $fwrite(dump_fd, "%064h\\n", dut.u_hbm.mem[dump_addr]);
                end
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped debug trace", $time);
            $fflush();
        end

        #100;
        $finish;
    end

    // FSM state monitor
    reg [4:0] prev_state;
    reg [7:0] prev_layer;
    initial begin prev_state = 0; prev_layer = 0; end
    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.u_fsm.layer_cnt !== prev_layer && dut.u_fsm.state != 0) begin
                $display("[%0t] === Layer %0d started ===", $time, dut.u_fsm.layer_cnt);
                prev_layer <= dut.u_fsm.layer_cnt;
            end
            prev_state <= dut.u_fsm.state;
        end
    end

    // Timeout watchdog
    initial begin
        #{num_layers * 400}000000000;
        $display("[%0t] ERROR: Simulation timeout!", $time);
        $display("  FSM state: %0d, Layer: %0d, Step: %0d",
                 dut.u_fsm.state, dut.u_fsm.layer_cnt, dut.u_fsm.step_idx);
        $display("  TEST FAILED: timeout");
        $fflush();
        $finish;
    end

endmodule
""")
    print(f"  Testbench written: {tb_path}")
    return tb_path


def compile_token_design(tb_path, num_layers):
    """Compile with Verilator."""
    flags_path = write_verilator_flags()
    rtl_paths = [os.path.join(RTL_DIR, f) for f in RTL_ALL]

    cmd = (["verilator", "--binary", "-f", flags_path,
            f"-DSIM_NUM_LAYERS={num_layers}",
            tb_path]
           + rtl_paths + ["--top-module", "tb_top_multi"])

    print(f"  Compiling with Verilator (NUM_LAYERS={num_layers})...")
    result = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  COMPILE FAILED:\n{result.stderr[:5000]}")
        return False
    print("  Compilation OK.")
    return True


def run_token_simulation(num_layers):
    """Run the compiled simulation."""
    binary = os.path.join(OBJ_DIR, "Vtb_top_multi")
    if not os.path.exists(binary):
        print(f"  ERROR: binary not found: {binary}")
        return False

    timeout = max(1800, num_layers * 600)
    print(f"  Running simulation ({num_layers} layers, timeout={timeout}s)...")
    try:
        result = subprocess.run([binary], cwd=PROJECT_ROOT,
                                capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"  FAIL: Simulation timed out ({timeout}s)")
        return False

    for line in result.stdout.splitlines():
        print(f"    {line}")

    if "TEST PASSED" not in result.stdout:
        print("  FAIL: TEST PASSED not in simulation output")
        if result.stderr:
            print(f"  stderr: {result.stderr[:2000]}")
        return False
    return True


def compare_token_output(golden_res2, bt, num_layers, act_base):
    """Read RTL dumps and compare against golden model."""
    flush_path = os.path.join(TEST_DATA_DIR, "hbm_flush_multi_dump.hex")
    uram_path  = os.path.join(TEST_DATA_DIR, "uram_multi_dump.hex")

    if not os.path.exists(flush_path):
        print("  ERROR: flush dump file not found")
        return None

    flush_words = read_hex_dump(flush_path)

    total_ok = total_mis = 0

    with open(RTL_OUT, 'w') as f:
        f.write("=" * 60 + "\n")
        f.write(f"TOKEN CO-SIM ({num_layers} layers) - RTL vs GOLDEN\n")
        f.write("=" * 60 + "\n\n")

        f.write("--- Final Output: Last layer res2 (flush HBM @ ACT_EMBED) ---\n")
        rtl_final = extract_matrix_from_hbm(
            flush_words, act_base + 0, bt, MODEL_STRIDE, MODEL_DIM)
        ok, mis = compare_matrices(golden_res2, rtl_final, 'final_output_flush', f,
                                   rel_tol=0.05, abs_tol=0.15)
        total_ok += ok; total_mis += mis

        if os.path.exists(uram_path):
            uram_words = read_hex_dump(uram_path)
            f.write("\n--- URAM Contents (should be final layer res2) ---\n")
            rtl_uram = extract_matrix_from_uram(
                uram_words, 0, bt, MODEL_STRIDE, MODEL_STRIDE)
            ok, mis = compare_matrices(golden_res2, rtl_uram, 'final_output_uram', f,
                                       rel_tol=0.05, abs_tol=0.15)
            total_ok += ok; total_mis += mis

        f.write("\n" + "=" * 60 + "\n")
        total = total_ok + total_mis
        f.write(f"SUMMARY: {total_ok}/{total} elements match\n")
        if total_mis == 0:
            f.write("ALL CHECKS PASSED\n")
        else:
            f.write(f"MISMATCHES: {total_mis} element(s) differ\n")

    print(f"  RTL comparison written: {RTL_OUT}")
    total = total_ok + total_mis
    # Allow up to 0.5% mismatch rate — FP16 rounding through deep pipelines
    mismatch_rate = total_mis / total if total > 0 else 0
    if total_mis == 0:
        print("  ALL FP16 CHECKS PASSED")
    elif mismatch_rate <= 0.005:
        print(f"  {total_mis}/{total} elements mismatched ({mismatch_rate*100:.2f}%) — within FP16 tolerance")
    else:
        print(f"  {total_mis}/{total} element(s) mismatched ({mismatch_rate*100:.2f}%) — EXCEEDS tolerance")
        print(f"  (see {RTL_OUT})")
        return None
    return rtl_final


def print_debug_trace():
    """Parse and print debug trace if available."""
    trace_path = os.path.join(TEST_DATA_DIR, "debug_trace_multi.hex")
    if not os.path.exists(trace_path):
        print("  (no debug trace file found)")
        return
    records = parse_trace_file(trace_path)
    if records:
        print_trace(records, trace_path)
    else:
        print("  (debug trace empty)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="End-to-end token co-simulation")
    parser.add_argument('--prompt', type=str, default=None,
                        help='Custom prompt (requires transformers library)')
    parser.add_argument('--data-only', action='store_true',
                        help='Generate data files only, skip compile/run')
    parser.add_argument('--compare-only', action='store_true',
                        help='Skip compile/run, compare existing dumps')
    args = parser.parse_args()

    num_layers = int(os.environ.get('NUM_LAYERS', '2'))

    # Resolve prompt and token IDs
    if args.prompt is not None:
        try:
            from transformers import GPT2Tokenizer
            tokenizer = GPT2Tokenizer.from_pretrained('gpt2')
            token_ids = tokenizer.encode(args.prompt)
            prompt_text = args.prompt
            print(f"  Tokenized prompt: {token_ids}")
        except ImportError:
            print("ERROR: --prompt requires `pip install transformers`")
            sys.exit(1)
    else:
        prompt_text = DEFAULT_PROMPT
        token_ids = DEFAULT_TOKEN_IDS

    num_tokens = len(token_ids)
    if num_tokens > SEQ_LEN:
        print(f"ERROR: prompt has {num_tokens} tokens, max {SEQ_LEN}")
        sys.exit(1)

    # Check weight files exist
    weights_path = os.path.join(DATA_DIR, "weights.bin")
    embed_path = os.path.join(DATA_DIR, "embed.bin")
    for p in [weights_path, embed_path]:
        if not os.path.exists(p):
            print(f"ERROR: {p} not found!")
            print(f"  Run on server: python3 scripts/export_gpt2.py --output-dir fpga/data")
            print(f"  Then: scp yangzi:~/FPGA_LLM/fpga/data/*.bin fpga/data/")
            sys.exit(1)

    # Compute HBM layout (BT=32 fixed, matching test_multi_layer)
    weight_base = 0
    act_base = num_layers * LAYER_SIZE
    kv_base = act_base + 6 * MAX_SEQ_LEN * MODEL_DIM // WE  # after activation scratch
    kv_layer_size = 2 * MAX_SEQ_LEN * MODEL_DIM // WE        # 16384
    kv_region_end = kv_base + num_layers * kv_layer_size
    sim_hbm_depth = 1 << max(21, kv_region_end.bit_length())

    print("=" * 60)
    print(f"  Token Co-Simulation ({num_layers} layers, real GPT-2 FP16 weights)")
    print(f"  Prompt: \"{prompt_text}\"")
    print(f"  Tokens: {token_ids} ({num_tokens} tokens, padded to BT={BT})")
    print(f"  MODEL_DIM={MODEL_DIM}, F_DIM={F_DIM}, NUM_HEADS={NUM_HEADS}")
    print(f"  WEIGHT_BASE={weight_base}, ACT_BASE={act_base}, KV_BASE={kv_base}")
    print(f"  SIM_HBM_DEPTH={sim_hbm_depth}")
    print("=" * 60)

    # Step 1: Load embed.bin
    print("\n  Loading embed.bin...")
    embed_data = load_embed_bin(embed_path)
    print(f"    vocab={embed_data['vocab_size']}, dim={embed_data['model_dim']}, "
          f"max_pos={embed_data['max_pos']}")

    # Step 2: Load weights.bin (includes inline biases)
    print(f"\n  Loading weights.bin ({num_layers} layers)...")
    layer_weights = load_weights_bin(weights_path, num_layers)

    # Extract biases from inline weights data
    print(f"  Extracting inline biases ({num_layers} layers)...")
    with open(weights_path, 'rb') as f:
        wgt_data = f.read()
    layer_biases = load_biases_from_weights(wgt_data, num_layers)
    for i in range(num_layers):
        layer_weights[i].update(layer_biases[i])

    # Step 3: Compute embeddings (pad to BT=32)
    print("\n  Computing FP16 embeddings...")
    embed_fp16_real = compute_embeddings(
        embed_data['wte'], embed_data['wpe'], token_ids)

    # Pad to BT=32 with zero rows
    embed_fp16 = embed_fp16_real + [[0] * MODEL_DIM] * (BT - num_tokens)
    assert len(embed_fp16) == BT

    # Step 4: Run golden model (with BT=32)
    # Use FP32-internal golden for token prediction (coherent at 24 layers)
    # Use RTL-matching golden for RTL comparison (exact FP16 precision match)
    print(f"\n  Running FP32-internal golden model ({num_layers} layers)...")
    all_intermediates = {}
    x = embed_fp16
    all_intermediates['embed_fp16'] = x
    for layer_idx in range(num_layers):
        print(f"  === Layer {layer_idx} ===")
        x, layer_g = compute_one_layer_fp32(x, layer_weights[layer_idx], layer_idx)
        all_intermediates.update(layer_g)
    all_intermediates['final_output'] = x

    golden_res2 = all_intermediates['final_output']

    # RTL-matching golden (exact FP16 precision) — skip for --data-only (slow)
    if not args.data_only:
        print(f"\n  Running RTL-matching golden model ({num_layers} layers)...")
        import verify.test_multi_layer as tml
        old_bt, old_nl = tml.BT, tml.NUM_LAYERS
        tml.BT = BT
        tml.NUM_LAYERS = num_layers
        try:
            x_rtl = embed_fp16
            for layer_idx in range(num_layers):
                print(f"  === Layer {layer_idx} (RTL-match) ===")
                x_rtl, _ = compute_one_layer(x_rtl, layer_weights[layer_idx], layer_idx)
            rtl_golden_res2 = x_rtl
        finally:
            tml.BT, tml.NUM_LAYERS = old_bt, old_nl
    else:
        rtl_golden_res2 = golden_res2  # use FP32 golden as placeholder

    # Write golden summary
    with open(GOLDEN_OUT, 'w') as f:
        f.write("=" * 60 + "\n")
        f.write(f"TOKEN CO-SIM GOLDEN ({num_layers} layers)\n")
        f.write("=" * 60 + "\n")
        f.write(f"Prompt: \"{prompt_text}\"\n")
        f.write(f"Tokens: {token_ids}\n")
        f.write(f"Config: BT={BT}, num_tokens={num_tokens}, "
                f"MODEL_DIM={MODEL_DIM}, NUM_LAYERS={num_layers}\n\n")
        for i in range(min(num_tokens, 4)):
            vals = "  ".join(hex16(v) for v in golden_res2[i][:32])
            f.write(f"  res2[{i}][:32]: {vals} ...\n")
    print(f"  Golden written: {GOLDEN_OUT}")

    # Step 5: Apply final pipeline to both goldens
    print("\n  Applying final pipeline (ln_f → unembed → argmax) to FP32 golden...")
    golden_tokens = apply_final_pipeline(
        golden_res2[:num_tokens], embed_data['ln_f_gamma'], embed_data['ln_f_beta'],
        embed_data['wte'])
    print(f"  FP32 golden tokens: {golden_tokens}")

    print("\n  Applying final pipeline to RTL-matching golden...")
    rtl_match_tokens = apply_final_pipeline(
        rtl_golden_res2[:num_tokens], embed_data['ln_f_gamma'], embed_data['ln_f_beta'],
        embed_data['wte'])
    print(f"  RTL-match golden tokens: {rtl_match_tokens}")

    # Try to decode
    try:
        from transformers import GPT2Tokenizer
        tokenizer = GPT2Tokenizer.from_pretrained('gpt2')
        print(f"\n  FP32 golden: \"{prompt_text}\" → \"{tokenizer.decode(golden_tokens)}\"")
        print(f"  RTL-match:   \"{prompt_text}\" → \"{tokenizer.decode(rtl_match_tokens)}\"")
    except ImportError:
        pass

    # Step 6: Generate hex files (BT=32 padded embeddings)
    print("\n  Generating HBM hex files...")
    generate_hex_files_from_binary(
        weights_path, embed_fp16, num_layers,
        BT, sim_hbm_depth, weight_base, act_base)

    if args.data_only:
        print("\n  --data-only: skipping compile/run")
        print(f"\n  FP32 golden next-token (pos {num_tokens-1}): {golden_tokens[-1]}")
        print(f"  RTL-match next-token (pos {num_tokens-1}): {rtl_match_tokens[-1]}")
        return

    if not args.compare_only:
        # Step 7: Write testbench, compile, simulate (BT=32)
        tb_path = write_token_testbench(BT, SEQ_LEN, BATCH, sim_hbm_depth,
                                        weight_base, act_base, kv_base, num_layers)
        if not compile_token_design(tb_path, num_layers):
            sys.exit(1)

        if not run_token_simulation(num_layers):
            sys.exit(1)
    else:
        print("\n  --compare-only: skipping compile/run")

    # Step 7.5: Print debug trace
    print("\n  === FSM Debug Trace ===")
    print_debug_trace()

    # Step 8: Compare RTL output against RTL-matching golden (element-wise)
    print("\n  Comparing RTL vs RTL-matching golden (element-wise)...")
    rtl_final = compare_token_output(rtl_golden_res2, BT, num_layers, act_base)
    if rtl_final is None:
        sys.exit(1)

    # Step 9: Apply final pipeline to RTL output (only real token positions)
    print("\n  Applying final pipeline to RTL output...")
    rtl_tokens = apply_final_pipeline(
        rtl_final[:num_tokens], embed_data['ln_f_gamma'], embed_data['ln_f_beta'],
        embed_data['wte'])
    print(f"  RTL tokens: {rtl_tokens}")

    # Step 10: Compare tokens (RTL vs FP32 golden for coherence check)
    print("\n" + "=" * 60)
    print("  TOKEN COMPARISON (RTL vs FP32 golden)")
    print("=" * 60)
    all_match = True
    for i in range(num_tokens):
        g = golden_tokens[i]
        r = rtl_tokens[i]
        rm = rtl_match_tokens[i]
        match_fp32 = "OK" if g == r else "MISS"
        match_rtl = "OK" if rm == r else "MISS"
        if g != r:
            all_match = False
        print(f"  pos[{i}]: fp32_golden={g:6d}  rtl_golden={rm:6d}  rtl={r:6d}  vs_fp32={match_fp32}  vs_rtl_golden={match_rtl}")

    # Focus on last real token position (next-token prediction)
    print(f"\n  Next token (pos {num_tokens-1}): fp32_golden={golden_tokens[-1]}, rtl={rtl_tokens[-1]}")

    # Try to decode tokens if transformers is available
    try:
        from transformers import GPT2Tokenizer
        tokenizer = GPT2Tokenizer.from_pretrained('gpt2')
        golden_text = tokenizer.decode(golden_tokens)
        rtl_text = tokenizer.decode(rtl_tokens)
        print(f"\n  Golden decoded: \"{prompt_text}\" → \"{golden_text}\"")
        print(f"  RTL decoded:    \"{prompt_text}\" → \"{rtl_text}\"")
    except ImportError:
        pass

    if all_match:
        print("\n  ALL TOKENS MATCH — PASSED")
    else:
        print("\n  TOKEN MISMATCH — FAILED")
        sys.exit(1)

    print("\nDone.")


if __name__ == "__main__":
    main()
