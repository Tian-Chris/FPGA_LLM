`timescale 1ns / 1ps

`include "defines.vh"

// =============================================================================
// tb_top_matmul1k.v — Production-Scale Single Matmul Test (1024x1024)
// =============================================================================
//
// Tests a single 1024x1024 matmul at production scale:
//   MODEL_DIM=1024, NUM_ENGINES=6, TILE_SIZE=32
//   32x32 tile grid, 32 K-tiles per output tile
//   URAM accumulation from 6 engines writing non-overlapping column shards
//   URAM→HBM flush of 1024 rows × 64 col_words
//
// SINGLE_MATMUL=1 makes FSM go to DONE after first QKV flush.
// No -DSIM_SMALL: uses production parameters from defines.vh.
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

module tb_top_matmul1k;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam AXI_AW = 32;
    localparam AXI_DW = 32;
    localparam TB_HBM_DEPTH = 262144;   // 2^18, power-of-2 for ADDR_MASK

    localparam SEQ_LEN = 1024;
    localparam BATCH   = 1;

    // Production layout constants
    localparam WE              = 16;     // BUS_ELEMS = 256/16
    localparam URAM_COL_WORDS_L = 64;   // Columns used: MODEL_DIM/BUS_ELEMS = 1024/16
    localparam URAM_COL_WORDS_HW = 256; // Actual URAM stride: URAM_COLS/BUS_ELEMS = 4096/16
    localparam URAM_ROWS_L     = 1024;

    // Weight/act base addresses (word-addressed, 256-bit words)
    localparam WEIGHT_BASE = 0;
    localparam ACT_BASE    = 65536;     // W_q takes 1024*64 = 65536 words
    localparam OUTPUT_BASE = 32'h8000;

    // Flush destination: ACT_BASE + ACT_Q_OFFSET
    // ACT_Q_OFFSET = MAX_SEQ_LEN * MODEL_DIM / WE = 128 * 1024 / 16 = 8192
    localparam FLUSH_BASE = ACT_BASE + 8192;  // 73728

    // =========================================================================
    // Signals
    // =========================================================================
    reg clk, rst_n;

    // AXI-Lite
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

    // Loop variables (module-level for Verilog-2001)
    integer fi;
    integer dump_row, dump_col;
    integer dump_addr;
    integer dump_fd;

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
        .SINGLE_MATMUL  (1)
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
    // Backdoor HBM Preloading
    // =========================================================================
    initial begin
        // Wait for sim_hbm_port zero-init to complete, then overwrite
        #1;

        // Load weight + activation data into shared HBM.
        // Weight hex: W_q at addresses 0..65535
        // Activation hex: embeddings at addresses 65536+
        // Load wgt first, then act on top (non-overlapping regions).

        // Shared HBM: weights + activations
        $readmemh("verify/test_data/hbm_wgt_1k.hex", dut.u_hbm.mem);
        $readmemh("verify/test_data/hbm_act_1k.hex", dut.u_hbm.mem);

        $display("[%0t] tb_top_matmul1k: HBM preloading complete (shared prefetch ports)", $time);
        $fflush();
    end

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("[%0t] tb_top_matmul1k: simulation starting", $time);
        $fflush();

        // Initialize AXI signals
        rst_n = 0;
        s_axi_awaddr  = 0; s_axi_awvalid = 0;
        s_axi_wdata   = 0; s_axi_wstrb   = 0; s_axi_wvalid = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0; s_axi_arvalid = 0; s_axi_rready = 0;

        // Reset
        #100;
        $display("[%0t] tb_top_matmul1k: releasing reset", $time);
        $fflush();
        rst_n = 1;
        #100;
        $display("[%0t] tb_top_matmul1k: post-reset, starting AXI config", $time);
        $fflush();

        // Configure via AXI-Lite
        $display("[%0t] Configuring: batch=%0d, seq_len=%0d, weight_base=%0d, act_base=%0d",
                 $time, BATCH, SEQ_LEN, WEIGHT_BASE, ACT_BASE);
        $fflush();
        axi_write(32'h08, BATCH);
        axi_write(32'h0C, SEQ_LEN);
        axi_write(32'h10, WEIGHT_BASE);
        axi_write(32'h14, ACT_BASE);
        axi_write(32'h18, OUTPUT_BASE);

        // Start inference
        $display("[%0t] tb_top_matmul1k: AXI config done, starting inference", $time);
        $fflush();
        axi_write(32'h00, 32'h1);

        // Wait for FSM to reach DONE (S_DONE = 15)
        while (dut.u_fsm.state != 5'd15) begin
            @(posedge clk);
        end

        $display("[%0t] TEST PASSED: FSM reached DONE (state 15)", $time);
        $fflush();

        // =====================================================================
        // Post-Simulation Dumps
        // =====================================================================

        // --- URAM dump (use HW stride, dump only MODEL_DIM cols) ---
        dump_fd = $fopen("verify/test_data/uram_1k_dump.hex", "w");
        if (dump_fd == 0) begin
            $display("[%0t] ERROR: Could not open uram_1k_dump.hex for writing", $time);
            $fflush();
        end else begin
            for (dump_row = 0; dump_row < URAM_ROWS_L; dump_row = dump_row + 1) begin
                for (dump_col = 0; dump_col < URAM_COL_WORDS_L; dump_col = dump_col + 1) begin
                    $fwrite(dump_fd, "%064h\n",
                            dut.u_uram.mem[dump_row * URAM_COL_WORDS_HW + dump_col]);
                end
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped URAM to verify/test_data/uram_1k_dump.hex (%0d rows x %0d col_words, stride=%0d)",
                     $time, URAM_ROWS_L, URAM_COL_WORDS_L, URAM_COL_WORDS_HW);
            $fflush();
        end

        // --- Flush HBM dump ---
        dump_fd = $fopen("verify/test_data/hbm_flush_1k_dump.hex", "w");
        if (dump_fd == 0) begin
            $display("[%0t] ERROR: Could not open hbm_flush_1k_dump.hex for writing", $time);
            $fflush();
        end else begin
            for (dump_addr = 0; dump_addr < TB_HBM_DEPTH; dump_addr = dump_addr + 1) begin
                $fwrite(dump_fd, "%064h\n", dut.u_hbm.mem[dump_addr]);
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped flush HBM to verify/test_data/hbm_flush_1k_dump.hex (%0d words)",
                     $time, TB_HBM_DEPTH);
            $fflush();
        end

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
            $display("[%0t] FSM: %0d -> %0d (layer=%0d, step=%0d, qkv=%0d, head=%0d)",
                     $time, prev_state, dut.u_fsm.state,
                     dut.u_fsm.layer_cnt, dut.u_fsm.step_idx,
                     dut.u_fsm.qkv_phase, dut.u_fsm.head_cnt);
            $fflush();
            prev_state <= dut.u_fsm.state;
        end
    end

    // =========================================================================
    // Flush-to-Load Memory Mirroring — NOT NEEDED with shared u_hbm
    // =========================================================================
    // With a single shared HBM instance, flush writes are immediately visible
    // to all readers. No mirroring required.

    // =========================================================================
    // Timeout Watchdog (120s = 12,000,000,000 cycles at 10ns)
    // =========================================================================
    initial begin
        #120000000000;
        $display("[%0t] ERROR: Simulation timeout (120s)!", $time);
        $fflush();
        $display("  FSM state: %0d", dut.u_fsm.state);
        $display("  Layer: %0d", dut.u_fsm.layer_cnt);
        $display("  Step idx: %0d", dut.u_fsm.step_idx);
        $display("  Step bt/cfg: %0d/%0d", dut.u_fsm.step_bt, dut.u_fsm.step_cfg);
        $display("  QKV phase: %0d", dut.u_fsm.qkv_phase);
        $display("  Head cnt: %0d", dut.u_fsm.head_cnt);
        $display("  waiting_mm: %0d", dut.u_fsm.waiting_mm);
        $display("  TE state: %0d, tiles_outst: %0d",
                 dut.u_tiling_engine.state, dut.u_tiling_engine.tiles_outstanding);
        $display("  TEST FAILED: timeout");
        $fflush();
        $finish;
    end

endmodule
