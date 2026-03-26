`timescale 1ns / 1ps

`include "defines.vh"

// =============================================================================
// tb_top_diag.v — Diagnostic Test Mode Testbench
// =============================================================================
//
// Runs hardware diagnostic tests via test_mode register. No weights or
// embeddings needed — tests exercise primitives (HBM write, URAM write/read,
// latency probe, register readback) in isolation.
//
// Test modes exercised (set via TEST_MODE parameter):
//   1  = HBM echo (debug_writer pattern write)
//   5  = URAM write + flush (nm_adapter → URAM row 0 → HBM)
//   6  = URAM latency probe (checkpoint read cycle count)
//   7  = Multi-row URAM (rows 0/256/512/768 via checkpoint read)
//   12 = Register value readback
//
// After FSM reaches DONE, dumps output region of HBM for Python verification.
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

module tb_top_diag;

    // =========================================================================
    // Overridable parameters
    // =========================================================================
    parameter HBM_RD_LATENCY  = 2;
    parameter URAM_RD_LATENCY = 1;
    parameter TEST_MODE       = 1;     // which diagnostic to run

    // =========================================================================
    // Constants
    // =========================================================================
    localparam AXI_AW = 32;
    localparam AXI_DW = 32;
    localparam TB_HBM_DEPTH = 1048576;    // 2^20

    localparam SEQ_LEN = 32;
    localparam BATCH   = 1;

    // Use same layout as tb_top_1k for consistency
    localparam WE              = 16;
    localparam WEIGHT_BASE     = 0;
    localparam ACT_BASE        = 787264;
    localparam KV_BASE         = ACT_BASE + 6 * 128 * 1024 / 16;
    localparam OUTPUT_BASE     = KV_BASE + 2 * 128 * 1024 / 16;
    localparam DEBUG_BASE      = TB_HBM_DEPTH - 512;

    // =========================================================================
    // Signals
    // =========================================================================
    reg clk, rst_n;

    reg  [AXI_AW-1:0]    s_axi_awaddr;
    reg                   s_axi_awvalid;
    wire                  s_axi_awready;
    reg  [AXI_DW-1:0]    s_axi_wdata;
    reg  [AXI_DW/8-1:0]  s_axi_wstrb;
    reg                   s_axi_wvalid;
    wire                  s_axi_wready;
    wire [1:0]            s_axi_bresp;
    wire                  s_axi_bvalid;
    reg                   s_axi_bready;
    reg  [AXI_AW-1:0]    s_axi_araddr;
    reg                   s_axi_arvalid;
    wire                  s_axi_arready;
    wire [AXI_DW-1:0]    s_axi_rdata;
    wire [1:0]            s_axi_rresp;
    wire                  s_axi_rvalid;
    reg                   s_axi_rready;
    wire                  irq_done;

    // Dump variables
    integer dump_addr, dump_fd;

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    diffusion_transformer_top #(
        .AXI_ADDR_WIDTH (AXI_AW),
        .AXI_DATA_WIDTH (AXI_DW),
        .SIM_HBM_DEPTH  (TB_HBM_DEPTH),
        .HBM_RD_LATENCY (HBM_RD_LATENCY),
        .URAM_RD_LATENCY(URAM_RD_LATENCY)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .irq_done       (irq_done)
    );

    // =========================================================================
    // AXI-Lite Write Task
    // =========================================================================
    task axi_write;
        input [AXI_AW-1:0] addr;
        input [AXI_DW-1:0] data;
        begin
            @(negedge clk);
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = data;
            s_axi_wstrb   = 4'hF;
            s_axi_wvalid  = 1'b1;
            s_axi_bready  = 1'b1;
            @(posedge clk); @(negedge clk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
            @(posedge clk); @(posedge clk);
            while (!s_axi_bvalid) @(posedge clk);
            @(posedge clk); @(negedge clk);
            s_axi_bready = 1'b0;
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("[%0t] tb_top_diag: test_mode=%0d, HBM_LAT=%0d, URAM_LAT=%0d",
                 $time, TEST_MODE, HBM_RD_LATENCY, URAM_RD_LATENCY);
        $fflush();

        // Initialize AXI signals
        rst_n = 0;
        s_axi_awaddr  = 0; s_axi_awvalid = 0;
        s_axi_wdata   = 0; s_axi_wstrb   = 0; s_axi_wvalid = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0; s_axi_arvalid = 0; s_axi_rready = 0;

        // Reset
        #100;
        rst_n = 1;
        #100;

        // Configure registers
        $display("[%0t] Configuring: batch=%0d, seq=%0d, test_mode=%0d",
                 $time, BATCH, SEQ_LEN, TEST_MODE);
        $fflush();
        axi_write(32'h08, BATCH);            // batch_size
        axi_write(32'h0C, SEQ_LEN);          // seq_len
        axi_write(32'h10, WEIGHT_BASE);      // weight_base
        axi_write(32'h14, ACT_BASE);         // act_base
        axi_write(32'h24, KV_BASE);          // kv_base
        axi_write(32'h18, OUTPUT_BASE);      // output_base
        axi_write(32'h28, NUM_ENC_LAYERS);   // num_layers
        axi_write(32'h2C, DEBUG_BASE);        // debug_base
        axi_write(32'h34, TEST_MODE);         // test_mode
        axi_write(32'h30, 0);                 // max_steps (0 = unlimited)

        // Start
        $display("[%0t] Starting diagnostic test_mode=%0d", $time, TEST_MODE);
        $fflush();
        axi_write(32'h00, 32'h1);

        // Wait for FSM DONE
        while (dut.u_fsm.state != 5'd15) begin
            @(posedge clk);
        end

        $display("[%0t] FSM reached DONE", $time);
        $fflush();

        // Dump output region of HBM for Python verification
        // Dump 64 words starting at OUTPUT_BASE (more than enough for any test)
        dump_fd = $fopen("verify/test_data/diag_output.hex", "w");
        if (dump_fd != 0) begin
            for (dump_addr = OUTPUT_BASE; dump_addr < OUTPUT_BASE + 64; dump_addr = dump_addr + 1) begin
                $fwrite(dump_fd, "%064h\n", dut.u_hbm.mem[dump_addr]);
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped output region to verify/test_data/diag_output.hex", $time);
            $fflush();
        end

        // Also dump debug trace (for test_mode=12 which writes via debug_writer)
        dump_fd = $fopen("verify/test_data/diag_debug.hex", "w");
        if (dump_fd != 0) begin
            for (dump_addr = DEBUG_BASE; dump_addr < DEBUG_BASE + 64; dump_addr = dump_addr + 1) begin
                $fwrite(dump_fd, "%064h\n", dut.u_hbm.mem[dump_addr]);
            end
            $fclose(dump_fd);
        end

        // Print first few output words for quick visual check
        $display("--- Output HBM[OUTPUT_BASE+0..3] ---");
        $display("  [+0] %064h", dut.u_hbm.mem[OUTPUT_BASE + 0]);
        $display("  [+1] %064h", dut.u_hbm.mem[OUTPUT_BASE + 1]);
        $display("  [+2] %064h", dut.u_hbm.mem[OUTPUT_BASE + 2]);
        $display("  [+3] %064h", dut.u_hbm.mem[OUTPUT_BASE + 3]);
        $fflush();

        #100;
        $finish;
    end

    // =========================================================================
    // FSM State Monitor
    // =========================================================================
    reg [4:0] prev_state;
    initial prev_state = 0;

    always @(posedge clk) begin
        if (rst_n && dut.u_fsm.state !== prev_state) begin
            $display("[%0t] FSM: %0d -> %0d (test_phase=%0d, test_cnt=%0d)",
                     $time, prev_state, dut.u_fsm.state,
                     dut.u_fsm.test_phase, dut.u_fsm.test_cnt);
            $fflush();
            prev_state <= dut.u_fsm.state;
        end
    end

    // =========================================================================
    // Timeout Watchdog (30s — diagnostic tests should be fast)
    // =========================================================================
    initial begin
        #30000000000;
        $display("[%0t] ERROR: Simulation timeout (30s)!", $time);
        $display("  FSM state: %0d, test_phase: %0d, test_cnt: %0d",
                 dut.u_fsm.state, dut.u_fsm.test_phase, dut.u_fsm.test_cnt);
        $display("  TEST FAILED: timeout");
        $fflush();
        $finish;
    end

endmodule
