`timescale 1ns / 1ps
`include "defines.vh"

// =============================================================================
// tb_matmul.v -- Testbench for matmul_controller with tile_loaders,
//                sim_hbm_ports, and uram_accum_buf
// =============================================================================
//
// Instantiates:
//   1. matmul_controller (DUT)
//   2. tile_loader for weights (connected to weight sim_hbm_port)
//   3. tile_loader for activations (connected to activation sim_hbm_port)
//   4. sim_hbm_port for weights
//   5. sim_hbm_port for activations
//   6. uram_accum_buf (output accumulation buffer)
//
// Test 1: Single-tile matmul (M=32, K=32, N=32)
//   A[i][j] = 1  for all i,j
//   B[k][j] = j + 1
//   Expected C[i][j] = 32 * (j + 1)
//
// Test 2: Multi-k-tile matmul (M=32, K=64, N=32)
//   A[i][j] = 1  for all i,j
//   B[k][j] = j + 1
//   Expected C[i][j] = 64 * (j + 1)
//
// Compatible with VLT: no X/Z, no SystemVerilog, no disable, no named end.
// =============================================================================

module tb_matmul;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter DATA_W     = 16;
    parameter OUT_W      = 16;
    parameter ACC_W      = 32;
    parameter TILE       = 32;
    parameter BUS_W      = 256;
    parameter BUS_EL     = BUS_W / DATA_W;   // 16
    parameter DIM_W      = 16;
    parameter HBM_ADDR_W = 28;
    parameter ID_W       = 4;
    parameter LEN_W      = 8;
    parameter HBM_DEPTH  = 4096;

    // URAM: small for sim
    parameter URAM_ROWS  = 64;
    parameter URAM_COLS  = 64;
    parameter N_ENG      = 6;
    parameter URAM_ROW_W = $clog2(URAM_ROWS);               // 6
    parameter URAM_COL_W = $clog2(URAM_COLS / (BUS_W / DATA_W));  // 2
    parameter URAM_WORDS = URAM_COLS / BUS_EL;               // 4

    // =========================================================================
    // Clock and reset
    // =========================================================================
    reg clk;
    reg rst_n;

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // VCD dump
    initial begin
        $dumpfile("scripts/wave.vcd");
        $dumpvars(0, tb_matmul);
    end

    // =========================================================================
    // DUT (matmul_controller) wires
    // =========================================================================
    reg                     cmd_valid;
    reg  [2:0]              cmd_op;
    reg  [DIM_W-1:0]        cmd_m, cmd_k, cmd_n;
    reg  [HBM_ADDR_W-1:0]  cmd_a_base, cmd_b_base;
    reg  [HBM_ADDR_W-1:0]  cmd_a_stride, cmd_b_stride;
    reg  [URAM_ROW_W-1:0]  cmd_out_row;
    reg  [URAM_COL_W-1:0]  cmd_out_col_word;
    wire                    cmd_ready;
    wire                    cmd_done;

    // Weight tile_loader command
    wire                    wgt_load_cmd_valid;
    wire                    wgt_load_cmd_ready;
    wire [HBM_ADDR_W-1:0]  wgt_load_hbm_base;
    wire [5:0]              wgt_load_tile_rows;
    wire [HBM_ADDR_W-1:0]  wgt_load_stride;
    wire                    wgt_load_cmd_done;

    // Weight tile_loader local read
    wire                    wgt_local_rd_en;
    wire [5:0]              wgt_local_rd_addr;
    wire [BUS_W-1:0]        wgt_local_rd_data;
    wire                    wgt_local_rd_valid;

    // Activation tile_loader command
    wire                    act_load_cmd_valid;
    wire                    act_load_cmd_ready;
    wire [HBM_ADDR_W-1:0]  act_load_hbm_base;
    wire [5:0]              act_load_tile_rows;
    wire [HBM_ADDR_W-1:0]  act_load_stride;
    wire                    act_load_cmd_done;

    // Activation tile_loader local read
    wire                    act_local_rd_en;
    wire [5:0]              act_local_rd_addr;
    wire [BUS_W-1:0]        act_local_rd_data;
    wire                    act_local_rd_valid;

    // URAM write
    wire                    uram_wr_en;
    wire [URAM_ROW_W-1:0]  uram_wr_row;
    wire [URAM_COL_W-1:0]  uram_wr_col_word;
    wire [BUS_W-1:0]        uram_wr_data;

    // =========================================================================
    // AXI wires: weight tile_loader <-> weight sim_hbm_port
    // =========================================================================
    wire [ID_W-1:0]         wgt_axi_arid;
    wire [HBM_ADDR_W-1:0]  wgt_axi_araddr;
    wire [LEN_W-1:0]        wgt_axi_arlen;
    wire                    wgt_axi_arvalid;
    wire                    wgt_axi_arready;

    wire [ID_W-1:0]         wgt_axi_rid;
    wire [BUS_W-1:0]        wgt_axi_rdata;
    wire [1:0]              wgt_axi_rresp;
    wire                    wgt_axi_rlast;
    wire                    wgt_axi_rvalid;
    wire                    wgt_axi_rready;

    // =========================================================================
    // AXI wires: activation tile_loader <-> activation sim_hbm_port
    // =========================================================================
    wire [ID_W-1:0]         act_axi_arid;
    wire [HBM_ADDR_W-1:0]  act_axi_araddr;
    wire [LEN_W-1:0]        act_axi_arlen;
    wire                    act_axi_arvalid;
    wire                    act_axi_arready;

    wire [ID_W-1:0]         act_axi_rid;
    wire [BUS_W-1:0]        act_axi_rdata;
    wire [1:0]              act_axi_rresp;
    wire                    act_axi_rlast;
    wire                    act_axi_rvalid;
    wire                    act_axi_rready;

    // =========================================================================
    // URAM packed port wires
    // =========================================================================
    reg  [N_ENG-1:0]                eng_wr_en_packed;
    reg  [URAM_ROW_W*N_ENG-1:0]    eng_wr_row_packed;
    reg  [URAM_COL_W*N_ENG-1:0]    eng_wr_col_word_packed;
    reg  [BUS_W*N_ENG-1:0]         eng_wr_data_packed;
    wire [N_ENG-1:0]               eng_wr_accept_packed;

    // URAM read port
    reg                     uram_rd_en;
    reg  [URAM_ROW_W-1:0]  uram_rd_row;
    reg  [URAM_COL_W-1:0]  uram_rd_col_word;
    wire [BUS_W-1:0]        uram_rd_data;
    wire                    uram_rd_valid;

    // Wire engine 0 from controller, tie off engines 1..5
    integer eng_idx;
    always @(*) begin
        // Default: all zeros
        eng_wr_en_packed       = {N_ENG{1'b0}};
        eng_wr_row_packed      = {(URAM_ROW_W*N_ENG){1'b0}};
        eng_wr_col_word_packed = {(URAM_COL_W*N_ENG){1'b0}};
        eng_wr_data_packed     = {(BUS_W*N_ENG){1'b0}};

        // Engine 0 driven by controller
        eng_wr_en_packed[0] = uram_wr_en;
        eng_wr_row_packed[0*URAM_ROW_W +: URAM_ROW_W] = uram_wr_row;
        eng_wr_col_word_packed[0*URAM_COL_W +: URAM_COL_W] = uram_wr_col_word;
        eng_wr_data_packed[0*BUS_W +: BUS_W] = uram_wr_data;
    end

    // =========================================================================
    // DUT: matmul_controller
    // =========================================================================
    matmul_controller #(
        .DATA_W(DATA_W),
        .OUT_W(OUT_W),
        .ACC_W(ACC_W),
        .TILE(TILE),
        .BUS_W(BUS_W),
        .DIM_W(DIM_W),
        .HBM_ADDR_W(HBM_ADDR_W),
        .URAM_ROW_W(URAM_ROW_W),
        .URAM_COL_W(URAM_COL_W)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),

        // Command
        .cmd_valid(cmd_valid),
        .cmd_op(cmd_op),
        .cmd_m(cmd_m),
        .cmd_k(cmd_k),
        .cmd_n(cmd_n),
        .cmd_a_base(cmd_a_base),
        .cmd_b_base(cmd_b_base),
        .cmd_a_stride(cmd_a_stride),
        .cmd_b_stride(cmd_b_stride),
        .cmd_out_row(cmd_out_row),
        .cmd_out_col_word(cmd_out_col_word),
        .cmd_ready(cmd_ready),
        .cmd_done(cmd_done),

        // Weight tile_loader command
        .wgt_load_cmd_valid(wgt_load_cmd_valid),
        .wgt_load_cmd_ready(wgt_load_cmd_ready),
        .wgt_load_hbm_base(wgt_load_hbm_base),
        .wgt_load_tile_rows(wgt_load_tile_rows),
        .wgt_load_stride(wgt_load_stride),
        .wgt_load_cmd_done(wgt_load_cmd_done),

        // Weight tile_loader local read
        .wgt_local_rd_en(wgt_local_rd_en),
        .wgt_local_rd_addr(wgt_local_rd_addr),
        .wgt_local_rd_data(wgt_local_rd_data),
        .wgt_local_rd_valid(wgt_local_rd_valid),

        // Activation tile_loader command
        .act_load_cmd_valid(act_load_cmd_valid),
        .act_load_cmd_ready(act_load_cmd_ready),
        .act_load_hbm_base(act_load_hbm_base),
        .act_load_tile_rows(act_load_tile_rows),
        .act_load_stride(act_load_stride),
        .act_load_cmd_done(act_load_cmd_done),

        // Activation tile_loader local read
        .act_local_rd_en(act_local_rd_en),
        .act_local_rd_addr(act_local_rd_addr),
        .act_local_rd_data(act_local_rd_data),
        .act_local_rd_valid(act_local_rd_valid),

        // URAM write
        .uram_wr_en(uram_wr_en),
        .uram_wr_row(uram_wr_row),
        .uram_wr_col_word(uram_wr_col_word),
        .uram_wr_data(uram_wr_data),
        .uram_wr_accept(eng_wr_accept_packed[0])
    );

    // =========================================================================
    // Weight tile_loader
    // =========================================================================
    tile_loader #(
        .TILE(TILE),
        .BUS_W(BUS_W),
        .DATA_W(DATA_W),
        .HBM_ADDR_W(HBM_ADDR_W),
        .ID_W(ID_W),
        .LEN_W(LEN_W)
    ) u_wgt_loader (
        .clk(clk),
        .rst_n(rst_n),

        // Command from controller
        .cmd_valid(wgt_load_cmd_valid),
        .cmd_ready(wgt_load_cmd_ready),
        .cmd_hbm_base(wgt_load_hbm_base),
        .cmd_tile_rows(wgt_load_tile_rows),
        .cmd_stride(wgt_load_stride),
        .cmd_done(wgt_load_cmd_done),

        // AXI master -> weight HBM
        .m_axi_arid(wgt_axi_arid),
        .m_axi_araddr(wgt_axi_araddr),
        .m_axi_arlen(wgt_axi_arlen),
        .m_axi_arvalid(wgt_axi_arvalid),
        .m_axi_arready(wgt_axi_arready),

        .m_axi_rid(wgt_axi_rid),
        .m_axi_rdata(wgt_axi_rdata),
        .m_axi_rresp(wgt_axi_rresp),
        .m_axi_rlast(wgt_axi_rlast),
        .m_axi_rvalid(wgt_axi_rvalid),
        .m_axi_rready(wgt_axi_rready),

        // Local read from controller
        .local_rd_en(wgt_local_rd_en),
        .local_rd_addr(wgt_local_rd_addr),
        .local_rd_data(wgt_local_rd_data),
        .local_rd_valid(wgt_local_rd_valid)
    );

    // =========================================================================
    // Activation tile_loader
    // =========================================================================
    tile_loader #(
        .TILE(TILE),
        .BUS_W(BUS_W),
        .DATA_W(DATA_W),
        .HBM_ADDR_W(HBM_ADDR_W),
        .ID_W(ID_W),
        .LEN_W(LEN_W)
    ) u_act_loader (
        .clk(clk),
        .rst_n(rst_n),

        // Command from controller
        .cmd_valid(act_load_cmd_valid),
        .cmd_ready(act_load_cmd_ready),
        .cmd_hbm_base(act_load_hbm_base),
        .cmd_tile_rows(act_load_tile_rows),
        .cmd_stride(act_load_stride),
        .cmd_done(act_load_cmd_done),

        // AXI master -> activation HBM
        .m_axi_arid(act_axi_arid),
        .m_axi_araddr(act_axi_araddr),
        .m_axi_arlen(act_axi_arlen),
        .m_axi_arvalid(act_axi_arvalid),
        .m_axi_arready(act_axi_arready),

        .m_axi_rid(act_axi_rid),
        .m_axi_rdata(act_axi_rdata),
        .m_axi_rresp(act_axi_rresp),
        .m_axi_rlast(act_axi_rlast),
        .m_axi_rvalid(act_axi_rvalid),
        .m_axi_rready(act_axi_rready),

        // Local read from controller
        .local_rd_en(act_local_rd_en),
        .local_rd_addr(act_local_rd_addr),
        .local_rd_data(act_local_rd_data),
        .local_rd_valid(act_local_rd_valid)
    );

    // =========================================================================
    // Weight HBM (sim_hbm_port)
    // =========================================================================
    sim_hbm_port #(
        .DEPTH(HBM_DEPTH),
        .ADDR_W(HBM_ADDR_W),
        .DATA_W(BUS_W),
        .ID_W(ID_W),
        .LEN_W(LEN_W),
        .INIT_FILE("")
    ) u_wgt_hbm (
        .clk(clk),
        .rst_n(rst_n),

        // AXI read (from weight tile_loader)
        .s_axi_arid(wgt_axi_arid),
        .s_axi_araddr(wgt_axi_araddr),
        .s_axi_arlen(wgt_axi_arlen),
        .s_axi_arvalid(wgt_axi_arvalid),
        .s_axi_arready(wgt_axi_arready),

        .s_axi_rid(wgt_axi_rid),
        .s_axi_rdata(wgt_axi_rdata),
        .s_axi_rresp(wgt_axi_rresp),
        .s_axi_rlast(wgt_axi_rlast),
        .s_axi_rvalid(wgt_axi_rvalid),
        .s_axi_rready(wgt_axi_rready),

        // AXI write (tied off -- read-only from controller perspective)
        .s_axi_awid({ID_W{1'b0}}),
        .s_axi_awaddr({HBM_ADDR_W{1'b0}}),
        .s_axi_awlen({LEN_W{1'b0}}),
        .s_axi_awvalid(1'b0),
        .s_axi_awready(),

        .s_axi_wdata({BUS_W{1'b0}}),
        .s_axi_wlast(1'b0),
        .s_axi_wvalid(1'b0),
        .s_axi_wready(),

        .s_axi_bid(),
        .s_axi_bresp(),
        .s_axi_bvalid(),
        .s_axi_bready(1'b0)
    );

    // =========================================================================
    // Activation HBM (sim_hbm_port)
    // =========================================================================
    sim_hbm_port #(
        .DEPTH(HBM_DEPTH),
        .ADDR_W(HBM_ADDR_W),
        .DATA_W(BUS_W),
        .ID_W(ID_W),
        .LEN_W(LEN_W),
        .INIT_FILE("")
    ) u_act_hbm (
        .clk(clk),
        .rst_n(rst_n),

        // AXI read (from activation tile_loader)
        .s_axi_arid(act_axi_arid),
        .s_axi_araddr(act_axi_araddr),
        .s_axi_arlen(act_axi_arlen),
        .s_axi_arvalid(act_axi_arvalid),
        .s_axi_arready(act_axi_arready),

        .s_axi_rid(act_axi_rid),
        .s_axi_rdata(act_axi_rdata),
        .s_axi_rresp(act_axi_rresp),
        .s_axi_rlast(act_axi_rlast),
        .s_axi_rvalid(act_axi_rvalid),
        .s_axi_rready(act_axi_rready),

        // AXI write (tied off)
        .s_axi_awid({ID_W{1'b0}}),
        .s_axi_awaddr({HBM_ADDR_W{1'b0}}),
        .s_axi_awlen({LEN_W{1'b0}}),
        .s_axi_awvalid(1'b0),
        .s_axi_awready(),

        .s_axi_wdata({BUS_W{1'b0}}),
        .s_axi_wlast(1'b0),
        .s_axi_wvalid(1'b0),
        .s_axi_wready(),

        .s_axi_bid(),
        .s_axi_bresp(),
        .s_axi_bvalid(),
        .s_axi_bready(1'b0)
    );

    // =========================================================================
    // URAM Accumulation Buffer
    // =========================================================================
    uram_accum_buf #(
        .ROWS(URAM_ROWS),
        .COLS(URAM_COLS),
        .DATA_W(DATA_W),
        .BUS_W(BUS_W),
        .N_ENG(N_ENG),
        .ROW_W(URAM_ROW_W),
        .COL_W(URAM_COL_W)
    ) u_uram (
        .clk(clk),
        .rst_n(rst_n),
        .clear(1'b0),

        // Per-engine write ports
        .eng_wr_en(eng_wr_en_packed),
        .eng_wr_row(eng_wr_row_packed),
        .eng_wr_col_word(eng_wr_col_word_packed),
        .eng_wr_data(eng_wr_data_packed),
        .eng_wr_accept(eng_wr_accept_packed),

        // Non-matmul write port (unused in this test)
        .nm_wr_en(1'b0),
        .nm_wr_row({URAM_ROW_W{1'b0}}),
        .nm_wr_col_word({URAM_COL_W{1'b0}}),
        .nm_wr_data({BUS_W{1'b0}}),

        // Read port
        .rd_en(uram_rd_en),
        .rd_row(uram_rd_row),
        .rd_col_word(uram_rd_col_word),
        .rd_data(uram_rd_data),
        .rd_valid(uram_rd_valid)
    );

    // =========================================================================
    // Helper function: pack 16 INT16 values into a 256-bit word
    // =========================================================================
    // VLT does not support passing arrays to functions, so we use a task
    // that writes directly to HBM memory.

    // make_word: pack 16 signed INT16 values into a 256-bit bus word
    // Values are passed as v0..v15 (element 0 in LSBs).
    function [BUS_W-1:0] make_word;
        input signed [DATA_W-1:0] v0,  v1,  v2,  v3;
        input signed [DATA_W-1:0] v4,  v5,  v6,  v7;
        input signed [DATA_W-1:0] v8,  v9,  v10, v11;
        input signed [DATA_W-1:0] v12, v13, v14, v15;
        begin
            make_word = {v15, v14, v13, v12, v11, v10, v9, v8,
                         v7,  v6,  v5,  v4,  v3,  v2,  v1, v0};
        end
    endfunction

    // make_const_word: pack a single constant into all 16 element slots
    function [BUS_W-1:0] make_const_word;
        input signed [DATA_W-1:0] val;
        begin
            make_const_word = {16{val}};
        end
    endfunction

    // =========================================================================
    // Test state
    // =========================================================================
    integer i, j, el;
    integer pass_count, fail_count;
    integer total_pass, total_fail;
    reg signed [DATA_W-1:0] elem;
    reg signed [DATA_W-1:0] expected_val;
    reg [BUS_W-1:0] word_tmp;
    integer timeout_cnt;

    // Constant for URAM row 32 (cannot bit-select a literal in Verilog)
    localparam [URAM_ROW_W-1:0] URAM_ROW_32 = 32;

    // =========================================================================
    // Task: preload_act_hbm
    // =========================================================================
    // Loads activation matrix A into activation HBM.
    // A[i][j] = val for all i,j  (constant matrix)
    // base_addr: HBM word address where A starts
    // rows: number of rows in A
    // cols: number of columns in A
    // val: constant value for all elements
    task preload_act_hbm;
        input [HBM_ADDR_W-1:0] base_addr;
        input integer           rows;
        input integer           cols;
        input signed [DATA_W-1:0] val;

        integer r, w, addr;
        reg [BUS_W-1:0] word_val;
        integer words_per_row;
        begin
            words_per_row = cols / BUS_EL;
            word_val = make_const_word(val);
            for (r = 0; r < rows; r = r + 1) begin
                for (w = 0; w < words_per_row; w = w + 1) begin
                    addr = base_addr + r * words_per_row + w;
                    u_act_hbm.mem[addr] = word_val;
                end
            end
        end
    endtask

    // =========================================================================
    // Task: preload_wgt_hbm
    // =========================================================================
    // Loads weight matrix B into weight HBM.
    // B[k][j] = j + 1  (column index + 1)
    // base_addr: HBM word address where B starts
    // rows: number of rows in B (= K dimension)
    // cols: number of columns in B (= N dimension)
    task preload_wgt_hbm;
        input [HBM_ADDR_W-1:0] base_addr;
        input integer           rows;
        input integer           cols;

        integer r, w, e, addr;
        reg [BUS_W-1:0] word_val;
        integer words_per_row;
        integer col_idx;
        begin
            words_per_row = cols / BUS_EL;
            for (r = 0; r < rows; r = r + 1) begin
                for (w = 0; w < words_per_row; w = w + 1) begin
                    word_val = {BUS_W{1'b0}};
                    for (e = 0; e < BUS_EL; e = e + 1) begin
                        col_idx = w * BUS_EL + e;
                        // B[k][j] = j + 1
                        word_val[e*DATA_W +: DATA_W] = col_idx[DATA_W-1:0] + 1;
                    end
                    addr = base_addr + r * words_per_row + w;
                    u_wgt_hbm.mem[addr] = word_val;
                end
            end
        end
    endtask

    // =========================================================================
    // Task: verify_uram_word
    // =========================================================================
    // Reads one word from URAM and verifies each element against expected.
    // row:      URAM row index
    // col_word: URAM column word index
    // k_dim:    K dimension (for computing expected = K * (j+1))
    // base_col: column offset for this word (col_word * BUS_EL)
    task verify_uram_word;
        input [URAM_ROW_W-1:0]   row;
        input [URAM_COL_W-1:0]   col_word;
        input integer             k_dim;
        input integer             base_col;

        integer e_idx;
        reg signed [DATA_W-1:0] actual_elem;
        reg signed [DATA_W-1:0] expect_elem;
        begin
            // Issue read: hold rd_en=1 for one posedge so URAM latches it
            uram_rd_en       = 1'b1;
            uram_rd_row      = row;
            uram_rd_col_word = col_word;
            @(posedge clk); #1;
            // URAM has registered rd_en=1: rd_valid will go high next posedge
            // Keep rd_en=1 so we can sample rd_valid=1 after the next posedge
            @(posedge clk); #1;
            // Now rd_valid=1 and rd_data are valid (latched from previous cycle)
            uram_rd_en = 1'b0;
            if (!uram_rd_valid) begin
                $display("ERROR: URAM rd_valid not asserted for row=%0d col_word=%0d",
                         row, col_word);
                fail_count = fail_count + 1;
            end else begin
                for (e_idx = 0; e_idx < BUS_EL; e_idx = e_idx + 1) begin
                    actual_elem = $signed(uram_rd_data[e_idx*DATA_W +: DATA_W]);
                    // Expected C[i][j] = K * (j + 1)
                    expect_elem = k_dim * (base_col + e_idx + 1);
                    if (actual_elem == expect_elem) begin
                        pass_count = pass_count + 1;
                    end else begin
                        fail_count = fail_count + 1;
                        if (fail_count <= 20) begin
                            $display("  FAIL: URAM[row=%0d][col=%0d] = %0d, expected %0d",
                                     row, base_col + e_idx, actual_elem, expect_elem);
                        end
                    end
                end
            end
        end
    endtask

    // =========================================================================
    // Task: issue_cmd
    // =========================================================================
    // Issues a matmul command and waits for cmd_done.
    // Returns after cmd_done pulse.
    task issue_cmd;
        input [2:0]              op;
        input [DIM_W-1:0]        m_dim, k_dim, n_dim;
        input [HBM_ADDR_W-1:0]  a_base, b_base;
        input [HBM_ADDR_W-1:0]  a_stride, b_stride;
        input [URAM_ROW_W-1:0]  out_row;
        input [URAM_COL_W-1:0]  out_col;
        begin
            // Wait until controller is ready
            while (!cmd_ready) @(posedge clk);
            #1;

            cmd_valid       = 1'b1;
            cmd_op          = op;
            cmd_m           = m_dim;
            cmd_k           = k_dim;
            cmd_n           = n_dim;
            cmd_a_base      = a_base;
            cmd_b_base      = b_base;
            cmd_a_stride    = a_stride;
            cmd_b_stride    = b_stride;
            cmd_out_row     = out_row;
            cmd_out_col_word = out_col;

            @(posedge clk); #1;
            cmd_valid = 1'b0;

            // Wait for cmd_done
            timeout_cnt = 0;
            while (!cmd_done) begin
                @(posedge clk); #1;
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > 50000) begin
                    $display("ERROR: cmd_done timeout after %0d cycles!", timeout_cnt);
                    $finish;
                end
            end
        end
    endtask

    // =========================================================================
    // Task: verify_uram_tile
    // =========================================================================
    // Verifies a TILE x TILE output region in URAM.
    // out_row_start: starting URAM row
    // out_col_word_start: starting URAM column word
    // k_dim: K dimension for expected value computation
    // n_dim: N dimension (number of columns to check)
    task verify_uram_tile;
        input [URAM_ROW_W-1:0] out_row_start;
        input [URAM_COL_W-1:0] out_col_word_start;
        input integer           k_dim;
        input integer           n_dim;

        integer r, cw;
        integer words_per_tile_row;
        integer base_col;
        begin
            words_per_tile_row = n_dim / BUS_EL;
            for (r = 0; r < TILE; r = r + 1) begin
                for (cw = 0; cw < words_per_tile_row; cw = cw + 1) begin
                    base_col = cw * BUS_EL;
                    verify_uram_word(
                        out_row_start + r[URAM_ROW_W-1:0],
                        out_col_word_start + cw[URAM_COL_W-1:0],
                        k_dim,
                        base_col
                    );
                end
            end
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        $display("========================================================");
        $display("tb_matmul: matmul_controller Integration Testbench");
        $display("  TILE=%0d  DATA_W=%0d  BUS_W=%0d  BUS_EL=%0d",
                 TILE, DATA_W, BUS_W, BUS_EL);
        $display("  URAM: ROWS=%0d COLS=%0d ROW_W=%0d COL_W=%0d",
                 URAM_ROWS, URAM_COLS, URAM_ROW_W, URAM_COL_W);
        $display("========================================================");

        // Initialize all command signals
        rst_n            = 0;
        cmd_valid        = 0;
        cmd_op           = 0;
        cmd_m            = 0;
        cmd_k            = 0;
        cmd_n            = 0;
        cmd_a_base       = 0;
        cmd_b_base       = 0;
        cmd_a_stride     = 0;
        cmd_b_stride     = 0;
        cmd_out_row      = 0;
        cmd_out_col_word = 0;
        uram_rd_en       = 0;
        uram_rd_row      = 0;
        uram_rd_col_word = 0;
        total_pass       = 0;
        total_fail       = 0;
        pass_count       = 0;
        fail_count       = 0;
        timeout_cnt      = 0;

        // =====================================================================
        // Reset
        // =====================================================================
        #20;
        rst_n = 1;
        #20;

        // =====================================================================
        // TEST 1: Single-tile matmul (M=32, K=32, N=32)
        // =====================================================================
        $display("");
        $display("--- TEST 1: Single-tile matmul (M=32, K=32, N=32) ---");

        // Preload HBM memories
        // A (activation): 32x32, all 1s, at HBM base 0
        // stride = K/BUS_EL = 32/16 = 2 words per row
        preload_act_hbm(0, 32, 32, 16'd1);

        // B (weight): 32x32, B[k][j] = j+1, at HBM base 100
        preload_wgt_hbm(100, 32, 32);

        $display("  HBM preloaded: A at addr 0 (all 1s), B at addr 100 (col+1)");

        // Issue command
        pass_count = 0;
        fail_count = 0;

        issue_cmd(
            3'd0,           // OP_MATMUL
            16'd32,         // M
            16'd32,         // K
            16'd32,         // N
            28'd0,          // a_base
            28'd100,        // b_base
            28'd2,          // a_stride (32/16 = 2)
            28'd2,          // b_stride (32/16 = 2)
            {URAM_ROW_W{1'b0}},  // out_row = 0
            {URAM_COL_W{1'b0}}   // out_col_word = 0
        );

        $display("  cmd_done received. Verifying URAM output...");

        // Allow a few cycles for URAM writes to settle
        repeat(5) @(posedge clk);

        // Verify: C[i][j] = 32 * (j+1)
        verify_uram_tile(
            {URAM_ROW_W{1'b0}},  // out_row_start
            {URAM_COL_W{1'b0}},  // out_col_word_start
            32,                    // k_dim
            32                     // n_dim
        );

        // Print sample values
        $display("  Sample expected values: C[0][0]=%0d C[0][15]=%0d C[0][31]=%0d",
                 32*1, 32*16, 32*32);

        if (fail_count == 0) begin
            $display("  TEST 1 PASSED: %0d elements verified", pass_count);
        end else begin
            $display("  TEST 1 FAILED: %0d passed, %0d failed", pass_count, fail_count);
        end
        total_pass = total_pass + pass_count;
        total_fail = total_fail + fail_count;

        // =====================================================================
        // TEST 2: Multi-k-tile matmul (M=32, K=64, N=32)
        // =====================================================================
        $display("");
        $display("--- TEST 2: Multi-k-tile matmul (M=32, K=64, N=32) ---");

        // Preload HBM memories for K=64
        // A (activation): 32x64, all 1s, at HBM base 0
        // stride = K/BUS_EL = 64/16 = 4 words per row
        preload_act_hbm(0, 32, 64, 16'd1);

        // B (weight): 64x32, B[k][j] = j+1, at HBM base 200
        preload_wgt_hbm(200, 64, 32);

        $display("  HBM preloaded: A at addr 0 (32x64, all 1s), B at addr 200 (64x32, col+1)");

        // Write to different URAM location (row 32) to avoid overlap with test 1
        pass_count = 0;
        fail_count = 0;

        issue_cmd(
            3'd0,           // OP_MATMUL
            16'd32,         // M
            16'd64,         // K
            16'd32,         // N
            28'd0,          // a_base
            28'd200,        // b_base
            28'd4,          // a_stride (64/16 = 4)
            28'd2,          // b_stride (32/16 = 2)
            URAM_ROW_32,        // out_row = 32
            {URAM_COL_W{1'b0}}  // out_col_word = 0
        );

        $display("  cmd_done received. Verifying URAM output...");

        // Allow a few cycles for URAM writes to settle
        repeat(5) @(posedge clk);

        // Verify: C[i][j] = 64 * (j+1), starting at URAM row 32
        verify_uram_tile(
            URAM_ROW_32,          // out_row_start = 32
            {URAM_COL_W{1'b0}},   // out_col_word_start
            64,                     // k_dim
            32                      // n_dim
        );

        // Print sample values
        $display("  Sample expected values: C[0][0]=%0d C[0][15]=%0d C[0][31]=%0d",
                 64*1, 64*16, 64*32);

        if (fail_count == 0) begin
            $display("  TEST 2 PASSED: %0d elements verified", pass_count);
        end else begin
            $display("  TEST 2 FAILED: %0d passed, %0d failed", pass_count, fail_count);
        end
        total_pass = total_pass + pass_count;
        total_fail = total_fail + fail_count;

        // =====================================================================
        // Summary
        // =====================================================================
        $display("");
        $display("========================================================");
        if (total_fail == 0) begin
            $display("=== ALL TESTS PASSED ===");
            $display("  Total elements verified: %0d", total_pass);
        end else begin
            $display("=== TESTS FAILED ===");
            $display("  Total passed: %0d  Total failed: %0d", total_pass, total_fail);
        end
        $display("========================================================");

        #100;
        $finish;
    end

    // =========================================================================
    // Watchdog timeout
    // =========================================================================
    initial begin
        #5000000;
        $display("ERROR: Testbench watchdog timeout (500000 ns / 50000 cycles)!");
        $finish;
    end

endmodule
