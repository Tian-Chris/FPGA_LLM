#!/usr/bin/env python3
"""Generate GELU LUT for FP16 activation module.

The LUT maps 512 entries covering FP16 inputs from -8.0 to +8.0.
Below -8: GELU ≈ 0. Above +8: GELU ≈ x. Between: LUT lookup.

Index mapping: idx = clamp((x + 8.0) * 32, 0, 511)
Each entry is a GELU(x) value stored as FP16 bit pattern.
"""

import numpy as np
import math
import os


def gelu(x):
    """Exact GELU function."""
    return 0.5 * x * (1.0 + math.erf(x / math.sqrt(2.0)))


def main():
    lut_size = 512
    x_min = -8.0
    x_max = 8.0

    entries = []
    for i in range(lut_size):
        # Map index to x: idx = clamp((x + 8) * 32, 0, 511) → x = idx/32 - 8
        x = i / 32.0 + x_min
        y = gelu(x)
        # Convert to FP16 bit pattern
        fp16_val = np.float16(y)
        bits = int(fp16_val.view(np.uint16))
        entries.append(bits)

    # Write hex file
    out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "rtl")
    out_path = os.path.join(out_dir, "gelu_lut.hex")
    with open(out_path, "w") as f:
        for bits in entries:
            f.write(f"{bits:04x}\n")

    print(f"Generated {out_path} with {lut_size} entries")

    # Verify a few values
    for x_test in [-8, -4, -2, -1, 0, 1, 2, 4, 8]:
        y_exact = gelu(x_test)
        idx = int(np.clip((x_test + 8.0) * 32, 0, 511))
        y_lut = float(np.uint16(entries[idx]).view(np.float16))
        print(f"  x={x_test:+6.2f}  GELU={y_exact:+8.4f}  LUT[{idx:3d}]={y_lut:+8.4f}")


if __name__ == "__main__":
    main()
