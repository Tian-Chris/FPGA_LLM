`include "defines.vh"

// =============================================================================
// tiling_engine.v - Master Tile Dispatcher for Multi-Engine Matmul
// =============================================================================
//
// Drop-in replacement for single matmul_controller from FSM controller's
// perspective. Accepts a matmul command, tiles the output space into
// (tile_m, tile_n) pairs, and dispatches them to idle engines.
//
// Each engine's matmul_controller handles the K-loop internally via
// tile_loaders. Output coordinates (URAM row/col) computed per tile.
//
// Updated for HBM architecture: uses HBM_ADDR_W addresses, stride
// pass-through, URAM output coordinates instead of c_base.
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

module tiling_engine #(
    parameter N_ENG      = 6,
    parameter TILE       = 32,
    parameter DIM_W      = 16,
    parameter DATA_W     = 16,
    parameter OUT_W      = 16,
    parameter ACC_W      = 32,
    parameter BUS_W      = 256,
    parameter URAM_ROW_W = 10,
    parameter URAM_COL_W = 6
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
    input  wire [URAM_COL_W-1:0] cmd_out_col_offset, // URAM column offset (for multi-head concat)
    (* mark_debug = "true" *) output reg                  cmd_ready,
    (* mark_debug = "true" *) output reg                  cmd_done,

    // Per-engine tile command interface
    output reg  [N_ENG-1:0]                    eng_cmd_valid,
    output reg  [3*N_ENG-1:0]                  eng_cmd_op,
    output reg  [DIM_W*N_ENG-1:0]              eng_cmd_m,
    output reg  [DIM_W*N_ENG-1:0]              eng_cmd_k,
    output reg  [DIM_W*N_ENG-1:0]              eng_cmd_n,
    output reg  [HBM_ADDR_W*N_ENG-1:0]        eng_cmd_a_base,
    output reg  [HBM_ADDR_W*N_ENG-1:0]        eng_cmd_b_base,
    output reg  [HBM_ADDR_W*N_ENG-1:0]        eng_cmd_a_stride,
    output reg  [HBM_ADDR_W*N_ENG-1:0]        eng_cmd_b_stride,
    output reg  [URAM_ROW_W*N_ENG-1:0]        eng_cmd_out_row,
    output reg  [URAM_COL_W*N_ENG-1:0]        eng_cmd_out_col_word,
    input  wire [N_ENG-1:0]                    eng_cmd_ready,
    input  wire [N_ENG-1:0]                    eng_cmd_done
);

    localparam TILE_COL_WORDS = TILE / BUS_ELEMS;  // 2 bus words per tile column

    // State machine
    (* mark_debug = "true" *) reg [2:0] state;
    localparam ST_IDLE     = 3'd0;
    localparam ST_SETUP    = 3'd1;
    localparam ST_DISPATCH = 3'd2;
    localparam ST_WAIT     = 3'd3;
    localparam ST_DONE     = 3'd4;

    // Registered command
    reg [2:0] op_r;
    reg [DIM_W-1:0] m_r, k_r, n_r;
    reg [HBM_ADDR_W-1:0] a_base_r, b_base_r, a_stride_r, b_stride_r;
    reg [URAM_COL_W-1:0] out_col_offset_r;

    // Tile grid dimensions
    reg [DIM_W-1:0] num_m_tiles;
    reg [DIM_W-1:0] num_n_tiles;

    // Tile cursor (row-major iteration)
    (* mark_debug = "true" *) reg [DIM_W-1:0] cur_m;
    (* mark_debug = "true" *) reg [DIM_W-1:0] cur_n;
    (* mark_debug = "true" *) reg             all_dispatched;

    // Outstanding tile counter
    (* mark_debug = "true" *) reg [DIM_W-1:0] tiles_outstanding;

    // Per-tile HBM base address calculations
    // A tile at (cur_m, cur_n): A starts at row cur_m*TILE, stride = words/row
    wire [HBM_ADDR_W-1:0] a_base_tile = a_base_r + (cur_m * TILE * a_stride_r);
    // B tile: same row base, shifted by tile column offset
    wire [HBM_ADDR_W-1:0] b_base_tile = b_base_r + (cur_n * TILE_COL_WORDS);

    // Per-tile URAM output coordinates
    wire [URAM_ROW_W-1:0] out_row_tile      = cur_m * TILE;
    wire [URAM_COL_W-1:0] out_col_word_tile = cur_n * TILE_COL_WORDS + out_col_offset_r;

    // Effective dimensions for edge tiles
    wire [DIM_W-1:0] eff_m = ((cur_m + 1) * TILE > m_r) ? (m_r - cur_m * TILE) : TILE;
    wire [DIM_W-1:0] eff_n = ((cur_n + 1) * TILE > n_r) ? (n_r - cur_n * TILE) : TILE;

    // Find an idle engine (excluding just-dispatched engine for 1-cycle mask)
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

    // Count bits in done_rising
    reg [3:0] done_count;
    integer di;
    always @(*) begin
        done_count = 0;
        for (di = 0; di < N_ENG; di = di + 1)
            done_count = done_count + eng_done_rising[di];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eng_done_prev <= 0;
        end else begin
            eng_done_prev <= eng_cmd_done;
        end
    end

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
        end else begin
            cmd_done         <= 1'b0;
            eng_cmd_valid    <= 0;    // Clear valid pulses each cycle
            just_dispatched  <= 0;    // Clear 1-cycle dispatch mask

            // Decrement outstanding on engine completions
            if (|eng_done_rising)
                tiles_outstanding <= tiles_outstanding - done_count;

            case (state)
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

                ST_SETUP: begin
                    num_m_tiles      <= (m_r + TILE - 1) / TILE;
                    num_n_tiles      <= (n_r + TILE - 1) / TILE;
                    cur_m            <= 0;
                    cur_n            <= 0;
                    all_dispatched   <= 1'b0;
                    tiles_outstanding <= 0;
                    state            <= ST_DISPATCH;
                end

                ST_DISPATCH: begin
                    if (!all_dispatched && idle_found) begin
                        // Dispatch current tile to idle engine
                        eng_cmd_valid[idle_eng] <= 1'b1;
                        eng_cmd_op[idle_eng*3 +: 3]                            <= op_r;
                        eng_cmd_m[idle_eng*DIM_W +: DIM_W]                     <= eff_m;
                        eng_cmd_k[idle_eng*DIM_W +: DIM_W]                     <= k_r;
                        eng_cmd_n[idle_eng*DIM_W +: DIM_W]                     <= eff_n;
                        eng_cmd_a_base[idle_eng*HBM_ADDR_W +: HBM_ADDR_W]     <= a_base_tile;
                        eng_cmd_b_base[idle_eng*HBM_ADDR_W +: HBM_ADDR_W]     <= b_base_tile;
                        eng_cmd_a_stride[idle_eng*HBM_ADDR_W +: HBM_ADDR_W]   <= a_stride_r;
                        eng_cmd_b_stride[idle_eng*HBM_ADDR_W +: HBM_ADDR_W]   <= b_stride_r;
                        eng_cmd_out_row[idle_eng*URAM_ROW_W +: URAM_ROW_W]     <= out_row_tile;
                        eng_cmd_out_col_word[idle_eng*URAM_COL_W +: URAM_COL_W] <= out_col_word_tile;

                        tiles_outstanding <= tiles_outstanding + 1 - done_count;
                        just_dispatched[idle_eng] <= 1'b1;

                        // Advance cursor (row-major)
                        if (cur_n == num_n_tiles - 1) begin
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
                    // If no idle engine, stay in DISPATCH and wait
                end

                ST_WAIT: begin
                    // Wait for all outstanding tiles to complete
                    if (tiles_outstanding == 0 && !( |eng_done_rising )) begin
                        state <= ST_DONE;
                    end else if (tiles_outstanding == done_count) begin
                        // This cycle's completions bring us to zero
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    cmd_done <= 1'b1;
                    state    <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
