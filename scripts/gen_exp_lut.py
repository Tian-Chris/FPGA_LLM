#!/usr/bin/env python3
"""Generate exp(-x) LUT for FP16 softmax module.

256 entries: exp_lut[i] = FP16(exp(-i/16))
Range: x ∈ [0, 15.9375], so exp(-x) ∈ [1.0, ~1.1e-7]
Values below FP16 min normal (~6.1e-5) are flushed to 0.

Index mapping in RTL: idx = clamp(|diff| * 16, 0, 255)
where diff = scaled_score - max_score (always ≤ 0).
"""

import numpy as np
import math
import os


def main():
    lut_size = 256

    entries = []
    for i in range(lut_size):
        x = i / 16.0  # [0, 15.9375]
        y = math.exp(-x)
        fp16_val = np.float16(y)
        bits = int(fp16_val.view(np.uint16))
        entries.append(bits)

    out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "rtl")
    out_path = os.path.join(out_dir, "exp_lut.hex")
    with open(out_path, "w") as f:
        for bits in entries:
            f.write(f"{bits:04x}\n")

    print(f"Generated {out_path} with {lut_size} entries")

    for i in [0, 1, 4, 8, 16, 32, 64, 128, 255]:
        x = i / 16.0
        y_exact = math.exp(-x)
        y_lut = float(np.uint16(entries[i]).view(np.float16))
        print(f"  idx={i:3d}  x={x:7.4f}  exp(-x)={y_exact:12.6f}  LUT={y_lut:12.6f}")


if __name__ == "__main__":
    main()
