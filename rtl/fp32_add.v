// =============================================================================
// fp32_add.v — FP32 + FP32 → FP32 Adder (3-stage pipeline)
// =============================================================================
// Stage 1: Unpack, compare magnitudes, swap so larger is first, compute shift
// Stage 2: Align smaller mantissa, add/subtract
// Stage 3: Normalize (CLZ + shift), round-to-nearest-even, pack
//
// Subnormals (exp=0) are flushed to zero.
// =============================================================================

`timescale 1ns / 1ps

module fp32_add (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] a_in,
    input  wire [31:0] b_in,
    output reg         out_valid,
    output reg  [31:0] result
);

    // ---- Unpack ----
    wire        a_sign = a_in[31];
    wire [7:0]  a_exp  = a_in[30:23];
    wire [22:0] a_mant = a_in[22:0];
    wire        b_sign = b_in[31];
    wire [7:0]  b_exp  = b_in[30:23];
    wire [22:0] b_mant = b_in[22:0];

    wire a_zero = (a_exp == 8'd0);
    wire b_zero = (b_exp == 8'd0);
    wire a_inf  = (a_exp == 8'hFF) && (a_mant == 23'd0);
    wire b_inf  = (b_exp == 8'hFF) && (b_mant == 23'd0);
    wire a_nan  = (a_exp == 8'hFF) && (a_mant != 23'd0);
    wire b_nan  = (b_exp == 8'hFF) && (b_mant != 23'd0);

    // Magnitude comparison: a >= b?
    wire a_mag_ge_b = (a_exp > b_exp) ||
                      ((a_exp == b_exp) && (a_mant >= b_mant));

    // Swap so large has bigger magnitude
    wire        lg_sign = a_mag_ge_b ? a_sign : b_sign;
    wire [7:0]  lg_exp  = a_mag_ge_b ? a_exp  : b_exp;
    wire [22:0] lg_mant = a_mag_ge_b ? a_mant : b_mant;
    wire        lg_zero = a_mag_ge_b ? a_zero : b_zero;
    wire        sm_sign = a_mag_ge_b ? b_sign : a_sign;
    wire [7:0]  sm_exp  = a_mag_ge_b ? b_exp  : a_exp;
    wire [22:0] sm_mant = a_mag_ge_b ? b_mant : a_mant;
    wire        sm_zero = a_mag_ge_b ? b_zero : a_zero;

    wire eff_sub = lg_sign ^ sm_sign;  // Different signs → subtract
    wire [7:0] exp_diff = lg_exp - sm_exp;

    // ---- Stage 1 registers ----
    reg        s1_valid;
    reg        s1_result_sign;
    reg [7:0]  s1_lg_exp;
    reg [26:0] s1_lg_mant;   // {1, mant[22:0], 3'b000} = 27 bits
    reg [26:0] s1_sm_mant;
    reg [4:0]  s1_shift;      // Clamped to 27
    reg        s1_eff_sub;
    reg        s1_is_zero, s1_is_inf, s1_is_nan;
    reg [31:0] s1_special_result;
    reg        s1_sm_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0;
            s1_result_sign <= 0;
            s1_lg_exp <= 0;
            s1_lg_mant <= 0;
            s1_sm_mant <= 0;
            s1_shift <= 0;
            s1_eff_sub <= 0;
            s1_is_zero <= 0;
            s1_is_inf <= 0;
            s1_is_nan <= 0;
            s1_special_result <= 0;
            s1_sm_zero <= 0;
        end else begin
            s1_valid <= in_valid;
            s1_result_sign <= lg_sign;
            s1_lg_exp <= lg_exp;
            s1_lg_mant <= lg_zero ? 27'd0 : {1'b1, lg_mant, 3'b000};
            s1_sm_mant <= sm_zero ? 27'd0 : {1'b1, sm_mant, 3'b000};
            s1_shift <= (exp_diff > 8'd27) ? 5'd27 : exp_diff[4:0];
            s1_eff_sub <= eff_sub;
            s1_sm_zero <= sm_zero;

            // Special cases
            s1_is_nan <= a_nan || b_nan || (a_inf && b_inf && eff_sub);
            s1_is_inf <= (a_inf || b_inf) && !a_nan && !b_nan &&
                         !(a_inf && b_inf && eff_sub);
            s1_is_zero <= a_zero && b_zero;

            if (a_nan || b_nan || (a_inf && b_inf && eff_sub))
                s1_special_result <= {1'b0, 8'hFF, 23'h400000};  // NaN
            else if (a_inf)
                s1_special_result <= {a_sign, 8'hFF, 23'd0};
            else if (b_inf)
                s1_special_result <= {b_sign, 8'hFF, 23'd0};
            else if (a_zero && b_zero)
                s1_special_result <= {a_sign & b_sign, 31'd0};   // +0 unless both -0
            else if (b_zero)
                s1_special_result <= a_in;
            else if (a_zero)
                s1_special_result <= b_in;
            else
                s1_special_result <= 32'd0;
        end
    end

    // ---- Stage 2: align + add/subtract ----
    wire [26:0] aligned_sm = s1_sm_mant >> s1_shift;

    // Sticky: detect if any bits were shifted out
    wire [26:0] restored = aligned_sm << s1_shift;
    wire        sticky_shift = (restored != s1_sm_mant);

    // Add or subtract mantissas (28-bit to handle carry)
    wire [27:0] lg_ext = {1'b0, s1_lg_mant};
    wire [27:0] sm_ext = {1'b0, aligned_sm};

    wire [27:0] sum_mant = s1_eff_sub ? (lg_ext - sm_ext - {27'd0, sticky_shift})
                                      : (lg_ext + sm_ext);
    // For subtraction with sticky: result is exact (large - small_true),
    // and the remainder goes to the new sticky bit.
    wire sum_sticky = s1_eff_sub ? sticky_shift : sticky_shift;

    reg        s2_valid;
    reg        s2_sign;
    reg [7:0]  s2_exp;
    reg [27:0] s2_mant;        // 28-bit sum
    reg        s2_sticky;
    reg        s2_is_special;
    reg [31:0] s2_special_result;
    reg        s2_one_zero;    // One operand was zero → result is the other

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 0;
            s2_sign <= 0;
            s2_exp <= 0;
            s2_mant <= 0;
            s2_sticky <= 0;
            s2_is_special <= 0;
            s2_special_result <= 0;
            s2_one_zero <= 0;
        end else begin
            s2_valid <= s1_valid;
            s2_sign <= s1_result_sign;
            s2_exp <= s1_lg_exp;
            s2_mant <= sum_mant;
            s2_sticky <= sum_sticky;
            s2_is_special <= s1_is_nan || s1_is_inf || s1_is_zero ||
                             s1_sm_zero || (s1_lg_mant == 27'd0);
            s2_special_result <= s1_special_result;
            s2_one_zero <= s1_sm_zero || (s1_lg_mant == 27'd0);
        end
    end

    // ---- Stage 3: normalize + round + pack ----

    // Count leading zeros in 28-bit mantissa
    function [4:0] clz28;
        input [27:0] val;
        reg found;
        integer i;
        begin
            clz28 = 5'd28;
            found = 0;
            for (i = 27; i >= 0; i = i - 1) begin
                if (!found && val[i]) begin
                    clz28 = 5'd27 - i[4:0];
                    found = 1;
                end
            end
        end
    endfunction

    wire [4:0] lzc = clz28(s2_mant);

    // Normalization: shift mantissa left by (lzc - 1) to place leading 1 at bit 26
    // Or shift right if carry (bit 27 set, lzc=0)
    // After normalization: bit[26] = implicit 1, bits[25:3] = mantissa, bits[2:0] = GRS
    reg [27:0] norm_mant;
    reg [8:0]  norm_exp;  // Signed-ish (9 bits for underflow detection)
    reg        norm_sticky;

    always @(*) begin
        norm_sticky = s2_sticky;
        if (s2_mant == 28'd0) begin
            norm_mant = 28'd0;
            norm_exp  = 9'd0;
        end else if (lzc == 5'd0) begin
            // Carry out: shift right 1
            norm_sticky = s2_sticky | s2_mant[0];
            norm_mant = {1'b0, s2_mant[27:1]};
            norm_exp  = {1'b0, s2_exp} + 9'd1;
        end else if (lzc == 5'd1) begin
            // Already normalized (leading 1 at bit 26)
            norm_mant = s2_mant;
            norm_exp  = {1'b0, s2_exp};
        end else begin
            // Left shift by (lzc - 1)
            norm_mant = s2_mant << (lzc - 5'd1);
            norm_exp  = {1'b0, s2_exp} - {4'd0, lzc} + 9'd1;
        end
    end

    // Extract mantissa and GRS
    wire [22:0] final_mant = norm_mant[25:3];
    wire        guard      = norm_mant[2];
    wire        round_bit  = norm_mant[1];
    wire        sticky_all = norm_mant[0] | norm_sticky;

    // Round to nearest even
    wire round_up = guard && (round_bit || sticky_all || final_mant[0]);

    wire [23:0] rounded_mant = {1'b0, final_mant} + {23'd0, round_up};
    // If rounded mantissa overflows (bit 23 set), shift right and increment exp
    wire        round_overflow = rounded_mant[23];
    wire [22:0] result_mant = round_overflow ? rounded_mant[23:1] : rounded_mant[22:0];
    wire [8:0]  result_exp  = round_overflow ? norm_exp + 9'd1 : norm_exp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 0;
            result    <= 0;
        end else begin
            out_valid <= s2_valid;
            if (s2_is_special)
                result <= s2_special_result;
            else if (s2_mant == 28'd0)
                result <= {s2_sign, 31'd0};  // Exact zero from cancellation
            else if (result_exp >= 9'd255)
                result <= {s2_sign, 8'hFF, 23'd0};  // Overflow → Inf
            else if (result_exp[8] || result_exp == 9'd0)
                result <= {s2_sign, 31'd0};  // Underflow → zero
            else
                result <= {s2_sign, result_exp[7:0], result_mant};
        end
    end

endmodule
