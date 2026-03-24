#!/usr/bin/env python3
"""
Parse FSM debug trace records dumped from simulation HBM.

Each record is a 256-bit word written by fsm_controller at S_NEXT_STEP:
  [31:0]    cycle_counter (32)
  [47:32]   layer_cnt (16)
  [55:48]   state (8)
  [63:56]   step_idx (8)
  [79:64]   step_bt:step_cfg:padding (16)
  [95:80]   dbg_write_idx (16)
  [123:96]  layer_wgt_base (28)
  [127:124] reserved (4)
  [143:128] mm_cmd_m (16)
  [159:144] mm_cmd_n (16)
  [175:160] mm_cmd_k (16)
  [191:176] head_cnt (16)
  [207:192] nm_row_cnt (16)
  [223:208] cache_len_r (16)
  [231:224] decode_r (8)
  [255:232] reserved (24)

Usage:
  python3 verify/parse_debug_trace.py verify/test_data/debug_trace_1k.hex
  python3 verify/parse_debug_trace.py  # defaults to debug_trace_decode.hex
"""

import sys
import os

FSM_STATES = {
    0:  "S_IDLE",
    1:  "S_DECODE",
    2:  "S_LN_RUN",
    3:  "S_QKV_MM",
    4:  "S_QKV_FL",
    5:  "S_ATT_SCORE",
    6:  "S_ATT_SM",
    7:  "S_ATT_SM_FL",
    8:  "S_ATT_OUT",
    9:  "S_ATT_OUT_FL",
    10: "S_MM_RUN",
    11: "S_ACT_RUN",
    12: "S_RES_RUN",
    13: "S_UF_RUN",
    14: "S_NEXT_STEP",
    15: "S_DONE",
    16: "S_OUTPUT_COPY",
    17: "S_CHECKPOINT",
}

BLOCK_TYPES = {
    0:  "BT_LN",
    1:  "BT_QKV",
    2:  "BT_ATTN",
    3:  "BT_MATMUL",
    4:  "BT_ACT",
    5:  "BT_RES",
    6:  "BT_FLUSH",
    15: "BT_END",
}

# Pre-Norm step table for human-readable labels
STEP_LABELS = {
    0:  "LN1",
    1:  "flush LN1→ACT_TEMP",
    2:  "QKV",
    3:  "attention block",
    4:  "output projection",
    5:  "residual1",
    6:  "flush res1→ACT_EMBED",
    7:  "LN2",
    8:  "flush LN2→ACT_TEMP",
    9:  "FFN1",
    10: "GELU",
    11: "flush act→ACT_FFN",
    12: "FFN2",
    13: "residual2",
    14: "flush res2→ACT_EMBED",
    15: "END",
}


def parse_record(hex_str):
    """Parse a 256-bit hex string (64 hex chars) into a debug record dict.

    Two record formats:
      Normal:     [31:24]=anything except 0xCC — standard FSM step record
      Checkpoint: [31:24]=0xCC — URAM activation dump (4 per layer)
        [15:0]   layer_cnt
        [23:16]  col_idx (0-3)
        [31:24]  0xCC marker
        [255:32] URAM data[223:0] (14 FP16 values)
    """
    val = int(hex_str.strip(), 16)

    marker = (val >> 24) & 0xFF
    if marker == 0xCC:
        layer   = val & 0xFFFF
        col_idx = (val >> 16) & 0xFF
        # Extract 14 FP16 values from bits [255:32]
        fp16_vals = []
        for i in range(14):
            fp16_bits = (val >> (32 + i * 16)) & 0xFFFF
            fp16_vals.append(fp16_bits)
        return {
            'type': 'checkpoint',
            'layer': layer,
            'col_idx': col_idx,
            'fp16_vals': fp16_vals,
        }

    cycle     = val & 0xFFFFFFFF
    layer     = (val >> 32) & 0xFFFF
    state     = (val >> 48) & 0xFF
    step_idx  = (val >> 56) & 0xFF
    bt_cfg    = (val >> 64) & 0xFFFF
    dbg_idx   = (val >> 80) & 0xFFFF
    wgt_base  = (val >> 96) & 0x0FFFFFFF
    mm_m      = (val >> 128) & 0xFFFF
    mm_n      = (val >> 144) & 0xFFFF
    mm_k      = (val >> 160) & 0xFFFF
    head_cnt  = (val >> 176) & 0xFFFF
    nm_row    = (val >> 192) & 0xFFFF
    cache_len = (val >> 208) & 0xFFFF
    decode_r  = (val >> 224) & 0xFF

    # bt_cfg packing: {step_bt[3:0], step_cfg[3:0], 8'd0}
    step_bt  = (bt_cfg >> 12) & 0xF
    step_cfg = (bt_cfg >> 8) & 0xF

    return {
        'type': 'step',
        'cycle': cycle,
        'layer': layer,
        'state': state,
        'step_idx': step_idx,
        'step_bt': step_bt,
        'step_cfg': step_cfg,
        'dbg_idx': dbg_idx,
        'wgt_base': wgt_base,
        'mm_m': mm_m,
        'mm_n': mm_n,
        'mm_k': mm_k,
        'head_cnt': head_cnt,
        'nm_row': nm_row,
        'cache_len': cache_len,
        'decode_r': decode_r,
    }


def fp16_to_float(bits):
    """Convert FP16 bit pattern to float for display."""
    import struct
    import numpy as np
    return float(np.array([bits], dtype=np.uint16).view(np.float16)[0])


def format_record(rec, idx):
    """Format a parsed record as a human-readable string."""
    if rec.get('type') == 'checkpoint':
        vals_str = " ".join(f"{fp16_to_float(v):7.3f}" for v in rec['fp16_vals'][:8])
        return (f"  [{idx:3d}] CHECKPOINT  L{rec['layer']}  col={rec['col_idx']}  "
                f"data[0:7]: {vals_str}")

    state_name = FSM_STATES.get(rec['state'], f"???({rec['state']})")
    bt_name = BLOCK_TYPES.get(rec['step_bt'], f"???({rec['step_bt']})")
    step_label = STEP_LABELS.get(rec['step_idx'], "")

    done = rec['step_idx'] == 0xFF
    if done:
        return (f"  [{idx:3d}] cyc={rec['cycle']:8d}  L{rec['layer']}  "
                f"{state_name:<14s}  step=0xFF  <<DONE>>")

    parts = [
        f"  [{idx:3d}] cyc={rec['cycle']:8d}  L{rec['layer']}  "
        f"{state_name:<14s}  step={rec['step_idx']:2d} ({bt_name}/{step_label})"
    ]

    # Add matmul dimensions if relevant
    if rec['mm_m'] or rec['mm_n'] or rec['mm_k']:
        parts.append(f"  mm({rec['mm_m']}x{rec['mm_n']}x{rec['mm_k']})")

    if rec['head_cnt']:
        parts.append(f"  head={rec['head_cnt']}")
    if rec['decode_r']:
        parts.append(f"  DECODE cache={rec['cache_len']}")

    return "".join(parts)


def parse_trace_file(filepath):
    """Parse and print all records from a debug trace hex file."""
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        return []

    records = []
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or line.startswith('@'):
                continue
            records.append(parse_record(line))
    return records


def print_trace(records, filepath=""):
    """Print formatted debug trace."""
    print(f"{'=' * 72}")
    print(f"FSM DEBUG TRACE — {filepath} ({len(records)} records)")
    print(f"{'=' * 72}")

    prev_layer = -1
    for i, rec in enumerate(records):
        if rec['layer'] != prev_layer:
            if prev_layer >= 0:
                print(f"  {'─' * 60}")
            prev_layer = rec['layer']
        print(format_record(rec, i))

    step_records = [r for r in records if r.get('type') != 'checkpoint']
    if step_records:
        first_cyc = step_records[0]['cycle']
        last_cyc = step_records[-1]['cycle']
        print(f"\nTotal: {last_cyc - first_cyc} cycles "
              f"({first_cyc} → {last_cyc})")
    print(f"{'=' * 72}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        path = "verify/test_data/debug_trace_decode.hex"

    records = parse_trace_file(path)
    if records:
        print_trace(records, path)
