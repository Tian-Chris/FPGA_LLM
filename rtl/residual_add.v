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
    reg signed [DATA_WIDTH-1:0] res_latched, sub_latched;
    reg reads_issued;

    // Both responses available (either latched or arriving this cycle)
    wire res_ready = got_res || res_rd_valid;
    wire sub_ready = got_sub || sub_rd_valid;
    wire both_ready = res_ready && sub_ready && reads_issued;

    // Select latched data or live wire data
    wire signed [DATA_WIDTH-1:0] res_use = got_res ? res_latched : $signed(res_rd_data);
    wire signed [DATA_WIDTH-1:0] sub_use = got_sub ? sub_latched : $signed(sub_rd_data);

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
                        res_latched <= $signed(res_rd_data);
                        got_res     <= 1'b1;
                    end
                    if (sub_rd_valid && !both_ready) begin
                        sub_latched <= $signed(sub_rd_data);
                        got_sub     <= 1'b1;
                    end

                    // Both responses received: compute saturating add and write
                    if (both_ready) begin
                        out_wr_en    <= 1'b1;
                        out_wr_addr  <= idx;
                        out_wr_data  <= saturating_add(res_use, sub_use);
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

    // Saturating addition
    function [DATA_WIDTH-1:0] saturating_add;
        input signed [DATA_WIDTH-1:0] a;
        input signed [DATA_WIDTH-1:0] b;
        reg signed [DATA_WIDTH:0] sum;
        begin
            sum = a + b;

            // Check for overflow
            if (sum > $signed({1'b0, {(DATA_WIDTH-1){1'b1}}}))  // Max positive
                saturating_add = {1'b0, {(DATA_WIDTH-1){1'b1}}};
            else if (sum < $signed({1'b1, {(DATA_WIDTH-1){1'b0}}}))  // Min negative
                saturating_add = {1'b1, {(DATA_WIDTH-1){1'b0}}};
            else
                saturating_add = sum[DATA_WIDTH-1:0];
        end
    endfunction

endmodule
