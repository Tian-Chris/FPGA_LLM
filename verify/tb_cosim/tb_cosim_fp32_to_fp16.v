`timescale 1ns / 1ps

// =============================================================================
// tb_cosim_fp32_to_fp16.v — FP32→FP16 Conversion Co-Simulation Testbench
// =============================================================================
// Combinational module — no pipeline, feed input and capture output same cycle.

module tb_cosim_fp32_to_fp16;

    parameter NUM_TESTS = 256;

    reg  [31:0] in;
    wire [15:0] out;

    reg [31:0] test_in [0:NUM_TESTS-1];
    reg [15:0] results [0:NUM_TESTS-1];

    integer i, fd;

    fp32_to_fp16 dut (
        .in(in),
        .out(out)
    );

    initial begin
        $readmemh("verify/test_data/fp32_to_fp16_in.hex", test_in);

        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            in = test_in[i];
            #1;  // Allow combinational propagation
            results[i] = out;
        end

        fd = $fopen("verify/test_data/fp32_to_fp16_out.hex", "w");
        for (i = 0; i < NUM_TESTS; i = i + 1)
            $fwrite(fd, "%04x\n", results[i]);
        $fclose(fd);

        $display("tb_cosim_fp32_to_fp16: wrote %0d results", NUM_TESTS);
        $finish;
    end

endmodule
