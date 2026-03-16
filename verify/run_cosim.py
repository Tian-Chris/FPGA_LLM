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
from verify.golden.activation import relu_golden
from verify.golden.residual_add import residual_add_golden

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
    rng = random.Random(seed)
    K, N = TILE_SIZE, TILE_SIZE
    mat_a = [[rng.randint(-30, 30) for _ in range(K)] for _ in range(N)]
    mat_b = [[rng.randint(-30, 30) for _ in range(N)] for _ in range(K)]
    expected = matmul_golden(mat_a, mat_b, TILE_SIZE)
    expected_flat = [expected[i][j] for i in range(N) for j in range(N)]
    
    flat_a = [mat_a[i][k] for i in range(N) for k in range(K)]
    flat_b = [mat_b[k][j] for k in range(K) for j in range(N)]
    write_hex_file(os.path.join(TEST_DATA_DIR, "matmul_a.hex"), flat_a, 16)
    write_hex_file(os.path.join(TEST_DATA_DIR, "matmul_b.hex"), flat_b, 16)

    verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_matmul.v"), [
        os.path.join(RTL_DIR, "matmul_engine.v"),
        os.path.join(RTL_DIR, "mac_unit.v"),
    ], "tb_cosim_matmul")
    verilator_run("tb_cosim_matmul")
    actual = read_hex_file(os.path.join(TEST_DATA_DIR, "matmul_out.hex"), 16)

    print_results_table("matmul", flat_a, flat_b, expected_flat, actual)
    return

def run_softmax(seed):
    rng = random.Random(seed)
    inputs = [rng.randint(-2000, 2000) for _ in range(8)]
    expected = softmax_golden(inputs)
    write_hex_file(os.path.join(TEST_DATA_DIR, "softmax_in.hex"), inputs, 16)

    verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_softmax.v"), [os.path.join(RTL_DIR, "softmax.v")], "tb_cosim_softmax")
    verilator_run("tb_cosim_softmax")
    actual = [a & 0xFFFF for a in read_hex_file(os.path.join(TEST_DATA_DIR, "softmax_out.hex"), 16)]

    print_results_table("softmax", inputs, None, expected, actual)
    return

def run_layernorm(seed):
    rng = random.Random(seed)
    dim = 16
    inputs = [rng.randint(-500, 500) for _ in range(dim)]
    gamma = [rng.randint(50, 127) for _ in range(dim)]
    beta = [rng.randint(-50, 50) for _ in range(dim)]
    expected = [e & 0xFFFF for e in layernorm_golden(inputs, gamma, beta, dim)]
    
    write_hex_file(os.path.join(TEST_DATA_DIR, "layernorm_in.hex"), inputs, 16)
    write_hex_file(os.path.join(TEST_DATA_DIR, "layernorm_gamma.hex"), gamma, 8)
    write_hex_file(os.path.join(TEST_DATA_DIR, "layernorm_beta.hex"), beta, 8)

    verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_layernorm.v"), [os.path.join(RTL_DIR, "layernorm.v")], "tb_cosim_layernorm")
    verilator_run("tb_cosim_layernorm")
    actual = [a & 0xFFFF for a in read_hex_file(os.path.join(TEST_DATA_DIR, "layernorm_out.hex"), 16)]

    print_results_table("layernorm", inputs, gamma, expected, actual)
    return

def run_activation(seed):
    rng = random.Random(seed)
    inputs = [rng.randint(-1000, 1000) for _ in range(16)]
    expected = [relu_golden(x) for x in inputs]
    write_hex_file(os.path.join(TEST_DATA_DIR, "activation_in.hex"), inputs, 16)

    verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_activation.v"), [os.path.join(RTL_DIR, "activation.v")], "tb_cosim_activation")
    verilator_run("tb_cosim_activation")
    actual = read_hex_file(os.path.join(TEST_DATA_DIR, "activation_out.hex"), 16)

    print_results_table("activation", inputs, None, expected, actual)
    return

def run_residual_add(seed):
    rng = random.Random(seed)
    res = [rng.randint(-1000, 1000) for _ in range(16)]
    sub = [rng.randint(-1000, 1000) for _ in range(16)]
    expected = residual_add_golden(res, sub)
    
    write_hex_file(os.path.join(TEST_DATA_DIR, "residual_res.hex"), res, 16)
    write_hex_file(os.path.join(TEST_DATA_DIR, "residual_sub.hex"), sub, 16)

    verilator_compile(os.path.join(TB_COSIM_DIR, "tb_cosim_residual_add.v"), [os.path.join(RTL_DIR, "residual_add.v")], "tb_cosim_residual_add")
    verilator_run("tb_cosim_residual_add")
    actual = read_hex_file(os.path.join(TEST_DATA_DIR, "residual_out.hex"), 16)

    print_results_table("residual_add", res, sub, expected, actual)
    return

MODULES = {
    "matmul":       run_matmul,
    "softmax":      run_softmax,
    "layernorm":    run_layernorm,
    "activation":   run_activation,
    "residual_add": run_residual_add,
}

def main():
    args = sys.argv[1:]
    targets = [a for a in args if a in MODULES] if args else list(MODULES.keys())
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    for module_name in targets:
        runner = MODULES[module_name]
        for i in range(NUM_TESTS):
            seed = (1000 * hash(module_name) + i) & 0x7FFFFFFF
            runner(seed)

if __name__ == "__main__":
    main()