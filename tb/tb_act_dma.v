// =============================================================================
// tb_act_dma.v — Testbench for act_dma scalar-to-AXI bridge
// =============================================================================
//
// Tests the 1-word read cache and write buffer with flush, verifying:
//   1. Sequential read (cache hit path)
//   2. Read miss (different word triggers AXI fetch)
//   3. Sequential write + flush
//   4. Write word boundary cross (auto-flush)
//
// Instantiates act_dma (DUT) and sim_hbm_port (HBM backing store).
// Compatible with Verilator: no X/Z, no SystemVerilog, no disable.
// =============================================================================

`include "defines.vh"

module tb_act_dma;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter DATA_W     = 16;
    parameter BUS_W      = 256;
    parameter HBM_ADDR_W = 28;
    parameter SCALAR_AW  = 16;
    parameter ID_W       = 4;
    parameter LEN_W      = 8;
    parameter BUS_EL     = 16;       // BUS_W / DATA_W
    parameter EL_IDX_W   = 4;        // $clog2(BUS_EL)
    parameter WORD_AW    = 12;       // SCALAR_AW - EL_IDX_W
    parameter HBM_DEPTH  = 4096;

    // =========================================================================
    // Clock and reset
    // =========================================================================
    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // DUT scalar-side signals
    // =========================================================================
    reg  [HBM_ADDR_W-1:0] cfg_rd_base;
    reg  [HBM_ADDR_W-1:0] cfg_wr_base;
    reg                    rd_en;
    reg  [SCALAR_AW-1:0]  rd_addr;
    wire [DATA_W-1:0]     rd_data;
    wire                   rd_valid;
    reg                    wr_en;
    reg  [SCALAR_AW-1:0]  wr_addr;
    reg  [DATA_W-1:0]     wr_data;
    reg                    flush;
    wire                   flush_done;

    // =========================================================================
    // AXI interconnect signals (DUT master <-> HBM slave)
    // =========================================================================
    wire [ID_W-1:0]       axi_arid;
    wire [HBM_ADDR_W-1:0] axi_araddr;
    wire [LEN_W-1:0]      axi_arlen;
    wire                   axi_arvalid;
    wire                   axi_arready;

    wire [ID_W-1:0]       axi_rid;
    wire [BUS_W-1:0]      axi_rdata;
    wire [1:0]            axi_rresp;
    wire                   axi_rlast;
    wire                   axi_rvalid;
    wire                   axi_rready;

    wire [ID_W-1:0]       axi_awid;
    wire [HBM_ADDR_W-1:0] axi_awaddr;
    wire [LEN_W-1:0]      axi_awlen;
    wire                   axi_awvalid;
    wire                   axi_awready;

    wire [BUS_W-1:0]      axi_wdata;
    wire                   axi_wlast;
    wire                   axi_wvalid;
    wire                   axi_wready;

    wire [ID_W-1:0]       axi_bid;
    wire [1:0]            axi_bresp;
    wire                   axi_bvalid;
    wire                   axi_bready;

    // =========================================================================
    // DUT: act_dma
    // =========================================================================
    act_dma #(
        .DATA_W     (DATA_W),
        .BUS_W      (BUS_W),
        .HBM_ADDR_W (HBM_ADDR_W),
        .SCALAR_AW  (SCALAR_AW),
        .ID_W       (ID_W),
        .LEN_W      (LEN_W)
    ) u_dut (
        .clk        (clk),
        .rst_n      (rst_n),

        .cfg_rd_base (cfg_rd_base),
        .cfg_wr_base (cfg_wr_base),

        .rd_en      (rd_en),
        .rd_addr    (rd_addr),
        .rd_data    (rd_data),
        .rd_valid   (rd_valid),

        .wr_en      (wr_en),
        .wr_addr    (wr_addr),
        .wr_data    (wr_data),

        .flush      (flush),
        .flush_done (flush_done),

        .m_axi_arid    (axi_arid),
        .m_axi_araddr  (axi_araddr),
        .m_axi_arlen   (axi_arlen),
        .m_axi_arvalid (axi_arvalid),
        .m_axi_arready (axi_arready),

        .m_axi_rid     (axi_rid),
        .m_axi_rdata   (axi_rdata),
        .m_axi_rresp   (axi_rresp),
        .m_axi_rlast   (axi_rlast),
        .m_axi_rvalid  (axi_rvalid),
        .m_axi_rready  (axi_rready),

        .m_axi_awid    (axi_awid),
        .m_axi_awaddr  (axi_awaddr),
        .m_axi_awlen   (axi_awlen),
        .m_axi_awvalid (axi_awvalid),
        .m_axi_awready (axi_awready),

        .m_axi_wdata   (axi_wdata),
        .m_axi_wlast   (axi_wlast),
        .m_axi_wvalid  (axi_wvalid),
        .m_axi_wready  (axi_wready),

        .m_axi_bid     (axi_bid),
        .m_axi_bresp   (axi_bresp),
        .m_axi_bvalid  (axi_bvalid),
        .m_axi_bready  (axi_bready)
    );

    // =========================================================================
    // HBM backing store
    // =========================================================================
    sim_hbm_port #(
        .DEPTH  (HBM_DEPTH),
        .ADDR_W (HBM_ADDR_W),
        .DATA_W (BUS_W),
        .ID_W   (ID_W),
        .LEN_W  (LEN_W)
    ) u_hbm (
        .clk    (clk),
        .rst_n  (rst_n),

        .s_axi_arid    (axi_arid),
        .s_axi_araddr  (axi_araddr),
        .s_axi_arlen   (axi_arlen),
        .s_axi_arvalid (axi_arvalid),
        .s_axi_arready (axi_arready),

        .s_axi_rid     (axi_rid),
        .s_axi_rdata   (axi_rdata),
        .s_axi_rresp   (axi_rresp),
        .s_axi_rlast   (axi_rlast),
        .s_axi_rvalid  (axi_rvalid),
        .s_axi_rready  (axi_rready),

        .s_axi_awid    (axi_awid),
        .s_axi_awaddr  (axi_awaddr),
        .s_axi_awlen   (axi_awlen),
        .s_axi_awvalid (axi_awvalid),
        .s_axi_awready (axi_awready),

        .s_axi_wdata   (axi_wdata),
        .s_axi_wlast   (axi_wlast),
        .s_axi_wvalid  (axi_wvalid),
        .s_axi_wready  (axi_wready),

        .s_axi_bid     (axi_bid),
        .s_axi_bresp   (axi_bresp),
        .s_axi_bvalid  (axi_bvalid),
        .s_axi_bready  (axi_bready)
    );

    // =========================================================================
    // Testbench state
    // =========================================================================
    integer errors;
    integer watchdog;

    // =========================================================================
    // Helper task: scalar_read
    //   Assert rd_en for 1 cycle, then wait for rd_valid with timeout.
    //   Note: in simulation, <= in initial blocks behaves as blocking =,
    //   so we use blocking assignments and careful timing to ensure rd_en
    //   is sampled high at exactly one posedge.
    // =========================================================================
    task scalar_read;
        input  [SCALAR_AW-1:0] addr;
        output [DATA_W-1:0]    data;
        output                 ok;
        integer wd;
        reg     got_valid;
        begin
            // Set up address and enable BEFORE the posedge
            rd_addr = addr;
            rd_en   = 1;
            @(posedge clk);
            // DUT samples rd_en=1 at this posedge (registers rd_valid for next cycle)
            #1;
            rd_en = 0;

            // Now wait for rd_valid (1 cycle for hit, more for miss)
            got_valid = 0;
            wd = 0;
            // Check if rd_valid already came (cache hit: DUT sets rd_valid
            // in same posedge as sampling rd_en, visible after NBA settle)
            if (rd_valid) begin
                data = rd_data;
                got_valid = 1;
            end
            while (!got_valid) begin
                @(posedge clk);
                #1;
                if (rd_valid) begin
                    data = rd_data;
                    got_valid = 1;
                end
                wd = wd + 1;
                if (wd > 200) begin
                    $display("TIMEOUT: scalar_read addr=%0d after %0d cycles", addr, wd);
                    data = {DATA_W{1'b0}};
                    got_valid = 1;
                    ok = 0;
                end
            end
            if (wd <= 200) ok = 1;
        end
    endtask

    // =========================================================================
    // Helper task: scalar_write
    //   Assert wr_en for 1 cycle.
    // =========================================================================
    task scalar_write;
        input [SCALAR_AW-1:0] addr;
        input [DATA_W-1:0]    data;
        begin
            wr_addr = addr;
            wr_data = data;
            wr_en   = 1;
            @(posedge clk);
            #1;
            wr_en = 0;
        end
    endtask

    // =========================================================================
    // Helper task: do_flush
    //   Assert flush for 1 cycle, wait for flush_done with timeout.
    // =========================================================================
    task do_flush;
        output ok;
        integer wd;
        reg     got_done;
        begin
            flush = 1;
            @(posedge clk);
            #1;
            flush = 0;

            // Check if flush_done already asserted (buffer was clean)
            got_done = 0;
            wd = 0;
            if (flush_done) begin
                got_done = 1;
            end
            while (!got_done) begin
                @(posedge clk);
                #1;
                if (flush_done) begin
                    got_done = 1;
                end
                wd = wd + 1;
                if (wd > 200) begin
                    $display("TIMEOUT: do_flush after %0d cycles", wd);
                    got_done = 1;
                    ok = 0;
                end
            end
            if (wd <= 200) ok = 1;
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    integer i;
    reg [DATA_W-1:0]  rd_val;
    reg               rd_ok;
    reg               flush_ok;
    reg [DATA_W-1:0]  expected;
    reg [BUS_W-1:0]   hbm_word;
    reg [DATA_W-1:0]  elem;

    initial begin
        $display("=== tb_act_dma ===");
        errors = 0;

        // Initialize all inputs
        rst_n       = 0;
        rd_en       = 0;
        rd_addr     = 0;
        wr_en       = 0;
        wr_addr     = 0;
        wr_data     = 0;
        flush       = 0;
        cfg_rd_base = 28'd256;   // HBM word address base for reads
        cfg_wr_base = 28'd512;   // HBM word address base for writes

        // Reset
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // =================================================================
        // Test 1: Sequential read (cache hit)
        // =================================================================
        // Preload HBM word at cfg_rd_base + 0 = addr 256
        // 16 elements, each 16 bits: element i = 16'hA000 + i
        $display("");
        $display("Test 1: Sequential read (cache hit)");

        hbm_word = {BUS_W{1'b0}};
        for (i = 0; i < BUS_EL; i = i + 1) begin
            hbm_word[i * DATA_W +: DATA_W] = 16'hA000 + i[DATA_W-1:0];
        end
        u_hbm.mem[256] = hbm_word;

        // Read scalar addr 0 -- this is a cache miss (fetches from HBM)
        scalar_read(16'd0, rd_val, rd_ok);
        if (!rd_ok) begin
            $display("  FAIL: read addr 0 timed out");
            errors = errors + 1;
        end else begin
            expected = 16'hA000;
            if (rd_val !== expected) begin
                $display("  FAIL: addr 0: got %h exp %h", rd_val, expected);
                errors = errors + 1;
            end else begin
                $display("  PASS: addr 0: got %h (cache miss)", rd_val);
            end
        end

        // Read scalar addrs 1-15 -- these should be cache hits (faster)
        for (i = 1; i < BUS_EL; i = i + 1) begin
            scalar_read(i[SCALAR_AW-1:0], rd_val, rd_ok);
            if (!rd_ok) begin
                $display("  FAIL: read addr %0d timed out", i);
                errors = errors + 1;
            end else begin
                expected = 16'hA000 + i[DATA_W-1:0];
                if (rd_val !== expected) begin
                    $display("  FAIL: addr %0d: got %h exp %h", i, rd_val, expected);
                    errors = errors + 1;
                end else begin
                    $display("  PASS: addr %0d: got %h (cache hit)", i, rd_val);
                end
            end
        end

        repeat (5) @(posedge clk);

        // =================================================================
        // Test 2: Read miss (different word)
        // =================================================================
        // Preload HBM word at cfg_rd_base + 1 = addr 257
        // element i = 16'hB000 + i
        $display("");
        $display("Test 2: Read miss (different word)");

        hbm_word = {BUS_W{1'b0}};
        for (i = 0; i < BUS_EL; i = i + 1) begin
            hbm_word[i * DATA_W +: DATA_W] = 16'hB000 + i[DATA_W-1:0];
        end
        u_hbm.mem[257] = hbm_word;

        // Read scalar addr 16 -> word addr 1 -> HBM addr cfg_rd_base + 1 = 257
        // Element index = 16 % 16 = 0
        scalar_read(16'd16, rd_val, rd_ok);
        if (!rd_ok) begin
            $display("  FAIL: read addr 16 timed out");
            errors = errors + 1;
        end else begin
            expected = 16'hB000;
            if (rd_val !== expected) begin
                $display("  FAIL: addr 16: got %h exp %h", rd_val, expected);
                errors = errors + 1;
            end else begin
                $display("  PASS: addr 16: got %h (cache miss, new word)", rd_val);
            end
        end

        // Also verify another element in the same word (should be hit now)
        scalar_read(16'd21, rd_val, rd_ok);
        if (!rd_ok) begin
            $display("  FAIL: read addr 21 timed out");
            errors = errors + 1;
        end else begin
            // addr 21: word 1, element 5 -> 16'hB005
            expected = 16'hB005;
            if (rd_val !== expected) begin
                $display("  FAIL: addr 21: got %h exp %h", rd_val, expected);
                errors = errors + 1;
            end else begin
                $display("  PASS: addr 21: got %h (cache hit after miss)", rd_val);
            end
        end

        repeat (5) @(posedge clk);

        // =================================================================
        // Test 3: Sequential write + flush
        // =================================================================
        // Write scalar addrs 0-15 with values 16'hC000 + i
        // All go to word 0 -> HBM addr cfg_wr_base + 0 = 512
        // Then flush and verify HBM content
        $display("");
        $display("Test 3: Sequential write + flush");

        for (i = 0; i < BUS_EL; i = i + 1) begin
            scalar_write(i[SCALAR_AW-1:0], 16'hC000 + i[DATA_W-1:0]);
            // Allow 1 idle cycle between writes for AXI state to settle
            @(posedge clk);
        end

        repeat (2) @(posedge clk);

        // Flush to push write buffer to HBM
        do_flush(flush_ok);
        if (!flush_ok) begin
            $display("  FAIL: flush timed out");
            errors = errors + 1;
        end

        repeat (2) @(posedge clk);

        // Verify HBM word at address 512 (cfg_wr_base + 0)
        hbm_word = u_hbm.mem[512];
        for (i = 0; i < BUS_EL; i = i + 1) begin
            elem = hbm_word[i * DATA_W +: DATA_W];
            expected = 16'hC000 + i[DATA_W-1:0];
            if (elem !== expected) begin
                $display("  FAIL: HBM word[512] elem %0d: got %h exp %h", i, elem, expected);
                errors = errors + 1;
            end else begin
                $display("  PASS: HBM word[512] elem %0d: %h", i, elem);
            end
        end

        repeat (5) @(posedge clk);

        // =================================================================
        // Test 4: Write word boundary cross (auto-flush)
        // =================================================================
        // Write to scalar addr 0 (word 0) with value 16'hD000
        // Then write to scalar addr 16 (word 1) with value 16'hE000
        // The second write should trigger an auto-flush of word 0 to HBM
        // Then explicitly flush word 1
        // Verify both HBM words
        $display("");
        $display("Test 4: Write word boundary cross (auto-flush)");

        // Write elem 0 of word 0
        scalar_write(16'd0, 16'hD000);
        repeat (2) @(posedge clk);

        // Write elem 0 of word 1 -- triggers auto-flush of word 0
        scalar_write(16'd16, 16'hE000);

        // Wait for auto-flush AXI transaction to complete
        // The DUT enters AX_WR_AW -> AX_WR_DATA -> AX_WR_RESP -> AX_IDLE
        watchdog = 0;
        while (u_dut.ax_state !== 3'd0 && watchdog < 200) begin
            @(posedge clk);
            watchdog = watchdog + 1;
        end
        if (watchdog >= 200) begin
            $display("  FAIL: auto-flush AXI transaction timed out");
            errors = errors + 1;
        end

        repeat (2) @(posedge clk);

        // Verify HBM word at cfg_wr_base + 0 = 512 (auto-flushed word 0)
        hbm_word = u_hbm.mem[512];
        elem = hbm_word[0 * DATA_W +: DATA_W];
        expected = 16'hD000;
        if (elem !== expected) begin
            $display("  FAIL: auto-flush word 0 elem 0: got %h exp %h", elem, expected);
            errors = errors + 1;
        end else begin
            $display("  PASS: auto-flush word 0 elem 0: %h", elem);
        end

        // Now explicitly flush word 1
        do_flush(flush_ok);
        if (!flush_ok) begin
            $display("  FAIL: explicit flush of word 1 timed out");
            errors = errors + 1;
        end

        repeat (2) @(posedge clk);

        // Verify HBM word at cfg_wr_base + 1 = 513 (explicitly flushed word 1)
        hbm_word = u_hbm.mem[513];
        elem = hbm_word[0 * DATA_W +: DATA_W];
        expected = 16'hE000;
        if (elem !== expected) begin
            $display("  FAIL: explicit flush word 1 elem 0: got %h exp %h", elem, expected);
            errors = errors + 1;
        end else begin
            $display("  PASS: explicit flush word 1 elem 0: %h", elem);
        end

        // =================================================================
        // Summary
        // =================================================================
        $display("");
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("FAILED: %0d errors", errors);
        $finish;
    end

endmodule
