#!/usr/bin/env python3
"""End-to-end token co-simulation: real GPT-2 weights → RTL → token ID.

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
import math
import os
import struct
import sys
import subprocess
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.golden.common import int8, int16, int32, saturate_int16
from verify.golden.softmax import softmax_golden
from verify.golden.layernorm import layernorm_golden
from verify.golden.activation import relu_golden
from verify.golden.residual_add import residual_add_golden

from verify.test_top import (
    pack_int16_to_256bit, pack_int8_to_256bit_as_int16,
    write_hex_file, pack_matrix_int8_as_int16, pack_matrix_int16,
    pack_ln_params,
    read_hex_dump, extract_int16_from_256bit,
    extract_matrix_from_hbm, extract_matrix_from_uram,
    compare_matrices, hex16,
)

from verify.test_top_1k import tiled_matmul_int16_numpy, _transpose

from verify.test_multi_layer import (
    compute_one_layer, compute_golden,
    write_testbench, write_verilator_flags,
    compile_design, run_simulation,
    compare_rtl_output, write_golden,
)

# ---------------------------------------------------------------------------
# Parameters (production dimensions)
# ---------------------------------------------------------------------------
MODEL_DIM     = 1024
NUM_HEADS     = 16
HEAD_DIM      = MODEL_DIM // NUM_HEADS   # 64
SCALE_SHIFT   = math.ceil(math.log2(HEAD_DIM)) >> 1  # 3
F_DIM         = 4096
MAX_SEQ_LEN   = 128
TILE_SIZE     = 32
NUM_ENGINES   = 6

DATA_W = 16
BUS_ELEMS = 16
WE = BUS_ELEMS
WORD_BYTES = 32

# HBM layout constants
LAYER_WQ_OFFSET   = 0
LAYER_WK_OFFSET   = MODEL_DIM * MODEL_DIM // WE
LAYER_WV_OFFSET   = 2 * MODEL_DIM * MODEL_DIM // WE
LAYER_WO_OFFSET   = 3 * MODEL_DIM * MODEL_DIM // WE
LAYER_FFN1_OFFSET = 4 * MODEL_DIM * MODEL_DIM // WE
LAYER_FFN2_OFFSET = LAYER_FFN1_OFFSET + MODEL_DIM * F_DIM // WE
LAYER_LN1_OFFSET  = LAYER_FFN2_OFFSET + F_DIM * MODEL_DIM // WE
LAYER_LN2_OFFSET  = LAYER_LN1_OFFSET + 2 * MODEL_DIM // WE
LAYER_SIZE        = LAYER_LN2_OFFSET + 2 * MODEL_DIM // WE

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
    "bram_controller.v", "mac_unit.v", "agu.v", "matmul_engine.v",
    "mem_arbiter.v", "tiling_engine.v", "softmax.v", "layernorm.v",
    "activation.v", "residual_add.v", "quant_layer.v", "host_interface.v",
    "positional_embedding.v", "fsm_controller.v", "sim_hbm_port.v",
    "uram_accum_buf.v", "tile_loader.v", "uram_flush.v", "act_dma.v",
    "uram_nm_adapter.v", "uram_prefetch_buf.v", "hbm_prefetch.v",
    "top_level.v",
]


# ---------------------------------------------------------------------------
# Binary File Loaders
# ---------------------------------------------------------------------------

def load_embed_bin(path):
    """Load embed.bin: header + wte + wpe + ln_f params.

    Returns dict with keys: vocab_size, model_dim, max_pos, wte, wpe,
    ln_f_gamma, ln_f_beta (all numpy arrays).
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
    """Load first num_layers from weights.bin.

    Each layer occupies LAYER_SIZE * WORD_BYTES bytes in HBM layout.
    Unpacks INT16 matrices (which contain sign-extended INT8 values) and
    LN params (packed as {beta[7:0], gamma[7:0]} per INT16 element).

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
            """Read INT8 weight matrix from HBM layout."""
            mat = []
            words_per_row = cols // WE
            for r in range(rows):
                row = []
                for ww in range(words_per_row):
                    word_offset = base + (offset + r * stride + ww) * WORD_BYTES
                    elements = np.frombuffer(
                        raw[word_offset:word_offset + WORD_BYTES], dtype=np.int16)
                    # Values are sign-extended INT8 → INT16; extract INT8
                    row.extend(int(np.int8(e)) for e in elements)
                mat.append(row)
            return mat

        def read_ln_params(offset):
            """Read LN gamma/beta from packed format."""
            gamma = []
            beta = []
            words = MODEL_DIM // WE
            for ww in range(words):
                word_offset = base + (offset + ww) * WORD_BYTES
                elements = np.frombuffer(
                    raw[word_offset:word_offset + WORD_BYTES], dtype=np.int16)
                for e in elements:
                    val = int(e) & 0xFFFF
                    g = val & 0xFF
                    b = (val >> 8) & 0xFF
                    # Sign-extend from 8-bit
                    gamma.append(g if g < 128 else g - 256)
                    beta.append(b if b < 128 else b - 256)
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
              f"(W_q[0][:8]={w['W_q'][0][:8]})")

    return layers


# ---------------------------------------------------------------------------
# Embedding Computation (matching host.cpp)
# ---------------------------------------------------------------------------

def compute_embeddings(wte, wpe, token_ids, start_pos=0):
    """Compute INT16 embeddings from token IDs, matching host.cpp quantization.

    Returns list of lists [seq_len x MODEL_DIM] with INT16 values.
    """
    seq_len = len(token_ids)
    embed_fp32 = np.zeros((seq_len, MODEL_DIM), dtype=np.float32)

    for s, tid in enumerate(token_ids):
        pos = start_pos + s
        embed_fp32[s] = wte[tid] + wpe[pos]

    # Symmetric quantization to INT16 (matching host.cpp quantize_embed_to_int16)
    amax = np.max(np.abs(embed_fp32))
    scale = amax / 32767.0 if amax > 1e-10 else 1.0
    embed_int16 = np.clip(np.round(embed_fp32 / scale), -32768, 32767).astype(np.int16)

    print(f"    Embedding: amax={amax:.4f}, scale={scale:.6e}")
    print(f"    Row 0 FP32[:8]: {embed_fp32[0, :8]}")
    print(f"    Row 0 INT16[:8]: {embed_int16[0, :8]}")

    return embed_int16.tolist(), scale


# ---------------------------------------------------------------------------
# Final Pipeline: ln_f → unembed → argmax (matching host.cpp)
# ---------------------------------------------------------------------------

def apply_final_pipeline(res2_int16, ln_f_gamma, ln_f_beta, wte):
    """Apply CPU-side final pipeline to INT16 output, matching host.cpp.

    For each sequence position:
      1. Cast INT16 → float (no scale, just raw cast like host.cpp)
      2. LayerNorm (FP32, eps=1e-5)
      3. Matmul with wte^T → logits
      4. Argmax → token ID

    Returns list of token IDs (one per sequence position).
    """
    tokens = []
    for row_idx, row in enumerate(res2_int16):
        # Cast to float — host.cpp does: (float)raw_int16
        hidden = np.array([v if v < 32768 else v - 65536 for v in row],
                          dtype=np.float32)

        # LayerNorm (eps=1e-5)
        mean = np.mean(hidden)
        var = np.mean((hidden - mean) ** 2)
        inv_std = 1.0 / np.sqrt(var + 1e-5)
        normed = (hidden - mean) * inv_std * ln_f_gamma + ln_f_beta

        # Unembed: normed @ wte.T → logits, then argmax
        logits = normed @ wte.T
        token_id = int(np.argmax(logits))
        tokens.append(token_id)

        if row_idx < 3 or row_idx == len(res2_int16) - 1:
            print(f"    pos[{row_idx}]: mean={mean:.2f} var={var:.2f} "
                  f"top_logit={logits[token_id]:.2f} → token {token_id}")

    return tokens


# ---------------------------------------------------------------------------
# HBM Hex File Generation (from binary files)
# ---------------------------------------------------------------------------

def generate_hex_files_from_binary(weights_path, embed_int16, num_layers,
                                   bt, sim_hbm_depth, weight_base, act_base):
    """Generate hex files from weights.bin directly (already in HBM layout)."""
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    layer_bytes = LAYER_SIZE * WORD_BYTES
    total_weight_bytes = num_layers * layer_bytes

    # Read raw weight bytes
    with open(weights_path, 'rb') as f:
        weight_raw = f.read(total_weight_bytes)

    # Weight HBM: convert 32-byte chunks to 64-char hex strings
    print("    Packing weight HBM from binary...")
    wgt_mem = {}
    for layer_idx in range(num_layers):
        layer_base_byte = layer_idx * layer_bytes
        hbm_word_base = weight_base + layer_idx * LAYER_SIZE
        for word_idx in range(LAYER_SIZE):
            byte_offset = layer_base_byte + word_idx * WORD_BYTES
            chunk = weight_raw[byte_offset:byte_offset + WORD_BYTES]
            # Check if non-zero (skip zero words for speed)
            if any(b != 0 for b in chunk):
                # Convert to 256-bit hex string (big-endian byte order for hex)
                hex_str = ''.join(f'{b:02x}' for b in reversed(chunk))
                wgt_mem[hbm_word_base + word_idx] = hex_str

    print(f"    Writing weight hex file ({len(wgt_mem)} non-zero words)...")
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_wgt_multi.hex"),
                   [wgt_mem.get(a, '0' * 64) for a in range(sim_hbm_depth)])

    # Activation HBM: INT16 embeddings
    print("    Packing activation HBM...")
    act_mem = {}
    pack_matrix_int16(embed_int16, bt, MODEL_DIM,
                      act_base + 0, MODEL_STRIDE, act_mem)

    print("    Writing activation hex file...")
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_act_multi.hex"),
                   [act_mem.get(a, '0' * 64) for a in range(sim_hbm_depth)])

    # DMA HBM: LN params from weight binary + initial embeddings
    print("    Packing DMA HBM...")
    dma_mem = {}

    # LN params: extract from weight binary and pack
    for layer_idx in range(num_layers):
        layer_base_byte = layer_idx * layer_bytes
        hbm_word_base = weight_base + layer_idx * LAYER_SIZE

        for ln_offset in [LAYER_LN1_OFFSET, LAYER_LN2_OFFSET]:
            ln_words = 2 * MODEL_DIM // WE  # gamma + beta packed
            for word_idx in range(ln_words):
                byte_offset = layer_base_byte + (ln_offset + word_idx) * WORD_BYTES
                chunk = weight_raw[byte_offset:byte_offset + WORD_BYTES]
                if any(b != 0 for b in chunk):
                    hex_str = ''.join(f'{b:02x}' for b in reversed(chunk))
                    dma_mem[hbm_word_base + ln_offset + word_idx] = hex_str

    # Initial embeddings in DMA
    pack_matrix_int16(embed_int16, bt, MODEL_DIM,
                      act_base + 0, MODEL_STRIDE, dma_mem)

    print("    Writing DMA hex file...")
    write_hex_file(os.path.join(TEST_DATA_DIR, "hbm_dma_multi.hex"),
                   [dma_mem.get(a, '0' * 64) for a in range(sim_hbm_depth)])

    print(f"  HBM hex files written ({num_layers} layers, depth={sim_hbm_depth})")


# ---------------------------------------------------------------------------
# Testbench, Compile, Run (reuse from test_multi_layer with patched globals)
# ---------------------------------------------------------------------------

def write_token_testbench(bt, seq_len, batch, sim_hbm_depth,
                          weight_base, act_base, kv_base, num_layers):
    """Write testbench for token co-sim (same structure as multi-layer)."""
    import verify.test_multi_layer as tml
    # Patch module-level globals that write_testbench uses
    old_vals = (tml.SEQ_LEN, tml.BATCH, tml.BT, tml.SIM_HBM_DEPTH,
                tml.WEIGHT_BASE, tml.ACT_BASE, tml.KV_BASE, tml.NUM_LAYERS)
    tml.SEQ_LEN = seq_len
    tml.BATCH = batch
    tml.BT = bt
    tml.SIM_HBM_DEPTH = sim_hbm_depth
    tml.WEIGHT_BASE = weight_base
    tml.ACT_BASE = act_base
    tml.KV_BASE = kv_base
    tml.NUM_LAYERS = num_layers
    try:
        tb_path = write_testbench()
    finally:
        (tml.SEQ_LEN, tml.BATCH, tml.BT, tml.SIM_HBM_DEPTH,
         tml.WEIGHT_BASE, tml.ACT_BASE, tml.KV_BASE, tml.NUM_LAYERS) = old_vals
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

    timeout = max(600, num_layers * 120)
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
        ok, mis = compare_matrices(golden_res2, rtl_final, 'final_output_flush', f)
        total_ok += ok; total_mis += mis

        if os.path.exists(uram_path):
            uram_words = read_hex_dump(uram_path)
            f.write("\n--- URAM Contents (should be final layer res2) ---\n")
            rtl_uram = extract_matrix_from_uram(
                uram_words, 0, bt, MODEL_STRIDE, MODEL_STRIDE)
            ok, mis = compare_matrices(golden_res2, rtl_uram, 'final_output_uram', f)
            total_ok += ok; total_mis += mis

        f.write("\n" + "=" * 60 + "\n")
        total = total_ok + total_mis
        f.write(f"SUMMARY: {total_ok}/{total} elements match\n")
        if total_mis == 0:
            f.write("ALL CHECKS PASSED\n")
        else:
            f.write(f"MISMATCHES: {total_mis} element(s) differ\n")

    print(f"  RTL comparison written: {RTL_OUT}")
    if total_mis == 0:
        print("  ALL INT16 CHECKS PASSED")
        return rtl_final
    else:
        print(f"  {total_mis} element(s) mismatched (see {RTL_OUT})")
        return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="End-to-end token co-simulation")
    parser.add_argument('--prompt', type=str, default=None,
                        help='Custom prompt (requires transformers library)')
    parser.add_argument('--data-only', action='store_true',
                        help='Generate data files only, skip compile/run')
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
            print(f"  Download from server:")
            print(f"    scp yangzi:~/FPGA_LLM/fpga/data/weights.bin fpga/data/")
            print(f"    scp yangzi:~/FPGA_LLM/fpga/data/embed.bin fpga/data/")
            sys.exit(1)

    # Compute HBM layout (BT=32 fixed, matching test_multi_layer)
    weight_base = 0
    act_base = num_layers * LAYER_SIZE
    kv_base = act_base + 6 * MAX_SEQ_LEN * MODEL_DIM // WE  # after activation scratch
    kv_layer_size = 2 * MAX_SEQ_LEN * MODEL_DIM // WE        # 16384
    kv_region_end = kv_base + num_layers * kv_layer_size
    sim_hbm_depth = 1 << max(21, kv_region_end.bit_length())

    print("=" * 60)
    print(f"  Token Co-Simulation ({num_layers} layers, real GPT-2 weights)")
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

    # Step 2: Load weights.bin
    print(f"\n  Loading weights.bin ({num_layers} layers)...")
    layer_weights = load_weights_bin(weights_path, num_layers)

    # Step 3: Compute embeddings (pad to BT=32)
    print("\n  Computing embeddings...")
    embed_int16_real, embed_scale = compute_embeddings(
        embed_data['wte'], embed_data['wpe'], token_ids)

    # Pad to BT=32 with zero rows
    embed_int16 = embed_int16_real + [[0] * MODEL_DIM] * (BT - num_tokens)
    assert len(embed_int16) == BT

    # Step 4: Run golden model (with BT=32)
    print("\n  Running golden model...")
    import verify.test_multi_layer as tml
    # Patch globals for golden model
    old_bt, old_nl = tml.BT, tml.NUM_LAYERS
    tml.BT = BT
    tml.NUM_LAYERS = num_layers
    try:
        all_intermediates = {}
        x = embed_int16  # BT=32 rows, INT16 list-of-lists
        all_intermediates['embed_int16'] = x
        for layer_idx in range(num_layers):
            print(f"  === Layer {layer_idx} ===")
            x, layer_g = compute_one_layer(x, layer_weights[layer_idx], layer_idx)
            all_intermediates.update(layer_g)
        all_intermediates['final_output'] = x
    finally:
        tml.BT, tml.NUM_LAYERS = old_bt, old_nl

    golden_res2 = all_intermediates['final_output']

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

    # Step 5: Apply final pipeline to golden (only real token positions)
    print("\n  Applying final pipeline (ln_f → unembed → argmax) to golden output...")
    golden_tokens = apply_final_pipeline(
        golden_res2[:num_tokens], embed_data['ln_f_gamma'], embed_data['ln_f_beta'],
        embed_data['wte'])
    print(f"  Golden tokens: {golden_tokens}")

    # Step 6: Generate hex files (BT=32 padded embeddings)
    print("\n  Generating HBM hex files...")
    generate_hex_files_from_binary(
        weights_path, embed_int16, num_layers,
        BT, sim_hbm_depth, weight_base, act_base)

    if args.data_only:
        print("\n  --data-only: skipping compile/run")
        print(f"\n  Golden next-token (pos {num_tokens-1}): {golden_tokens[-1]}")
        return

    # Step 7: Write testbench, compile, simulate (BT=32)
    tb_path = write_token_testbench(BT, SEQ_LEN, BATCH, sim_hbm_depth,
                                    weight_base, act_base, kv_base, num_layers)
    if not compile_token_design(tb_path, num_layers):
        sys.exit(1)

    if not run_token_simulation(num_layers):
        sys.exit(1)

    # Step 8: Compare RTL output (all 32 rows)
    rtl_final = compare_token_output(golden_res2, BT, num_layers, act_base)
    if rtl_final is None:
        sys.exit(1)

    # Step 9: Apply final pipeline to RTL output (only real token positions)
    print("\n  Applying final pipeline to RTL output...")
    rtl_tokens = apply_final_pipeline(
        rtl_final[:num_tokens], embed_data['ln_f_gamma'], embed_data['ln_f_beta'],
        embed_data['wte'])
    print(f"  RTL tokens: {rtl_tokens}")

    # Step 10: Compare tokens
    print("\n" + "=" * 60)
    print("  TOKEN COMPARISON")
    print("=" * 60)
    all_match = True
    for i in range(num_tokens):
        match = "OK" if golden_tokens[i] == rtl_tokens[i] else "MISMATCH"
        if golden_tokens[i] != rtl_tokens[i]:
            all_match = False
        print(f"  pos[{i}]: golden={golden_tokens[i]:6d}  rtl={rtl_tokens[i]:6d}  {match}")

    # Focus on last real token position (next-token prediction)
    print(f"\n  Next token (pos {num_tokens-1}): golden={golden_tokens[-1]}, rtl={rtl_tokens[-1]}")

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
