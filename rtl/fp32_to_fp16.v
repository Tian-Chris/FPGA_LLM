// =============================================================================
// fp32_to_fp16.v — FP32 → FP16 Conversion (combinational)
// =============================================================================
// Rebias exponent (−112), truncate mantissa 23→10 bits, round-to-nearest-even.
// Overflow → ±Inf, underflow → ±0.
// =============================================================================

`timescale 1ns / 1ps

module fp32_to_fp16 (
    input  wire [31:0] in,
    output reg  [15:0] out
);

    wire        sign = in[31];
    wire [7:0]  exp  = in[30:23];
    wire [22:0] mant = in[22:0];

    // Rebias: fp16_exp = fp32_exp - 127 + 15 = fp32_exp - 112
    wire signed [8:0] new_exp_s = {1'b0, exp} - 9'sd112;

    // Mantissa truncation: keep upper 10 bits, GRS from lower 13
    wire [9:0]  trunc_mant = mant[22:13];
    wire        guard      = mant[12];
    wire        round_bit  = mant[11];
    wire        sticky     = |mant[10:0];

    // Round to nearest even
    wire round_up = guard && (round_bit || sticky || trunc_mant[0]);
    wire [10:0] rounded = {1'b0, trunc_mant} + {10'd0, round_up};
    // If rounded overflows (bit 10 set): mantissa becomes 0, exponent increments
    wire        round_ovf = rounded[10];
    wire [9:0]  result_mant = round_ovf ? 10'd0 : rounded[9:0];
    wire signed [8:0] result_exp = round_ovf ? new_exp_s + 9'sd1 : new_exp_s;

    always @(*) begin
        if (exp == 8'hFF && mant != 23'd0)
            out = {sign, 5'b11111, 1'b1, mant[21:13]};     // NaN (preserve payload)
        else if (exp == 8'hFF)
            out = {sign, 5'b11111, 10'd0};                  // Inf
        else if (exp == 8'd0)
            out = {sign, 15'd0};                             // Zero (flush subnormals)
        else if (result_exp >= 9'sd31)
            out = {sign, 5'b11111, 10'd0};                  // Overflow → Inf
        else if (result_exp <= 9'sd0)
            out = {sign, 15'd0};                             // Underflow → zero
        else
            out = {sign, result_exp[4:0], result_mant};
    end

endmodule
