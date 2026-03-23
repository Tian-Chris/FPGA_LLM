`timescale 1ns / 1ps

// =============================================================================
// tb_cosim_fp32_add.v — FP32 Adder Co-Simulation Testbench
// =============================================================================

module tb_cosim_fp32_add;

    parameter NUM_TESTS = 256;

    reg clk, rst_n;
    reg in_valid;
    reg [31:0] a_in, b_in;
    wire out_valid;
    wire [31:0] result;

    // Use 32-bit wide memories, loaded as 8-digit hex
    reg [31:0] test_a [0:NUM_TESTS-1];
    reg [31:0] test_b [0:NUM_TESTS-1];
    reg [31:0] results [0:NUM_TESTS-1];

    integer i, out_idx, fd;

    initial clk = 0;
    always #5 clk = ~clk;

    fp32_add dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid),
        .a_in(a_in), .b_in(b_in),
        .out_valid(out_valid),
        .result(result)
    );

    initial begin
        $readmemh("verify/test_data/fp32_add_a.hex", test_a);
        $readmemh("verify/test_data/fp32_add_b.hex", test_b);

        rst_n = 0; in_valid = 0; a_in = 0; b_in = 0; out_idx = 0;
        #20; rst_n = 1; #10;

        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            @(posedge clk); #1;
            in_valid = 1;
            a_in = test_a[i];
            b_in = test_b[i];
        end
        @(posedge clk); #1;
        in_valid = 0;

        // Wait for 3-stage pipeline to drain
        repeat (10) @(posedge clk);
    end

    always @(posedge clk) begin
        if (out_valid && out_idx < NUM_TESTS) begin
            results[out_idx] <= result;
            out_idx <= out_idx + 1;
        end
    end

    initial begin
        #100;
        wait (out_idx >= NUM_TESTS || $time > 500000);
        @(posedge clk); @(posedge clk);

        fd = $fopen("verify/test_data/fp32_add_out.hex", "w");
        for (i = 0; i < NUM_TESTS; i = i + 1)
            $fwrite(fd, "%08x\n", results[i]);
        $fclose(fd);

        $display("tb_cosim_fp32_add: wrote %0d results", NUM_TESTS);
        $finish;
    end

    initial begin
        #1000000;
        $display("ERROR: tb_cosim_fp32_add timeout");
        $finish;
    end

endmodule
