`timescale 1ns / 1ps

// =============================================================================
// tb_cosim_fp16_mult.v — FP16 Multiplier Co-Simulation Testbench
// =============================================================================

module tb_cosim_fp16_mult;

    parameter NUM_TESTS = 256;

    reg clk, rst_n;
    reg in_valid;
    reg [15:0] a_in, b_in;
    wire out_valid;
    wire [31:0] result;

    reg [15:0] test_a [0:NUM_TESTS-1];
    reg [15:0] test_b [0:NUM_TESTS-1];
    reg [31:0] results [0:NUM_TESTS-1];

    integer i, out_idx, fd;

    initial clk = 0;
    always #5 clk = ~clk;

    fp16_mult dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid),
        .a_in(a_in), .b_in(b_in),
        .out_valid(out_valid),
        .result(result)
    );

    initial begin
        $readmemh("verify/test_data/fp16_mult_a.hex", test_a);
        $readmemh("verify/test_data/fp16_mult_b.hex", test_b);

        rst_n = 0; in_valid = 0; a_in = 0; b_in = 0; out_idx = 0;
        #20; rst_n = 1; #10;

        // Feed all test vectors
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            @(posedge clk); #1;
            in_valid = 1;
            a_in = test_a[i];
            b_in = test_b[i];
        end
        @(posedge clk); #1;
        in_valid = 0;

        // Wait for pipeline to drain (2-stage)
        repeat (10) @(posedge clk);
    end

    // Capture outputs
    always @(posedge clk) begin
        if (out_valid && out_idx < NUM_TESTS) begin
            results[out_idx] <= result;
            out_idx <= out_idx + 1;
        end
    end

    // Write output file when done
    initial begin
        #100;  // Wait for pipeline start
        wait (out_idx >= NUM_TESTS || $time > 500000);
        @(posedge clk); @(posedge clk);

        fd = $fopen("verify/test_data/fp16_mult_out.hex", "w");
        for (i = 0; i < NUM_TESTS; i = i + 1)
            $fwrite(fd, "%08x\n", results[i]);
        $fclose(fd);

        $display("tb_cosim_fp16_mult: wrote %0d results", NUM_TESTS);
        $finish;
    end

    initial begin
        #1000000;
        $display("ERROR: tb_cosim_fp16_mult timeout");
        $finish;
    end

endmodule
