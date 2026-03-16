// =============================================================================
// tb_tile_loader.v — Testbench for tile_loader
// =============================================================================
// Tests:
//   1. Load a single row (1 row, stride=2) from HBM, readback from local buffer
//   2. Load a full 32-row tile with stride > WORDS_PER_ROW (non-contiguous)
//   3. Load partial tile (8 rows), verify only those rows are loaded
//   4. Back-to-back tile loads (second load overwrites first)
// =============================================================================

`include "defines.vh"

module tb_tile_loader;

    parameter TILE       = 32;
    parameter BUS_W      = 256;
    parameter DATA_W     = 16;
    parameter HBM_ADDR_W = 28;
    parameter ID_W       = 4;
    parameter LEN_W      = 8;
    parameter HBM_DEPTH  = 4096;

    localparam BUS_EL       = BUS_W / DATA_W;
    localparam WORDS_PER_ROW = TILE / BUS_EL;     // 2
    localparam BUF_DEPTH    = TILE * WORDS_PER_ROW; // 64

    reg clk, rst_n;

    // Command interface
    reg                     cmd_valid;
    wire                    cmd_ready;
    reg  [HBM_ADDR_W-1:0]  cmd_hbm_base;
    reg  [5:0]              cmd_tile_rows;
    reg  [HBM_ADDR_W-1:0]  cmd_stride;
    wire                    cmd_done;

    // AXI4 wires (tile_loader ↔ sim_hbm_port)
    wire [ID_W-1:0]        arid;
    wire [HBM_ADDR_W-1:0]  araddr;
    wire [LEN_W-1:0]       arlen;
    wire                    arvalid;
    wire                    arready;
    wire [ID_W-1:0]        rid;
    wire [BUS_W-1:0]       rdata;
    wire [1:0]             rresp;
    wire                    rlast;
    wire                    rvalid;
    wire                    rready;

    // Local read interface
    reg                    local_rd_en;
    reg  [5:0]             local_rd_addr;
    wire [BUS_W-1:0]       local_rd_data;
    wire                   local_rd_valid;

    // ---- DUT: tile_loader ----
    tile_loader #(
        .TILE(TILE), .BUS_W(BUS_W), .DATA_W(DATA_W),
        .HBM_ADDR_W(HBM_ADDR_W), .ID_W(ID_W), .LEN_W(LEN_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_hbm_base(cmd_hbm_base), .cmd_tile_rows(cmd_tile_rows),
        .cmd_stride(cmd_stride), .cmd_done(cmd_done),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp),
        .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .local_rd_en(local_rd_en), .local_rd_addr(local_rd_addr),
        .local_rd_data(local_rd_data), .local_rd_valid(local_rd_valid)
    );

    // ---- HBM stub ----
    // Tie off write channels (not used by tile_loader)
    sim_hbm_port #(
        .DEPTH(HBM_DEPTH), .ADDR_W(HBM_ADDR_W), .DATA_W(BUS_W),
        .ID_W(ID_W), .LEN_W(LEN_W)
    ) u_hbm (
        .clk(clk), .rst_n(rst_n),
        .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rlast(rlast), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        // Write channels tied off
        .s_axi_awid({ID_W{1'b0}}), .s_axi_awaddr({HBM_ADDR_W{1'b0}}),
        .s_axi_awlen({LEN_W{1'b0}}), .s_axi_awvalid(1'b0), .s_axi_awready(),
        .s_axi_wdata({BUS_W{1'b0}}), .s_axi_wlast(1'b0),
        .s_axi_wvalid(1'b0), .s_axi_wready(),
        .s_axi_bid(), .s_axi_bresp(),
        .s_axi_bvalid(), .s_axi_bready(1'b0)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    integer errors, i, row, word, watchdog;
    reg [BUS_W-1:0] expected;

    // ---- Helper: preload HBM memory directly ----
    task preload_hbm;
        input [HBM_ADDR_W-1:0] addr;
        input [BUS_W-1:0]      data;
        begin
            u_hbm.mem[addr] = data;
        end
    endtask

    // ---- Helper: make pattern word from base ----
    function [BUS_W-1:0] make_pattern;
        input integer base;
        integer k;
        begin
            make_pattern = {BUS_W{1'b0}};
            for (k = 0; k < BUS_EL; k = k + 1)
                make_pattern[k*DATA_W +: DATA_W] = base + k;
        end
    endfunction

    // ---- Helper: issue load command and wait for completion ----
    task load_tile;
        input [HBM_ADDR_W-1:0] base;
        input [5:0]             rows;
        input [HBM_ADDR_W-1:0] stride;
        begin
            cmd_hbm_base  = base;
            cmd_tile_rows = rows;
            cmd_stride    = stride;
            cmd_valid     = 1'b1;
            @(posedge clk);
            cmd_valid = 1'b0;

            // Wait for cmd_done
            watchdog = 0;
            while (!cmd_done) begin
                @(posedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 5000) begin
                    $display("TIMEOUT: waiting for cmd_done");
                    $finish;
                end
            end
            @(posedge clk);
        end
    endtask

    // ---- Helper: read one word from local buffer ----
    task read_local;
        input [5:0] addr;
        begin
            local_rd_en   = 1'b1;
            local_rd_addr = addr;
            @(posedge clk);
            local_rd_en = 1'b0;
            @(posedge clk);  // Wait for rd_valid
        end
    endtask

    initial begin
        $display("=== tb_tile_loader ===");
        errors      = 0;
        rst_n       = 0;
        cmd_valid   = 0;
        local_rd_en = 0;
        local_rd_addr = 0;
        cmd_hbm_base  = 0;
        cmd_tile_rows = 0;
        cmd_stride    = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // =============================================================
        // Test 1: Single row load (contiguous, stride = WORDS_PER_ROW)
        // =============================================================
        $display("Test 1: Single row load");
        // Preload HBM: addr 100 and 101 (2 words for 1 row)
        preload_hbm(28'd100, make_pattern(1000));
        preload_hbm(28'd101, make_pattern(2000));

        load_tile(28'd100, 6'd1, WORDS_PER_ROW[HBM_ADDR_W-1:0]);

        // Readback local buffer addr 0 and 1
        read_local(6'd0);
        expected = make_pattern(1000);
        if (local_rd_data !== expected) begin
            $display("FAIL T1: addr=0 got %h exp %h", local_rd_data, expected);
            errors = errors + 1;
        end

        read_local(6'd1);
        expected = make_pattern(2000);
        if (local_rd_data !== expected) begin
            $display("FAIL T1: addr=1 got %h exp %h", local_rd_data, expected);
            errors = errors + 1;
        end

        // =============================================================
        // Test 2: Full 32-row tile, stride=4 (non-contiguous in HBM)
        // =============================================================
        $display("Test 2: Full 32-row tile, stride=4");
        // Preload HBM: base=200, stride=4 words between rows
        // Row i: HBM addr = 200 + i*4, word 0 and word 1
        for (row = 0; row < TILE; row = row + 1) begin
            preload_hbm(200 + row * 4,     make_pattern(row * 100));
            preload_hbm(200 + row * 4 + 1, make_pattern(row * 100 + 50));
        end

        load_tile(28'd200, 6'd32, 28'd4);

        // Verify all 64 words
        for (row = 0; row < TILE; row = row + 1) begin
            for (word = 0; word < WORDS_PER_ROW; word = word + 1) begin
                read_local(row * WORDS_PER_ROW + word);
                if (word == 0)
                    expected = make_pattern(row * 100);
                else
                    expected = make_pattern(row * 100 + 50);
                if (local_rd_data !== expected) begin
                    $display("FAIL T2: row=%0d word=%0d got %h exp %h",
                             row, word, local_rd_data, expected);
                    errors = errors + 1;
                end
            end
        end

        // =============================================================
        // Test 3: Partial tile (8 rows)
        // =============================================================
        $display("Test 3: Partial 8-row tile");
        for (row = 0; row < 8; row = row + 1) begin
            preload_hbm(500 + row * 2, make_pattern(3000 + row * 10));
            preload_hbm(500 + row * 2 + 1, make_pattern(4000 + row * 10));
        end

        load_tile(28'd500, 6'd8, 28'd2);

        for (row = 0; row < 8; row = row + 1) begin
            read_local(row * 2);
            expected = make_pattern(3000 + row * 10);
            if (local_rd_data !== expected) begin
                $display("FAIL T3: row=%0d word=0 got %h exp %h",
                         row, local_rd_data, expected);
                errors = errors + 1;
            end
            read_local(row * 2 + 1);
            expected = make_pattern(4000 + row * 10);
            if (local_rd_data !== expected) begin
                $display("FAIL T3: row=%0d word=1 got %h exp %h",
                         row, local_rd_data, expected);
                errors = errors + 1;
            end
        end

        // =============================================================
        // Test 4: Back-to-back loads (second overwrites first)
        // =============================================================
        $display("Test 4: Back-to-back loads");
        // First load: 4 rows at addr 800
        for (row = 0; row < 4; row = row + 1) begin
            preload_hbm(800 + row * 2, make_pattern(5000 + row));
            preload_hbm(800 + row * 2 + 1, make_pattern(6000 + row));
        end
        load_tile(28'd800, 6'd4, 28'd2);

        // Verify first load
        read_local(6'd0);
        expected = make_pattern(5000);
        if (local_rd_data !== expected) begin
            $display("FAIL T4a: got %h exp %h", local_rd_data, expected);
            errors = errors + 1;
        end

        // Second load: 4 rows at addr 900 (different data)
        for (row = 0; row < 4; row = row + 1) begin
            preload_hbm(900 + row * 2, make_pattern(7000 + row));
            preload_hbm(900 + row * 2 + 1, make_pattern(8000 + row));
        end
        load_tile(28'd900, 6'd4, 28'd2);

        // Verify second load overwrote first
        read_local(6'd0);
        expected = make_pattern(7000);
        if (local_rd_data !== expected) begin
            $display("FAIL T4b: got %h exp %h", local_rd_data, expected);
            errors = errors + 1;
        end
        read_local(6'd1);
        expected = make_pattern(8000);
        if (local_rd_data !== expected) begin
            $display("FAIL T4b: addr=1 got %h exp %h", local_rd_data, expected);
            errors = errors + 1;
        end

        // =============================================================
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("FAILED: %0d errors", errors);
        $finish;
    end

endmodule
