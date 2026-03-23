// =============================================================================
// uram_accum_buf.v — URAM Output Accumulation Buffer
// =============================================================================
//
// 1024×1024 × FP16 buffer for matmul output accumulation.
// Column-sharded write ports: each engine writes to non-overlapping column
// ranges, so no arbitration is needed on writes.
// Single read port for flush/DMA readback.
//
// Write serialization: A round-robin arbiter selects one writer per cycle
// from {clear, nm_adapter, engines}. This produces a simple dual-port
// RAM template (1 write always + 1 read always) that Vivado can infer
// as URAM. Engines receive backpressure via eng_wr_accept.
//
// In simulation: same serialized write path (matches FPGA behavior).
// In synthesis:  (* ram_style = "ultra" *) for Vivado URAM inference.
// =============================================================================

`include "defines.vh"

module uram_accum_buf #(
    parameter ROWS    = 1024,
    parameter COLS    = 1024,
    parameter DATA_W  = 16,
    parameter BUS_W   = 256,
    parameter N_ENG   = 6,
    parameter ROW_W   = $clog2(ROWS),           // 10
    parameter COL_W   = $clog2(COLS / (BUS_W / DATA_W)), // 6 (64 words per row)
    parameter RD_LATENCY = 1   // Read latency: 1=current, 2-4=realistic URAM
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Clear — zero the buffer for a new matmul
    input  wire                 clear,

    // -----------------------------------------------------------------
    // Per-engine write ports (column-sharded, non-overlapping)
    // -----------------------------------------------------------------
    input  wire [N_ENG-1:0]         eng_wr_en,
    input  wire [ROW_W*N_ENG-1:0]   eng_wr_row,
    input  wire [COL_W*N_ENG-1:0]   eng_wr_col_word,
    input  wire [BUS_W*N_ENG-1:0]   eng_wr_data,
    input  wire [N_ENG-1:0]         eng_wr_accum,      // 1=add to existing (k-chunk accumulation)

    // Per-engine write accept (one-hot grant from arbiter)
    output reg  [N_ENG-1:0]         eng_wr_accept,

    // -----------------------------------------------------------------
    // Non-matmul write port (from uram_nm_adapter)
    // FSM guarantees mutual exclusion with engine writes.
    // -----------------------------------------------------------------
    input  wire                 nm_wr_en,
    input  wire [ROW_W-1:0]    nm_wr_row,
    input  wire [COL_W-1:0]    nm_wr_col_word,
    input  wire [BUS_W-1:0]    nm_wr_data,

    // -----------------------------------------------------------------
    // Flush read port (single reader — uram_flush unit)
    // -----------------------------------------------------------------
    input  wire                 rd_en,
    input  wire [ROW_W-1:0]    rd_row,
    input  wire [COL_W-1:0]    rd_col_word,
    output reg  [BUS_W-1:0]    rd_data,
    output reg                  rd_valid
);

    localparam BUS_EL    = BUS_W / DATA_W;       // 16
    localparam WORDS     = COLS / BUS_EL;        // 64
    localparam ADDR_W    = ROW_W + COL_W;

    // =====================================================================
    // Storage — 1024 rows × 64 words × 256-bit
    // =====================================================================
    // Flatten to [ROWS * WORDS] for Vivado URAM inference.
    // Simple dual-port template: one write always + one read always.
    (* ram_style = "ultra" *)
    reg [BUS_W-1:0] mem [0:ROWS * WORDS - 1];

    // =====================================================================
    // Clear logic — done over multiple cycles (background)
    // =====================================================================
    (* mark_debug = "true" *) reg         clearing;
    reg [ADDR_W-1:0] clear_idx;
    localparam CLEAR_MAX = ROWS * WORDS - 1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clearing  <= 1'b0;
            clear_idx <= 0;
        end else if (clear) begin
            clearing  <= 1'b1;
            clear_idx <= 0;
        end else if (clearing) begin
            if (clear_idx == CLEAR_MAX[ADDR_W-1:0])
                clearing <= 1'b0;
            else
                clear_idx <= clear_idx + 1;
        end
    end

    // =====================================================================
    // Write Arbiter — round-robin among engines, priority to clear/nm_wr
    // =====================================================================
    // Selects one writer per cycle. Produces a single (addr, data, en)
    // tuple for the memory write port.
    //
    // Priority: clearing > nm_wr > engines (round-robin)
    //
    // The round-robin pointer advances past the accepted engine each
    // cycle an engine write is granted.

    localparam ENG_W = $clog2(N_ENG > 1 ? N_ENG : 2);
    reg [ENG_W-1:0] arb_ptr;

    // Write mux outputs (combinational)
    reg                  wr_en_mux;
    reg [ADDR_W-1:0]     wr_addr_mux;
    reg [BUS_W-1:0]      wr_data_mux;
    reg                  wr_accum_mux;  // 1=read-modify-write accumulation

    // Arbiter winner tracking
    reg                  arb_eng_found;
    reg [ENG_W-1:0]      arb_winner;

    // Pre-computed priority order (rotated by arb_ptr)
    reg [ENG_W-1:0] pri_idx [0:N_ENG-1];
    integer p, pri_sum_i;

    always @(*) begin
        for (p = 0; p < N_ENG; p = p + 1) begin
            pri_sum_i = arb_ptr + p;
            if (pri_sum_i >= N_ENG)
                pri_idx[p] = pri_sum_i - N_ENG;
            else
                pri_idx[p] = pri_sum_i;
        end
    end

    integer e;
    always @(*) begin
        wr_en_mux    = 1'b0;
        wr_addr_mux  = {ADDR_W{1'b0}};
        wr_data_mux  = {BUS_W{1'b0}};
        wr_accum_mux = 1'b0;
        eng_wr_accept = {N_ENG{1'b0}};
        arb_eng_found = 1'b0;
        arb_winner    = {ENG_W{1'b0}};

        if (clearing) begin
            // Highest priority: clear
            wr_en_mux   = 1'b1;
            wr_addr_mux = clear_idx;
            wr_data_mux = {BUS_W{1'b0}};
        end else if (nm_wr_en) begin
            // Second priority: non-matmul adapter write
            wr_en_mux   = 1'b1;
            wr_addr_mux = nm_wr_row * WORDS + nm_wr_col_word;
            wr_data_mux = nm_wr_data;
        end else begin
            // Round-robin among engines using pre-computed priority order
            for (e = 0; e < N_ENG; e = e + 1) begin
                if (!arb_eng_found && eng_wr_en[pri_idx[e]]) begin
                    arb_eng_found              = 1'b1;
                    arb_winner                 = pri_idx[e];
                    wr_en_mux                  = 1'b1;
                    wr_addr_mux                = eng_wr_row[pri_idx[e] * ROW_W +: ROW_W] * WORDS +
                                                 eng_wr_col_word[pri_idx[e] * COL_W +: COL_W];
                    wr_data_mux                = eng_wr_data[pri_idx[e] * BUS_W +: BUS_W];
                    wr_accum_mux               = eng_wr_accum[pri_idx[e]];
                    eng_wr_accept[pri_idx[e]]  = 1'b1;
                end
            end
        end
    end

    // Advance round-robin pointer when an engine write is accepted
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_ptr <= {ENG_W{1'b0}};
        end else if (arb_eng_found) begin
            if (arb_winner == N_ENG - 1)
                arb_ptr <= {ENG_W{1'b0}};
            else
                arb_ptr <= arb_winner + 1;
        end
    end

    // =====================================================================
    // Port A: Single Write with optional FP16 accumulation
    // =====================================================================
    // When wr_accum_mux=1, perform element-wise FP16 addition
    // (read-modify-write). This implements k-chunk accumulation for matmuls
    // where K > PREFETCH_DIM.
    //
    // The read of mem[addr] in a non-blocking assignment uses the OLD value
    // (read-before-write), which is correct for accumulation.
    // =====================================================================
    integer acc_i;
    reg [BUS_W-1:0] acc_result;

    always @(*) begin
        acc_result = {BUS_W{1'b0}};
        for (acc_i = 0; acc_i < BUS_EL; acc_i = acc_i + 1) begin
            acc_result[acc_i*DATA_W +: DATA_W] = fp16_add_comb(
                mem[wr_addr_mux][acc_i*DATA_W +: DATA_W],
                wr_data_mux[acc_i*DATA_W +: DATA_W]
            );
        end
    end

    // Combinational FP16 adder for k-chunk accumulation
    function [15:0] fp16_add_comb;
        input [15:0] a, b;
        reg        a_s, b_s, lg_s, sm_s, res_s, eff_sub;
        reg [4:0]  a_e, b_e, lg_e, sm_e;
        reg [9:0]  a_m, b_m, lg_mr, sm_mr;
        reg        a_z, b_z;
        reg [4:0]  ediff;
        reg [3:0]  shift;
        reg [13:0] lg_ext, sm_ext, aligned, restored;
        reg        sticky;
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
                // Inf/NaN passthrough
                if (a_e == 5'd31 && a_m != 0)
                    fp16_add_comb = a;
                else if (b_e == 5'd31 && b_m != 0)
                    fp16_add_comb = b;
                else
                    fp16_add_comb = (a_e == 5'd31) ? a : b;
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
                sticky = (restored != sm_ext);

                if (eff_sub)
                    sum_m = {1'b0, lg_ext} - {1'b0, aligned} - {14'd0, sticky};
                else
                    sum_m = {1'b0, lg_ext} + {1'b0, aligned};

                if (sum_m == 15'd0) begin
                    fp16_add_comb = 16'd0;
                end else begin
                    lzc = 4'd15;
                    for (k = 14; k >= 0; k = k - 1) begin
                        if (sum_m[k] && lzc == 4'd15)
                            lzc = 14 - k;
                    end
                    norm_sticky = sticky;
                    if (lzc == 4'd0) begin
                        norm_sticky = sticky | sum_m[0];
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
                    if (rexp >= 6'd31)
                        fp16_add_comb = {res_s, 5'b11111, 10'd0};
                    else if (rexp[5] || rexp == 6'd0)
                        fp16_add_comb = {res_s, 15'd0};
                    else
                        fp16_add_comb = {res_s, rexp[4:0], rmant};
                end
            end
        end
    endfunction

    always @(posedge clk) begin
        if (wr_en_mux) begin
            if (wr_accum_mux)
                mem[wr_addr_mux] <= acc_result;
            else
                mem[wr_addr_mux] <= wr_data_mux;
        end
    end

    // =====================================================================
    // Port B: Flush Read — configurable latency pipeline (RD_LATENCY cycles)
    // =====================================================================
    // Stage 0 is the registered memory read. Stages 1..RD_LATENCY-1 are
    // additional delay registers. Output is taken from the last stage.
    // When RD_LATENCY=1, the for-loop body never executes (0 iterations).
    reg [BUS_W-1:0] rd_pipe_data  [0:RD_LATENCY-1];
    reg             rd_pipe_valid [0:RD_LATENCY-1];
    integer s;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s = 0; s < RD_LATENCY; s = s + 1) begin
                rd_pipe_data[s]  <= {BUS_W{1'b0}};
                rd_pipe_valid[s] <= 1'b0;
            end
        end else begin
            // Stage 0: registered memory read
            rd_pipe_valid[0] <= rd_en;
            if (rd_en) begin
                rd_pipe_data[0] <= mem[rd_row * WORDS + rd_col_word];
            end
            // Stages 1..RD_LATENCY-1: shift register (no iterations when RD_LATENCY=1)
            for (s = 1; s < RD_LATENCY; s = s + 1) begin
                rd_pipe_data[s]  <= rd_pipe_data[s-1];
                rd_pipe_valid[s] <= rd_pipe_valid[s-1];
            end
        end
    end

    // Connect output from last pipeline stage
    always @(*) begin
        rd_data  = rd_pipe_data[RD_LATENCY-1];
        rd_valid = rd_pipe_valid[RD_LATENCY-1];
    end

    // =====================================================================
    // Simulation init — zero memory
    // =====================================================================
    integer init_i;
    initial begin
        for (init_i = 0; init_i < ROWS * WORDS; init_i = init_i + 1)
            mem[init_i] = {BUS_W{1'b0}};
    end

endmodule
