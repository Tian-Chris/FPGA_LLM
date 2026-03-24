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
    initial begin
        exp_lut[0] = 16'h3c00;
        exp_lut[1] = 16'h3b84;
        exp_lut[2] = 16'h3b0f;
        exp_lut[3] = 16'h3aa2;
        exp_lut[4] = 16'h3a3b;
        exp_lut[5] = 16'h39da;
        exp_lut[6] = 16'h3980;
        exp_lut[7] = 16'h392a;
        exp_lut[8] = 16'h38da;
        exp_lut[9] = 16'h388f;
        exp_lut[10] = 16'h3848;
        exp_lut[11] = 16'h3806;
        exp_lut[12] = 16'h378f;
        exp_lut[13] = 16'h371a;
        exp_lut[14] = 16'h36ab;
        exp_lut[15] = 16'h3644;
        exp_lut[16] = 16'h35e3;
        exp_lut[17] = 16'h3588;
        exp_lut[18] = 16'h3532;
        exp_lut[19] = 16'h34e1;
        exp_lut[20] = 16'h3496;
        exp_lut[21] = 16'h344e;
        exp_lut[22] = 16'h340c;
        exp_lut[23] = 16'h339a;
        exp_lut[24] = 16'h3324;
        exp_lut[25] = 16'h32b5;
        exp_lut[26] = 16'h324d;
        exp_lut[27] = 16'h31eb;
        exp_lut[28] = 16'h3190;
        exp_lut[29] = 16'h3139;
        exp_lut[30] = 16'h30e8;
        exp_lut[31] = 16'h309c;
        exp_lut[32] = 16'h3055;
        exp_lut[33] = 16'h3011;
        exp_lut[34] = 16'h2fa5;
        exp_lut[35] = 16'h2f2e;
        exp_lut[36] = 16'h2ebf;
        exp_lut[37] = 16'h2e56;
        exp_lut[38] = 16'h2df4;
        exp_lut[39] = 16'h2d98;
        exp_lut[40] = 16'h2d41;
        exp_lut[41] = 16'h2cef;
        exp_lut[42] = 16'h2ca3;
        exp_lut[43] = 16'h2c5b;
        exp_lut[44] = 16'h2c17;
        exp_lut[45] = 16'h2bb0;
        exp_lut[46] = 16'h2b39;
        exp_lut[47] = 16'h2ac9;
        exp_lut[48] = 16'h2a5f;
        exp_lut[49] = 16'h29fd;
        exp_lut[50] = 16'h29a0;
        exp_lut[51] = 16'h2948;
        exp_lut[52] = 16'h28f7;
        exp_lut[53] = 16'h28aa;
        exp_lut[54] = 16'h2861;
        exp_lut[55] = 16'h281d;
        exp_lut[56] = 16'h27bb;
        exp_lut[57] = 16'h2743;
        exp_lut[58] = 16'h26d2;
        exp_lut[59] = 16'h2669;
        exp_lut[60] = 16'h2605;
        exp_lut[61] = 16'h25a8;
        exp_lut[62] = 16'h2550;
        exp_lut[63] = 16'h24fe;
        exp_lut[64] = 16'h24b0;
        exp_lut[65] = 16'h2468;
        exp_lut[66] = 16'h2423;
        exp_lut[67] = 16'h23c6;
        exp_lut[68] = 16'h234e;
        exp_lut[69] = 16'h22dc;
        exp_lut[70] = 16'h2272;
        exp_lut[71] = 16'h220e;
        exp_lut[72] = 16'h21b0;
        exp_lut[73] = 16'h2158;
        exp_lut[74] = 16'h2105;
        exp_lut[75] = 16'h20b7;
        exp_lut[76] = 16'h206e;
        exp_lut[77] = 16'h2029;
        exp_lut[78] = 16'h1fd1;
        exp_lut[79] = 16'h1f58;
        exp_lut[80] = 16'h1ee6;
        exp_lut[81] = 16'h1e7b;
        exp_lut[82] = 16'h1e17;
        exp_lut[83] = 16'h1db8;
        exp_lut[84] = 16'h1d60;
        exp_lut[85] = 16'h1d0c;
        exp_lut[86] = 16'h1cbe;
        exp_lut[87] = 16'h1c74;
        exp_lut[88] = 16'h1c2f;
        exp_lut[89] = 16'h1bdd;
        exp_lut[90] = 16'h1b63;
        exp_lut[91] = 16'h1af0;
        exp_lut[92] = 16'h1a85;
        exp_lut[93] = 16'h1a20;
        exp_lut[94] = 16'h19c1;
        exp_lut[95] = 16'h1967;
        exp_lut[96] = 16'h1914;
        exp_lut[97] = 16'h18c5;
        exp_lut[98] = 16'h187b;
        exp_lut[99] = 16'h1835;
        exp_lut[100] = 16'h17e8;
        exp_lut[101] = 16'h176e;
        exp_lut[102] = 16'h16fa;
        exp_lut[103] = 16'h168e;
        exp_lut[104] = 16'h1628;
        exp_lut[105] = 16'h15c9;
        exp_lut[106] = 16'h156f;
        exp_lut[107] = 16'h151b;
        exp_lut[108] = 16'h14cc;
        exp_lut[109] = 16'h1481;
        exp_lut[110] = 16'h143b;
        exp_lut[111] = 16'h13f4;
        exp_lut[112] = 16'h1378;
        exp_lut[113] = 16'h1304;
        exp_lut[114] = 16'h1298;
        exp_lut[115] = 16'h1231;
        exp_lut[116] = 16'h11d1;
        exp_lut[117] = 16'h1177;
        exp_lut[118] = 16'h1122;
        exp_lut[119] = 16'h10d3;
        exp_lut[120] = 16'h1088;
        exp_lut[121] = 16'h1042;
        exp_lut[122] = 16'h0fff;
        exp_lut[123] = 16'h0f83;
        exp_lut[124] = 16'h0f0f;
        exp_lut[125] = 16'h0ea1;
        exp_lut[126] = 16'h0e3a;
        exp_lut[127] = 16'h0dda;
        exp_lut[128] = 16'h0d7f;
        exp_lut[129] = 16'h0d2a;
        exp_lut[130] = 16'h0cda;
        exp_lut[131] = 16'h0c8e;
        exp_lut[132] = 16'h0c48;
        exp_lut[133] = 16'h0c05;
        exp_lut[134] = 16'h0b8e;
        exp_lut[135] = 16'h0b19;
        exp_lut[136] = 16'h0aab;
        exp_lut[137] = 16'h0a43;
        exp_lut[138] = 16'h09e2;
        exp_lut[139] = 16'h0987;
        exp_lut[140] = 16'h0931;
        exp_lut[141] = 16'h08e1;
        exp_lut[142] = 16'h0895;
        exp_lut[143] = 16'h084e;
        exp_lut[144] = 16'h080b;
        exp_lut[145] = 16'h0799;
        exp_lut[146] = 16'h0723;
        exp_lut[147] = 16'h06b4;
        exp_lut[148] = 16'h064c;
        exp_lut[149] = 16'h05eb;
        exp_lut[150] = 16'h058f;
        exp_lut[151] = 16'h0539;
        exp_lut[152] = 16'h04e8;
        exp_lut[153] = 16'h049c;
        exp_lut[154] = 16'h0454;
        exp_lut[155] = 16'h0411;
        exp_lut[156] = 16'h03d2;
        exp_lut[157] = 16'h0397;
        exp_lut[158] = 16'h035f;
        exp_lut[159] = 16'h032b;
        exp_lut[160] = 16'h02fa;
        exp_lut[161] = 16'h02cc;
        exp_lut[162] = 16'h02a0;
        exp_lut[163] = 16'h0277;
        exp_lut[164] = 16'h0251;
        exp_lut[165] = 16'h022d;
        exp_lut[166] = 16'h020b;
        exp_lut[167] = 16'h01ec;
        exp_lut[168] = 16'h01ce;
        exp_lut[169] = 16'h01b2;
        exp_lut[170] = 16'h0198;
        exp_lut[171] = 16'h017f;
        exp_lut[172] = 16'h0168;
        exp_lut[173] = 16'h0152;
        exp_lut[174] = 16'h013e;
        exp_lut[175] = 16'h012a;
        exp_lut[176] = 16'h0118;
        exp_lut[177] = 16'h0107;
        exp_lut[178] = 16'h00f7;
        exp_lut[179] = 16'h00e8;
        exp_lut[180] = 16'h00da;
        exp_lut[181] = 16'h00cd;
        exp_lut[182] = 16'h00c1;
        exp_lut[183] = 16'h00b5;
        exp_lut[184] = 16'h00aa;
        exp_lut[185] = 16'h00a0;
        exp_lut[186] = 16'h0096;
        exp_lut[187] = 16'h008d;
        exp_lut[188] = 16'h0084;
        exp_lut[189] = 16'h007c;
        exp_lut[190] = 16'h0075;
        exp_lut[191] = 16'h006e;
        exp_lut[192] = 16'h0067;
        exp_lut[193] = 16'h0061;
        exp_lut[194] = 16'h005b;
        exp_lut[195] = 16'h0055;
        exp_lut[196] = 16'h0050;
        exp_lut[197] = 16'h004b;
        exp_lut[198] = 16'h0047;
        exp_lut[199] = 16'h0043;
        exp_lut[200] = 16'h003f;
        exp_lut[201] = 16'h003b;
        exp_lut[202] = 16'h0037;
        exp_lut[203] = 16'h0034;
        exp_lut[204] = 16'h0031;
        exp_lut[205] = 16'h002e;
        exp_lut[206] = 16'h002b;
        exp_lut[207] = 16'h0028;
        exp_lut[208] = 16'h0026;
        exp_lut[209] = 16'h0024;
        exp_lut[210] = 16'h0021;
        exp_lut[211] = 16'h001f;
        exp_lut[212] = 16'h001e;
        exp_lut[213] = 16'h001c;
        exp_lut[214] = 16'h001a;
        exp_lut[215] = 16'h0018;
        exp_lut[216] = 16'h0017;
        exp_lut[217] = 16'h0016;
        exp_lut[218] = 16'h0014;
        exp_lut[219] = 16'h0013;
        exp_lut[220] = 16'h0012;
        exp_lut[221] = 16'h0011;
        exp_lut[222] = 16'h0010;
        exp_lut[223] = 16'h000f;
        exp_lut[224] = 16'h000e;
        exp_lut[225] = 16'h000d;
        exp_lut[226] = 16'h000c;
        exp_lut[227] = 16'h000c;
        exp_lut[228] = 16'h000b;
        exp_lut[229] = 16'h000a;
        exp_lut[230] = 16'h000a;
        exp_lut[231] = 16'h0009;
        exp_lut[232] = 16'h0008;
        exp_lut[233] = 16'h0008;
        exp_lut[234] = 16'h0007;
        exp_lut[235] = 16'h0007;
        exp_lut[236] = 16'h0007;
        exp_lut[237] = 16'h0006;
        exp_lut[238] = 16'h0006;
        exp_lut[239] = 16'h0005;
        exp_lut[240] = 16'h0005;
        exp_lut[241] = 16'h0005;
        exp_lut[242] = 16'h0005;
        exp_lut[243] = 16'h0004;
        exp_lut[244] = 16'h0004;
        exp_lut[245] = 16'h0004;
        exp_lut[246] = 16'h0004;
        exp_lut[247] = 16'h0003;
        exp_lut[248] = 16'h0003;
        exp_lut[249] = 16'h0003;
        exp_lut[250] = 16'h0003;
        exp_lut[251] = 16'h0003;
        exp_lut[252] = 16'h0002;
        exp_lut[253] = 16'h0002;
        exp_lut[254] = 16'h0002;
        exp_lut[255] = 16'h0002;
    end

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
