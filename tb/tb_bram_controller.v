`timescale 1ns/1ps
`include "defines.vh"

module tb_bram_controller;

    // Parameters
    parameter DEPTH = 64;
    parameter DATA_W = 8;
    parameter ADDR_W = 6;
    parameter NUM_BANKS = 4;
    parameter INIT_FILE = "";

    // Testbench signals
    reg clk;
    reg rst_n;

    // Port A signals
    reg pa_en;
    reg pa_we;
    reg [ADDR_W-1:0] pa_addr;
    reg [DATA_W*NUM_BANKS-1:0] pa_wdata;
    wire [DATA_W*NUM_BANKS-1:0] pa_rdata;
    wire pa_valid;

    // Port B signals
    reg pb_en;
    reg pb_we;
    reg [ADDR_W-1:0] pb_addr;
    reg [DATA_W*NUM_BANKS-1:0] pb_wdata;
    wire [DATA_W*NUM_BANKS-1:0] pb_rdata;
    wire pb_valid;

    // Clock generation
    initial begin
        clk = 0;
    end

    always #5 clk = ~clk;

    // DUT instantiation
    bram_controller #(
        .DEPTH(DEPTH),
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .NUM_BANKS(NUM_BANKS),
        .INIT_FILE(INIT_FILE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pa_en(pa_en),
        .pa_we(pa_we),
        .pa_addr(pa_addr),
        .pa_wdata(pa_wdata),
        .pa_rdata(pa_rdata),
        .pa_valid(pa_valid),
        .pb_en(pb_en),
        .pb_we(pb_we),
        .pb_addr(pb_addr),
        .pb_wdata(pb_wdata),
        .pb_rdata(pb_rdata),
        .pb_valid(pb_valid)
    );

    // VCD dump
    initial begin
        $dumpfile("scripts/wave.vcd");
        $dumpvars(0, tb_bram_controller);
    end

    // Test variables
    reg [DATA_W*NUM_BANKS-1:0] expected_data;
    integer test_pass;

    // Test procedure
    initial begin
        // Initialize signals
        rst_n = 0;
        pa_en = 0;
        pa_we = 0;
        pa_addr = 0;
        pa_wdata = 0;
        pb_en = 0;
        pb_we = 0;
        pb_addr = 0;
        pb_wdata = 0;
        test_pass = 1;

        $display("=== BRAM Controller Testbench ===");
        $display("Parameters: DEPTH=%0d, DATA_W=%0d, ADDR_W=%0d, NUM_BANKS=%0d", DEPTH, DATA_W, ADDR_W, NUM_BANKS);

        // Test 1: Reset
        $display("\n[TEST 1] Reset Test");
        #20;
        rst_n = 1;
        #10;
        $display("Reset deasserted");

        // Test 2: Port A Write and Read Back
        $display("\n[TEST 2] Port A Write and Read Back");
        @(posedge clk);
        pa_en = 1;
        pa_we = 1;
        pa_addr = 6'h0A;
        pa_wdata = 32'hDEADBEEF;
        $display("Writing to Port A: addr=0x%02h, data=0x%08h", pa_addr, pa_wdata);

        @(posedge clk);
        pa_we = 0;

        @(posedge clk);
        if (pa_valid) begin
            $display("Port A write completed");
        end

        // Read back from Port A
        @(posedge clk);
        pa_addr = 6'h0A;
        pa_en = 1;
        pa_we = 0;
        $display("Reading from Port A: addr=0x%02h", pa_addr);

        @(posedge clk);
        @(posedge clk);
        expected_data = 32'hDEADBEEF;
        if (pa_valid && pa_rdata == expected_data) begin
            $display("PASS: Port A read data=0x%08h (expected=0x%08h)", pa_rdata, expected_data);
        end else begin
            $display("FAIL: Port A read data=0x%08h (expected=0x%08h), valid=%0b", pa_rdata, expected_data, pa_valid);
            test_pass = 0;
        end

        pa_en = 0;

        // Test 3: Port B Write and Read Back
        $display("\n[TEST 3] Port B Write and Read Back");
        @(posedge clk);
        pb_en = 1;
        pb_we = 1;
        pb_addr = 6'h15;
        pb_wdata = 32'hCAFEBABE;
        $display("Writing to Port B: addr=0x%02h, data=0x%08h", pb_addr, pb_wdata);

        @(posedge clk);
        pb_we = 0;

        @(posedge clk);
        if (pb_valid) begin
            $display("Port B write completed");
        end

        // Read back from Port B
        @(posedge clk);
        pb_addr = 6'h15;
        pb_en = 1;
        pb_we = 0;
        $display("Reading from Port B: addr=0x%02h", pb_addr);

        @(posedge clk);
        @(posedge clk);
        expected_data = 32'hCAFEBABE;
        if (pb_valid && pb_rdata == expected_data) begin
            $display("PASS: Port B read data=0x%08h (expected=0x%08h)", pb_rdata, expected_data);
        end else begin
            $display("FAIL: Port B read data=0x%08h (expected=0x%08h), valid=%0b", pb_rdata, expected_data, pb_valid);
            test_pass = 0;
        end

        pb_en = 0;

        // Test 4: Simultaneous Port A and Port B operations on different addresses
        $display("\n[TEST 4] Simultaneous Port A and Port B Write Operations");
        @(posedge clk);
        pa_en = 1;
        pa_we = 1;
        pa_addr = 6'h20;
        pa_wdata = 32'h12345678;

        pb_en = 1;
        pb_we = 1;
        pb_addr = 6'h30;
        pb_wdata = 32'h87654321;

        $display("Writing simultaneously - Port A: addr=0x%02h, data=0x%08h", pa_addr, pa_wdata);
        $display("                         Port B: addr=0x%02h, data=0x%08h", pb_addr, pb_wdata);

        @(posedge clk);
        pa_we = 0;
        pb_we = 0;

        @(posedge clk);
        @(posedge clk);

        // Simultaneous read back
        $display("\n[TEST 5] Simultaneous Port A and Port B Read Operations");
        @(posedge clk);
        pa_en = 1;
        pa_we = 0;
        pa_addr = 6'h20;

        pb_en = 1;
        pb_we = 0;
        pb_addr = 6'h30;

        $display("Reading simultaneously - Port A: addr=0x%02h", pa_addr);
        $display("                         Port B: addr=0x%02h", pb_addr);

        @(posedge clk);
        @(posedge clk);

        expected_data = 32'h12345678;
        if (pa_valid && pa_rdata == expected_data) begin
            $display("PASS: Port A simultaneous read data=0x%08h (expected=0x%08h)", pa_rdata, expected_data);
        end else begin
            $display("FAIL: Port A simultaneous read data=0x%08h (expected=0x%08h), valid=%0b", pa_rdata, expected_data, pa_valid);
            test_pass = 0;
        end

        expected_data = 32'h87654321;
        if (pb_valid && pb_rdata == expected_data) begin
            $display("PASS: Port B simultaneous read data=0x%08h (expected=0x%08h)", pb_rdata, expected_data);
        end else begin
            $display("FAIL: Port B simultaneous read data=0x%08h (expected=0x%08h), valid=%0b", pb_rdata, expected_data, pb_valid);
            test_pass = 0;
        end

        pa_en = 0;
        pb_en = 0;

        // Test 6: Cross-port verification (write on A, read on B)
        $display("\n[TEST 6] Cross-port Verification (Write Port A, Read Port B)");
        @(posedge clk);
        pa_en = 1;
        pa_we = 1;
        pa_addr = 6'h3F;
        pa_wdata = 32'hABCDEF01;
        $display("Writing to Port A: addr=0x%02h, data=0x%08h", pa_addr, pa_wdata);

        @(posedge clk);
        pa_we = 0;
        pa_en = 0;

        @(posedge clk);
        @(posedge clk);

        // Read from Port B
        pb_en = 1;
        pb_we = 0;
        pb_addr = 6'h3F;
        $display("Reading from Port B: addr=0x%02h", pb_addr);

        @(posedge clk);
        @(posedge clk);

        expected_data = 32'hABCDEF01;
        if (pb_valid && pb_rdata == expected_data) begin
            $display("PASS: Port B read (after Port A write) data=0x%08h (expected=0x%08h)", pb_rdata, expected_data);
        end else begin
            $display("FAIL: Port B read (after Port A write) data=0x%08h (expected=0x%08h), valid=%0b", pb_rdata, expected_data, pb_valid);
            test_pass = 0;
        end

        pb_en = 0;

        // Final results
        $display("\n=== Test Complete ===");
        if (test_pass) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SOME TESTS FAILED");
        end

        #50;
        $finish;
    end

endmodule
