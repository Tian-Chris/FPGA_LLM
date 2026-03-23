// =============================================================================
// fp16_mult.v — FP16 × FP16 → FP32 Multiplier (2-stage pipeline)
// =============================================================================
// Stage 1: Unpack inputs, sign XOR, exponent add, register mantissas
// Stage 2: 11×11 mantissa multiply, normalize, pack FP32 result
//
// Subnormals (exp=0) are flushed to zero.
// =============================================================================

`timescale 1ns / 1ps

module fp16_mult (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [15:0] a_in,
    input  wire [15:0] b_in,
    output reg         out_valid,
    output reg  [31:0] result
);

    // FP16 unpack
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

    // ---- Stage 1: unpack + exponent add ----
    reg        s1_valid;
    reg        s1_sign;
    reg [5:0]  s1_exp_sum;   // ea + eb, max 60
    reg [10:0] s1_mant_a;    // {1, mantissa}
    reg [10:0] s1_mant_b;
    reg        s1_zero, s1_inf, s1_nan;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid  <= 1'b0;
            s1_sign   <= 1'b0;
            s1_exp_sum <= 6'd0;
            s1_mant_a <= 11'd0;
            s1_mant_b <= 11'd0;
            s1_zero   <= 1'b0;
            s1_inf    <= 1'b0;
            s1_nan    <= 1'b0;
        end else begin
            s1_valid  <= in_valid;
            s1_sign   <= a_sign ^ b_sign;
            s1_mant_a <= {1'b1, a_mant};
            s1_mant_b <= {1'b1, b_mant};
            s1_exp_sum <= {1'b0, a_exp} + {1'b0, b_exp};
            s1_zero   <= a_zero || b_zero;
            s1_inf    <= (a_inf || b_inf) && !a_nan && !b_nan;
            s1_nan    <= a_nan || b_nan || (a_inf && b_zero) || (b_inf && a_zero);
        end
    end

    // ---- Stage 2: mantissa multiply + pack FP32 ----
    wire [21:0] product = s1_mant_a * s1_mant_b;  // 11×11 = 22 bits

    // Normalize: product is in range [2^20, 2^22)
    // If product[21]=1: mantissa = product[20:0], exp += 1
    // If product[21]=0: mantissa = product[19:0] << 1
    wire        prod_hi  = product[21];
    wire [22:0] fp32_mant = prod_hi ? {product[20:0], 2'b00}
                                    : {product[19:0], 3'b000};

    // FP32 exponent = ea + eb - 30 + 127 + shift = exp_sum + 97 + prod_hi
    wire [8:0] result_exp = {3'd0, s1_exp_sum} + 9'd97 + {8'd0, prod_hi};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            result    <= 32'd0;
        end else begin
            out_valid <= s1_valid;
            if (s1_nan)
                result <= {s1_sign, 8'hFF, 23'h400000};    // Quiet NaN
            else if (s1_inf)
                result <= {s1_sign, 8'hFF, 23'd0};         // Infinity
            else if (s1_zero)
                result <= {s1_sign, 31'd0};                 // Zero
            else if (result_exp >= 9'd255)
                result <= {s1_sign, 8'hFF, 23'd0};         // Overflow → Inf
            else
                result <= {s1_sign, result_exp[7:0], fp32_mant};
        end
    end

endmodule
