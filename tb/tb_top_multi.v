`timescale 1ns / 1ps

`include "defines.vh"

// Multi-layer integration test — 3 phases:
//   Phase 1: Prefill (BT=32, decode_mode=0)
//   Phase 2: Decode token 1 (BT=1, decode_mode=1, cache_len=32)
//   Phase 3: Decode token 2 (BT=1, decode_mode=1, cache_len=33)

module tb_top_multi;

    parameter HBM_RD_LATENCY  = 2;
    parameter URAM_RD_LATENCY = 1;

    localparam AXI_AW = 32;
    localparam AXI_DW = 32;
    localparam TB_HBM_DEPTH = 2097152;

    localparam SEQ_LEN = 32;
    localparam BATCH   = 1;

    localparam WE              = 16;
    localparam URAM_COL_WORDS_L = 64;
    localparam URAM_COL_WORDS_HW = 256;
    localparam URAM_ROWS_L     = 1024;

    localparam MODEL_STRIDE_L = 64;
    localparam TOTAL_KV_ROWS  = 34;

    localparam WEIGHT_BASE = 0;
    localparam ACT_BASE    = 1573376;
    localparam KV_BASE     = 1622528;
    localparam OUTPUT_BASE = 32'h8000;

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

    integer fi;
    integer dump_row, dump_col;
    integer dump_addr;
    integer dump_fd;
    integer mirror_r, mirror_c, mirror_addr;

    // Decode embed temp arrays
    reg [255:0] decode_embed_1 [0:MODEL_STRIDE_L-1];
    reg [255:0] decode_embed_2 [0:MODEL_STRIDE_L-1];
    integer de_i;

    initial clk = 0;
    always #5 clk = ~clk;

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

    integer uram_r, uram_c, uram_src;
    localparam URAM_EMBED_SRC = ACT_BASE;

    // =========================================================================
    // HBM + URAM Preloading
    // =========================================================================
    initial begin
        #1;
        $readmemh("verify/test_data/hbm_wgt_multi.hex", dut.u_hbm_pf_wgt.mem);
        $readmemh("verify/test_data/hbm_act_multi.hex", dut.u_hbm_pf_wgt.mem);
        $readmemh("verify/test_data/hbm_wgt_multi.hex", dut.u_hbm_pf_act.mem);
        $readmemh("verify/test_data/hbm_act_multi.hex", dut.u_hbm_pf_act.mem);
        $readmemh("verify/test_data/hbm_dma_multi.hex", dut.u_hbm_dma.mem);

        // Load decode embed arrays
        $readmemh("verify/test_data/decode_embed_1.hex", decode_embed_1);
        $readmemh("verify/test_data/decode_embed_2.hex", decode_embed_2);

        for (uram_r = 0; uram_r < SEQ_LEN; uram_r = uram_r + 1) begin
            for (uram_c = 0; uram_c < MODEL_STRIDE_L; uram_c = uram_c + 1) begin
                uram_src = URAM_EMBED_SRC + uram_r * MODEL_STRIDE_L + uram_c;
                dut.u_uram.mem[uram_r * URAM_COL_WORDS_HW + uram_c] =
                    dut.u_hbm_pf_act.mem[uram_src];
            end
        end

        $display("[%0t] tb_top_multi: HBM + URAM preloading complete", $time);
        $fflush();
    end

    // =========================================================================
    // Main Test Sequence: 3 Phases
    // =========================================================================
    initial begin
        $display("[%0t] tb_top_multi: simulation starting (3-phase decode test)", $time);
        $fflush();

        rst_n = 0;
        s_axi_awaddr  = 0; s_axi_awvalid = 0;
        s_axi_wdata   = 0; s_axi_wstrb   = 0; s_axi_wvalid = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0; s_axi_arvalid = 0; s_axi_rready = 0;

        #100;
        rst_n = 1;
        #100;

        // ============ PHASE 1: PREFILL ============
        $display("[%0t] === PHASE 1: PREFILL (seq=%0d, decode=0) ===", $time, SEQ_LEN);
        $fflush();
        axi_write(32'h08, BATCH);
        axi_write(32'h0C, SEQ_LEN);
        axi_write(32'h10, WEIGHT_BASE);
        axi_write(32'h14, ACT_BASE);
        axi_write(32'h18, OUTPUT_BASE);
        axi_write(32'h24, KV_BASE);
        axi_write(32'h1C, 32'd0);       // decode_mode = 0
        axi_write(32'h20, 32'd0);       // cache_len = 0

        axi_write(32'h00, 32'h1);       // START

        while (dut.u_fsm.state != S_DONE) @(posedge clk);
        $display("[%0t] PREFILL DONE", $time);
        $fflush();
        @(posedge clk); @(posedge clk);

        // ============ INJECT DECODE EMBED 1 ============
        for (de_i = 0; de_i < MODEL_STRIDE_L; de_i = de_i + 1) begin
            dut.u_hbm_pf_act.mem[ACT_BASE + de_i]  = decode_embed_1[de_i];
            dut.u_hbm_pf_wgt.mem[ACT_BASE + de_i]  = decode_embed_1[de_i];
            dut.u_hbm_dma.mem[ACT_BASE + de_i]      = decode_embed_1[de_i];
            dut.u_hbm_flush.mem[ACT_BASE + de_i]    = decode_embed_1[de_i];
            dut.u_uram.mem[0 * URAM_COL_WORDS_HW + de_i] = decode_embed_1[de_i];
        end
        $display("[%0t] Injected decode_embed_1", $time);
        $fflush();

        // ============ PHASE 2: DECODE TOKEN 1 ============
        $display("[%0t] === PHASE 2: DECODE TOKEN 1 (cache_len=%0d) ===", $time, SEQ_LEN);
        $fflush();
        axi_write(32'h0C, 32'd1);            // seq_len = 1
        axi_write(32'h1C, 32'd1);            // decode_mode = 1
        axi_write(32'h20, SEQ_LEN);          // cache_len = 32

        axi_write(32'h00, 32'h1);            // START

        while (dut.u_fsm.state != S_DONE) @(posedge clk);
        $display("[%0t] DECODE TOKEN 1 DONE", $time);
        $fflush();
        @(posedge clk); @(posedge clk);

        // Debug: dump decode 1 output (URAM row 0) and ACT_BASE row 0 from flush HBM
        dump_fd = $fopen("verify/test_data/dec1_output_dump.hex", "w");
        if (dump_fd != 0) begin
            $fwrite(dump_fd, "URAM_ROW0:\n");
            for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                $fwrite(dump_fd, "%064h\n",
                        dut.u_uram.mem[0 * URAM_COL_WORDS_HW + dump_col]);
            end
            $fwrite(dump_fd, "FLUSH_ACT_BASE_ROW0:\n");
            for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                dump_addr = ACT_BASE + dump_col;
                $fwrite(dump_fd, "%064h\n",
                        dut.u_hbm_flush.mem[dump_addr]);
            end
            // Also dump L1 K cache row 32 (first 2 words)
            $fwrite(dump_fd, "L1_K_ROW32:\n");
            for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                dump_addr = KV_BASE + 1 * 16384 + 32 * MODEL_STRIDE_L + dump_col;
                $fwrite(dump_fd, "%064h\n", dut.u_hbm_flush.mem[dump_addr]);
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped decode 1 intermediate output", $time);
            $fflush();
        end

        // ============ INJECT DECODE EMBED 2 ============
        for (de_i = 0; de_i < MODEL_STRIDE_L; de_i = de_i + 1) begin
            dut.u_hbm_pf_act.mem[ACT_BASE + de_i]  = decode_embed_2[de_i];
            dut.u_hbm_pf_wgt.mem[ACT_BASE + de_i]  = decode_embed_2[de_i];
            dut.u_hbm_dma.mem[ACT_BASE + de_i]      = decode_embed_2[de_i];
            dut.u_hbm_flush.mem[ACT_BASE + de_i]    = decode_embed_2[de_i];
            dut.u_uram.mem[0 * URAM_COL_WORDS_HW + de_i] = decode_embed_2[de_i];
        end
        $display("[%0t] Injected decode_embed_2", $time);
        $fflush();

        // ============ PHASE 3: DECODE TOKEN 2 ============
        $display("[%0t] === PHASE 3: DECODE TOKEN 2 (cache_len=%0d) ===", $time, SEQ_LEN + 1);
        $fflush();
        axi_write(32'h20, SEQ_LEN + 1);      // cache_len = 33

        axi_write(32'h00, 32'h1);            // START

        while (dut.u_fsm.state != S_DONE) @(posedge clk);
        $display("[%0t] DECODE TOKEN 2 DONE", $time);
        $fflush();

        $display("[%0t] TEST PASSED: All 3 phases completed", $time);
        $fflush();

        // ============ DUMP RESULTS ============

        // URAM dump (row 0 = decode token 2 output)
        dump_fd = $fopen("verify/test_data/uram_multi_dump.hex", "w");
        if (dump_fd != 0) begin
            for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                $fwrite(dump_fd, "%064h\n",
                        dut.u_uram.mem[0 * URAM_COL_WORDS_HW + dump_col]);
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped URAM (1 row, %0d words)", $time, MODEL_STRIDE_L);
            $fflush();
        end

        // Sparse flush HBM dump:
        //   - Final decode output: ACT_BASE row 0 (1 row)
        //   - Per-layer KV caches: TOTAL_KV_ROWS rows (prefill + 2 decode)
        dump_fd = $fopen("verify/test_data/hbm_flush_multi_dump.hex", "w");
        if (dump_fd != 0) begin
            // Final output: ACT_BASE row 0 only (decode token 2 output)
            for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                dump_addr = ACT_BASE + dump_col;
                $fwrite(dump_fd, "@%08h %064h\n", dump_addr,
                        dut.u_hbm_flush.mem[dump_addr]);
            end

            // Per-layer KV caches: all rows including decode rows
            for (fi = 0; fi < 2; fi = fi + 1) begin
                // K cache (TOTAL_KV_ROWS rows)
                for (dump_row = 0; dump_row < TOTAL_KV_ROWS; dump_row = dump_row + 1) begin
                    for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                        dump_addr = KV_BASE + fi * 16384 + dump_row * MODEL_STRIDE_L + dump_col;
                        $fwrite(dump_fd, "@%08h %064h\n", dump_addr,
                                dut.u_hbm_flush.mem[dump_addr]);
                    end
                end
                // V cache (TOTAL_KV_ROWS rows)
                for (dump_row = 0; dump_row < TOTAL_KV_ROWS; dump_row = dump_row + 1) begin
                    for (dump_col = 0; dump_col < MODEL_STRIDE_L; dump_col = dump_col + 1) begin
                        dump_addr = KV_BASE + fi * 16384 + 8192 + dump_row * MODEL_STRIDE_L + dump_col;
                        $fwrite(dump_fd, "@%08h %064h\n", dump_addr,
                                dut.u_hbm_flush.mem[dump_addr]);
                    end
                end
            end
            $fclose(dump_fd);
            $display("[%0t] Dumped sparse flush HBM (KV %0d rows/layer + decode output)", $time, TOTAL_KV_ROWS);
            $fflush();
        end

        #100;
        $finish;
    end

    // Compact FSM logging — phase + layer boundaries
    reg [4:0] prev_state;
    reg [7:0] prev_layer;
    initial begin prev_state = 0; prev_layer = 0; end

    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.u_fsm.layer_cnt !== prev_layer && dut.u_fsm.state != 0) begin
                $display("[%0t] === Layer %0d started (decode=%0d) ===",
                         $time, dut.u_fsm.layer_cnt, dut.u_fsm.decode_r);
                prev_layer <= dut.u_fsm.layer_cnt;
            end
            prev_state <= dut.u_fsm.state;
        end
    end

    // Flush-to-Load Memory Mirroring
    reg uf_done_prev;
    reg [27:0] saved_flush_base;
    reg [27:0] saved_flush_stride;
    reg [9:0]  saved_flush_rows;
    reg [7:0]  saved_flush_cols;
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
            if (dut.u_fsm.uram_flush_start) begin
                saved_flush_base   <= dut.u_fsm.uram_flush_hbm_base;
                saved_flush_stride <= dut.u_fsm.uram_flush_hbm_stride;
                saved_flush_rows   <= dut.u_fsm.uram_flush_num_rows;
                saved_flush_cols   <= dut.u_fsm.uram_flush_num_col_words;
                flush_params_valid <= 1'b1;
            end

            uf_done_prev <= dut.uf_done;
            if (dut.uf_done && !uf_done_prev && flush_params_valid) begin
                for (mirror_r = 0; mirror_r <= saved_flush_rows; mirror_r = mirror_r + 1) begin
                    for (mirror_c = 0; mirror_c <= saved_flush_cols; mirror_c = mirror_c + 1) begin
                        mirror_addr = saved_flush_base + mirror_r * saved_flush_stride + mirror_c;
                        dut.u_hbm_pf_act.mem[mirror_addr] = dut.u_hbm_flush.mem[mirror_addr];
                        dut.u_hbm_pf_wgt.mem[mirror_addr] = dut.u_hbm_flush.mem[mirror_addr];
                        dut.u_hbm_dma.mem[mirror_addr]    = dut.u_hbm_flush.mem[mirror_addr];
                    end
                end
                flush_params_valid <= 1'b0;
            end
        end
    end

    // Timeout watchdog (scaled with layers, 3 phases)
    initial begin
        #1600000000000;
        $display("[%0t] ERROR: Simulation timeout!", $time);
        $fflush();
        $display("  FSM state: %0d", dut.u_fsm.state);
        $display("  Layer: %0d", dut.u_fsm.layer_cnt);
        $display("  Step idx: %0d", dut.u_fsm.step_idx);
        $display("  TEST FAILED: timeout");
        $fflush();
        $finish;
    end

endmodule
