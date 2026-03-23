// =============================================================================
// fp_mac_unit.v — FP16×FP16 → FP32 Accumulate (3-stage pipeline)
// =============================================================================
// Same pipeline depth and port interface as mac_unit.v for drop-in replacement.
//   Stage 1: Registered inputs (a_r, b_r)
//   Stage 2: FP16 multiply → FP32 product (registered)
//   Stage 3: FP32 accumulate (combinational FP32 add + register)
//
// Inputs are FP16 bit patterns (not signed integers).
// acc_out is FP32 bit pattern.
// Subnormals (exp=0) flushed to zero.
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

    input  wire [DATA_W-1:0]    a_in,    // FP16 bit pattern
    input  wire [DATA_W-1:0]    b_in,    // FP16 bit pattern

    output reg  [ACC_W-1:0]     acc_out  // FP32 bit pattern
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
    // Stage 2: FP16 multiply → FP32 product
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

    // Normalize to FP32
    wire        prod_hi = mant_prod[21];
    wire [22:0] prod_mant = prod_hi ? {mant_prod[20:0], 2'b00}
                                    : {mant_prod[19:0], 3'b000};

    // FP32 exponent = (a_exp + b_exp) - 30 + 127 + shift = (a_exp + b_exp) + 97 + shift
    wire [7:0] prod_exp = ({3'd0, a_exp} + {3'd0, b_exp}) + 8'd97 + {7'd0, prod_hi};

    wire [31:0] product = either_zero ? {prod_sign, 31'd0}
                                      : {prod_sign, prod_exp, prod_mant};

    reg [31:0] product_r;
    reg        enable_s2, clear_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_r <= 32'd0;
            enable_s2 <= 1'b0;
            clear_s2  <= 1'b0;
        end else begin
            product_r <= product;
            enable_s2 <= enable_s1;
            clear_s2  <= clear_s1;
        end
    end

    // =========================================================================
    // Stage 3: FP32 Accumulate (combinational add + register)
    // =========================================================================
    wire [31:0] sum = fp32_add_comb(acc_out, product_r);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= 32'd0;
        end else if (clear_s2) begin
            acc_out <= 32'd0;  // FP32 +0
        end else if (enable_s2) begin
            acc_out <= sum;
        end
    end

    // =========================================================================
    // Combinational FP32 Adder Function
    // =========================================================================
    function [31:0] fp32_add_comb;
        input [31:0] a, b;

        reg        a_s, b_s, lg_s, sm_s, res_s, eff_sub;
        reg [7:0]  a_e, b_e, lg_e, sm_e;
        reg [22:0] a_m, b_m, lg_m_r, sm_m_r;
        reg        a_z, b_z;
        reg [7:0]  ediff;
        reg [4:0]  shift;
        reg [26:0] lg_ext, sm_ext, aligned, restored;
        reg        sticky;
        reg [27:0] sum_m;
        // Normalize
        reg [4:0]  lzc;
        reg [27:0] norm_m;
        reg [8:0]  norm_e;
        reg        norm_sticky;
        // Round
        reg [22:0] fmant;
        reg        g, r, s_all, rup;
        reg [23:0] rounded;
        reg [22:0] rmant;
        reg [8:0]  rexp;
        integer    k;

        begin
            a_s = a[31]; a_e = a[30:23]; a_m = a[22:0];
            b_s = b[31]; b_e = b[30:23]; b_m = b[22:0];
            a_z = (a_e == 8'd0); b_z = (b_e == 8'd0);

            // Special cases
            if (a_e == 8'hFF || b_e == 8'hFF) begin
                if ((a_e == 8'hFF && a_m != 0) || (b_e == 8'hFF && b_m != 0))
                    fp32_add_comb = {1'b0, 8'hFF, 23'h400000};
                else if (a_e == 8'hFF && b_e == 8'hFF && a_s != b_s)
                    fp32_add_comb = {1'b0, 8'hFF, 23'h400000};
                else if (a_e == 8'hFF)
                    fp32_add_comb = a;
                else
                    fp32_add_comb = b;
            end else if (a_z && b_z) begin
                fp32_add_comb = {a_s & b_s, 31'd0};
            end else if (a_z) begin
                fp32_add_comb = b;
            end else if (b_z) begin
                fp32_add_comb = a;
            end else begin
                // Compare magnitudes
                if (a_e > b_e || (a_e == b_e && a_m >= b_m)) begin
                    lg_s = a_s; lg_e = a_e; lg_m_r = a_m;
                    sm_s = b_s; sm_e = b_e; sm_m_r = b_m;
                end else begin
                    lg_s = b_s; lg_e = b_e; lg_m_r = b_m;
                    sm_s = a_s; sm_e = a_e; sm_m_r = a_m;
                end

                res_s = lg_s;
                eff_sub = lg_s ^ sm_s;
                ediff = lg_e - sm_e;
                shift = (ediff > 8'd27) ? 5'd27 : ediff[4:0];

                lg_ext = {1'b1, lg_m_r, 3'b000};
                sm_ext = {1'b1, sm_m_r, 3'b000};

                aligned = sm_ext >> shift;
                restored = aligned << shift;
                sticky = (restored != sm_ext);

                if (eff_sub)
                    sum_m = {1'b0, lg_ext} - {1'b0, aligned} - {27'd0, sticky};
                else
                    sum_m = {1'b0, lg_ext} + {1'b0, aligned};

                if (sum_m == 28'd0) begin
                    fp32_add_comb = 32'd0;
                end else begin
                    // CLZ
                    lzc = 5'd28;
                    for (k = 27; k >= 0; k = k - 1) begin
                        if (sum_m[k] && lzc == 5'd28)
                            lzc = 27 - k;
                    end

                    // Normalize
                    norm_sticky = sticky;
                    if (lzc == 5'd0) begin
                        norm_sticky = sticky | sum_m[0];
                        norm_m = {1'b0, sum_m[27:1]};
                        norm_e = {1'b0, lg_e} + 9'd1;
                    end else if (lzc == 5'd1) begin
                        norm_m = sum_m;
                        norm_e = {1'b0, lg_e};
                    end else begin
                        norm_m = sum_m << (lzc - 5'd1);
                        norm_e = {1'b0, lg_e} - {4'd0, lzc} + 9'd1;
                    end

                    // Round to nearest even
                    fmant = norm_m[25:3];
                    g = norm_m[2];
                    r = norm_m[1];
                    s_all = norm_m[0] | norm_sticky;
                    rup = g && (r || s_all || fmant[0]);
                    rounded = {1'b0, fmant} + {23'd0, rup};
                    if (rounded[23]) begin
                        rmant = rounded[23:1];
                        rexp = norm_e + 9'd1;
                    end else begin
                        rmant = rounded[22:0];
                        rexp = norm_e;
                    end

                    if (rexp >= 9'd255)
                        fp32_add_comb = {res_s, 8'hFF, 23'd0};
                    else if (rexp[8] || rexp == 9'd0)
                        fp32_add_comb = {res_s, 31'd0};
                    else
                        fp32_add_comb = {res_s, rexp[7:0], rmant};
                end
            end
        end
    endfunction

endmodule
