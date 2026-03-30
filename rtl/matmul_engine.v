`include "defines.vh"

// =============================================================================
// matmul_engine.v - 32x32 Outer-Product FP16 MAC Engine
// =============================================================================
//
// Uses 1024 fp_mac_unit instances (32x32 generate grid).
// Data loading: 256-bit bus, 2 reads per 32-element row.
// Supports OP_MATMUL (standard) and OP_MATMUL_T (transposed B) via full
// B-tile buffer: for OP_MATMUL, rows of B are broadcast; for OP_MATMUL_T,
// columns of B are extracted (B[n][k] instead of B[k][n]).
// Output serialization: FP32 acc → FP16 conversion, 16 elements per write.
//
// MAC pipeline drain uses parameterized counter (MAC_DEPTH) instead of
// hardcoded delay chain — engine is MAC-latency-agnostic.
// =============================================================================

module matmul_engine #(
    parameter TILE      = 32,
    parameter DATA_W    = 16,
    parameter ACC_W     = 32,
    parameter OUT_W     = 16,
    parameter BUS_W     = 256,
    parameter BUS_EL    = BUS_W / DATA_W,   // 16 elements per bus read
    parameter MAC_DEPTH = 3                  // MAC pipeline stages for drain timing
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Control interface
    input  wire                 start,
    input  wire [2:0]           op_type,
    (* mark_debug = "true" *) output reg                  busy,
    (* mark_debug = "true" *) output reg                  done,

    // Data input - A matrix (256-bit bus = 16 INT16 elements per read)
    input  wire                 a_valid,
    input  wire [BUS_W-1:0]     a_data,

    // Data input - B matrix (256-bit bus = 16 INT16 elements per read)
    input  wire                 b_valid,
    input  wire [BUS_W-1:0]     b_data,

    // Tile control signals (from controller)
    input  wire                 tile_start,
    input  wire                 tile_done,
    input  wire [4:0]           tile_row,
    input  wire [4:0]           tile_col,
    input  wire                 first_tile,    // Clear MACs only on first k-tile
    input  wire [4:0]           tile_k_limit,  // Last valid compute_k index (0-based)

    // Output interface: BUS_EL (16) FP16 per write = 256 bits
    (* mark_debug = "true" *) output reg                  out_valid,
    output reg  [BUS_W-1:0]     out_data,
    output reg  [4:0]           out_row,
    output reg  [4:0]           out_col,

    // Backpressure from URAM write arbiter
    (* mark_debug = "true" *) input  wire                 out_stall,

    // Compute phase done pulse (for controller handshake)
    output wire                 compute_done
);

    localparam WORDS_PER_ROW = TILE / BUS_EL;       // 2
    localparam BUF_BEATS     = TILE * WORDS_PER_ROW; // 64
    localparam [2:0] OP_T    = 3'd1;                // OP_MATMUL_T

    // =========================================================================
    // A-tile buffer: TILE x TILE array of FP16 bit patterns
    // =========================================================================
    reg [DATA_W-1:0] a_buf [0:TILE-1][0:TILE-1];

    // Counters for multi-cycle loading
    reg [4:0] a_row_cnt;        // Which row of A we're loading
    reg       a_half;           // 0 = first 16 elems, 1 = second 16 elems

    // =========================================================================
    // B-tile buffer: TILE x TILE (full 2D for transpose support)
    // =========================================================================
    reg [DATA_W-1:0] b_buf [0:TILE-1][0:TILE-1];
    reg [4:0] b_load_row;       // Which row of B we're loading
    reg       b_load_half;      // 0 = first 16 elems, 1 = second 16 elems
    reg [6:0] b_load_cnt;       // Total b_valid beats received: 0..BUF_BEATS
    wire      b_loaded = (b_load_cnt == BUF_BEATS[6:0]);

    // Registered op_type
    reg [2:0] op_r;

    // =========================================================================
    // Compute phase: iterate k from 0 to TILE-1 after B is fully loaded
    // =========================================================================
    reg       computing;
    reg [4:0] compute_k;
    reg       compute_done_flag;   // Stays set until tile_start clears it

    // B broadcast: frozen row/column extracted from b_buf during compute
    reg [DATA_W-1:0] b_frozen [0:TILE-1];
    // MAC control
    reg  mac_clear;
    reg  mac_enable;

    // Drain counter: replaces hardcoded tile_done delay chain
    reg        flush_pending;
    reg [4:0]  flush_col;
    reg [3:0]  drain_cnt;

    integer i, j;

    // =========================================================================
    // FP MAC unit wires
    // =========================================================================
    wire [ACC_W-1:0] mac_acc [0:TILE-1][0:TILE-1];

    // Broadcast signals for outer-product (FP16 bit patterns, not signed)
    reg  [DATA_W-1:0] a_broadcast_r [0:TILE-1]; // a_buf[row][k] — registered
    wire [DATA_W-1:0] b_broadcast   [0:TILE-1]; // b_frozen[col]

    genvar gi, gj;
    generate
        for (gi = 0; gi < TILE; gi = gi + 1) begin : mac_row
            always @(posedge clk) begin
                a_broadcast_r[gi] <= a_buf[gi][compute_k];
            end

            for (gj = 0; gj < TILE; gj = gj + 1) begin : mac_col
                fp_mac_unit #(
                    .DATA_W(DATA_W),
                    .ACC_W(ACC_W)
                ) u_mac (
                    .clk(clk),
                    .rst_n(rst_n),
                    .clear(mac_clear),
                    .enable(mac_enable),
                    .a_in(a_broadcast_r[gi]),
                    .b_in(b_broadcast[gj]),
                    .acc_out(mac_acc[gi][gj])
                );
            end
        end
    endgenerate

    // B broadcast assignment (reads from frozen buffer, stable during MAC)
    generate
        for (gj = 0; gj < TILE; gj = gj + 1) begin : b_bcast
            assign b_broadcast[gj] = b_frozen[gj];
        end
    endgenerate

    // =========================================================================
    // Op type registration
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) op_r <= 3'd0;
        else if (start) op_r <= op_type;
    end

    // =========================================================================
    // Input Registration & A-Buffer Loading
    // =========================================================================
    // Each A row needs 2 bus reads (16 elems each) to fill 32 elements.
    // a_half=0: store elements [0:15], a_half=1: store elements [16:31], advance row.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_row_cnt <= 0;
            a_half    <= 0;
            for (i = 0; i < TILE; i = i + 1)
                for (j = 0; j < TILE; j = j + 1)
                    a_buf[i][j] <= 0;
        end else begin
            if (tile_start) begin
                a_row_cnt <= 0;
                a_half    <= 0;
            end else if (a_valid) begin
                // Unpack 16 elements from bus into a_buf
                for (j = 0; j < BUS_EL; j = j + 1) begin
                    if (!a_half)
                        a_buf[a_row_cnt][j] <= a_data[j*DATA_W +: DATA_W];
                    else
                        a_buf[a_row_cnt][j + BUS_EL] <= a_data[j*DATA_W +: DATA_W];
                end

                if (a_half) begin
                    // Second half received: row complete, advance
                    a_row_cnt <= a_row_cnt + 1;
                    a_half    <= 0;
                end else begin
                    a_half <= 1;
                end
            end
        end
    end

    // =========================================================================
    // B-Buffer Loading (full 2D buffer for transpose support)
    // =========================================================================
    // Each B row needs 2 bus reads (16 elems each) to fill 32 elements.
    // All TILE rows loaded into b_buf before compute phase starts.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_load_row  <= 0;
            b_load_half <= 0;
            b_load_cnt  <= 0;
            for (i = 0; i < TILE; i = i + 1)
                for (j = 0; j < TILE; j = j + 1)
                    b_buf[i][j] <= 0;
        end else begin
            if (tile_start) begin
                b_load_row  <= 0;
                b_load_half <= 0;
                b_load_cnt  <= 0;
            end else if (b_valid && !b_loaded) begin
                for (j = 0; j < BUS_EL; j = j + 1) begin
                    if (!b_load_half)
                        b_buf[b_load_row][j] <= b_data[j*DATA_W +: DATA_W];
                    else
                        b_buf[b_load_row][j + BUS_EL] <= b_data[j*DATA_W +: DATA_W];
                end
                b_load_cnt <= b_load_cnt + 1;
                if (b_load_half) begin
                    b_load_row  <= b_load_row + 1;
                    b_load_half <= 0;
                end else begin
                    b_load_half <= 1;
                end
            end
        end
    end

    // =========================================================================
    // Compute Phase State Machine
    // =========================================================================
    // After b_loaded, iterate compute_k from 0 to tile_k_limit.
    // Each cycle extracts a row (OP_MATMUL) or column (OP_MATMUL_T) from b_buf
    // into b_frozen. MAC fires one cycle later (mac_enable = computing delayed 1).
    // tile_k_limit is normally TILE-1 (31) but can be smaller for the last k-tile
    // when cmd_k is not a multiple of TILE (e.g., decode attention with k=9).
    reg [4:0] k_limit_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            computing         <= 1'b0;
            compute_k         <= 5'd0;
            compute_done_flag <= 1'b0;
            k_limit_r         <= TILE[4:0] - 1;
        end else begin
            if (tile_start) begin
                computing         <= 1'b0;
                compute_k         <= 5'd0;
                compute_done_flag <= 1'b0;
                k_limit_r         <= tile_k_limit;
            end else if (b_loaded && !computing && !compute_done_flag) begin
                // Start compute phase
                computing <= 1'b1;
                compute_k <= 5'd0;
            end else if (computing) begin
                if (compute_k == k_limit_r) begin
                    computing         <= 1'b0;
                    compute_done_flag <= 1'b1;
                end else begin
                    compute_k <= compute_k + 1;
                end
            end
        end
    end

    // =========================================================================
    // B Frozen Extraction (from b_buf during compute phase)
    // =========================================================================
    // OP_MATMUL:   b_frozen[n] = b_buf[compute_k][n]  (row k of B)
    // OP_MATMUL_T: b_frozen[n] = b_buf[n][compute_k]  (column k of B = B[n][k])
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < TILE; j = j + 1)
                b_frozen[j] <= 0;
        end else if (computing) begin
            for (j = 0; j < TILE; j = j + 1) begin
                if (op_r == OP_T)
                    b_frozen[j] <= b_buf[j][compute_k];
                else
                    b_frozen[j] <= b_buf[compute_k][j];
            end
        end
    end

    // =========================================================================
    // MAC Clear & Enable
    // =========================================================================
    // mac_clear: pulse when tile_start on first k-tile
    // mac_enable: fires 1 cycle after computing starts (aligns with settled b_frozen)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_clear  <= 1'b0;
            mac_enable <= 1'b0;
        end else begin
            mac_clear  <= tile_start && first_tile;
            mac_enable <= computing;
        end
    end

    // =========================================================================
    // Compute Done Output
    // =========================================================================
    // Pulses high for 1 cycle on the falling edge of mac_enable
    // (all k-steps have been processed for this tile)
    reg mac_enable_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mac_enable_prev <= 1'b0;
        else        mac_enable_prev <= mac_enable;
    end
    assign compute_done = mac_enable_prev && !mac_enable;

    // =========================================================================
    // Drain Counter — replaces hardcoded 5-stage delay chain
    // =========================================================================
    // When tile_done arrives, latch it and count MAC_DEPTH cycles for the
    // MAC pipeline to drain. Then trigger output serialization.
    // This makes the engine MAC-latency-agnostic.

    // Consume signal: drain done → output serialization triggered
    wire flush_consumed = flush_pending && drain_cnt == 4'd0
                          && !start_pending && !outputting;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flush_pending <= 1'b0;
            flush_col     <= 5'd0;
            drain_cnt     <= 4'd0;
        end else begin
            if (tile_start) begin
                flush_pending <= 1'b0;
                drain_cnt     <= 4'd0;
            end else if (tile_done) begin
                flush_pending <= 1'b1;
                flush_col     <= tile_col;
                drain_cnt     <= MAC_DEPTH[3:0];
            end else if (flush_consumed) begin
                flush_pending <= 1'b0;
            end else if (flush_pending && drain_cnt > 4'd0) begin
                drain_cnt <= drain_cnt - 4'd1;
            end
        end
    end

    // =========================================================================
    // Output Serialization
    // =========================================================================
    // 32 cols / 16 per write = 2 sub-column writes per row
    // 32 rows * 2 writes = 64 output cycles per tile

    reg [4:0] out_row_cnt;
    reg       out_sub_col;     // 0-1: which 16-element half
    reg       outputting;
    reg       start_pending;
    reg [4:0] tile_col_saved;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid      <= 1'b0;
            out_data       <= 0;
            out_row        <= 0;
            out_col        <= 0;
            out_row_cnt    <= 0;
            out_sub_col    <= 0;
            outputting     <= 1'b0;
            start_pending  <= 1'b0;
            tile_col_saved <= 0;
        end else begin
            // NOTE: No default out_valid <= 0 here. The engine HOLDS
            // out_valid high during stalls so the controller can capture
            // the beat when the stall lifts. Without this, a 1-cycle
            // pipeline bubble causes lost beats when the arbiter denies
            // the write.

            // Drain counter expired → trigger output serialization
            if (flush_pending && drain_cnt == 4'd0 && !start_pending && !outputting) begin
                start_pending  <= 1'b1;
                tile_col_saved <= flush_col;
            end

            // Wait for MAC pipeline to drain before starting output
            if (start_pending && !mac_enable && !outputting) begin
                start_pending <= 1'b0;
                outputting    <= 1'b1;
                out_row_cnt   <= 0;
                out_sub_col   <= 0;
                out_valid     <= 1'b0;
            end

            if (outputting && !out_stall) begin
                out_valid <= 1'b1;
                out_row   <= out_row_cnt;
                out_col   <= tile_col_saved;

                // Pack 16 FP16 elements: FP32 acc → FP16 conversion
                for (j = 0; j < BUS_EL; j = j + 1) begin
                    out_data[j*OUT_W +: OUT_W] <= fp32_to_fp16_func(mac_acc[out_row_cnt][out_sub_col * BUS_EL + j]);
                end

                if (out_sub_col) begin
                    // Both halves done for this row
                    out_sub_col <= 0;
                    if (out_row_cnt == TILE - 1) begin
                        outputting <= 1'b0;
                    end else begin
                        out_row_cnt <= out_row_cnt + 1;
                    end
                end else begin
                    out_sub_col <= 1;
                end
            end

            // Clear out_valid when not outputting, BUT hold it during a
            // stall so the last beat isn't lost.  Once the stall lifts,
            // mm_out_new fires (consuming the beat) and this condition
            // becomes true in the same cycle, clearing out_valid via NBA.
            // No infinite re-issue: out_valid goes to 0 the cycle after
            // consumption, so mm_out_new cannot fire again.
            if (!outputting && !(out_valid && out_stall))
                out_valid <= 1'b0;
        end
    end

    // =========================================================================
    // FP32 → FP16 Conversion (replaces saturate)
    // =========================================================================
    function [OUT_W-1:0] fp32_to_fp16_func;
        input [ACC_W-1:0] val;
        reg        sign;
        reg [7:0]  exp;
        reg [22:0] mant;
        reg signed [8:0] new_exp;
        reg [9:0]  trunc_mant;
        reg        guard, rnd, sticky;
        reg        round_up;
        reg [10:0] rounded;
        reg [9:0]  rmant;
        reg signed [8:0] rexp;
        begin
            sign = val[31];
            exp  = val[30:23];
            mant = val[22:0];
            new_exp = {1'b0, exp} - 9'sd112;

            if (exp == 8'hFF && mant != 23'd0)
                fp32_to_fp16_func = {sign, 5'b11111, 1'b1, mant[21:13]};  // NaN
            else if (exp == 8'hFF)
                fp32_to_fp16_func = {sign, 5'b11111, 10'd0};              // Inf
            else if (exp == 8'd0)
                fp32_to_fp16_func = {sign, 15'd0};                        // Zero
            else begin
                trunc_mant = mant[22:13];
                guard   = mant[12];
                rnd     = mant[11];
                sticky  = |mant[10:0];
                round_up = guard && (rnd || sticky || trunc_mant[0]);
                rounded = {1'b0, trunc_mant} + {10'd0, round_up};
                if (rounded[10]) begin
                    rmant = 10'd0;
                    rexp = new_exp + 9'sd1;
                end else begin
                    rmant = rounded[9:0];
                    rexp = new_exp;
                end

                if (rexp >= 9'sd31)
                    fp32_to_fp16_func = {sign, 5'b11111, 10'd0};  // Overflow → Inf
                else if (rexp <= 9'sd0)
                    fp32_to_fp16_func = {sign, 15'd0};            // Underflow → zero
                else
                    fp32_to_fp16_func = {sign, rexp[4:0], rmant};
            end
        end
    endfunction

    // =========================================================================
    // Busy/Done Control
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start)
                busy <= 1'b1;

            if (outputting && !out_stall && out_row_cnt == TILE - 1 && out_sub_col) begin
                done <= 1'b1;
                busy <= 1'b0;
            end
        end
    end

endmodule


// =============================================================================
// matmul_controller.v - Per-Engine Wrapper (URAM Prefetch Architecture)
// =============================================================================
//
// Wraps matmul_engine with URAM prefetch buffer read interfaces.
// Tile commands come from the tiling_engine dispatcher.
//
// K-loop is managed here: for each k-tile, the controller:
//   1. Reads tile data from shared URAM prefetch buffers (act + wgt)
//   2. Streams data into the matmul_engine
//   3. Waits for engine compute phase to finish
//   4. After the last k-tile, triggers output serialization
//
// No tile_loader or HBM access — data is pre-loaded into URAM by hbm_prefetch.
// Output goes to URAM accumulation buffer (column-sharded write port).
// =============================================================================

module matmul_controller #(
    parameter DATA_W      = 16,
    parameter OUT_W       = 16,
    parameter ACC_W       = 32,
    parameter TILE        = 32,
    parameter BUS_W       = 256,
    parameter DIM_W       = 16,
    parameter HBM_ADDR_W  = 28,
    parameter URAM_ROW_W  = 10,    // $clog2(1024)
    parameter URAM_COL_W  = 6,     // $clog2(64)
    parameter PF_ROW_W    = 10,    // prefetch buffer row width
    parameter PF_COL_W    = 6      // prefetch buffer col width
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // -----------------------------------------------------------------
    // Tile command interface (from tiling_engine)
    // -----------------------------------------------------------------
    input  wire                     cmd_valid,
    input  wire [2:0]               cmd_op,
    input  wire [DIM_W-1:0]         cmd_m,
    input  wire [DIM_W-1:0]         cmd_k,
    input  wire [DIM_W-1:0]         cmd_n,
    input  wire [PF_ROW_W-1:0]     cmd_a_row_off,     // A tile row offset in prefetch URAM
    input  wire [PF_COL_W-1:0]     cmd_a_col_off,     // A tile col offset in prefetch URAM
    input  wire [PF_ROW_W-1:0]     cmd_b_row_off,     // B tile row offset in prefetch URAM
    input  wire [PF_COL_W-1:0]     cmd_b_col_off,     // B tile col offset in prefetch URAM
    input  wire [URAM_ROW_W-1:0]   cmd_out_row,       // URAM output starting row
    input  wire [URAM_COL_W-1:0]   cmd_out_col_word,  // URAM output starting col word
    input  wire                     cmd_first_k_chunk, // 1=first k-chunk (overwrite), 0=accumulate
    input  wire                     cmd_last_k_chunk,  // 1=last k-chunk (apply bias if has_bias)
    input  wire                     cmd_has_bias,      // 1=add bias on last k-chunk output
    (* mark_debug = "true" *) output reg                      cmd_ready,
    (* mark_debug = "true" *) output reg                      cmd_done,

    // -----------------------------------------------------------------
    // Weight URAM prefetch read interface
    // -----------------------------------------------------------------
    output reg                      wgt_uram_rd_en,
    output reg  [PF_ROW_W-1:0]     wgt_uram_rd_row,
    output reg  [PF_COL_W-1:0]     wgt_uram_rd_col_word,
    input  wire [BUS_W-1:0]        wgt_uram_rd_data,
    input  wire                     wgt_uram_rd_valid,

    // -----------------------------------------------------------------
    // Activation URAM prefetch read interface
    // -----------------------------------------------------------------
    output reg                      act_uram_rd_en,
    output reg  [PF_ROW_W-1:0]     act_uram_rd_row,
    output reg  [PF_COL_W-1:0]     act_uram_rd_col_word,
    input  wire [BUS_W-1:0]        act_uram_rd_data,
    input  wire                     act_uram_rd_valid,

    // -----------------------------------------------------------------
    // URAM write interface (to uram_accum_buf)
    // -----------------------------------------------------------------
    output reg                      uram_wr_en,
    output reg  [URAM_ROW_W-1:0]   uram_wr_row,
    output reg  [URAM_COL_W-1:0]   uram_wr_col_word,
    output reg  [BUS_W-1:0]        uram_wr_data,
    output reg                      uram_wr_accum,     // 1=accumulate (add to existing)

    // Backpressure from URAM write arbiter
    input  wire                     uram_wr_accept,

    // -----------------------------------------------------------------
    // Bias read interface (from tiling_engine bias_buf)
    // -----------------------------------------------------------------
    output wire [7:0]               bias_rd_addr,
    input  wire [BUS_W-1:0]        bias_rd_data
);

    // FP16 add (inlined from fp_funcs.vh to avoid include-guard conflict)
    function [15:0] fp16_add_comb;
        input [15:0] a, b;
        reg        a_s, b_s, lg_s, sm_s, res_s, eff_sub;
        reg [4:0]  a_e, b_e, lg_e, sm_e;
        reg [9:0]  a_m, b_m, lg_mr, sm_mr;
        reg        a_z, b_z;
        reg [4:0]  ediff;
        reg [3:0]  shift;
        reg [13:0] lg_ext, sm_ext, aligned, restored;
        reg        sticky_bit;
        reg [14:0] sum_m;
        reg [3:0]  lzc;
        reg [14:0] norm_m;
        reg [5:0]  norm_e;
        reg        norm_sticky;
        reg [9:0]  fmant;
        reg        g, r, s_all, rup;
        reg [10:0] rounded;
        reg [9:0]  rmant;
        reg [5:0]  rexp;
        integer    k;
        begin
            a_s = a[15]; a_e = a[14:10]; a_m = a[9:0];
            b_s = b[15]; b_e = b[14:10]; b_m = b[9:0];
            a_z = (a_e == 5'd0); b_z = (b_e == 5'd0);
            if ((a_e == 5'd31) || (b_e == 5'd31)) begin
                if (a_e == 5'd31 && a_m != 0)      fp16_add_comb = a;
                else if (b_e == 5'd31 && b_m != 0)  fp16_add_comb = b;
                else fp16_add_comb = (a_e == 5'd31) ? a : b;
            end else if (a_z && b_z) begin
                fp16_add_comb = {a_s & b_s, 15'd0};
            end else if (a_z) begin
                fp16_add_comb = b;
            end else if (b_z) begin
                fp16_add_comb = a;
            end else begin
                if (a_e > b_e || (a_e == b_e && a_m >= b_m)) begin
                    lg_s = a_s; lg_e = a_e; lg_mr = a_m;
                    sm_s = b_s; sm_e = b_e; sm_mr = b_m;
                end else begin
                    lg_s = b_s; lg_e = b_e; lg_mr = b_m;
                    sm_s = a_s; sm_e = a_e; sm_mr = a_m;
                end
                res_s = lg_s;
                eff_sub = lg_s ^ sm_s;
                ediff = lg_e - sm_e;
                shift = (ediff > 5'd14) ? 4'd14 : ediff[3:0];
                lg_ext = {1'b1, lg_mr, 3'b000};
                sm_ext = {1'b1, sm_mr, 3'b000};
                aligned = sm_ext >> shift;
                restored = aligned << shift;
                sticky_bit = (restored != sm_ext);
                if (eff_sub)
                    sum_m = {1'b0, lg_ext} - {1'b0, aligned} - {14'd0, sticky_bit};
                else
                    sum_m = {1'b0, lg_ext} + {1'b0, aligned};
                if (sum_m == 15'd0) begin
                    fp16_add_comb = 16'd0;
                end else begin
                    lzc = 4'd15;
                    for (k = 14; k >= 0; k = k - 1)
                        if (sum_m[k] && lzc == 4'd15) lzc = 14 - k;
                    norm_sticky = sticky_bit;
                    if (lzc == 4'd0) begin
                        norm_sticky = sticky_bit | sum_m[0];
                        norm_m = {1'b0, sum_m[14:1]};
                        norm_e = {1'b0, lg_e} + 6'd1;
                    end else if (lzc == 4'd1) begin
                        norm_m = sum_m;
                        norm_e = {1'b0, lg_e};
                    end else begin
                        norm_m = sum_m << (lzc - 4'd1);
                        norm_e = {1'b0, lg_e} - {2'd0, lzc} + 6'd1;
                    end
                    fmant = norm_m[12:3];
                    g = norm_m[2]; r = norm_m[1];
                    s_all = norm_m[0] | norm_sticky;
                    rup = g && (r || s_all || fmant[0]);
                    rounded = {1'b0, fmant} + {10'd0, rup};
                    if (rounded[10]) begin
                        rmant = 10'd0; rexp = norm_e + 6'd1;
                    end else begin
                        rmant = rounded[9:0]; rexp = norm_e;
                    end
                    // rexp[5] set means norm_e wrapped negative (lzc > lg_e+1):
                    // flush to zero before the >= 31 overflow check fires.
                    if (rexp[5] || rexp == 6'd0)
                        fp16_add_comb = {res_s, 15'd0};
                    else if (rexp >= 6'd31)
                        fp16_add_comb = {res_s, 5'b11111, 10'd0};
                    else
                        fp16_add_comb = {res_s, rexp[4:0], rmant};
                end
            end
        end
    endfunction

    // =====================================================================
    // Constants
    // =====================================================================
    localparam BUS_EL        = BUS_W / DATA_W;           // 16
    localparam WORDS_PER_ROW = TILE / BUS_EL;            // 2
    localparam BUF_DEPTH     = TILE * WORDS_PER_ROW;     // 64
    localparam TILE_W        = $clog2(TILE);             // 5

    // =====================================================================
    // Matmul Engine Signals
    // =====================================================================
    wire        mm_busy, mm_done;
    wire        mm_compute_done;
    wire        mm_out_valid;
    wire [BUS_W-1:0] mm_out_data;
    wire [4:0]  mm_out_row, mm_out_col;

    reg         tile_start_r;
    reg         tile_done_r;
    reg         first_tile_r;

    // =====================================================================
    // State Machine (no ST_LOAD_CMD / ST_WAIT_LOAD — data already in URAM)
    // =====================================================================
    (* mark_debug = "true" *) reg [3:0] state;
    localparam ST_IDLE          = 4'd0;
    localparam ST_TILE_START    = 4'd3;   // Pulse tile_start
    localparam ST_FEED_A        = 4'd4;   // Stream A data from act URAM
    localparam ST_FEED_B        = 4'd5;   // Stream B data from wgt URAM
    localparam ST_WAIT_COMPUTE  = 4'd6;   // Wait for engine compute phase
    localparam ST_NEXT_K        = 4'd7;   // Advance k-tile or finish
    localparam ST_FLUSH         = 4'd8;   // Wait for engine output complete
    localparam ST_DONE          = 4'd9;

    // =====================================================================
    // Registered Command
    // =====================================================================
    reg [2:0]              op_r;
    reg [DIM_W-1:0]        m_r, k_r, n_r;
    reg [PF_ROW_W-1:0]    a_row_off_r, b_row_off_r;
    reg [PF_COL_W-1:0]    a_col_off_r, b_col_off_r;
    reg [URAM_ROW_W-1:0]  out_row_start_r;
    reg [URAM_COL_W-1:0]  out_col_word_start_r;

    // K-loop state
    reg [DIM_W-1:0]        num_k_tiles;
    reg [DIM_W-1:0]        k_tile_idx;
    reg                     first_k_chunk_r;
    reg                     last_k_chunk_r;
    reg                     has_bias_r;

    // Last k-tile may have fewer than TILE valid elements.
    // last_tile_k_limit = (cmd_k % TILE == 0) ? TILE-1 : (cmd_k % TILE) - 1
    // For non-last tiles, k_limit = TILE-1.
    reg [4:0]              last_tile_k_limit;
    wire [4:0]             cur_tile_k_limit = (k_tile_idx == num_k_tiles - 1)
                                              ? last_tile_k_limit
                                              : (TILE[4:0] - 1);

    // Data feed counter
    reg [6:0] feed_cnt;  // 0..64 (needs 7 bits)

    reg mm_done_r;  // Latched mm_done for safe flush->done transition

    // =====================================================================
    // Main FSM
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            cmd_ready        <= 1'b1;
            cmd_done         <= 1'b0;
            tile_start_r     <= 1'b0;
            tile_done_r      <= 1'b0;
            first_tile_r     <= 1'b0;
            feed_cnt         <= 7'd0;
            k_tile_idx       <= {DIM_W{1'b0}};
            num_k_tiles      <= {DIM_W{1'b0}};
            wgt_uram_rd_en   <= 1'b0;
            act_uram_rd_en   <= 1'b0;
            mm_done_r        <= 1'b0;
            first_k_chunk_r  <= 1'b1;
            last_k_chunk_r   <= 1'b1;
            has_bias_r       <= 1'b0;
            last_tile_k_limit <= TILE[4:0] - 1;
        end else begin
            // Defaults
            cmd_done         <= 1'b0;
            tile_start_r     <= 1'b0;
            tile_done_r      <= 1'b0;
            wgt_uram_rd_en   <= 1'b0;
            act_uram_rd_en   <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                ST_IDLE: begin
                    cmd_ready <= 1'b1;
                    if (cmd_valid && cmd_ready) begin
                        state         <= ST_TILE_START;
                        cmd_ready     <= 1'b0;
                        mm_done_r     <= 1'b0;
                        op_r          <= cmd_op;
                        m_r           <= cmd_m;
                        k_r           <= cmd_k;
                        n_r           <= cmd_n;
                        a_row_off_r   <= cmd_a_row_off;
                        a_col_off_r   <= cmd_a_col_off;
                        b_row_off_r   <= cmd_b_row_off;
                        b_col_off_r   <= cmd_b_col_off;
                        out_row_start_r     <= cmd_out_row;
                        out_col_word_start_r <= cmd_out_col_word;
                        first_k_chunk_r     <= cmd_first_k_chunk;
                        last_k_chunk_r      <= cmd_last_k_chunk;
                        has_bias_r          <= cmd_has_bias;
                        // K-loop init
                        num_k_tiles   <= (cmd_k + TILE - 1) >> TILE_W;
                        k_tile_idx    <= {DIM_W{1'b0}};
                        // Last tile's k limit: (cmd_k % TILE) - 1, or TILE-1 if exact multiple
                        last_tile_k_limit <= (cmd_k[4:0] == 5'd0)
                                             ? (TILE[4:0] - 1)
                                             : (cmd_k[4:0] - 1);
                    end
                end

                // ---------------------------------------------------------
                // Pulse tile_start for 1 cycle
                // ---------------------------------------------------------
                ST_TILE_START: begin
                    tile_start_r <= 1'b1;
                    first_tile_r <= (k_tile_idx == 0);
                    feed_cnt     <= 7'd0;
                    state        <= ST_FEED_A;
                end

                // ---------------------------------------------------------
                // Stream A data from activation URAM prefetch buffer (64 beats)
                // feed_cnt[6:1] = row within tile (0..31)
                // feed_cnt[0]   = word within row (0..1)
                // ---------------------------------------------------------
                ST_FEED_A: begin
                    if (feed_cnt < BUF_DEPTH) begin
                        act_uram_rd_en       <= 1'b1;
                        act_uram_rd_row      <= a_row_off_r + feed_cnt[5:1];
                        act_uram_rd_col_word <= a_col_off_r + feed_cnt[0];
                        feed_cnt <= feed_cnt + 1;
                    end else begin
                        feed_cnt <= 7'd0;
                        state    <= ST_FEED_B;
                    end
                end

                // ---------------------------------------------------------
                // Stream B data from weight URAM prefetch buffer (64 beats)
                // ---------------------------------------------------------
                ST_FEED_B: begin
                    if (feed_cnt < BUF_DEPTH) begin
                        wgt_uram_rd_en       <= 1'b1;
                        wgt_uram_rd_row      <= b_row_off_r + feed_cnt[5:1];
                        wgt_uram_rd_col_word <= b_col_off_r + feed_cnt[0];
                        feed_cnt <= feed_cnt + 1;
                    end else begin
                        feed_cnt <= 7'd0;
                        state    <= ST_WAIT_COMPUTE;
                    end
                end

                // ---------------------------------------------------------
                // Wait for engine compute phase to finish
                // ---------------------------------------------------------
                ST_WAIT_COMPUTE: begin
                    if (mm_compute_done) begin
                        if (k_tile_idx == num_k_tiles - 1)
                            tile_done_r <= 1'b1;
                        state <= ST_NEXT_K;
                    end
                end

                // ---------------------------------------------------------
                // Advance k-tile or go to flush
                // ---------------------------------------------------------
                ST_NEXT_K: begin
                    if (k_tile_idx == num_k_tiles - 1) begin
                        state <= ST_FLUSH;
                    end else begin
                        // Next k-tile: advance chunk-relative offsets
                        k_tile_idx  <= k_tile_idx + 1;
                        // A advances along K columns: col offset += WORDS_PER_ROW
                        a_col_off_r <= a_col_off_r + WORDS_PER_ROW[PF_COL_W-1:0];
                        // B: for standard matmul, K is the row dimension → advance rows
                        //    for transposed matmul, K is the column dimension → advance cols
                        if (op_r == OP_MATMUL_T)
                            b_col_off_r <= b_col_off_r + WORDS_PER_ROW[PF_COL_W-1:0];
                        else
                            b_row_off_r <= b_row_off_r + TILE[PF_ROW_W-1:0];
                        state       <= ST_TILE_START;
                    end
                end

                // ---------------------------------------------------------
                // Wait for engine output + last URAM write accepted
                // ---------------------------------------------------------
                ST_FLUSH: begin
                    if (mm_done)
                        mm_done_r <= 1'b1;
                    if (mm_done_r && !wr_pending)
                        state <= ST_DONE;
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

    // =====================================================================
    // Matmul Engine Instance
    // =====================================================================
    matmul_engine #(
        .TILE(TILE),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .OUT_W(OUT_W),
        .BUS_W(BUS_W),
        .BUS_EL(BUS_W / DATA_W)
    ) u_matmul (
        .clk(clk),
        .rst_n(rst_n),
        .start(state == ST_TILE_START && k_tile_idx == 0),
        .op_type(op_r),
        .busy(mm_busy),
        .done(mm_done),
        .a_valid(act_uram_rd_valid),
        .a_data(act_uram_rd_data),
        .b_valid(wgt_uram_rd_valid),
        .b_data(wgt_uram_rd_data),
        .tile_start(tile_start_r),
        .tile_done(tile_done_r),
        .tile_row(5'd0),
        .tile_col(5'd0),
        .first_tile(first_tile_r),
        .tile_k_limit(cur_tile_k_limit),
        .out_valid(mm_out_valid),
        .out_data(mm_out_data),
        .out_row(mm_out_row),
        .out_col(mm_out_col),
        .out_stall(mm_out_stall),
        .compute_done(mm_compute_done)
    );

    // =====================================================================
    // Bias Add — element-wise FP16 add on matmul output
    // =====================================================================
    // Bias read address = global URAM column word for current output
    assign bias_rd_addr = out_col_word_start_r + wr_sub_col;

    // Generate biased output: 16× parallel fp16_add_comb
    wire [BUS_W-1:0] biased_data;
    genvar bi;
    generate
        for (bi = 0; bi < BUS_W / DATA_W; bi = bi + 1) begin : gen_bias_add
            assign biased_data[bi*DATA_W +: DATA_W] =
                (has_bias_r && last_k_chunk_r) ? fp16_add_comb(mm_out_data[bi*DATA_W +: DATA_W],
                                                                bias_rd_data[bi*DATA_W +: DATA_W])
                                               : mm_out_data[bi*DATA_W +: DATA_W];
        end
    endgenerate

    // =====================================================================
    // URAM Write Control — with backpressure from write arbiter
    // =====================================================================
    reg wr_sub_col;
    reg wr_pending;
    wire mm_out_stall = wr_pending && !uram_wr_accept;


    wire mm_out_new = mm_out_valid && !mm_out_stall;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_sub_col <= 1'b0;
        else if (mm_out_new) wr_sub_col <= ~wr_sub_col;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_pending       <= 1'b0;
            uram_wr_en       <= 1'b0;
            uram_wr_row      <= {URAM_ROW_W{1'b0}};
            uram_wr_col_word <= {URAM_COL_W{1'b0}};
            uram_wr_data     <= {BUS_W{1'b0}};
            uram_wr_accum    <= 1'b0;
        end else begin
            if (mm_out_new) begin
                // synthesis translate_off
                if (has_bias_r && wr_sub_col == 0 && mm_out_row == 0)
                    $display("[MC %0t] BIAS row0 col0: raw=%h bias=%h biased=%h addr=%0d",
                             $time, mm_out_data[15:0], bias_rd_data[15:0], biased_data[15:0], bias_rd_addr);
                // synthesis translate_on
                wr_pending       <= 1'b1;
                uram_wr_en       <= 1'b1;
                uram_wr_data     <= biased_data;
                uram_wr_row      <= out_row_start_r + mm_out_row;
                uram_wr_col_word <= out_col_word_start_r + wr_sub_col;
                uram_wr_accum    <= !first_k_chunk_r;
            end else if (wr_pending && uram_wr_accept) begin
                wr_pending <= 1'b0;
                uram_wr_en <= 1'b0;
            end
        end
    end

endmodule
