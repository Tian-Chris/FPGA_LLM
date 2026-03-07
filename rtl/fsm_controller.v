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
    output reg                      done,
    output reg                      busy,

    // HBM base addresses (from host_interface)
    input  wire [HBM_ADDR_W-1:0]   weight_base,
    input  wire [HBM_ADDR_W-1:0]   act_base,
    input  wire [HBM_ADDR_W-1:0]   output_base,

    // Matmul / tiling_engine command interface
    output reg                      mm_cmd_valid,
    output reg  [2:0]               mm_cmd_op,
    output reg  [DIM_W-1:0]         mm_cmd_m,
    output reg  [DIM_W-1:0]         mm_cmd_k,
    output reg  [DIM_W-1:0]         mm_cmd_n,
    output reg  [HBM_ADDR_W-1:0]   mm_cmd_a_base,
    output reg  [HBM_ADDR_W-1:0]   mm_cmd_b_base,
    output reg  [HBM_ADDR_W-1:0]   mm_cmd_a_stride,
    output reg  [HBM_ADDR_W-1:0]   mm_cmd_b_stride,
    output reg  [7:0]               mm_cmd_out_col_offset,
    input  wire                     mm_cmd_ready,
    input  wire                     mm_cmd_done,

    // URAM flush control
    output reg                      uram_flush_start,
    output reg  [9:0]               uram_flush_num_rows,
    output reg  [7:0]               uram_flush_num_col_words,
    output reg  [7:0]               uram_flush_start_col,
    output reg  [HBM_ADDR_W-1:0]   uram_flush_hbm_base,
    output reg  [HBM_ADDR_W-1:0]   uram_flush_hbm_stride,
    input  wire                     uram_flush_done,

    // Non-matmul adapter control
    output reg  [3:0]               nm_cfg_col_bits,
    output reg                      nm_adapter_flush,
    input  wire                     nm_adapter_flush_done,
    output reg  [DIM_W-1:0]         nm_addr_offset,

    // act_dma base address control
    output reg  [HBM_ADDR_W-1:0]   act_dma_rd_base,
    output reg  [HBM_ADDR_W-1:0]   act_dma_wr_base,
    output reg                      act_dma_flush,
    input  wire                     act_dma_flush_done,

    // Softmax controller interface
    output reg                      sm_start,
    output reg  [DIM_W-1:0]         sm_seq_len,
    output reg  [DIM_W-1:0]         sm_row_idx,
    output reg  [3:0]               sm_scale_shift,
    input  wire                     sm_done,

    // LayerNorm controller interface
    output reg                      ln_start,
    output reg  [DIM_W-1:0]         ln_dim,
    input  wire                     ln_done,

    // Activation unit interface
    output reg                      act_start,
    output reg  [DIM_W-1:0]         act_dim,
    input  wire                     act_done,

    // Residual add interface
    output reg                      res_start,
    output reg  [DIM_W-1:0]         res_dim,
    input  wire                     res_done,

    // Quantization layer interface
    output reg                      quant_start,
    output reg  [DIM_W-1:0]         quant_dim,
    output reg  [HBM_ADDR_W-1:0]   quant_src_base,
    output reg  [HBM_ADDR_W-1:0]   quant_dst_base,
    input  wire                     quant_done,

    // Debug/status outputs
    output reg  [5:0]               current_state,
    output reg  [DIM_W-1:0]         current_layer
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
    localparam LAYER_SIZE        = LAYER_LN2_OFFSET + 2 * MODEL_DIM / WE;

    // Row strides
    localparam MODEL_STRIDE = MODEL_DIM / WE;
    localparam F_STRIDE     = F_DIM / WE;

    // =====================================================================
    // HBM Activation Memory Layout
    // =====================================================================
    localparam ACT_EMBED_OFFSET  = 0;
    localparam ACT_Q_OFFSET      = MAX_SEQ_LEN * MODEL_DIM / WE;
    localparam ACT_K_OFFSET      = 2 * MAX_SEQ_LEN * MODEL_DIM / WE;
    localparam ACT_V_OFFSET      = 3 * MAX_SEQ_LEN * MODEL_DIM / WE;
    localparam ACT_ATTN_OFFSET   = 4 * MAX_SEQ_LEN * MODEL_DIM / WE;
    localparam ACT_TEMP_OFF      = 5 * MAX_SEQ_LEN * MODEL_DIM / WE;
    localparam ACT_FFN_OFFSET    = 0;

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
    reg [4:0] state;

    reg [DIM_W-1:0] batch_r, seq_r;
    reg              decode_r;
    reg [DIM_W-1:0]  cache_len_r;
    reg [DIM_W-1:0] layer_cnt;
    reg [3:0]       step_idx;
    reg [3:0]       step_bt;      // block type from decoded step
    reg [3:0]       step_cfg;     // config id from decoded step
    reg [1:0]       qkv_phase;
    reg              waiting_mm;
    reg              nm_flush_phase;
    reg [DIM_W-1:0]  nm_row_cnt;
    reg [DIM_W-1:0]  head_cnt;
    reg              flush_sent;

    // Computed values
    wire [DIM_W-1:0] bt = batch_r * seq_r;
    wire [HBM_ADDR_W-1:0] layer_wgt_base = weight_base + layer_cnt * LAYER_SIZE;

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
            uram_flush_start <= 1'b0;
            uram_flush_num_rows      <= 10'd0;
            uram_flush_num_col_words <= 8'd0;
            uram_flush_start_col     <= 8'd0;
            uram_flush_hbm_base      <= {HBM_ADDR_W{1'b0}};
            uram_flush_hbm_stride    <= {HBM_ADDR_W{1'b0}};
            nm_cfg_col_bits  <= 4'd10;
            nm_adapter_flush <= 1'b0;
            nm_addr_offset   <= {DIM_W{1'b0}};
            nm_row_cnt       <= {DIM_W{1'b0}};
            act_dma_rd_base  <= {HBM_ADDR_W{1'b0}};
            act_dma_wr_base  <= {HBM_ADDR_W{1'b0}};
            act_dma_flush    <= 1'b0;
            sm_start         <= 1'b0;
            sm_row_idx       <= {DIM_W{1'b0}};
            sm_scale_shift   <= 4'd0;
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
            waiting_mm       <= 1'b0;
            nm_flush_phase   <= 1'b0;
            head_cnt         <= {DIM_W{1'b0}};
            flush_sent       <= 1'b0;
            flush_hbm_base   <= {HBM_ADDR_W{1'b0}};
            flush_hbm_stride <= {HBM_ADDR_W{1'b0}};
            flush_num_rows   <= 10'd0;
            flush_num_col_words <= 8'd0;
            flush_start_col  <= 8'd0;
            current_state    <= 6'd0;
            current_layer    <= {DIM_W{1'b0}};
        end else begin
            // Default: clear one-shot signals
            done             <= 1'b0;
            mm_cmd_valid     <= 1'b0;
            sm_start         <= 1'b0;
            ln_start         <= 1'b0;
            act_start        <= 1'b0;
            res_start        <= 1'b0;
            quant_start      <= 1'b0;
            uram_flush_start <= 1'b0;
            nm_adapter_flush <= 1'b0;
            act_dma_flush    <= 1'b0;

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
                        layer_cnt   <= {DIM_W{1'b0}};
                        step_idx  <= 4'd0;
                        qkv_phase <= 2'd0;
                        head_cnt       <= {DIM_W{1'b0}};
                        nm_row_cnt     <= {DIM_W{1'b0}};
                        nm_addr_offset <= {DIM_W{1'b0}};
                        state     <= S_DECODE;
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
                        if (!ln_start && !ln_done) begin
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
                                nm_addr_offset <= {DIM_W{1'b0}};
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
                        case (qkv_phase)
                            2'd0: flush_hbm_base <= act_base + ACT_Q_OFFSET;
                            2'd1: flush_hbm_base <= act_base + ACT_K_OFFSET
                                                  + (decode_r ? cache_len_r * MODEL_STRIDE : {HBM_ADDR_W{1'b0}});
                            default: flush_hbm_base <= act_base + ACT_V_OFFSET
                                                     + (decode_r ? cache_len_r * MODEL_STRIDE : {HBM_ADDR_W{1'b0}});
                        endcase
                        flush_hbm_stride    <= MODEL_STRIDE;
                        flush_num_rows      <= bt - 1;
                        flush_num_col_words <= URAM_MODEL_COLS_M1;
                        flush_start_col     <= 8'd0;
                        waiting_mm          <= 1'b1;
                    end
                    if (mm_cmd_done && waiting_mm) begin
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
                        mm_cmd_b_base   <= act_base + ACT_K_OFFSET + head_cnt * HEAD_WORDS;
                        mm_cmd_a_stride <= MODEL_STRIDE;
                        mm_cmd_b_stride <= MODEL_STRIDE;
                        mm_cmd_out_col_offset <= 8'd0;
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
                        if (!sm_start && !sm_done) begin
                            nm_cfg_col_bits <= CFG_COL_SEQ;
                            nm_addr_offset  <= nm_row_cnt * (decode_r ? cache_total : seq_r);
                            sm_start       <= 1'b1;
                            sm_seq_len     <= decode_r ? cache_total : seq_r;
                            sm_row_idx     <= decode_r ? cache_len_r : nm_row_cnt;
                            sm_scale_shift <= SCALE_SHIFT;
                        end
                        if (sm_done) begin
                            if (nm_row_cnt == bt - 1) begin
                                nm_row_cnt     <= {DIM_W{1'b0}};
                                nm_addr_offset <= {DIM_W{1'b0}};
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
                        mm_cmd_b_base   <= act_base + ACT_V_OFFSET + head_cnt * HEAD_WORDS;
                        mm_cmd_a_stride <= decode_r ? cache_total_words : seq_words;
                        mm_cmd_b_stride <= MODEL_STRIDE;
                        mm_cmd_out_col_offset <= head_cnt * HEAD_WORDS;
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
                        case (step_cfg)
                            4'd0: begin  // PROJ: (BT, MODEL_DIM) x (MODEL_DIM, MODEL_DIM)
                                mm_cmd_m       <= bt;
                                mm_cmd_k       <= MODEL_DIM;
                                mm_cmd_n       <= MODEL_DIM;
                                mm_cmd_a_base  <= act_base + ACT_Q_OFFSET;
                                mm_cmd_b_base  <= layer_wgt_base + LAYER_WO_OFFSET;
                                mm_cmd_a_stride <= MODEL_STRIDE;
                                mm_cmd_b_stride <= MODEL_STRIDE;
                            end
                            4'd1: begin  // FFN1 from EMBED: (BT, MODEL_DIM) x (MODEL_DIM, F_DIM)
                                mm_cmd_m       <= bt;
                                mm_cmd_k       <= MODEL_DIM;
                                mm_cmd_n       <= F_DIM;
                                mm_cmd_a_base  <= act_base + ACT_EMBED_OFFSET;
                                mm_cmd_b_base  <= layer_wgt_base + LAYER_FFN1_OFFSET;
                                mm_cmd_a_stride <= MODEL_STRIDE;
                                mm_cmd_b_stride <= F_STRIDE;
                            end
                            4'd2: begin  // FFN1 from TEMP: (BT, MODEL_DIM) x (MODEL_DIM, F_DIM)
                                mm_cmd_m       <= bt;
                                mm_cmd_k       <= MODEL_DIM;
                                mm_cmd_n       <= F_DIM;
                                mm_cmd_a_base  <= act_base + ACT_TEMP_OFF;
                                mm_cmd_b_base  <= layer_wgt_base + LAYER_FFN1_OFFSET;
                                mm_cmd_a_stride <= MODEL_STRIDE;
                                mm_cmd_b_stride <= F_STRIDE;
                            end
                            default: begin  // FFN2: (BT, F_DIM) x (F_DIM, MODEL_DIM)
                                mm_cmd_m       <= bt;
                                mm_cmd_k       <= F_DIM;
                                mm_cmd_n       <= MODEL_DIM;
                                mm_cmd_a_base  <= act_base + ACT_FFN_OFFSET;
                                mm_cmd_b_base  <= layer_wgt_base + LAYER_FFN2_OFFSET;
                                mm_cmd_a_stride <= F_STRIDE;
                                mm_cmd_b_stride <= MODEL_STRIDE;
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
                        if (!act_start && !act_done) begin
                            nm_cfg_col_bits <= CFG_COL_FFN;
                            act_start <= 1'b1;
                            act_dim   <= bt * F_DIM;
                        end
                        if (act_done) begin
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
                // Residual Add executor (+ adapter flush)
                // config: 0=skip from ACT_EMBED
                // ---------------------------------------------------------
                S_RES_RUN: begin
                    if (!nm_flush_phase) begin
                        if (!res_start && !res_done) begin
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
                    if (step_bt == BT_END) begin
                        // Layer complete
                        if (layer_cnt < NUM_ENC_LAYERS - 1) begin
                            layer_cnt <= layer_cnt + 1;
                            step_idx  <= 4'd0;
                            state     <= S_DECODE;
                        end else begin
                            state <= S_OUTPUT_COPY;
                        end
                    end else begin
                        step_idx <= step_idx + 1;
                        state    <= S_DECODE;
                    end
                end

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

                // ---------------------------------------------------------
                S_DONE: begin
                    // synthesis translate_off
                    $display("[FSM %0t] DONE — kernel complete", $time);
                    // synthesis translate_on
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
