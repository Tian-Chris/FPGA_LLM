`include "defines.vh"

module layernorm #(
    parameter DATA_W     = 16,
    parameter OUT_W      = 16,
    parameter PARAM_W    = 8,
    parameter DIM_W      = 16,
    parameter MAX_DIM    = 256
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 start,
    input  wire [DIM_W-1:0]     dim,
    output reg                  busy,
    output reg                  done,

    // Input memory read (requires >= 1 cycle read latency)
    output reg                  in_rd_en,
    output reg  [DIM_W-1:0]     in_rd_addr,
    input  wire [DATA_W-1:0]    in_rd_data,
    input  wire                 in_rd_valid,

    // Parameter memory read (requires >= 1 cycle read latency)
    output reg                  param_rd_en,
    output reg  [DIM_W-1:0]     param_rd_addr,
    input  wire [PARAM_W-1:0]   gamma_data,
    input  wire [PARAM_W-1:0]   beta_data,
    input  wire                 param_rd_valid,

    output reg                  out_wr_en,
    output reg  [DIM_W-1:0]     out_wr_addr,
    output reg  [OUT_W-1:0]     out_wr_data
);

    localparam EPS = 32'd1;

    (* mark_debug = "true" *) reg [2:0] state;
    localparam ST_IDLE      = 3'd0;
    localparam ST_COMP_MEAN = 3'd1;
    localparam ST_COMP_VAR  = 3'd2;
    localparam ST_NORMALIZE = 3'd3;
    localparam ST_DONE      = 3'd4;

    reg [DIM_W-1:0] dim_r;
    reg [DIM_W-1:0] idx;
    reg signed [31:0] sum;
    reg signed [31:0] mean;
    reg [31:0] var_sum;
    reg [31:0] variance;
    reg [31:0] inv_std;

    reg signed [DATA_W-1:0] data_r;
    reg valid_r;
    reg [DIM_W-1:0] idx_r;
    reg rd_inflight;

    // BRAM input buffer (infers block RAM — eliminates ~80K F7/F8 muxes)
    (* ram_style = "block" *) reg signed [DATA_W-1:0] input_buffer [0:MAX_DIM-1];
    reg signed [DATA_W-1:0] bram_rd_data;
    reg [DIM_W-1:0] bram_rd_addr;
    reg buf_rd_valid;

    // Normalize pipeline registers (2-stage: break DSP chain for timing closure)
    reg pipe1_valid;
    reg signed [47:0] pipe1_norm_prod;
    reg signed [PARAM_W-1:0] pipe1_gamma;
    reg signed [PARAM_W-1:0] pipe1_beta;
    reg [DIM_W-1:0] pipe1_wr_addr;

    // 1/sqrt(x) LUT (Index: variance magnitude, Output: Q8.8)
    reg [15:0] rsqrt_lut [0:255];

    integer i;
    initial begin
        for (i = 1; i < 256; i = i + 1) begin
            rsqrt_lut[i] = 256 * 16 / i;
        end
        rsqrt_lut[0] = 16'hFFFF;
    end

    function [15:0] compute_rsqrt;
        input [31:0] var_in;
        reg [7:0] lut_addr;
        begin
            if (var_in < 8)
                lut_addr = 8'd1;
            else if (var_in > 32'h00FFFF)
                lut_addr = 8'hFF;
            else
                lut_addr = var_in[15:8];

            compute_rsqrt = rsqrt_lut[lut_addr];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            {busy, done, in_rd_en, param_rd_en, out_wr_en} <= 5'b0;
            {sum, var_sum, idx} <= 0;
            rd_inflight  <= 1'b0;
            buf_rd_valid <= 1'b0;
            pipe1_valid  <= 1'b0;
            bram_rd_addr <= 0;
        end else begin
            {done, in_rd_en, param_rd_en, out_wr_en} <= 4'b0;
            pipe1_valid <= 1'b0;

            valid_r <= in_rd_valid;
            data_r  <= $signed(in_rd_data);
            idx_r   <= idx - 1;

            // BRAM write + registered read (single always block, simple dual-port)
            if (valid_r && state == ST_COMP_MEAN)
                input_buffer[idx_r] <= data_r;
            bram_rd_data <= input_buffer[bram_rd_addr];

            // Pipeline Stage 2: fires when pipe1_valid (set previous cycle)
            if (pipe1_valid) begin : stage2_block
                reg signed [31:0] normalized_s2;
                reg signed [31:0] result_s2;
                normalized_s2 = pipe1_norm_prod >>> 8;
                result_s2     = ((normalized_s2 * pipe1_gamma) >>> 7) + pipe1_beta;
                out_wr_en   <= 1'b1;
                out_wr_addr <= pipe1_wr_addr;
                if (result_s2 > 31'sd32767)       out_wr_data <= 16'sd32767;
                else if (result_s2 < -31'sd32768) out_wr_data <= 16'sh8000;
                else                              out_wr_data <= result_s2[15:0];
            end

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state       <= ST_COMP_MEAN;
                        busy        <= 1'b1;
                        dim_r       <= dim;
                        rd_inflight <= 1'b0;
                        buf_rd_valid <= 1'b0;
                        {idx, sum, var_sum} <= 0;
                    end
                end

                // Pass 1: Mean Calculation (BRAM write handled above)
                ST_COMP_MEAN: begin
                    if (idx < dim_r && !rd_inflight) begin
                        in_rd_en    <= 1'b1;
                        in_rd_addr  <= idx;
                        idx         <= idx + 1;
                        rd_inflight <= 1'b1;
                    end

                    if (in_rd_valid)
                        rd_inflight <= 1'b0;

                    if (valid_r) begin
                        sum <= sum + data_r;
                    end

                    if (idx == dim_r && !valid_r && !in_rd_en && !rd_inflight) begin
                        mean        <= divide_by_dim(sum, dim_r);
                        state       <= ST_COMP_VAR;
                        idx         <= 0;
                        rd_inflight <= 1'b0;
                    end
                end

                // Pass 2: Variance Calculation (BRAM read with 1-cycle latency)
                ST_COMP_VAR: begin
                    if (idx < dim_r) begin
                        bram_rd_addr <= idx;
                    end
                    if (idx <= dim_r) idx <= idx + 1;

                    buf_rd_valid <= (idx > 0 && idx <= dim_r);

                    if (buf_rd_valid) begin
                        var_sum <= var_sum + compute_sq_diff(bram_rd_data, mean);
                    end

                    if (idx > dim_r && !buf_rd_valid) begin
                        variance <= divide_by_dim(var_sum, dim_r);
                        inv_std  <= compute_rsqrt(divide_by_dim(var_sum, dim_r) + EPS);
                        state    <= ST_NORMALIZE;
                        idx      <= 0;
                    end
                end

                // Pass 3: Scale & Shift (2-stage pipeline)
                // bram_rd_addr issued alongside param_rd_en. Both internal BRAM
                // and external param memory have 1-cycle latency, so bram_rd_data
                // and gamma/beta arrive aligned on param_rd_valid.
                ST_NORMALIZE: begin
                    if (idx < dim_r && !rd_inflight) begin
                        param_rd_en   <= 1'b1;
                        param_rd_addr <= idx;
                        bram_rd_addr  <= idx;
                        idx           <= idx + 1;
                        rd_inflight   <= 1'b1;
                    end

                    if (param_rd_valid)
                        rd_inflight <= 1'b0;

                    // Stage 1: centered * inv_std
                    if (param_rd_valid && idx > 0) begin
                        pipe1_norm_prod <= ($signed({{(32-DATA_W){bram_rd_data[DATA_W-1]}}, bram_rd_data}) - mean)
                                           * $signed({1'b0, inv_std[15:0]});
                        pipe1_gamma     <= $signed(gamma_data);
                        pipe1_beta      <= $signed(beta_data);
                        pipe1_wr_addr   <= idx - 1;
                        pipe1_valid     <= 1'b1;
                    end

                    // Stage 2 handled above (outside case, fires on pipe1_valid)

                    if (idx == dim_r && !param_rd_en && !rd_inflight && !pipe1_valid)
                        state <= ST_DONE;
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

    function signed [31:0] divide_by_dim;
        input signed [31:0] val;
        input [DIM_W-1:0] d;
        begin
            case (d)
                16'd4:   divide_by_dim = val >>> 2;
                16'd8:   divide_by_dim = val >>> 3;
                16'd16:  divide_by_dim = val >>> 4;
                16'd32:  divide_by_dim = val >>> 5;
                16'd64:  divide_by_dim = val >>> 6;
                16'd128: divide_by_dim = val >>> 7;
                16'd256:  divide_by_dim = val >>> 8;
                16'd512:  divide_by_dim = val >>> 9;
                16'd1024: divide_by_dim = val >>> 10;
                default:  divide_by_dim = val >>> 8;
            endcase
        end
    endfunction

    function [31:0] compute_sq_diff;
        input signed [DATA_W-1:0] x;
        input signed [31:0] m;
        reg signed [31:0] diff;
        begin
            diff = $signed({{(32-DATA_W){x[DATA_W-1]}}, x}) - m;
            compute_sq_diff = diff * diff;
        end
    endfunction

endmodule