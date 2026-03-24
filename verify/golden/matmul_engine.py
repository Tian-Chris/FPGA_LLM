"""
FP16 matmul golden model with integer accumulation:
  - FP16 inputs unpacked to float64 (52-bit mantissa models exact integer math)
  - float64 accumulation within each k-chunk (no intermediate rounding)
  - Convert to FP16 at k-chunk boundary
  - Cross-k-chunk merging via FP16 addition (matches RTL uram_accum_buf)

K-chunk accumulation: when k_dim > tile_size, each k-chunk produces FP16 partial
results that are merged via FP16 addition (matching RTL uram_accum_buf behavior).
"""

import numpy as np


def _fp16_add(a_bits, b_bits):
    """FP16 addition matching RTL fp16_add_comb: convert to float, add, convert back."""
    a = float(np.array(a_bits, dtype=np.uint16).view(np.float16))
    b = float(np.array(b_bits, dtype=np.uint16).view(np.float16))
    result = np.float16(a + b)
    return int(result.view(np.uint16))


def matmul_golden(mat_a, mat_b, tile_size):
    """FP16 matmul with integer accumulation and k-chunk merging matching RTL.

    Integer accumulation is modeled via float64: the 52-bit mantissa exceeds
    the ~27 bits needed for 32 products of 22-bit mantissas, so no rounding
    occurs between individual additions — only at the final FP16 conversion.
    This matches RTL's exponent-aligned integer add behavior.

    When k_dim > tile_size, the matmul is split into k-chunks. Each chunk
    accumulates with no intermediate rounding and produces FP16 output.
    Multiple k-chunks are merged via FP16 addition (matching uram_accum_buf).

    mat_a: 2D list of FP16 bit patterns (uint16)
    mat_b: 2D list of FP16 bit patterns (uint16)
    Returns: 2D list of FP16 bit patterns (uint16)
    """
    k_dim = len(mat_a[0])
    rows = len(mat_a)
    cols = len(mat_b[0])
    num_k_chunks = (k_dim + tile_size - 1) // tile_size

    # Result accumulator (FP16 bit patterns)
    result = [[0] * cols for _ in range(rows)]

    for kc in range(num_k_chunks):
        k_start = kc * tile_size
        k_end = min(k_start + tile_size, k_dim)

        # float64 accumulator for this k-chunk (models integer accumulation)
        acc = [[np.float64(0.0)] * cols for _ in range(rows)]

        for k in range(k_start, k_end):
            a_col = [np.float64(np.uint16(mat_a[i][k]).view(np.float16)) for i in range(rows)]
            b_row = [np.float64(np.uint16(mat_b[k][j]).view(np.float16)) for j in range(cols)]
            for i in range(rows):
                for j in range(cols):
                    acc[i][j] += a_col[i] * b_row[j]

        # Convert this k-chunk's result to FP16
        for i in range(rows):
            for j in range(cols):
                # RTL path: integer → FP32 → FP16 (double rounding)
                chunk_fp16 = int(np.float16(np.float32(acc[i][j])).view(np.uint16))
                if kc == 0:
                    result[i][j] = chunk_fp16
                else:
                    # k-chunk accumulation: FP16 add (matches uram_accum_buf)
                    result[i][j] = _fp16_add(result[i][j], chunk_fp16)

    return result
