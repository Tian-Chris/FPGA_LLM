`timescale 1ns / 1ps

// =============================================================================
// tb_cosim_fp16_compare.v — FP16 Comparator Co-Simulation Testbench
// =============================================================================
// Combinational module — no clock needed.

module tb_cosim_fp16_compare;

    parameter NUM_TESTS = 256;

    reg  [15:0] a_in, b_in;
    wire [15:0] max_out, min_out;
    wire        a_gt_b;

    reg [15:0] test_a [0:NUM_TESTS-1];
    reg [15:0] test_b [0:NUM_TESTS-1];
    reg [15:0] max_results [0:NUM_TESTS-1];
    reg [15:0] min_results [0:NUM_TESTS-1];

    integer i, fd;

    fp16_compare dut (
        .a_in(a_in), .b_in(b_in),
        .max_out(max_out), .min_out(min_out),
        .a_gt_b(a_gt_b)
    );

    initial begin
        $readmemh("verify/test_data/fp16_cmp_a.hex", test_a);
        $readmemh("verify/test_data/fp16_cmp_b.hex", test_b);

        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            a_in = test_a[i];
            b_in = test_b[i];
            #1;
            max_results[i] = max_out;
            min_results[i] = min_out;
        end

        fd = $fopen("verify/test_data/fp16_cmp_max_out.hex", "w");
        for (i = 0; i < NUM_TESTS; i = i + 1)
            $fwrite(fd, "%04x\n", max_results[i]);
        $fclose(fd);

        fd = $fopen("verify/test_data/fp16_cmp_min_out.hex", "w");
        for (i = 0; i < NUM_TESTS; i = i + 1)
            $fwrite(fd, "%04x\n", min_results[i]);
        $fclose(fd);

        $display("tb_cosim_fp16_compare: wrote %0d results", NUM_TESTS);
        $finish;
    end

endmodule
