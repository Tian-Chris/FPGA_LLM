`include "defines.vh"

module residual_add #(
    parameter DATA_WIDTH = 16,
    parameter DIM_WIDTH  = 16,
    parameter MAX_DIM    = 256
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Control
    input  wire                     start,
    input  wire [DIM_WIDTH-1:0]     dim,
    output reg                      done,
    output reg                      busy,

    // Residual input (skip connection) — routed through URAM adapter
    output reg                      res_rd_en,
    output reg  [DIM_WIDTH-1:0]     res_rd_addr,
    input  wire [DATA_WIDTH-1:0]    res_rd_data,
    input  wire                     res_rd_valid,

    // Sublayer output input — routed through act_dma (HBM)
    output reg                      sub_rd_en,
    output reg  [DIM_WIDTH-1:0]     sub_rd_addr,
    input  wire [DATA_WIDTH-1:0]    sub_rd_data,
    input  wire                     sub_rd_valid,

    // Output (residual + sublayer) — routed through URAM adapter write
    output reg                      out_wr_en,
    output reg  [DIM_WIDTH-1:0]     out_wr_addr,
    output reg  [DATA_WIDTH-1:0]    out_wr_data
);

    // State machine
    reg [1:0] state;
    localparam ST_IDLE    = 2'd0;
    localparam ST_PROCESS = 2'd1;
    localparam ST_DONE    = 2'd2;

    reg [DIM_WIDTH-1:0] dim_r, idx;

    // Async response latching — adapter and DMA have different latencies
    reg got_res, got_sub;
    reg [DATA_WIDTH-1:0] res_latched, sub_latched;
    reg reads_issued;

    // Both responses available (either latched or arriving this cycle)
    wire res_ready = got_res || res_rd_valid;
    wire sub_ready = got_sub || sub_rd_valid;
    wire both_ready = res_ready && sub_ready && reads_issued;

    // Select latched data or live wire data (FP16 bit patterns, no sign cast)
    wire [DATA_WIDTH-1:0] res_use = got_res ? res_latched : res_rd_data;
    wire [DATA_WIDTH-1:0] sub_use = got_sub ? sub_latched : sub_rd_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            res_rd_en    <= 1'b0;
            sub_rd_en    <= 1'b0;
            out_wr_en    <= 1'b0;
            idx          <= 0;
            got_res      <= 1'b0;
            got_sub      <= 1'b0;
            reads_issued <= 1'b0;
        end else begin
            done      <= 1'b0;
            res_rd_en <= 1'b0;
            sub_rd_en <= 1'b0;
            out_wr_en <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state        <= ST_PROCESS;
                        busy         <= 1'b1;
                        dim_r        <= dim;
                        idx          <= 0;
                        got_res      <= 1'b0;
                        got_sub      <= 1'b0;
                        reads_issued <= 1'b0;
                    end
                end

                ST_PROCESS: begin
                    // Issue paired reads (adapter + DMA) for current element
                    // Don't issue on write cycles (avoids adapter read-write collision)
                    if (idx < dim_r && !reads_issued) begin
                        res_rd_en   <= 1'b1;
                        sub_rd_en   <= 1'b1;
                        res_rd_addr <= idx;
                        sub_rd_addr <= idx;
                        reads_issued <= 1'b1;
                    end

                    // Latch responses as they arrive (only if not consuming this cycle)
                    if (res_rd_valid && !both_ready) begin
                        res_latched <= res_rd_data;
                        got_res     <= 1'b1;
                    end
                    if (sub_rd_valid && !both_ready) begin
                        sub_latched <= sub_rd_data;
                        got_sub     <= 1'b1;
                    end

                    // Both responses received: FP16 add and write
                    if (both_ready) begin
                        out_wr_en    <= 1'b1;
                        out_wr_addr  <= idx;
                        out_wr_data  <= fp16_add_comb(res_use, sub_use);
                        idx          <= idx + 1;
                        got_res      <= 1'b0;
                        got_sub      <= 1'b0;
                        reads_issued <= 1'b0;
                    end

                    // All elements processed
                    if (idx == dim_r && !reads_issued && !got_res && !got_sub) begin
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // Combinational FP16 adder (replaces saturating INT16 add)
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
                sticky = (restored != sm_ext);
                if (eff_sub)
                    sum_m = {1'b0, lg_ext} - {1'b0, aligned} - {14'd0, sticky};
                else
                    sum_m = {1'b0, lg_ext} + {1'b0, aligned};

                if (sum_m == 15'd0) begin
                    fp16_add_comb = 16'd0;
                end else begin
                    lzc = 4'd15;
                    for (k = 14; k >= 0; k = k - 1)
                        if (sum_m[k] && lzc == 4'd15) lzc = 14 - k;
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

endmodule
