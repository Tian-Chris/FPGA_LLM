// =============================================================================
// tb_uram_accum_buf.v — Testbench for URAM accumulation buffer
// =============================================================================
// Tests:
//   1. Multi-engine writes to non-overlapping columns
//   2. Flush readback verifies correct data
//   3. Clear zeroes the buffer
// =============================================================================

`include "defines.vh"

module tb_uram_accum_buf;

    parameter ROWS   = 64;    // Small for sim
    parameter COLS   = 64;
    parameter DATA_W = 16;
    parameter BUS_W  = 256;
    parameter N_ENG  = 6;
    parameter BUS_EL = BUS_W / DATA_W;           // 16
    parameter WORDS  = COLS / BUS_EL;             // 4
    parameter ROW_W  = $clog2(ROWS);              // 6
    parameter COL_W  = $clog2(WORDS);             // 2

    reg clk, rst_n;
    reg clear;

    reg  [N_ENG-1:0]         eng_wr_en;
    reg  [ROW_W*N_ENG-1:0]   eng_wr_row;
    reg  [COL_W*N_ENG-1:0]   eng_wr_col_word;
    reg  [BUS_W*N_ENG-1:0]   eng_wr_data;
    wire [N_ENG-1:0]         eng_wr_accept;

    reg                  rd_en;
    reg  [ROW_W-1:0]     rd_row;
    reg  [COL_W-1:0]     rd_col_word;
    wire [BUS_W-1:0]     rd_data;
    wire                 rd_valid;

    uram_accum_buf #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_W(DATA_W),
        .BUS_W(BUS_W),
        .N_ENG(N_ENG)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .eng_wr_en(eng_wr_en),
        .eng_wr_row(eng_wr_row),
        .eng_wr_col_word(eng_wr_col_word),
        .eng_wr_data(eng_wr_data),
        .eng_wr_accept(eng_wr_accept),
        .nm_wr_en(1'b0),
        .nm_wr_row({ROW_W{1'b0}}),
        .nm_wr_col_word({COL_W{1'b0}}),
        .nm_wr_data({BUS_W{1'b0}}),
        .rd_en(rd_en),
        .rd_row(rd_row),
        .rd_col_word(rd_col_word),
        .rd_data(rd_data),
        .rd_valid(rd_valid)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;
    integer i, eng, row, col;
    reg [BUS_W-1:0] expected;

    // Helper task: write one word from one engine
    task write_word;
        input integer eng_id;
        input [ROW_W-1:0] wr_row;
        input [COL_W-1:0] wr_col;
        input [BUS_W-1:0] wr_data_val;
        begin
            eng_wr_en = (1 << eng_id);
            eng_wr_row  = {(ROW_W*N_ENG){1'b0}};
            eng_wr_col_word = {(COL_W*N_ENG){1'b0}};
            eng_wr_data = {(BUS_W*N_ENG){1'b0}};
            eng_wr_row[eng_id*ROW_W +: ROW_W] = wr_row;
            eng_wr_col_word[eng_id*COL_W +: COL_W] = wr_col;
            eng_wr_data[eng_id*BUS_W +: BUS_W] = wr_data_val;
            @(posedge clk);
            eng_wr_en = 0;
        end
    endtask

    // Helper task: read one word
    task read_word;
        input [ROW_W-1:0] r_row;
        input [COL_W-1:0] r_col;
        begin
            rd_en       = 1'b1;
            rd_row      = r_row;
            rd_col_word = r_col;
            @(posedge clk);
            rd_en = 1'b0;
            @(posedge clk);  // Wait for rd_valid
        end
    endtask

    // Build a pattern word from base value
    function [BUS_W-1:0] make_pattern;
        input integer base;
        integer k;
        begin
            make_pattern = {BUS_W{1'b0}};
            for (k = 0; k < BUS_EL; k = k + 1)
                make_pattern[k*DATA_W +: DATA_W] = base + k;
        end
    endfunction

    initial begin
        $display("=== tb_uram_accum_buf ===");
        errors  = 0;
        rst_n   = 0;
        clear   = 0;
        eng_wr_en       = 0;
        eng_wr_row      = 0;
        eng_wr_col_word = 0;
        eng_wr_data     = 0;
        rd_en           = 0;
        rd_row          = 0;
        rd_col_word     = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // -----------------------------------------------------------------
        // Test 1: Multi-engine writes to non-overlapping columns
        // -----------------------------------------------------------------
        $display("Test 1: Multi-engine writes");
        // Engine 0 writes row 0, col_word 0
        // Engine 1 writes row 0, col_word 1
        // Engine 2 writes row 1, col_word 0
        // Engine 3 writes row 1, col_word 1
        write_word(0, 0, 0, make_pattern(100));
        write_word(1, 0, 1, make_pattern(200));
        write_word(2, 1, 0, make_pattern(300));
        write_word(3, 1, 1, make_pattern(400));

        // Readback
        read_word(0, 0);
        expected = make_pattern(100);
        if (rd_data !== expected) begin
            $display("FAIL: row=0 col=0 got %h exp %h", rd_data, expected);
            errors = errors + 1;
        end

        read_word(0, 1);
        expected = make_pattern(200);
        if (rd_data !== expected) begin
            $display("FAIL: row=0 col=1 got %h exp %h", rd_data, expected);
            errors = errors + 1;
        end

        read_word(1, 0);
        expected = make_pattern(300);
        if (rd_data !== expected) begin
            $display("FAIL: row=1 col=0 got %h exp %h", rd_data, expected);
            errors = errors + 1;
        end

        read_word(1, 1);
        expected = make_pattern(400);
        if (rd_data !== expected) begin
            $display("FAIL: row=1 col=1 got %h exp %h", rd_data, expected);
            errors = errors + 1;
        end

        // -----------------------------------------------------------------
        // Test 2: Simultaneous writes from multiple engines (same cycle)
        // -----------------------------------------------------------------
        $display("Test 2: Simultaneous multi-engine write");
        eng_wr_en = 6'b000011;  // Engines 0 and 1 simultaneously
        // Engine 0: row 5, col 0
        eng_wr_row[0*ROW_W +: ROW_W] = 5;
        eng_wr_col_word[0*COL_W +: COL_W] = 0;
        eng_wr_data[0*BUS_W +: BUS_W] = make_pattern(500);
        // Engine 1: row 5, col 1 (different column — no conflict)
        eng_wr_row[1*ROW_W +: ROW_W] = 5;
        eng_wr_col_word[1*COL_W +: COL_W] = 1;
        eng_wr_data[1*BUS_W +: BUS_W] = make_pattern(600);
        @(posedge clk);
        eng_wr_en = 0;

        read_word(5, 0);
        expected = make_pattern(500);
        if (rd_data !== expected) begin
            $display("FAIL: sim write eng0 got %h exp %h", rd_data, expected);
            errors = errors + 1;
        end

        read_word(5, 1);
        expected = make_pattern(600);
        if (rd_data !== expected) begin
            $display("FAIL: sim write eng1 got %h exp %h", rd_data, expected);
            errors = errors + 1;
        end

        // -----------------------------------------------------------------
        // Test 3: Clear zeroes the buffer
        // -----------------------------------------------------------------
        $display("Test 3: Clear");
        clear = 1;
        @(posedge clk);
        clear = 0;

        // Wait for clear to complete (ROWS * WORDS cycles)
        repeat (ROWS * WORDS + 10) @(posedge clk);

        read_word(0, 0);
        if (rd_data !== {BUS_W{1'b0}}) begin
            $display("FAIL: after clear row=0 col=0 not zero, got %h", rd_data);
            errors = errors + 1;
        end

        read_word(5, 0);
        if (rd_data !== {BUS_W{1'b0}}) begin
            $display("FAIL: after clear row=5 col=0 not zero, got %h", rd_data);
            errors = errors + 1;
        end

        // -----------------------------------------------------------------
        // Results
        // -----------------------------------------------------------------
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILED: %0d errors", errors);

        $finish;
    end

endmodule
