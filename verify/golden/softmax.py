"""Golden model for softmax.v — FP16 softmax with LUT-based exp.

Pass 1: Scale scores by FP16 scale_factor, find FP16 max
Pass 2: exp(scaled - max) via 256-entry LUT, FP32 sum
Pass 3: Normalize by FP32 reciprocal (Newton-Raphson)
"""

import numpy as np
import struct
import math
import os


def _fp16_to_fp32(bits):
    """FP16 bit pattern → float32."""
    return float(np.uint16(bits).view(np.float16).astype(np.float32))


def _fp32_bits(f):
    """Float → FP32 bit pattern."""
    return struct.unpack('<I', struct.pack('<f', np.float32(f)))[0]


def _bits_to_fp32(bits):
    """FP32 bit pattern → float."""
    return struct.unpack('<f', struct.pack('<I', bits & 0xFFFFFFFF))[0]


def _fp16_bits(f):
    """Float → FP16 bit pattern."""
    return int(np.float32(f).astype(np.float16).view(np.uint16))


def _fp16_mult(a_bits, b_bits):
    """FP16 × FP16 → FP16 (bit patterns)."""
    a = float(np.uint16(a_bits).view(np.float16))
    b = float(np.uint16(b_bits).view(np.float16))
    result = np.float16(np.float16(a) * np.float16(b))
    return int(result.view(np.uint16))


def _fp16_add(a_bits, b_bits):
    """FP16 + FP16 → FP16 (bit patterns)."""
    a = np.uint16(a_bits).view(np.float16)
    b = np.uint16(b_bits).view(np.float16)
    result = np.float16(a + b)
    return int(result.view(np.uint16))


def _fp16_max(a_bits, b_bits):
    """FP16 max (bit patterns)."""
    a = float(np.uint16(a_bits).view(np.float16))
    b = float(np.uint16(b_bits).view(np.float16))
    # Handle NaN
    if np.isnan(a):
        return a_bits
    if np.isnan(b):
        return b_bits
    return a_bits if a >= b else b_bits


def _build_exp_lut():
    """Build exp LUT matching RTL: exp_lut[i] = FP16(exp(-i/16))."""
    lut = []
    for i in range(256):
        x = i / 16.0
        y = math.exp(-x)
        fp16_val = np.float16(y)
        lut.append(int(fp16_val.view(np.uint16)))
    return lut


EXP_LUT = _build_exp_lut()


def _exp_lut_index(diff_bits):
    """Compute exp LUT index from FP16 diff (always ≤ 0).

    Index = clamp(|diff| * 16, 0, 255).
    Matches RTL exp_lut_index function exactly.
    """
    e = (diff_bits >> 10) & 0x1F
    m = diff_bits & 0x3FF

    if diff_bits == 0x0000 or diff_bits == 0x8000 or e == 0:
        return 0
    elif e == 31:
        return 255
    elif e >= 19:
        return 255
    elif e < 11:
        return 0
    else:
        # e ∈ [11, 18]: floor(|diff| * 16) = {1, mant} >> (21 - e)
        full = (1 << 10) | m  # {1, mant} = 11 bits
        shift_right = 21 - e
        idx = full >> shift_right
        return min(idx, 255)


def _newton_raphson_recip(sum_bits):
    """FP32 reciprocal via Newton-Raphson, matching RTL ST_COMP_RECIP.

    Step 0: y0 = 0x7EF311C7 - sum_bits
    Step 1: tmp = sum * y0
    Step 2: tmp = 2 - tmp
    Step 3: recip = y0 * tmp
    """
    exp_sum = _bits_to_fp32(sum_bits)

    # Step 0: magic number initial estimate
    y0_bits = (0x7EF311C7 - sum_bits) & 0xFFFFFFFF
    y0 = _bits_to_fp32(y0_bits)

    # Step 1: tmp = sum * y0
    tmp = np.float32(np.float32(exp_sum) * np.float32(y0))

    # Step 2: tmp = 2 - tmp
    tmp = np.float32(np.float32(2.0) - tmp)

    # Step 3: recip = y0 * tmp
    recip = np.float32(np.float32(y0) * tmp)

    return recip


def softmax_golden(input_bits, scale_factor_bits, row_idx=None):
    """Full 3-pass FP16 softmax.

    Args:
        input_bits: list of FP16 bit patterns (attention scores)
        scale_factor_bits: FP16 bit pattern for scale (1/√head_dim)
        row_idx: if not None, enable causal masking (mask cols > row_idx)
    Returns:
        list of FP16 bit patterns (probabilities)
    """
    seq_len = len(input_bits)
    FP16_NEG_INF = 0xFC00

    # Pass 1: Scale and find max
    scaled = []
    max_val = FP16_NEG_INF
    for j, bits in enumerate(input_bits):
        s = _fp16_mult(bits, scale_factor_bits)
        scaled.append(s)
        if row_idx is not None and j > row_idx:
            continue
        max_val = _fp16_max(s, max_val)

    # Pass 2: Compute exp and accumulate FP32 sum
    exp_buffer = []
    exp_sum = np.float32(0.0)
    neg_max = max_val ^ 0x8000  # Flip sign bit for negation
    for j, s in enumerate(scaled):
        if row_idx is not None and j > row_idx:
            exp_buffer.append(0x0000)
        else:
            diff = _fp16_add(s, neg_max)
            idx = _exp_lut_index(diff)
            exp_val = EXP_LUT[idx]
            exp_buffer.append(exp_val)
            exp_sum = np.float32(exp_sum +
                                 np.float32(_fp16_to_fp32(exp_val)))

    # Reciprocal via Newton-Raphson
    exp_sum_bits = _fp32_bits(exp_sum)
    recip = _newton_raphson_recip(exp_sum_bits)

    # Pass 3: Normalize
    output = []
    for exp_val in exp_buffer:
        exp_fp32 = np.float32(_fp16_to_fp32(exp_val))
        result_fp32 = np.float32(exp_fp32 * recip)
        output.append(_fp16_bits(result_fp32))

    return output
