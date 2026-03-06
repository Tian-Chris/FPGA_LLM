`timescale 1ns / 1ps
`include "defines.vh"

module tb_cosim_activation;

    parameter DATA_WIDTH = 16;
    parameter DIM        = 16;

    reg clk, rst_n;
    reg start;
    reg [15:0] dim_in;
    wire done_w, busy;

    wire mem_rd_en;
    wire [15:0] mem_rd_addr;
    reg [DATA_WIDTH-1:0] mem_rd_data;
    reg mem_rd_valid;

    wire mem_wr_en;
    wire [15:0] mem_wr_addr;
    wire [DATA_WIDTH-1:0] mem_wr_data;

    // Memory model
    reg signed [DATA_WIDTH-1:0] input_mem [0:255];
    reg signed [DATA_WIDTH-1:0] output_mem [0:255];

    integer i, fd;

    initial clk = 0;
    always #5 clk = ~clk;

    activation_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_DIM(256)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .dim(dim_in),
        .done(done_w), .busy(busy),
        .mem_rd_en(mem_rd_en), .mem_rd_addr(mem_rd_addr),
        .mem_rd_data(mem_rd_data), .mem_rd_valid(mem_rd_valid),
        .mem_wr_en(mem_wr_en), .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data)
    );

    // Memory read (1-cycle latency)
    always @(posedge clk) begin
        mem_rd_valid <= mem_rd_en;
        if (mem_rd_en)
            mem_rd_data <= input_mem[mem_rd_addr];
    end

    // Capture writes
    always @(posedge clk) begin
        if (mem_wr_en)
            output_mem[mem_wr_addr] <= mem_wr_data;
    end

    initial begin
        $readmemh("verify/test_data/activation_in.hex", input_mem);
        for (i = 0; i < 256; i = i + 1)
            output_mem[i] = 0;

        rst_n = 0; start = 0;
        dim_in = DIM;
        mem_rd_data = 0; mem_rd_valid = 0;

        #20; rst_n = 1; #20;

        start = 1; #10; start = 0;

        for (i = 0; i < 10000; i = i + 1) begin
            if (done_w) i = 10000;
            #10;
        end

        #20;

        fd = $fopen("verify/test_data/activation_out.hex", "w");
        for (i = 0; i < DIM; i = i + 1)
            $fwrite(fd, "%04x\n", output_mem[i][15:0]);
        $fclose(fd);

        $finish;
    end

    initial begin
        #500000;
        $display("ERROR: tb_cosim_activation timeout");
        $finish;
    end

endmodule
