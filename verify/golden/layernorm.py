"""Golden model for layernorm.v — FP16/FP32 layer normalization.

Pass 1: FP32 sum of FP16 inputs, mean = sum * (1/dim)
Pass 2: FP32 variance = sum((x - mean)^2) * (1/dim)
Rsqrt:  Quake fast inverse sqrt + 1 Newton-Raphson iteration
Pass 3: out = FP16((x_fp32 - mean) * inv_std * gamma_fp32 + beta_fp32)
"""

import numpy as np
import struct


def _fp16_to_fp32(bits):
    """Convert FP16 bit pattern to numpy float32."""
    return float(np.uint16(bits).view(np.float16).astype(np.float32))


def _fp32_bits(f):
    """Get FP32 bit pattern from float."""
    return struct.unpack('<I', struct.pack('<f', np.float32(f)))[0]


def _bits_to_fp32(bits):
    """Convert FP32 bit pattern to float."""
    return struct.unpack('<f', struct.pack('<I', bits & 0xFFFFFFFF))[0]


def _fp32_to_fp16_bits(f):
    """Convert float to FP16 bit pattern (round-to-nearest-even, subnormal flush)."""
    fp16 = np.float32(f).astype(np.float16)
    return int(fp16.view(np.uint16))


# Power-of-2 reciprocals matching fp32_recip_dim in fp_funcs.vh
_RECIP_DIM = {
    4: 0.25, 8: 0.125, 16: 0.0625, 32: 1/32, 64: 1/64,
    128: 1/128, 256: 1/256, 512: 1/512, 1024: 1/1024,
}


def _quake_rsqrt(var_eps_bits):
    """Quake fast inverse sqrt + 1 Newton-Raphson iteration.

    Replicates ST_COMP_RSQRT in layernorm.v exactly:
    Step 0: y0 = 0x5F3759DF - (bits >> 1), half_v = 0.5 * var_eps
    Step 1: y_sq = y0 * y0
    Step 2: half_v_y_sq = half_v * y_sq
    Step 3: factor = 1.5 - half_v_y_sq
    Step 4: inv_std = y0 * factor
    """
    var_eps = _bits_to_fp32(var_eps_bits)

    # Step 0: initial estimate (integer trick on FP32 bit pattern)
    y0_bits = (0x5F3759DF - (var_eps_bits >> 1)) & 0xFFFFFFFF
    y0 = _bits_to_fp32(y0_bits)
    half_v = np.float32(np.float32(0.5) * np.float32(var_eps))

    # Step 1: y_sq = y0 * y0
    y_sq = np.float32(np.float32(y0) * np.float32(y0))

    # Step 2: half_v_y_sq = half_v * y_sq
    half_v_y_sq = np.float32(half_v * y_sq)

    # Step 3: factor = 1.5 - half_v_y_sq
    factor = np.float32(np.float32(1.5) - half_v_y_sq)

    # Step 4: inv_std = y0 * factor
    inv_std = np.float32(np.float32(y0) * factor)

    return inv_std


def layernorm_golden(input_bits, gamma_bits, beta_bits, dim):
    """Full 3-pass FP16/FP32 layernorm.

    Args:
        input_bits: list of FP16 bit patterns (uint16)
        gamma_bits: list of FP16 bit patterns (uint16)
        beta_bits:  list of FP16 bit patterns (uint16)
        dim:        vector dimension (must be power of 2)
    Returns:
        list of FP16 bit patterns (uint16)
    """
    assert len(input_bits) == dim
    assert len(gamma_bits) == dim
    assert len(beta_bits) == dim

    recip = np.float32(_RECIP_DIM.get(dim, 1/256))

    # Pass 1: Mean (FP32 accumulation)
    fp32_sum = np.float32(0.0)
    for bits in input_bits:
        x_fp32 = np.float32(_fp16_to_fp32(bits))
        fp32_sum = np.float32(fp32_sum + x_fp32)
    mean = np.float32(fp32_sum * recip)
    neg_mean_f = np.float32(-mean)

    # Pass 2: Variance (FP32 accumulation)
    var_sum = np.float32(0.0)
    for bits in input_bits:
        x_fp32 = np.float32(_fp16_to_fp32(bits))
        centered = np.float32(x_fp32 + neg_mean_f)
        sq = np.float32(centered * centered)
        var_sum = np.float32(var_sum + sq)
    variance = np.float32(var_sum * recip)

    # Add epsilon (1e-3 = 0x3A83126F)
    eps = _bits_to_fp32(0x3A83126F)
    var_eps = np.float32(variance + np.float32(eps))
    var_eps_bits = _fp32_bits(var_eps)

    # Rsqrt via Quake trick
    inv_std = _quake_rsqrt(var_eps_bits)

    # Pass 3: Normalize
    output = []
    for i in range(dim):
        x_fp32 = np.float32(_fp16_to_fp32(input_bits[i]))
        gamma_fp32 = np.float32(_fp16_to_fp32(gamma_bits[i]))
        beta_fp32 = np.float32(_fp16_to_fp32(beta_bits[i]))

        # centered = x - mean
        centered = np.float32(x_fp32 + neg_mean_f)
        # normed = centered * inv_std
        normed = np.float32(centered * inv_std)
        # scaled = normed * gamma
        scaled = np.float32(normed * gamma_fp32)
        # result = scaled + beta
        result = np.float32(scaled + beta_fp32)
        # Convert to FP16
        output.append(_fp32_to_fp16_bits(result))

    return output
