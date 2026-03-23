`ifndef FP_FUNCS_VH
`define FP_FUNCS_VH
// =============================================================================
// fp_funcs.vh — Combinational FP16/FP32 arithmetic functions
// =============================================================================
// Include in modules that need inline FP operations (layernorm, softmax, etc.)
// All functions are combinational (no pipeline registers).
// Subnormals flushed to zero.
// =============================================================================

// ---- FP16 → FP32 conversion ----
function [31:0] fp16_to_fp32_func;
    input [15:0] val;
    reg        s;
    reg [4:0]  e16;
    reg [9:0]  m16;
    begin
        s   = val[15];
        e16 = val[14:10];
        m16 = val[9:0];
        if (e16 == 5'd0)
            fp16_to_fp32_func = {s, 31'd0};
        else if (e16 == 5'd31)
            fp16_to_fp32_func = {s, 8'hFF, m16, 13'd0};
        else
            fp16_to_fp32_func = {s, {3'd0, e16} + 8'd112, m16, 13'd0};
    end
endfunction

// ---- FP32 → FP16 conversion ----
function [15:0] fp32_to_fp16_func;
    input [31:0] val;
    reg        sign;
    reg [7:0]  exp;
    reg [22:0] mant;
    reg signed [8:0] new_exp;
    reg [9:0]  trunc_mant;
    reg        guard, rnd, sticky, round_up;
    reg [10:0] rounded;
    reg [9:0]  rmant;
    reg signed [8:0] rexp;
    begin
        sign = val[31]; exp = val[30:23]; mant = val[22:0];
        new_exp = {1'b0, exp} - 9'sd112;
        if (exp == 8'hFF && mant != 23'd0)
            fp32_to_fp16_func = {sign, 5'b11111, 1'b1, mant[21:13]};
        else if (exp == 8'hFF)
            fp32_to_fp16_func = {sign, 5'b11111, 10'd0};
        else if (exp == 8'd0)
            fp32_to_fp16_func = {sign, 15'd0};
        else begin
            trunc_mant = mant[22:13];
            guard = mant[12]; rnd = mant[11]; sticky = |mant[10:0];
            round_up = guard && (rnd || sticky || trunc_mant[0]);
            rounded = {1'b0, trunc_mant} + {10'd0, round_up};
            if (rounded[10]) begin
                rmant = 10'd0; rexp = new_exp + 9'sd1;
            end else begin
                rmant = rounded[9:0]; rexp = new_exp;
            end
            if (rexp >= 9'sd31)
                fp32_to_fp16_func = {sign, 5'b11111, 10'd0};
            else if (rexp <= 9'sd0)
                fp32_to_fp16_func = {sign, 15'd0};
            else
                fp32_to_fp16_func = {sign, rexp[4:0], rmant};
        end
    end
endfunction

// ---- FP32 + FP32 → FP32 (combinational) ----
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
    reg [4:0]  lzc;
    reg [27:0] norm_m;
    reg [8:0]  norm_e;
    reg        norm_sticky;
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
        if (a_e == 8'hFF || b_e == 8'hFF) begin
            if ((a_e == 8'hFF && a_m != 0) || (b_e == 8'hFF && b_m != 0))
                fp32_add_comb = {1'b0, 8'hFF, 23'h400000};
            else if (a_e == 8'hFF && b_e == 8'hFF && a_s != b_s)
                fp32_add_comb = {1'b0, 8'hFF, 23'h400000};
            else if (a_e == 8'hFF) fp32_add_comb = a;
            else fp32_add_comb = b;
        end else if (a_z && b_z) begin
            fp32_add_comb = {a_s & b_s, 31'd0};
        end else if (a_z) begin
            fp32_add_comb = b;
        end else if (b_z) begin
            fp32_add_comb = a;
        end else begin
            if (a_e > b_e || (a_e == b_e && a_m >= b_m)) begin
                lg_s = a_s; lg_e = a_e; lg_m_r = a_m;
                sm_s = b_s; sm_e = b_e; sm_m_r = b_m;
            end else begin
                lg_s = b_s; lg_e = b_e; lg_m_r = b_m;
                sm_s = a_s; sm_e = a_e; sm_m_r = a_m;
            end
            res_s = lg_s; eff_sub = lg_s ^ sm_s;
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
                lzc = 5'd28;
                for (k = 27; k >= 0; k = k - 1)
                    if (sum_m[k] && lzc == 5'd28) lzc = 27 - k;
                norm_sticky = sticky;
                if (lzc == 5'd0) begin
                    norm_sticky = sticky | sum_m[0];
                    norm_m = {1'b0, sum_m[27:1]}; norm_e = {1'b0, lg_e} + 9'd1;
                end else if (lzc == 5'd1) begin
                    norm_m = sum_m; norm_e = {1'b0, lg_e};
                end else begin
                    norm_m = sum_m << (lzc - 5'd1);
                    norm_e = {1'b0, lg_e} - {4'd0, lzc} + 9'd1;
                end
                fmant = norm_m[25:3]; g = norm_m[2]; r = norm_m[1];
                s_all = norm_m[0] | norm_sticky;
                rup = g && (r || s_all || fmant[0]);
                rounded = {1'b0, fmant} + {23'd0, rup};
                if (rounded[23]) begin
                    rmant = rounded[23:1]; rexp = norm_e + 9'd1;
                end else begin
                    rmant = rounded[22:0]; rexp = norm_e;
                end
                if (rexp >= 9'd255) fp32_add_comb = {res_s, 8'hFF, 23'd0};
                else if (rexp[8] || rexp == 9'd0) fp32_add_comb = {res_s, 31'd0};
                else fp32_add_comb = {res_s, rexp[7:0], rmant};
            end
        end
    end
endfunction

// ---- FP32 × FP32 → FP32 (combinational) ----
function [31:0] fp32_mult_comb;
    input [31:0] a, b;
    reg        a_s, b_s, res_s;
    reg [7:0]  a_e, b_e;
    reg [22:0] a_m, b_m;
    reg        a_z, b_z, a_inf, b_inf, a_nan, b_nan;
    reg [47:0] prod;
    reg        prod_hi;
    reg [22:0] pmant;
    reg        g, r, sticky, rup;
    reg [23:0] rounded;
    reg [8:0]  rexp;
    begin
        a_s = a[31]; b_s = b[31]; res_s = a_s ^ b_s;
        a_e = a[30:23]; b_e = b[30:23];
        a_m = a[22:0]; b_m = b[22:0];
        a_z = (a_e == 8'd0); b_z = (b_e == 8'd0);
        a_inf = (a_e == 8'hFF) && (a_m == 0);
        b_inf = (b_e == 8'hFF) && (b_m == 0);
        a_nan = (a_e == 8'hFF) && (a_m != 0);
        b_nan = (b_e == 8'hFF) && (b_m != 0);

        if (a_nan || b_nan || (a_inf && b_z) || (b_inf && a_z))
            fp32_mult_comb = {1'b0, 8'hFF, 23'h400000};
        else if (a_inf || b_inf)
            fp32_mult_comb = {res_s, 8'hFF, 23'd0};
        else if (a_z || b_z)
            fp32_mult_comb = {res_s, 31'd0};
        else begin
            // 24×24 mantissa multiply
            prod = {1'b1, a_m} * {1'b1, b_m};  // 48 bits
            prod_hi = prod[47];

            // Normalize
            if (prod_hi) begin
                pmant = prod[46:24];
                g = prod[23]; r = prod[22]; sticky = |prod[21:0];
                rexp = {1'b0, a_e} + {1'b0, b_e} - 9'd126;
            end else begin
                pmant = prod[45:23];
                g = prod[22]; r = prod[21]; sticky = |prod[20:0];
                rexp = {1'b0, a_e} + {1'b0, b_e} - 9'd127;
            end

            // Round to nearest even
            rup = g && (r || sticky || pmant[0]);
            rounded = {1'b0, pmant} + {23'd0, rup};
            if (rounded[23]) begin
                rexp = rexp + 9'd1;
            end

            if (rexp >= 9'd255)
                fp32_mult_comb = {res_s, 8'hFF, 23'd0};
            else if (rexp[8] || rexp == 9'd0)
                fp32_mult_comb = {res_s, 31'd0};
            else
                fp32_mult_comb = {res_s, rexp[7:0], rounded[22:0]};
        end
    end
endfunction

// ---- FP32 reciprocal of power-of-2 dimension ----
function [31:0] fp32_recip_dim;
    input [15:0] d;
    begin
        case (d)
            16'd4:    fp32_recip_dim = 32'h3E800000;  // 0.25
            16'd8:    fp32_recip_dim = 32'h3E000000;  // 0.125
            16'd16:   fp32_recip_dim = 32'h3D800000;  // 0.0625
            16'd32:   fp32_recip_dim = 32'h3D000000;  // 1/32
            16'd64:   fp32_recip_dim = 32'h3C800000;  // 1/64
            16'd128:  fp32_recip_dim = 32'h3C000000;  // 1/128
            16'd256:  fp32_recip_dim = 32'h3B800000;  // 1/256
            16'd512:  fp32_recip_dim = 32'h3B000000;  // 1/512
            16'd1024: fp32_recip_dim = 32'h3A800000;  // 1/1024
            default:  fp32_recip_dim = 32'h3B800000;  // 1/256
        endcase
    end
endfunction

// ---- FP16 × FP16 → FP16 (combinational) ----
function [15:0] fp16_mult_comb;
    input [15:0] a, b;
    reg        a_s, b_s, res_s;
    reg [4:0]  a_e, b_e;
    reg [9:0]  a_m, b_m;
    reg        a_z, b_z;
    reg [21:0] prod;
    reg        prod_hi;
    reg [9:0]  pmant;
    reg        g, r, sticky, rup;
    reg [10:0] rounded;
    reg [5:0]  rexp;
    begin
        a_s = a[15]; b_s = b[15]; res_s = a_s ^ b_s;
        a_e = a[14:10]; b_e = b[14:10];
        a_m = a[9:0]; b_m = b[9:0];
        a_z = (a_e == 5'd0); b_z = (b_e == 5'd0);

        if ((a_e == 5'd31 && a_m != 0) || (b_e == 5'd31 && b_m != 0))
            fp16_mult_comb = {1'b0, 5'b11111, 10'h200};  // NaN
        else if ((a_e == 5'd31 && b_z) || (b_e == 5'd31 && a_z))
            fp16_mult_comb = {1'b0, 5'b11111, 10'h200};  // Inf*0 = NaN
        else if (a_e == 5'd31 || b_e == 5'd31)
            fp16_mult_comb = {res_s, 5'b11111, 10'd0};   // Inf
        else if (a_z || b_z)
            fp16_mult_comb = {res_s, 15'd0};              // Zero
        else begin
            prod = {1'b1, a_m} * {1'b1, b_m};  // 11×11 = 22 bits
            prod_hi = prod[21];
            if (prod_hi) begin
                pmant = prod[20:11];
                g = prod[10]; r = prod[9]; sticky = |prod[8:0];
                rexp = {1'b0, a_e} + {1'b0, b_e} - 6'd14;
            end else begin
                pmant = prod[19:10];
                g = prod[9]; r = prod[8]; sticky = |prod[7:0];
                rexp = {1'b0, a_e} + {1'b0, b_e} - 6'd15;
            end
            rup = g && (r || sticky || pmant[0]);
            rounded = {1'b0, pmant} + {10'd0, rup};
            if (rounded[10])
                rexp = rexp + 6'd1;
            if (rexp[5] || rexp == 6'd0)
                fp16_mult_comb = {res_s, 15'd0};
            else if (rexp >= 6'd31)
                fp16_mult_comb = {res_s, 5'b11111, 10'd0};
            else
                fp16_mult_comb = {res_s, rexp[4:0], rounded[9:0]};
        end
    end
endfunction

// ---- FP16 + FP16 → FP16 (combinational) ----
function [15:0] fp16_add_comb;
    input [15:0] a, b;
    reg        a_s, b_s, lg_s, sm_s, res_s, eff_sub;
    reg [4:0]  a_e, b_e, lg_e, sm_e;
    reg [9:0]  a_m, b_m, lg_mr, sm_mr;
    reg        a_z, b_z;
    reg [4:0]  ediff;
    reg [3:0]  shift;
    reg [13:0] lg_ext, sm_ext, aligned, restored;
    reg        sticky_bit;
    reg [14:0] sum_m;
    reg [3:0]  lzc;
    reg [14:0] norm_m;
    reg [5:0]  norm_e;
    reg        norm_sticky;
    reg [9:0]  fmant;
    reg        g, r, s_all, rup;
    reg [10:0] rounded;
    reg [9:0]  rmant;
    reg [5:0]  rexp;
    integer    k;
    begin
        a_s = a[15]; a_e = a[14:10]; a_m = a[9:0];
        b_s = b[15]; b_e = b[14:10]; b_m = b[9:0];
        a_z = (a_e == 5'd0); b_z = (b_e == 5'd0);

        if ((a_e == 5'd31) || (b_e == 5'd31)) begin
            if (a_e == 5'd31 && a_m != 0)      fp16_add_comb = a;
            else if (b_e == 5'd31 && b_m != 0)  fp16_add_comb = b;
            else fp16_add_comb = (a_e == 5'd31) ? a : b;
        end else if (a_z && b_z) begin
            fp16_add_comb = {a_s & b_s, 15'd0};
        end else if (a_z) begin
            fp16_add_comb = b;
        end else if (b_z) begin
            fp16_add_comb = a;
        end else begin
            if (a_e > b_e || (a_e == b_e && a_m >= b_m)) begin
                lg_s = a_s; lg_e = a_e; lg_mr = a_m;
                sm_s = b_s; sm_e = b_e; sm_mr = b_m;
            end else begin
                lg_s = b_s; lg_e = b_e; lg_mr = b_m;
                sm_s = a_s; sm_e = a_e; sm_mr = a_m;
            end
            res_s = lg_s;
            eff_sub = lg_s ^ sm_s;
            ediff = lg_e - sm_e;
            shift = (ediff > 5'd14) ? 4'd14 : ediff[3:0];
            lg_ext = {1'b1, lg_mr, 3'b000};
            sm_ext = {1'b1, sm_mr, 3'b000};
            aligned = sm_ext >> shift;
            restored = aligned << shift;
            sticky_bit = (restored != sm_ext);
            if (eff_sub)
                sum_m = {1'b0, lg_ext} - {1'b0, aligned} - {14'd0, sticky_bit};
            else
                sum_m = {1'b0, lg_ext} + {1'b0, aligned};

            if (sum_m == 15'd0) begin
                fp16_add_comb = 16'd0;
            end else begin
                lzc = 4'd15;
                for (k = 14; k >= 0; k = k - 1)
                    if (sum_m[k] && lzc == 4'd15) lzc = 14 - k;
                norm_sticky = sticky_bit;
                if (lzc == 4'd0) begin
                    norm_sticky = sticky_bit | sum_m[0];
                    norm_m = {1'b0, sum_m[14:1]};
                    norm_e = {1'b0, lg_e} + 6'd1;
                end else if (lzc == 4'd1) begin
                    norm_m = sum_m;
                    norm_e = {1'b0, lg_e};
                end else begin
                    norm_m = sum_m << (lzc - 4'd1);
                    norm_e = {1'b0, lg_e} - {2'd0, lzc} + 6'd1;
                end
                fmant = norm_m[12:3];
                g = norm_m[2]; r = norm_m[1];
                s_all = norm_m[0] | norm_sticky;
                rup = g && (r || s_all || fmant[0]);
                rounded = {1'b0, fmant} + {10'd0, rup};
                if (rounded[10]) begin
                    rmant = 10'd0; rexp = norm_e + 6'd1;
                end else begin
                    rmant = rounded[9:0]; rexp = norm_e;
                end
                if (rexp >= 6'd31)
                    fp16_add_comb = {res_s, 5'b11111, 10'd0};
                else if (rexp[5] || rexp == 6'd0)
                    fp16_add_comb = {res_s, 15'd0};
                else
                    fp16_add_comb = {res_s, rexp[4:0], rmant};
            end
        end
    end
endfunction
`endif // FP_FUNCS_VH
