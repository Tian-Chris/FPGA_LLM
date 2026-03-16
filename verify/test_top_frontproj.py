#!/usr/bin/env python3
"""Frontend projection stage test.

Operation: output[BT x MODEL_DIM] = input[BT x INPUT_DIM] @ W_proj[INPUT_DIM x MODEL_DIM]
           INT8 @ INT8 -> INT16 (saturating)

Produces two files:
  verify/frontproj_golden.txt  -- inputs, weights, operation, expected output (RTL hex)
  verify/frontproj_rtl.txt     -- RTL BRAM dump extracted after frontend stage (RTL hex)
"""

import os
import sys
import random
import subprocess

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from verify.hex_utils import to_hex
from verify.bram_layout import (
    encode_to_banks,
    flatten_weight_layout,
    write_bank_hex_files,
    read_interleaved_hex,
)
from verify.golden.transformer import (
    TransformerConfig,
    generate_random_weights,
    tiled_matmul,
)
from verify.golden.common import int8, int16

# ---------------------------------------------------------------------------
# Parameters — 4x4 frontend projection
# ---------------------------------------------------------------------------
MODEL_DIM   = 4
INPUT_DIM   = 4
F_DIM       = 8
NUM_HEADS   = 1
HEAD_DIM    = MODEL_DIM // NUM_HEADS
MAX_SEQ_LEN = 4
MAX_BATCH   = 1
NUM_ENC     = 1
NUM_DEN     = 1
TILE_SIZE   = 4
SEQ_LEN     = 4
BATCH       = 1
BT          = BATCH * SEQ_LEN   # 4 tokens

WGT_DEPTH   = 2048
ACT_DEPTH   = 512
WGT_BANKS   = TILE_SIZE        # 4
ACT_BANKS   = TILE_SIZE // 2  # 2

DATA_W = 8    # INT8
ACC_W  = 16   # INT16

# Activation BRAM offset where frontend output is written (matches fsm_controller.v)
# ACT_EMBED_OFFSET = MAX_SEQ_LEN * INPUT_DIM (elements)
ACT_EMBED_OFFSET = MAX_SEQ_LEN * INPUT_DIM // TILE_SIZE  # 4 (BRAM word address; matches fsm_controller.v)

TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
RTL_DIR       = os.path.join(PROJECT_ROOT, "rtl")
TB_DIR        = os.path.join(PROJECT_ROOT, "tb")
OBJ_DIR       = os.path.join(PROJECT_ROOT, "obj_dir")
VERILATOR_F   = os.path.join(PROJECT_ROOT, "scripts", "verilator.f")

GOLDEN_OUT = os.path.join(PROJECT_ROOT, "verify", "frontproj_golden.txt")
RTL_OUT    = os.path.join(PROJECT_ROOT, "verify", "frontproj_rtl.txt")

GOLDEN_CFG = TransformerConfig(
    BATCH=BATCH, SEQ_LEN=SEQ_LEN,
    MODEL_DIM=MODEL_DIM, INPUT_DIM=INPUT_DIM, F_DIM=F_DIM,
    NUM_HEADS=NUM_HEADS, HEAD_DIM=HEAD_DIM, TILE_SIZE=TILE_SIZE,
    NUM_ENC_LAYERS=NUM_ENC, NUM_DEN_LAYERS=NUM_DEN, MAX_SEQ_LEN=MAX_SEQ_LEN,
)

SEED = 42

RTL_FILES = [
    "bram_controller.v", "agu.v", "matmul_engine.v", "softmax.v",
    "layernorm.v", "activation.v", "residual_add.v", "host_interface.v",
    "fsm_controller.v", "top_level.v",
]


def hex16(val):
    return f"{val & 0xFFFF:04x}"


def generate_and_write_golden():
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    weights = generate_random_weights(GOLDEN_CFG, seed=SEED)
    W_proj = weights['W_proj']  # [INPUT_DIM x MODEL_DIM], INT8

    rng = random.Random(SEED + 1)
    input_data = [
        [rng.randint(-16, 15) for _ in range(INPUT_DIM)]
        for _ in range(BT)
    ]

    # Golden: input INT8 @ W_proj INT8 -> INT16
    output = tiled_matmul(input_data, W_proj, TILE_SIZE)  # [BT x MODEL_DIM]
    golden_flat = [v for row in output for v in row]

    with open(GOLDEN_OUT, "w") as f:
        f.write("=" * 60 + "\n")
        f.write("FRONTEND PROJECTION — GOLDEN REFERENCE\n")
        f.write("=" * 60 + "\n")
        f.write(f"Operation : output[{BT}x{MODEL_DIM}] = input[{BT}x{INPUT_DIM}] @ W_proj[{INPUT_DIM}x{MODEL_DIM}]\n")
        f.write(f"Input     : INT8  ({DATA_W}-bit signed)\n")
        f.write(f"Weights   : INT8  ({DATA_W}-bit signed)\n")
        f.write(f"Output    : INT16 ({ACC_W}-bit signed, saturating accumulation)\n")
        f.write(f"Hex fmt   : 4-digit zero-padded two's complement (e.g. ffff = -1)\n")
        f.write("\n")

        f.write("-" * 60 + "\n")
        f.write(f"INPUT ACTIVATIONS  [{BT} rows x {INPUT_DIM} cols]\n")
        for i, row in enumerate(input_data):
            vals = "  ".join(hex16(int16(v)) for v in row)
            f.write(f"  row[{i}]: {vals}\n")

        f.write("\n")
        f.write("-" * 60 + "\n")
        f.write(f"WEIGHT MATRIX W_proj  [{INPUT_DIM} rows x {MODEL_DIM} cols]\n")
        for i, row in enumerate(W_proj):
            vals = "  ".join(hex16(int16(v)) for v in row)
            f.write(f"  row[{i}]: {vals}\n")

        f.write("\n")
        f.write("-" * 60 + "\n")
        f.write(f"EXPECTED OUTPUT  [{BT} rows x {MODEL_DIM} cols]  (INT16 hex)\n")
        for i, row in enumerate(output):
            vals = "  ".join(hex16(v) for v in row)
            f.write(f"  row[{i}]: {vals}\n")

        f.write("\n")
        f.write("-" * 60 + "\n")
        f.write("FLAT ELEMENT ORDER (row-major, matches BRAM element index)\n")
        for i, v in enumerate(golden_flat):
            f.write(f"  [{i:3d}]  {hex16(v)}\n")

    print(f"  Golden written : {GOLDEN_OUT}")

    # Encode full weight layout and input activations to BRAM hex files
    flat_weights = flatten_weight_layout(weights, GOLDEN_CFG)
    flat_weights.extend([0] * (WGT_DEPTH * WGT_BANKS - len(flat_weights)))
    write_bank_hex_files(
        os.path.join(TEST_DATA_DIR, "top_wgt_b"),
        encode_to_banks(flat_weights, WGT_BANKS),
        DATA_W,
    )

    # Pack pairs of INT8 values into INT16 slots (2 INT8 per INT16 = hi<<8|lo).
    # The act BRAM has 2 banks x INT16, giving a 32-bit word per read.
    # The matmul engine unpacks that 32-bit word as 4 INT8 values (DATA_W=8),
    # so we need element[0] in bits[7:0], element[1] in bits[15:8], etc.
    flat_int8 = [int8(v) for row in input_data for v in row]
    flat_input = []
    for i in range(0, len(flat_int8), 2):
        lo = flat_int8[i] & 0xFF
        hi = (flat_int8[i + 1] & 0xFF) if i + 1 < len(flat_int8) else 0
        flat_input.append((hi << 8) | lo)
    flat_input.extend([0] * (ACT_DEPTH * ACT_BANKS - len(flat_input)))
    write_bank_hex_files(
        os.path.join(TEST_DATA_DIR, "top_act_b"),
        encode_to_banks(flat_input, ACT_BANKS),
        ACC_W,
    )

    print(f"  BRAM hex files : {TEST_DATA_DIR}/top_{{wgt,act}}_b*.hex")
    return golden_flat


def compile_design():
    tb_path  = os.path.join(TB_DIR, "tb_top.v")
    rtl_paths = [os.path.join(RTL_DIR, f) for f in RTL_FILES]
    cmd = ["verilator", "--binary", "-f", VERILATOR_F, tb_path] + rtl_paths + ["--top-module", "tb_top"]

    result = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  COMPILE FAILED:\n{result.stderr[:5000]}")
        return False
    return True


def run_simulation():
    binary = os.path.join(OBJ_DIR, "Vtb_top")
    if not os.path.exists(binary):
        return False

    print("  Running simulation...")
    result = subprocess.run([binary], cwd=PROJECT_ROOT, capture_output=True, text=True, timeout=120)
    for line in result.stdout.splitlines():
        print(f"    {line}")
    if "TEST PASSED" not in result.stdout:
        print("  FAIL: TEST PASSED not in simulation output")
        if result.stderr:
            print(f"  stderr: {result.stderr[:1000]}")
        return False
    return True


def write_rtl_dump(golden_flat):
    """Dump full contents of both stage_02 buffers to frontproj_rtl.txt."""
    n_elems = BT * MODEL_DIM

    buf_data = {}
    for label in ('a', 'b'):
        path = os.path.join(TEST_DATA_DIR, f"stage_02_{label}.hex")
        if os.path.exists(path):
            buf_data[label] = read_interleaved_hex(path, ACC_W)

    with open(RTL_OUT, "w") as f:
        f.write("=" * 60 + "\n")
        f.write("FRONTEND PROJECTION — RTL BRAM DUMP (stage_02)\n")
        f.write("=" * 60 + "\n")
        f.write(f"Hex fmt   : 4-digit zero-padded two's complement INT16\n")
        f.write(f"Golden n_elems = {n_elems}  ({BT} rows x {MODEL_DIM} cols)\n")
        f.write(f"Expected BRAM offset = {ACT_EMBED_OFFSET} "
                f"(= MAX_SEQ_LEN * INPUT_DIM = {MAX_SEQ_LEN} * {INPUT_DIM})\n")
        f.write("\n")

        if not buf_data:
            f.write("ERROR: no stage_02_*.hex files found\n")
            print("  ERROR: no stage_02 dump files found")
            return

        # Dump every element of both buffers so the correct region is visible
        for label in ('a', 'b'):
            if label not in buf_data:
                f.write(f"buf {label.upper()}: file not found\n\n")
                continue
            raw = buf_data[label]
            f.write("-" * 60 + "\n")
            f.write(f"BUF {label.upper()} — full dump ({len(raw)} elements)\n")
            f.write("-" * 60 + "\n")
            for i, v in enumerate(raw):
                # annotate with golden match if index falls in expected region
                idx_in_region = i - ACT_EMBED_OFFSET * ACT_BANKS
                if 0 <= idx_in_region < n_elems:
                    g      = golden_flat[idx_in_region]
                    status = "OK" if (v & 0xFFFF) == (g & 0xFFFF) else "MISMATCH"
                    g_str  = hex16(g)
                    f.write(f"  [{i:4d}]  {hex16(v)}  <- expected={g_str}  {status}\n")
                else:
                    f.write(f"  [{i:4d}]  {hex16(v)}\n")
            f.write("\n")

    print(f"  RTL dump written: {RTL_OUT}")


def main():
    print("=" * 60)
    print("  Frontend Projection Stage Test")
    print(f"  input[{BT}x{INPUT_DIM}] @ W_proj[{INPUT_DIM}x{MODEL_DIM}] -> output[{BT}x{MODEL_DIM}]")
    print("=" * 60)

    golden_flat = generate_and_write_golden()

    if not compile_design():
        sys.exit(1)

    if not run_simulation():
        sys.exit(1)

    write_rtl_dump(golden_flat)
    print("\nDone.")


if __name__ == "__main__":
    main()
