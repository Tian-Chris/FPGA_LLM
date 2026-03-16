// =============================================================================
// sim_hbm_port.v — HBM Channel Simulation Stub
// =============================================================================
//
// SIMULATION ONLY — replaced by Vivado HBM IP + AXI DataMover in synthesis.
//
// Simplified AXI4 read/write interface backed by a reg array.
// Configurable latency model: RD_LATENCY_CYCLES initial latency, then 1 beat/cycle.
// Supports $readmemh for preloading test data.
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module sim_hbm_port #(
    parameter DEPTH      = 65536,           // Words (256-bit each), default 2MB
    parameter ADDR_W     = 28,              // HBM word address width
    parameter DATA_W     = 256,             // 256-bit data bus
    parameter ID_W       = 4,               // AXI ID width
    parameter LEN_W      = 8,               // AXI burst length field width
    parameter INIT_FILE  = "",              // Optional $readmemh file
    parameter RD_LATENCY_CYCLES = 2        // Initial read latency (cycles, min 2)
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // -----------------------------------------------------------------
    // AXI4 Read Address Channel (AR)
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]      s_axi_arid,
    input  wire [ADDR_W-1:0]    s_axi_araddr,
    input  wire [LEN_W-1:0]     s_axi_arlen,      // Burst length - 1
    input  wire                 s_axi_arvalid,
    output reg                  s_axi_arready,

    // -----------------------------------------------------------------
    // AXI4 Read Data Channel (R)
    // -----------------------------------------------------------------
    output reg  [ID_W-1:0]      s_axi_rid,
    output reg  [DATA_W-1:0]    s_axi_rdata,
    output reg  [1:0]           s_axi_rresp,
    output reg                  s_axi_rlast,
    output reg                  s_axi_rvalid,
    input  wire                 s_axi_rready,

    // -----------------------------------------------------------------
    // AXI4 Write Address Channel (AW)
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]      s_axi_awid,
    input  wire [ADDR_W-1:0]    s_axi_awaddr,
    input  wire [LEN_W-1:0]     s_axi_awlen,
    input  wire                 s_axi_awvalid,
    output reg                  s_axi_awready,

    // -----------------------------------------------------------------
    // AXI4 Write Data Channel (W)
    // -----------------------------------------------------------------
    input  wire [DATA_W-1:0]    s_axi_wdata,
    input  wire                 s_axi_wlast,
    input  wire                 s_axi_wvalid,
    output reg                  s_axi_wready,

    // -----------------------------------------------------------------
    // AXI4 Write Response Channel (B)
    // -----------------------------------------------------------------
    output reg  [ID_W-1:0]      s_axi_bid,
    output reg  [1:0]           s_axi_bresp,
    output reg                  s_axi_bvalid,
    input  wire                 s_axi_bready
);

    // =====================================================================
    // Storage
    // =====================================================================
    localparam ADDR_MASK = DEPTH - 1;   // Assumes DEPTH is power of 2
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // =====================================================================
    // Read FSM
    // =====================================================================
    localparam RD_IDLE    = 2'd0;
    localparam RD_LATENCY = 2'd1;
    localparam RD_BURST   = 2'd2;

    reg [1:0]        rd_state;
    reg [ID_W-1:0]   rd_id;
    reg [ADDR_W-1:0] rd_addr;
    reg [LEN_W-1:0]  rd_len;       // Remaining beats - 1
    reg [LEN_W-1:0]  rd_cnt;       // Current beat count
    reg [7:0]         rd_lat_cnt;   // Latency counter

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rlast   <= 1'b0;
            s_axi_rdata   <= {DATA_W{1'b0}};
            s_axi_rresp   <= 2'b00;
            s_axi_rid     <= {ID_W{1'b0}};
            rd_id         <= {ID_W{1'b0}};
            rd_addr       <= {ADDR_W{1'b0}};
            rd_len        <= {LEN_W{1'b0}};
            rd_cnt        <= {LEN_W{1'b0}};
            rd_lat_cnt    <= 8'd0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_arready <= 1'b1;
                    s_axi_rvalid  <= 1'b0;
                    s_axi_rlast   <= 1'b0;
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_id         <= s_axi_arid;
                        rd_addr       <= s_axi_araddr;
                        rd_len        <= s_axi_arlen;
                        rd_cnt        <= {LEN_W{1'b0}};
                        rd_lat_cnt    <= 8'd0;
                        rd_state      <= RD_LATENCY;
                        s_axi_arready <= 1'b0;
                    end
                end

                RD_LATENCY: begin
                    // Configurable initial latency (count up to RD_LATENCY_CYCLES-1)
                    if (rd_lat_cnt == RD_LATENCY_CYCLES - 1) begin
                        rd_state <= RD_BURST;
                        // Present first beat
                        s_axi_rvalid <= 1'b1;
                        s_axi_rid    <= rd_id;
                        s_axi_rdata  <= mem[rd_addr & ADDR_MASK[ADDR_W-1:0]];
                        s_axi_rresp  <= 2'b00;
                        s_axi_rlast  <= (rd_len == {LEN_W{1'b0}});
                    end
                    rd_lat_cnt <= rd_lat_cnt + 8'd1;
                end

                RD_BURST: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (s_axi_rlast) begin
                            // Burst complete
                            s_axi_rvalid  <= 1'b0;
                            s_axi_rlast   <= 1'b0;
                            rd_state      <= RD_IDLE;
                        end else begin
                            // Next beat
                            rd_cnt  <= rd_cnt + 1;
                            rd_addr <= rd_addr + 1;
                            s_axi_rdata <= mem[(rd_addr + 1) & ADDR_MASK[ADDR_W-1:0]];
                            s_axi_rlast <= (rd_cnt + 1 == rd_len);
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Write FSM
    // =====================================================================
    localparam WR_IDLE    = 2'd0;
    localparam WR_ADDR    = 2'd1;
    localparam WR_DATA    = 2'd2;
    localparam WR_RESP    = 2'd3;

    reg [1:0]        wr_state;
    reg [ID_W-1:0]   wr_id;
    reg [ADDR_W-1:0] wr_addr;
    reg [LEN_W-1:0]  wr_len;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_bid     <= {ID_W{1'b0}};
            wr_id         <= {ID_W{1'b0}};
            wr_addr       <= {ADDR_W{1'b0}};
            wr_len        <= {LEN_W{1'b0}};
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b0;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id         <= s_axi_awid;
                        wr_addr       <= s_axi_awaddr;
                        wr_len        <= s_axi_awlen;
                        wr_state      <= WR_DATA;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                    end
                end

                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        mem[wr_addr & ADDR_MASK[ADDR_W-1:0]] <= s_axi_wdata;
                        wr_addr <= wr_addr + 1;
                        if (s_axi_wlast) begin
                            s_axi_wready <= 1'b0;
                            wr_state     <= WR_RESP;
                        end
                    end
                end

                WR_RESP: begin
                    s_axi_bvalid <= 1'b1;
                    s_axi_bid    <= wr_id;
                    s_axi_bresp  <= 2'b00;
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Simulation init
    // =====================================================================
    integer init_i;
    initial begin
        for (init_i = 0; init_i < DEPTH; init_i = init_i + 1)
            mem[init_i] = {DATA_W{1'b0}};
    end

    // Optional preload via $readmemh (set INIT_FILE parameter)
    // Note: Verilator requires this to be in an initial block with a string literal
    // or parameter. We use a generate to conditionally include it.
    generate
        if (INIT_FILE != "") begin : gen_init
            initial begin
                $readmemh(INIT_FILE, mem);
            end
        end
    endgenerate

endmodule
