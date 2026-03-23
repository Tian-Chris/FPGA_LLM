`timescale 1ns / 1ps
`include "defines.vh"

module tb_cosim_softmax;

    parameter DATA_W  = 16;
    parameter OUT_W   = 16;
    parameter MAX_LEN = 128;
    parameter SEQ_LEN = 8;

    reg clk, rst_n;
    reg start;
    reg [15:0] seq_len;
    wire busy, done_w;
    wire in_rd_en;
    wire [15:0] in_rd_addr;
    wire [DATA_W-1:0] in_rd_data;
    wire in_rd_valid;
    wire out_wr_en;
    wire [15:0] out_wr_addr;
    wire [OUT_W-1:0] out_wr_data;

    // Memory model (FP16 bit patterns)
    reg [DATA_W-1:0] input_mem [0:MAX_LEN-1];
    reg [OUT_W-1:0] output_mem [0:MAX_LEN-1];

    // Scale factor: 1.0 (no scaling for unit test)
    reg [15:0] scale_factor;

    integer i, fd;

    initial clk = 0;
    always #5 clk = ~clk;

    softmax #(
        .DATA_W(DATA_W),
        .OUT_W(OUT_W),
        .MAX_LEN(MAX_LEN),
        .CAUSAL(0)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .seq_len(seq_len),
        .row_idx(16'd0),
        .scale_factor(scale_factor),
        .busy(busy), .done(done_w),
        .in_rd_en(in_rd_en), .in_rd_addr(in_rd_addr),
        .in_rd_data(in_rd_data), .in_rd_valid(in_rd_valid),
        .out_wr_en(out_wr_en), .out_wr_addr(out_wr_addr),
        .out_wr_data(out_wr_data)
    );

    // Combinational memory read (0-cycle latency)
    assign in_rd_valid = in_rd_en;
    assign in_rd_data  = input_mem[in_rd_addr];

    // Capture writes
    always @(posedge clk) begin
        if (out_wr_en)
            output_mem[out_wr_addr] <= out_wr_data;
    end

    initial begin
        $readmemh("verify/test_data/softmax_in.hex", input_mem);
        for (i = 0; i < MAX_LEN; i = i + 1)
            output_mem[i] = 0;

        rst_n = 0; start = 0; seq_len = SEQ_LEN;
        scale_factor = 16'h3C00;  // 1.0 default, overridden by test data

        #20; rst_n = 1; #20;

        start = 1; #10; start = 0;

        for (i = 0; i < 10000; i = i + 1) begin
            if (done_w) i = 10000;
            #10;
        end

        #20;

        fd = $fopen("verify/test_data/softmax_out.hex", "w");
        for (i = 0; i < SEQ_LEN; i = i + 1)
            $fwrite(fd, "%04x\n", output_mem[i]);
        $fclose(fd);

        $finish;
    end

    initial begin
        #500000;
        $display("ERROR: tb_cosim_softmax timeout");
        $finish;
    end

endmodule
