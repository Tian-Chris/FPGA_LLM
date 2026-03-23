// =============================================================================
// fp16_add.v — FP16 + FP16 → FP16 Adder (2-stage pipeline)
// =============================================================================
// Stage 1: Unpack, compare, swap, align, add/subtract
// Stage 2: Normalize, round-to-nearest-even, pack
//
// Subnormals (exp=0) are flushed to zero.
// =============================================================================

`timescale 1ns / 1ps

module fp16_add (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [15:0] a_in,
    input  wire [15:0] b_in,
    output reg         out_valid,
    output reg  [15:0] result
);

    // ---- Unpack ----
    wire        a_sign = a_in[15];
    wire [4:0]  a_exp  = a_in[14:10];
    wire [9:0]  a_mant = a_in[9:0];
    wire        b_sign = b_in[15];
    wire [4:0]  b_exp  = b_in[14:10];
    wire [9:0]  b_mant = b_in[9:0];

    wire a_zero = (a_exp == 5'd0);
    wire b_zero = (b_exp == 5'd0);
    wire a_inf  = (a_exp == 5'd31) && (a_mant == 10'd0);
    wire b_inf  = (b_exp == 5'd31) && (b_mant == 10'd0);
    wire a_nan  = (a_exp == 5'd31) && (a_mant != 10'd0);
    wire b_nan  = (b_exp == 5'd31) && (b_mant != 10'd0);

    // Magnitude comparison
    wire a_mag_ge_b = (a_exp > b_exp) ||
                      ((a_exp == b_exp) && (a_mant >= b_mant));

    wire        lg_sign = a_mag_ge_b ? a_sign : b_sign;
    wire [4:0]  lg_exp  = a_mag_ge_b ? a_exp  : b_exp;
    wire [9:0]  lg_mant = a_mag_ge_b ? a_mant : b_mant;
    wire        lg_zero = a_mag_ge_b ? a_zero : b_zero;
    wire        sm_sign = a_mag_ge_b ? b_sign : a_sign;
    wire [4:0]  sm_exp  = a_mag_ge_b ? b_exp  : a_exp;
    wire [9:0]  sm_mant = a_mag_ge_b ? b_mant : a_mant;
    wire        sm_zero = a_mag_ge_b ? b_zero : a_zero;

    wire eff_sub = lg_sign ^ sm_sign;
    wire [4:0] exp_diff = lg_exp - sm_exp;

    // Working mantissa: {1, mant[9:0], 3'b000} = 14 bits
    wire [13:0] lg_mant_ext = lg_zero ? 14'd0 : {1'b1, lg_mant, 3'b000};
    wire [13:0] sm_mant_ext = sm_zero ? 14'd0 : {1'b1, sm_mant, 3'b000};

    // Align
    wire [3:0] shift = (exp_diff > 5'd14) ? 4'd14 : exp_diff[3:0];
    wire [13:0] aligned_sm = sm_mant_ext >> shift;
    wire [13:0] restored   = aligned_sm << shift;
    wire        sticky_shift = (restored != sm_mant_ext);

    // Add/subtract (15-bit for carry)
    wire [14:0] sum_raw = eff_sub ? ({1'b0, lg_mant_ext} - {1'b0, aligned_sm} - {14'd0, sticky_shift})
                                  : ({1'b0, lg_mant_ext} + {1'b0, aligned_sm});

    // ---- Stage 1 registers ----
    reg        s1_valid;
    reg        s1_sign;
    reg [4:0]  s1_exp;
    reg [14:0] s1_mant;      // 15-bit sum
    reg        s1_sticky;
    reg        s1_is_special;
    reg [15:0] s1_special_result;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0;
            s1_sign <= 0;
            s1_exp <= 0;
            s1_mant <= 0;
            s1_sticky <= 0;
            s1_is_special <= 0;
            s1_special_result <= 0;
        end else begin
            s1_valid <= in_valid;
            s1_sign  <= lg_sign;
            s1_exp   <= lg_exp;
            s1_mant  <= sum_raw;
            s1_sticky <= sticky_shift;

            // Special cases
            if (a_nan || b_nan || (a_inf && b_inf && eff_sub)) begin
                s1_is_special <= 1;
                s1_special_result <= {1'b0, 5'b11111, 1'b1, 9'd0};  // NaN
            end else if (a_inf) begin
                s1_is_special <= 1;
                s1_special_result <= {a_sign, 5'b11111, 10'd0};
            end else if (b_inf) begin
                s1_is_special <= 1;
                s1_special_result <= {b_sign, 5'b11111, 10'd0};
            end else if (a_zero && b_zero) begin
                s1_is_special <= 1;
                s1_special_result <= {a_sign & b_sign, 15'd0};
            end else if (sm_zero) begin
                s1_is_special <= 1;
                s1_special_result <= a_mag_ge_b ? a_in : b_in;
            end else if (lg_zero) begin
                s1_is_special <= 1;
                s1_special_result <= a_mag_ge_b ? b_in : a_in;
            end else begin
                s1_is_special <= 0;
                s1_special_result <= 16'd0;
            end
        end
    end

    // ---- Stage 2: normalize + round + pack ----

    // Count leading zeros in 15-bit mantissa
    function [3:0] clz15;
        input [14:0] val;
        reg found;
        integer i;
        begin
            clz15 = 4'd15;
            found = 0;
            for (i = 14; i >= 0; i = i - 1) begin
                if (!found && val[i]) begin
                    clz15 = 4'd14 - i[3:0];
                    found = 1;
                end
            end
        end
    endfunction

    wire [3:0] lzc = clz15(s1_mant);

    // Normalize
    reg [14:0] norm_mant;
    reg [5:0]  norm_exp;  // 6 bits for overflow/underflow
    reg        norm_sticky;

    always @(*) begin
        norm_sticky = s1_sticky;
        if (s1_mant == 15'd0) begin
            norm_mant = 15'd0;
            norm_exp  = 6'd0;
        end else if (lzc == 4'd0) begin
            // Carry: shift right 1
            norm_sticky = s1_sticky | s1_mant[0];
            norm_mant = {1'b0, s1_mant[14:1]};
            norm_exp  = {1'b0, s1_exp} + 6'd1;
        end else if (lzc == 4'd1) begin
            // Already normalized
            norm_mant = s1_mant;
            norm_exp  = {1'b0, s1_exp};
        end else begin
            // Left shift
            norm_mant = s1_mant << (lzc - 4'd1);
            norm_exp  = {1'b0, s1_exp} - {2'd0, lzc} + 6'd1;
        end
    end

    // Extract mantissa and GRS: bit[13]=implicit 1, bits[12:3]=mantissa, bits[2:0]=GRS
    wire [9:0]  final_mant = norm_mant[12:3];
    wire        guard      = norm_mant[2];
    wire        round_bit  = norm_mant[1];
    wire        sticky_all = norm_mant[0] | norm_sticky;

    wire round_up = guard && (round_bit || sticky_all || final_mant[0]);

    wire [10:0] rounded = {1'b0, final_mant} + {10'd0, round_up};
    wire        round_ovf = rounded[10];
    wire [9:0]  result_mant = round_ovf ? 10'd0 : rounded[9:0];
    wire [5:0]  result_exp  = round_ovf ? norm_exp + 6'd1 : norm_exp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 0;
            result    <= 0;
        end else begin
            out_valid <= s1_valid;
            if (s1_is_special)
                result <= s1_special_result;
            else if (s1_mant == 15'd0)
                result <= {s1_sign, 15'd0};
            else if (result_exp >= 6'd31)
                result <= {s1_sign, 5'b11111, 10'd0};  // Overflow → Inf
            else if (result_exp[5] || result_exp == 6'd0)
                result <= {s1_sign, 15'd0};             // Underflow → zero
            else
                result <= {s1_sign, result_exp[4:0], result_mant};
        end
    end

endmodule
