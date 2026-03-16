"""Golden model for softmax.v — 3-pass fixed-point softmax.

Replicates:
  - L96-103:  exp LUT initialization
  - L111-117: reciprocal LUT initialization
  - L122-139: compute_exp function
  - L255-285: normalize function
"""

from .common import int16, uint32


def _build_exp_lut():
    """Build the exact exp LUT from softmax.v L96-103."""
    lut = [0] * 256
    for i in range(256):
        if i == 255:
            lut[i] = 0x0100
        else:
            lut[i] = 0x0001 + (i & 0xFF)
    return lut


def _build_recip_lut():
    """Build the exact reciprocal LUT from softmax.v L111-117."""
    lut = [0] * 256
    lut[0] = 0xFFFF
    for i in range(1, 256):
        lut[i] = 0xFFFF // i
    return lut


EXP_LUT = _build_exp_lut()
RECIP_LUT = _build_recip_lut()


def compute_exp(x, max_x):
    """Replicate softmax.v compute_exp (L122-139).

    Args:
        x: INT16 input value
        max_x: INT16 maximum value in row
    Returns:
        16-bit unsigned exp value
    """
    diff = int16(x - max_x)  # Always <= 0

    if diff <= -2040:
        lut_addr = 0
    else:
        lut_addr = (diff + 2040) >> 3  # Scale to 8-bit address

    lut_addr = lut_addr & 0xFF
    return EXP_LUT[lut_addr]


def normalize(exp_val, exp_sum):
    """Replicate softmax.v normalize function (L255-285).

    Args:
        exp_val: 16-bit exp value for this element
        exp_sum: 32-bit sum of all exp values
    Returns:
        16-bit unsigned normalized value
    """
    exp_sum = uint32(exp_sum)

    # Adaptive addressing based on sum magnitude (L263-268)
    byte2 = (exp_sum >> 16) & 0xFF
    byte1 = (exp_sum >> 8) & 0xFF
    byte0 = exp_sum & 0xFF

    if byte2 != 0:
        recip_addr = byte2
    elif byte1 != 0:
        recip_addr = byte1
    else:
        recip_addr = byte0 if byte0 != 0 else 1

    recip_val = RECIP_LUT[recip_addr & 0xFF]

    # Adjust scaling based on which byte was used (shifts reduced by 8 for 16-bit output)
    product = (exp_val & 0xFFFF) * (recip_val & 0xFFFF)
    if byte2 != 0:
        scaled = product >> 16
    elif byte1 != 0:
        scaled = product >> 8
    else:
        scaled = product

    scaled = scaled & 0xFFFFFFFF

    # Saturate to 16 bits
    if scaled > 65535:
        return 0xFFFF
    return scaled & 0xFFFF


def softmax_golden(input_vec, scale_shift=0, row_idx=None):
    """Full 3-pass softmax computation.

    Args:
        input_vec: list of INT16 values (one row of attention scores)
        scale_shift: right-shift for attention scaling (÷√head_dim), default 0
        row_idx: if not None, enable causal masking (mask cols > row_idx)
    Returns:
        list of UINT16 normalized probabilities
    """
    seq_len = len(input_vec)

    # Apply attention scaling: arithmetic right-shift each input
    # Python's >> on negative ints is already arithmetic (sign-extending)
    scaled = [int16(int16(x) >> scale_shift) for x in input_vec]

    # Pass 1: Find maximum (with causal masking)
    max_val = -32768
    for j, v in enumerate(scaled):
        if row_idx is not None and j > row_idx:
            continue  # Masked — skip
        if v > max_val:
            max_val = v

    # Pass 2: Compute exp and sum (with causal masking)
    exp_buffer = []
    exp_sum = 0
    for j, v in enumerate(scaled):
        if row_idx is not None and j > row_idx:
            exp_buffer.append(0)  # Masked position → exp = 0
        else:
            e = compute_exp(v, max_val)
            exp_buffer.append(e)
            exp_sum = uint32(exp_sum + e)

    # Pass 3: Normalize
    output = []
    for e in exp_buffer:
        output.append(normalize(e, exp_sum))

    return output
