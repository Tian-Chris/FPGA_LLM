// =============================================================================
// tb_uram_flush.v — Testbench for uram_flush
// =============================================================================
// Tests:
//   1. Full flush (8 rows x 4 words/row) to HBM, verify all 32 words
//   2. Partial flush (4 rows), verify 16 words only
//   3. Non-contiguous stride (stride=8, gaps in HBM), verify correct addresses
//
// NOTE: ROW_W and COL_W are sized 1 bit wider than the strict $clog2 address
// width because uram_flush interprets num_rows / num_col_words as *counts*,
// not max-indices.  E.g. WORDS_PER_ROW=4 must fit in COL_W bits.
// =============================================================================

`include "defines.vh"

module tb_uram_flush;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter BUS_W       = 256;
    parameter DATA_W      = 16;
    parameter HBM_ADDR_W  = 28;
    parameter ID_W        = 4;
    parameter LEN_W       = 8;
    parameter HBM_DEPTH   = 4096;

    // Small URAM for fast sim
    parameter ROWS   = 8;
    parameter COLS   = 64;
    parameter N_ENG  = 1;

    // Width must hold the *count* (ROWS=8, WORDS_PER_ROW=4), not just the
    // max address, so use $clog2(N)+1.
    parameter ROW_W  = 4;   // holds 0..8
    parameter COL_W  = 3;   // holds 0..4

    localparam BUS_EL        = BUS_W / DATA_W;        // 16
    localparam WORDS_PER_ROW = COLS / BUS_EL;          // 4

    // =========================================================================
    // Signals
    // =========================================================================
    reg clk, rst_n;

    // uram_flush control
    reg                     start;
    reg  [ROW_W-1:0]       num_rows;
    reg  [COL_W-1:0]       num_col_words;
    reg  [HBM_ADDR_W-1:0]  hbm_base;
    reg  [HBM_ADDR_W-1:0]  hbm_stride;
    wire                    done;

    // URAM read port (uram_flush -> uram_accum_buf)
    wire                    uram_rd_en;
    wire [ROW_W-1:0]       uram_rd_row;
    wire [COL_W-1:0]       uram_rd_col_word;
    wire [BUS_W-1:0]       uram_rd_data;
    wire                    uram_rd_valid;

    // AXI4 write channels (uram_flush -> sim_hbm_port)
    wire [ID_W-1:0]        awid;
    wire [HBM_ADDR_W-1:0]  awaddr;
    wire [LEN_W-1:0]       awlen;
    wire                    awvalid;
    wire                    awready;
    wire [BUS_W-1:0]       wdata;
    wire                    wlast;
    wire                    wvalid;
    wire                    wready;
    wire [ID_W-1:0]        bid;
    wire [1:0]             bresp;
    wire                    bvalid;
    wire                    bready;

    // uram_accum_buf write port (testbench drives)
    reg                     uram_wr_en;
    reg  [ROW_W-1:0]       uram_wr_row;
    reg  [COL_W-1:0]       uram_wr_col_word;
    reg  [BUS_W-1:0]       uram_wr_data;

    // =========================================================================
    // DUT: uram_flush
    // =========================================================================
    uram_flush #(
        .BUS_W(BUS_W), .HBM_ADDR_W(HBM_ADDR_W), .ID_W(ID_W),
        .LEN_W(LEN_W), .ROW_W(ROW_W), .COL_W(COL_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .num_rows(num_rows), .num_col_words(num_col_words),
        .hbm_base(hbm_base), .hbm_stride(hbm_stride), .done(done),
        .uram_rd_en(uram_rd_en), .uram_rd_row(uram_rd_row),
        .uram_rd_col_word(uram_rd_col_word),
        .uram_rd_data(uram_rd_data), .uram_rd_valid(uram_rd_valid),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp),
        .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    // =========================================================================
    // uram_accum_buf — data source
    // =========================================================================
    uram_accum_buf #(
        .ROWS(ROWS), .COLS(COLS), .DATA_W(DATA_W), .BUS_W(BUS_W),
        .N_ENG(N_ENG), .ROW_W(ROW_W), .COL_W(COL_W)
    ) u_uram (
        .clk(clk), .rst_n(rst_n), .clear(1'b0),
        .eng_wr_en(uram_wr_en),
        .eng_wr_row(uram_wr_row),
        .eng_wr_col_word(uram_wr_col_word),
        .eng_wr_data(uram_wr_data),
        .eng_wr_accept(),
        .nm_wr_en(1'b0), .nm_wr_row({ROW_W{1'b0}}),
        .nm_wr_col_word({COL_W{1'b0}}), .nm_wr_data({BUS_W{1'b0}}),
        .rd_en(uram_rd_en), .rd_row(uram_rd_row),
        .rd_col_word(uram_rd_col_word),
        .rd_data(uram_rd_data), .rd_valid(uram_rd_valid)
    );

    // =========================================================================
    // sim_hbm_port — HBM sink (receives AXI4 writes)
    // =========================================================================
    sim_hbm_port #(
        .DEPTH(HBM_DEPTH), .ADDR_W(HBM_ADDR_W), .DATA_W(BUS_W),
        .ID_W(ID_W), .LEN_W(LEN_W)
    ) u_hbm (
        .clk(clk), .rst_n(rst_n),
        // Read channels tied off (not used)
        .s_axi_arid({ID_W{1'b0}}), .s_axi_araddr({HBM_ADDR_W{1'b0}}),
        .s_axi_arlen({LEN_W{1'b0}}), .s_axi_arvalid(1'b0), .s_axi_arready(),
        .s_axi_rid(), .s_axi_rdata(), .s_axi_rresp(),
        .s_axi_rlast(), .s_axi_rvalid(), .s_axi_rready(1'b0),
        // Write channels connected to uram_flush
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wlast(wlast),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bid(bid), .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid), .s_axi_bready(bready)
    );

    // =========================================================================
    // Clock generation
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    integer errors, row, col, watchdog;
    reg [BUS_W-1:0] expected;
    reg [BUS_W-1:0] actual;
    reg [HBM_ADDR_W-1:0] check_addr;

    // =========================================================================
    // Helper: make_pattern — pack 16 INT16 values into 256-bit word
    // Each element = base + element_index
    // =========================================================================
    function [BUS_W-1:0] make_pattern;
        input integer base;
        integer k;
        begin
            make_pattern = {BUS_W{1'b0}};
            for (k = 0; k < BUS_EL; k = k + 1)
                make_pattern[k*DATA_W +: DATA_W] = base + k;
        end
    endfunction

    // =========================================================================
    // Helper: write one word to uram_accum_buf via engine write port
    // =========================================================================
    task write_uram;
        input [ROW_W-1:0] wr_row;
        input [COL_W-1:0] wr_col;
        input [BUS_W-1:0] wr_data;
        begin
            uram_wr_en       = 1'b1;
            uram_wr_row      = wr_row;
            uram_wr_col_word = wr_col;
            uram_wr_data     = wr_data;
            @(posedge clk);
            uram_wr_en = 1'b0;
        end
    endtask

    // =========================================================================
    // Helper: preload URAM with pattern — each word = make_pattern(row*100+col)
    // =========================================================================
    task preload_uram;
        input integer n_rows;
        input integer n_cols;
        integer r, c;
        begin
            for (r = 0; r < n_rows; r = r + 1) begin
                for (c = 0; c < n_cols; c = c + 1) begin
                    write_uram(r[ROW_W-1:0], c[COL_W-1:0],
                               make_pattern(r * 100 + c));
                end
            end
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // Helper: start flush and wait for done
    // =========================================================================
    task run_flush;
        input [ROW_W-1:0]       f_num_rows;
        input [COL_W-1:0]       f_num_col_words;
        input [HBM_ADDR_W-1:0]  f_hbm_base;
        input [HBM_ADDR_W-1:0]  f_hbm_stride;
        begin
            num_rows      = f_num_rows;
            num_col_words = f_num_col_words;
            hbm_base      = f_hbm_base;
            hbm_stride    = f_hbm_stride;
            start         = 1'b1;
            @(posedge clk);
            start = 1'b0;

            watchdog = 0;
            while (!done) begin
                @(posedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 10000) begin
                    $display("TIMEOUT: waiting for flush done, state=%0d", dut.fl_state);
                    $finish;
                end
            end
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        $display("=== tb_uram_flush ===");
        errors          = 0;
        rst_n           = 0;
        start           = 0;
        num_rows        = 0;
        num_col_words   = 0;
        hbm_base        = 0;
        hbm_stride      = 0;
        uram_wr_en      = 0;
        uram_wr_row     = 0;
        uram_wr_col_word = 0;
        uram_wr_data    = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // =============================================================
        // Test 1: Full flush (8 rows x 4 words/row = 32 words)
        //   URAM pattern: make_pattern(row*100 + col_word)
        //   HBM base=100, stride=4 (contiguous rows)
        // =============================================================
        $display("Test 1: Full flush 8 rows x 4 words, base=100, stride=4");

        preload_uram(ROWS, WORDS_PER_ROW);

        run_flush((ROWS-1), (WORDS_PER_ROW-1),
                  28'd100, 28'd4);

        // Verify all 32 words in HBM
        for (row = 0; row < ROWS; row = row + 1) begin
            for (col = 0; col < WORDS_PER_ROW; col = col + 1) begin
                check_addr = 100 + row * 4 + col;
                expected = make_pattern(row * 100 + col);
                actual   = u_hbm.mem[check_addr];
                if (actual !== expected) begin
                    $display("FAIL T1: row=%0d col=%0d hbm[%0d] got %h exp %h",
                             row, col, check_addr, actual, expected);
                    errors = errors + 1;
                end
            end
        end
        if (errors == 0) $display("  Test 1 PASSED");

        // =============================================================
        // Test 2: Partial flush (4 rows only)
        //   HBM base=200, stride=4
        // =============================================================
        $display("Test 2: Partial flush 4 rows x 4 words, base=200, stride=4");

        run_flush(3'd3, (WORDS_PER_ROW-1),
                  28'd200, 28'd4);

        // Verify 16 words (rows 0-3 only)
        for (row = 0; row < 4; row = row + 1) begin
            for (col = 0; col < WORDS_PER_ROW; col = col + 1) begin
                check_addr = 200 + row * 4 + col;
                expected = make_pattern(row * 100 + col);
                actual   = u_hbm.mem[check_addr];
                if (actual !== expected) begin
                    $display("FAIL T2: row=%0d col=%0d hbm[%0d] got %h exp %h",
                             row, col, check_addr, actual, expected);
                    errors = errors + 1;
                end
            end
        end
        if (errors == 0) $display("  Test 2 PASSED");

        // =============================================================
        // Test 3: Non-contiguous stride (stride=8, gaps in HBM)
        //   Flush all 8 rows, HBM base=400, stride=8
        //   Row 0 -> HBM [400..403], Row 1 -> HBM [408..411], etc.
        //   HBM [404..407] should remain zero (gap)
        // =============================================================
        $display("Test 3: Non-contiguous stride=8, base=400, 8 rows");

        // Clear HBM region first to detect spurious writes
        for (row = 0; row < 128; row = row + 1)
            u_hbm.mem[400 + row] = {BUS_W{1'b0}};

        run_flush((ROWS-1), (WORDS_PER_ROW-1),
                  28'd400, 28'd8);

        // Verify data at strided addresses
        for (row = 0; row < ROWS; row = row + 1) begin
            for (col = 0; col < WORDS_PER_ROW; col = col + 1) begin
                check_addr = 400 + row * 8 + col;
                expected = make_pattern(row * 100 + col);
                actual   = u_hbm.mem[check_addr];
                if (actual !== expected) begin
                    $display("FAIL T3: row=%0d col=%0d hbm[%0d] got %h exp %h",
                             row, col, check_addr, actual, expected);
                    errors = errors + 1;
                end
            end
        end

        // Verify gaps are still zero
        for (row = 0; row < ROWS; row = row + 1) begin
            for (col = WORDS_PER_ROW; col < 8; col = col + 1) begin
                check_addr = 400 + row * 8 + col;
                actual = u_hbm.mem[check_addr];
                if (actual !== {BUS_W{1'b0}}) begin
                    $display("FAIL T3 gap: row=%0d gap_offset=%0d hbm[%0d] got %h exp 0",
                             row, col, check_addr, actual);
                    errors = errors + 1;
                end
            end
        end
        if (errors == 0) $display("  Test 3 PASSED");

        // =============================================================
        // Summary
        // =============================================================
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("FAILED: %0d errors", errors);
        $finish;
    end

endmodule
