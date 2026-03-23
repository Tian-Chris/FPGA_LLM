`include "defines.vh"
`include "fp_funcs.vh"

// =============================================================================
// softmax.v — FP16 softmax with LUT-based exp
// =============================================================================
// Pass 1 (find max):  FP16 scale × score, find max via FP16 comparison
// Pass 2 (compute exp): exp(scaled − max) via 256-entry LUT, FP32 sum
// Reciprocal:          Newton-Raphson FP32 reciprocal (4 cycles)
// Pass 3 (normalize):  exp_val × recip → FP16 output
// =============================================================================

module softmax #(
    parameter DATA_W     = 16,
    parameter OUT_W      = 16,
    parameter MAX_LEN    = 128,
    parameter CAUSAL     = 0
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 start,
    input  wire [15:0]          seq_len,
    input  wire [15:0]          row_idx,
    input  wire [15:0]          scale_factor,  // FP16 (e.g. 1/√64 = 0.125)
    output reg                  busy,
    output reg                  done,

    output reg                  in_rd_en,
    output reg  [15:0]          in_rd_addr,
    input  wire [DATA_W-1:0]    in_rd_data,
    input  wire                 in_rd_valid,

    output reg                  out_wr_en,
    output reg  [15:0]          out_wr_addr,
    output reg  [OUT_W-1:0]     out_wr_data
);

    // FP16 constants
    localparam [15:0] FP16_NEG_INF = 16'hFC00;  // -Inf
    localparam [15:0] FP16_ZERO    = 16'h0000;
    localparam [15:0] FP16_ONE     = 16'h3C00;  // 1.0

    // FP32 constants for Newton-Raphson reciprocal
    localparam [31:0] FP32_TWO = 32'h40000000;  // 2.0

    // ---- State Machine ----
    (* mark_debug = "true" *) reg [2:0] state;
    localparam ST_IDLE       = 3'd0;
    localparam ST_FIND_MAX   = 3'd1;
    localparam ST_COMP_EXP   = 3'd2;
    localparam ST_COMP_RECIP = 3'd3;
    localparam ST_NORMALIZE  = 3'd4;
    localparam ST_DONE       = 3'd5;

    // ---- Internal Registers ----
    reg [15:0] max_val;       // FP16 max of scaled scores
    reg [31:0] exp_sum;       // FP32 sum of exp values
    reg [31:0] recip;         // FP32 1/exp_sum
    reg [15:0] idx;           // Read request counter
    reg [15:0] rx_cnt;        // Valid data receive counter
    reg [15:0] len_r;
    reg [15:0] scale_r;       // Latched scale factor
    reg [15:0] row_r;         // Latched row index
    reg rd_inflight;

    // Exp buffer (FP16 exp values)
    (* ram_style = "block" *) reg [15:0] exp_buffer [0:MAX_LEN-1];

    // Pipeline registers
    reg valid_r;
    reg [15:0] scaled_r;      // FP16 scaled score

    // Reciprocal sub-state
    reg [2:0] recip_step;
    reg [31:0] recip_y;       // Current reciprocal estimate
    reg [31:0] recip_tmp;

    // Normalize pipeline
    reg        norm_valid_r;
    reg [15:0] norm_idx_r;
    reg [15:0] exp_buf_r;

    // Exp LUT: 256 entries, exp_lut[i] = FP16(exp(-i/16))
    reg [15:0] exp_lut [0:255];
    initial $readmemh("rtl/exp_lut.hex", exp_lut);

    // ---- Exp LUT index from FP16 diff ----
    // diff is always ≤ 0. Index = clamp(|diff| * 16, 0, 255)
    function [7:0] exp_lut_index;
        input [15:0] diff;
        reg [4:0]  e;
        reg [9:0]  m;
        begin
            e = diff[14:10];
            m = diff[9:0];

            if (diff == 16'h0000 || diff == 16'h8000 || e == 5'd0)
                // Zero or subnormal: diff ≈ 0 → exp(0) = 1.0
                exp_lut_index = 8'd0;
            else if (e == 5'd31)
                // Inf/NaN → exp(-∞) = 0
                exp_lut_index = 8'd255;
            else if (e >= 5'd19)
                // |diff| >= 16, exp ≈ 0
                exp_lut_index = 8'd255;
            else if (e < 5'd11)
                // |diff| < 1/16, exp ≈ 1.0
                exp_lut_index = 8'd0;
            else begin
                // e ∈ [11, 18]: |diff|*16 ∈ [1, 255]
                // floor(|diff| * 16) = {1, mant} >> (21 - e)
                case (e)
                    5'd11: exp_lut_index = 8'd1;
                    5'd12: exp_lut_index = {6'd0, 1'b1, m[9]};
                    5'd13: exp_lut_index = {5'd0, 1'b1, m[9:8]};
                    5'd14: exp_lut_index = {4'd0, 1'b1, m[9:7]};
                    5'd15: exp_lut_index = {3'd0, 1'b1, m[9:6]};
                    5'd16: exp_lut_index = {2'd0, 1'b1, m[9:5]};
                    5'd17: exp_lut_index = {1'b0, 1'b1, m[9:4]};
                    5'd18: exp_lut_index = {1'b1, m[9:3]};
                    default: exp_lut_index = 8'd255;
                endcase
            end
        end
    endfunction

    // ---- FP16 max (combinational) ----
    function [15:0] fp16_max;
        input [15:0] a, b;
        begin
            // Handle zeros
            if (a[14:0] == 15'd0 && b[14:0] == 15'd0)
                fp16_max = 16'h0000;
            // NaN propagation
            else if (a[14:10] == 5'd31 && a[9:0] != 0)
                fp16_max = a;
            else if (b[14:10] == 5'd31 && b[9:0] != 0)
                fp16_max = b;
            // Both positive: larger magnitude wins
            else if (!a[15] && !b[15])
                fp16_max = (a[14:0] >= b[14:0]) ? a : b;
            // Both negative: smaller magnitude wins
            else if (a[15] && b[15])
                fp16_max = (a[14:0] <= b[14:0]) ? a : b;
            // Mixed: positive wins
            else
                fp16_max = a[15] ? b : a;
        end
    endfunction

    // ---- Main State Machine ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            in_rd_en     <= 1'b0;
            out_wr_en    <= 1'b0;
            max_val      <= FP16_NEG_INF;
            exp_sum      <= 32'h00000000;
            idx          <= 0;
            rx_cnt       <= 0;
            rd_inflight  <= 1'b0;
            norm_valid_r <= 1'b0;
            valid_r      <= 1'b0;
        end else begin
            done      <= 1'b0;
            out_wr_en <= 1'b0;

            // Pipeline: scale input on valid
            valid_r <= in_rd_valid;
            if (in_rd_valid) begin
                scaled_r <= fp16_mult_comb(in_rd_data, scale_r);
                // synthesis translate_off
                if (state == ST_FIND_MAX && idx <= 1)
                    $display("[SM %0t] READ idx=%0d in_rd_data=%04h scale=%04h scaled=%04h row_idx=%0d",
                             $time, idx-1, in_rd_data, scale_r,
                             fp16_mult_comb(in_rd_data, scale_r), row_r);
                // synthesis translate_on
            end

            case (state)
                ST_IDLE: begin
                    if (start && seq_len > 0) begin
                        state       <= ST_FIND_MAX;
                        busy        <= 1'b1;
                        len_r       <= seq_len;
                        idx         <= 0;
                        rx_cnt      <= 0;
                        rd_inflight <= 1'b0;
                        max_val     <= FP16_NEG_INF;
                        exp_sum     <= 32'h00000000;
                        scale_r     <= scale_factor;
                        row_r       <= row_idx;
                    end
                end

                // Pass 1: Find max of scaled scores
                ST_FIND_MAX: begin
                    in_rd_en <= 1'b0;
                    if (idx < len_r && !rd_inflight) begin
                        in_rd_en    <= 1'b1;
                        in_rd_addr  <= idx;
                        idx         <= idx + 1;
                        rd_inflight <= 1'b1;
                    end

                    if (in_rd_valid)
                        rd_inflight <= 1'b0;

                    if (valid_r) begin
                        rx_cnt <= rx_cnt + 1;
                        if (CAUSAL == 0 || rx_cnt <= row_r) begin
                            max_val <= fp16_max(scaled_r, max_val);
                        end
                    end

                    if (rx_cnt == len_r) begin
                        state       <= ST_COMP_EXP;
                        idx         <= 0;
                        rx_cnt      <= 0;
                        rd_inflight <= 1'b0;
                    end
                end

                // Pass 2: Compute exp(scaled - max), accumulate sum
                ST_COMP_EXP: begin
                    in_rd_en <= 1'b0;
                    if (idx < len_r && !rd_inflight) begin
                        in_rd_en    <= 1'b1;
                        in_rd_addr  <= idx;
                        idx         <= idx + 1;
                        rd_inflight <= 1'b1;
                    end

                    if (in_rd_valid)
                        rd_inflight <= 1'b0;

                    if (valid_r) begin : exp_block
                        reg [15:0] diff, exp_val;
                        rx_cnt <= rx_cnt + 1;

                        if (CAUSAL != 0 && rx_cnt > row_r) begin
                            // Causal mask: future tokens → exp = 0
                            exp_buffer[rx_cnt] <= FP16_ZERO;
                        end else begin
                            // diff = scaled - max (always ≤ 0)
                            diff = fp16_add_comb(scaled_r,
                                                 {~max_val[15], max_val[14:0]});
                            exp_val = exp_lut[exp_lut_index(diff)];
                            exp_buffer[rx_cnt] <= exp_val;
                            exp_sum <= fp32_add_comb(exp_sum,
                                                    fp16_to_fp32_func(exp_val));
                            // synthesis translate_off
                            if (rx_cnt == 0 && row_r == 0)
                                $display("[SM %0t] EXP row0[0]: scaled=%04h max=%04h diff=%04h exp=%04h sum_add=%08h",
                                         $time, scaled_r, max_val, diff, exp_val,
                                         fp32_add_comb(exp_sum, fp16_to_fp32_func(exp_val)));
                            // synthesis translate_on
                        end
                    end

                    if (rx_cnt == len_r) begin
                        state      <= ST_COMP_RECIP;
                        recip_step <= 3'd0;
                    end
                end

                // Compute FP32 reciprocal of exp_sum via Newton-Raphson
                // y0 = 0x7EF311C7 - sum_bits (magic reciprocal)
                // y1 = y0 * (2 - sum * y0)
                ST_COMP_RECIP: begin
                    case (recip_step)
                        3'd0: begin
                            // Initial estimate
                            recip_y    <= 32'h7EF311C7 - exp_sum;
                            recip_step <= 3'd1;
                        end
                        3'd1: begin
                            // tmp = sum * y0
                            recip_tmp  <= fp32_mult_comb(exp_sum, recip_y);
                            recip_step <= 3'd2;
                        end
                        3'd2: begin
                            // tmp = 2 - sum*y0 (negate then add 2)
                            recip_tmp  <= fp32_add_comb(FP32_TWO,
                                              {~recip_tmp[31], recip_tmp[30:0]});
                            recip_step <= 3'd3;
                        end
                        3'd3: begin
                            // y1 = y0 * (2 - sum*y0)
                            recip <= fp32_mult_comb(recip_y, recip_tmp);
                            state  <= ST_NORMALIZE;
                            idx    <= 0;
                        end
                        default: recip_step <= 3'd0;
                    endcase
                end

                // Pass 3: Normalize — exp_val * recip → FP16 output
                ST_NORMALIZE: begin
                    // Read from exp_buffer (1-cycle BRAM latency)
                    if (idx < len_r) begin
                        norm_valid_r <= 1'b1;
                        norm_idx_r   <= idx;
                        exp_buf_r    <= exp_buffer[idx];
                        idx          <= idx + 1;
                    end else begin
                        norm_valid_r <= 1'b0;
                    end

                    // Write output (1 cycle delayed)
                    if (norm_valid_r) begin
                        out_wr_en   <= 1'b1;
                        out_wr_addr <= norm_idx_r;
                        // exp_fp32 * recip → FP16
                        out_wr_data <= fp32_to_fp16_func(
                            fp32_mult_comb(fp16_to_fp32_func(exp_buf_r), recip)
                        );

                        // synthesis translate_off
                        if (norm_idx_r == 0)
                            $display("[SM %0t] WRITE row0: exp=%04h recip=%08h prob=%04h",
                                     $time, exp_buf_r, recip,
                                     fp32_to_fp16_func(
                                         fp32_mult_comb(fp16_to_fp32_func(exp_buf_r), recip)));
                        // synthesis translate_on

                        if (norm_idx_r == len_r - 1)
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
