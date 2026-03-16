"""End-to-end golden model for the FPGA diffusion transformer forward pass.

Chains the per-module golden models (matmul, softmax, layernorm, activation,
residual_add) into a full transformer pipeline matching fsm_controller.v.

Precision boundaries (matching RTL):
  - Matmul:     INT8 in -> INT32 accumulate -> INT16 saturate out
  - LayerNorm:  INT16 in -> INT8 out
  - Activation: INT16 in -> INT16 out
  - Softmax:    INT16 in -> UINT8 out (reinterpreted as INT8 by next matmul)
  - BRAM read:  INT16 truncated to INT8 via int8() between activation and FFN2
  - Residual:   INT16 + INT16 -> INT16 (saturating)
"""

import random
from dataclasses import dataclass

from .common import int8, int16, saturate_int16
from .matmul_engine import matmul_golden
from .softmax import softmax_golden
from .layernorm import layernorm_golden
from .activation import relu_golden
from .residual_add import residual_add_golden


@dataclass
class TransformerConfig:
    BATCH: int = 1
    SEQ_LEN: int = 4
    MODEL_DIM: int = 16
    INPUT_DIM: int = 8
    F_DIM: int = 32
    NUM_HEADS: int = 1
    HEAD_DIM: int = 16     # MODEL_DIM / NUM_HEADS
    TILE_SIZE: int = 4
    NUM_ENC_LAYERS: int = 1
    NUM_DEN_LAYERS: int = 1
    MAX_SEQ_LEN: int = 4   # For weight layout (may differ from SEQ_LEN)


def generate_random_weights(config, seed=42):
    """Generate all INT8 weight matrices and gamma/beta vectors.

    Weight layout follows fsm_controller.v LAYER_* offsets:
      Per layer: W_q, W_k, W_v, W_o  [MODEL_DIM x MODEL_DIM each]
                 W_ffn1               [MODEL_DIM x F_DIM]
                 W_ffn2               [F_DIM x MODEL_DIM]
                 gamma1, beta1        [MODEL_DIM each]
                 gamma2, beta2        [MODEL_DIM each]
    """
    rng = random.Random(seed)
    D = config.MODEL_DIM
    F = config.F_DIM
    I = config.INPUT_DIM

    def rand_mat(rows, cols):
        return [[rng.randint(-128, 127) for _ in range(cols)]
                for _ in range(rows)]

    def rand_vec(dim):
        return [rng.randint(-128, 127) for _ in range(dim)]

    weights = {}

    # Frontend projection: (INPUT_DIM, MODEL_DIM)
    weights['W_proj'] = rand_mat(I, D)

    # Per-layer weights
    for prefix in ('enc', 'den'):
        n_layers = config.NUM_ENC_LAYERS if prefix == 'enc' else config.NUM_DEN_LAYERS
        for layer in range(n_layers):
            key = f'{prefix}_{layer}'
            weights[f'{key}_W_q'] = rand_mat(D, D)
            weights[f'{key}_W_k'] = rand_mat(D, D)
            weights[f'{key}_W_v'] = rand_mat(D, D)
            weights[f'{key}_W_o'] = rand_mat(D, D)
            weights[f'{key}_W_ffn1'] = rand_mat(D, F)
            weights[f'{key}_W_ffn2'] = rand_mat(F, D)
            weights[f'{key}_gamma1'] = rand_vec(D)
            weights[f'{key}_beta1'] = rand_vec(D)
            weights[f'{key}_gamma2'] = rand_vec(D)
            weights[f'{key}_beta2'] = rand_vec(D)

    return weights


def _make_int8_matrix(rows, cols, flat_values):
    """Reshape a flat list of INT8 values into a 2D matrix."""
    mat = []
    idx = 0
    for r in range(rows):
        row = []
        for c in range(cols):
            row.append(int8(flat_values[idx]))
            idx += 1
        mat.append(row)
    return mat


def tiled_matmul(mat_a, mat_b, tile_size):
    """Break a full matmul into TILE_SIZE tiles, calling matmul_golden per tile.

    Matches RTL tiled execution: outer loops over output tile rows/cols,
    inner loop accumulates across full K dimension per tile.

    Args:
        mat_a: 2D list [M][K] of INT8 values
        mat_b: 2D list [K][N] of INT8 values
        tile_size: tile dimension for PE array

    Returns:
        2D list [M][N] of INT16 (saturated) values
    """
    M = len(mat_a)
    K = len(mat_a[0])
    N = len(mat_b[0])

    # Initialize output as INT16 zeros
    result = [[0] * N for _ in range(M)]

    # Tile over output rows and columns
    for ti in range(0, M, tile_size):
        rows = min(tile_size, M - ti)
        for tj in range(0, N, tile_size):
            cols = min(tile_size, N - tj)

            # Extract tile slices with full K width
            tile_a = [[int8(mat_a[ti + r][k]) for k in range(K)]
                      for r in range(rows)]
            tile_b = [[int8(mat_b[k][tj + c]) for c in range(cols)]
                      for k in range(K)]

            # matmul_golden handles INT8*INT8 -> INT32 accum -> INT16 saturate
            tile_c = matmul_golden(tile_a, tile_b, rows)

            # Write tile result
            for r in range(rows):
                for c in range(cols):
                    result[ti + r][tj + c] = tile_c[r][c]

    return result


def _transpose(mat):
    """Transpose a 2D list."""
    rows = len(mat)
    cols = len(mat[0])
    return [[mat[r][c] for r in range(rows)] for c in range(cols)]


def _int16_to_int8_matrix(mat):
    """Truncate INT16 matrix to INT8 (matches RTL BRAM read truncation)."""
    return [[int8(v) for v in row] for row in mat]


def _flatten_to_int16(mat):
    """Flatten 2D INT16 matrix to 1D list."""
    return [v for row in mat for v in row]


def transformer_forward(input_data, weights, config, skip_frontend_proj=False):
    """Full transformer forward pass matching fsm_controller.v pipeline.

    Args:
        input_data: 2D list [B*T][INPUT_DIM] of INT8 values
        weights: dict from generate_random_weights()
        config: TransformerConfig
        skip_frontend_proj: if True, treat input_data directly as INT16
            activations (sign-extend each value) and skip W_proj matmul

    Returns:
        dict of all intermediate results for validation
    """
    BT = config.BATCH * config.SEQ_LEN
    D = config.MODEL_DIM
    F = config.F_DIM
    T = config.SEQ_LEN
    H = config.NUM_HEADS
    HD = config.HEAD_DIM
    TS = config.TILE_SIZE

    intermediates = {}
    intermediates['input'] = input_data

    # =========================================================================
    # Step 1: Frontend projection (optional)
    # (B*T, INPUT_DIM) x (INPUT_DIM, MODEL_DIM) -> (B*T, MODEL_DIM) INT16
    # =========================================================================
    if skip_frontend_proj:
        x_int16 = [[int16(v) for v in row] for row in input_data]
    else:
        x_int16 = tiled_matmul(input_data, weights['W_proj'], TS)
        intermediates['frontend_proj'] = x_int16

    # =========================================================================
    # Step 2: Encoder layers
    # =========================================================================
    for layer in range(config.NUM_ENC_LAYERS):
        key = f'enc_{layer}'

        # Save residual (INT16) before attention
        residual_pre_attn = [row[:] for row in x_int16]

        # --- QKV Projections ---
        # Input to matmul must be INT8 (BRAM read truncation)
        x_int8 = _int16_to_int8_matrix(x_int16)

        Q_int16 = tiled_matmul(x_int8, weights[f'{key}_W_q'], TS)  # [BT, D]
        K_int16 = tiled_matmul(x_int8, weights[f'{key}_W_k'], TS)  # [BT, D]
        V_int16 = tiled_matmul(x_int8, weights[f'{key}_W_v'], TS)  # [BT, D]

        intermediates[f'{key}_Q'] = Q_int16
        intermediates[f'{key}_K'] = K_int16
        intermediates[f'{key}_V'] = V_int16

        # --- Per-head attention ---
        # Reshape: [BT, D] -> per head [T, HEAD_DIM] (INT8 for matmul input)
        Q_int8 = _int16_to_int8_matrix(Q_int16)
        K_int8 = _int16_to_int8_matrix(K_int16)
        V_int8 = _int16_to_int8_matrix(V_int16)

        attn_concat = [[0] * D for _ in range(BT)]

        all_scores = []
        all_probs = []

        for h in range(H):
            # Extract head slices [T, HEAD_DIM]
            q_head = [[Q_int8[t][h * HD + d] for d in range(HD)]
                      for t in range(BT)]
            k_head = [[K_int8[t][h * HD + d] for d in range(HD)]
                      for t in range(BT)]
            v_head = [[V_int8[t][h * HD + d] for d in range(HD)]
                      for t in range(BT)]

            # Attention scores: Q * K^T -> [T, T] INT16
            k_T = _transpose(k_head)
            scores = tiled_matmul(q_head, k_T, TS)  # [T, T] INT16
            all_scores.append(scores)

            # Softmax per row -> UINT8
            probs = []
            for t in range(BT):
                row_probs = softmax_golden(scores[t])
                probs.append(row_probs)
            all_probs.append(probs)

            # Softmax output is UINT8 [0,255], treated as INT8 by next matmul
            # (the matmul reads bytes from BRAM without sign distinction)
            probs_as_int8 = [[int8(p) for p in row] for row in probs]

            # Attention output: probs * V -> [T, HEAD_DIM] INT16
            attn_out = tiled_matmul(probs_as_int8, v_head, TS)

            # Place into concat buffer
            for t in range(BT):
                for d in range(HD):
                    attn_concat[t][h * HD + d] = attn_out[t][d]

        intermediates[f'{key}_attn_scores'] = all_scores
        intermediates[f'{key}_attn_probs'] = all_probs

        # --- Output projection ---
        attn_concat_int8 = _int16_to_int8_matrix(attn_concat)
        attn_proj = tiled_matmul(attn_concat_int8, weights[f'{key}_W_o'], TS)
        intermediates[f'{key}_attn_proj'] = attn_proj

        # --- Residual add (INT16 + INT16 -> INT16 saturating) ---
        x_residual = []
        for t in range(BT):
            row = residual_add_golden(residual_pre_attn[t], attn_proj[t])
            x_residual.append(row)
        intermediates[f'{key}_residual1'] = x_residual

        # --- LayerNorm 1: INT16 -> INT8 ---
        # normalize_elem returns unsigned bytes (& 0xFF); convert to signed
        x_ln1 = []
        for t in range(BT):
            normed = layernorm_golden(
                x_residual[t],
                weights[f'{key}_gamma1'],
                weights[f'{key}_beta1'],
                D
            )
            x_ln1.append([int8(v) for v in normed])
        intermediates[f'{key}_ln1'] = x_ln1

        # --- FFN1: (BT, MODEL_DIM) x (MODEL_DIM, F_DIM) -> INT16 ---
        # x_ln1 is INT8 (layernorm output, signed)
        ffn1_out = tiled_matmul(x_ln1, weights[f'{key}_W_ffn1'], TS)
        intermediates[f'{key}_ffn1'] = ffn1_out

        # --- ReLU activation: INT16 -> INT16 ---
        ffn_act = [[relu_golden(v) for v in row] for row in ffn1_out]
        intermediates[f'{key}_ffn_act'] = ffn_act

        # --- Truncate to INT8 for FFN2 matmul input (BRAM read) ---
        ffn_act_int8 = _int16_to_int8_matrix(ffn_act)

        # --- FFN2: (BT, F_DIM) x (F_DIM, MODEL_DIM) -> INT16 ---
        ffn2_out = tiled_matmul(ffn_act_int8, weights[f'{key}_W_ffn2'], TS)
        intermediates[f'{key}_ffn2'] = ffn2_out

        # Residual for FFN: LN1 output (INT8) sign-extended to INT16
        residual_pre_ffn = [[int16(v) for v in row] for row in x_ln1]

        # --- Residual add ---
        x_residual2 = []
        for t in range(BT):
            row = residual_add_golden(residual_pre_ffn[t], ffn2_out[t])
            x_residual2.append(row)
        intermediates[f'{key}_residual2'] = x_residual2

        # --- LayerNorm 2: INT16 -> INT8 ---
        x_ln2 = []
        for t in range(BT):
            normed = layernorm_golden(
                x_residual2[t],
                weights[f'{key}_gamma2'],
                weights[f'{key}_beta2'],
                D
            )
            x_ln2.append([int8(v) for v in normed])
        intermediates[f'{key}_ln2'] = x_ln2

        # Output of encoder layer is INT8 (signed); promote to INT16
        x_int16 = [[int16(v) for v in row] for row in x_ln2]

    intermediates['encoder_output'] = x_int16

    # =========================================================================
    # Step 3: Denoiser layers (self-attention only, matching current RTL)
    # =========================================================================
    for layer in range(config.NUM_DEN_LAYERS):
        key = f'den_{layer}'

        residual_pre_attn = [row[:] for row in x_int16]

        x_int8 = _int16_to_int8_matrix(x_int16)

        Q_int16 = tiled_matmul(x_int8, weights[f'{key}_W_q'], TS)
        K_int16 = tiled_matmul(x_int8, weights[f'{key}_W_k'], TS)
        V_int16 = tiled_matmul(x_int8, weights[f'{key}_W_v'], TS)

        intermediates[f'{key}_Q'] = Q_int16
        intermediates[f'{key}_K'] = K_int16
        intermediates[f'{key}_V'] = V_int16

        Q_int8 = _int16_to_int8_matrix(Q_int16)
        K_int8 = _int16_to_int8_matrix(K_int16)
        V_int8 = _int16_to_int8_matrix(V_int16)

        attn_concat = [[0] * D for _ in range(BT)]

        all_scores = []
        all_probs = []

        for h in range(H):
            q_head = [[Q_int8[t][h * HD + d] for d in range(HD)]
                      for t in range(BT)]
            k_head = [[K_int8[t][h * HD + d] for d in range(HD)]
                      for t in range(BT)]
            v_head = [[V_int8[t][h * HD + d] for d in range(HD)]
                      for t in range(BT)]

            k_T = _transpose(k_head)
            scores = tiled_matmul(q_head, k_T, TS)
            all_scores.append(scores)

            probs = []
            for t in range(BT):
                row_probs = softmax_golden(scores[t])
                probs.append(row_probs)
            all_probs.append(probs)

            probs_as_int8 = [[int8(p) for p in row] for row in probs]
            attn_out = tiled_matmul(probs_as_int8, v_head, TS)

            for t in range(BT):
                for d in range(HD):
                    attn_concat[t][h * HD + d] = attn_out[t][d]

        intermediates[f'{key}_attn_scores'] = all_scores
        intermediates[f'{key}_attn_probs'] = all_probs

        attn_concat_int8 = _int16_to_int8_matrix(attn_concat)
        attn_proj = tiled_matmul(attn_concat_int8, weights[f'{key}_W_o'], TS)
        intermediates[f'{key}_attn_proj'] = attn_proj

        x_residual = []
        for t in range(BT):
            row = residual_add_golden(residual_pre_attn[t], attn_proj[t])
            x_residual.append(row)
        intermediates[f'{key}_residual1'] = x_residual

        x_ln1 = []
        for t in range(BT):
            normed = layernorm_golden(
                x_residual[t],
                weights[f'{key}_gamma1'],
                weights[f'{key}_beta1'],
                D
            )
            x_ln1.append([int8(v) for v in normed])
        intermediates[f'{key}_ln1'] = x_ln1

        ffn1_out = tiled_matmul(x_ln1, weights[f'{key}_W_ffn1'], TS)
        intermediates[f'{key}_ffn1'] = ffn1_out

        ffn_act = [[relu_golden(v) for v in row] for row in ffn1_out]
        intermediates[f'{key}_ffn_act'] = ffn_act

        ffn_act_int8 = _int16_to_int8_matrix(ffn_act)

        ffn2_out = tiled_matmul(ffn_act_int8, weights[f'{key}_W_ffn2'], TS)
        intermediates[f'{key}_ffn2'] = ffn2_out

        residual_pre_ffn = [[int16(v) for v in row] for row in x_ln1]

        x_residual2 = []
        for t in range(BT):
            row = residual_add_golden(residual_pre_ffn[t], ffn2_out[t])
            x_residual2.append(row)
        intermediates[f'{key}_residual2'] = x_residual2

        x_ln2 = []
        for t in range(BT):
            normed = layernorm_golden(
                x_residual2[t],
                weights[f'{key}_gamma2'],
                weights[f'{key}_beta2'],
                D
            )
            x_ln2.append([int8(v) for v in normed])
        intermediates[f'{key}_ln2'] = x_ln2

        x_int16 = [[int16(v) for v in row] for row in x_ln2]

    intermediates['denoiser_output'] = x_int16
    intermediates['output'] = x_int16

    return intermediates
