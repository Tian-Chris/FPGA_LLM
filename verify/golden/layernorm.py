"""Golden model for layernorm.v — 3-pass layer normalization.

Replicates:
  - L111-118: rsqrt LUT initialization
  - L265-283: divide_by_dim (arithmetic right shift for power-of-2 dims)
  - L286-294: compute_sq_diff
  - L297-326: normalize_elem
"""

from .common import int16, int32, saturate_int8


def _build_rsqrt_lut():
    """Build the exact rsqrt LUT from layernorm.v L111-118."""
    lut = [0] * 256
    lut[0] = 0xFFFF
    for i in range(1, 256):
        lut[i] = (256 * 16) // i
    return lut


RSQRT_LUT = _build_rsqrt_lut()

# Power-of-2 dimension -> shift amount (matches RTL L271-281)
_DIM_SHIFT = {
    4: 2, 8: 3, 16: 4, 32: 5, 64: 6, 128: 7, 256: 8, 512: 9, 1024: 10,
}


def divide_by_dim(val, dim):
    """Replicate layernorm.v divide_by_dim (L265-283).

    Arithmetic right shift for power-of-2 dims, default shift=8.
    """
    shift = _DIM_SHIFT.get(dim, 8)
    val = int32(val)
    return val >> shift  # Python >> on negative ints is arithmetic


def compute_rsqrt(var_in):
    """Replicate layernorm.v compute_rsqrt (L123-137)."""
    var_in = var_in & 0xFFFFFFFF
    if var_in < 8:
        lut_addr = 1
    elif var_in > 0x00FFFF:
        lut_addr = 0xFF
    else:
        lut_addr = (var_in >> 8) & 0xFF
    return RSQRT_LUT[lut_addr]


def normalize_elem(x, mean, inv_std, gamma, beta):
    # 1. Cast inputs to proper signed integers first
    x_s = int16(x)
    m_s = int32(mean)
    
    # 2. Centered must be SIGNED. x - mean
    centered_s = int32(x_s - m_s) 

    # 3. Multiply by inv_std (which is effectively a fractional scale)
    # If your RTL uses a logical shift, it implies the hardware is 
    # treating the product as a large signed block.
    normalized_product = int32(centered_s * (inv_std & 0xFFFF))
    normalized_s = normalized_product >> 8 

    # 4. Handle Gamma and Beta (Sign-extend from 8-bit)
    gamma_s = gamma if gamma < 128 else gamma - 256
    beta_s = beta if beta < 128 else beta - 256

    # 5. Apply Scaling (Matches RTL: scaled_product >> 7)
    scaled_product = int32(normalized_s * gamma_s)
    scaled = scaled_product >> 7

    # 6. Add Beta (RTL: result = scaled + beta, no shift on beta)
    result = int32(scaled + beta_s)

    # 7. Saturate to INT16 and return as unsigned 16-bit
    val = max(-32768, min(32767, result))
    return val & 0xFFFF

def compute_sq_diff(x, mean):
    # This must be signed to be mathematically correct
    x_s = int16(x)
    m_s = int32(mean)
    diff = int32(x_s - m_s)
    return (diff * diff) & 0xFFFFFFFF

def layernorm_golden(input_vec, gamma_vec, beta_vec, dim):
    """Full 3-pass layernorm computation.

    Args:
        input_vec: list of INT16 values
        gamma_vec: list of INT8 gamma values
        beta_vec:  list of INT8 beta values
        dim:       vector dimension (must be power of 2)
    Returns:
        list of INT16 normalized values (unsigned 16-bit representation)
    """
    assert len(input_vec) == dim
    assert len(gamma_vec) == dim
    assert len(beta_vec) == dim

    # Pass 1: Compute mean (L179-198)
    total = 0
    for x in input_vec:
        total = int32(total + int16(x))
    mean = divide_by_dim(total, dim)

    # Pass 2: Compute variance (L203-219)
    var_sum = 0
    for x in input_vec:
        var_sum = (var_sum + compute_sq_diff(x, mean)) & 0xFFFFFFFF

    EPS = 1
    variance = divide_by_dim(int32(var_sum), dim)
    inv_std = compute_rsqrt((variance + EPS) & 0xFFFFFFFF)

    # Pass 3: Normalize (L225-247)
    output = []
    for i in range(dim):
        out = normalize_elem(input_vec[i], mean, inv_std,
                             gamma_vec[i] & 0xFF, beta_vec[i] & 0xFF)
        output.append(out)

    return output
