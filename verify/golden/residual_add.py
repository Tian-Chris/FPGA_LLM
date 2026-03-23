"""Golden model for residual_add.v — FP16 element-wise addition."""

import numpy as np


def fp16_add(a_bits, b_bits):
    """FP16 + FP16 → FP16 (bit patterns)."""
    a = np.uint16(a_bits).view(np.float16)
    b = np.uint16(b_bits).view(np.float16)
    result = np.float16(a + b)
    return int(result.view(np.uint16))


def residual_add_golden(residual_bits, sublayer_bits):
    """Element-wise FP16 addition of two vectors.

    Args:
        residual_bits: list of FP16 bit patterns (skip connection)
        sublayer_bits: list of FP16 bit patterns (sublayer output)
    Returns:
        list of FP16 bit patterns (sums)
    """
    assert len(residual_bits) == len(sublayer_bits)
    return [fp16_add(a, b)
            for a, b in zip(residual_bits, sublayer_bits)]
