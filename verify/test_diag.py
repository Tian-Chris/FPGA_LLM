#!/usr/bin/env python3
"""Diagnostic test mode verification.

Builds and runs the diagnostic testbench for each test_mode, then verifies
the output HBM contents against expected patterns.

Test modes:
  12 = Register readback (all config values echoed to output via debug_writer)
   1 = HBM echo (known pattern written via debug_writer)
   5 = URAM write + flush (nm_adapter → URAM row 0 → HBM flush)
   6 = URAM latency probe (measures chk_uram_rd cycle count)
   7 = Multi-row URAM (rows 0/256/512/768 via checkpoint reads)
"""

import os
import sys
import subprocess
import struct

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(PROJECT_ROOT)

# Production parameters (must match defines.vh SIM_1K)
MODEL_DIM = 1024
F_DIM = 4096
NUM_HEADS = 16
MAX_SEQ_LEN = 128
NUM_ENC_LAYERS = 1  # SIM_1K default
BUS_ELEMS = 16

# Memory layout (must match tb_top_diag.v)
WE = 16
WEIGHT_BASE = 0
ACT_BASE = 787264
KV_BASE = ACT_BASE + 6 * 128 * 1024 // 16
OUTPUT_BASE = KV_BASE + 2 * 128 * 1024 // 16

BATCH = 1
SEQ_LEN = 32

# =========================================================================
# Hex parsing
# =========================================================================
def read_hex_dump(path):
    """Read a hex dump file, return list of 256-bit integers."""
    words = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                words.append(int(line, 16))
    return words

def extract_fp16_from_word(word256, elem_idx):
    """Extract a 16-bit element from a 256-bit word (little-endian packing)."""
    return (word256 >> (elem_idx * 16)) & 0xFFFF

def word_to_fp16_list(word256):
    """Convert 256-bit word to list of 16 FP16 values."""
    return [extract_fp16_from_word(word256, i) for i in range(16)]


# =========================================================================
# Build + run
# =========================================================================
def build_and_run(test_mode, hbm_lat=2, uram_lat=1):
    """Build Verilator sim for given test_mode, run it, return output hex."""

    rtl_dir = "rtl"
    tb_file = "tb/tb_top_diag.v"

    # RTL file list (same as Makefile RTL_ALL)
    rtl_files = [
        f"{rtl_dir}/bram_controller.v", f"{rtl_dir}/mac_unit.v",
        f"{rtl_dir}/fp16_mult.v", f"{rtl_dir}/fp32_add.v",
        f"{rtl_dir}/fp32_to_fp16.v", f"{rtl_dir}/fp16_add.v",
        f"{rtl_dir}/fp16_compare.v", f"{rtl_dir}/fp_mac_unit.v",
        f"{rtl_dir}/agu.v", f"{rtl_dir}/matmul_engine.v",
        f"{rtl_dir}/mem_arbiter.v", f"{rtl_dir}/tiling_engine.v",
        f"{rtl_dir}/softmax.v", f"{rtl_dir}/layernorm.v",
        f"{rtl_dir}/activation.v", f"{rtl_dir}/residual_add.v",
        f"{rtl_dir}/quant_layer.v", f"{rtl_dir}/host_interface.v",
        f"{rtl_dir}/positional_embedding.v", f"{rtl_dir}/fsm_controller.v",
        f"{rtl_dir}/sim_hbm.v", f"{rtl_dir}/debug_writer.v",
        f"{rtl_dir}/uram_accum_buf.v", f"{rtl_dir}/tile_loader.v",
        f"{rtl_dir}/uram_flush.v", f"{rtl_dir}/act_dma.v",
        f"{rtl_dir}/uram_nm_adapter.v", f"{rtl_dir}/uram_prefetch_buf.v",
        f"{rtl_dir}/hbm_prefetch.v", f"{rtl_dir}/top_level.v",
    ]

    # Ensure test_data dir exists
    os.makedirs("verify/test_data", exist_ok=True)

    # Build
    build_cmd = [
        "verilator", "--binary", "-f", "scripts/verilator_diag.f",
        f"-GTEST_MODE={test_mode}",
        f"-GHBM_RD_LATENCY={hbm_lat}",
        f"-GURAM_RD_LATENCY={uram_lat}",
        tb_file,
    ] + rtl_files + [
        "--top-module", "tb_top_diag",
        "-o", f"Vtb_top_diag_{test_mode}",
    ]

    print(f"\n{'='*60}")
    print(f"Building test_mode={test_mode} (HBM_LAT={hbm_lat}, URAM_LAT={uram_lat})...")
    result = subprocess.run(build_cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"BUILD FAILED for test_mode={test_mode}")
        print(result.stderr[-2000:] if len(result.stderr) > 2000 else result.stderr)
        return None

    # Run
    print(f"Running test_mode={test_mode}...")
    sim_cmd = [f"./obj_dir/Vtb_top_diag_{test_mode}"]
    result = subprocess.run(sim_cmd, capture_output=True, text=True, timeout=120)
    print(result.stdout[-3000:] if len(result.stdout) > 3000 else result.stdout)
    if result.returncode != 0:
        print(f"SIM FAILED for test_mode={test_mode}")
        if result.stderr:
            print(result.stderr[-1000:])
        return None

    # Read output
    try:
        output = read_hex_dump("verify/test_data/diag_output.hex")
    except FileNotFoundError:
        print(f"ERROR: diag_output.hex not found for test_mode={test_mode}")
        return None

    return output


# =========================================================================
# Verification functions
# =========================================================================

def verify_test_12(output):
    """Test 12: Register readback. First 4 words contain packed register values."""
    if not output or len(output) < 4:
        print("FAIL: test_mode=12 — insufficient output data")
        return False

    # Word 0 layout (from fsm_controller.v S_TEST_REG_CHK):
    #   [15:0]   = batch_r
    #   [31:16]  = seq_r
    #   [47:32]  = num_layers_r
    #   [51:48]  = test_mode_r (4 bits)
    #   [63:52]  = 0
    #   [79:64]  = max_steps_r
    #   [95:80]  = cache_len_r
    #   [96]     = decode_r
    #   [255:97] = 0
    w0 = output[0]
    batch_r     = (w0 >>   0) & 0xFFFF
    seq_r       = (w0 >>  16) & 0xFFFF
    num_layers  = (w0 >>  32) & 0xFFFF
    test_mode_r = (w0 >>  48) & 0xF
    max_steps_r = (w0 >>  64) & 0xFFFF
    cache_len_r = (w0 >>  80) & 0xFFFF
    decode_r    = (w0 >>  96) & 0x1

    ok = True
    checks = [
        ("batch_r",     batch_r,     BATCH),
        ("seq_r",       seq_r,       SEQ_LEN),
        ("num_layers",  num_layers,  NUM_ENC_LAYERS),
        ("test_mode_r", test_mode_r, 12),
        ("max_steps_r", max_steps_r, 0),
        ("decode_r",    decode_r,    0),
        ("cache_len_r", cache_len_r, 0),
    ]

    for name, got, exp in checks:
        if got != exp:
            print(f"  MISMATCH {name}: got {got}, expected {exp}")
            ok = False
        else:
            print(f"  OK {name} = {got}")

    # Word 1: [27:0]=weight_base, [59:32]=act_base (4-bit gaps at [31:28],[63:60])
    w1 = output[1]
    wb = w1 & 0x0FFFFFFF
    ab = (w1 >> 32) & 0x0FFFFFFF
    checks_w1 = [
        ("weight_base", wb, WEIGHT_BASE),
        ("act_base",    ab, ACT_BASE),
    ]
    for name, got, exp in checks_w1:
        if got != exp:
            print(f"  MISMATCH {name}: got {got}, expected {exp}")
            ok = False
        else:
            print(f"  OK {name} = {got}")

    # Word 2: [27:0]=output_base, [59:32]=kv_base
    w2 = output[2]
    ob = w2 & 0x0FFFFFFF
    kb = (w2 >> 32) & 0x0FFFFFFF
    checks_w2 = [
        ("output_base", ob, OUTPUT_BASE),
        ("kv_base",     kb, KV_BASE),
    ]
    for name, got, exp in checks_w2:
        if got != exp:
            print(f"  MISMATCH {name}: got {got}, expected {exp}")
            ok = False
        else:
            print(f"  OK {name} = {got}")

    # Word 3: [27:0]=debug_base
    w3 = output[3]
    db = w3 & 0x0FFFFFFF
    TB_HBM_DEPTH = 1048576
    DEBUG_BASE_EXP = TB_HBM_DEPTH - 512
    if db != DEBUG_BASE_EXP:
        print(f"  MISMATCH debug_base: got {db}, expected {DEBUG_BASE_EXP}")
        ok = False
    else:
        print(f"  OK debug_base = {db}")

    return ok


def verify_test_1(output):
    """Test 1: HBM echo. 8 words with pattern {idx, CAFE, idx, CAFE, ...}."""
    if not output or len(output) < 8:
        print("FAIL: test_mode=1 — insufficient output data")
        return False

    ok = True
    for i in range(8):
        expected = 0
        for e in range(8):  # 8 × 32-bit = 256-bit
            # Each 32-bit chunk: {idx[15:0], 0xCAFE}
            chunk = ((i & 0xFFFF) << 16) | 0xCAFE
            expected |= (chunk << (e * 32))

        if output[i] != expected:
            # More readable: show as FP16 elements
            got_elems = word_to_fp16_list(output[i])
            exp_elems = word_to_fp16_list(expected)
            print(f"  MISMATCH word[{i}]:")
            print(f"    got: {[hex(x) for x in got_elems]}")
            print(f"    exp: {[hex(x) for x in exp_elems]}")
            ok = False
        else:
            print(f"  OK word[{i}] = pattern(idx={i})")

    return ok


def verify_test_5(output):
    """Test 5: URAM write+flush. Row 0, 4 bus words = 64 FP16 values.
    Pattern: 0x3C00 + index (for index 0..63).
    Note: URAM flush writes 256-bit words, little-endian element packing.
    """
    if not output or len(output) < 4:
        print("FAIL: test_mode=5 — insufficient output data")
        return False

    ok = True
    for word_idx in range(4):
        elems = word_to_fp16_list(output[word_idx])
        for e in range(16):
            global_idx = word_idx * 16 + e
            expected = (0x3C00 + global_idx) & 0xFFFF
            if elems[e] != expected:
                print(f"  MISMATCH elem[{global_idx}]: got 0x{elems[e]:04X}, expected 0x{expected:04X}")
                ok = False
        if ok:
            print(f"  OK word[{word_idx}] = 0x3C{word_idx*16:02X}..0x3C{word_idx*16+15:02X}")

    return ok


def verify_test_6(output):
    """Test 6: URAM latency probe. Single output word with:
      [15:0]   = measured latency (cycles)
      [31:16]  = expected latency (should be URAM_RD_LATENCY)
      [47:32]  = 0xBEEF marker
      [255:48] = URAM read data
    """
    if not output or len(output) < 1:
        print("FAIL: test_mode=6 — no output")
        return False

    w = output[0]
    measured = w & 0xFFFF
    expected = (w >> 16) & 0xFFFF
    marker   = (w >> 32) & 0xFFFF

    # The "expected" field contains the raw URAM_RD_LATENCY parameter (hardcoded 1 in RTL).
    # Due to NBA scheduling, the measurement includes +1 cycle overhead:
    #   Cycle N:   FSM sets chk_uram_rd_en via NBA (takes effect cycle N+1), counter=1
    #   Cycle N+1: URAM sees enable. Counter increments in phase 1.
    #   Cycle N+1+RD_LATENCY: valid arrives.
    # So measured = RD_LATENCY + 1 (the +1 is the NBA pipeline delay).
    expected_measured = expected + 1

    print(f"  Measured latency: {measured} cycles")
    print(f"  URAM_RD_LATENCY param: {expected}")
    print(f"  Expected measurement: {expected_measured} (param + 1 for NBA delay)")
    print(f"  Marker: 0x{marker:04X}")

    ok = True
    if marker != 0xBEEF:
        print(f"  MISMATCH marker: got 0x{marker:04X}, expected 0xBEEF")
        ok = False

    if measured != expected_measured:
        print(f"  LATENCY MISMATCH! measured={measured}, expected={expected_measured}")
        if measured > expected_measured:
            extra = measured - expected_measured
            print(f"  >>> URAM read takes {extra} MORE cycles than RTL expects!")
            print(f"  >>> This likely means URAM cascade adds {extra} extra pipeline stages")
        ok = False
    else:
        print(f"  OK latency matches ({measured} cycles = RD_LATENCY({expected}) + 1)")

    # Also check the read data — should be pattern from test_mode=6 write phase
    # Wrote 16 values: 0x3C00..0x3C0F to URAM row 0
    data_bits = (w >> 48) & ((1 << 208) - 1)  # 208 bits = 13 FP16 values
    for i in range(13):
        val = (data_bits >> (i * 16)) & 0xFFFF
        expected_val = (0x3C00 + i) & 0xFFFF
        if val != expected_val:
            print(f"  MISMATCH data[{i}]: got 0x{val:04X}, expected 0x{expected_val:04X}")
            ok = False

    if ok:
        print(f"  OK read data matches written pattern")

    return ok


def verify_test_7(output):
    """Test 7: Multi-row URAM. 4 words, one per row (0, 256, 512, 768).
    Each word is checkpoint-read data from col 0 of that row.
    Row R pattern: base + index, where base = 0xA000/0xB000/0xC000/0xD000.
    """
    if not output or len(output) < 4:
        print("FAIL: test_mode=7 — insufficient output data")
        return False

    bases = [0xA000, 0xB000, 0xC000, 0xD000]
    rows  = [0, 256, 512, 768]
    ok = True

    for row_idx in range(4):
        elems = word_to_fp16_list(output[row_idx])
        base = bases[row_idx]
        row = rows[row_idx]
        row_ok = True
        for e in range(16):
            expected = (base + e) & 0xFFFF
            if elems[e] != expected:
                print(f"  MISMATCH row {row} elem[{e}]: got 0x{elems[e]:04X}, expected 0x{expected:04X}")
                row_ok = False
                ok = False
        if row_ok:
            print(f"  OK row {row}: base=0x{base:04X}, 16 elements correct")

    return ok


# =========================================================================
# Main
# =========================================================================
def main():
    # Test order: simplest first
    tests = [
        (12, "Register readback",    verify_test_12),
        (1,  "HBM echo pattern",     verify_test_1),
        (5,  "URAM write + flush",   verify_test_5),
        (6,  "URAM latency probe",   verify_test_6),
        (7,  "Multi-row URAM",       verify_test_7),
    ]

    # Allow running a single test via command line
    if len(sys.argv) > 1:
        requested = int(sys.argv[1])
        tests = [(tm, desc, fn) for tm, desc, fn in tests if tm == requested]
        if not tests:
            print(f"Unknown test_mode={requested}")
            sys.exit(1)

    results = {}
    for test_mode, desc, verify_fn in tests:
        output = build_and_run(test_mode)
        if output is None:
            results[test_mode] = "BUILD/SIM FAILED"
            continue

        print(f"\nVerifying test_mode={test_mode} ({desc}):")
        passed = verify_fn(output)
        results[test_mode] = "PASS" if passed else "FAIL"

    # Summary
    print(f"\n{'='*60}")
    print("DIAGNOSTIC TEST SUMMARY")
    print(f"{'='*60}")
    all_pass = True
    for test_mode, desc, _ in tests:
        status = results.get(test_mode, "NOT RUN")
        marker = "✓" if status == "PASS" else "✗"
        print(f"  {marker} test_mode={test_mode:2d} ({desc}): {status}")
        if status != "PASS":
            all_pass = False

    print(f"{'='*60}")
    if all_pass:
        print("ALL DIAGNOSTIC TESTS PASSED")
    else:
        print("SOME TESTS FAILED")
        sys.exit(1)


if __name__ == "__main__":
    main()
