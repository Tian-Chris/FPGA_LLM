`timescale 1ns / 1ps

module tb_mac_unit;

    parameter DATA_W = 16;
    parameter ACC_W  = 32;

    reg  clk, rst_n;
    reg  clear, enable;
    reg  signed [DATA_W-1:0] a_in, b_in;
    wire signed [ACC_W-1:0]  acc_out;

    integer pass_count, fail_count;

    initial clk = 0;
    always #5 clk = ~clk;

    mac_unit #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .clear(clear), .enable(enable),
        .a_in(a_in), .b_in(b_in),
        .acc_out(acc_out)
    );

    task check(input signed [ACC_W-1:0] expected, input [255:0] test_name);
        begin
            if (acc_out === expected) begin
                $display("PASS %0s: acc_out = %0d (expected %0d)", test_name, acc_out, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL %0s: acc_out = %0d (expected %0d)", test_name, acc_out, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Drive one MAC cycle (enable for 1 clock, then wait pipeline: 3 clocks)
    task mac_one(input signed [DATA_W-1:0] a, input signed [DATA_W-1:0] b);
        begin
            @(posedge clk);
            a_in = a; b_in = b; enable = 1;
            @(posedge clk);
            enable = 0; a_in = 0; b_in = 0;
            // Wait 3 more clocks for pipeline to flush (total 3 stages)
            @(posedge clk);
            @(posedge clk);
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0; clear = 0; enable = 0;
        a_in = 0; b_in = 0;
        #20; rst_n = 1; #10;

        // =================================================================
        // Test 1: Accumulate 4 products
        // 3*5 + 7*(-2) + 10*10 + (-4)*8 = 15 + (-14) + 100 + (-32) = 69
        // =================================================================
        // Clear accumulator first
        @(posedge clk); clear = 1;
        @(posedge clk); clear = 0;
        repeat(3) @(posedge clk); // flush pipeline

        mac_one(16'sd3, 16'sd5);
        mac_one(16'sd7, -16'sd2);
        mac_one(16'sd10, 16'sd10);
        mac_one(-16'sd4, 16'sd8);
        // Wait extra cycle for last accumulate
        @(posedge clk);

        check(32'sd69, "accumulate_4_products");

        // =================================================================
        // Test 2: Clear mid-stream
        // Accumulate 2*3=6, then clear, then 5*5=25
        // =================================================================
        @(posedge clk); clear = 1;
        @(posedge clk); clear = 0;
        repeat(3) @(posedge clk);

        mac_one(16'sd2, 16'sd3);
        @(posedge clk);

        // Clear
        @(posedge clk); clear = 1;
        @(posedge clk); clear = 0;
        repeat(3) @(posedge clk);

        mac_one(16'sd5, 16'sd5);
        @(posedge clk);

        check(32'sd25, "clear_mid_stream");

        // =================================================================
        // Test 3: Negative values (signed multiply)
        // (-100)*(-200) = 20000
        // =================================================================
        @(posedge clk); clear = 1;
        @(posedge clk); clear = 0;
        repeat(3) @(posedge clk);

        mac_one(-16'sd100, -16'sd200);
        @(posedge clk);

        check(32'sd20000, "negative_multiply");

        // =================================================================
        // Test 4: Large values near INT16 boundary
        // 32767 * 32767 = 1073676289
        // =================================================================
        @(posedge clk); clear = 1;
        @(posedge clk); clear = 0;
        repeat(3) @(posedge clk);

        mac_one(16'sd32767, 16'sd32767);
        @(posedge clk);

        check(32'sd1073676289, "large_positive");

        // =================================================================
        // Summary
        // =================================================================
        #20;
        $display("\n=== MAC Unit Test Summary ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

    initial begin
        #200000;
        $display("ERROR: tb_mac_unit timeout");
        $finish;
    end

endmodule
