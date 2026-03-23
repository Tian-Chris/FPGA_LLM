"""Golden reference models for FP16/FP32 primitives.

All functions operate on bit patterns (unsigned integers) to match RTL behavior.
Subnormals are flushed to zero to match RTL.
"""

import numpy as np
import struct


def fp16_to_bits(val):
    """Convert a Python float to FP16 bit pattern (uint16)."""
    return int(np.float16(val).view(np.uint16))


def bits_to_fp16(bits):
    """Convert FP16 bit pattern (uint16) to Python float."""
    return float(np.uint16(bits).view(np.float16))


def fp32_to_bits(val):
    """Convert a Python float to FP32 bit pattern (uint32)."""
    return int(np.float32(val).view(np.uint32))


def bits_to_fp32(bits):
    """Convert FP32 bit pattern (uint32) to Python float."""
    return float(np.uint32(bits).view(np.float32))


def flush_fp16_subnormal(bits):
    """Flush FP16 subnormal to zero (preserve sign)."""
    exp = (bits >> 10) & 0x1F
    if exp == 0:
        return bits & 0x8000  # Keep sign, zero everything else
    return bits


def flush_fp32_subnormal(bits):
    """Flush FP32 subnormal to zero (preserve sign)."""
    exp = (bits >> 23) & 0xFF
    if exp == 0:
        return bits & 0x80000000
    return bits


def fp16_mult_golden(a_bits, b_bits):
    """FP16 × FP16 → FP32 result as bit pattern.

    Matches RTL: subnormals flushed to zero before multiply.
    """
    a_bits = flush_fp16_subnormal(a_bits)
    b_bits = flush_fp16_subnormal(b_bits)
    a = bits_to_fp16(a_bits)
    b = bits_to_fp16(b_bits)
    result = np.float32(a) * np.float32(b)
    return fp32_to_bits(result)


def fp32_add_golden(a_bits, b_bits):
    """FP32 + FP32 → FP32 result as bit pattern.

    Matches RTL: subnormals flushed to zero.
    """
    a_bits = flush_fp32_subnormal(a_bits)
    b_bits = flush_fp32_subnormal(b_bits)
    a = bits_to_fp32(a_bits)
    b = bits_to_fp32(b_bits)
    result = np.float32(a + b)
    return fp32_to_bits(result)


def fp32_to_fp16_golden(a_bits):
    """FP32 → FP16 conversion as bit pattern.

    Matches RTL: FP32 subnormals flushed to zero, result subnormals also zero.
    """
    a_bits = flush_fp32_subnormal(a_bits)
    a = bits_to_fp32(a_bits)
    result = np.float16(a)
    result_bits = int(np.float16(result).view(np.uint16))
    return flush_fp16_subnormal(result_bits)


def fp16_add_golden(a_bits, b_bits):
    """FP16 + FP16 → FP16 result as bit pattern.

    Matches RTL: subnormals flushed to zero.
    """
    a_bits = flush_fp16_subnormal(a_bits)
    b_bits = flush_fp16_subnormal(b_bits)
    a = bits_to_fp16(a_bits)
    b = bits_to_fp16(b_bits)
    result = np.float16(np.float32(a) + np.float32(b))
    return int(np.float16(result).view(np.uint16))


def fp16_max_golden(a_bits, b_bits):
    """FP16 max(a, b) as bit pattern."""
    a = bits_to_fp16(a_bits)
    b = bits_to_fp16(b_bits)
    if np.isnan(a) or np.isnan(b):
        return 0x7E00  # Quiet NaN
    if a > b:
        return a_bits
    elif b > a:
        return b_bits
    else:
        # Equal (including +0 == -0)
        return b_bits  # Arbitrary choice for equal


def fp16_min_golden(a_bits, b_bits):
    """FP16 min(a, b) as bit pattern."""
    a = bits_to_fp16(a_bits)
    b = bits_to_fp16(b_bits)
    if np.isnan(a) or np.isnan(b):
        return 0x7E00  # Quiet NaN
    if a < b:
        return a_bits
    elif b < a:
        return b_bits
    else:
        return b_bits


def generate_fp16_test_vectors(seed=42, n_random=50):
    """Generate a mix of edge case and random FP16 bit patterns."""
    rng = np.random.RandomState(seed)

    # Edge cases
    edge_cases = [
        0x0000,  # +0
        0x8000,  # -0
        0x3C00,  # 1.0
        0xBC00,  # -1.0
        0x4000,  # 2.0
        0xC000,  # -2.0
        0x3555,  # ~0.333
        0x4248,  # ~3.14
        0x7BFF,  # Max normal (65504)
        0xFBFF,  # -Max normal
        0x0400,  # Min normal (2^-14)
        0x8400,  # -Min normal
        0x7C00,  # +Inf
        0xFC00,  # -Inf
        0x7E00,  # NaN
        0x5640,  # 100.0
        0xD640,  # -100.0
        0x2E66,  # 0.1 (approx)
    ]

    # Random normal FP16 values (avoid subnormals and specials)
    random_vals = []
    for _ in range(n_random):
        sign = rng.randint(0, 2) << 15
        exp = rng.randint(1, 31) << 10  # Normal range only
        mant = rng.randint(0, 1024)
        random_vals.append(sign | exp | mant)

    return edge_cases + random_vals


def generate_fp32_test_vectors(seed=42, n_random=50):
    """Generate FP32 test vectors from FP16 products (realistic range)."""
    rng = np.random.RandomState(seed)
    vectors = []

    # Generate by multiplying random FP16 pairs → gives valid FP32 range
    for _ in range(n_random):
        sign = rng.randint(0, 2) << 31
        exp = rng.randint(97, 160) << 23  # Range of FP16×FP16 products
        mant = rng.randint(0, 1 << 23)
        vectors.append(sign | exp | mant)

    # Edge cases
    vectors.extend([
        0x00000000,  # +0
        0x80000000,  # -0
        0x3F800000,  # 1.0
        0xBF800000,  # -1.0
        0x7F800000,  # +Inf
        0xFF800000,  # -Inf
        0x7FC00000,  # NaN
        0x42C80000,  # 100.0
        0xC2C80000,  # -100.0
    ])
    return vectors
