`include "defines.vh"

// =============================================================================
// tiling_engine.v - Master Tile Dispatcher with URAM Prefetch Coordination
// =============================================================================
//
// Drop-in replacement for FSM controller's matmul interface. Accepts a matmul
// command, coordinates prefetch of matrix chunks into shared URAM buffers,
// then dispatches (tile_m, tile_n) pairs to idle engines.
//
// Outer loops iterate K and N in chunks of up to PREFETCH_DIM (1024).
// For each chunk: prefetch act+wgt buffers, dispatch all tiles, wait.
// Engines receive chunk-relative URAM offsets (no HBM addresses).
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

module tiling_engine #(
    parameter N_ENG        = 6,
    parameter TILE         = 32,
    parameter DIM_W        = 16,
    parameter DATA_W       = 16,
    parameter OUT_W        = 16,
    parameter ACC_W        = 32,
    parameter BUS_W        = 256,
    parameter URAM_ROW_W   = 10,
    parameter URAM_COL_W   = 6,
    parameter PF_ROW_W     = 10,      // prefetch buffer row address width
    parameter PF_COL_W     = 6,       // prefetch buffer col address width
    parameter PREFETCH_DIM = 1024     // max rows/cols per chunk
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Command interface (from FSM controller)
    input  wire                 cmd_valid,
    input  wire [2:0]           cmd_op,
    input  wire [DIM_W-1:0]     cmd_m,
    input  wire [DIM_W-1:0]     cmd_k,
    input  wire [DIM_W-1:0]     cmd_n,
    input  wire [HBM_ADDR_W-1:0] cmd_a_base,
    input  wire [HBM_ADDR_W-1:0] cmd_b_base,
    input  wire [HBM_ADDR_W-1:0] cmd_a_stride,
    input  wire [HBM_ADDR_W-1:0] cmd_b_stride,
    input  wire [URAM_COL_W-1:0] cmd_out_col_offset,
    (* mark_debug = "true" *) output reg                  cmd_ready,
    (* mark_debug = "true" *) output reg                  cmd_done,

    // -----------------------------------------------------------------
    // Prefetch command interface — activation buffer
    // -----------------------------------------------------------------
    output reg                      pf_act_cmd_valid,
    input  wire                     pf_act_cmd_ready,
    input  wire                     pf_act_cmd_done,
    output reg  [HBM_ADDR_W-1:0]   pf_act_hbm_base,
    output reg  [HBM_ADDR_W-1:0]   pf_act_hbm_stride,
    output reg  [DIM_W-1:0]        pf_act_num_rows,
    output reg  [DIM_W-1:0]        pf_act_num_col_words,

    // -----------------------------------------------------------------
    // Prefetch command interface — weight buffer
    // -----------------------------------------------------------------
    output reg                      pf_wgt_cmd_valid,
    input  wire                     pf_wgt_cmd_ready,
    input  wire                     pf_wgt_cmd_done,
    output reg  [HBM_ADDR_W-1:0]   pf_wgt_hbm_base,
    output reg  [HBM_ADDR_W-1:0]   pf_wgt_hbm_stride,
    output reg  [DIM_W-1:0]        pf_wgt_num_rows,
    output reg  [DIM_W-1:0]        pf_wgt_num_col_words,

    // Per-engine tile command interface
    output reg  [N_ENG-1:0]                    eng_cmd_valid,
    output reg  [3*N_ENG-1:0]                  eng_cmd_op,
    output reg  [DIM_W*N_ENG-1:0]              eng_cmd_m,
    output reg  [DIM_W*N_ENG-1:0]              eng_cmd_k,
    output reg  [DIM_W*N_ENG-1:0]              eng_cmd_n,
    output reg  [PF_ROW_W*N_ENG-1:0]          eng_cmd_a_row_off,
    output reg  [PF_COL_W*N_ENG-1:0]          eng_cmd_a_col_off,
    output reg  [PF_ROW_W*N_ENG-1:0]          eng_cmd_b_row_off,
    output reg  [PF_COL_W*N_ENG-1:0]          eng_cmd_b_col_off,
    output reg  [URAM_ROW_W*N_ENG-1:0]        eng_cmd_out_row,
    output reg  [URAM_COL_W*N_ENG-1:0]        eng_cmd_out_col_word,
    output reg  [N_ENG-1:0]                    eng_cmd_first_k_chunk,
    input  wire [N_ENG-1:0]                    eng_cmd_ready,
    input  wire [N_ENG-1:0]                    eng_cmd_done
);

    localparam BUS_EL         = BUS_W / DATA_W;           // 16
    localparam TILE_COL_WORDS = TILE / BUS_EL;            // 2

    // =========================================================================
    // State machine
    // =========================================================================
    (* mark_debug = "true" *) reg [3:0] state;
    localparam ST_IDLE           = 4'd0;
    localparam ST_SETUP          = 4'd1;
    localparam ST_K_CHUNK_SETUP  = 4'd2;
    localparam ST_N_CHUNK_SETUP  = 4'd3;
    localparam ST_PREFETCH_CMD   = 4'd4;
    localparam ST_WAIT_PREFETCH  = 4'd5;
    localparam ST_DISPATCH       = 4'd6;
    localparam ST_WAIT           = 4'd7;
    localparam ST_NEXT_N_CHUNK   = 4'd8;
    localparam ST_NEXT_K_CHUNK   = 4'd9;
    localparam ST_DONE           = 4'd10;

    // =========================================================================
    // Registered command
    // =========================================================================
    reg [2:0] op_r;
    reg [DIM_W-1:0] m_r, k_r, n_r;
    reg [HBM_ADDR_W-1:0] a_base_r, b_base_r, a_stride_r, b_stride_r;
    reg [URAM_COL_W-1:0] out_col_offset_r;

    // =========================================================================
    // Tile grid dimensions (within current chunk)
    // =========================================================================
    reg [DIM_W-1:0] num_m_tiles;
    reg [DIM_W-1:0] num_n_tiles_chunk;   // N tiles in current N-chunk

    // Tile cursor (row-major within chunk)
    (* mark_debug = "true" *) reg [DIM_W-1:0] cur_m;
    (* mark_debug = "true" *) reg [DIM_W-1:0] cur_n;
    (* mark_debug = "true" *) reg             all_dispatched;

    // Outstanding tile counter
    (* mark_debug = "true" *) reg [DIM_W-1:0] tiles_outstanding;

    // =========================================================================
    // K-chunk and N-chunk state
    // =========================================================================
    reg [DIM_W-1:0] k_chunk_idx;      // Current K chunk index
    reg [DIM_W-1:0] num_k_chunks;     // Total K chunks
    reg [DIM_W-1:0] k_chunk_size;     // K elements in current chunk (<=1024)

    reg [DIM_W-1:0] n_chunk_idx;      // Current N chunk index
    reg [DIM_W-1:0] num_n_chunks;     // Total N chunks
    reg [DIM_W-1:0] n_chunk_size;     // N elements in current chunk (<=1024)

    // HBM addresses for current chunk
    reg [HBM_ADDR_W-1:0] act_chunk_base;   // A base for current K-chunk
    reg [HBM_ADDR_W-1:0] wgt_chunk_base;   // B base for current (K,N)-chunk

    // K-chunk column words for A prefetch
    reg [DIM_W-1:0] k_chunk_col_words;  // K / BUS_EL

    // N-chunk column words for B prefetch
    reg [DIM_W-1:0] n_chunk_col_words;  // N_chunk / BUS_EL

    // Prefetch handshake tracking
    reg pf_act_launched;
    reg pf_wgt_launched;
    reg pf_act_done_r;    // Latched done (pulses may not align)
    reg pf_wgt_done_r;

    // =========================================================================
    // Per-tile offsets within prefetch buffers
    // =========================================================================
    // A tile at (cur_m): row = cur_m*TILE, col = 0 (engine K-loop walks cols)
    wire [PF_ROW_W-1:0] a_row_off_tile = cur_m * TILE;
    wire [PF_COL_W-1:0] a_col_off_tile = {PF_COL_W{1'b0}};  // K-loop starts at 0

    // B tile at (cur_n): row = 0 (engine K-loop walks rows), col = cur_n*TILE_COL_WORDS
    wire [PF_ROW_W-1:0] b_row_off_tile = {PF_ROW_W{1'b0}};
    wire [PF_COL_W-1:0] b_col_off_tile = cur_n * TILE_COL_WORDS;

    // Per-tile URAM output coordinates (global, not chunk-relative)
    wire [URAM_ROW_W-1:0] out_row_tile      = cur_m * TILE;
    wire [URAM_COL_W-1:0] out_col_word_tile = n_chunk_idx * (PREFETCH_DIM / BUS_EL) +
                                                cur_n * TILE_COL_WORDS +
                                                out_col_offset_r;

    // K for this chunk (engine's K-loop range)
    wire [DIM_W-1:0] chunk_k = k_chunk_size;

    // =========================================================================
    // Find idle engine
    // =========================================================================
    reg [N_ENG-1:0] just_dispatched;
    reg [$clog2(N_ENG)-1:0] idle_eng;
    reg idle_found;
    integer ei;

    always @(*) begin
        idle_found = 1'b0;
        idle_eng   = 0;
        for (ei = 0; ei < N_ENG; ei = ei + 1) begin
            if (!idle_found && eng_cmd_ready[ei] && !just_dispatched[ei]) begin
                idle_eng   = ei;
                idle_found = 1'b1;
            end
        end
    end

    // Count done pulses
    reg [N_ENG-1:0] eng_done_prev;
    wire [N_ENG-1:0] eng_done_rising = eng_cmd_done & ~eng_done_prev;

    reg [3:0] done_count;
    integer di;
    always @(*) begin
        done_count = 0;
        for (di = 0; di < N_ENG; di = di + 1)
            done_count = done_count + eng_done_rising[di];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            eng_done_prev <= 0;
        else
            eng_done_prev <= eng_cmd_done;
    end

    // =========================================================================
    // Helper: min(a, b)
    // =========================================================================
    function [DIM_W-1:0] min_dim;
        input [DIM_W-1:0] a, b;
        begin
            min_dim = (a < b) ? a : b;
        end
    endfunction

    // =========================================================================
    // Main State Machine
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            cmd_ready        <= 1'b1;
            cmd_done         <= 1'b0;
            eng_cmd_valid    <= 0;
            all_dispatched   <= 1'b0;
            tiles_outstanding <= 0;
            cur_m            <= 0;
            cur_n            <= 0;
            just_dispatched  <= 0;
            pf_act_cmd_valid <= 1'b0;
            pf_wgt_cmd_valid <= 1'b0;
            pf_act_launched  <= 1'b0;
            pf_wgt_launched  <= 1'b0;
            pf_act_done_r    <= 1'b0;
            pf_wgt_done_r    <= 1'b0;
        end else begin
            cmd_done         <= 1'b0;
            eng_cmd_valid    <= 0;
            just_dispatched  <= 0;
            pf_act_cmd_valid <= 1'b0;
            pf_wgt_cmd_valid <= 1'b0;

            // Latch prefetch done pulses (may arrive on different cycles)
            if (pf_act_cmd_done) pf_act_done_r <= 1'b1;
            if (pf_wgt_cmd_done) pf_wgt_done_r <= 1'b1;

            // Decrement outstanding on engine completions
            if (|eng_done_rising)
                tiles_outstanding <= tiles_outstanding - done_count;

            case (state)
                // ---------------------------------------------------------
                ST_IDLE: begin
                    cmd_ready <= 1'b1;
                    if (cmd_valid) begin
                        state            <= ST_SETUP;
                        cmd_ready        <= 1'b0;
                        op_r             <= cmd_op;
                        m_r              <= cmd_m;
                        k_r              <= cmd_k;
                        n_r              <= cmd_n;
                        a_base_r         <= cmd_a_base;
                        b_base_r         <= cmd_b_base;
                        a_stride_r       <= cmd_a_stride;
                        b_stride_r       <= cmd_b_stride;
                        out_col_offset_r <= cmd_out_col_offset;
                    end
                end

                // ---------------------------------------------------------
                ST_SETUP: begin
                    num_m_tiles  <= (m_r + TILE - 1) / TILE;
                    num_k_chunks <= (k_r + PREFETCH_DIM - 1) / PREFETCH_DIM;
                    num_n_chunks <= (n_r + PREFETCH_DIM - 1) / PREFETCH_DIM;
                    k_chunk_idx  <= 0;
                    state        <= ST_K_CHUNK_SETUP;
                end

                // ---------------------------------------------------------
                ST_K_CHUNK_SETUP: begin
                    // Compute K-chunk parameters
                    k_chunk_size     <= min_dim(PREFETCH_DIM[DIM_W-1:0], k_r - k_chunk_idx * PREFETCH_DIM);
                    k_chunk_col_words <= min_dim(PREFETCH_DIM[DIM_W-1:0], k_r - k_chunk_idx * PREFETCH_DIM) / BUS_EL;
                    // A base for this K-chunk: advance cols by k_chunk_idx * (PREFETCH_DIM/BUS_EL)
                    act_chunk_base   <= a_base_r + k_chunk_idx * (PREFETCH_DIM / BUS_EL);
                    n_chunk_idx      <= 0;
                    state            <= ST_N_CHUNK_SETUP;
                end

                // ---------------------------------------------------------
                ST_N_CHUNK_SETUP: begin
                    // Compute N-chunk parameters
                    n_chunk_size      <= min_dim(PREFETCH_DIM[DIM_W-1:0], n_r - n_chunk_idx * PREFETCH_DIM);
                    n_chunk_col_words <= min_dim(PREFETCH_DIM[DIM_W-1:0], n_r - n_chunk_idx * PREFETCH_DIM) / BUS_EL;
                    num_n_tiles_chunk <= (min_dim(PREFETCH_DIM[DIM_W-1:0], n_r - n_chunk_idx * PREFETCH_DIM) + TILE - 1) / TILE;
                    // B base for this (K,N)-chunk:
                    // row offset = k_chunk_idx * PREFETCH_DIM rows
                    // col offset = n_chunk_idx * (PREFETCH_DIM/BUS_EL) words
                    wgt_chunk_base   <= b_base_r +
                                        k_chunk_idx * PREFETCH_DIM * b_stride_r +
                                        n_chunk_idx * (PREFETCH_DIM / BUS_EL);
                    pf_act_launched  <= 1'b0;
                    pf_wgt_launched  <= 1'b0;
                    pf_act_done_r    <= 1'b0;
                    pf_wgt_done_r    <= 1'b0;
                    state            <= ST_PREFETCH_CMD;
                end

                // ---------------------------------------------------------
                // Issue prefetch commands for both buffers
                // ---------------------------------------------------------
                ST_PREFETCH_CMD: begin
                    // Activation prefetch
                    if (!pf_act_launched) begin
                        pf_act_cmd_valid   <= 1'b1;
                        pf_act_hbm_base    <= act_chunk_base;
                        pf_act_hbm_stride  <= a_stride_r;
                        pf_act_num_rows    <= m_r;
                        pf_act_num_col_words <= k_chunk_col_words;
                        if (pf_act_cmd_valid && pf_act_cmd_ready)
                            pf_act_launched <= 1'b1;
                    end
                    // Weight prefetch
                    if (!pf_wgt_launched) begin
                        pf_wgt_cmd_valid   <= 1'b1;
                        pf_wgt_hbm_base    <= wgt_chunk_base;
                        pf_wgt_hbm_stride  <= b_stride_r;
                        pf_wgt_num_rows    <= k_chunk_size;
                        pf_wgt_num_col_words <= n_chunk_col_words;
                        if (pf_wgt_cmd_valid && pf_wgt_cmd_ready)
                            pf_wgt_launched <= 1'b1;
                    end
                    // Both launched
                    if (pf_act_launched && pf_wgt_launched) begin
                        state <= ST_WAIT_PREFETCH;
                    end
                end

                // ---------------------------------------------------------
                // Wait for both prefetch DMA engines to finish
                // ---------------------------------------------------------
                ST_WAIT_PREFETCH: begin
                    if (pf_act_done_r && pf_wgt_done_r) begin
                        cur_m            <= 0;
                        cur_n            <= 0;
                        all_dispatched   <= 1'b0;
                        tiles_outstanding <= 0;
                        state            <= ST_DISPATCH;
                    end
                end

                // ---------------------------------------------------------
                // Dispatch tiles to engines (within current chunk)
                // ---------------------------------------------------------
                ST_DISPATCH: begin
                    if (!all_dispatched && idle_found) begin
                        eng_cmd_valid[idle_eng] <= 1'b1;
                        eng_cmd_op[idle_eng*3 +: 3]     <= op_r;
                        eng_cmd_m[idle_eng*DIM_W +: DIM_W] <= TILE[DIM_W-1:0];
                        eng_cmd_k[idle_eng*DIM_W +: DIM_W] <= chunk_k;
                        eng_cmd_n[idle_eng*DIM_W +: DIM_W] <= TILE[DIM_W-1:0];
                        eng_cmd_a_row_off[idle_eng*PF_ROW_W +: PF_ROW_W] <= a_row_off_tile;
                        eng_cmd_a_col_off[idle_eng*PF_COL_W +: PF_COL_W] <= a_col_off_tile;
                        eng_cmd_b_row_off[idle_eng*PF_ROW_W +: PF_ROW_W] <= b_row_off_tile;
                        eng_cmd_b_col_off[idle_eng*PF_COL_W +: PF_COL_W] <= b_col_off_tile;
                        eng_cmd_out_row[idle_eng*URAM_ROW_W +: URAM_ROW_W] <= out_row_tile;
                        eng_cmd_out_col_word[idle_eng*URAM_COL_W +: URAM_COL_W] <= out_col_word_tile;
                        eng_cmd_first_k_chunk[idle_eng] <= (k_chunk_idx == 0);

                        tiles_outstanding <= tiles_outstanding + 1 - done_count;
                        just_dispatched[idle_eng] <= 1'b1;

                        // Advance cursor (row-major)
                        if (cur_n == num_n_tiles_chunk - 1) begin
                            cur_n <= 0;
                            if (cur_m == num_m_tiles - 1) begin
                                all_dispatched <= 1'b1;
                                state <= ST_WAIT;
                            end else begin
                                cur_m <= cur_m + 1;
                            end
                        end else begin
                            cur_n <= cur_n + 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Wait for all outstanding tiles in this chunk
                // ---------------------------------------------------------
                ST_WAIT: begin
                    if (tiles_outstanding == 0 && !(|eng_done_rising)) begin
                        state <= ST_NEXT_N_CHUNK;
                    end else if (tiles_outstanding == done_count) begin
                        state <= ST_NEXT_N_CHUNK;
                    end
                end

                // ---------------------------------------------------------
                // Advance N-chunk or go to next K-chunk
                // ---------------------------------------------------------
                ST_NEXT_N_CHUNK: begin
                    if (n_chunk_idx == num_n_chunks - 1) begin
                        state <= ST_NEXT_K_CHUNK;
                    end else begin
                        n_chunk_idx <= n_chunk_idx + 1;
                        state       <= ST_N_CHUNK_SETUP;
                    end
                end

                // ---------------------------------------------------------
                // Advance K-chunk or finish
                // ---------------------------------------------------------
                ST_NEXT_K_CHUNK: begin
                    if (k_chunk_idx == num_k_chunks - 1) begin
                        state <= ST_DONE;
                    end else begin
                        k_chunk_idx <= k_chunk_idx + 1;
                        state       <= ST_K_CHUNK_SETUP;
                    end
                end

                // ---------------------------------------------------------
                ST_DONE: begin
                    cmd_done <= 1'b1;
                    state    <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
