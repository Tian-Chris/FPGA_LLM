#!/usr/bin/env python3
import os
import sys
import random
import subprocess

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)
RTL_DIR = os.path.join(PROJECT_ROOT, "rtl")
TB_COSIM_DIR = os.path.join(PROJECT_ROOT, "verify", "tb_cosim")
TEST_DATA_DIR = os.path.join(PROJECT_ROOT, "verify", "test_data")
VERILATOR_F = os.path.join(PROJECT_ROOT, "scripts", "verilator.f")
OBJ_DIR = os.path.join(PROJECT_ROOT, "obj_dir")

TILE_SIZE = 32
NUM_TESTS = 1

from verify.hex_utils import write_hex_file, read_hex_file
from verify.golden.matmul_engine import matmul_golden
from verify.golden.softmax import softmax_golden
from verify.golden.layernorm import layernorm_golden
from verify.golden.activation import gelu_golden
from verify.golden.residual_add import residual_add_golden
from verify.golden.fp_primitives import (
    fp16_mult_golden, fp32_add_golden, fp32_to_fp16_golden,
    fp16_add_golden, fp16_max_golden, fp16_min_golden,
    generate_fp16_test_vectors, generate_fp32_test_vectors,
    fp16_to_bits, bits_to_fp16, fp32_to_bits, bits_to_fp32,
)

def print_results_table(name, inputs_a, inputs_b, expected, actual, truncate=8):
    print(f"\n--- {name.upper()} ---")
    
    if inputs_b is not None:
        print(f"{'Idx':<4} | {'In A':<8} | {'In B':<8} | {'Expected':<10} | {'Actual':<10} | {'Status'}")
        print("-" * 65)
    else:
        print(f"{'Idx':<4} | {'Input':<8} | {'Expected':<10} | {'Actual':<10} | {'Status'}")
        print("-" * 55)
    
    for i in range(min(len(actual), truncate)):
        match = "OK" if expected[i] == actual[i] else "FAIL"
        if inputs_b is not None:
            print(f"{i:<4} | {str(inputs_a[i]):<8} | {str(inputs_b[i]):<8} | "
                  f"{expected[i]:<10} | {actual[i]:<10} | {match}")
        else:
            print(f"{i:<4} | {str(inputs_a[i]):<8} | {expected[i]:<10} | "
                  f"{actual[i]:<10} | {match}")

def verilator_compile(tb_path, rtl_paths, top_module):
    cmd = ["verilator", "--binary", "-f", VERILATOR_F] + [tb_path] + rtl_paths + ["--top-module", top_module]
    result = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  Verilator compile failed:\n{result.stderr}")
        return False
    return True

def verilator_run(top_module):
    binary = os.path.join(OBJ_DIR, f"V{top_module}")
    result = subprocess.run([binary], cwd=PROJECT_ROOT, capture_output=True, text=True)
    return result.returncode == 0

def run_matmul(seed):
    import numpy as np
    rng = np.random.RandomState(seed & 0xFFFFFFFF)
    K, N = TILE_SIZE, TILE_SIZE

    # Generate random FP16 values (small range for stable accumulation)
    a_fp32 = rng.uniform(-1.0, 1.0, (N, K)).astype(np.float32)
    b_fp32 = rng.uniform(-1.0, 1.0, (K, N)).astype(np.float32)

    # Convert to FP16 bit patterns
    a_fp16 = a_fp32.astype(np.float16)
    b_fp16 = b_fp32.astype(np.float16)
    mat_a = [[int(a_fp16[i, k].view(np.uint16)) for k in range(K)] for i in range(N)]
    mat_b = [[int(b_fp16[k, j].view(np.uint16)) for j in range(N)] for k in range(K)]

    expected = matmul_golden(mat_a, mat_b, TILE_SIZE)
    expected_flat = [expected[i][j] for i in range(N) for j in range(N)]

    flat_a = [mat_a[i][k] for i in range(N) for k in range(K)]
    flat_b = [mat_b[k][j] for k in range(K) for j in range(N)]
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "matmul_a.hex"), flat_a, 16)
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "matmul_b.hex"), flat_b, 16)

    if not verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_matmul.v"), [
        os.path.join(RTL_DIR, "matmul_engine.v"),
        os.path.join(RTL_DIR, "fp_mac_unit.v"),
    ], "tb_cosim_matmul"):
        return
    verilator_run("tb_cosim_matmul")
    actual = _read_hex_unsigned(os.path.join(TEST_DATA_DIR, "matmul_out.hex"), 16)

    print_fp_results_table("matmul (fp16)", flat_a, None, expected_flat, actual)
    return

def run_softmax(seed):
    import numpy as np
    rng = np.random.RandomState(seed & 0xFFFFFFFF)
    seq_len = 8

    # Generate random FP16 attention scores
    scores_fp16 = rng.uniform(-3.0, 3.0, seq_len).astype(np.float16)
    input_bits = [int(v.view(np.uint16)) for v in scores_fp16]

    # Scale factor = 1.0 (FP16 0x3C00) — matches testbench default
    scale_bits = 0x3C00

    expected = softmax_golden(input_bits, scale_bits)
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "softmax_in.hex"), input_bits, 16)

    if not verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_softmax.v"), [os.path.join(RTL_DIR, "softmax.v")], "tb_cosim_softmax"):
        return
    verilator_run("tb_cosim_softmax")
    actual = _read_hex_unsigned(os.path.join(TEST_DATA_DIR, "softmax_out.hex"), 16)

    print_fp_results_table("softmax (fp16)", input_bits, None, expected, actual)
    return

def run_layernorm(seed):
    import numpy as np
    rng = np.random.RandomState(seed & 0xFFFFFFFF)
    dim = 16

    # Generate random FP16 values as bit patterns
    inputs_fp16 = rng.uniform(-5.0, 5.0, dim).astype(np.float16)
    gamma_fp16 = rng.uniform(0.5, 2.0, dim).astype(np.float16)
    beta_fp16 = rng.uniform(-1.0, 1.0, dim).astype(np.float16)

    input_bits = [int(v.view(np.uint16)) for v in inputs_fp16]
    gamma_bits = [int(v.view(np.uint16)) for v in gamma_fp16]
    beta_bits = [int(v.view(np.uint16)) for v in beta_fp16]

    expected = layernorm_golden(input_bits, gamma_bits, beta_bits, dim)

    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "layernorm_in.hex"), input_bits, 16)
    # Interleaved params: gamma[0], beta[0], gamma[1], beta[1], ...
    interleaved = []
    for g, b in zip(gamma_bits, beta_bits):
        interleaved.append(g)
        interleaved.append(b)
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "layernorm_params.hex"), interleaved, 16)

    if not verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_layernorm.v"), [os.path.join(RTL_DIR, "layernorm.v")], "tb_cosim_layernorm"):
        return
    verilator_run("tb_cosim_layernorm")
    actual = _read_hex_unsigned(os.path.join(TEST_DATA_DIR, "layernorm_out.hex"), 16)

    print_fp_results_table("layernorm (fp16)", input_bits, None, expected, actual)
    return

def run_activation(seed):
    import numpy as np
    rng = np.random.RandomState(seed & 0xFFFFFFFF)

    # Generate random FP16 values in [-5, 5] range
    inputs_fp16 = rng.uniform(-5.0, 5.0, 16).astype(np.float16)
    input_bits = [int(v.view(np.uint16)) for v in inputs_fp16]

    expected = gelu_golden(input_bits)
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "activation_in.hex"), input_bits, 16)

    if not verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_activation.v"), [os.path.join(RTL_DIR, "activation.v")], "tb_cosim_activation"):
        return
    verilator_run("tb_cosim_activation")
    actual = _read_hex_unsigned(os.path.join(TEST_DATA_DIR, "activation_out.hex"), 16)

    print_fp_results_table("activation (gelu)", input_bits, None, expected, actual)
    return

def run_residual_add(seed):
    import numpy as np
    rng = np.random.RandomState(seed & 0xFFFFFFFF)

    # Generate random FP16 values
    res_fp16 = rng.uniform(-3.0, 3.0, 16).astype(np.float16)
    sub_fp16 = rng.uniform(-3.0, 3.0, 16).astype(np.float16)
    res_bits = [int(v.view(np.uint16)) for v in res_fp16]
    sub_bits = [int(v.view(np.uint16)) for v in sub_fp16]

    expected = residual_add_golden(res_bits, sub_bits)

    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "residual_res.hex"), res_bits, 16)
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "residual_sub.hex"), sub_bits, 16)

    if not verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_residual_add.v"), [os.path.join(RTL_DIR, "residual_add.v")], "tb_cosim_residual_add"):
        return
    verilator_run("tb_cosim_residual_add")
    actual = _read_hex_unsigned(os.path.join(TEST_DATA_DIR, "residual_out.hex"), 16)

    print_fp_results_table("residual_add (fp16)", res_bits, sub_bits, expected, actual)
    return

def print_fp_results_table(name, a_vals, b_vals, expected, actual, hex_width=4, truncate=16):
    """Print results table for FP cosim (bit pattern comparison)."""
    print(f"\n--- {name.upper()} ---")
    n_total = len(expected)
    n_pass = sum(1 for e, a in zip(expected, actual) if e == a)
    print(f"  {n_pass}/{n_total} passed")

    fmt = f"0{hex_width}x"
    if b_vals is not None:
        print(f"{'Idx':<4} | {'In A':<{hex_width+4}} | {'In B':<{hex_width+4}} | "
              f"{'Expected':<{hex_width+4}} | {'Actual':<{hex_width+4}} | {'Status'}")
        print("-" * (30 + hex_width * 4))
    else:
        print(f"{'Idx':<4} | {'Input':<{hex_width+4}} | "
              f"{'Expected':<{hex_width+4}} | {'Actual':<{hex_width+4}} | {'Status'}")
        print("-" * (22 + hex_width * 3))

    shown = 0
    for i in range(n_total):
        match = "OK" if expected[i] == actual[i] else "FAIL"
        if match == "FAIL" or shown < 8:
            if b_vals is not None:
                print(f"{i:<4} | {format(a_vals[i], fmt):<{hex_width+4}} | "
                      f"{format(b_vals[i], fmt):<{hex_width+4}} | "
                      f"{format(expected[i], fmt):<{hex_width+4}} | "
                      f"{format(actual[i], fmt):<{hex_width+4}} | {match}")
            else:
                print(f"{i:<4} | {format(a_vals[i], fmt):<{hex_width+4}} | "
                      f"{format(expected[i], fmt):<{hex_width+4}} | "
                      f"{format(actual[i], fmt):<{hex_width+4}} | {match}")
            shown += 1
            if shown >= truncate:
                break


NUM_FP_TESTS = 256

def _write_hex_unsigned(path, values, width):
    """Write unsigned bit patterns as hex."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fmt = f"0{width // 4}x"
    with open(path, "w") as f:
        for v in values:
            f.write(format(v & ((1 << width) - 1), fmt) + "\n")

def _read_hex_unsigned(path, width):
    """Read hex values as unsigned bit patterns."""
    values = []
    mask = (1 << width) - 1
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("//"):
                values.append(int(line, 16) & mask)
    return values


def run_fp16_mult(seed):
    import numpy as np
    test_a = generate_fp16_test_vectors(seed, n_random=NUM_FP_TESTS - 18)
    test_b = generate_fp16_test_vectors(seed + 1, n_random=NUM_FP_TESTS - 18)
    # Ensure same length
    n = min(len(test_a), len(test_b), NUM_FP_TESTS)
    test_a, test_b = test_a[:n], test_b[:n]

    expected = [fp16_mult_golden(a, b) for a, b in zip(test_a, test_b)]
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp16_mult_a.hex"), test_a, 16)
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp16_mult_b.hex"), test_b, 16)

    if not verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_fp16_mult.v"),
                             [os.path.join(RTL_DIR, "fp16_mult.v")],
                             "tb_cosim_fp16_mult"):
        return
    verilator_run("tb_cosim_fp16_mult")
    actual = _read_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp16_mult_out.hex"), 32)

    print_fp_results_table("fp16_mult", test_a, test_b, expected, actual, hex_width=8)


def run_fp32_add(seed):
    import numpy as np
    test_a = generate_fp32_test_vectors(seed, n_random=NUM_FP_TESTS - 9)
    test_b = generate_fp32_test_vectors(seed + 1, n_random=NUM_FP_TESTS - 9)
    n = min(len(test_a), len(test_b), NUM_FP_TESTS)
    test_a, test_b = test_a[:n], test_b[:n]

    expected = [fp32_add_golden(a, b) for a, b in zip(test_a, test_b)]
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp32_add_a.hex"), test_a, 32)
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp32_add_b.hex"), test_b, 32)

    if not verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_fp32_add.v"),
                             [os.path.join(RTL_DIR, "fp32_add.v")],
                             "tb_cosim_fp32_add"):
        return
    verilator_run("tb_cosim_fp32_add")
    actual = _read_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp32_add_out.hex"), 32)

    print_fp_results_table("fp32_add", test_a, test_b, expected, actual, hex_width=8)


def run_fp32_to_fp16(seed):
    import numpy as np
    test_in = generate_fp32_test_vectors(seed, n_random=NUM_FP_TESTS - 9)
    test_in = test_in[:NUM_FP_TESTS]

    expected = [fp32_to_fp16_golden(v) for v in test_in]
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp32_to_fp16_in.hex"), test_in, 32)

    if not verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_fp32_to_fp16.v"),
                             [os.path.join(RTL_DIR, "fp32_to_fp16.v")],
                             "tb_cosim_fp32_to_fp16"):
        return
    verilator_run("tb_cosim_fp32_to_fp16")
    actual = _read_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp32_to_fp16_out.hex"), 16)

    print_fp_results_table("fp32_to_fp16", test_in, None, expected, actual, hex_width=4)


def run_fp16_add(seed):
    import numpy as np
    test_a = generate_fp16_test_vectors(seed, n_random=NUM_FP_TESTS - 18)
    test_b = generate_fp16_test_vectors(seed + 1, n_random=NUM_FP_TESTS - 18)
    n = min(len(test_a), len(test_b), NUM_FP_TESTS)
    test_a, test_b = test_a[:n], test_b[:n]

    expected = [fp16_add_golden(a, b) for a, b in zip(test_a, test_b)]
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp16_add_a.hex"), test_a, 16)
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp16_add_b.hex"), test_b, 16)

    if not verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_fp16_add.v"),
                             [os.path.join(RTL_DIR, "fp16_add.v")],
                             "tb_cosim_fp16_add"):
        return
    verilator_run("tb_cosim_fp16_add")
    actual = _read_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp16_add_out.hex"), 16)

    print_fp_results_table("fp16_add", test_a, test_b, expected, actual)


def run_fp16_compare(seed):
    import numpy as np
    test_a = generate_fp16_test_vectors(seed, n_random=NUM_FP_TESTS - 18)
    test_b = generate_fp16_test_vectors(seed + 1, n_random=NUM_FP_TESTS - 18)
    n = min(len(test_a), len(test_b), NUM_FP_TESTS)
    test_a, test_b = test_a[:n], test_b[:n]

    expected_max = [fp16_max_golden(a, b) for a, b in zip(test_a, test_b)]
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp16_cmp_a.hex"), test_a, 16)
    _write_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp16_cmp_b.hex"), test_b, 16)

    if not verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_fp16_compare.v"),
                             [os.path.join(RTL_DIR, "fp16_compare.v")],
                             "tb_cosim_fp16_compare"):
        return
    verilator_run("tb_cosim_fp16_compare")
    actual_max = _read_hex_unsigned(os.path.join(TEST_DATA_DIR, "fp16_cmp_max_out.hex"), 16)

    print_fp_results_table("fp16_compare (max)", test_a, test_b, expected_max, actual_max)


MODULES = {
    "matmul":       run_matmul,
    "softmax":      run_softmax,
    "layernorm":    run_layernorm,
    "activation":   run_activation,
    "residual_add": run_residual_add,
    "fp16_mult":    run_fp16_mult,
    "fp32_add":     run_fp32_add,
    "fp32_to_fp16": run_fp32_to_fp16,
    "fp16_add":     run_fp16_add,
    "fp16_compare": run_fp16_compare,
}

FP_MODULES = ["fp16_mult", "fp32_add", "fp32_to_fp16", "fp16_add", "fp16_compare"]

def main():
    args = sys.argv[1:]
    if args and args[0] == "fp-primitives":
        targets = FP_MODULES
    elif args:
        targets = [a for a in args if a in MODULES]
    else:
        targets = list(MODULES.keys())
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    for module_name in targets:
        runner = MODULES[module_name]
        for i in range(NUM_TESTS):
            seed = (1000 * hash(module_name) + i) & 0x7FFFFFFF
            runner(seed)

if __name__ == "__main__":
    main()