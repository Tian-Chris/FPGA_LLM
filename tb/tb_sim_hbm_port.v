// =============================================================================
// tb_sim_hbm_port.v — Testbench for HBM channel simulation stub
// =============================================================================

`include "defines.vh"

module tb_sim_hbm_port;

    parameter DEPTH  = 1024;
    parameter ADDR_W = 28;
    parameter DATA_W = 256;
    parameter ID_W   = 4;
    parameter LEN_W  = 8;

    reg clk, rst_n;

    // AXI signals
    reg  [ID_W-1:0]   arid, awid;
    reg  [ADDR_W-1:0] araddr, awaddr;
    reg  [LEN_W-1:0]  arlen, awlen;
    reg                arvalid, awvalid;
    wire               arready, awready;
    wire [ID_W-1:0]    rid, bid;
    wire [DATA_W-1:0]  rdata;
    wire [1:0]         rresp, bresp;
    wire               rlast, rvalid, bvalid;
    wire               wready;
    reg                rready, bready;
    reg  [DATA_W-1:0]  wdata;
    reg                wlast, wvalid;

    sim_hbm_port #(
        .DEPTH(DEPTH), .ADDR_W(ADDR_W), .DATA_W(DATA_W),
        .ID_W(ID_W), .LEN_W(LEN_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rlast(rlast), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wlast(wlast),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bid(bid), .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid), .s_axi_bready(bready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors, i, watchdog;
    reg [DATA_W-1:0] read_buf [0:15];
    integer read_cnt;

    // Direct memory access for checking (sim only)
    task write_mem_direct;
        input [ADDR_W-1:0] addr;
        input [DATA_W-1:0] data;
        begin
            dut.mem[addr] = data;
        end
    endtask

    task read_mem_direct;
        input  [ADDR_W-1:0] addr;
        output [DATA_W-1:0] data;
        begin
            data = dut.mem[addr];
        end
    endtask

    // ---- AXI write burst (direct mem + AXI write for protocol test) ----
    task axi_write_burst;
        input [ADDR_W-1:0] addr;
        input [LEN_W-1:0]  len;
        input integer       base_val;
        integer beat;
        begin
            // Write address phase
            awid    <= 4'd1;
            awaddr  <= addr;
            awlen   <= len;
            awvalid <= 1'b1;
            @(posedge clk);  // DUT samples: awvalid=1, awready=1 → accepted
            awvalid <= 1'b0;
            @(posedge clk);  // DUT now in WR_DATA, wready=1

            // Write data phase
            for (beat = 0; beat <= len; beat = beat + 1) begin
                wdata  <= base_val + beat;
                wlast  <= (beat == len) ? 1'b1 : 1'b0;
                wvalid <= 1'b1;
                @(posedge clk);  // DUT samples: wvalid=1, wready=1 → beat accepted
            end
            wvalid <= 1'b0;
            wlast  <= 1'b0;

            // Write response phase
            bready <= 1'b1;
            @(posedge clk);  // DUT in WR_RESP, bvalid=1
            @(posedge clk);  // bvalid && bready → accepted
            bready <= 1'b0;
            @(posedge clk);  // Let it settle
        end
    endtask

    // ---- AXI read burst ----
    task axi_read_burst;
        input [ADDR_W-1:0] addr;
        input [LEN_W-1:0]  len;
        reg done;
        begin
            // Read address phase
            arid    <= 4'd2;
            araddr  <= addr;
            arlen   <= len;
            arvalid <= 1'b1;
            @(posedge clk);  // DUT samples: arvalid=1, arready=1 → accepted
            #1;
            $display("  AR accept: arvalid=%0d arready=%0d rd_state=%0d", arvalid, arready, dut.rd_state);
            arvalid <= 1'b0;

            // DUT goes to RD_LATENCY for 2 cycles, then RD_BURST
            rready   <= 1'b1;
            read_cnt = 0;
            done     = 0;
            watchdog = 0;

            while (!done) begin
                @(posedge clk);
                #1;
                if (watchdog < 5 || watchdog > 95)
                    $display("  R[%0d]: rvalid=%0d rlast=%0d arready=%0d arvalid=%0d rd_state=%0d",
                             watchdog, rvalid, rlast, arready, arvalid, dut.rd_state);
                // After NBA: check rvalid (it's a registered output)
                if (rvalid) begin
                    read_buf[read_cnt] = rdata;
                    read_cnt = read_cnt + 1;
                    if (rlast) done = 1;
                end
                watchdog = watchdog + 1;
                if (watchdog > 100) begin
                    $display("TIMEOUT: R data after %0d cycles", watchdog);
                    $finish;
                end
            end

            // Keep rready=1 until DUT finishes processing rlast and returns
            // to RD_IDLE (rvalid goes low)
            done = 0; watchdog = 0;
            while (!done) begin
                @(posedge clk);
                #1;
                if (!rvalid) done = 1;
                watchdog = watchdog + 1;
                if (watchdog > 100) begin
                    $display("TIMEOUT: R drain after %0d cycles", watchdog);
                    $finish;
                end
            end
            rready <= 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        $display("=== tb_sim_hbm_port ===");
        errors = 0; rst_n = 0;
        arvalid = 0; rready = 0; awvalid = 0;
        wvalid = 0; wlast = 0; bready = 0;
        arid = 0; araddr = 0; arlen = 0;
        awid = 0; awaddr = 0; awlen = 0;
        wdata = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // -----------------------------------------------------------------
        // Test 1: Direct memory write + AXI read
        // -----------------------------------------------------------------
        $display("Test 1: Direct write + AXI read");
        write_mem_direct(28'd10, 256'hDEAD_BEEF);
        axi_read_burst(28'd10, 8'd0);
        if (read_buf[0] !== 256'hDEAD_BEEF) begin
            $display("FAIL: got %h exp DEAD_BEEF", read_buf[0]);
            errors = errors + 1;
        end

        // -----------------------------------------------------------------
        // Test 2: AXI write + direct memory verify
        // -----------------------------------------------------------------
        $display("Test 2: AXI write + direct verify");
        axi_write_burst(28'd20, 8'd0, 32'h0AFE_0000);
        begin
            reg [DATA_W-1:0] readback;
            read_mem_direct(28'd20, readback);
            if (readback !== 256'h0AFE_0000) begin
                $display("FAIL: written %h exp 0AFE_0000", readback);
                errors = errors + 1;
            end
        end

        // -----------------------------------------------------------------
        // Test 3: AXI burst write + AXI burst read (4 beats)
        // -----------------------------------------------------------------
        $display("Test 3: 4-beat burst round-trip");
        axi_write_burst(28'd100, 8'd3, 32'h1000);
        axi_read_burst(28'd100, 8'd3);
        for (i = 0; i < 4; i = i + 1) begin
            if (read_buf[i] !== (256'h1000 + i)) begin
                $display("FAIL: burst[%0d] got %h exp %h", i, read_buf[i], 256'h1000 + i);
                errors = errors + 1;
            end
        end

        // -----------------------------------------------------------------
        // Test 4: Back-to-back writes + reads
        // -----------------------------------------------------------------
        $display("Test 4: Back-to-back transactions");
        $display("  T4: starting write 1");
        axi_write_burst(28'd200, 8'd1, 32'hAAAA);
        $display("  T4: write 1 done, starting write 2");
        axi_write_burst(28'd202, 8'd1, 32'hBBBB);
        $display("  T4: write 2 done, starting read 1");

        axi_read_burst(28'd200, 8'd1);
        if (read_buf[0] !== 256'hAAAA || read_buf[1] !== 256'hAAAB) begin
            $display("FAIL: b2b pair 1 got %h %h", read_buf[0], read_buf[1]);
            errors = errors + 1;
        end
        axi_read_burst(28'd202, 8'd1);
        if (read_buf[0] !== 256'hBBBB || read_buf[1] !== 256'hBBBC) begin
            $display("FAIL: b2b pair 2 got %h %h", read_buf[0], read_buf[1]);
            errors = errors + 1;
        end

        // -----------------------------------------------------------------
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("FAILED: %0d errors", errors);
        $finish;
    end

endmodule
