`include "defines.vh"
`include "fp_funcs.vh"

// =============================================================================
// layernorm.v — FP16/FP32 Layer Normalization
// =============================================================================
// Pass 1 (mean):      FP32 running sum, divide by dim
// Pass 2 (variance):  FP32 (x-mean)² accumulation, divide by dim
// Rsqrt:              Quake fast inverse sqrt + 1 Newton-Raphson iteration
// Pass 3 (normalize): 2-stage pipeline: normed=(x-mean)*inv_std, out=normed*gamma+beta
// =============================================================================

module layernorm #(
    parameter DATA_W     = 16,
    parameter OUT_W      = 16,
    parameter PARAM_W    = 16,    // FP16 gamma/beta
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

    // FP32 constants
    localparam [31:0] FP32_EPS        = 32'h3727C5AC;  // 1e-5
    localparam [31:0] FP32_HALF       = 32'h3F000000;  // 0.5
    localparam [31:0] FP32_THREE_HALF = 32'h3FC00000;  // 1.5
    localparam [31:0] FP32_ZERO       = 32'h00000000;

    (* mark_debug = "true" *) reg [2:0] state;
    localparam ST_IDLE       = 3'd0;
    localparam ST_COMP_MEAN  = 3'd1;
    localparam ST_COMP_VAR   = 3'd2;
    localparam ST_COMP_RSQRT = 3'd3;
    localparam ST_NORMALIZE  = 3'd4;
    localparam ST_DONE       = 3'd5;

    reg [DIM_W-1:0] dim_r;
    reg [DIM_W-1:0] idx;
    reg [31:0] fp32_sum;        // FP32 running sum for mean
    reg [31:0] mean;            // FP32 mean
    reg [31:0] neg_mean;        // FP32 -mean (sign-flipped)
    reg [31:0] var_sum;         // FP32 variance accumulator
    reg [31:0] inv_std;         // FP32 1/sqrt(var + eps)

    reg rd_inflight;

    // BRAM input buffer (infers block RAM)
    (* ram_style = "block" *) reg [DATA_W-1:0] input_buffer [0:MAX_DIM-1];
    reg [DATA_W-1:0] bram_rd_data;
    reg [DIM_W-1:0] bram_rd_addr;
    reg buf_rd_valid;

    // Mean pass pipeline (1-cycle delay for BRAM write alignment)
    reg valid_r;
    reg [DATA_W-1:0] data_r;
    reg [DIM_W-1:0] idx_r;

    // Rsqrt sub-state
    reg [2:0] rsqrt_step;
    reg [31:0] rsqrt_y;
    reg [31:0] rsqrt_half_v;
    reg [31:0] rsqrt_tmp;

    // Normalize 2-stage pipeline
    reg pipe1_valid;
    reg [31:0] pipe1_normed;
    reg [31:0] pipe1_gamma_fp32;
    reg [31:0] pipe1_beta_fp32;
    reg [DIM_W-1:0] pipe1_wr_addr;

    // Interleaved gamma/beta read: gamma at addr 2*i, beta at addr 2*i+1
    reg param_phase;            // 0=reading gamma, 1=reading beta
    reg [31:0] stored_gamma_fp32;
    reg [31:0] stored_normed;

    // BRAM input buffer — separate always block with NO async reset
    // (async reset prevents Vivado BRAM inference: Synth 8-4767)
    always @(posedge clk) begin
        // Write port (during mean pass only)
        if (valid_r && state == ST_COMP_MEAN)
            input_buffer[idx_r] <= data_r;
        // Read port (simple dual-port, registered output)
        bram_rd_data <= input_buffer[bram_rd_addr];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            {busy, done, in_rd_en, param_rd_en, out_wr_en} <= 5'b0;
            idx         <= 0;
            fp32_sum    <= FP32_ZERO;
            var_sum     <= FP32_ZERO;
            rd_inflight <= 1'b0;
            buf_rd_valid <= 1'b0;
            valid_r     <= 1'b0;
            pipe1_valid <= 1'b0;
            bram_rd_addr <= 0;
            rsqrt_step  <= 0;
            param_phase <= 1'b0;
        end else begin
            {done, in_rd_en, param_rd_en, out_wr_en} <= 4'b0;
            pipe1_valid <= 1'b0;

            // Input data pipeline (1-cycle delay)
            valid_r <= in_rd_valid;
            data_r  <= in_rd_data;
            idx_r   <= idx - 1;

            // Normalize Stage 2: out = normed * gamma + beta → FP16
            if (pipe1_valid) begin
                out_wr_en   <= 1'b1;
                out_wr_addr <= pipe1_wr_addr;
                out_wr_data <= fp32_to_fp16_func(
                    fp32_add_comb(
                        fp32_mult_comb(pipe1_normed, pipe1_gamma_fp32),
                        pipe1_beta_fp32
                    )
                );
                // synthesis translate_off
                if (pipe1_wr_addr < 4)
                    $display("[LN OUT] addr=%0d out=%04h normed=%08h gamma=%08h beta=%08h",
                             pipe1_wr_addr,
                             fp32_to_fp16_func(fp32_add_comb(fp32_mult_comb(pipe1_normed, pipe1_gamma_fp32), pipe1_beta_fp32)),
                             pipe1_normed, pipe1_gamma_fp32, pipe1_beta_fp32);
                // synthesis translate_on
            end

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state       <= ST_COMP_MEAN;
                        busy        <= 1'b1;
                        dim_r       <= dim;
                        rd_inflight <= 1'b0;
                        buf_rd_valid <= 1'b0;
                        idx         <= 0;
                        fp32_sum    <= FP32_ZERO;
                        var_sum     <= FP32_ZERO;
                    end
                end

                // Pass 1: Mean — read FP16 inputs, accumulate FP32 sum, store in BRAM
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
                        fp32_sum <= fp32_add_comb(fp32_sum,
                                                  fp16_to_fp32_func(data_r));
                        // synthesis translate_off
                        if (idx_r < 4)
                            $display("[LN MEAN] idx=%0d data=%04h fp32=%08h sum=%08h",
                                     idx_r, data_r, fp16_to_fp32_func(data_r),
                                     fp32_add_comb(fp32_sum, fp16_to_fp32_func(data_r)));
                        // synthesis translate_on
                    end

                    if (idx == dim_r && !valid_r && !in_rd_en && !rd_inflight) begin : mean_end
                        reg [31:0] computed_mean;
                        computed_mean = fp32_mult_comb(fp32_sum,
                                                      fp32_recip_dim(dim_r));
                        mean     <= computed_mean;
                        neg_mean <= {~computed_mean[31], computed_mean[30:0]};
                        state    <= ST_COMP_VAR;
                        idx      <= 0;
                        // synthesis translate_off
                        $display("[LN MEAN DONE] dim=%0d sum=%08h recip=%08h mean=%08h",
                                 dim_r, fp32_sum, fp32_recip_dim(dim_r), computed_mean);
                        // synthesis translate_on
                    end
                end

                // Pass 2: Variance — read BRAM, compute (x - mean)², accumulate
                ST_COMP_VAR: begin
                    if (idx < dim_r)
                        bram_rd_addr <= idx;
                    if (idx <= dim_r)
                        idx <= idx + 1;

                    buf_rd_valid <= (idx > 0 && idx <= dim_r);

                    if (buf_rd_valid) begin : var_acc
                        reg [31:0] x_fp32, centered, sq;
                        x_fp32   = fp16_to_fp32_func(bram_rd_data);
                        centered = fp32_add_comb(x_fp32, neg_mean);
                        sq       = fp32_mult_comb(centered, centered);
                        var_sum  <= fp32_add_comb(var_sum, sq);
                    end

                    if (idx > dim_r && !buf_rd_valid) begin : var_end
                        reg [31:0] variance;
                        variance   = fp32_mult_comb(var_sum, fp32_recip_dim(dim_r));
                        rsqrt_tmp  <= fp32_add_comb(variance, FP32_EPS);
                        rsqrt_step <= 3'd0;
                        state      <= ST_COMP_RSQRT;
                    end
                end

                // Rsqrt: Quake fast inverse sqrt + Newton-Raphson
                // y0 = 0x5F3759DF - (var_eps >> 1)
                // y1 = y0 * (1.5 - 0.5 * var_eps * y0 * y0)
                ST_COMP_RSQRT: begin
                    case (rsqrt_step)
                        3'd0: begin
                            // Initial estimate (integer trick on FP32 bits)
                            rsqrt_y      <= 32'h5F3759DF - {1'b0, rsqrt_tmp[31:1]};
                            rsqrt_half_v <= fp32_mult_comb(FP32_HALF, rsqrt_tmp);
                            rsqrt_step   <= 3'd1;
                        end
                        3'd1: begin
                            // y_sq = y * y
                            rsqrt_tmp  <= fp32_mult_comb(rsqrt_y, rsqrt_y);
                            rsqrt_step <= 3'd2;
                        end
                        3'd2: begin
                            // half_v_y_sq = half_v * y_sq
                            rsqrt_tmp  <= fp32_mult_comb(rsqrt_half_v, rsqrt_tmp);
                            rsqrt_step <= 3'd3;
                        end
                        3'd3: begin
                            // factor = 1.5 - half_v_y_sq (negate via sign flip)
                            rsqrt_tmp  <= fp32_add_comb(FP32_THREE_HALF,
                                                        {~rsqrt_tmp[31], rsqrt_tmp[30:0]});
                            rsqrt_step <= 3'd4;
                        end
                        3'd4: begin
                            // inv_std = y * factor
                            inv_std     <= fp32_mult_comb(rsqrt_y, rsqrt_tmp);
                            state       <= ST_NORMALIZE;
                            idx         <= 0;
                            rd_inflight <= 1'b0;
                            param_phase <= 1'b0;
                        end
                        default: rsqrt_step <= 3'd0;
                    endcase
                end

                // Pass 3: Normalize — 2-stage pipeline with interleaved gamma/beta reads
                // Param memory layout: gamma[0], beta[0], gamma[1], beta[1], ...
                // Phase 0: read gamma at addr 2*idx, also read BRAM input
                // Phase 1: read beta at addr 2*idx+1, process with stored gamma
                // Stage 2: out = normed * gamma + beta → FP16 (outside case)
                ST_NORMALIZE: begin
                    if (idx < dim_r && !rd_inflight && !pipe1_valid) begin
                        param_rd_en   <= 1'b1;
                        param_rd_addr <= {idx[DIM_W-2:0], param_phase};  // 2*idx or 2*idx+1
                        if (!param_phase)
                            bram_rd_addr <= idx;
                        rd_inflight   <= 1'b1;
                    end

                    if (param_rd_valid)
                        rd_inflight <= 1'b0;

                    // Phase 0: gamma arrives — store it and compute normed
                    if (param_rd_valid && !param_phase) begin : norm_gamma
                        reg [31:0] x_fp32, centered;
                        x_fp32   = fp16_to_fp32_func(bram_rd_data);
                        centered = fp32_add_comb(x_fp32, neg_mean);

                        stored_gamma_fp32 <= fp16_to_fp32_func(gamma_data);
                        stored_normed     <= fp32_mult_comb(centered, inv_std);
                        param_phase       <= 1'b1;
                    end

                    // Phase 1: beta arrives — push to pipe1
                    if (param_rd_valid && param_phase) begin
                        pipe1_valid      <= 1'b1;
                        pipe1_normed     <= stored_normed;
                        pipe1_gamma_fp32 <= stored_gamma_fp32;
                        pipe1_beta_fp32  <= fp16_to_fp32_func(beta_data);
                        pipe1_wr_addr    <= idx;
                        param_phase      <= 1'b0;
                        idx              <= idx + 1;
                    end

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

endmodule
