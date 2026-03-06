`timescale 1ns/1ps

`include "defines.vh"

module tb_agu;

    // Parameters
    parameter ADDR_W = 16;
    parameter DIM_W = 16;
    parameter TILE_W = 2;

    // Clock and reset
    reg clk;
    reg rst_n;

    // Control signals
    reg start;
    reg [2:0] op_type;
    wire busy;
    wire done;

    // Dimension inputs
    reg [DIM_W-1:0] dim_m;
    reg [DIM_W-1:0] dim_k;
    reg [DIM_W-1:0] dim_n;

    // Base addresses
    reg [ADDR_W-1:0] base_a;
    reg [ADDR_W-1:0] base_b;
    reg [ADDR_W-1:0] base_c;

    // Strides
    reg [DIM_W-1:0] stride_a;
    reg [DIM_W-1:0] stride_b;
    reg [DIM_W-1:0] stride_c;

    // Address outputs
    wire addr_valid;
    wire [ADDR_W-1:0] addr_a;
    wire [ADDR_W-1:0] addr_b;
    wire [ADDR_W-1:0] addr_c;
    wire is_write;

    // Tile outputs
    wire [TILE_W-1:0] tile_row;
    wire [TILE_W-1:0] tile_col;
    wire tile_start;
    wire tile_done;
    wire [DIM_W-1:0] k_idx;

    // Instantiate DUT
    agu #(
        .ADDR_W(ADDR_W),
        .DIM_W(DIM_W),
        .TILE_W(TILE_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .op_type(op_type),
        .busy(busy),
        .done(done),
        .dim_m(dim_m),
        .dim_k(dim_k),
        .dim_n(dim_n),
        .base_a(base_a),
        .base_b(base_b),
        .base_c(base_c),
        .stride_a(stride_a),
        .stride_b(stride_b),
        .stride_c(stride_c),
        .addr_valid(addr_valid),
        .addr_a(addr_a),
        .addr_b(addr_b),
        .addr_c(addr_c),
        .is_write(is_write),
        .tile_row(tile_row),
        .tile_col(tile_col),
        .tile_start(tile_start),
        .tile_done(tile_done),
        .k_idx(k_idx)
    );

    // Clock generation
    initial begin
        clk = 0;
    end

    always #5 clk = ~clk;

    // VCD dump
    initial begin
        $dumpfile("scripts/wave.vcd");
        $dumpvars(0, tb_agu);
    end

    // Counter for valid addresses
    integer addr_count;

    // Monitor address generation
    always @(posedge clk) begin
        if (addr_valid) begin
            addr_count = addr_count + 1;
            $display("Time %0t: addr_valid=1, addr_a=0x%h, addr_b=0x%h, addr_c=0x%h, tile_row=%0d, tile_col=%0d, k_idx=%0d, is_write=%0d",
                     $time, addr_a, addr_b, addr_c, tile_row, tile_col, k_idx, is_write);
        end

        if (tile_start) begin
            $display("Time %0t: tile_start asserted, tile_row=%0d, tile_col=%0d", $time, tile_row, tile_col);
        end

        if (tile_done) begin
            $display("Time %0t: tile_done asserted", $time);
        end
    end

    // Test sequence
    initial begin
        // Initialize signals
        rst_n = 0;
        start = 0;
        op_type = 3'b0;
        dim_m = 0;
        dim_k = 0;
        dim_n = 0;
        base_a = 0;
        base_b = 0;
        base_c = 0;
        stride_a = 0;
        stride_b = 0;
        stride_c = 0;
        addr_count = 0;

        $display("=== AGU Testbench Start ===");

        // Reset sequence
        #20;
        rst_n = 1;
        #10;

        $display("Time %0t: Reset complete", $time);

        // Configure for small matmul: 4x4 * 4x4 = 4x4
        dim_m = 16'd4;
        dim_k = 16'd4;
        dim_n = 16'd4;

        // Set base addresses
        base_a = 16'h1000;
        base_b = 16'h2000;
        base_c = 16'h3000;

        // Set strides (row-major: stride = number of columns)
        stride_a = 16'd4;  // A is 4x4, stride = 4
        stride_b = 16'd4;  // B is 4x4, stride = 4
        stride_c = 16'd4;  // C is 4x4, stride = 4

        // Start matmul operation
        op_type = 3'd0; // OP_MATMUL

        $display("Time %0t: Starting MATMUL operation (dim_m=%0d, dim_k=%0d, dim_n=%0d)", $time, dim_m, dim_k, dim_n);
        $display("         base_a=0x%h, base_b=0x%h, base_c=0x%h", base_a, base_b, base_c);

        #10;
        start = 1;
        #10;
        start = 0;

        // Wait for busy to assert
        wait(busy == 1);
        $display("Time %0t: AGU is busy", $time);

        // Wait for operation to complete
        wait(done == 1);
        $display("Time %0t: AGU operation done", $time);
        $display("         Total addresses generated: %0d", addr_count);

        // Wait a few more cycles
        #100;

        // Check results
        if (addr_count > 0) begin
            $display("=== TEST PASSED ===");
            $display("AGU generated %0d valid addresses", addr_count);
        end else begin
            $display("=== TEST FAILED ===");
            $display("No addresses were generated!");
        end

        $display("=== AGU Testbench Complete ===");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule
