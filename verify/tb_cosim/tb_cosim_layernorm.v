`timescale 1ns / 1ps
`include "defines.vh"

module tb_cosim_layernorm;

    parameter DATA_W  = 16;
    parameter OUT_W   = 16;
    parameter PARAM_W = 16;   // FP16 gamma/beta
    parameter DIM_W   = 16;
    parameter DIM     = 16;
    parameter MAX_DIM = 256;

    reg clk, rst_n;
    reg start;
    reg [DIM_W-1:0] dim;
    wire busy, done_w;

    wire in_rd_en;
    wire [DIM_W-1:0] in_rd_addr;
    wire [DATA_W-1:0] in_rd_data;
    wire in_rd_valid;

    wire param_rd_en;
    wire [DIM_W-1:0] param_rd_addr;
    wire [PARAM_W-1:0] gamma_data, beta_data;
    wire param_rd_valid;

    wire out_wr_en;
    wire [DIM_W-1:0] out_wr_addr;
    wire [OUT_W-1:0] out_wr_data;

    // Memory models (FP16 bit patterns — unsigned)
    reg [DATA_W-1:0] input_mem [0:MAX_DIM-1];
    // Interleaved param memory: gamma[0], beta[0], gamma[1], beta[1], ...
    reg [PARAM_W-1:0] param_mem [0:2*MAX_DIM-1];
    reg [OUT_W-1:0] output_mem [0:MAX_DIM-1];

    integer i, fd;

    initial clk = 0;
    always #5 clk = ~clk;

    layernorm #(
        .DATA_W(DATA_W),
        .OUT_W(OUT_W),
        .PARAM_W(PARAM_W),
        .DIM_W(DIM_W),
        .MAX_DIM(MAX_DIM)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .dim(dim),
        .busy(busy), .done(done_w),
        .in_rd_en(in_rd_en), .in_rd_addr(in_rd_addr),
        .in_rd_data(in_rd_data), .in_rd_valid(in_rd_valid),
        .param_rd_en(param_rd_en), .param_rd_addr(param_rd_addr),
        .gamma_data(gamma_data), .beta_data(beta_data),
        .param_rd_valid(param_rd_valid),
        .out_wr_en(out_wr_en), .out_wr_addr(out_wr_addr),
        .out_wr_data(out_wr_data)
    );

    // 1-cycle registered memory reads (matches real hardware)
    reg in_rd_valid_r;
    reg [DATA_W-1:0] in_rd_data_r;
    reg param_rd_valid_r;
    reg [PARAM_W-1:0] param_data_r;

    always @(posedge clk) begin
        in_rd_valid_r    <= in_rd_en;
        in_rd_data_r     <= input_mem[in_rd_addr];
        param_rd_valid_r <= param_rd_en;
        param_data_r     <= param_mem[param_rd_addr];
    end

    assign in_rd_valid = in_rd_valid_r;
    assign in_rd_data  = in_rd_data_r;
    assign param_rd_valid = param_rd_valid_r;
    // Both gamma_data and beta_data come from the same interleaved memory
    assign gamma_data     = param_data_r;
    assign beta_data      = param_data_r;

    // Capture writes
    always @(posedge clk) begin
        if (out_wr_en)
            output_mem[out_wr_addr] <= out_wr_data;
    end

    initial begin
        $readmemh("verify/test_data/layernorm_in.hex", input_mem);
        $readmemh("verify/test_data/layernorm_params.hex", param_mem);
        for (i = 0; i < MAX_DIM; i = i + 1)
            output_mem[i] = 0;

        rst_n = 0; start = 0; dim = DIM;

        #20; rst_n = 1; #20;

        start = 1; #10; start = 0;

        for (i = 0; i < 50000; i = i + 1) begin
            if (done_w) i = 50000;
            #10;
        end

        #20;

        fd = $fopen("verify/test_data/layernorm_out.hex", "w");
        for (i = 0; i < DIM; i = i + 1)
            $fwrite(fd, "%04x\n", output_mem[i]);
        $fclose(fd);

        $finish;
    end

    initial begin
        #1000000;
        $display("ERROR: tb_cosim_layernorm timeout");
        $finish;
    end

endmodule
