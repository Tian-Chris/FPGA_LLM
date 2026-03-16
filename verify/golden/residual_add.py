"""Golden model for residual_add.v — saturating INT16 addition.

Replicates L137-152: saturating_add function.
"""

from .common import int16, saturate_int16


def saturating_add(a, b):
    """Replicate residual_add.v saturating_add (L137-152).

    Sum two INT16 values with overflow clamping to [-32768, 32767].
    """
    a = int16(a)
    b = int16(b)
    total = a + b  # 17-bit range in Python (no overflow)
    return saturate_int16(total)


def residual_add_golden(residual_vec, sublayer_vec):
    """Element-wise saturating addition of two INT16 vectors.

    Args:
        residual_vec: list of INT16 values (skip connection)
        sublayer_vec: list of INT16 values (sublayer output)
    Returns:
        list of INT16 saturated sums
    """
    assert len(residual_vec) == len(sublayer_vec)
    return [saturating_add(a, b)
            for a, b in zip(residual_vec, sublayer_vec)]
