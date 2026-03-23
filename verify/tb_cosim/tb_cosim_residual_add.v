`timescale 1ns / 1ps
`include "defines.vh"

module tb_cosim_residual_add;

    parameter DATA_WIDTH = 16;
    parameter DIM_WIDTH  = 16;
    parameter DIM        = 16;
    parameter MAX_DIM    = 256;

    reg clk, rst_n;
    reg start;
    reg [DIM_WIDTH-1:0] dim_in;
    wire done_w, busy;

    wire res_rd_en;
    wire [DIM_WIDTH-1:0] res_rd_addr;
    reg [DATA_WIDTH-1:0] res_rd_data;
    reg res_rd_valid;

    wire sub_rd_en;
    wire [DIM_WIDTH-1:0] sub_rd_addr;
    reg [DATA_WIDTH-1:0] sub_rd_data;
    reg sub_rd_valid;

    wire out_wr_en;
    wire [DIM_WIDTH-1:0] out_wr_addr;
    wire [DATA_WIDTH-1:0] out_wr_data;

    // Memory models
    reg [DATA_WIDTH-1:0] res_mem [0:MAX_DIM-1];
    reg [DATA_WIDTH-1:0] sub_mem [0:MAX_DIM-1];
    reg [DATA_WIDTH-1:0] output_mem [0:MAX_DIM-1];

    integer i, fd;

    initial clk = 0;
    always #5 clk = ~clk;

    residual_add #(
        .DATA_WIDTH(DATA_WIDTH),
        .DIM_WIDTH(DIM_WIDTH),
        .MAX_DIM(MAX_DIM)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .dim(dim_in),
        .done(done_w), .busy(busy),
        .res_rd_en(res_rd_en), .res_rd_addr(res_rd_addr),
        .res_rd_data(res_rd_data), .res_rd_valid(res_rd_valid),
        .sub_rd_en(sub_rd_en), .sub_rd_addr(sub_rd_addr),
        .sub_rd_data(sub_rd_data), .sub_rd_valid(sub_rd_valid),
        .out_wr_en(out_wr_en), .out_wr_addr(out_wr_addr),
        .out_wr_data(out_wr_data)
    );

    // Residual memory read (1-cycle latency)
    always @(posedge clk) begin
        res_rd_valid <= res_rd_en;
        if (res_rd_en)
            res_rd_data <= res_mem[res_rd_addr];
    end

    // Sublayer memory read (1-cycle latency)
    always @(posedge clk) begin
        sub_rd_valid <= sub_rd_en;
        if (sub_rd_en)
            sub_rd_data <= sub_mem[sub_rd_addr];
    end

    // Capture writes
    always @(posedge clk) begin
        if (out_wr_en)
            output_mem[out_wr_addr] <= out_wr_data;
    end

    initial begin
        $readmemh("verify/test_data/residual_res.hex", res_mem);
        $readmemh("verify/test_data/residual_sub.hex", sub_mem);
        for (i = 0; i < MAX_DIM; i = i + 1)
            output_mem[i] = 0;

        rst_n = 0; start = 0; dim_in = DIM;
        res_rd_data = 0; res_rd_valid = 0;
        sub_rd_data = 0; sub_rd_valid = 0;

        #20; rst_n = 1; #20;

        start = 1; #10; start = 0;

        for (i = 0; i < 10000; i = i + 1) begin
            if (done_w) i = 10000;
            #10;
        end

        #20;

        fd = $fopen("verify/test_data/residual_out.hex", "w");
        for (i = 0; i < DIM; i = i + 1)
            $fwrite(fd, "%04x\n", output_mem[i][15:0]);
        $fclose(fd);

        $finish;
    end

    initial begin
        #500000;
        $display("ERROR: tb_cosim_residual_add timeout");
        $finish;
    end

endmodule
