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
//   3. Flush-to-load memory mirroring (u_hbm_flush → all act/wgt HBMs)
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
    localparam ACT_BASE    = 2064;      // LAYER_SIZE with SIM_SMALL params
    localparam OUTPUT_BASE = 32'h8000;

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
    integer mirror_r, mirror_c, mirror_addr;

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

        // Load weight + activation data into shared prefetch HBM ports.
        // Weight data occupies addresses 0..519, activation data at 520+.
        // The hex files use @addr directives so they write to non-overlapping regions.

        // Weight prefetch HBM: weights + activations
        $readmemh("verify/test_data/hbm_wgt.hex", dut.u_hbm_pf_wgt.mem);
        $readmemh("verify/test_data/hbm_act.hex", dut.u_hbm_pf_wgt.mem);

        // Activation prefetch HBM: weights + activations
        $readmemh("verify/test_data/hbm_wgt.hex", dut.u_hbm_pf_act.mem);
        $readmemh("verify/test_data/hbm_act.hex", dut.u_hbm_pf_act.mem);

        // Load DMA HBM data (LN params, residual sub)
        $readmemh("verify/test_data/hbm_dma.hex", dut.u_hbm_dma.mem);

        // GPT-2 pre-norm: backdoor-preload URAM with initial embeddings.
        // LN1 is the FIRST step and reads data from URAM. The URAM must already
        // contain the embeddings before inference starts.
        // Copy from act HBM (engine 0) at ACT_BASE + ACT_EMBED_OFFSET.
        for (uram_r = 0; uram_r < SEQ_LEN; uram_r = uram_r + 1) begin
            for (uram_c = 0; uram_c < MODEL_STRIDE_L; uram_c = uram_c + 1) begin
                uram_src = URAM_EMBED_SRC + uram_r * MODEL_STRIDE_L + uram_c;
                dut.u_uram.mem[uram_r * URAM_COL_WORDS_L + uram_c] =
                    dut.u_hbm_pf_act.mem[uram_src];
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
        axi_write(32'h18, OUTPUT_BASE);

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
                $fwrite(dump_fd, "%064h\n", dut.u_hbm_flush.mem[dump_addr]);
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped flush HBM to verify/test_data/hbm_flush_dump.hex (%0d words)",
                     $time, TB_HBM_DEPTH);
            $fflush();
        end

        // --- DMA HBM dump (debug) ---
        dump_fd = $fopen("verify/test_data/hbm_dma_dump.hex", "w");
        if (dump_fd == 0) begin
            $display("[%0t] ERROR: Could not open hbm_dma_dump.hex for writing", $time);
            $fflush();
        end else begin
            for (dump_addr = 0; dump_addr < TB_HBM_DEPTH; dump_addr = dump_addr + 1) begin
                $fwrite(dump_fd, "%064h\n", dut.u_hbm_dma.mem[dump_addr]);
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped DMA HBM to verify/test_data/hbm_dma_dump.hex (%0d words)",
                     $time, TB_HBM_DEPTH);
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
            $fflush();
            prev_state <= dut.u_fsm.state;
        end
    end

    // =========================================================================
    // Flush-to-Load Memory Mirroring (Region-Tracked)
    // =========================================================================
    // Capture flush parameters on uram_flush_start, then on uf_done mirror
    // the EXACT flush region to all engine HBMs — including zero-valued words.
    // The old approach skipped zero words, leaving stale data from prior flushes
    // (e.g., LN1 data persisting through FFN_ACT flush where ReLU zeros a word).
    // =========================================================================
    reg uf_done_prev;
    reg [27:0] saved_flush_base;
    reg [27:0] saved_flush_stride;
    reg [9:0]  saved_flush_rows;     // count-1
    reg [7:0]  saved_flush_cols;     // count-1
    reg        flush_params_valid;

    initial begin
        uf_done_prev = 0;
        saved_flush_base = 0;
        saved_flush_stride = 0;
        saved_flush_rows = 0;
        saved_flush_cols = 0;
        flush_params_valid = 0;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            // Capture flush parameters when flush starts
            if (dut.u_fsm.uram_flush_start) begin
                saved_flush_base   <= dut.u_fsm.uram_flush_hbm_base;
                saved_flush_stride <= dut.u_fsm.uram_flush_hbm_stride;
                saved_flush_rows   <= dut.u_fsm.uram_flush_num_rows;
                saved_flush_cols   <= dut.u_fsm.uram_flush_num_col_words;
                flush_params_valid <= 1'b1;
            end

            // Mirror on flush done — iterate exact flush region
            uf_done_prev <= dut.uf_done;
            if (dut.uf_done && !uf_done_prev && flush_params_valid) begin
                for (mirror_r = 0; mirror_r <= saved_flush_rows; mirror_r = mirror_r + 1) begin
                    for (mirror_c = 0; mirror_c <= saved_flush_cols; mirror_c = mirror_c + 1) begin
                        mirror_addr = saved_flush_base + mirror_r * saved_flush_stride + mirror_c;
                        dut.u_hbm_pf_act.mem[mirror_addr] = dut.u_hbm_flush.mem[mirror_addr];
                        dut.u_hbm_pf_wgt.mem[mirror_addr] = dut.u_hbm_flush.mem[mirror_addr];
                    end
                end
                flush_params_valid <= 1'b0;
                $display("[%0t] FLUSH MIRROR: base=%0d stride=%0d rows=%0d cols=%0d (state=%0d)",
                         $time, saved_flush_base, saved_flush_stride,
                         saved_flush_rows + 1, saved_flush_cols + 1, dut.u_fsm.state);
                $fflush();
            end
        end
    end

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
