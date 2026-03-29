#!/usr/bin/env python3
"""
compare_fpga_act.py — Compare FPGA activation dump against golden model.

Usage:
    python3 verify/compare_fpga_act.py fpga/act_dump.hex fpga/data/weights.bin fpga/data/embed.bin

Loads the same GPT-2 weights the FPGA uses, runs golden model for 1 layer,
and compares per-step intermediate values against the FPGA activation dump.
"""

import sys
import struct
import numpy as np

# --------------------------------------------------------------------------
# FP16 helpers
# --------------------------------------------------------------------------
def fp16_to_f32(bits):
    """uint16 FP16 bit pattern → float32"""
    return float(np.array([bits], dtype=np.uint16).view(np.float16)[0])

def f32_to_fp16_bits(val):
    """float → uint16 FP16 bit pattern"""
    return int(np.float16(val).view(np.uint16))

def fp16_arr(bits_arr):
    """numpy uint16 array → float32 array"""
    return np.array(bits_arr, dtype=np.uint16).view(np.float16).astype(np.float32)

# --------------------------------------------------------------------------
# Parse act_dump.hex header and data
# --------------------------------------------------------------------------
def load_act_dump(path):
    meta = {}
    hex_lines = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith('#'):
                # parse key=value pairs
                for token in line.split():
                    if '=' in token:
                        k, v = token.split('=', 1)
                        try:
                            meta[k] = int(v)
                        except ValueError:
                            meta[k] = v
            elif line:
                hex_lines.append(line)
    # parse hex values
    vals = []
    for line in hex_lines:
        for tok in line.split():
            vals.append(int(tok, 16))
    return meta, np.array(vals, dtype=np.uint16)

# --------------------------------------------------------------------------
# Load weights from weights.bin
# --------------------------------------------------------------------------
MODEL_DIM = 1024
F_DIM     = 4096
NUM_HEADS = 16
HEAD_DIM  = MODEL_DIM // NUM_HEADS  # 64
WE        = 16  # elements per 256-bit word
WORD_BYTES = 32
MODEL_STRIDE = MODEL_DIM // WE  # 64
FFN_STRIDE   = F_DIM // WE      # 256
LAYER_SIZE   = 787264  # words per layer

# Per-layer word offsets
WQ_OFF    = 0
WK_OFF    = 65536
WV_OFF    = 131072
WO_OFF    = 196608
FFN1_OFF  = 262144
FFN2_OFF  = 524288
LN1_OFF   = 786432
LN2_OFF   = 786560
BIAS_QKV_OFF  = 786688
BIAS_PROJ_OFF = 786880
BIAS_FFN1_OFF = 786944
BIAS_FFN2_OFF = 787200

def load_weight_matrix(data, layer, offset, rows, cols, stride):
    """Extract a weight matrix from weights.bin raw bytes."""
    base = layer * LAYER_SIZE * WORD_BYTES
    mat = np.zeros((rows, cols), dtype=np.float16)
    for r in range(rows):
        for w in range(cols // WE):
            byte_off = base + (offset + r * stride + w) * WORD_BYTES
            for e in range(WE):
                c = w * WE + e
                if c < cols:
                    bits = struct.unpack_from('<H', data, byte_off + e * 2)[0]
                    mat[r, c] = np.uint16(bits).view(np.float16)
    return mat

def load_bias(data, layer, offset, size):
    """Extract a 1D bias vector from weights.bin."""
    base = layer * LAYER_SIZE * WORD_BYTES
    vec = np.zeros(size, dtype=np.float16)
    for i in range(size):
        word_idx = offset + i // WE
        elem_idx = i % WE
        byte_off = base + word_idx * WORD_BYTES + elem_idx * 2
        bits = struct.unpack_from('<H', data, byte_off)[0]
        vec[i] = np.uint16(bits).view(np.float16)
    return vec

def load_ln_params(data, layer, offset):
    """Extract interleaved gamma/beta from weights.bin."""
    base = layer * LAYER_SIZE * WORD_BYTES
    interleaved = []
    n_words = 2 * MODEL_DIM // WE  # 128 words
    for w in range(n_words):
        byte_off = base + (offset + w) * WORD_BYTES
        for e in range(WE):
            bits = struct.unpack_from('<H', data, byte_off + e * 2)[0]
            interleaved.append(np.uint16(bits).view(np.float16))
    gamma = np.array(interleaved[0::2], dtype=np.float16)
    beta  = np.array(interleaved[1::2], dtype=np.float16)
    return gamma, beta

def load_all_weights(wbin_path, layer=0):
    """Load all weights for a single layer."""
    with open(wbin_path, 'rb') as f:
        data = f.read()

    W = {}
    W['Wq']   = load_weight_matrix(data, layer, WQ_OFF,   MODEL_DIM, MODEL_DIM, MODEL_STRIDE)
    W['Wk']   = load_weight_matrix(data, layer, WK_OFF,   MODEL_DIM, MODEL_DIM, MODEL_STRIDE)
    W['Wv']   = load_weight_matrix(data, layer, WV_OFF,   MODEL_DIM, MODEL_DIM, MODEL_STRIDE)
    W['Wo']   = load_weight_matrix(data, layer, WO_OFF,   MODEL_DIM, MODEL_DIM, MODEL_STRIDE)
    W['Wffn1'] = load_weight_matrix(data, layer, FFN1_OFF, MODEL_DIM, F_DIM,     FFN_STRIDE)
    W['Wffn2'] = load_weight_matrix(data, layer, FFN2_OFF, F_DIM,     MODEL_DIM, MODEL_STRIDE)

    W['ln1_gamma'], W['ln1_beta'] = load_ln_params(data, layer, LN1_OFF)
    W['ln2_gamma'], W['ln2_beta'] = load_ln_params(data, layer, LN2_OFF)

    W['bias_qkv']  = load_bias(data, layer, BIAS_QKV_OFF,  3 * MODEL_DIM)
    W['bias_proj'] = load_bias(data, layer, BIAS_PROJ_OFF, MODEL_DIM)
    W['bias_ffn1'] = load_bias(data, layer, BIAS_FFN1_OFF, F_DIM)
    W['bias_ffn2'] = load_bias(data, layer, BIAS_FFN2_OFF, MODEL_DIM)
    return W

# --------------------------------------------------------------------------
# Load embeddings from embed.bin
# --------------------------------------------------------------------------
def load_embeddings(embed_path, token_ids):
    with open(embed_path, 'rb') as f:
        vocab_size, model_dim, max_pos, _ = struct.unpack('<4I', f.read(16))
        wte = np.frombuffer(f.read(vocab_size * model_dim * 4), dtype=np.float32).reshape(vocab_size, model_dim)
        wpe = np.frombuffer(f.read(max_pos * model_dim * 4), dtype=np.float32).reshape(max_pos, model_dim)
    # Compute embedding: wte[token] + wpe[pos], convert to FP16
    seq_len = len(token_ids)
    embed = np.zeros((seq_len, model_dim), dtype=np.float32)
    for i, tid in enumerate(token_ids):
        embed[i] = wte[tid] + wpe[i]
    return np.float16(embed)

# --------------------------------------------------------------------------
# Golden model functions (FP16 arithmetic matching RTL)
# --------------------------------------------------------------------------
def layernorm_golden(x_fp16, gamma_fp16, beta_fp16):
    """LayerNorm in FP32, output in FP16."""
    x = x_fp16.astype(np.float32)
    gamma = gamma_fp16.astype(np.float32)
    beta = beta_fp16.astype(np.float32)
    seq_len, dim = x.shape
    out = np.zeros_like(x)
    for i in range(seq_len):
        row = x[i]
        mean = np.mean(row)
        var = np.mean((row - mean) ** 2)
        inv_std = 1.0 / np.sqrt(var + 1e-5)
        out[i] = (row - mean) * inv_std * gamma + beta
    return np.float16(out)

def matmul_golden(a_fp16, w_fp16, bias_fp16=None):
    """FP16 matmul: A @ W + bias, accumulated in FP32."""
    result = a_fp16.astype(np.float32) @ w_fp16.astype(np.float32)
    if bias_fp16 is not None:
        result += bias_fp16.astype(np.float32)
    return np.float16(result)

def softmax_golden(x_fp16):
    """Row-wise softmax in FP32, output in FP16."""
    x = x_fp16.astype(np.float32)
    rows, cols = x.shape
    out = np.zeros_like(x)
    for i in range(rows):
        row = x[i, :cols]
        m = np.max(row)
        e = np.exp(row - m)
        out[i] = e / np.sum(e)
    return np.float16(out)

def gelu_golden(x_fp16):
    """GELU approximation matching RTL LUT."""
    x = x_fp16.astype(np.float32)
    return np.float16(0.5 * x * (1 + np.tanh(np.sqrt(2 / np.pi) * (x + 0.044715 * x**3))))

def multi_head_attention(Q, K, V, seq_len):
    """Multi-head attention with causal mask."""
    # Q, K, V are (seq_len, MODEL_DIM) in FP16
    scale = np.float16(1.0 / np.sqrt(HEAD_DIM))
    attn_out = np.zeros((seq_len, MODEL_DIM), dtype=np.float16)
    for h in range(NUM_HEADS):
        start = h * HEAD_DIM
        end = start + HEAD_DIM
        q = Q[:, start:end]  # (seq, head_dim)
        k = K[:, start:end]
        v = V[:, start:end]
        # Scores: Q @ K^T, in FP32
        scores = q.astype(np.float32) @ k.astype(np.float32).T  # (seq, seq)
        scores = np.float16(scores * float(scale))
        # Causal mask
        for i in range(seq_len):
            scores[i, i+1:] = np.float16(-65504.0)  # -inf in FP16
        # Softmax per row
        probs = softmax_golden(scores)
        # Attn output: probs @ V
        attn_out[:, start:end] = np.float16(
            probs.astype(np.float32) @ v.astype(np.float32)
        )
    return attn_out

def residual_add_golden(a_fp16, b_fp16):
    """Element-wise FP16 add."""
    return np.float16(a_fp16.astype(np.float32) + b_fp16.astype(np.float32))

# --------------------------------------------------------------------------
# Run golden model for 1 layer
# --------------------------------------------------------------------------
def compute_golden_layer(embed_fp16, W):
    """Compute one transformer layer, return per-step intermediates."""
    seq_len = embed_fp16.shape[0]
    steps = {}

    # Step 0: LN1
    ln1 = layernorm_golden(embed_fp16, W['ln1_gamma'], W['ln1_beta'])
    steps['LN1'] = ln1

    # Step 2: QKV matmul
    bias_q = W['bias_qkv'][:MODEL_DIM]
    bias_k = W['bias_qkv'][MODEL_DIM:2*MODEL_DIM]
    bias_v = W['bias_qkv'][2*MODEL_DIM:]
    Q = matmul_golden(ln1, W['Wq'], bias_q)
    K = matmul_golden(ln1, W['Wk'], bias_k)
    V = matmul_golden(ln1, W['Wv'], bias_v)
    steps['Q'] = Q
    steps['K'] = K
    steps['V'] = V

    # Step 3: Attention
    attn_out = multi_head_attention(Q, K, V, seq_len)
    steps['attn_out'] = attn_out

    # Step 4: Proj
    proj = matmul_golden(attn_out, W['Wo'], W['bias_proj'])
    steps['proj'] = proj

    # Step 5: Res1
    res1 = residual_add_golden(embed_fp16, proj)
    steps['res1'] = res1

    # Step 7: LN2
    ln2 = layernorm_golden(res1, W['ln2_gamma'], W['ln2_beta'])
    steps['LN2'] = ln2

    # Step 9: FFN1
    ffn1 = matmul_golden(ln2, W['Wffn1'], W['bias_ffn1'])
    steps['FFN1'] = ffn1

    # Step 10: GELU
    gelu = gelu_golden(ffn1)
    steps['GELU'] = gelu

    # Step 12: FFN2
    ffn2 = matmul_golden(gelu, W['Wffn2'], W['bias_ffn2'])
    steps['FFN2'] = ffn2

    # Step 13: Res2
    res2 = residual_add_golden(res1, ffn2)
    steps['res2'] = res2

    return steps

# --------------------------------------------------------------------------
# Extract activation regions from FPGA dump
# --------------------------------------------------------------------------
def extract_region(act_data, word_offset, seq_len, stride_words):
    """Extract (seq_len, MODEL_DIM) FP16 array from act dump at given word offset."""
    result = np.zeros((seq_len, MODEL_DIM), dtype=np.float16)
    for r in range(seq_len):
        base_elem = (word_offset + r * stride_words) * WE
        for c in range(MODEL_DIM):
            idx = base_elem + c
            if idx < len(act_data):
                result[r, c] = np.uint16(act_data[idx]).view(np.float16)
    return result

def compare(name, golden, fpga, tol=0.05):
    """Compare golden vs FPGA arrays, print stats."""
    g = golden.astype(np.float32).flatten()
    f = fpga.astype(np.float32).flatten()
    n = len(g)

    diff = np.abs(g - f)
    nonzero_g = np.count_nonzero(g)
    nonzero_f = np.count_nonzero(f)
    max_abs = np.max(diff)
    mean_abs = np.mean(diff)
    mismatch = np.sum(diff > tol)

    # Correlation
    if np.std(g) > 0 and np.std(f) > 0:
        corr = np.corrcoef(g, f)[0, 1]
    else:
        corr = 0.0

    status = "OK" if corr > 0.99 and mismatch < n * 0.05 else "**MISMATCH**"
    print(f"  {name:12s}: corr={corr:.6f} max_abs={max_abs:.4f} mean_abs={mean_abs:.6f} "
          f"mismatch={mismatch}/{n} nz_g={nonzero_g} nz_f={nonzero_f} {status}")

    if status == "**MISMATCH**":
        # Print first few mismatched values
        for i in range(min(10, n)):
            if diff[i] > tol:
                r, c = divmod(i, MODEL_DIM)
                print(f"    [{r},{c}] golden={g[i]:.6f} fpga={f[i]:.6f} diff={diff[i]:.6f}")
    return corr

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <act_dump.hex> <weights.bin> <embed.bin>")
        sys.exit(1)

    dump_path = sys.argv[1]
    wbin_path = sys.argv[2]
    embed_path = sys.argv[3]

    # Token IDs for "The meaning of life is"
    token_ids = [464, 3616, 286, 1204, 318]
    seq_len = len(token_ids)

    print("Loading activation dump...")
    meta, act_data = load_act_dump(dump_path)
    print(f"  meta: {meta}")
    print(f"  data: {len(act_data)} uint16 values")

    print("Loading embeddings...")
    embed_fp16 = load_embeddings(embed_path, token_ids)
    print(f"  embed shape: {embed_fp16.shape}")
    print(f"  embed[0,:4]: {embed_fp16[0,:4]}")

    print("Loading weights (layer 0)...")
    W = load_all_weights(wbin_path, layer=0)
    print(f"  Wq shape: {W['Wq'].shape}, Wq[0,:4]: {W['Wq'][0,:4]}")

    print("\nComputing golden model (layer 0)...")
    golden = compute_golden_layer(embed_fp16, W)

    # Extract FPGA regions from dump
    embed_off = meta.get('embed', 0)
    q_off     = meta.get('q', 8192)
    attn_off  = meta.get('attn', 32768)
    temp_off  = meta.get('temp', 40960)
    scratch   = meta.get('act_scratch_words', 49152)
    kv_layer  = meta.get('kv_layer_size', 16384)

    print("\n=== FPGA vs Golden Comparison (Layer 0) ===")

    # ACT_EMBED after all steps = res2 output
    fpga_embed = extract_region(act_data, embed_off, seq_len, MODEL_STRIDE)
    compare("res2/EMBED", golden['res2'], fpga_embed)

    # ACT_TEMP after step 8 = LN2 output (overwrites LN1 from step 1)
    fpga_temp = extract_region(act_data, temp_off, seq_len, MODEL_STRIDE)
    compare("LN2/TEMP", golden['LN2'], fpga_temp)

    # Q region — may contain QKV data or attn_out depending on step overwrites
    fpga_q = extract_region(act_data, q_off, seq_len, MODEL_STRIDE)
    # Try both Q and attn_out
    corr_q = compare("Q", golden['Q'], fpga_q)
    corr_attn = compare("attn_out", golden['attn_out'], fpga_q)

    # KV cache: K at scratch + 0, V at scratch + seq*MODEL_STRIDE
    kv_base_words = scratch  # start of KV region
    fpga_k = extract_region(act_data, kv_base_words, seq_len, MODEL_STRIDE)
    compare("K(KV$)", golden['K'], fpga_k)

    fpga_v = extract_region(act_data, kv_base_words + seq_len * MODEL_STRIDE, seq_len, MODEL_STRIDE)
    compare("V(KV$)", golden['V'], fpga_v)

    # Golden intermediate values for reference
    print("\n=== Golden Reference Values ===")
    for name in ['LN1', 'Q', 'K', 'V', 'attn_out', 'proj', 'res1', 'LN2', 'FFN1', 'GELU', 'FFN2', 'res2']:
        arr = golden[name].astype(np.float32)
        print(f"  {name:10s}: shape={golden[name].shape} "
              f"range=[{arr.min():.4f}, {arr.max():.4f}] "
              f"mean={arr.mean():.6f} absmax={np.abs(arr).max():.4f}")

    # Print first 8 values of each golden step for quick comparison
    print("\n=== Golden row0[0:8] per step ===")
    for name in ['LN1', 'Q', 'K', 'V', 'attn_out', 'proj', 'res1', 'LN2', 'FFN1', 'GELU', 'FFN2', 'res2']:
        vals = golden[name][0, :8].astype(np.float32)
        print(f"  {name:10s}: {' '.join(f'{v:10.4f}' for v in vals)}")

    # Print first 8 values from FPGA regions
    print("\n=== FPGA row0[0:8] per region ===")
    print(f"  {'EMBED':10s}: {' '.join(f'{v:10.4f}' for v in fpga_embed[0,:8].astype(np.float32))}")
    print(f"  {'TEMP':10s}: {' '.join(f'{v:10.4f}' for v in fpga_temp[0,:8].astype(np.float32))}")
    print(f"  {'Q_region':10s}: {' '.join(f'{v:10.4f}' for v in fpga_q[0,:8].astype(np.float32))}")
    print(f"  {'K(KV)':10s}: {' '.join(f'{v:10.4f}' for v in fpga_k[0,:8].astype(np.float32))}")
    print(f"  {'V(KV)':10s}: {' '.join(f'{v:10.4f}' for v in fpga_v[0,:8].astype(np.float32))}")

if __name__ == '__main__':
    main()
