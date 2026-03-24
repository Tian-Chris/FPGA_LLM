// =============================================================================
// fp_mac_unit.v — FP16×FP16 → Integer Accumulate → FP32 Output (3-stage pipe)
// =============================================================================
// Same pipeline depth and port interface as before for drop-in replacement.
//   Stage 1: Registered inputs (a_r, b_r)
//   Stage 2: FP16 multiply → product (sign, exp, 22-bit mantissa) (registered)
//   Stage 3: Integer accumulate (exponent-aligned add) + convert to FP32
//
// Accumulator state: acc_val (32-bit signed integer) + acc_exp (8-bit biased)
// No FP32 adder — only integer add + barrel shift.
// Output (acc_out) is IEEE FP32 bit pattern, converted combinationally from
// (acc_val, acc_exp) when read by matmul_engine.
//
// Inputs are FP16 bit patterns. Subnormals (exp=0) flushed to zero.
// =============================================================================

`timescale 1ns / 1ps

module fp_mac_unit #(
    parameter DATA_W = 16,
    parameter ACC_W  = 32
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 clear,
    input  wire                 enable,

    input  wire [DATA_W-1:0]   a_in,    // FP16 bit pattern
    input  wire [DATA_W-1:0]   b_in,    // FP16 bit pattern

    output wire [ACC_W-1:0]    acc_out  // FP32 bit pattern (converted from int acc)
);

    // =========================================================================
    // Stage 1: Registered inputs
    // =========================================================================
    reg [DATA_W-1:0] a_r, b_r;
    reg              enable_s1, clear_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r       <= 0;
            b_r       <= 0;
            enable_s1 <= 1'b0;
            clear_s1  <= 1'b0;
        end else begin
            a_r       <= a_in;
            b_r       <= b_in;
            enable_s1 <= enable;
            clear_s1  <= clear;
        end
    end

    // =========================================================================
    // Stage 2: FP16 multiply → product components
    // =========================================================================
    // Unpack FP16
    wire        a_sign = a_r[15];
    wire [4:0]  a_exp  = a_r[14:10];
    wire [9:0]  a_mant = a_r[9:0];
    wire        b_sign = b_r[15];
    wire [4:0]  b_exp  = b_r[14:10];
    wire [9:0]  b_mant = b_r[9:0];

    wire either_zero = (a_exp == 5'd0) || (b_exp == 5'd0);

    // Sign
    wire prod_sign = a_sign ^ b_sign;

    // Mantissa multiply: {1, mant} × {1, mant} = 11×11 = 22 bits
    wire [21:0] mant_prod = {1'b1, a_mant} * {1'b1, b_mant};

    // Product mantissa is in format 1x.xxxx (bit 21) or 0x.xxxx (bit 20)
    // Normalize: ensure leading 1 is at bit 21
    wire        prod_hi = mant_prod[21];
    wire [21:0] mant_norm = prod_hi ? mant_prod : {mant_prod[20:0], 1'b0};

    // Product exponent (biased, FP32-compatible)
    // = (a_exp - 15) + (b_exp - 15) + 127 + prod_hi
    // = a_exp + b_exp + 97 + prod_hi
    wire [8:0]  prod_exp_wide = {4'd0, a_exp} + {4'd0, b_exp} + 9'd97 + {8'd0, prod_hi};
    wire [7:0]  prod_exp = prod_exp_wide[7:0];

    // Register Stage 2 outputs
    reg         prod_sign_r;
    reg [7:0]   prod_exp_r;
    reg [21:0]  prod_mant_r;    // Normalized 22-bit mantissa (leading 1 at bit 21)
    reg         prod_zero_r;
    reg         enable_s2, clear_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_sign_r <= 1'b0;
            prod_exp_r  <= 8'd0;
            prod_mant_r <= 22'd0;
            prod_zero_r <= 1'b1;
            enable_s2   <= 1'b0;
            clear_s2    <= 1'b0;
        end else begin
            prod_sign_r <= prod_sign;
            prod_exp_r  <= prod_exp;
            prod_mant_r <= mant_norm;
            prod_zero_r <= either_zero;
            enable_s2   <= enable_s1;
            clear_s2    <= clear_s1;
        end
    end

    // =========================================================================
    // Stage 3: Integer Accumulate
    // =========================================================================
    // Accumulator state: signed 32-bit value + 8-bit biased exponent
    // The mantissa lives in bits [21:0] of acc_val when only one product,
    // but grows as products accumulate (up to ~27 bits for 32 products).
    reg signed [31:0] acc_val;
    reg        [7:0]  acc_exp;
    reg               acc_zero;     // Accumulator is zero

    // Signed product mantissa (22-bit unsigned → 23-bit signed)
    wire signed [22:0] prod_signed = prod_sign_r ? -{1'b0, prod_mant_r} : {1'b0, prod_mant_r};

    // Exponent difference (unsigned) and direction
    wire        acc_ge_prod = (acc_exp >= prod_exp_r);
    wire [7:0]  shift_amt   = acc_ge_prod ? (acc_exp - prod_exp_r)
                                          : (prod_exp_r - acc_exp);
    wire [4:0]  shift_clamp = (shift_amt > 8'd27) ? 5'd27 : shift_amt[4:0];
    wire        shift_discard = (shift_amt > 8'd27);

    // Sign-extended product as 32-bit signed
    wire signed [31:0] prod_ext = {{10{prod_signed[22]}}, prod_signed[21:0]};

    // Compute aligned values and new accumulator
    reg signed [31:0] new_acc_val;
    reg        [7:0]  new_acc_exp;
    reg signed [31:0] prod_aligned;
    reg signed [31:0] acc_aligned;

    always @(*) begin
        prod_aligned = 32'sd0;
        acc_aligned  = 32'sd0;
        new_acc_val  = acc_val;
        new_acc_exp  = acc_exp;

        if (prod_zero_r || !enable_s2) begin
            // Zero product or disabled — keep accumulator unchanged
        end else if (acc_zero) begin
            // First product — just load it
            new_acc_val = prod_ext;
            new_acc_exp = prod_exp_r;
        end else if (acc_ge_prod) begin
            // acc_exp >= prod_exp: shift product right to align
            if (!shift_discard) begin
                prod_aligned = prod_ext >>> shift_clamp;
                new_acc_val = acc_val + prod_aligned;
            end
            new_acc_exp = acc_exp;
        end else begin
            // prod_exp > acc_exp: shift accumulator right, adopt product's exponent
            if (!shift_discard) begin
                acc_aligned = acc_val >>> shift_clamp;
                new_acc_val = acc_aligned + prod_ext;
            end else begin
                new_acc_val = prod_ext;
            end
            new_acc_exp = prod_exp_r;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_val  <= 32'sd0;
            acc_exp  <= 8'd0;
            acc_zero <= 1'b1;
        end else if (clear_s2) begin
            acc_val  <= 32'sd0;
            acc_exp  <= 8'd0;
            acc_zero <= 1'b1;
        end else if (enable_s2) begin
            acc_val  <= new_acc_val;
            acc_exp  <= new_acc_exp;
            acc_zero <= (acc_zero && prod_zero_r);
        end
    end

    // =========================================================================
    // Output: Convert (acc_val, acc_exp) → IEEE FP32
    // =========================================================================
    // This is combinational so matmul_engine can read acc_out as FP32.
    // Only used when accumulation is complete (not in the critical add path).

    // Find leading bit position of |acc_val|
    wire               out_sign = acc_val[31];
    wire [31:0]        abs_val  = out_sign ? (-acc_val) : acc_val;

    // CLZ on abs_val to find leading one
    reg [4:0] lzc;
    integer i;
    always @(*) begin
        lzc = 5'd31;
        for (i = 31; i >= 0; i = i - 1) begin
            if (abs_val[i] && lzc == 5'd31)
                lzc = 5'd31 - i[4:0];
        end
    end

    // Shift to normalize: put leading 1 at bit 23 (hidden bit position for FP32)
    wire [4:0]  lead_pos = 5'd31 - lzc;  // Position of leading 1

    wire [31:0] shifted_val = (lead_pos >= 5'd23) ? (abs_val >> (lead_pos - 5'd23))
                                                   : (abs_val << (5'd23 - lead_pos));
    wire [22:0] out_mant = shifted_val[22:0];

    // Output exponent: acc_exp corresponds to mantissa leading 1 at bit 21
    // Adjustment: lead_pos relative to 21
    wire signed [8:0] exp_adjust = {4'd0, lead_pos} - 9'sd21;
    wire signed [8:0] out_exp_s  = {1'b0, acc_exp} + exp_adjust;

    // Pack FP32
    reg [31:0] acc_out_r;
    always @(*) begin
        if (acc_zero || acc_val == 32'sd0) begin
            acc_out_r = 32'd0;
        end else if (out_exp_s >= 9'sd255) begin
            acc_out_r = {out_sign, 8'hFF, 23'd0};     // Overflow → Inf
        end else if (out_exp_s <= 9'sd0) begin
            acc_out_r = {out_sign, 31'd0};             // Underflow → zero
        end else begin
            acc_out_r = {out_sign, out_exp_s[7:0], out_mant};
        end
    end

    assign acc_out = acc_out_r;

endmodule
