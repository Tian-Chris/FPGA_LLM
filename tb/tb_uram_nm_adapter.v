// =============================================================================
// tb_uram_nm_adapter.v — Testbench for uram_nm_adapter
// =============================================================================
// Tests: 1) cache miss/hit, 2) write merge/flush, 3) read-after-write
//        4) cfg_col_bits switching
// =============================================================================

`include "defines.vh"

module tb_uram_nm_adapter;

    localparam ROW_W     = 10;
    localparam COL_W     = 8;
    localparam BUS_W     = 256;
    localparam DATA_W    = 16;
    localparam SCALAR_AW = 16;
    localparam BUS_EL    = BUS_W / DATA_W;  // 16

    reg                     clk;
    reg                     rst_n;
    reg  [3:0]              cfg_col_bits;

    reg                     rd_en;
    reg  [SCALAR_AW-1:0]   rd_addr;
    wire [DATA_W-1:0]       rd_data;
    wire                    rd_valid;

    reg                     wr_en;
    reg  [SCALAR_AW-1:0]   wr_addr;
    reg  [DATA_W-1:0]       wr_data;

    reg                     flush;
    wire                    flush_done;

    wire                    uram_rd_en;
    wire [ROW_W-1:0]        uram_rd_row;
    wire [COL_W-1:0]        uram_rd_col_word;
    wire [BUS_W-1:0]        uram_rd_data;
    wire                    uram_rd_valid;

    wire                    uram_wr_en;
    wire [ROW_W-1:0]        uram_wr_row;
    wire [COL_W-1:0]        uram_wr_col_word;
    wire [BUS_W-1:0]        uram_wr_data;

    // =========================================================================
    // DUT
    // =========================================================================
    uram_nm_adapter #(
        .ROW_W(ROW_W), .COL_W(COL_W), .BUS_W(BUS_W),
        .DATA_W(DATA_W), .SCALAR_AW(SCALAR_AW)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_col_bits(cfg_col_bits),
        .rd_en(rd_en), .rd_addr(rd_addr),
        .rd_data(rd_data), .rd_valid(rd_valid),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .flush(flush), .flush_done(flush_done),
        .uram_rd_en(uram_rd_en), .uram_rd_row(uram_rd_row),
        .uram_rd_col_word(uram_rd_col_word),
        .uram_rd_data(uram_rd_data), .uram_rd_valid(uram_rd_valid),
        .uram_wr_en(uram_wr_en), .uram_wr_row(uram_wr_row),
        .uram_wr_col_word(uram_wr_col_word), .uram_wr_data(uram_wr_data)
    );

    // =========================================================================
    // Backing URAM model (simple 1-cycle read latency register array)
    // =========================================================================
    localparam URAM_ROWS = 1024;
    localparam URAM_WORDS = 256;
    reg [BUS_W-1:0] uram_mem [0:URAM_ROWS * URAM_WORDS - 1];

    reg [BUS_W-1:0] uram_rd_data_r;
    reg              uram_rd_valid_r;

    assign uram_rd_data  = uram_rd_data_r;
    assign uram_rd_valid = uram_rd_valid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uram_rd_data_r  <= {BUS_W{1'b0}};
            uram_rd_valid_r <= 1'b0;
        end else begin
            uram_rd_valid_r <= uram_rd_en;
            if (uram_rd_en) begin
                uram_rd_data_r <= uram_mem[uram_rd_row * URAM_WORDS + uram_rd_col_word];
            end
        end
    end

    // Write port
    always @(posedge clk) begin
        if (uram_wr_en) begin
            uram_mem[uram_wr_row * URAM_WORDS + uram_wr_col_word] <= uram_wr_data;
        end
    end

    // =========================================================================
    // Clock generation
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // Test helpers
    // =========================================================================
    integer pass_count;
    integer fail_count;

    task check;
        input [DATA_W-1:0] expected;
        input [255:0] msg;  // Packed string
        begin
            if (rd_data === expected) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: expected %0d, got %0d", expected, rd_data);
            end
        end
    endtask

    // =========================================================================
    // Tests
    // =========================================================================
    integer i;
    integer test_num;

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0;
        rd_en = 0; rd_addr = 0;
        wr_en = 0; wr_addr = 0; wr_data = 0;
        flush = 0;
        cfg_col_bits = 4'd10;  // MODEL_DIM=1024

        // Init URAM with known pattern
        for (i = 0; i < URAM_ROWS * URAM_WORDS; i = i + 1)
            uram_mem[i] = {BUS_W{1'b0}};

        // Pre-load some URAM data for read tests
        // Row 0, col_word 0: elements 0-15 = values 100-115
        for (i = 0; i < BUS_EL; i = i + 1) begin
            uram_mem[0][i*DATA_W +: DATA_W] = 100 + i;
        end
        // Row 0, col_word 1: elements 0-15 = values 200-215
        for (i = 0; i < BUS_EL; i = i + 1) begin
            uram_mem[1][i*DATA_W +: DATA_W] = 200 + i;
        end
        // Row 1, col_word 0: elements 0-15 = values 300-315
        for (i = 0; i < BUS_EL; i = i + 1) begin
            uram_mem[URAM_WORDS][i*DATA_W +: DATA_W] = 300 + i;
        end

        #20;
        rst_n = 1;
        #10;

        // =================================================================
        // Test 1: Cache miss then cache hit
        // =================================================================
        test_num = 1;
        $display("Test %0d: Cache miss then hit", test_num);

        // Read addr 0 (row=0, col_word=0, el=0) — should be cache miss (2 cycles)
        @(posedge clk);
        rd_en   <= 1;
        rd_addr <= 16'd0;  // With cfg_col_bits=10: row=0, col_word=0, el=0
        @(posedge clk);
        rd_en <= 0;

        // Wait for rd_valid
        @(posedge clk);  // URAM read latency
        while (!rd_valid) @(posedge clk);
        check(16'd100, "miss read el 0");

        // Read addr 3 (row=0, col_word=0, el=3) — should be cache hit (1 cycle)
        @(posedge clk);
        rd_en   <= 1;
        rd_addr <= 16'd3;
        @(posedge clk);
        rd_en <= 0;
        // Cache hit should give rd_valid same cycle as we clear rd_en
        // Actually rd_valid comes 1 cycle after rd_en is asserted (registered)
        while (!rd_valid) @(posedge clk);
        check(16'd103, "hit read el 3");

        $display("  Test %0d done", test_num);

        // =================================================================
        // Test 2: Write merge and flush
        // =================================================================
        test_num = 2;
        $display("Test %0d: Write merge and flush", test_num);

        // Write to addr 1024 (row=1, col_word=0, el=0)
        @(posedge clk);
        wr_en   <= 1;
        wr_addr <= 16'd1024;  // col_bits=10: row=1, col_word=0, el=0
        wr_data <= 16'd42;
        @(posedge clk);
        // Write to addr 1025 (row=1, col_word=0, el=1) — merge
        wr_addr <= 16'd1025;
        wr_data <= 16'd43;
        @(posedge clk);
        // Write to addr 1026 (row=1, col_word=0, el=2) — merge
        wr_addr <= 16'd1026;
        wr_data <= 16'd44;
        @(posedge clk);
        wr_en <= 0;

        // Flush to commit write buffer to URAM
        @(posedge clk);
        flush <= 1;
        @(posedge clk);
        flush <= 0;
        while (!flush_done) @(posedge clk);

        // Verify URAM got the data: read back from URAM model directly
        @(posedge clk);
        if (uram_mem[URAM_WORDS][0*DATA_W +: DATA_W] !== 16'd42) begin
            $display("FAIL: uram_mem write merge el 0, got %0d", uram_mem[URAM_WORDS][0*DATA_W +: DATA_W]);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end
        if (uram_mem[URAM_WORDS][1*DATA_W +: DATA_W] !== 16'd43) begin
            $display("FAIL: uram_mem write merge el 1, got %0d", uram_mem[URAM_WORDS][1*DATA_W +: DATA_W]);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end
        if (uram_mem[URAM_WORDS][2*DATA_W +: DATA_W] !== 16'd44) begin
            $display("FAIL: uram_mem write merge el 2, got %0d", uram_mem[URAM_WORDS][2*DATA_W +: DATA_W]);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end

        $display("  Test %0d done", test_num);

        // =================================================================
        // Test 3: Read-after-write (from write buffer)
        // =================================================================
        test_num = 3;
        $display("Test %0d: Read-after-write from write buffer", test_num);

        // Write to addr 2048 (row=2, col_word=0, el=0)
        @(posedge clk);
        wr_en   <= 1;
        wr_addr <= 16'd2048;
        wr_data <= 16'd99;
        @(posedge clk);
        wr_en <= 0;

        // Read same address — should hit write buffer
        @(posedge clk);
        rd_en   <= 1;
        rd_addr <= 16'd2048;
        @(posedge clk);
        rd_en <= 0;
        while (!rd_valid) @(posedge clk);
        check(16'd99, "read from write buffer");

        // Flush the write buffer
        @(posedge clk);
        flush <= 1;
        @(posedge clk);
        flush <= 0;
        while (!flush_done) @(posedge clk);

        $display("  Test %0d done", test_num);

        // =================================================================
        // Test 4: cfg_col_bits switching (seq_len=128, col_bits=7)
        // =================================================================
        test_num = 4;
        $display("Test %0d: cfg_col_bits=7 (seq_len addressing)", test_num);

        cfg_col_bits = 4'd7;
        // With col_bits=7: row = addr[15:7], col_word = addr[6:4], el = addr[3:0]
        // addr 128 = row 1, col_word 0, el 0
        // Pre-load row 1, col_word 0 in URAM
        for (i = 0; i < BUS_EL; i = i + 1) begin
            uram_mem[URAM_WORDS][i*DATA_W +: DATA_W] = 500 + i;
        end

        // Read addr 128 — row=1, col_word=0, el=0
        @(posedge clk);
        rd_en   <= 1;
        rd_addr <= 16'd128;
        @(posedge clk);
        rd_en <= 0;
        while (!rd_valid) @(posedge clk);
        check(16'd500, "col_bits=7, el 0");

        // Read addr 131 — row=1, col_word=0, el=3 (cache hit)
        @(posedge clk);
        rd_en   <= 1;
        rd_addr <= 16'd131;
        @(posedge clk);
        rd_en <= 0;
        while (!rd_valid) @(posedge clk);
        check(16'd503, "col_bits=7, el 3 hit");

        $display("  Test %0d done", test_num);

        // =================================================================
        // Summary
        // =================================================================
        #20;
        $display("");
        $display("========================================");
        $display("  PASS: %0d  FAIL: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED");
        $display("========================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
