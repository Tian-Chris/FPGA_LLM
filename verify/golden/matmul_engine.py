"""
acc[i][j] += a[i] * b[j]  (INT16*INT16 -> INT32 accumulation)
Output saturated to INT16.
"""

from .common import int16, int32, saturate_int16


def matmul_golden(mat_a, mat_b, tile_size):
    k_dim = len(mat_a[0])
    rows = len(mat_a)
    cols = len(mat_b[0])

    # INT32 accumulator array
    acc = [[0] * cols for _ in range(rows)]

    # Outer product accumulation (matches RTL mac_unit grid)
    for k in range(k_dim):
        a_col = [int16(mat_a[i][k]) for i in range(rows)]
        b_row = [int16(mat_b[k][j]) for j in range(cols)]
        for i in range(rows):
            for j in range(cols):
                acc[i][j] = int32(acc[i][j] + a_col[i] * b_row[j])

    # Saturate to INT16
    result = [[0] * cols for _ in range(rows)]
    for i in range(rows):
        for j in range(cols):
            result[i][j] = saturate_int16(acc[i][j])

    return result
