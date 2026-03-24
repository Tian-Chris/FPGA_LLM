#!/usr/bin/env python3
"""BRAM utilities for banked memory layout (interleaved elements)."""

import os
from verify.hex_utils import to_hex, from_hex

def encode_to_banks(flat, num_banks):
    """Interleave flat list across banks: flat[i] -> bank[i % num_banks]."""
    depth = (len(flat) + num_banks - 1) // num_banks
    banks = [[] for _ in range(num_banks)]
    for i, val in enumerate(flat):
        banks[i % num_banks].append(val)
    
    # Pad banks to uniform depth
    for b in range(num_banks):
        banks[b] += [0] * (depth - len(banks[b]))
    return banks

def decode_from_banks(banks):
    """Reconstruct flat list: bank[b][addr] -> flat[addr * num_banks + b]."""
    num_banks = len(banks)
    depth = len(banks[0])
    return [banks[b][addr] for addr in range(depth) for b in range(num_banks)]

def flatten_weight_layout(weights, config):
    """Flatten weights following fsm_controller.v memory offsets."""
    D, T, I = config.MODEL_DIM, config.MAX_SEQ_LEN, config.INPUT_DIM
    flat = []

    # 1. Frontend projection (INPUT_DIM * MODEL_DIM)
    for row in weights['W_proj']: flat.extend(row)

    # 2. Positional embeddings (MAX_SEQ_LEN * MODEL_DIM)
    flat.extend([0] * (T * D))

    # 3. Transformer Layers (Encoder then Denoiser)
    for prefix in ('enc', 'den'):
        n_layers = config.NUM_ENC_LAYERS if prefix == 'enc' else config.NUM_DEN_LAYERS
        for layer in range(n_layers):
            key = f'{prefix}_{layer}'
            # Order: Q, K, V, O, FFN1, FFN2, G1, B1, G2, B2
            for suffix in ('_W_q', '_W_k', '_W_v', '_W_o', '_W_ffn1', '_W_ffn2'):
                for row in weights[key + suffix]: flat.extend(row)
            for suffix in ('gamma1', 'beta1', 'gamma2', 'beta2'):
                flat.extend(weights[key + '_' + suffix])
    return flat

def flatten_input(input_data):
    """Flatten 2D input [B*T][INPUT_DIM] to 1D."""
    return [val for row in input_data for val in row]

def write_bank_hex_files(prefix, banks, width):
    """Write individual hex files: {prefix}{bank_idx}.hex."""
    for b, bank_data in enumerate(banks):
        path = f"{prefix}{b}.hex"
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            for val in bank_data:
                f.write(to_hex(val, width) + "\n")

def read_bank_hex_files(prefix, num_banks, width):
    """Read individual bank hex files into nested list."""
    banks = []
    for b in range(num_banks):
        with open(f"{prefix}{b}.hex", "r") as f:
            banks.append([from_hex(l.strip(), width) for l in f 
                          if l.strip() and not l.startswith("//")])
    return banks

def read_interleaved_hex(path, width):
    """Read TB-generated interleaved file (already in flat element order)."""
    with open(path, "r") as f:
        return [from_hex(l.strip(), width) for l in f 
                if l.strip() and not l.startswith("//")]