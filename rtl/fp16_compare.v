// =============================================================================
// fp16_compare.v — FP16 Max/Min Comparator (combinational)
// =============================================================================
// Compares two FP16 values considering sign-magnitude encoding.
// Handles NaN (propagated), ±0 (treated as equal).
// =============================================================================

`timescale 1ns / 1ps

module fp16_compare (
    input  wire [15:0] a_in,
    input  wire [15:0] b_in,
    output reg  [15:0] max_out,
    output reg  [15:0] min_out,
    output reg         a_gt_b
);

    wire        a_sign = a_in[15];
    wire [4:0]  a_exp  = a_in[14:10];
    wire [9:0]  a_mant = a_in[9:0];
    wire        b_sign = b_in[15];
    wire [4:0]  b_exp  = b_in[14:10];
    wire [9:0]  b_mant = b_in[9:0];

    wire a_nan = (a_exp == 5'd31) && (a_mant != 10'd0);
    wire b_nan = (b_exp == 5'd31) && (b_mant != 10'd0);

    // Sign-magnitude comparison
    // Positive > Negative; for same sign, compare magnitude
    reg a_greater;
    always @(*) begin
        if (a_sign != b_sign)
            a_greater = b_sign;  // a positive, b negative → a > b
        else if (a_sign == 1'b0)
            // Both positive: larger magnitude = larger value
            a_greater = (a_exp > b_exp) ||
                        ((a_exp == b_exp) && (a_mant > b_mant));
        else
            // Both negative: smaller magnitude = larger value
            a_greater = (a_exp < b_exp) ||
                        ((a_exp == b_exp) && (a_mant < b_mant));
    end

    always @(*) begin
        if (a_nan || b_nan) begin
            // Propagate NaN
            max_out = {1'b0, 5'b11111, 1'b1, 9'd0};
            min_out = {1'b0, 5'b11111, 1'b1, 9'd0};
            a_gt_b  = 1'b0;
        end else begin
            a_gt_b  = a_greater;
            max_out = a_greater ? a_in : b_in;
            min_out = a_greater ? b_in : a_in;
        end
    end

endmodule
