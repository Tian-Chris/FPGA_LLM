"""Golden model for activation.v — GELU via 512-entry LUT (FP16 → FP16).

Index: clamp((x + 8) * 32, 0, 511) where x is the FP16 input value.
Below -8: output ≈ 0. Above 8: output ≈ x. Between: LUT lookup.
"""

import numpy as np
import math
import os

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _build_gelu_lut():
    """Build GELU LUT matching RTL: gelu_lut[i] = FP16(GELU(i/32 - 8))."""
    lut = []
    for i in range(512):
        x = i / 32.0 - 8.0
        y = 0.5 * x * (1.0 + math.erf(x / math.sqrt(2.0)))
        fp16_val = np.float16(y)
        lut.append(int(fp16_val.view(np.uint16)))
    return lut


GELU_LUT = _build_gelu_lut()


def _gelu_index(x_bits):
    """Compute GELU LUT index from FP16 bit pattern.

    Matches RTL gelu_index function in activation.v exactly.
    Index = clamp((x + 8) * 32, 0, 511) computed via FP16 bit manipulation.
    """
    x_sign = (x_bits >> 15) & 1
    x_exp = (x_bits >> 10) & 0x1F
    x_mant = x_bits & 0x3FF

    if x_exp == 0:
        # Zero/subnormal → index 256 (GELU(0) ≈ 0)
        return 256
    elif x_exp == 31:
        # Inf/NaN
        return 0 if x_sign else 511
    elif x_exp >= 20:
        # |x| >= 32 → way beyond ±8 range
        return 0 if x_sign else 511
    elif x_exp >= 10:
        # |x|*32 = {1, mant} >> (20 - exp)
        full = (1 << 10) | x_mant  # {1, mant} = 11 bits
        fixed_val = full >> (20 - x_exp)
        if x_sign:
            shifted = 256 - fixed_val
        else:
            shifted = 256 + fixed_val
        return max(0, min(511, shifted))
    else:
        # |x| < 1/1024, effectively 0
        return 256


def gelu_golden(input_bits):
    """GELU activation for a list of FP16 bit patterns.

    Args:
        input_bits: list of FP16 bit patterns (uint16)
    Returns:
        list of FP16 bit patterns (uint16)
    """
    return [GELU_LUT[_gelu_index(b)] for b in input_bits]
