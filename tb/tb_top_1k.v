`timescale 1ns / 1ps

`include "defines.vh"

// =============================================================================
// tb_top_1k.v — Production-Scale Full Pipeline Test (1024x1024)
// =============================================================================
//
// Full integration test for diffusion_transformer_top at production scale:
//   MODEL_DIM=1024, F_DIM=4096, NUM_HEADS=16, NUM_ENGINES=6, TILE_SIZE=32
//   URAM_ROWS=1024, URAM_COLS=4096, URAM_COL_WORDS=256
//
// Exercises the complete GPT-2 pre-norm pipeline:
//   LN1 -> QKV -> attention -> proj -> res1 -> LN2 -> FFN1 -> act -> FFN2 -> res2
//
// Features:
//   1. Backdoor preloading of shared prefetch HBM memories via $readmemh
//   2. URAM preloading of initial embeddings
//   3. AXI-Lite configuration (batch=1, seq_len=32)
//   4. Single shared u_hbm instance (no flush-to-load mirroring needed)
//   5. FSM state transition monitor with step_idx/head_cnt
//   6. Post-simulation URAM + HBM dumps for Python golden comparison
//
// No -DSIM_SMALL: uses production parameters from defines.vh.
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

module tb_top_1k;

    // =========================================================================
    // Overridable parameters (use -GHBM_RD_LATENCY=N -GURAM_RD_LATENCY=N)
    // =========================================================================
    parameter HBM_RD_LATENCY  = 2;
    parameter URAM_RD_LATENCY = 1;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam AXI_AW = 32;
    localparam AXI_DW = 32;
    localparam TB_HBM_DEPTH = 1048576;    // 2^20

    localparam SEQ_LEN = 32;
    localparam BATCH   = 1;

    // Production layout constants
    localparam WE              = 16;       // BUS_ELEMS = 256/16
    localparam URAM_COL_WORDS_L = 64;     // MODEL_DIM/WE = 1024/16 (used cols)
    localparam URAM_COL_WORDS_HW = 256;   // URAM_COLS/WE = 4096/16 (HW stride)
    localparam URAM_ROWS_L     = 1024;

    // Production memory layout (must match fsm_controller.v)
    localparam MODEL_STRIDE_L = 64;        // MODEL_DIM/WE = 1024/16

    // Weight/act base addresses
    localparam WEIGHT_BASE = 0;
    localparam ACT_BASE    = 787264;       // LAYER_SIZE (production, with biases)
    localparam KV_BASE     = ACT_BASE + 6 * 128 * 1024 / 16;  // after activation scratch
    localparam OUTPUT_BASE = KV_BASE + 2 * 128 * 1024 / 16;  // after KV cache
    localparam DEBUG_BASE  = TB_HBM_DEPTH - 512;  // Last 512 words for debug trace

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
    // Backdoor HBM Preloading
    // =========================================================================
    integer uram_r, uram_c, uram_src;
    localparam URAM_EMBED_SRC = ACT_BASE;   // Embeddings start at ACT_BASE in act HBM

    initial begin
        // Wait for sim_hbm_port zero-init to complete, then overwrite
        #1;

        // Load weight + activation + DMA data into shared HBM.
        // Weight data at addresses 0..786687, activation data at 786688+.
        // Load wgt first, then act on top (non-overlapping regions).

        // Shared HBM: weights + activations
        $readmemh("verify/test_data/hbm_wgt_1k_full.hex", dut.u_hbm.mem);
        $readmemh("verify/test_data/hbm_act_1k_full.hex", dut.u_hbm.mem);

        // DMA data (LN params + embeddings for residual add) — same shared HBM
        $readmemh("verify/test_data/hbm_dma_1k_full.hex", dut.u_hbm.mem);

        // GPT-2 pre-norm: backdoor-preload URAM with initial embeddings.
        // LN1 is the FIRST step and reads data from URAM. The URAM must already
        // contain the embeddings before inference starts.
        // Copy from shared prefetch act HBM at ACT_BASE + ACT_EMBED_OFFSET.
        // URAM stride = URAM_COL_WORDS_HW (256), but only MODEL_STRIDE_L (64) cols used.
        for (uram_r = 0; uram_r < SEQ_LEN; uram_r = uram_r + 1) begin
            for (uram_c = 0; uram_c < MODEL_STRIDE_L; uram_c = uram_c + 1) begin
                uram_src = URAM_EMBED_SRC + uram_r * MODEL_STRIDE_L + uram_c;
                dut.u_uram.mem[uram_r * URAM_COL_WORDS_HW + uram_c] =
                    dut.u_hbm.mem[uram_src];
            end
        end

        $display("[%0t] tb_top_1k: HBM + URAM preloading complete (shared prefetch ports)", $time);
        $fflush();
    end

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("[%0t] tb_top_1k: simulation starting", $time);
        $fflush();

        // Initialize AXI signals
        rst_n = 0;
        s_axi_awaddr  = 0; s_axi_awvalid = 0;
        s_axi_wdata   = 0; s_axi_wstrb   = 0; s_axi_wvalid = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0; s_axi_arvalid = 0; s_axi_rready = 0;

        // Reset
        #100;
        $display("[%0t] tb_top_1k: releasing reset", $time);
        $fflush();
        rst_n = 1;
        #100;
        $display("[%0t] tb_top_1k: post-reset, starting AXI config", $time);
        $fflush();

        // Configure via AXI-Lite
        $display("[%0t] Configuring: batch=%0d, seq_len=%0d, weight_base=%0d, act_base=%0d",
                 $time, BATCH, SEQ_LEN, WEIGHT_BASE, ACT_BASE);
        $fflush();
        axi_write(32'h08, BATCH);
        axi_write(32'h0C, SEQ_LEN);
        axi_write(32'h10, WEIGHT_BASE);
        axi_write(32'h14, ACT_BASE);
        axi_write(32'h24, KV_BASE);
        axi_write(32'h18, OUTPUT_BASE);
        axi_write(32'h28, NUM_ENC_LAYERS);  // num_layers
        axi_write(32'h2C, DEBUG_BASE);  // debug trace base

        // Start inference
        $display("[%0t] tb_top_1k: AXI config done, starting inference", $time);
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
        dump_fd = $fopen("verify/test_data/uram_1k_full_dump.hex", "w");
        if (dump_fd == 0) begin
            $display("[%0t] ERROR: Could not open uram_1k_full_dump.hex for writing", $time);
            $fflush();
        end else begin
            for (dump_row = 0; dump_row < URAM_ROWS_L; dump_row = dump_row + 1) begin
                for (dump_col = 0; dump_col < URAM_COL_WORDS_L; dump_col = dump_col + 1) begin
                    $fwrite(dump_fd, "%064h\n",
                            dut.u_uram.mem[dump_row * URAM_COL_WORDS_HW + dump_col]);
                end
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped URAM to verify/test_data/uram_1k_full_dump.hex (%0d rows x %0d col_words, stride=%0d)",
                     $time, URAM_ROWS_L, URAM_COL_WORDS_L, URAM_COL_WORDS_HW);
            $fflush();
        end

        // --- Flush HBM dump (only ACT region, not entire 1M) ---
        dump_fd = $fopen("verify/test_data/hbm_flush_1k_full_dump.hex", "w");
        if (dump_fd == 0) begin
            $display("[%0t] ERROR: Could not open hbm_flush_1k_full_dump.hex for writing", $time);
            $fflush();
        end else begin
            for (dump_addr = 0; dump_addr < TB_HBM_DEPTH; dump_addr = dump_addr + 1) begin
                $fwrite(dump_fd, "%064h\n", dut.u_hbm.mem[dump_addr]);
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped flush HBM to verify/test_data/hbm_flush_1k_full_dump.hex (%0d words)",
                     $time, TB_HBM_DEPTH);
            $fflush();
        end

        // --- Debug trace dump ---
        dump_fd = $fopen("verify/test_data/debug_trace_1k.hex", "w");
        if (dump_fd != 0) begin
            for (dump_addr = DEBUG_BASE; dump_addr < DEBUG_BASE + 512; dump_addr = dump_addr + 1) begin
                if (dut.u_hbm.mem[dump_addr] != 256'd0) begin
                    $fwrite(dump_fd, "%064h\n", dut.u_hbm.mem[dump_addr]);
                end
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped debug trace to verify/test_data/debug_trace_1k.hex", $time);
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
            // Dump URAM rows 0+1 at ALL step transitions (NEXT_STEP→DECODE)
            if (prev_state == 5'd14 && dut.u_fsm.state == 5'd1) begin
                // Row 0 first word (always)
                $display("[URAM step=%0d] row0 cw0[0:3]=%04h %04h %04h %04h",
                         dut.u_fsm.step_idx,
                         dut.u_uram.mem[0][15:0], dut.u_uram.mem[0][31:16],
                         dut.u_uram.mem[0][47:32], dut.u_uram.mem[0][63:48]);
                // Row 1 first word (always) — mem[256] = row 1, col_word 0
                $display("[URAM step=%0d] row1 cw0[0:3]=%04h %04h %04h %04h",
                         dut.u_fsm.step_idx,
                         dut.u_uram.mem[256][15:0], dut.u_uram.mem[256][31:16],
                         dut.u_uram.mem[256][47:32], dut.u_uram.mem[256][63:48]);
                // For FFN1/GELU/FFN2 steps: dump deeper columns
                if (dut.u_fsm.step_idx >= 4'd10 && dut.u_fsm.step_idx <= 4'd13) begin
                    $display("[URAM step=%0d] row0 cw2[32:35]=%04h %04h %04h %04h",
                             dut.u_fsm.step_idx,
                             dut.u_uram.mem[2][15:0], dut.u_uram.mem[2][31:16],
                             dut.u_uram.mem[2][47:32], dut.u_uram.mem[2][63:48]);
                    $display("[URAM step=%0d] row0 cw100[1600:1603]=%04h %04h %04h %04h",
                             dut.u_fsm.step_idx,
                             dut.u_uram.mem[100][15:0], dut.u_uram.mem[100][31:16],
                             dut.u_uram.mem[100][47:32], dut.u_uram.mem[100][63:48]);
                    $display("[URAM step=%0d] row1 cw2[32:35]=%04h %04h %04h %04h",
                             dut.u_fsm.step_idx,
                             dut.u_uram.mem[258][15:0], dut.u_uram.mem[258][31:16],
                             dut.u_uram.mem[258][47:32], dut.u_uram.mem[258][63:48]);
                end
            end
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
    // Timeout Watchdog (600s = 600,000,000,000 time units at 10ns)
    // =========================================================================
    initial begin
        #600000000000;
        $display("[%0t] ERROR: Simulation timeout (600s)!", $time);
        $fflush();
        $display("  FSM state: %0d", dut.u_fsm.state);
        $display("  Layer: %0d", dut.u_fsm.layer_cnt);
        $display("  Step idx: %0d", dut.u_fsm.step_idx);
        $display("  Step bt/cfg: %0d/%0d", dut.u_fsm.step_bt, dut.u_fsm.step_cfg);
        $display("  QKV phase: %0d", dut.u_fsm.qkv_phase);
        $display("  Head cnt: %0d", dut.u_fsm.head_cnt);
        $display("  waiting_mm: %0d", dut.u_fsm.waiting_mm);
        $display("  nm_flush_phase: %0d", dut.u_fsm.nm_flush_phase);
        $display("  TE state: %0d, tiles_outst: %0d",
                 dut.u_tiling_engine.state, dut.u_tiling_engine.tiles_outstanding);
        $display("  TEST FAILED: timeout");
        $fflush();
        $finish;
    end

endmodule
