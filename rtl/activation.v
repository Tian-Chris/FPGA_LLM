`include "defines.vh"

// =============================================================================
// activation.v — GELU activation via 512-entry LUT
// =============================================================================
// Maps FP16 input to FP16 output using GELU lookup table.
// Index: clamp((x + 8.0) * 32, 0, 511)
// Below -8: output ≈ 0. Above 8: output ≈ x. Between: LUT lookup.
// =============================================================================

module activation_unit #(
    parameter DATA_WIDTH = 16,
    parameter MAX_DIM    = 256
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Control
    input  wire                     start,
    input  wire [15:0]              dim,
    output reg                      done,
    output reg                      busy,

    // Memory interface
    output reg                      mem_rd_en,
    output reg  [15:0]              mem_rd_addr,
    input  wire [DATA_WIDTH-1:0]    mem_rd_data,
    input  wire                     mem_rd_valid,

    output reg                      mem_wr_en,
    output reg  [15:0]              mem_wr_addr,
    output reg  [DATA_WIDTH-1:0]    mem_wr_data
);

    reg [1:0] state;
    localparam ST_IDLE    = 2'd0;
    localparam ST_PROCESS = 2'd1;
    localparam ST_DONE    = 2'd2;
    reg [15:0] dim_r, idx;

    // GELU LUT: 512 entries of FP16 bit patterns
    reg [15:0] gelu_lut [0:511];
    initial begin
        gelu_lut[0] = 16'h8000;
        gelu_lut[1] = 16'h8000;
        gelu_lut[2] = 16'h8000;
        gelu_lut[3] = 16'h8000;
        gelu_lut[4] = 16'h8000;
        gelu_lut[5] = 16'h8000;
        gelu_lut[6] = 16'h8000;
        gelu_lut[7] = 16'h8000;
        gelu_lut[8] = 16'h8000;
        gelu_lut[9] = 16'h8000;
        gelu_lut[10] = 16'h8000;
        gelu_lut[11] = 16'h8000;
        gelu_lut[12] = 16'h8000;
        gelu_lut[13] = 16'h8000;
        gelu_lut[14] = 16'h8000;
        gelu_lut[15] = 16'h8000;
        gelu_lut[16] = 16'h8000;
        gelu_lut[17] = 16'h8000;
        gelu_lut[18] = 16'h8000;
        gelu_lut[19] = 16'h8000;
        gelu_lut[20] = 16'h8000;
        gelu_lut[21] = 16'h8000;
        gelu_lut[22] = 16'h8000;
        gelu_lut[23] = 16'h8000;
        gelu_lut[24] = 16'h8000;
        gelu_lut[25] = 16'h8000;
        gelu_lut[26] = 16'h8000;
        gelu_lut[27] = 16'h8000;
        gelu_lut[28] = 16'h8000;
        gelu_lut[29] = 16'h8000;
        gelu_lut[30] = 16'h8000;
        gelu_lut[31] = 16'h8000;
        gelu_lut[32] = 16'h8000;
        gelu_lut[33] = 16'h8000;
        gelu_lut[34] = 16'h8000;
        gelu_lut[35] = 16'h8000;
        gelu_lut[36] = 16'h8000;
        gelu_lut[37] = 16'h8000;
        gelu_lut[38] = 16'h8000;
        gelu_lut[39] = 16'h8000;
        gelu_lut[40] = 16'h8000;
        gelu_lut[41] = 16'h8000;
        gelu_lut[42] = 16'h8000;
        gelu_lut[43] = 16'h8000;
        gelu_lut[44] = 16'h8000;
        gelu_lut[45] = 16'h8000;
        gelu_lut[46] = 16'h8000;
        gelu_lut[47] = 16'h8000;
        gelu_lut[48] = 16'h8000;
        gelu_lut[49] = 16'h8000;
        gelu_lut[50] = 16'h8000;
        gelu_lut[51] = 16'h8000;
        gelu_lut[52] = 16'h8000;
        gelu_lut[53] = 16'h8000;
        gelu_lut[54] = 16'h8000;
        gelu_lut[55] = 16'h8000;
        gelu_lut[56] = 16'h8000;
        gelu_lut[57] = 16'h8000;
        gelu_lut[58] = 16'h8000;
        gelu_lut[59] = 16'h8000;
        gelu_lut[60] = 16'h8000;
        gelu_lut[61] = 16'h8000;
        gelu_lut[62] = 16'h8000;
        gelu_lut[63] = 16'h8000;
        gelu_lut[64] = 16'h8000;
        gelu_lut[65] = 16'h8000;
        gelu_lut[66] = 16'h8000;
        gelu_lut[67] = 16'h8000;
        gelu_lut[68] = 16'h8000;
        gelu_lut[69] = 16'h8000;
        gelu_lut[70] = 16'h8000;
        gelu_lut[71] = 16'h8000;
        gelu_lut[72] = 16'h8000;
        gelu_lut[73] = 16'h8001;
        gelu_lut[74] = 16'h8001;
        gelu_lut[75] = 16'h8001;
        gelu_lut[76] = 16'h8001;
        gelu_lut[77] = 16'h8001;
        gelu_lut[78] = 16'h8001;
        gelu_lut[79] = 16'h8001;
        gelu_lut[80] = 16'h8002;
        gelu_lut[81] = 16'h8002;
        gelu_lut[82] = 16'h8002;
        gelu_lut[83] = 16'h8003;
        gelu_lut[84] = 16'h8003;
        gelu_lut[85] = 16'h8004;
        gelu_lut[86] = 16'h8005;
        gelu_lut[87] = 16'h8006;
        gelu_lut[88] = 16'h8007;
        gelu_lut[89] = 16'h8008;
        gelu_lut[90] = 16'h8009;
        gelu_lut[91] = 16'h800b;
        gelu_lut[92] = 16'h800d;
        gelu_lut[93] = 16'h800f;
        gelu_lut[94] = 16'h8012;
        gelu_lut[95] = 16'h8015;
        gelu_lut[96] = 16'h8018;
        gelu_lut[97] = 16'h801c;
        gelu_lut[98] = 16'h8021;
        gelu_lut[99] = 16'h8026;
        gelu_lut[100] = 16'h802c;
        gelu_lut[101] = 16'h8034;
        gelu_lut[102] = 16'h803c;
        gelu_lut[103] = 16'h8046;
        gelu_lut[104] = 16'h8051;
        gelu_lut[105] = 16'h805e;
        gelu_lut[106] = 16'h806d;
        gelu_lut[107] = 16'h807e;
        gelu_lut[108] = 16'h8091;
        gelu_lut[109] = 16'h80a8;
        gelu_lut[110] = 16'h80c1;
        gelu_lut[111] = 16'h80df;
        gelu_lut[112] = 16'h8101;
        gelu_lut[113] = 16'h8127;
        gelu_lut[114] = 16'h8153;
        gelu_lut[115] = 16'h8185;
        gelu_lut[116] = 16'h81be;
        gelu_lut[117] = 16'h81fe;
        gelu_lut[118] = 16'h8248;
        gelu_lut[119] = 16'h829b;
        gelu_lut[120] = 16'h82fa;
        gelu_lut[121] = 16'h8365;
        gelu_lut[122] = 16'h83df;
        gelu_lut[123] = 16'h8468;
        gelu_lut[124] = 16'h8503;
        gelu_lut[125] = 16'h85b2;
        gelu_lut[126] = 16'h8677;
        gelu_lut[127] = 16'h8754;
        gelu_lut[128] = 16'h8827;
        gelu_lut[129] = 16'h88b3;
        gelu_lut[130] = 16'h8950;
        gelu_lut[131] = 16'h8a00;
        gelu_lut[132] = 16'h8ac5;
        gelu_lut[133] = 16'h8ba1;
        gelu_lut[134] = 16'h8c4c;
        gelu_lut[135] = 16'h8cd5;
        gelu_lut[136] = 16'h8d6f;
        gelu_lut[137] = 16'h8e19;
        gelu_lut[138] = 16'h8ed7;
        gelu_lut[139] = 16'h8faa;
        gelu_lut[140] = 16'h904a;
        gelu_lut[141] = 16'h90cc;
        gelu_lut[142] = 16'h915c;
        gelu_lut[143] = 16'h91fb;
        gelu_lut[144] = 16'h92ac;
        gelu_lut[145] = 16'h936e;
        gelu_lut[146] = 16'h9422;
        gelu_lut[147] = 16'h9498;
        gelu_lut[148] = 16'h951a;
        gelu_lut[149] = 16'h95a9;
        gelu_lut[150] = 16'h9646;
        gelu_lut[151] = 16'h96f2;
        gelu_lut[152] = 16'h97ae;
        gelu_lut[153] = 16'h983e;
        gelu_lut[154] = 16'h98af;
        gelu_lut[155] = 16'h992a;
        gelu_lut[156] = 16'h99b1;
        gelu_lut[157] = 16'h9a43;
        gelu_lut[158] = 16'h9ae2;
        gelu_lut[159] = 16'h9b8f;
        gelu_lut[160] = 16'h9c26;
        gelu_lut[161] = 16'h9c8c;
        gelu_lut[162] = 16'h9cfa;
        gelu_lut[163] = 16'h9d71;
        gelu_lut[164] = 16'h9df3;
        gelu_lut[165] = 16'h9e7e;
        gelu_lut[166] = 16'h9f14;
        gelu_lut[167] = 16'h9fb6;
        gelu_lut[168] = 16'ha032;
        gelu_lut[169] = 16'ha090;
        gelu_lut[170] = 16'ha0f4;
        gelu_lut[171] = 16'ha15f;
        gelu_lut[172] = 16'ha1d3;
        gelu_lut[173] = 16'ha24e;
        gelu_lut[174] = 16'ha2d1;
        gelu_lut[175] = 16'ha35d;
        gelu_lut[176] = 16'ha3f3;
        gelu_lut[177] = 16'ha449;
        gelu_lut[178] = 16'ha49d;
        gelu_lut[179] = 16'ha4f7;
        gelu_lut[180] = 16'ha556;
        gelu_lut[181] = 16'ha5ba;
        gelu_lut[182] = 16'ha624;
        gelu_lut[183] = 16'ha694;
        gelu_lut[184] = 16'ha70b;
        gelu_lut[185] = 16'ha787;
        gelu_lut[186] = 16'ha805;
        gelu_lut[187] = 16'ha849;
        gelu_lut[188] = 16'ha891;
        gelu_lut[189] = 16'ha8dd;
        gelu_lut[190] = 16'ha92b;
        gelu_lut[191] = 16'ha97d;
        gelu_lut[192] = 16'ha9d3;
        gelu_lut[193] = 16'haa2c;
        gelu_lut[194] = 16'haa88;
        gelu_lut[195] = 16'haae8;
        gelu_lut[196] = 16'hab4c;
        gelu_lut[197] = 16'habb2;
        gelu_lut[198] = 16'hac0e;
        gelu_lut[199] = 16'hac45;
        gelu_lut[200] = 16'hac7d;
        gelu_lut[201] = 16'hacb6;
        gelu_lut[202] = 16'hacf1;
        gelu_lut[203] = 16'had2d;
        gelu_lut[204] = 16'had6b;
        gelu_lut[205] = 16'hada9;
        gelu_lut[206] = 16'hade9;
        gelu_lut[207] = 16'hae29;
        gelu_lut[208] = 16'hae6a;
        gelu_lut[209] = 16'haeab;
        gelu_lut[210] = 16'haeed;
        gelu_lut[211] = 16'haf2f;
        gelu_lut[212] = 16'haf71;
        gelu_lut[213] = 16'hafb3;
        gelu_lut[214] = 16'haff4;
        gelu_lut[215] = 16'hb01a;
        gelu_lut[216] = 16'hb03a;
        gelu_lut[217] = 16'hb059;
        gelu_lut[218] = 16'hb077;
        gelu_lut[219] = 16'hb095;
        gelu_lut[220] = 16'hb0b1;
        gelu_lut[221] = 16'hb0cc;
        gelu_lut[222] = 16'hb0e5;
        gelu_lut[223] = 16'hb0fd;
        gelu_lut[224] = 16'hb114;
        gelu_lut[225] = 16'hb128;
        gelu_lut[226] = 16'hb13a;
        gelu_lut[227] = 16'hb14a;
        gelu_lut[228] = 16'hb158;
        gelu_lut[229] = 16'hb162;
        gelu_lut[230] = 16'hb16a;
        gelu_lut[231] = 16'hb16f;
        gelu_lut[232] = 16'hb170;
        gelu_lut[233] = 16'hb16e;
        gelu_lut[234] = 16'hb169;
        gelu_lut[235] = 16'hb15f;
        gelu_lut[236] = 16'hb152;
        gelu_lut[237] = 16'hb140;
        gelu_lut[238] = 16'hb12a;
        gelu_lut[239] = 16'hb10f;
        gelu_lut[240] = 16'hb0f0;
        gelu_lut[241] = 16'hb0cb;
        gelu_lut[242] = 16'hb0a2;
        gelu_lut[243] = 16'hb073;
        gelu_lut[244] = 16'hb03f;
        gelu_lut[245] = 16'hb005;
        gelu_lut[246] = 16'haf8c;
        gelu_lut[247] = 16'haf02;
        gelu_lut[248] = 16'hae6c;
        gelu_lut[249] = 16'hadca;
        gelu_lut[250] = 16'had1c;
        gelu_lut[251] = 16'hac61;
        gelu_lut[252] = 16'hab34;
        gelu_lut[253] = 16'ha98d;
        gelu_lut[254] = 16'ha79a;
        gelu_lut[255] = 16'ha3cd;
        gelu_lut[256] = 16'h0000;
        gelu_lut[257] = 16'h241a;
        gelu_lut[258] = 16'h2833;
        gelu_lut[259] = 16'h2a73;
        gelu_lut[260] = 16'h2c66;
        gelu_lut[261] = 16'h2d9f;
        gelu_lut[262] = 16'h2ee4;
        gelu_lut[263] = 16'h301b;
        gelu_lut[264] = 16'h30ca;
        gelu_lut[265] = 16'h317f;
        gelu_lut[266] = 16'h323a;
        gelu_lut[267] = 16'h32fb;
        gelu_lut[268] = 16'h33c1;
        gelu_lut[269] = 16'h3446;
        gelu_lut[270] = 16'h34af;
        gelu_lut[271] = 16'h351a;
        gelu_lut[272] = 16'h3588;
        gelu_lut[273] = 16'h35f8;
        gelu_lut[274] = 16'h366b;
        gelu_lut[275] = 16'h36e0;
        gelu_lut[276] = 16'h3757;
        gelu_lut[277] = 16'h37d0;
        gelu_lut[278] = 16'h3826;
        gelu_lut[279] = 16'h3864;
        gelu_lut[280] = 16'h38a4;
        gelu_lut[281] = 16'h38e4;
        gelu_lut[282] = 16'h3925;
        gelu_lut[283] = 16'h3967;
        gelu_lut[284] = 16'h39aa;
        gelu_lut[285] = 16'h39ed;
        gelu_lut[286] = 16'h3a31;
        gelu_lut[287] = 16'h3a76;
        gelu_lut[288] = 16'h3abb;
        gelu_lut[289] = 16'h3b01;
        gelu_lut[290] = 16'h3b47;
        gelu_lut[291] = 16'h3b8d;
        gelu_lut[292] = 16'h3bd4;
        gelu_lut[293] = 16'h3c0d;
        gelu_lut[294] = 16'h3c31;
        gelu_lut[295] = 16'h3c55;
        gelu_lut[296] = 16'h3c79;
        gelu_lut[297] = 16'h3c9d;
        gelu_lut[298] = 16'h3cc1;
        gelu_lut[299] = 16'h3ce5;
        gelu_lut[300] = 16'h3d09;
        gelu_lut[301] = 16'h3d2d;
        gelu_lut[302] = 16'h3d51;
        gelu_lut[303] = 16'h3d75;
        gelu_lut[304] = 16'h3d99;
        gelu_lut[305] = 16'h3dbd;
        gelu_lut[306] = 16'h3de1;
        gelu_lut[307] = 16'h3e05;
        gelu_lut[308] = 16'h3e29;
        gelu_lut[309] = 16'h3e4d;
        gelu_lut[310] = 16'h3e71;
        gelu_lut[311] = 16'h3e95;
        gelu_lut[312] = 16'h3eb8;
        gelu_lut[313] = 16'h3edc;
        gelu_lut[314] = 16'h3eff;
        gelu_lut[315] = 16'h3f22;
        gelu_lut[316] = 16'h3f46;
        gelu_lut[317] = 16'h3f69;
        gelu_lut[318] = 16'h3f8c;
        gelu_lut[319] = 16'h3faf;
        gelu_lut[320] = 16'h3fd1;
        gelu_lut[321] = 16'h3ff4;
        gelu_lut[322] = 16'h400b;
        gelu_lut[323] = 16'h401d;
        gelu_lut[324] = 16'h402e;
        gelu_lut[325] = 16'h403f;
        gelu_lut[326] = 16'h4050;
        gelu_lut[327] = 16'h4061;
        gelu_lut[328] = 16'h4072;
        gelu_lut[329] = 16'h4083;
        gelu_lut[330] = 16'h4094;
        gelu_lut[331] = 16'h40a5;
        gelu_lut[332] = 16'h40b5;
        gelu_lut[333] = 16'h40c6;
        gelu_lut[334] = 16'h40d7;
        gelu_lut[335] = 16'h40e7;
        gelu_lut[336] = 16'h40f8;
        gelu_lut[337] = 16'h4109;
        gelu_lut[338] = 16'h4119;
        gelu_lut[339] = 16'h412a;
        gelu_lut[340] = 16'h413a;
        gelu_lut[341] = 16'h414b;
        gelu_lut[342] = 16'h415b;
        gelu_lut[343] = 16'h416b;
        gelu_lut[344] = 16'h417c;
        gelu_lut[345] = 16'h418c;
        gelu_lut[346] = 16'h419c;
        gelu_lut[347] = 16'h41ad;
        gelu_lut[348] = 16'h41bd;
        gelu_lut[349] = 16'h41cd;
        gelu_lut[350] = 16'h41de;
        gelu_lut[351] = 16'h41ee;
        gelu_lut[352] = 16'h41fe;
        gelu_lut[353] = 16'h420e;
        gelu_lut[354] = 16'h421e;
        gelu_lut[355] = 16'h422e;
        gelu_lut[356] = 16'h423f;
        gelu_lut[357] = 16'h424f;
        gelu_lut[358] = 16'h425f;
        gelu_lut[359] = 16'h426f;
        gelu_lut[360] = 16'h427f;
        gelu_lut[361] = 16'h428f;
        gelu_lut[362] = 16'h429f;
        gelu_lut[363] = 16'h42af;
        gelu_lut[364] = 16'h42bf;
        gelu_lut[365] = 16'h42cf;
        gelu_lut[366] = 16'h42df;
        gelu_lut[367] = 16'h42f0;
        gelu_lut[368] = 16'h4300;
        gelu_lut[369] = 16'h4310;
        gelu_lut[370] = 16'h4320;
        gelu_lut[371] = 16'h4330;
        gelu_lut[372] = 16'h4340;
        gelu_lut[373] = 16'h4350;
        gelu_lut[374] = 16'h4360;
        gelu_lut[375] = 16'h4370;
        gelu_lut[376] = 16'h4380;
        gelu_lut[377] = 16'h4390;
        gelu_lut[378] = 16'h43a0;
        gelu_lut[379] = 16'h43b0;
        gelu_lut[380] = 16'h43c0;
        gelu_lut[381] = 16'h43d0;
        gelu_lut[382] = 16'h43e0;
        gelu_lut[383] = 16'h43f0;
        gelu_lut[384] = 16'h4400;
        gelu_lut[385] = 16'h4408;
        gelu_lut[386] = 16'h4410;
        gelu_lut[387] = 16'h4418;
        gelu_lut[388] = 16'h4420;
        gelu_lut[389] = 16'h4428;
        gelu_lut[390] = 16'h4430;
        gelu_lut[391] = 16'h4438;
        gelu_lut[392] = 16'h4440;
        gelu_lut[393] = 16'h4448;
        gelu_lut[394] = 16'h4450;
        gelu_lut[395] = 16'h4458;
        gelu_lut[396] = 16'h4460;
        gelu_lut[397] = 16'h4468;
        gelu_lut[398] = 16'h4470;
        gelu_lut[399] = 16'h4478;
        gelu_lut[400] = 16'h4480;
        gelu_lut[401] = 16'h4488;
        gelu_lut[402] = 16'h4490;
        gelu_lut[403] = 16'h4498;
        gelu_lut[404] = 16'h44a0;
        gelu_lut[405] = 16'h44a8;
        gelu_lut[406] = 16'h44b0;
        gelu_lut[407] = 16'h44b8;
        gelu_lut[408] = 16'h44c0;
        gelu_lut[409] = 16'h44c8;
        gelu_lut[410] = 16'h44d0;
        gelu_lut[411] = 16'h44d8;
        gelu_lut[412] = 16'h44e0;
        gelu_lut[413] = 16'h44e8;
        gelu_lut[414] = 16'h44f0;
        gelu_lut[415] = 16'h44f8;
        gelu_lut[416] = 16'h4500;
        gelu_lut[417] = 16'h4508;
        gelu_lut[418] = 16'h4510;
        gelu_lut[419] = 16'h4518;
        gelu_lut[420] = 16'h4520;
        gelu_lut[421] = 16'h4528;
        gelu_lut[422] = 16'h4530;
        gelu_lut[423] = 16'h4538;
        gelu_lut[424] = 16'h4540;
        gelu_lut[425] = 16'h4548;
        gelu_lut[426] = 16'h4550;
        gelu_lut[427] = 16'h4558;
        gelu_lut[428] = 16'h4560;
        gelu_lut[429] = 16'h4568;
        gelu_lut[430] = 16'h4570;
        gelu_lut[431] = 16'h4578;
        gelu_lut[432] = 16'h4580;
        gelu_lut[433] = 16'h4588;
        gelu_lut[434] = 16'h4590;
        gelu_lut[435] = 16'h4598;
        gelu_lut[436] = 16'h45a0;
        gelu_lut[437] = 16'h45a8;
        gelu_lut[438] = 16'h45b0;
        gelu_lut[439] = 16'h45b8;
        gelu_lut[440] = 16'h45c0;
        gelu_lut[441] = 16'h45c8;
        gelu_lut[442] = 16'h45d0;
        gelu_lut[443] = 16'h45d8;
        gelu_lut[444] = 16'h45e0;
        gelu_lut[445] = 16'h45e8;
        gelu_lut[446] = 16'h45f0;
        gelu_lut[447] = 16'h45f8;
        gelu_lut[448] = 16'h4600;
        gelu_lut[449] = 16'h4608;
        gelu_lut[450] = 16'h4610;
        gelu_lut[451] = 16'h4618;
        gelu_lut[452] = 16'h4620;
        gelu_lut[453] = 16'h4628;
        gelu_lut[454] = 16'h4630;
        gelu_lut[455] = 16'h4638;
        gelu_lut[456] = 16'h4640;
        gelu_lut[457] = 16'h4648;
        gelu_lut[458] = 16'h4650;
        gelu_lut[459] = 16'h4658;
        gelu_lut[460] = 16'h4660;
        gelu_lut[461] = 16'h4668;
        gelu_lut[462] = 16'h4670;
        gelu_lut[463] = 16'h4678;
        gelu_lut[464] = 16'h4680;
        gelu_lut[465] = 16'h4688;
        gelu_lut[466] = 16'h4690;
        gelu_lut[467] = 16'h4698;
        gelu_lut[468] = 16'h46a0;
        gelu_lut[469] = 16'h46a8;
        gelu_lut[470] = 16'h46b0;
        gelu_lut[471] = 16'h46b8;
        gelu_lut[472] = 16'h46c0;
        gelu_lut[473] = 16'h46c8;
        gelu_lut[474] = 16'h46d0;
        gelu_lut[475] = 16'h46d8;
        gelu_lut[476] = 16'h46e0;
        gelu_lut[477] = 16'h46e8;
        gelu_lut[478] = 16'h46f0;
        gelu_lut[479] = 16'h46f8;
        gelu_lut[480] = 16'h4700;
        gelu_lut[481] = 16'h4708;
        gelu_lut[482] = 16'h4710;
        gelu_lut[483] = 16'h4718;
        gelu_lut[484] = 16'h4720;
        gelu_lut[485] = 16'h4728;
        gelu_lut[486] = 16'h4730;
        gelu_lut[487] = 16'h4738;
        gelu_lut[488] = 16'h4740;
        gelu_lut[489] = 16'h4748;
        gelu_lut[490] = 16'h4750;
        gelu_lut[491] = 16'h4758;
        gelu_lut[492] = 16'h4760;
        gelu_lut[493] = 16'h4768;
        gelu_lut[494] = 16'h4770;
        gelu_lut[495] = 16'h4778;
        gelu_lut[496] = 16'h4780;
        gelu_lut[497] = 16'h4788;
        gelu_lut[498] = 16'h4790;
        gelu_lut[499] = 16'h4798;
        gelu_lut[500] = 16'h47a0;
        gelu_lut[501] = 16'h47a8;
        gelu_lut[502] = 16'h47b0;
        gelu_lut[503] = 16'h47b8;
        gelu_lut[504] = 16'h47c0;
        gelu_lut[505] = 16'h47c8;
        gelu_lut[506] = 16'h47d0;
        gelu_lut[507] = 16'h47d8;
        gelu_lut[508] = 16'h47e0;
        gelu_lut[509] = 16'h47e8;
        gelu_lut[510] = 16'h47f0;
        gelu_lut[511] = 16'h47f8;
    end

    reg rd_inflight;

    // GELU LUT index from FP16 input
    // Index = clamp((x + 8) * 32, 0, 511)
    // |x| * 32 = {1, mant} * 2^(exp-20), so right-shift by (20 - exp) for exp < 20
    function [8:0] gelu_index;
        input [15:0] x;
        reg        x_sign;
        reg [4:0]  x_exp;
        reg [9:0]  x_mant;
        reg [16:0] fixed_val;
        reg signed [16:0] shifted;
        begin
            x_sign = x[15];
            x_exp  = x[14:10];
            x_mant = x[9:0];

            if (x_exp == 5'd0) begin
                gelu_index = 9'd256;  // Zero/subnormal → GELU(0)
            end else if (x_exp == 5'd31) begin
                gelu_index = x_sign ? 9'd0 : 9'd511;
            end else if (x_exp >= 5'd20) begin
                // |x| >= 32 → way beyond ±8 range
                gelu_index = x_sign ? 9'd0 : 9'd511;
            end else if (x_exp >= 5'd10) begin
                // |x|*32 = {1, mant} >> (20 - exp)
                fixed_val = {1'b1, x_mant} >> (5'd20 - x_exp);
                if (x_sign)
                    shifted = 17'sd256 - fixed_val;
                else
                    shifted = 17'sd256 + fixed_val;

                if (shifted < 0)
                    gelu_index = 9'd0;
                else if (shifted > 17'sd511)
                    gelu_index = 9'd511;
                else
                    gelu_index = shifted[8:0];
            end else begin
                gelu_index = 9'd256;  // |x| < 1/32 → GELU(0)
            end
        end
    endfunction

    // Combinational GELU result from current read data
    wire [8:0]           cur_lut_idx  = gelu_index(mem_rd_data);
    wire [DATA_WIDTH-1:0] cur_gelu_out = gelu_lut[cur_lut_idx];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            mem_rd_en <= 1'b0;
            mem_wr_en <= 1'b0;
            idx       <= 0;
            rd_inflight <= 1'b0;
        end else begin
            done      <= 1'b0;
            mem_rd_en <= 1'b0;
            mem_wr_en <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state       <= ST_PROCESS;
                        busy        <= 1'b1;
                        dim_r       <= dim;
                        idx         <= 0;
                        rd_inflight <= 1'b0;
                    end
                end

                ST_PROCESS: begin
                    // When read data arrives, compute GELU and write back
                    if (mem_rd_valid) begin
                        mem_wr_en   <= 1'b1;
                        mem_wr_addr <= mem_rd_addr;
                        mem_wr_data <= cur_gelu_out;
                        rd_inflight <= 1'b0;
                    end

                    // Issue read only when no write pending and no read inflight
                    if (idx < dim_r && !rd_inflight && !mem_rd_valid) begin
                        mem_rd_en   <= 1'b1;
                        mem_rd_addr <= idx;
                        idx         <= idx + 1;
                        rd_inflight <= 1'b1;
                    end

                    if (idx == dim_r && !mem_rd_valid && !rd_inflight && !mem_wr_en) begin
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
