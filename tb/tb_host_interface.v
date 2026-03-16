// =============================================================================
// tb_host_interface.v - Testbench for AXI-Lite Host Interface
// =============================================================================
//
// Description:
//   Testbench (compatible with verilator) for the host_interface module.
//   Tests AXI-Lite write/read transactions, control register operations,
//   and status monitoring.
//
// =============================================================================

`timescale 1ns/1ps

`include "defines.vh"

module tb_host_interface;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter AXI_ADDR_WIDTH    = 32;
    parameter AXI_DATA_WIDTH    = 32;
    parameter WEIGHT_ADDR_WIDTH = 20;
    parameter WEIGHT_DATA_WIDTH = 128;
    parameter DIM_WIDTH         = 16;

    parameter CLK_PERIOD = 10;  // 100 MHz clock

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    reg                         clk;
    reg                         rst_n;

    // AXI-Lite Slave Interface
    reg  [AXI_ADDR_WIDTH-1:0]   s_axi_awaddr;
    reg                         s_axi_awvalid;
    wire                        s_axi_awready;
    reg  [AXI_DATA_WIDTH-1:0]   s_axi_wdata;
    reg  [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb;
    reg                         s_axi_wvalid;
    wire                        s_axi_wready;
    wire [1:0]                  s_axi_bresp;
    wire                        s_axi_bvalid;
    reg                         s_axi_bready;
    reg  [AXI_ADDR_WIDTH-1:0]   s_axi_araddr;
    reg                         s_axi_arvalid;
    wire                        s_axi_arready;
    wire [AXI_DATA_WIDTH-1:0]   s_axi_rdata;
    wire [1:0]                  s_axi_rresp;
    wire                        s_axi_rvalid;
    reg                         s_axi_rready;

    // Control outputs
    wire                        start;
    wire [DIM_WIDTH-1:0]        batch_size;
    wire [DIM_WIDTH-1:0]        seq_len;

    // Status inputs
    reg                         done;
    reg                         busy;
    reg  [4:0]                  current_state;
    reg  [DIM_WIDTH-1:0]        current_layer;

    // Weight loading
    wire                        weight_we;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    wire [WEIGHT_DATA_WIDTH-1:0] weight_wdata;
    reg                         weight_ready;

    // Test variables
    reg [AXI_DATA_WIDTH-1:0]    read_data;
    integer                     error_count;

    // Start pulse detector
    reg start_ever_seen;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            start_ever_seen <= 1'b0;
        else if (start)
            start_ever_seen <= 1'b1;
    end

    // Weight write pulse detector
    reg weight_we_seen;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr_cap;
    reg [WEIGHT_DATA_WIDTH-1:0] weight_wdata_cap;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            weight_we_seen <= 1'b0;
        else if (weight_we) begin
            weight_we_seen  <= 1'b1;
            weight_addr_cap <= weight_addr;
            weight_wdata_cap <= weight_wdata;
        end
    end

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    host_interface #(
        .AXI_ADDR_WIDTH    (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH    (AXI_DATA_WIDTH),
        .WEIGHT_ADDR_WIDTH (WEIGHT_ADDR_WIDTH),
        .WEIGHT_DATA_WIDTH (WEIGHT_DATA_WIDTH),
        .DIM_WIDTH         (DIM_WIDTH)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),
        .start            (start),
        .batch_size       (batch_size),
        .seq_len          (seq_len),
        .done             (done),
        .busy             (busy),
        .current_state    (current_state),
        .current_layer    (current_layer),
        .weight_we        (weight_we),
        .weight_addr      (weight_addr),
        .weight_wdata     (weight_wdata),
        .weight_ready     (weight_ready)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // VCD Dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("scripts/wave.vcd");
        $dumpvars(0, tb_host_interface);
    end

    // -------------------------------------------------------------------------
    // AXI-Lite Write Task
    // -------------------------------------------------------------------------
    task axi_write;
        input [AXI_ADDR_WIDTH-1:0] addr;
        input [AXI_DATA_WIDTH-1:0] data;
        begin
            // Drive on negedge so signals are stable at posedge
            @(negedge clk);
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = data;
            s_axi_wstrb   = 4'hF;
            s_axi_wvalid  = 1'b1;
            s_axi_bready  = 1'b1;

            // Handshake fires at next posedge (RTL in WR_IDLE has ready=1)
            @(posedge clk);
            @(negedge clk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;

            // Wait for write response
            @(posedge clk);
            @(posedge clk);
            while (!s_axi_bvalid) @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            s_axi_bready = 1'b0;

            $display("[%0t] AXI Write: addr=0x%08h, data=0x%08h, resp=%0d",
                     $time, addr, data, s_axi_bresp);
        end
    endtask

    // -------------------------------------------------------------------------
    // AXI-Lite Read Task
    // -------------------------------------------------------------------------
    task axi_read;
        input  [AXI_ADDR_WIDTH-1:0] addr;
        output [AXI_DATA_WIDTH-1:0] data;
        begin
            // Drive on negedge so signals are stable at posedge
            @(negedge clk);
            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b1;
            s_axi_rready  = 1'b1;

            // Handshake fires at next posedge (RTL in RD_IDLE has ready=1)
            @(posedge clk);
            @(negedge clk);
            s_axi_arvalid = 1'b0;

            // Wait for read data
            @(posedge clk);
            while (!s_axi_rvalid) @(posedge clk);
            data = s_axi_rdata;
            @(posedge clk);
            @(negedge clk);
            s_axi_rready = 1'b0;

            $display("[%0t] AXI Read:  addr=0x%08h, data=0x%08h, resp=%0d",
                     $time, addr, data, s_axi_rresp);
        end
    endtask

    // -------------------------------------------------------------------------
    // Test Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Initialize signals
        rst_n           = 1'b0;
        s_axi_awaddr    = 32'h0;
        s_axi_awvalid   = 1'b0;
        s_axi_wdata     = 32'h0;
        s_axi_wstrb     = 4'h0;
        s_axi_wvalid    = 1'b0;
        s_axi_bready    = 1'b0;
        s_axi_araddr    = 32'h0;
        s_axi_arvalid   = 1'b0;
        s_axi_rready    = 1'b0;
        done            = 1'b0;
        busy            = 1'b0;
        current_state   = 5'h0;
        current_layer   = 16'h0;
        weight_ready    = 1'b1;
        error_count     = 0;

        // Wait for reset
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        repeat(5) @(posedge clk);

        $display("\n=============================================================================");
        $display("Starting Host Interface Testbench");
        $display("=============================================================================\n");

        // -------------------------------------------------------------------------
        // Test 1: Write and Read Batch Size
        // -------------------------------------------------------------------------
        $display("--- Test 1: Write Batch Size = 2 ---");
        axi_write(32'h00000008, 32'h00000002);

        $display("--- Test 1: Read Back Batch Size ---");
        axi_read(32'h00000008, read_data);
        if (read_data[15:0] == 16'd2) begin
            $display("[PASS] Batch size readback matches (expected=2, got=%0d)", read_data[15:0]);
        end else begin
            $display("[FAIL] Batch size readback mismatch (expected=2, got=%0d)", read_data[15:0]);
            error_count = error_count + 1;
        end

        // -------------------------------------------------------------------------
        // Test 2: Write and Read Sequence Length
        // -------------------------------------------------------------------------
        $display("\n--- Test 2: Write Sequence Length = 32 ---");
        axi_write(32'h0000000C, 32'h00000020);

        $display("--- Test 2: Read Back Sequence Length ---");
        axi_read(32'h0000000C, read_data);
        if (read_data[15:0] == 16'd32) begin
            $display("[PASS] Sequence length readback matches (expected=32, got=%0d)", read_data[15:0]);
        end else begin
            $display("[FAIL] Sequence length readback mismatch (expected=32, got=%0d)", read_data[15:0]);
            error_count = error_count + 1;
        end

        // -------------------------------------------------------------------------
        // Test 3: Verify Control Outputs
        // -------------------------------------------------------------------------
        $display("\n--- Test 3: Verify Control Outputs ---");
        if (batch_size == 16'd2) begin
            $display("[PASS] batch_size output = %0d", batch_size);
        end else begin
            $display("[FAIL] batch_size output mismatch (expected=2, got=%0d)", batch_size);
            error_count = error_count + 1;
        end

        if (seq_len == 16'd32) begin
            $display("[PASS] seq_len output = %0d", seq_len);
        end else begin
            $display("[FAIL] seq_len output mismatch (expected=32, got=%0d)", seq_len);
            error_count = error_count + 1;
        end

        // -------------------------------------------------------------------------
        // Test 4: Start Pulse Test
        // -------------------------------------------------------------------------
        $display("\n--- Test 4: Start Pulse Test ---");

        // Set conditions for start to work
        weight_ready = 1'b1;
        busy = 1'b0;

        $display("Writing 1 to Control Register (0x00) to trigger start");
        axi_write(32'h00000000, 32'h00000001);

        // The start pulse fires during the write sequence; check the capture flag
        repeat(2) @(posedge clk);

        if (start_ever_seen) begin
            $display("[PASS] Start pulse detected");
        end else begin
            $display("[FAIL] Start pulse NOT detected");
            error_count = error_count + 1;
        end

        // Verify start is only a pulse (should be low by now)
        if (start == 1'b0) begin
            $display("[PASS] Start pulse de-asserted (single cycle pulse confirmed)");
        end else begin
            $display("[FAIL] Start signal stuck high (should be single cycle pulse)");
            error_count = error_count + 1;
        end

        // -------------------------------------------------------------------------
        // Test 5: Status Register Test
        // -------------------------------------------------------------------------
        $display("\n--- Test 5: Status Register Read Test ---");

        // Set some status values
        busy = 1'b1;
        done = 1'b0;
        current_state = 5'b00101;  // State 5
        current_layer = 16'h0003;   // Layer 3

        repeat(2) @(posedge clk);

        axi_read(32'h00000004, read_data);

        $display("Status register breakdown:");
        $display("  - Busy bit [0]:          %0b (expected: 1)", read_data[0]);
        $display("  - Done bit [1]:          %0b (expected: 0)", read_data[1]);
        $display("  - Current state [12:8]:  %0d (expected: 5)", read_data[12:8]);
        $display("  - Current layer [23:16]: %0d (expected: 3)", read_data[23:16]);

        // Verify status register bits
        if (read_data[0] == 1'b1) begin
            $display("[PASS] Busy bit is set");
        end else begin
            $display("[FAIL] Busy bit mismatch");
            error_count = error_count + 1;
        end

        if (read_data[12:8] == 5'd5) begin
            $display("[PASS] Current state matches");
        end else begin
            $display("[FAIL] Current state mismatch");
            error_count = error_count + 1;
        end

        if (read_data[23:16] == 8'd3) begin
            $display("[PASS] Current layer matches");
        end else begin
            $display("[FAIL] Current layer mismatch");
            error_count = error_count + 1;
        end

        // -------------------------------------------------------------------------
        // Test 6: Weight Write Test
        // -------------------------------------------------------------------------
        $display("\n--- Test 6: Weight Write Test ---");

        // Write weight address
        axi_write(32'h00000010, 32'h00001234);

        // Write weight data (4 x 32-bit words = 128 bits)
        axi_write(32'h00000014, 32'hDEADBEEF);  // Data[31:0]
        axi_write(32'h00000018, 32'hCAFEBABE);  // Data[63:32]
        axi_write(32'h0000001C, 32'h12345678);  // Data[95:64]
        axi_write(32'h00000020, 32'hABCDEF00);  // Data[127:96]

        // Trigger weight write enable
        axi_write(32'h00000024, 32'h00000001);

        repeat(2) @(posedge clk);

        if (weight_we_seen) begin
            $display("[PASS] Weight write enable was asserted");
            $display("       Weight address: 0x%05h", weight_addr_cap);
            $display("       Weight data:    0x%032h", weight_wdata_cap);

            if (weight_addr_cap == 20'h01234) begin
                $display("[PASS] Weight address matches");
            end else begin
                $display("[FAIL] Weight address mismatch");
                error_count = error_count + 1;
            end

            if (weight_wdata_cap == 128'hABCDEF00_12345678_CAFEBABE_DEADBEEF) begin
                $display("[PASS] Weight data matches");
            end else begin
                $display("[FAIL] Weight data mismatch");
                error_count = error_count + 1;
            end
        end else begin
            $display("[FAIL] Weight write enable NOT asserted");
            error_count = error_count + 1;
        end

        // -------------------------------------------------------------------------
        // Test Summary
        // -------------------------------------------------------------------------
        repeat(10) @(posedge clk);

        $display("\n=============================================================================");
        $display("Test Summary");
        $display("=============================================================================");
        $display("Total errors: %0d", error_count);

        if (error_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
        end else begin
            $display("\n*** TESTS FAILED ***\n");
        end

        $display("Simulation complete at time %0t ns\n", $time);
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout Watchdog
    // -------------------------------------------------------------------------
    initial begin
        #100000;  // 100 us timeout
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
