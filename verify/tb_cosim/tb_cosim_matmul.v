`timescale 1ns / 1ps
`include "defines.vh"

// =============================================================================
// tb_cosim_matmul.v — 32x32 FP16 Matmul Engine Co-Simulation Testbench
// =============================================================================
// Protocol:
//   1. Assert start for 1 cycle
//   2. Assert tile_start for 1 cycle
//   3. Load A: 32 rows x 2 bus reads per row (a_valid)
//   4. Load B: 32 k-steps x 2 bus reads per step (b_valid), MAC fires after each pair
//   5. Assert tile_done for 1 cycle
//   6. Capture 64 output cycles (32 rows x 2 sub-cols)
//   7. Write to matmul_out.hex
// =============================================================================

module tb_cosim_matmul;

    parameter TILE   = 32;
    parameter DATA_W = 16;
    parameter ACC_W  = 32;
    parameter OUT_W  = 16;
    parameter BUS_W  = 256;
    parameter BUS_EL = BUS_W / DATA_W;  // 16
    parameter K_DIM  = 32;

    reg clk, rst_n;
    reg start;
    reg [2:0] op_type;
    wire busy, done;

    reg a_valid;
    reg [BUS_W-1:0] a_data;
    reg b_valid;
    reg [BUS_W-1:0] b_data;

    reg tile_start, tile_done;
    reg [4:0] tile_row, tile_col;
    reg first_tile;

    wire out_valid;
    wire [BUS_W-1:0] out_data;
    wire [4:0] out_row, out_col;
    wire compute_done;

    // Test data: flat arrays (FP16 bit patterns, unsigned)
    reg [DATA_W-1:0] mat_a [0:TILE*K_DIM-1];
    reg [DATA_W-1:0] mat_b [0:K_DIM*TILE-1];
    // Output: TILE*TILE = 1024 elements (FP16 bit patterns)
    reg [OUT_W-1:0]  result [0:TILE*TILE-1];

    integer i, j, k, fd, out_cnt;

    initial clk = 0;
    always #5 clk = ~clk;

    matmul_engine #(
        .TILE(TILE),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .OUT_W(OUT_W),
        .BUS_W(BUS_W),
        .BUS_EL(BUS_EL)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .op_type(op_type),
        .busy(busy), .done(done),
        .a_valid(a_valid), .a_data(a_data),
        .b_valid(b_valid), .b_data(b_data),
        .tile_start(tile_start), .tile_done(tile_done),
        .tile_row(tile_row), .tile_col(tile_col),
        .first_tile(first_tile),
        .tile_k_limit(TILE - 1),  // Full TILE for cosim (k=TILE=32)
        .out_valid(out_valid), .out_data(out_data),
        .out_row(out_row), .out_col(out_col),
        .out_stall(1'b0),
        .compute_done(compute_done)
    );

    initial begin
        // Load input matrices from hex files (FP16 bit patterns)
        $readmemh("verify/test_data/matmul_a.hex", mat_a);
        $readmemh("verify/test_data/matmul_b.hex", mat_b);

        rst_n = 0; start = 0; op_type = 0;
        a_valid = 0; a_data = 0;
        b_valid = 0; b_data = 0;
        tile_start = 0; tile_done = 0;
        tile_row = 0; tile_col = 0; first_tile = 0;
        out_cnt = 0;

        // Initialize result
        for (i = 0; i < TILE*TILE; i = i + 1)
            result[i] = 0;

        #20; rst_n = 1; #20;

        // ---- Start engine ----
        start = 1; op_type = 3'b000;
        @(posedge clk); #1;
        start = 0;
        @(posedge clk); #1;

        // ---- Tile start ----
        tile_start = 1; tile_row = 0; tile_col = 0; first_tile = 1;
        @(posedge clk); #1;
        tile_start = 0;
        @(posedge clk); #1;

        // ---- Load A matrix: 32 rows x 2 bus reads ----
        for (i = 0; i < TILE; i = i + 1) begin
            // First half: elements [0:15]
            a_valid = 1;
            for (j = 0; j < BUS_EL; j = j + 1)
                a_data[j*DATA_W +: DATA_W] = mat_a[i*K_DIM + j];
            @(posedge clk); #1;

            // Second half: elements [16:31]
            for (j = 0; j < BUS_EL; j = j + 1)
                a_data[j*DATA_W +: DATA_W] = mat_a[i*K_DIM + BUS_EL + j];
            @(posedge clk); #1;
        end
        a_valid = 0; a_data = 0;
        @(posedge clk); #1;

        // ---- Load B & compute: 32 k-steps x 2 bus reads ----
        for (k = 0; k < K_DIM; k = k + 1) begin
            // First half: elements [0:15]
            b_valid = 1;
            for (j = 0; j < BUS_EL; j = j + 1)
                b_data[j*DATA_W +: DATA_W] = mat_b[k*TILE + j];
            @(posedge clk); #1;

            // Second half: elements [16:31]
            for (j = 0; j < BUS_EL; j = j + 1)
                b_data[j*DATA_W +: DATA_W] = mat_b[k*TILE + BUS_EL + j];
            @(posedge clk); #1;
        end
        b_valid = 0; b_data = 0;
        first_tile = 0;

        // Wait for engine compute phase to finish
        @(posedge compute_done);
        @(posedge clk); #1;

        // ---- Tile done ----
        tile_done = 1;
        @(posedge clk); #1;
        tile_done = 0;

        // ---- Capture output: 64 cycles (32 rows x 2 sub-cols) ----
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk); #1;
            if (out_valid) begin
                for (j = 0; j < BUS_EL; j = j + 1) begin
                    result[out_row * TILE + (out_cnt & 1) * BUS_EL + j] =
                        out_data[j*OUT_W +: OUT_W];
                end
                out_cnt = out_cnt + 1;
            end
            if (done) begin
                i = 200;
            end
        end

        // ---- Write output (FP16 bit patterns) ----
        fd = $fopen("verify/test_data/matmul_out.hex", "w");
        for (i = 0; i < TILE * TILE; i = i + 1)
            $fwrite(fd, "%04x\n", result[i][15:0]);
        $fclose(fd);

        $display("tb_cosim_matmul: wrote %0d output elements", TILE*TILE);
        $finish;
    end

    initial begin
        #2000000;
        $display("ERROR: tb_cosim_matmul timeout");
        $finish;
    end

endmodule
