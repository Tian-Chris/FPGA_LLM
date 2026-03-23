`timescale 1ns / 1ps

`include "defines.vh"

// =============================================================================
// tb_top.v — SIM_SMALL Integration Test (HBM/URAM Architecture)
// =============================================================================
//
// Full integration test for diffusion_transformer_top with SIM_SMALL parameters:
//   MODEL_DIM=64, F_DIM=128, NUM_HEADS=2, NUM_ENGINES=2, TILE_SIZE=32
//   URAM_ROWS=32, URAM_COLS=128, URAM_COL_WORDS=8
//
// Features:
//   1. Backdoor preloading of HBM memories via $readmemh
//   2. AXI-Lite configuration (batch=1, seq_len=4)
//   3. Single shared u_hbm instance (no flush-to-load mirroring needed)
//   4. FSM state transition monitor
//   5. Post-simulation URAM + HBM dumps for Python golden comparison
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

module tb_top;

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
    localparam TB_HBM_DEPTH = 4096;

    localparam SEQ_LEN = 32;
    localparam BATCH   = 1;

    // SIM_SMALL layout constants
    localparam WE              = 16;    // BUS_ELEMS = 256/16
    localparam URAM_COL_WORDS_L = 8;   // URAM_COLS/BUS_ELEMS = 128/16
    localparam URAM_ROWS_L     = 32;

    // Weight/act base addresses
    localparam WEIGHT_BASE = 0;
    localparam ACT_BASE    = 2092;      // LAYER_SIZE with SIM_SMALL params (includes biases)
    localparam KV_BASE     = ACT_BASE + 6 * 32 * 64 / 16;  // after activation scratch
    localparam OUTPUT_BASE = 32'h8000;
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
    localparam MODEL_STRIDE_L = 64 / WE;    // MODEL_DIM / WE for SIM_SMALL = 4

    initial begin
        // Wait for sim_hbm_port zero-init to complete, then overwrite
        #1;

        // Load weight + activation + DMA data into shared HBM.
        // Weight data occupies addresses 0..519, activation data at 520+.
        // The hex files use @addr directives so they write to non-overlapping regions.

        // Shared HBM: weights + activations
        $readmemh("verify/test_data/hbm_wgt.hex", dut.u_hbm.mem);
        $readmemh("verify/test_data/hbm_act.hex", dut.u_hbm.mem);

        // DMA data (LN params, residual sub) — same shared HBM
        $readmemh("verify/test_data/hbm_dma.hex", dut.u_hbm.mem);

        // GPT-2 pre-norm: backdoor-preload URAM with initial embeddings.
        // LN1 is the FIRST step and reads data from URAM. The URAM must already
        // contain the embeddings before inference starts.
        // Copy from act HBM (engine 0) at ACT_BASE + ACT_EMBED_OFFSET.
        for (uram_r = 0; uram_r < SEQ_LEN; uram_r = uram_r + 1) begin
            for (uram_c = 0; uram_c < MODEL_STRIDE_L; uram_c = uram_c + 1) begin
                uram_src = URAM_EMBED_SRC + uram_r * MODEL_STRIDE_L + uram_c;
                dut.u_uram.mem[uram_r * URAM_COL_WORDS_L + uram_c] =
                    dut.u_hbm.mem[uram_src];
            end
        end

        $display("[%0t] tb_top: HBM + URAM preloading complete", $time);
        $fflush();
    end

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("[%0t] tb_top: simulation starting", $time);
        $fflush();

        // Initialize AXI signals
        rst_n = 0;
        s_axi_awaddr  = 0; s_axi_awvalid = 0;
        s_axi_wdata   = 0; s_axi_wstrb   = 0; s_axi_wvalid = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0; s_axi_arvalid = 0; s_axi_rready = 0;

        // Reset
        #100;
        $display("[%0t] tb_top: releasing reset", $time);
        $fflush();
        rst_n = 1;
        #100;
        $display("[%0t] tb_top: post-reset, starting AXI config", $time);
        $fflush();

        // Configure via AXI-Lite (register map from host_interface.v)
        //   0x00: Control (start)
        //   0x08: Batch size
        //   0x0C: Sequence length
        //   0x10: Weight HBM base (word addr)
        //   0x14: Activation HBM base
        //   0x18: Output HBM base
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
        $display("[%0t] tb_top: AXI config done, starting inference", $time);
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

        // --- URAM dump ---
        dump_fd = $fopen("verify/test_data/uram_dump.hex", "w");
        if (dump_fd == 0) begin
            $display("[%0t] ERROR: Could not open uram_dump.hex for writing", $time);
            $fflush();
        end else begin
            for (dump_row = 0; dump_row < URAM_ROWS_L; dump_row = dump_row + 1) begin
                for (dump_col = 0; dump_col < URAM_COL_WORDS_L; dump_col = dump_col + 1) begin
                    $fwrite(dump_fd, "%064h\n",
                            dut.u_uram.mem[dump_row * URAM_COL_WORDS_L + dump_col]);
                end
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped URAM to verify/test_data/uram_dump.hex (%0d rows x %0d col_words)",
                     $time, URAM_ROWS_L, URAM_COL_WORDS_L);
            $fflush();
        end

        // --- Flush HBM dump ---
        dump_fd = $fopen("verify/test_data/hbm_flush_dump.hex", "w");
        if (dump_fd == 0) begin
            $display("[%0t] ERROR: Could not open hbm_flush_dump.hex for writing", $time);
            $fflush();
        end else begin
            for (dump_addr = 0; dump_addr < TB_HBM_DEPTH; dump_addr = dump_addr + 1) begin
                $fwrite(dump_fd, "%064h\n", dut.u_hbm.mem[dump_addr]);
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped flush HBM to verify/test_data/hbm_flush_dump.hex (%0d words)",
                     $time, TB_HBM_DEPTH);
            $fflush();
        end

        // --- Debug trace dump ---
        dump_fd = $fopen("verify/test_data/debug_trace_small.hex", "w");
        if (dump_fd != 0) begin
            for (dump_addr = DEBUG_BASE; dump_addr < DEBUG_BASE + 512; dump_addr = dump_addr + 1) begin
                if (dut.u_hbm.mem[dump_addr] != 256'd0) begin
                    $fwrite(dump_fd, "%064h\n", dut.u_hbm.mem[dump_addr]);
                end
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped debug trace to verify/test_data/debug_trace_small.hex", $time);
            $fflush();
        end

        #100;
        $finish;
    end

    // =========================================================================
    // FSM State Monitor + Intermediate URAM/Flush Dumps
    // =========================================================================
    reg [4:0] prev_state;
    initial prev_state = 0;

    always @(posedge clk) begin
        if (rst_n && dut.u_fsm.state !== prev_state) begin
            $display("[%0t] FSM: %0d -> %0d (layer=%0d, step=%0d, qkv=%0d, head=%0d)",
                     $time, prev_state, dut.u_fsm.state,
                     dut.u_fsm.layer_cnt, dut.u_fsm.step_idx,
                     dut.u_fsm.qkv_phase, dut.u_fsm.head_cnt);
            // Dump first 4 FP16 elements of URAM row 0 when entering S_NEXT_STEP (14)
            if (dut.u_fsm.state == 5'd14) begin
                $display("[URAM step=%0d] row0[0:3]=%04h %04h %04h %04h",
                         dut.u_fsm.step_idx,
                         dut.u_uram.mem[0][15:0],
                         dut.u_uram.mem[0][31:16],
                         dut.u_uram.mem[0][47:32],
                         dut.u_uram.mem[0][63:48]);
                // Dump Q row 0 from flush HBM after QKV step (step 2, before attn overwrites it)
                if (dut.u_fsm.step_idx == 4'd2)
                    $display("[Q_FLUSH] Q_row0 word0=%064h word1=%064h word2=%064h word3=%064h",
                             dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16],
                             dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16 + 1],
                             dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16 + 2],
                             dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16 + 3]);
            end
            // Dump attn_concat at ACT_Q_OFFSET when entering S_MM_RUN (10) for step 4 (proj)
            if (dut.u_fsm.state == 5'd10 && dut.u_fsm.step_idx == 4'd4) begin
                $display("[PROJ_IN] attn_concat row0 at ACT_Q_OFFSET:");
                $display("[PROJ_IN]   word0=%064h", dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16]);
                $display("[PROJ_IN]   word1=%064h", dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16 + 1]);
                $display("[PROJ_IN]   word2=%064h", dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16 + 2]);
                $display("[PROJ_IN]   word3=%064h", dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16 + 3]);
            end
            // S_ATT_OUT = 8 → S_ATT_OUT_FL = 9: dump URAM cols 0-3 row 0
            if (dut.u_fsm.state == 5'd9 && prev_state == 5'd8) begin
                $display("[ATT_OUT_DONE] head=%0d URAM row0: col0=%064h col1=%064h col2=%064h col3=%064h",
                         dut.u_fsm.head_cnt,
                         dut.u_uram.mem[0],
                         dut.u_uram.mem[1],
                         dut.u_uram.mem[2],
                         dut.u_uram.mem[3]);
            end
            // S_ATT_OUT_FL = 9. When leaving it, check HBM
            if (prev_state == 5'd9) begin
                $display("[ATT_FL_DONE] head=%0d Q_OFFSET w0=%064h w1=%064h w2=%064h w3=%064h",
                         dut.u_fsm.head_cnt,
                         dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16],
                         dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16 + 1],
                         dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16 + 2],
                         dut.u_hbm.mem[ACT_BASE + SEQ_LEN*64/16 + 3]);
            end
            // Dump URAM scores BEFORE softmax starts (entering S_ATT_SM = 6)
            if (dut.u_fsm.state == 5'd6) begin
                $display("[SM_START] head=%0d URAM scores row0: col0=%064h col1=%064h",
                         dut.u_fsm.head_cnt,
                         dut.u_uram.mem[0],
                         dut.u_uram.mem[1]);
            end
            // Dump URAM probs after softmax (entering S_ATT_SM_FL = 7)
            if (dut.u_fsm.state == 5'd7 && prev_state == 5'd6) begin
                $display("[SM_DONE] head=%0d URAM probs row0: col0=%064h col1=%064h",
                         dut.u_fsm.head_cnt,
                         dut.u_uram.mem[0],
                         dut.u_uram.mem[1]);
            end
            // Dump probs at ACT_ATTN_OFFSET when entering S_ATT_OUT (8)
            if (dut.u_fsm.state == 5'd8) begin
                $display("[ATT_OUT_START] head=%0d probs_row0: w0=%064h w1=%064h",
                         dut.u_fsm.head_cnt,
                         dut.u_hbm.mem[ACT_BASE + 4*SEQ_LEN*64/16],
                         dut.u_hbm.mem[ACT_BASE + 4*SEQ_LEN*64/16 + 1]);
                $display("[ATT_OUT_START] V_h row0: w0=%064h w1=%064h",
                         dut.u_hbm.mem[KV_BASE + dut.u_fsm.head_cnt * (32/16)],
                         dut.u_hbm.mem[KV_BASE + dut.u_fsm.head_cnt * (32/16) + 1]);
            end
            // Dump HBM probs and V when entering S_ATT_OUT (8) from S_ATT_SM_FL (7)
            if (prev_state == 5'd7 && dut.u_fsm.state == 5'd8) begin
                $display("[ATT_OUT] HBM probs row0 word0: %064h", dut.u_hbm.mem[ACT_BASE + 4*SEQ_LEN*64/16]);
                $display("[ATT_OUT] HBM probs row0 word1: %064h", dut.u_hbm.mem[ACT_BASE + 4*SEQ_LEN*64/16 + 1]);
                $display("[ATT_OUT] HBM V row0 word0:     %064h", dut.u_hbm.mem[KV_BASE + SEQ_LEN*64/16]);
                $display("[ATT_OUT] HBM V row0 word1:     %064h", dut.u_hbm.mem[KV_BASE + SEQ_LEN*64/16 + 1]);
                $display("[ATT_OUT] URAM row0 word0:      %064h", dut.u_uram.mem[0]);
                $display("[ATT_OUT] URAM row0 word1:      %064h", dut.u_uram.mem[1]);
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
    // Timeout Watchdog (50ms = 5,000,000 cycles at 10ns)
    // =========================================================================
    initial begin
        #50000000;
        $display("[%0t] ERROR: Simulation timeout!", $time);
        $fflush();
        $display("  FSM state: %0d", dut.u_fsm.state);
        $display("  Layer: %0d", dut.u_fsm.layer_cnt);
        $display("  Step idx: %0d", dut.u_fsm.step_idx);
        $display("  Step bt/cfg: %0d/%0d", dut.u_fsm.step_bt, dut.u_fsm.step_cfg);
        $display("  QKV phase: %0d", dut.u_fsm.qkv_phase);
        $display("  waiting_mm: %0d", dut.u_fsm.waiting_mm);
        $display("  nm_flush_phase: %0d", dut.u_fsm.nm_flush_phase);
        $display("  head_cnt: %0d", dut.u_fsm.head_cnt);
        $display("  TE state: %0d, tiles_outst: %0d",
                 dut.u_tiling_engine.state, dut.u_tiling_engine.tiles_outstanding);
        $display("  TEST FAILED: timeout");
        $fflush();
        $finish;
    end

endmodule
