// =============================================================================
// defines.vh
// =============================================================================
//
// Bitwidths:
//   Input/Weight: INT16
//   Accumulation: INT32
//   Output:       INT16

`ifndef DEFINES_VH
`define DEFINES_VH

// =============================================================================
// Transformer Parameters
// =============================================================================

`ifdef SIM_SMALL
// --- SIM_SMALL parameters (must match verify/test_top.py) ---
parameter MODEL_DIM     = 64;
parameter NUM_HEADS     = 2;
parameter HEAD_DIM      = MODEL_DIM / NUM_HEADS;   // 32
parameter F_DIM         = 128;
parameter INPUT_DIM     = 64;
parameter MAX_SEQ_LEN   = 32;
parameter MAX_BATCH     = 1;
parameter NUM_ENC_LAYERS = 1;
parameter NUM_DEN_LAYERS = 0;
parameter NUM_DIFFUSION_STEPS = 1;
`elsif SIM_1K
// --- Production dimensions, single layer (for verification) ---
// Uses full MODEL_DIM=1024 but NUM_ENC_LAYERS=1 to keep memory/sim manageable
parameter MODEL_DIM     = 1024;
parameter NUM_HEADS     = 16;
parameter HEAD_DIM      = MODEL_DIM / NUM_HEADS;   // 64
parameter F_DIM         = 4096;
parameter INPUT_DIM     = 64;
parameter MAX_SEQ_LEN   = 128;
parameter MAX_BATCH     = 4;
parameter NUM_ENC_LAYERS = 1;
parameter NUM_DEN_LAYERS = 0;
parameter NUM_DIFFUSION_STEPS = 1;
`else
// --- Production parameters (Alveo U280) ---
`define FPGA_TARGET
parameter MODEL_DIM     = 1024;
parameter NUM_HEADS     = 16;
parameter HEAD_DIM      = MODEL_DIM / NUM_HEADS;   // 64
parameter F_DIM         = 4096;
parameter INPUT_DIM     = 64;
parameter MAX_SEQ_LEN   = 128;
parameter MAX_BATCH     = 4;
parameter NUM_ENC_LAYERS = 24;
parameter NUM_DEN_LAYERS = 0;
parameter NUM_DIFFUSION_STEPS = 1;
`endif

// Attention scale: divide scores by sqrt(HEAD_DIM) via right-shift
// Production: $clog2(64)>>1 = 3 (÷8 = ÷√64, exact for GPT-2)
// SIM_SMALL:  $clog2(32)>>1 = 2 (÷4, approximation of ÷√32 ≈ 5.66)
parameter SCALE_SHIFT   = $clog2(HEAD_DIM) >> 1;

// Hardware Configuration
parameter DATA_WIDTH    = 16;           // INT16 inputs/weights
parameter ACC_WIDTH     = 32;           // INT32 accumulation
parameter ADDR_WIDTH    = 20;           // Legacy — local BRAM address width
parameter TILE_SIZE     = 32;

// Multi-Engine Configuration
parameter NUM_ENGINES   = 1;            // 1 engine for URAM prefetch debug phase

// Memory Bus Configuration
parameter BUS_WIDTH     = 256;                          // 256-bit memory bus
parameter BUS_ELEMS     = BUS_WIDTH / DATA_WIDTH;       // 16 elements per read (256/16)
parameter LOADS_PER_ROW = TILE_SIZE / BUS_ELEMS;        // 2 reads per 32-element row
parameter TILE_W        = $clog2(TILE_SIZE);            // 5 bits for 0-31

// HBM Configuration (Alveo U280: 32 channels × 256MB each)
parameter HBM_ADDR_W    = 28;           // Word-addressed, 256-bit words, covers 8GB
parameter HBM_DATA_W    = 256;          // 256-bit AXI data width (matches BUS_WIDTH)
parameter HBM_NUM_CH    = 10;           // Channels used (of 32 available)

// URAM Configuration (output accumulation buffer)
`ifdef SIM_SMALL
parameter URAM_ROWS     = 32;           // MAX_SEQ_LEN
parameter URAM_COLS     = 128;          // F_DIM
`else
parameter URAM_ROWS     = 1024;         // MODEL_DIM
parameter URAM_COLS     = 4096;         // F_DIM (widened for non-matmul URAM staging)
`endif
parameter URAM_DATA_W   = 16;           // INT16 output elements
parameter URAM_COL_WORDS = URAM_COLS / BUS_ELEMS;  // SIM_SMALL: 8, Production: 256

// Prefetch Buffer Configuration
`ifdef SIM_SMALL
parameter PREFETCH_ROWS      = 128;
parameter PREFETCH_COLS      = 128;
`else
parameter PREFETCH_ROWS      = 1024;
parameter PREFETCH_COLS      = 1024;
`endif
parameter PREFETCH_COL_WORDS = PREFETCH_COLS / BUS_ELEMS;  // SIM_SMALL: 8, Production: 64

// -----------------------------------------------------------------------------
// Architecture Selection (compile-time)
// -----------------------------------------------------------------------------
// 0 = GPT-2 Pre-Norm (LN before attention, LN before FFN)
// 1 = Post-Norm (original architecture — attention, then LN)
parameter ARCHITECTURE = 0;

// ACT_TEMP activation offset — staging area for LN output in pre-norm
// SIM_SMALL: 5 * 32 * 64 / 16 = 640.  Production: 5 * 128 * 1024 / 16 = 40960.
parameter ACT_TEMP_OFFSET = 5 * MAX_SEQ_LEN * MODEL_DIM / BUS_ELEMS;

// -----------------------------------------------------------------------------
// Step-Table Block Types (upper nibble of step entry)
// -----------------------------------------------------------------------------
localparam BT_LN     = 4'd0;    // LayerNorm (per-row loop + adapter flush)
localparam BT_QKV    = 4'd1;    // QKV matmul block (3 phases, each with URAM flush)
localparam BT_ATTN   = 4'd2;    // Attention block (per-head: score->SM->flush->out->flush)
localparam BT_MATMUL = 4'd3;    // Single matmul
localparam BT_ACT    = 4'd4;    // Activation (+ adapter flush)
localparam BT_RES    = 4'd5;    // Residual add (+ adapter flush)
localparam BT_FLUSH  = 4'd6;    // URAM->HBM flush
localparam BT_END    = 4'd15;   // End of layer program

// -----------------------------------------------------------------------------
// Step-Table FSM States
// -----------------------------------------------------------------------------
localparam S_IDLE       = 5'd0;
localparam S_DECODE     = 5'd1;
localparam S_LN_RUN     = 5'd2;   // per-row LN + adapter flush
localparam S_QKV_MM     = 5'd3;   // QKV matmul phase
localparam S_QKV_FL     = 5'd4;   // QKV URAM flush
localparam S_ATT_SCORE  = 5'd5;   // attention score matmul
localparam S_ATT_SM     = 5'd6;   // softmax (per-row loop + adapter flush)
localparam S_ATT_SM_FL  = 5'd7;   // softmax URAM->HBM flush
localparam S_ATT_OUT    = 5'd8;   // attention output matmul
localparam S_ATT_OUT_FL = 5'd9;   // attention output URAM flush
localparam S_MM_RUN     = 5'd10;  // single matmul (issue + wait)
localparam S_ACT_RUN    = 5'd11;  // activation + adapter flush
localparam S_RES_RUN    = 5'd12;  // residual + adapter flush
localparam S_UF_RUN     = 5'd13;  // standalone URAM->HBM flush
localparam S_NEXT_STEP  = 5'd14;  // advance step_idx, handle layer loop
localparam S_DONE        = 5'd15;
localparam S_OUTPUT_COPY = 5'd16;

// Legacy aliases (kept for host_interface status register compatibility)
localparam FSM_IDLE = 6'd0;
localparam FSM_DONE = 6'd15;

// -----------------------------------------------------------------------------
// Matmul Engine Ops
// -----------------------------------------------------------------------------
localparam OP_MATMUL     = 3'd0;
localparam OP_MATMUL_T   = 3'd1;        // Transposed B
localparam OP_MATVEC     = 3'd2;
localparam OP_ELEMWISE   = 3'd3;
localparam OP_MATMUL_AA  = 3'd4;        // Act BRAM x Act BRAM

`endif
