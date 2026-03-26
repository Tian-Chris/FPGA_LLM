// =============================================================================
// fsm_controller.v - Step-Table FSM for Transformer Inference
// =============================================================================
//
// Modular step-table architecture: the layer program is a localparam array
// selected by ARCHITECTURE parameter. Adding a new architecture = defining
// a new step table only.
//
// Step table format (8 bits per entry):
//   [7:4] block_type  — which executor to run
//   [3:0] config_id   — selects parameters within that block type
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module fsm_controller #(
    parameter DIM_W          = 16,
    parameter MODEL_DIM      = 1024,
    parameter INPUT_DIM      = 64,
    parameter F_DIM          = 4096,
    parameter NUM_HEADS      = 8,
    parameter MAX_SEQ_LEN    = 128,
    parameter NUM_DIFF_STEPS = 50,
    parameter TILE_SIZE      = 32,
    parameter SINGLE_MATMUL  = 0,
    parameter ARCH           = 0        // 0=GPT2_PRENORM, 1=POSTNORM
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Host interface
    input  wire                     start,
    input  wire [DIM_W-1:0]         batch_size,
    input  wire [DIM_W-1:0]         seq_len,
    input  wire                     decode_mode,
    input  wire [DIM_W-1:0]         cache_len,
    input  wire [DIM_W-1:0]         num_layers,
    (* mark_debug = "true" *) output reg                      done,
    (* mark_debug = "true" *) output reg                      busy,

    // HBM base addresses (from host_interface)
    input  wire [HBM_ADDR_W-1:0]   weight_base,
    input  wire [HBM_ADDR_W-1:0]   act_base,
    input  wire [HBM_ADDR_W-1:0]   kv_base,
    input  wire [HBM_ADDR_W-1:0]   output_base,

    // Matmul / tiling_engine command interface
    (* mark_debug = "true" *) output reg                      mm_cmd_valid,
    output reg  [2:0]               mm_cmd_op,
    output reg  [DIM_W-1:0]         mm_cmd_m,
    output reg  [DIM_W-1:0]         mm_cmd_k,
    output reg  [DIM_W-1:0]         mm_cmd_n,
    output reg  [HBM_ADDR_W-1:0]   mm_cmd_a_base,
    output reg  [HBM_ADDR_W-1:0]   mm_cmd_b_base,
    output reg  [HBM_ADDR_W-1:0]   mm_cmd_a_stride,
    output reg  [HBM_ADDR_W-1:0]   mm_cmd_b_stride,
    output reg  [7:0]               mm_cmd_out_col_offset,
    output reg                      mm_cmd_has_bias,
    output reg  [HBM_ADDR_W-1:0]   mm_cmd_bias_base,
    output reg  [DIM_W-1:0]         mm_cmd_bias_words,
    (* mark_debug = "true" *) input  wire                     mm_cmd_ready,
    (* mark_debug = "true" *) input  wire                     mm_cmd_done,

    // URAM flush control
    (* mark_debug = "true" *) output reg                      uram_flush_start,
    output reg  [9:0]               uram_flush_num_rows,
    output reg  [7:0]               uram_flush_num_col_words,
    output reg  [7:0]               uram_flush_start_col,
    output reg  [HBM_ADDR_W-1:0]   uram_flush_hbm_base,
    output reg  [HBM_ADDR_W-1:0]   uram_flush_hbm_stride,
    (* mark_debug = "true" *) input  wire                     uram_flush_done,

    // Non-matmul adapter control
    output reg  [3:0]               nm_cfg_col_bits,
    output reg                      nm_adapter_flush,
    (* mark_debug = "true" *) input  wire                     nm_adapter_flush_done,
    output reg  [NM_ADDR_W-1:0]     nm_addr_offset,

    // act_dma base address control
    output reg  [HBM_ADDR_W-1:0]   act_dma_rd_base,
    output reg  [HBM_ADDR_W-1:0]   act_dma_wr_base,
    output reg                      act_dma_flush,
    input  wire                     act_dma_flush_done,

    // Softmax controller interface
    output reg                      sm_start,
    output reg  [DIM_W-1:0]         sm_seq_len,
    output reg  [DIM_W-1:0]         sm_row_idx,
    output reg  [15:0]              sm_scale_factor,
    (* mark_debug = "true" *) input  wire                     sm_done,
    input  wire                     sm_busy,

    // LayerNorm controller interface
    output reg                      ln_start,
    output reg  [DIM_W-1:0]         ln_dim,
    (* mark_debug = "true" *) input  wire                     ln_done,
    input  wire                     ln_busy,

    // Activation unit interface
    output reg                      act_start,
    output reg  [DIM_W-1:0]         act_dim,
    (* mark_debug = "true" *) input  wire                     act_done,
    input  wire                     act_busy,

    // Residual add interface
    output reg                      res_start,
    output reg  [DIM_W-1:0]         res_dim,
    (* mark_debug = "true" *) input  wire                     res_done,
    input  wire                     res_busy,

    // Quantization layer interface
    output reg                      quant_start,
    output reg  [DIM_W-1:0]         quant_dim,
    output reg  [HBM_ADDR_W-1:0]   quant_src_base,
    output reg  [HBM_ADDR_W-1:0]   quant_dst_base,
    input  wire                     quant_done,

    // Debug/status outputs
    output reg  [5:0]               current_state,
    output reg  [DIM_W-1:0]         current_layer,

    // Diagnostic test controls
    input  wire [DIM_W-1:0]         max_steps,
    input  wire [3:0]               test_mode,

    // Test injection: nm_adapter scalar write (active when test_mode != 0)
    output reg                      test_wr_en,
    output reg  [NM_ADDR_W-1:0]    test_wr_addr,
    output reg  [DATA_WIDTH-1:0]    test_wr_data,

    // Test injection: act_dma scalar read (active when test_mode != 0)
    output reg                      test_dma_rd_en,
    output reg  [15:0]              test_dma_rd_addr,
    input  wire [DATA_WIDTH-1:0]    test_dma_rd_data,
    input  wire                     test_dma_rd_valid,

    // Debug trace to HBM
    input  wire [HBM_ADDR_W-1:0]   debug_base,
    output reg                      dbg_wr_valid,
    output reg  [HBM_ADDR_W-1:0]   dbg_wr_addr,
    output reg  [255:0]             dbg_wr_data,
    input  wire                     dbg_wr_done,
    input  wire                     dbg_wr_busy,

    // URAM checkpoint read (post-layer activation dump to debug trace)
    output reg                      chk_uram_rd_en,
    output reg  [9:0]               chk_uram_rd_row,
    output reg  [7:0]               chk_uram_rd_col,
    input  wire [255:0]             chk_uram_rd_data,
    input  wire                     chk_uram_rd_valid
);

    // =====================================================================
    // HBM Weight Memory Layout (word-addressed, 256-bit words)
    // =====================================================================
    localparam WE = BUS_ELEMS;  // 16 elements per 256-bit word

    // Per-layer weight offsets
    localparam LAYER_WQ_OFFSET   = 0;
    localparam LAYER_WK_OFFSET   = MODEL_DIM * MODEL_DIM / WE;
    localparam LAYER_WV_OFFSET   = 2 * MODEL_DIM * MODEL_DIM / WE;
    localparam LAYER_WO_OFFSET   = 3 * MODEL_DIM * MODEL_DIM / WE;
    localparam LAYER_FFN1_OFFSET = 4 * MODEL_DIM * MODEL_DIM / WE;
    localparam LAYER_FFN2_OFFSET = LAYER_FFN1_OFFSET + MODEL_DIM * F_DIM / WE;
    localparam LAYER_LN1_OFFSET  = LAYER_FFN2_OFFSET + F_DIM * MODEL_DIM / WE;
    localparam LAYER_LN2_OFFSET  = LAYER_LN1_OFFSET + 2 * MODEL_DIM / WE;

    // Per-layer bias offsets (appended after LN2 params)
    localparam LAYER_BIAS_QKV_OFFSET  = LAYER_LN2_OFFSET + 2 * MODEL_DIM / WE;
    localparam LAYER_BIAS_PROJ_OFFSET = LAYER_BIAS_QKV_OFFSET + 3 * MODEL_DIM / WE;
    localparam LAYER_BIAS_FFN1_OFFSET = LAYER_BIAS_PROJ_OFFSET + MODEL_DIM / WE;
    localparam LAYER_BIAS_FFN2_OFFSET = LAYER_BIAS_FFN1_OFFSET + F_DIM / WE;
    localparam LAYER_SIZE             = LAYER_BIAS_FFN2_OFFSET + MODEL_DIM / WE;

    // Row strides
    localparam MODEL_STRIDE = MODEL_DIM / WE;
    localparam F_STRIDE     = F_DIM / WE;

    // =====================================================================
    // HBM Activation Memory Layout
    // =====================================================================
    localparam ACT_EMBED_OFFSET  = 0;
    localparam ACT_Q_OFFSET      = MAX_SEQ_LEN * MODEL_DIM / WE;
    localparam ACT_ATTN_OFFSET   = 4 * MAX_SEQ_LEN * MODEL_DIM / WE;
    localparam ACT_TEMP_OFF      = 5 * MAX_SEQ_LEN * MODEL_DIM / WE;
    localparam ACT_FFN_OFFSET    = ACT_Q_OFFSET;  // reuse Q space (free after attention)

    // URAM flush geometry (count-1 semantics)
    localparam URAM_MODEL_COLS_M1 = MODEL_DIM / WE - 1;
    localparam URAM_F_COLS_M1     = F_DIM / WE - 1;

    // cfg_col_bits values
    localparam CFG_COL_SEQ  = $clog2(MAX_SEQ_LEN);
    localparam CFG_COL_MOD  = $clog2(MODEL_DIM);
    localparam CFG_COL_FFN  = $clog2(F_DIM);

    // Head dimension constants
    localparam HEAD_DIM_PARAM = MODEL_DIM / NUM_HEADS;
    localparam HEAD_WORDS = HEAD_DIM_PARAM / WE;

    // =====================================================================
    // Step Table
    // =====================================================================
    // Max 16 steps per layer program. Each entry is 8 bits: {block_type[3:0], config_id[3:0]}
    localparam MAX_STEPS = 16;

    // GPT-2 Pre-Norm program (16 steps)
    localparam [8*MAX_STEPS-1:0] PROG_PRENORM = {
        {BT_END,    4'd0},   // step 15
        {BT_FLUSH,  4'd0},   // step 14: flush res2 -> ACT_EMBED
        {BT_RES,    4'd0},   // step 13: residual2
        {BT_MATMUL, 4'd3},   // step 12: FFN2
        {BT_FLUSH,  4'd2},   // step 11: flush act -> ACT_FFN
        {BT_ACT,    4'd0},   // step 10: ReLU
        {BT_MATMUL, 4'd2},   // step 9:  FFN1 (read from ACT_TEMP)
        {BT_FLUSH,  4'd1},   // step 8:  flush LN2 -> ACT_TEMP
        {BT_LN,     4'd1},   // step 7:  LN2
        {BT_FLUSH,  4'd0},   // step 6:  flush res1 -> ACT_EMBED
        {BT_RES,    4'd0},   // step 5:  residual1
        {BT_MATMUL, 4'd0},   // step 4:  output projection
        {BT_ATTN,   4'd0},   // step 3:  attention block
        {BT_QKV,    4'd1},   // step 2:  QKV (read from ACT_TEMP)
        {BT_FLUSH,  4'd1},   // step 1:  flush LN1 -> ACT_TEMP
        {BT_LN,     4'd0}    // step 0:  LN1
    };

    // Post-Norm program (13 steps, padded to 16)
    localparam [8*MAX_STEPS-1:0] PROG_POSTNORM = {
        {BT_END,    4'd0},   // step 15 (pad)
        {BT_END,    4'd0},   // step 14 (pad)
        {BT_END,    4'd0},   // step 13 (pad)
        {BT_END,    4'd0},   // step 12: end
        {BT_FLUSH,  4'd0},   // step 11: flush res2 -> EMBED
        {BT_RES,    4'd0},   // step 10: residual2
        {BT_MATMUL, 4'd3},   // step 9:  FFN2
        {BT_FLUSH,  4'd2},   // step 8:  flush act -> FFN
        {BT_ACT,    4'd0},   // step 7:  activation
        {BT_MATMUL, 4'd1},   // step 6:  FFN1 (read from EMBED)
        {BT_FLUSH,  4'd0},   // step 5:  flush LN1 -> EMBED
        {BT_LN,     4'd0},   // step 4:  LN1
        {BT_RES,    4'd0},   // step 3:  residual1
        {BT_MATMUL, 4'd0},   // step 2:  proj
        {BT_ATTN,   4'd0},   // step 1:  attention block
        {BT_QKV,    4'd0}    // step 0:  QKV (read from ACT_EMBED)
    };

    // Select program based on ARCH parameter
    localparam [8*MAX_STEPS-1:0] PROGRAM = (ARCH == 0) ? PROG_PRENORM : PROG_POSTNORM;

    // Extract step entry: step_table[i] = PROGRAM[i*8 +: 8]
    // We use step_idx to index into the program

    // =====================================================================
    // Internal Registers
    // =====================================================================
    (* mark_debug = "true" *) reg [4:0] state;

    reg [DIM_W-1:0] batch_r, seq_r;
    (* mark_debug = "true" *) reg              decode_r;
    reg [DIM_W-1:0]  cache_len_r;
    reg [DIM_W-1:0]  num_layers_r;
    (* mark_debug = "true" *) reg [DIM_W-1:0] layer_cnt;

    // Debug trace registers
    reg [31:0]       dbg_cycle_cnt;
    reg [DIM_W-1:0]  dbg_write_idx;
    reg [HBM_ADDR_W-1:0] dbg_base_r;
    reg              dbg_pending;   // 1 = waiting for debug write to complete

    // Checkpoint dump registers
    reg [2:0]        chk_col_idx;   // 0-3: which URAM col word to read
    reg              chk_rd_issued; // 1 = waiting for URAM rd_valid
    reg              chk_data_valid;// 1 = URAM data captured, ready to write
    reg [255:0]      chk_data_r;   // captured URAM read data
    (* mark_debug = "true" *) reg [3:0]       step_idx;
    (* mark_debug = "true" *) reg [3:0]       step_bt;      // block type from decoded step
    reg [3:0]       step_cfg;     // config id from decoded step
    (* mark_debug = "true" *) reg [1:0]       qkv_phase;
    (* mark_debug = "true" *) reg              waiting_mm;
    (* mark_debug = "true" *) reg              nm_flush_phase;
    (* mark_debug = "true" *) reg [DIM_W-1:0]  nm_row_cnt;
    (* mark_debug = "true" *) reg [DIM_W-1:0]  head_cnt;
    reg              flush_sent;

    `ifdef STEP_DEBUG
    reg              step_dbg_flush_sent;
    reg [HBM_ADDR_W-1:0] step_dbg_offset;   // running offset into output region
    reg [HBM_ADDR_W-1:0] step_dbg_stride;   // bt * MODEL_STRIDE (precomputed)
    `endif

    // Diagnostic test registers
    reg [DIM_W-1:0]      max_steps_r;
    reg [3:0]            test_mode_r;
    reg [DIM_W-1:0]      step_cnt;         // total steps executed (for max_steps)
    reg [DIM_W-1:0]      test_cnt;         // generic counter for test loops
    reg [15:0]           test_latency_cnt; // cycle counter for latency probe
    reg [2:0]            test_phase;       // sub-state within test states
    reg [3:0]            test_row_idx;     // which row we're testing (multi-row)

    // Computed values
    wire [DIM_W-1:0] bt = batch_r * seq_r;
    wire [HBM_ADDR_W-1:0] layer_wgt_base = weight_base + layer_cnt * LAYER_SIZE;

    // Per-layer KV cache addressing
    localparam KV_V_OFFSET   = MAX_SEQ_LEN * MODEL_DIM / WE;
    localparam KV_LAYER_SIZE = 2 * MAX_SEQ_LEN * MODEL_DIM / WE;
    wire [HBM_ADDR_W-1:0] layer_kv_base = kv_base + layer_cnt * KV_LAYER_SIZE;

    // Ceiling division: seq_r in 256-bit HBM words (handles seq_r < WE)
    wire [DIM_W-1:0] seq_words = (seq_r + WE - 1) >> $clog2(WE);

    // Decode-mode derived values
    wire [DIM_W-1:0] cache_total = cache_len_r + 1;            // includes new token
    wire [DIM_W-1:0] cache_total_words = (cache_total + WE - 1) >> $clog2(WE);

    // Flush destination after matmul
    reg [HBM_ADDR_W-1:0]  flush_hbm_base;
    reg [HBM_ADDR_W-1:0]  flush_hbm_stride;
    reg [9:0]              flush_num_rows;
    reg [7:0]              flush_num_col_words;
    reg [7:0]              flush_start_col;

    // Step table decode — extract 8-bit entry from flat bitvector
    wire [7:0] step_entry = PROGRAM[step_idx * 8 +: 8];

    // =====================================================================
    // Main FSM
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            busy             <= 1'b0;
            done             <= 1'b0;
            mm_cmd_valid     <= 1'b0;
            mm_cmd_op        <= 3'd0;
            mm_cmd_m         <= {DIM_W{1'b0}};
            mm_cmd_k         <= {DIM_W{1'b0}};
            mm_cmd_n         <= {DIM_W{1'b0}};
            mm_cmd_a_base    <= {HBM_ADDR_W{1'b0}};
            mm_cmd_b_base    <= {HBM_ADDR_W{1'b0}};
            mm_cmd_a_stride  <= {HBM_ADDR_W{1'b0}};
            mm_cmd_b_stride  <= {HBM_ADDR_W{1'b0}};
            mm_cmd_out_col_offset <= 8'd0;
            mm_cmd_has_bias  <= 1'b0;
            mm_cmd_bias_base <= {HBM_ADDR_W{1'b0}};
            mm_cmd_bias_words <= {DIM_W{1'b0}};
            uram_flush_start <= 1'b0;
            uram_flush_num_rows      <= 10'd0;
            uram_flush_num_col_words <= 8'd0;
            uram_flush_start_col     <= 8'd0;
            uram_flush_hbm_base      <= {HBM_ADDR_W{1'b0}};
            uram_flush_hbm_stride    <= {HBM_ADDR_W{1'b0}};
            nm_cfg_col_bits  <= 4'd10;
            nm_adapter_flush <= 1'b0;
            nm_addr_offset   <= {NM_ADDR_W{1'b0}};
            nm_row_cnt       <= {DIM_W{1'b0}};
            act_dma_rd_base  <= {HBM_ADDR_W{1'b0}};
            act_dma_wr_base  <= {HBM_ADDR_W{1'b0}};
            act_dma_flush    <= 1'b0;
            sm_start         <= 1'b0;
            sm_row_idx       <= {DIM_W{1'b0}};
            sm_scale_factor  <= 16'd0;
            ln_start         <= 1'b0;
            act_start        <= 1'b0;
            res_start        <= 1'b0;
            quant_start      <= 1'b0;
            sm_seq_len       <= {DIM_W{1'b0}};
            ln_dim           <= {DIM_W{1'b0}};
            act_dim          <= {DIM_W{1'b0}};
            res_dim          <= {DIM_W{1'b0}};
            quant_dim        <= {DIM_W{1'b0}};
            quant_src_base   <= {HBM_ADDR_W{1'b0}};
            quant_dst_base   <= {HBM_ADDR_W{1'b0}};
            layer_cnt        <= {DIM_W{1'b0}};
            step_idx         <= 4'd0;
            step_bt          <= 4'd0;
            step_cfg         <= 4'd0;
            qkv_phase        <= 2'd0;
            decode_r         <= 1'b0;
            cache_len_r      <= {DIM_W{1'b0}};
            num_layers_r     <= {DIM_W{1'b0}};
            dbg_cycle_cnt    <= 32'd0;
            dbg_write_idx    <= {DIM_W{1'b0}};
            dbg_base_r       <= {HBM_ADDR_W{1'b0}};
            dbg_wr_valid     <= 1'b0;
            dbg_wr_addr      <= {HBM_ADDR_W{1'b0}};
            dbg_wr_data      <= 256'd0;
            dbg_pending      <= 1'b0;
            chk_uram_rd_en   <= 1'b0;
            chk_uram_rd_row  <= 10'd0;
            chk_uram_rd_col  <= 8'd0;
            chk_col_idx      <= 3'd0;
            chk_rd_issued    <= 1'b0;
            chk_data_valid   <= 1'b0;
            chk_data_r       <= 256'd0;
            waiting_mm       <= 1'b0;
            nm_flush_phase   <= 1'b0;
            head_cnt         <= {DIM_W{1'b0}};
            flush_sent       <= 1'b0;
            `ifdef STEP_DEBUG
            step_dbg_flush_sent <= 1'b0;
            step_dbg_offset     <= {HBM_ADDR_W{1'b0}};
            step_dbg_stride     <= {HBM_ADDR_W{1'b0}};
            `endif
            // Diagnostic test resets
            max_steps_r      <= {DIM_W{1'b0}};
            test_mode_r      <= 4'd0;
            step_cnt         <= {DIM_W{1'b0}};
            test_cnt         <= {DIM_W{1'b0}};
            test_latency_cnt <= 16'd0;
            test_phase       <= 3'd0;
            test_row_idx     <= 4'd0;
            test_wr_en       <= 1'b0;
            test_wr_addr     <= {NM_ADDR_W{1'b0}};
            test_wr_data     <= {DATA_WIDTH{1'b0}};
            test_dma_rd_en   <= 1'b0;
            test_dma_rd_addr <= 16'd0;
            flush_hbm_base   <= {HBM_ADDR_W{1'b0}};
            flush_hbm_stride <= {HBM_ADDR_W{1'b0}};
            flush_num_rows   <= 10'd0;
            flush_num_col_words <= 8'd0;
            flush_start_col  <= 8'd0;
            current_state    <= 6'd0;
            current_layer    <= {DIM_W{1'b0}};
        end else begin
            // Cycle counter (runs while busy)
            if (busy) dbg_cycle_cnt <= dbg_cycle_cnt + 32'd1;

            // Default: clear one-shot signals
            done             <= 1'b0;
            mm_cmd_valid     <= 1'b0;
            dbg_wr_valid     <= 1'b0;
            sm_start         <= 1'b0;
            ln_start         <= 1'b0;
            act_start        <= 1'b0;
            res_start        <= 1'b0;
            quant_start      <= 1'b0;
            uram_flush_start <= 1'b0;
            nm_adapter_flush <= 1'b0;
            act_dma_flush    <= 1'b0;
            chk_uram_rd_en   <= 1'b0;
            test_wr_en       <= 1'b0;
            test_dma_rd_en   <= 1'b0;

            // Debug
            current_state <= {1'b0, state};
            current_layer <= layer_cnt;

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy        <= 1'b1;
                        batch_r     <= batch_size;
                        seq_r       <= seq_len;
                        decode_r    <= decode_mode;
                        cache_len_r <= cache_len;
                        num_layers_r <= num_layers;
                        dbg_base_r   <= debug_base;
                        dbg_cycle_cnt <= 32'd0;
                        dbg_write_idx <= {DIM_W{1'b0}};
                        layer_cnt   <= {DIM_W{1'b0}};
                        step_idx  <= 4'd0;
                        qkv_phase <= 2'd0;
                        head_cnt       <= {DIM_W{1'b0}};
                        nm_row_cnt     <= {DIM_W{1'b0}};
                        nm_addr_offset <= {NM_ADDR_W{1'b0}};
                        `ifdef STEP_DEBUG
                        step_dbg_flush_sent <= 1'b0;
                        step_dbg_offset     <= {HBM_ADDR_W{1'b0}};
                        step_dbg_stride     <= batch_size * seq_len * MODEL_STRIDE;
                        `endif
                        // Diagnostic test registers
                        max_steps_r  <= max_steps;
                        test_mode_r  <= test_mode;
                        step_cnt     <= {DIM_W{1'b0}};
                        test_cnt     <= {DIM_W{1'b0}};
                        test_phase   <= 3'd0;
                        test_row_idx <= 4'd0;
                        // Branch: test mode or normal operation
                        state <= (test_mode != 4'd0) ? S_TEST_DISPATCH : S_DECODE;
                        // synthesis translate_off
                        $display("[FSM %0t] START: batch=%0d seq=%0d decode=%0d cache_len=%0d",
                                 $time, batch_size, seq_len, decode_mode, cache_len);
                        // synthesis translate_on
                    end
                end

                // ---------------------------------------------------------
                // DECODE: read step table entry, dispatch to executor
                // ---------------------------------------------------------
                S_DECODE: begin
                    step_bt  <= step_entry[7:4];
                    step_cfg <= step_entry[3:0];
                    // synthesis translate_off
                    $display("[FSM %0t] DECODE step[%0d]: bt=%0d cfg=%0d",
                             $time, step_idx, step_entry[7:4], step_entry[3:0]);
                    // synthesis translate_on
                    case (step_entry[7:4])
                        BT_LN:     state <= S_LN_RUN;
                        BT_QKV:    begin state <= S_QKV_MM; qkv_phase <= 2'd0; end
                        BT_ATTN:   begin state <= S_ATT_SCORE; head_cnt <= {DIM_W{1'b0}}; end
                        BT_MATMUL: state <= S_MM_RUN;
                        BT_ACT:    state <= S_ACT_RUN;
                        BT_RES:    state <= S_RES_RUN;
                        BT_FLUSH:  state <= S_UF_RUN;
                        BT_END:    state <= S_NEXT_STEP;
                        default:   state <= S_NEXT_STEP;
                    endcase
                end

                // ---------------------------------------------------------
                // LayerNorm executor (per-row loop + adapter flush)
                // config: 0=LN1_params, 1=LN2_params
                // ---------------------------------------------------------
                S_LN_RUN: begin
                    if (!nm_flush_phase) begin
                        if (!ln_start && !ln_done && !ln_busy) begin
                            nm_cfg_col_bits <= CFG_COL_MOD;
                            nm_addr_offset  <= nm_row_cnt * MODEL_DIM;
                            case (step_cfg)
                                4'd0: act_dma_rd_base <= layer_wgt_base + LAYER_LN1_OFFSET;
                                default: act_dma_rd_base <= layer_wgt_base + LAYER_LN2_OFFSET;
                            endcase
                            ln_start <= 1'b1;
                            ln_dim   <= MODEL_DIM;
                            // synthesis translate_off
                            $display("[FSM %0t] LN_RUN: row=%0d/%0d dim=%0d", $time, nm_row_cnt, bt, MODEL_DIM);
                            // synthesis translate_on
                        end
                        if (ln_done) begin
                            // synthesis translate_off
                            $display("[FSM %0t] LN_DONE: row=%0d", $time, nm_row_cnt);
                            // synthesis translate_on
                            if (nm_row_cnt == bt - 1) begin
                                nm_row_cnt     <= {DIM_W{1'b0}};
                                nm_addr_offset <= {NM_ADDR_W{1'b0}};
                                nm_flush_phase <= 1'b1;
                            end else begin
                                nm_row_cnt <= nm_row_cnt + 1;
                            end
                        end
                    end else begin
                        if (!nm_adapter_flush && !nm_adapter_flush_done) begin
                            nm_adapter_flush <= 1'b1;
                        end
                        if (nm_adapter_flush_done) begin
                            nm_flush_phase <= 1'b0;
                            state <= S_NEXT_STEP;
                        end
                    end
                end

                // ---------------------------------------------------------
                // QKV matmul executor (3 phases, each with URAM flush)
                // config: 0=read from ACT_EMBED, 1=read from ACT_TEMP
                // ---------------------------------------------------------
                S_QKV_MM: begin
                    if (mm_cmd_ready && !mm_cmd_valid && !waiting_mm) begin
                        // synthesis translate_off
                        $display("[FSM %0t] QKV_MM ISSUED: phase=%0d m=%0d k=%0d n=%0d layer=%0d cache_len_r=%0d layer_kv_base=0x%08h",
                                 $time, qkv_phase, bt, MODEL_DIM, MODEL_DIM,
                                 layer_cnt, cache_len_r, layer_kv_base);
                        // synthesis translate_on
                        mm_cmd_valid   <= 1'b1;
                        mm_cmd_op      <= OP_MATMUL;
                        mm_cmd_m       <= bt;
                        mm_cmd_k       <= MODEL_DIM;
                        mm_cmd_n       <= MODEL_DIM;
                        case (step_cfg)
                            4'd0: mm_cmd_a_base <= act_base + ACT_EMBED_OFFSET;
                            default: mm_cmd_a_base <= act_base + ACT_TEMP_OFF;
                        endcase
                        mm_cmd_a_stride <= MODEL_STRIDE;
                        mm_cmd_b_stride <= MODEL_STRIDE;
                        mm_cmd_out_col_offset <= 8'd0;
                        case (qkv_phase)
                            2'd0: mm_cmd_b_base <= layer_wgt_base + LAYER_WQ_OFFSET;
                            2'd1: mm_cmd_b_base <= layer_wgt_base + LAYER_WK_OFFSET;
                            default: mm_cmd_b_base <= layer_wgt_base + LAYER_WV_OFFSET;
                        endcase
                        // Bias: QKV bias split per phase (Q=0..1023, K=1024..2047, V=2048..3071)
                        mm_cmd_has_bias   <= 1'b1;
                        mm_cmd_bias_words <= MODEL_DIM / WE;
                        case (qkv_phase)
                            2'd0: mm_cmd_bias_base <= layer_wgt_base + LAYER_BIAS_QKV_OFFSET;
                            2'd1: mm_cmd_bias_base <= layer_wgt_base + LAYER_BIAS_QKV_OFFSET + MODEL_DIM / WE;
                            default: mm_cmd_bias_base <= layer_wgt_base + LAYER_BIAS_QKV_OFFSET + 2 * MODEL_DIM / WE;
                        endcase
                        case (qkv_phase)
                            2'd0: flush_hbm_base <= act_base + ACT_Q_OFFSET;
                            2'd1: flush_hbm_base <= layer_kv_base
                                                  + (decode_r ? cache_len_r * MODEL_STRIDE : {HBM_ADDR_W{1'b0}});
                            default: flush_hbm_base <= layer_kv_base + KV_V_OFFSET
                                                     + (decode_r ? cache_len_r * MODEL_STRIDE : {HBM_ADDR_W{1'b0}});
                        endcase
                        flush_hbm_stride    <= MODEL_STRIDE;
                        flush_num_rows      <= bt - 1;
                        flush_num_col_words <= URAM_MODEL_COLS_M1;
                        flush_start_col     <= 8'd0;
                        waiting_mm          <= 1'b1;
                    end
                    if (mm_cmd_done && waiting_mm) begin
                        // synthesis translate_off
                        $display("[FSM %0t] QKV_MM DONE: phase=%0d", $time, qkv_phase);
                        // synthesis translate_on
                        waiting_mm <= 1'b0;
                        state      <= S_QKV_FL;
                    end
                end

                // Flush URAM->HBM after QKV matmul
                S_QKV_FL: begin
                    if (!flush_sent && !uram_flush_done) begin
                        uram_flush_start     <= 1'b1;
                        flush_sent           <= 1'b1;
                        uram_flush_num_rows  <= flush_num_rows;
                        uram_flush_num_col_words <= flush_num_col_words;
                        uram_flush_start_col     <= flush_start_col;
                        uram_flush_hbm_base  <= flush_hbm_base;
                        uram_flush_hbm_stride <= flush_hbm_stride;
                    end
                    if (uram_flush_done) begin
                        flush_sent <= 1'b0;
                        if (SINGLE_MATMUL) begin
                            state <= S_DONE;
                        end else if (qkv_phase < 2'd2) begin
                            qkv_phase <= qkv_phase + 1;
                            state     <= S_QKV_MM;
                        end else begin
                            qkv_phase <= 2'd0;
                            state     <= S_NEXT_STEP;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Attention Score: Q * K^T -> (T, T)
                // ---------------------------------------------------------
                S_ATT_SCORE: begin
                    if (mm_cmd_ready && !mm_cmd_valid && !waiting_mm) begin
                        mm_cmd_valid    <= 1'b1;
                        mm_cmd_op       <= OP_MATMUL_T;
                        mm_cmd_m        <= decode_r ? 16'd1 : seq_r;
                        mm_cmd_k        <= HEAD_DIM_PARAM;
                        mm_cmd_n        <= decode_r ? cache_total : seq_r;
                        mm_cmd_a_base   <= act_base + ACT_Q_OFFSET + head_cnt * HEAD_WORDS;
                        mm_cmd_b_base   <= layer_kv_base + head_cnt * HEAD_WORDS;
                        mm_cmd_a_stride <= MODEL_STRIDE;
                        mm_cmd_b_stride <= MODEL_STRIDE;
                        mm_cmd_out_col_offset <= 8'd0;
                        mm_cmd_has_bias <= 1'b0;
                        flush_hbm_base      <= act_base + ACT_ATTN_OFFSET;
                        flush_hbm_stride    <= decode_r ? cache_total_words : seq_words;
                        flush_num_rows      <= decode_r ? 10'd0 : (seq_r - 1);
                        flush_num_col_words <= decode_r ? (cache_total_words - 1) : (seq_words - 1);
                        flush_start_col     <= 8'd0;
                        waiting_mm <= 1'b1;
                    end
                    if (mm_cmd_done && waiting_mm) begin
                        waiting_mm <= 1'b0;
                        state      <= S_ATT_SM;
                    end
                end

                // ---------------------------------------------------------
                // Softmax (per-row loop + adapter flush)
                // ---------------------------------------------------------
                S_ATT_SM: begin
                    if (!nm_flush_phase) begin
                        if (!sm_start && !sm_done && !sm_busy) begin
                            nm_cfg_col_bits <= CFG_COL_SEQ;
                            // Offset must align with 2^cfg_col_bits (URAM row boundary),
                            // not the logical seq_r. The matmul stores each score row in
                            // its own URAM row, so the adapter stride must match col_bits.
                            // Decode mode has only 1 row (nm_row_cnt=0), so offset=0.
                            nm_addr_offset  <= decode_r ? {NM_ADDR_W{1'b0}}
                                             : (nm_row_cnt << CFG_COL_SEQ);
                            sm_start       <= 1'b1;
                            sm_seq_len     <= decode_r ? cache_total : seq_r;
                            sm_row_idx     <= decode_r ? cache_len_r : nm_row_cnt;
                            sm_scale_factor <= SCALE_FACTOR;
                        end
                        if (sm_done) begin
                            if (nm_row_cnt == bt - 1) begin
                                nm_row_cnt     <= {DIM_W{1'b0}};
                                nm_addr_offset <= {NM_ADDR_W{1'b0}};
                                nm_flush_phase <= 1'b1;
                            end else begin
                                nm_row_cnt <= nm_row_cnt + 1;
                            end
                        end
                    end else begin
                        if (!nm_adapter_flush && !nm_adapter_flush_done) begin
                            nm_adapter_flush <= 1'b1;
                        end
                        if (nm_adapter_flush_done) begin
                            nm_flush_phase <= 1'b0;
                            state <= S_ATT_SM_FL;
                        end
                    end
                end

                // URAM->HBM flush (softmax result)
                S_ATT_SM_FL: begin
                    if (!flush_sent && !uram_flush_done) begin
                        uram_flush_start         <= 1'b1;
                        flush_sent               <= 1'b1;
                        uram_flush_num_rows      <= flush_num_rows;
                        uram_flush_num_col_words <= flush_num_col_words;
                        uram_flush_start_col     <= flush_start_col;
                        uram_flush_hbm_base      <= flush_hbm_base;
                        uram_flush_hbm_stride    <= flush_hbm_stride;
                    end
                    if (uram_flush_done) begin
                        flush_sent <= 1'b0;
                        state <= S_ATT_OUT;
                    end
                end

                // ---------------------------------------------------------
                // Attention Output: scores * V -> (T, HEAD_DIM)
                // ---------------------------------------------------------
                S_ATT_OUT: begin
                    if (mm_cmd_ready && !mm_cmd_valid && !waiting_mm) begin
                        mm_cmd_valid    <= 1'b1;
                        mm_cmd_op       <= OP_MATMUL_AA;
                        mm_cmd_m        <= decode_r ? 16'd1 : seq_r;
                        mm_cmd_k        <= decode_r ? cache_total : seq_r;
                        mm_cmd_n        <= HEAD_DIM_PARAM;
                        mm_cmd_a_base   <= act_base + ACT_ATTN_OFFSET;
                        mm_cmd_b_base   <= layer_kv_base + KV_V_OFFSET + head_cnt * HEAD_WORDS;
                        mm_cmd_a_stride <= decode_r ? cache_total_words : seq_words;
                        mm_cmd_b_stride <= MODEL_STRIDE;
                        mm_cmd_out_col_offset <= head_cnt * HEAD_WORDS;
                        mm_cmd_has_bias <= 1'b0;
                        flush_hbm_base      <= act_base + ACT_Q_OFFSET + head_cnt * HEAD_WORDS;
                        flush_hbm_stride    <= MODEL_STRIDE;
                        flush_num_rows      <= decode_r ? 10'd0 : (seq_r - 1);
                        flush_num_col_words <= HEAD_WORDS - 1;
                        flush_start_col     <= head_cnt * HEAD_WORDS;
                        waiting_mm <= 1'b1;
                    end
                    if (mm_cmd_done && waiting_mm) begin
                        waiting_mm <= 1'b0;
                        state      <= S_ATT_OUT_FL;
                    end
                end

                // URAM->HBM flush (per-head attn_out)
                S_ATT_OUT_FL: begin
                    if (!flush_sent && !uram_flush_done) begin
                        uram_flush_start         <= 1'b1;
                        flush_sent               <= 1'b1;
                        uram_flush_num_rows      <= flush_num_rows;
                        uram_flush_num_col_words <= flush_num_col_words;
                        uram_flush_start_col     <= flush_start_col;
                        uram_flush_hbm_base      <= flush_hbm_base;
                        uram_flush_hbm_stride    <= flush_hbm_stride;
                    end
                    if (uram_flush_done) begin
                        flush_sent <= 1'b0;
                        if (head_cnt < NUM_HEADS - 1) begin
                            head_cnt <= head_cnt + 1;
                            state    <= S_ATT_SCORE;
                        end else begin
                            head_cnt <= {DIM_W{1'b0}};
                            state    <= S_NEXT_STEP;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Single Matmul executor
                // config: 0=PROJ, 1=FFN1(from EMBED), 2=FFN1(from TEMP), 3=FFN2
                // ---------------------------------------------------------
                S_MM_RUN: begin
                    if (mm_cmd_ready && !mm_cmd_valid && !waiting_mm) begin
                        mm_cmd_valid <= 1'b1;
                        mm_cmd_op    <= OP_MATMUL;
                        mm_cmd_out_col_offset <= 8'd0;
                        mm_cmd_has_bias <= 1'b1;
                        case (step_cfg)
                            4'd0: begin  // PROJ: (BT, MODEL_DIM) x (MODEL_DIM, MODEL_DIM)
                                mm_cmd_m       <= bt;
                                mm_cmd_k       <= MODEL_DIM;
                                mm_cmd_n       <= MODEL_DIM;
                                mm_cmd_a_base  <= act_base + ACT_Q_OFFSET;
                                mm_cmd_b_base  <= layer_wgt_base + LAYER_WO_OFFSET;
                                mm_cmd_a_stride <= MODEL_STRIDE;
                                mm_cmd_b_stride <= MODEL_STRIDE;
                                mm_cmd_bias_base  <= layer_wgt_base + LAYER_BIAS_PROJ_OFFSET;
                                mm_cmd_bias_words <= MODEL_DIM / WE;
                            end
                            4'd1: begin  // FFN1 from EMBED: (BT, MODEL_DIM) x (MODEL_DIM, F_DIM)
                                mm_cmd_m       <= bt;
                                mm_cmd_k       <= MODEL_DIM;
                                mm_cmd_n       <= F_DIM;
                                mm_cmd_a_base  <= act_base + ACT_EMBED_OFFSET;
                                mm_cmd_b_base  <= layer_wgt_base + LAYER_FFN1_OFFSET;
                                mm_cmd_a_stride <= MODEL_STRIDE;
                                mm_cmd_b_stride <= F_STRIDE;
                                mm_cmd_bias_base  <= layer_wgt_base + LAYER_BIAS_FFN1_OFFSET;
                                mm_cmd_bias_words <= F_DIM / WE;
                            end
                            4'd2: begin  // FFN1 from TEMP: (BT, MODEL_DIM) x (MODEL_DIM, F_DIM)
                                mm_cmd_m       <= bt;
                                mm_cmd_k       <= MODEL_DIM;
                                mm_cmd_n       <= F_DIM;
                                mm_cmd_a_base  <= act_base + ACT_TEMP_OFF;
                                mm_cmd_b_base  <= layer_wgt_base + LAYER_FFN1_OFFSET;
                                mm_cmd_a_stride <= MODEL_STRIDE;
                                mm_cmd_b_stride <= F_STRIDE;
                                mm_cmd_bias_base  <= layer_wgt_base + LAYER_BIAS_FFN1_OFFSET;
                                mm_cmd_bias_words <= F_DIM / WE;
                            end
                            default: begin  // FFN2: (BT, F_DIM) x (F_DIM, MODEL_DIM)
                                mm_cmd_m       <= bt;
                                mm_cmd_k       <= F_DIM;
                                mm_cmd_n       <= MODEL_DIM;
                                mm_cmd_a_base  <= act_base + ACT_FFN_OFFSET;
                                mm_cmd_b_base  <= layer_wgt_base + LAYER_FFN2_OFFSET;
                                mm_cmd_a_stride <= F_STRIDE;
                                mm_cmd_b_stride <= MODEL_STRIDE;
                                mm_cmd_bias_base  <= layer_wgt_base + LAYER_BIAS_FFN2_OFFSET;
                                mm_cmd_bias_words <= MODEL_DIM / WE;
                            end
                        endcase
                        waiting_mm <= 1'b1;
                    end
                    if (mm_cmd_done && waiting_mm) begin
                        waiting_mm <= 1'b0;
                        state      <= S_NEXT_STEP;
                    end
                end

                // ---------------------------------------------------------
                // Activation executor (+ adapter flush)
                // ---------------------------------------------------------
                S_ACT_RUN: begin
                    if (!nm_flush_phase) begin
                        if (!act_start && !act_done && !act_busy) begin
                            nm_cfg_col_bits <= CFG_COL_FFN;
                            nm_addr_offset  <= nm_row_cnt * F_DIM;
                            act_start <= 1'b1;
                            act_dim   <= F_DIM;
                        end
                        if (act_done) begin
                            if (nm_row_cnt == bt - 1) begin
                                nm_row_cnt     <= {DIM_W{1'b0}};
                                nm_addr_offset <= {NM_ADDR_W{1'b0}};
                                nm_flush_phase <= 1'b1;
                            end else begin
                                nm_row_cnt <= nm_row_cnt + 1;
                            end
                        end
                    end else begin
                        if (!nm_adapter_flush && !nm_adapter_flush_done) begin
                            nm_adapter_flush <= 1'b1;
                        end
                        if (nm_adapter_flush_done) begin
                            nm_flush_phase <= 1'b0;
                            state <= S_NEXT_STEP;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Residual Add executor (+ adapter flush)
                // config: 0=skip from ACT_EMBED
                // ---------------------------------------------------------
                S_RES_RUN: begin
                    if (!nm_flush_phase) begin
                        if (!res_start && !res_done && !res_busy) begin
                            nm_cfg_col_bits <= CFG_COL_MOD;
                            act_dma_rd_base <= act_base + ACT_EMBED_OFFSET;
                            res_start <= 1'b1;
                            res_dim   <= bt * MODEL_DIM;
                        end
                        if (res_done) begin
                            nm_flush_phase <= 1'b1;
                        end
                    end else begin
                        if (!nm_adapter_flush && !nm_adapter_flush_done) begin
                            nm_adapter_flush <= 1'b1;
                        end
                        if (nm_adapter_flush_done) begin
                            nm_flush_phase <= 1'b0;
                            state <= S_NEXT_STEP;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Standalone URAM->HBM flush executor
                // config: 0=to EMBED(model-wide), 1=to TEMP(model-wide), 2=to FFN(f-wide)
                // ---------------------------------------------------------
                S_UF_RUN: begin
                    if (!flush_sent && !uram_flush_done) begin
                        uram_flush_start <= 1'b1;
                        flush_sent       <= 1'b1;
                        case (step_cfg)
                            4'd0: begin  // flush to ACT_EMBED (model-wide)
                                uram_flush_hbm_base      <= act_base + ACT_EMBED_OFFSET;
                                uram_flush_hbm_stride    <= MODEL_STRIDE;
                                uram_flush_num_rows      <= bt - 1;
                                uram_flush_num_col_words <= URAM_MODEL_COLS_M1;
                                uram_flush_start_col     <= 8'd0;
                            end
                            4'd1: begin  // flush to ACT_TEMP (model-wide)
                                uram_flush_hbm_base      <= act_base + ACT_TEMP_OFF;
                                uram_flush_hbm_stride    <= MODEL_STRIDE;
                                uram_flush_num_rows      <= bt - 1;
                                uram_flush_num_col_words <= URAM_MODEL_COLS_M1;
                                uram_flush_start_col     <= 8'd0;
                            end
                            default: begin  // flush to ACT_FFN (f-wide)
                                uram_flush_hbm_base      <= act_base + ACT_FFN_OFFSET;
                                uram_flush_hbm_stride    <= F_STRIDE;
                                uram_flush_num_rows      <= bt - 1;
                                uram_flush_num_col_words <= URAM_F_COLS_M1;
                                uram_flush_start_col     <= 8'd0;
                            end
                        endcase
                    end
                    if (uram_flush_done) begin
                        flush_sent <= 1'b0;
                        state <= S_NEXT_STEP;
                    end
                end

                // ---------------------------------------------------------
                // S_NEXT_STEP: advance step_idx, handle BT_END -> layer loop
                // ---------------------------------------------------------
                S_NEXT_STEP: begin
                    // synthesis translate_off
                    $display("[FSM %0t] NEXT_STEP: step_idx=%0d step_bt=%0d layer=%0d",
                             $time, step_idx, step_bt, layer_cnt);
                    // synthesis translate_on

                    // Debug trace: fire write if enabled and not yet pending
                    if (dbg_base_r != {HBM_ADDR_W{1'b0}} && !dbg_pending && !dbg_wr_busy) begin
                        dbg_wr_valid <= 1'b1;
                        dbg_wr_addr  <= dbg_base_r + dbg_write_idx;
                        // Debug record: 256 bits total
                        //   [31:0]    cycle_counter (32)
                        //   [47:32]   layer_cnt (16)
                        //   [55:48]   state (8)
                        //   [63:56]   step_idx (8)
                        //   [79:64]   step_bt:step_cfg (16)
                        //   [95:80]   debug_write_idx (16)
                        //   [123:96]  layer_wgt_base (28)
                        //   [127:124] reserved (4)
                        //   [143:128] mm_cmd_m (16)
                        //   [159:144] mm_cmd_n (16)
                        //   [175:160] mm_cmd_k (16)
                        //   [191:176] head_cnt (16)
                        //   [207:192] nm_row_cnt (16)
                        //   [223:208] cache_len_r (16)
                        //   [231:224] decode_r (8)
                        //   [255:232] reserved (24)
                        dbg_wr_data[31:0]    <= dbg_cycle_cnt;
                        dbg_wr_data[47:32]   <= layer_cnt;
                        dbg_wr_data[55:48]   <= {3'b0, state};
                        dbg_wr_data[63:56]   <= {4'b0, step_idx};
                        dbg_wr_data[79:64]   <= {step_bt, step_cfg, 8'd0};
                        dbg_wr_data[95:80]   <= dbg_write_idx;
                        dbg_wr_data[123:96]  <= layer_wgt_base;
                        dbg_wr_data[127:124] <= 4'd0;
                        dbg_wr_data[143:128] <= mm_cmd_m;
                        dbg_wr_data[159:144] <= mm_cmd_n;
                        dbg_wr_data[175:160] <= mm_cmd_k;
                        dbg_wr_data[191:176] <= head_cnt;
                        dbg_wr_data[207:192] <= nm_row_cnt;
                        dbg_wr_data[223:208] <= cache_len_r;
                        dbg_wr_data[231:224] <= {7'b0, decode_r};
                        dbg_wr_data[255:232] <= 24'd0;
                        dbg_pending  <= 1'b1;
                    end

                    // Wait for debug write to complete (or skip if debug disabled)
                    if (dbg_base_r == {HBM_ADDR_W{1'b0}} || (dbg_pending && dbg_wr_done)) begin
                        dbg_pending   <= 1'b0;
                        dbg_write_idx <= dbg_write_idx + 1;
                        step_cnt      <= step_cnt + 1;
                        // max_steps limit (0 = unlimited)
                        if (max_steps_r != {DIM_W{1'b0}} && (step_cnt + 1) >= max_steps_r) begin
                            state <= S_DONE;
                        end else if (step_bt == BT_END) begin
                            // Checkpoint dump: read first 4 URAM words after layer
                            if (dbg_base_r != {HBM_ADDR_W{1'b0}}) begin
                                chk_col_idx   <= 3'd0;
                                chk_rd_issued <= 1'b0;
                                chk_data_valid <= 1'b0;
                                state         <= S_CHECKPOINT;
                            end else if (layer_cnt < num_layers_r - 1) begin
                                layer_cnt <= layer_cnt + 1;
                                step_idx  <= 4'd0;
                                state     <= S_DECODE;
                            end else begin
                                state <= S_DONE;
                            end
                        end else begin
                            `ifdef STEP_DEBUG
                            // Per-step debug: flush URAM before advancing
                            state <= S_STEP_DBG_FLUSH;
                            `else
                            step_idx <= step_idx + 1;
                            state    <= S_DECODE;
                            `endif
                        end
                    end
                end

                // ---------------------------------------------------------
                // S_CHECKPOINT: read 4 URAM words (row 0, cols 0-3) and
                // write them as debug trace records after each layer
                // ---------------------------------------------------------
                S_CHECKPOINT: begin
                    // Phase 1: Issue URAM read
                    if (!chk_rd_issued && !chk_data_valid && !dbg_pending) begin
                        chk_uram_rd_en  <= 1'b1;
                        chk_uram_rd_row <= 10'd0;
                        chk_uram_rd_col <= {5'd0, chk_col_idx};
                        chk_rd_issued   <= 1'b1;
                    end

                    // Phase 2: Capture URAM data
                    if (chk_rd_issued && chk_uram_rd_valid) begin
                        chk_data_r     <= chk_uram_rd_data;
                        chk_data_valid <= 1'b1;
                        chk_rd_issued  <= 1'b0;
                    end

                    // Phase 3: Write debug record
                    if (chk_data_valid && !dbg_pending && !dbg_wr_busy) begin
                        dbg_wr_valid         <= 1'b1;
                        dbg_wr_addr          <= dbg_base_r + dbg_write_idx;
                        // Header: [31:0] = {0xCC, col_idx, layer_cnt}
                        dbg_wr_data[15:0]    <= layer_cnt;
                        dbg_wr_data[23:16]   <= {5'd0, chk_col_idx};
                        dbg_wr_data[31:24]   <= 8'hCC;
                        // Payload: [255:32] = URAM data[223:0] (14 FP16 values)
                        dbg_wr_data[255:32]  <= chk_data_r[223:0];
                        dbg_pending          <= 1'b1;
                        chk_data_valid       <= 1'b0;
                    end

                    // Phase 4: Wait for debug write done, advance
                    if (dbg_pending && dbg_wr_done) begin
                        dbg_pending   <= 1'b0;
                        dbg_write_idx <= dbg_write_idx + 1;

                        if (chk_col_idx == 3'd3) begin
                            // Checkpoint done — advance layer
                            if (layer_cnt < num_layers_r - 1) begin
                                layer_cnt <= layer_cnt + 1;
                                step_idx  <= 4'd0;
                                state     <= S_DECODE;
                            end else begin
                                state <= S_DONE;
                            end
                        end else begin
                            chk_col_idx <= chk_col_idx + 1;
                        end
                    end
                end

                `ifdef STEP_DEBUG
                // ---------------------------------------------------------
                // S_STEP_DBG_FLUSH: dump full URAM (MODEL_DIM cols) to
                // output_base + running offset after each FSM step
                // ---------------------------------------------------------
                S_STEP_DBG_FLUSH: begin
                    if (!step_dbg_flush_sent && !uram_flush_done) begin
                        uram_flush_start         <= 1'b1;
                        step_dbg_flush_sent      <= 1'b1;
                        uram_flush_hbm_base      <= output_base + step_dbg_offset;
                        uram_flush_hbm_stride    <= MODEL_STRIDE;
                        uram_flush_num_rows      <= bt - 1;
                        uram_flush_num_col_words <= URAM_MODEL_COLS_M1;
                        uram_flush_start_col     <= 8'd0;
                        // synthesis translate_off
                        $display("[STEP_DBG %0t] Flush step %0d layer %0d -> output_base+%0d",
                                 $time, step_idx, layer_cnt, step_dbg_offset);
                        // synthesis translate_on
                    end
                    if (uram_flush_done) begin
                        step_dbg_flush_sent <= 1'b0;
                        step_dbg_offset     <= step_dbg_offset + step_dbg_stride;
                        step_idx            <= step_idx + 1;
                        state               <= S_DECODE;
                    end
                end
                `endif

                // ---------------------------------------------------------
                S_OUTPUT_COPY: begin
                    if (!flush_sent && !uram_flush_done) begin
                        uram_flush_start         <= 1'b1;
                        flush_sent               <= 1'b1;
                        uram_flush_hbm_base      <= output_base;
                        uram_flush_hbm_stride    <= MODEL_STRIDE;
                        uram_flush_num_rows      <= bt - 1;
                        uram_flush_num_col_words <= URAM_MODEL_COLS_M1;
                        uram_flush_start_col     <= 8'd0;
                    end
                    if (uram_flush_done) begin
                        flush_sent <= 1'b0;
                        state      <= S_DONE;
                    end
                end

                // =========================================================
                // DIAGNOSTIC TEST STATES (active when test_mode != 0)
                // =========================================================

                // ---------------------------------------------------------
                // S_TEST_DISPATCH: route to test-specific state
                // ---------------------------------------------------------
                S_TEST_DISPATCH: begin
                    case (test_mode_r)
                        4'd1:    state <= S_TEST_ECHO;
                        4'd5:    state <= S_TEST_URAM_WR;
                        4'd6:  begin
                            state <= S_TEST_URAM_WR;  // latency probe starts with URAM write
                        end
                        4'd7:    state <= S_TEST_URAM_WR;  // multi-row starts with write
                        4'd12:   state <= S_TEST_REG_CHK;
                        default: state <= S_DONE;
                    endcase
                    test_phase <= 3'd0;
                    test_cnt   <= {DIM_W{1'b0}};
                end

                // ---------------------------------------------------------
                // S_TEST_REG_CHK (test_mode=12): write register values to
                // output HBM via debug_writer so host can verify
                // ---------------------------------------------------------
                S_TEST_REG_CHK: begin
                    if (!dbg_pending && !dbg_wr_busy) begin
                        dbg_wr_valid <= 1'b1;
                        dbg_wr_addr  <= output_base + test_cnt;
                        case (test_cnt[1:0])
                            2'd0: begin
                                dbg_wr_data[15:0]    <= batch_r;
                                dbg_wr_data[31:16]   <= seq_r;
                                dbg_wr_data[47:32]   <= num_layers_r;
                                dbg_wr_data[51:48]   <= test_mode_r;
                                dbg_wr_data[63:52]   <= 12'd0;
                                dbg_wr_data[79:64]   <= max_steps_r;
                                dbg_wr_data[95:80]   <= cache_len_r;
                                dbg_wr_data[96]      <= decode_r;
                                dbg_wr_data[127:97]  <= 31'd0;
                                dbg_wr_data[255:128] <= 128'd0;
                            end
                            2'd1: begin
                                dbg_wr_data[27:0]    <= weight_base;
                                dbg_wr_data[31:28]   <= 4'd0;
                                dbg_wr_data[59:32]   <= act_base;
                                dbg_wr_data[63:60]   <= 4'd0;
                                dbg_wr_data[255:64]  <= 192'd0;
                            end
                            2'd2: begin
                                dbg_wr_data[27:0]    <= output_base;
                                dbg_wr_data[31:28]   <= 4'd0;
                                dbg_wr_data[59:32]   <= kv_base;
                                dbg_wr_data[63:60]   <= 4'd0;
                                dbg_wr_data[255:64]  <= 192'd0;
                            end
                            2'd3: begin
                                dbg_wr_data[27:0]    <= dbg_base_r;
                                dbg_wr_data[31:28]   <= 4'd0;
                                dbg_wr_data[255:32]  <= 224'd0;
                            end
                        endcase
                        dbg_pending <= 1'b1;
                    end
                    if (dbg_pending && dbg_wr_done) begin
                        dbg_pending <= 1'b0;
                        if (test_cnt == 16'd3)
                            state <= S_DONE;
                        else
                            test_cnt <= test_cnt + 1;
                    end
                end

                // ---------------------------------------------------------
                // S_TEST_ECHO (test_mode=1): write known pattern to output
                // HBM via debug_writer
                // ---------------------------------------------------------
                S_TEST_ECHO: begin
                    if (!dbg_pending && !dbg_wr_busy) begin
                        dbg_wr_valid <= 1'b1;
                        dbg_wr_addr  <= output_base + test_cnt;
                        // Pattern: {idx, CAFE, idx, CAFE, ...} repeated 8 times
                        dbg_wr_data <= {test_cnt[15:0], 16'hCAFE,
                                        test_cnt[15:0], 16'hCAFE,
                                        test_cnt[15:0], 16'hCAFE,
                                        test_cnt[15:0], 16'hCAFE,
                                        test_cnt[15:0], 16'hCAFE,
                                        test_cnt[15:0], 16'hCAFE,
                                        test_cnt[15:0], 16'hCAFE,
                                        test_cnt[15:0], 16'hCAFE};
                        dbg_pending <= 1'b1;
                    end
                    if (dbg_pending && dbg_wr_done) begin
                        dbg_pending <= 1'b0;
                        if (test_cnt == 16'd7)
                            state <= S_DONE;
                        else
                            test_cnt <= test_cnt + 1;
                    end
                end

                // ---------------------------------------------------------
                // S_TEST_URAM_WR (test_mode=5,6,7): write known pattern to
                // URAM via nm_adapter, then flush or probe latency
                // ---------------------------------------------------------
                S_TEST_URAM_WR: begin
                    case (test_phase)
                        3'd0: begin
                            // Configure nm_adapter
                            nm_cfg_col_bits <= CFG_COL_MOD;  // MODEL_DIM width
                            nm_addr_offset  <= {NM_ADDR_W{1'b0}};
                            test_cnt <= {DIM_W{1'b0}};
                            test_phase <= 3'd1;
                            // For multi-row test, set starting row offset
                            if (test_mode_r == 4'd7) begin
                                case (test_row_idx)
                                    4'd0: nm_addr_offset <= {NM_ADDR_W{1'b0}};
                                    4'd1: nm_addr_offset <= 20'd256 * MODEL_DIM;
                                    4'd2: nm_addr_offset <= 20'd512 * MODEL_DIM;
                                    4'd3: nm_addr_offset <= 20'd768 * MODEL_DIM;
                                    default: nm_addr_offset <= {NM_ADDR_W{1'b0}};
                                endcase
                            end
                        end
                        3'd1: begin
                            // Write 64 scalar values (4 bus words) to URAM
                            // For test 6 (latency), only write 16 values (1 bus word)
                            test_wr_en   <= 1'b1;
                            test_wr_addr <= test_cnt[NM_ADDR_W-1:0];
                            // Pattern: base + index. Base varies by row for multi-row
                            if (test_mode_r == 4'd7) begin
                                case (test_row_idx)
                                    4'd0: test_wr_data <= 16'hA000 + test_cnt[15:0];
                                    4'd1: test_wr_data <= 16'hB000 + test_cnt[15:0];
                                    4'd2: test_wr_data <= 16'hC000 + test_cnt[15:0];
                                    4'd3: test_wr_data <= 16'hD000 + test_cnt[15:0];
                                    default: test_wr_data <= 16'h3C00 + test_cnt[15:0];
                                endcase
                            end else begin
                                test_wr_data <= 16'h3C00 + test_cnt[15:0];
                            end
                            test_cnt <= test_cnt + 1;
                            if ((test_mode_r == 4'd6 && test_cnt == 16'd15) ||
                                (test_mode_r != 4'd6 && test_cnt == 16'd63)) begin
                                test_phase <= 3'd2;
                            end
                        end
                        3'd2: begin
                            // Flush nm_adapter write buffer to URAM
                            nm_adapter_flush <= 1'b1;
                            test_phase <= 3'd3;
                        end
                        3'd3: begin
                            // Wait for adapter flush done
                            if (nm_adapter_flush_done) begin
                                test_phase <= 3'd0;
                                test_cnt   <= {DIM_W{1'b0}};
                                if (test_mode_r == 4'd6)
                                    state <= S_TEST_LATENCY;
                                else if (test_mode_r == 4'd7 && test_row_idx < 4'd3) begin
                                    // Write all 4 rows before reading back
                                    test_row_idx <= test_row_idx + 1;
                                    state <= S_TEST_URAM_WR;
                                end else begin
                                    // test_mode=5 (single row) or 7 (all rows written)
                                    if (test_mode_r == 4'd7)
                                        test_row_idx <= 4'd0;  // reset for readback phase
                                    state <= S_TEST_URAM_FL;
                                end
                            end
                        end
                        default: test_phase <= 3'd0;
                    endcase
                end

                // ---------------------------------------------------------
                // S_TEST_URAM_FL (test_mode=5): flush URAM row 0 to HBM
                //                (test_mode=7): checkpoint-read rows
                //                0/256/512/768, write to HBM via debug_writer
                // ---------------------------------------------------------
                S_TEST_URAM_FL: begin
                    if (test_mode_r == 4'd7) begin
                        // Multi-row: use checkpoint reads (uram_flush can't
                        // start from arbitrary rows)
                        case (test_phase)
                            3'd0: begin
                                // Issue checkpoint read for target row
                                chk_uram_rd_en <= 1'b1;
                                case (test_row_idx)
                                    4'd0: chk_uram_rd_row <= 10'd0;
                                    4'd1: chk_uram_rd_row <= 10'd256;
                                    4'd2: chk_uram_rd_row <= 10'd512;
                                    4'd3: chk_uram_rd_row <= 10'd768;
                                    default: chk_uram_rd_row <= 10'd0;
                                endcase
                                chk_uram_rd_col <= 8'd0;  // first bus word
                                test_phase <= 3'd1;
                            end
                            3'd1: begin
                                // Wait for read valid
                                if (chk_uram_rd_valid)
                                    test_phase <= 3'd2;
                            end
                            3'd2: begin
                                // Write readback data to HBM via debug_writer
                                if (!dbg_pending && !dbg_wr_busy) begin
                                    dbg_wr_valid <= 1'b1;
                                    dbg_wr_addr  <= output_base + {24'd0, test_row_idx};
                                    dbg_wr_data  <= chk_uram_rd_data;
                                    dbg_pending  <= 1'b1;
                                end
                                if (dbg_pending && dbg_wr_done) begin
                                    dbg_pending <= 1'b0;
                                    if (test_row_idx < 4'd3) begin
                                        test_row_idx <= test_row_idx + 1;
                                        test_phase   <= 3'd0;
                                    end else begin
                                        state <= S_DONE;
                                    end
                                end
                            end
                            default: test_phase <= 3'd0;
                        endcase
                    end else begin
                        // test_mode=5: Simple flush row 0 to HBM
                        if (!flush_sent && !uram_flush_done) begin
                            uram_flush_start         <= 1'b1;
                            flush_sent               <= 1'b1;
                            uram_flush_num_rows      <= 10'd0;  // 1 row
                            uram_flush_num_col_words <= 8'd3;   // 4 words (count-1)
                            uram_flush_start_col     <= 8'd0;
                            uram_flush_hbm_base      <= output_base;
                            uram_flush_hbm_stride    <= MODEL_STRIDE;
                        end
                        if (uram_flush_done) begin
                            flush_sent <= 1'b0;
                            state <= S_DONE;
                        end
                    end
                end

                // ---------------------------------------------------------
                // S_TEST_LATENCY (test_mode=6): measure URAM read latency
                // via checkpoint read interface
                // ---------------------------------------------------------
                S_TEST_LATENCY: begin
                    case (test_phase)
                        3'd0: begin
                            // Issue URAM read via checkpoint interface
                            chk_uram_rd_en  <= 1'b1;
                            chk_uram_rd_row <= 10'd0;
                            chk_uram_rd_col <= 8'd0;
                            test_latency_cnt <= 16'd1;  // count starts at 1 (this cycle)
                            test_phase <= 3'd1;
                        end
                        3'd1: begin
                            // Count cycles until valid
                            if (chk_uram_rd_valid) begin
                                // Capture result
                                test_phase <= 3'd2;
                            end else begin
                                test_latency_cnt <= test_latency_cnt + 1;
                            end
                        end
                        3'd2: begin
                            // Write result via debug_writer
                            if (!dbg_pending && !dbg_wr_busy) begin
                                dbg_wr_valid <= 1'b1;
                                dbg_wr_addr  <= output_base;
                                // Result record:
                                //   [15:0]   measured latency (cycles)
                                //   [31:16]  expected latency (URAM_RD_LATENCY param)
                                //   [47:32]  0xBEEF (marker)
                                //   [255:48] URAM read data (first 13 FP16 values)
                                dbg_wr_data[15:0]   <= test_latency_cnt;
                                dbg_wr_data[31:16]  <= 16'd1;  // expected (RD_LATENCY=1)
                                dbg_wr_data[47:32]  <= 16'hBEEF;
                                dbg_wr_data[255:48] <= chk_uram_rd_data[207:0];
                                dbg_pending <= 1'b1;
                            end
                            if (dbg_pending && dbg_wr_done) begin
                                dbg_pending <= 1'b0;
                                state <= S_DONE;
                            end
                        end
                        default: test_phase <= 3'd0;
                    endcase
                end

                // ---------------------------------------------------------
                S_DONE: begin
                    // synthesis translate_off
                    $display("[FSM %0t] DONE — kernel complete", $time);
                    // synthesis translate_on
                    // Fire final debug record if enabled
                    if (dbg_base_r != {HBM_ADDR_W{1'b0}} && !dbg_pending && !dbg_wr_busy) begin
                        dbg_wr_valid         <= 1'b1;
                        dbg_wr_addr          <= dbg_base_r + dbg_write_idx;
                        dbg_wr_data[31:0]    <= dbg_cycle_cnt;
                        dbg_wr_data[47:32]   <= layer_cnt;
                        dbg_wr_data[55:48]   <= {3'b0, state};
                        dbg_wr_data[63:56]   <= 8'hFF;  // marker: DONE
                        dbg_wr_data[95:64]   <= 32'd0;
                        dbg_wr_data[127:96]  <= 32'd0;
                        dbg_wr_data[255:128] <= 128'd0;
                        dbg_pending          <= 1'b1;
                    end
                    if (dbg_base_r == {HBM_ADDR_W{1'b0}} || (dbg_pending && dbg_wr_done)) begin
                        dbg_pending <= 1'b0;
                        done <= 1'b1;
                        busy <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
