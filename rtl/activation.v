`include "defines.vh"

// =============================================================================
// activation.v — GELU activation via 512-entry LUT
// =============================================================================
// Maps FP16 input to FP16 output using GELU lookup table.
// Index: clamp((x + 8.0) * 32, 0, 511)
// Below -8: output ≈ 0. Above 8: output ≈ x. Between: LUT lookup.
// =============================================================================

module activation_unit #(
    parameter DATA_WIDTH = 16,
    parameter MAX_DIM    = 256
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Control
    input  wire                     start,
    input  wire [15:0]              dim,
    output reg                      done,
    output reg                      busy,

    // Memory interface
    output reg                      mem_rd_en,
    output reg  [15:0]              mem_rd_addr,
    input  wire [DATA_WIDTH-1:0]    mem_rd_data,
    input  wire                     mem_rd_valid,

    output reg                      mem_wr_en,
    output reg  [15:0]              mem_wr_addr,
    output reg  [DATA_WIDTH-1:0]    mem_wr_data
);

    reg [1:0] state;
    localparam ST_IDLE    = 2'd0;
    localparam ST_PROCESS = 2'd1;
    localparam ST_DONE    = 2'd2;
    reg [15:0] dim_r, idx;

    // GELU LUT: 512 entries of FP16 bit patterns
    reg [15:0] gelu_lut [0:511];
    `ifdef FPGA_TARGET
    initial $readmemh("gelu_lut.hex", gelu_lut);
    `else
    initial $readmemh("rtl/gelu_lut.hex", gelu_lut);
    `endif

    reg rd_inflight;

    // GELU LUT index from FP16 input
    // Index = clamp((x + 8) * 32, 0, 511)
    // |x| * 32 = {1, mant} * 2^(exp-20), so right-shift by (20 - exp) for exp < 20
    function [8:0] gelu_index;
        input [15:0] x;
        reg        x_sign;
        reg [4:0]  x_exp;
        reg [9:0]  x_mant;
        reg [16:0] fixed_val;
        reg signed [16:0] shifted;
        begin
            x_sign = x[15];
            x_exp  = x[14:10];
            x_mant = x[9:0];

            if (x_exp == 5'd0) begin
                gelu_index = 9'd256;  // Zero/subnormal → GELU(0)
            end else if (x_exp == 5'd31) begin
                gelu_index = x_sign ? 9'd0 : 9'd511;
            end else if (x_exp >= 5'd20) begin
                // |x| >= 32 → way beyond ±8 range
                gelu_index = x_sign ? 9'd0 : 9'd511;
            end else if (x_exp >= 5'd10) begin
                // |x|*32 = {1, mant} >> (20 - exp)
                fixed_val = {1'b1, x_mant} >> (5'd20 - x_exp);
                if (x_sign)
                    shifted = 17'sd256 - fixed_val;
                else
                    shifted = 17'sd256 + fixed_val;

                if (shifted < 0)
                    gelu_index = 9'd0;
                else if (shifted > 17'sd511)
                    gelu_index = 9'd511;
                else
                    gelu_index = shifted[8:0];
            end else begin
                gelu_index = 9'd256;  // |x| < 1/32 → GELU(0)
            end
        end
    endfunction

    // Combinational GELU result from current read data
    wire [8:0]           cur_lut_idx  = gelu_index(mem_rd_data);
    wire [DATA_WIDTH-1:0] cur_gelu_out = gelu_lut[cur_lut_idx];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            mem_rd_en <= 1'b0;
            mem_wr_en <= 1'b0;
            idx       <= 0;
            rd_inflight <= 1'b0;
        end else begin
            done      <= 1'b0;
            mem_rd_en <= 1'b0;
            mem_wr_en <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state       <= ST_PROCESS;
                        busy        <= 1'b1;
                        dim_r       <= dim;
                        idx         <= 0;
                        rd_inflight <= 1'b0;
                    end
                end

                ST_PROCESS: begin
                    // When read data arrives, compute GELU and write back
                    if (mem_rd_valid) begin
                        mem_wr_en   <= 1'b1;
                        mem_wr_addr <= mem_rd_addr;
                        mem_wr_data <= cur_gelu_out;
                        rd_inflight <= 1'b0;
                    end

                    // Issue read only when no write pending and no read inflight
                    if (idx < dim_r && !rd_inflight && !mem_rd_valid) begin
                        mem_rd_en   <= 1'b1;
                        mem_rd_addr <= idx;
                        idx         <= idx + 1;
                        rd_inflight <= 1'b1;
                    end

                    if (idx == dim_r && !mem_rd_valid && !rd_inflight && !mem_wr_en) begin
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

endmodule
