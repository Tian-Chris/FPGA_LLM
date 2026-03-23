"""
FP16 matmul golden model:
acc[i][j] += fp16_to_fp32(a[i]) * fp16_to_fp32(b[j])  (FP16*FP16 -> FP32 accumulation)
Output converted FP32 -> FP16.

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
    """FP16 matmul with FP32 accumulation and k-chunk merging matching RTL.

    When k_dim > tile_size, the matmul is split into k-chunks. Each chunk
    accumulates in FP32 and produces FP16 output. Multiple k-chunks are
    merged via FP16 addition (matching uram_accum_buf behavior).

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

        # FP32 accumulator for this k-chunk
        acc = [[np.float32(0.0)] * cols for _ in range(rows)]

        for k in range(k_start, k_end):
            a_col = [np.float32(np.uint16(mat_a[i][k]).view(np.float16)) for i in range(rows)]
            b_row = [np.float32(np.uint16(mat_b[k][j]).view(np.float16)) for j in range(cols)]
            for i in range(rows):
                for j in range(cols):
                    acc[i][j] = np.float32(acc[i][j] + a_col[i] * b_row[j])

        # Convert this k-chunk's result to FP16
        for i in range(rows):
            for j in range(cols):
                chunk_fp16 = int(np.float16(acc[i][j]).view(np.uint16))
                if kc == 0:
                    result[i][j] = chunk_fp16
                else:
                    # k-chunk accumulation: FP16 add (matches uram_accum_buf)
                    result[i][j] = _fp16_add(result[i][j], chunk_fp16)

    return result
