// =============================================================================
// sim_hbm.v — 5-Port Shared-Memory HBM Simulation Model
// =============================================================================
//
// SIMULATION ONLY — replaces sim_hbm_port instances with a single shared memory.
// All 5 AXI4 ports read/write from the same reg array, matching real HBM
// where all ports share the same address space.
//
// Port mapping (matches top_level wiring):
//   Port 0 (pf_wgt): read-only
//   Port 1 (pf_act): read-only
//   Port 2 (flush):  write-only
//   Port 3 (dma):    read+write
//   Port 4 (bias):   read-only
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module sim_hbm #(
    parameter DEPTH              = 65536,
    parameter ADDR_W             = 28,
    parameter DATA_W             = 256,
    parameter ID_W               = 4,
    parameter LEN_W              = 8,
    parameter RD_LATENCY_CYCLES  = 2
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // -----------------------------------------------------------------
    // Port 0: Weight prefetch (read-only)
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]      p0_arid,
    input  wire [ADDR_W-1:0]    p0_araddr,
    input  wire [LEN_W-1:0]     p0_arlen,
    input  wire                 p0_arvalid,
    output reg                  p0_arready,
    output reg  [ID_W-1:0]      p0_rid,
    output reg  [DATA_W-1:0]    p0_rdata,
    output reg  [1:0]           p0_rresp,
    output reg                  p0_rlast,
    output reg                  p0_rvalid,
    input  wire                 p0_rready,

    // -----------------------------------------------------------------
    // Port 1: Activation prefetch (read-only)
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]      p1_arid,
    input  wire [ADDR_W-1:0]    p1_araddr,
    input  wire [LEN_W-1:0]     p1_arlen,
    input  wire                 p1_arvalid,
    output reg                  p1_arready,
    output reg  [ID_W-1:0]      p1_rid,
    output reg  [DATA_W-1:0]    p1_rdata,
    output reg  [1:0]           p1_rresp,
    output reg                  p1_rlast,
    output reg                  p1_rvalid,
    input  wire                 p1_rready,

    // -----------------------------------------------------------------
    // Port 2: Flush (write-only)
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]      p2_awid,
    input  wire [ADDR_W-1:0]    p2_awaddr,
    input  wire [LEN_W-1:0]     p2_awlen,
    input  wire                 p2_awvalid,
    output reg                  p2_awready,
    input  wire [DATA_W-1:0]    p2_wdata,
    input  wire                 p2_wlast,
    input  wire                 p2_wvalid,
    output reg                  p2_wready,
    output reg  [ID_W-1:0]      p2_bid,
    output reg  [1:0]           p2_bresp,
    output reg                  p2_bvalid,
    input  wire                 p2_bready,

    // -----------------------------------------------------------------
    // Port 3: DMA (read+write)
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]      p3_arid,
    input  wire [ADDR_W-1:0]    p3_araddr,
    input  wire [LEN_W-1:0]     p3_arlen,
    input  wire                 p3_arvalid,
    output reg                  p3_arready,
    output reg  [ID_W-1:0]      p3_rid,
    output reg  [DATA_W-1:0]    p3_rdata,
    output reg  [1:0]           p3_rresp,
    output reg                  p3_rlast,
    output reg                  p3_rvalid,
    input  wire                 p3_rready,

    input  wire [ID_W-1:0]      p3_awid,
    input  wire [ADDR_W-1:0]    p3_awaddr,
    input  wire [LEN_W-1:0]     p3_awlen,
    input  wire                 p3_awvalid,
    output reg                  p3_awready,
    input  wire [DATA_W-1:0]    p3_wdata,
    input  wire                 p3_wlast,
    input  wire                 p3_wvalid,
    output reg                  p3_wready,
    output reg  [ID_W-1:0]      p3_bid,
    output reg  [1:0]           p3_bresp,
    output reg                  p3_bvalid,
    input  wire                 p3_bready,

    // -----------------------------------------------------------------
    // Port 4: Bias loader (read-only)
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]      p4_arid,
    input  wire [ADDR_W-1:0]    p4_araddr,
    input  wire [LEN_W-1:0]     p4_arlen,
    input  wire                 p4_arvalid,
    output reg                  p4_arready,
    output reg  [ID_W-1:0]      p4_rid,
    output reg  [DATA_W-1:0]    p4_rdata,
    output reg  [1:0]           p4_rresp,
    output reg                  p4_rlast,
    output reg                  p4_rvalid,
    input  wire                 p4_rready
);

    // =====================================================================
    // Shared Storage
    // =====================================================================
    localparam ADDR_MASK = DEPTH - 1;
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // =====================================================================
    // Port 0: Read FSM (weight prefetch)
    // =====================================================================
    localparam RD_IDLE    = 2'd0;
    localparam RD_LAT     = 2'd1;
    localparam RD_BURST   = 2'd2;

    reg [1:0]        p0_rd_state;
    reg [ID_W-1:0]   p0_rd_id;
    reg [ADDR_W-1:0] p0_rd_addr;
    reg [LEN_W-1:0]  p0_rd_len;
    reg [LEN_W-1:0]  p0_rd_cnt;
    reg [7:0]         p0_rd_lat_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p0_rd_state  <= RD_IDLE;
            p0_arready   <= 1'b1;
            p0_rvalid    <= 1'b0;
            p0_rlast     <= 1'b0;
            p0_rdata     <= {DATA_W{1'b0}};
            p0_rresp     <= 2'b00;
            p0_rid       <= {ID_W{1'b0}};
            p0_rd_id     <= {ID_W{1'b0}};
            p0_rd_addr   <= {ADDR_W{1'b0}};
            p0_rd_len    <= {LEN_W{1'b0}};
            p0_rd_cnt    <= {LEN_W{1'b0}};
            p0_rd_lat_cnt <= 8'd0;
        end else begin
            case (p0_rd_state)
                RD_IDLE: begin
                    p0_arready <= 1'b1;
                    p0_rvalid  <= 1'b0;
                    p0_rlast   <= 1'b0;
                    if (p0_arvalid && p0_arready) begin
                        p0_rd_id      <= p0_arid;
                        p0_rd_addr    <= p0_araddr;
                        p0_rd_len     <= p0_arlen;
                        p0_rd_cnt     <= {LEN_W{1'b0}};
                        p0_rd_lat_cnt <= 8'd0;
                        p0_rd_state   <= RD_LAT;
                        p0_arready    <= 1'b0;
                    end
                end
                RD_LAT: begin
                    if (p0_rd_lat_cnt == RD_LATENCY_CYCLES - 1) begin
                        p0_rd_state <= RD_BURST;
                        p0_rvalid   <= 1'b1;
                        p0_rid      <= p0_rd_id;
                        p0_rdata    <= mem[p0_rd_addr & ADDR_MASK[ADDR_W-1:0]];
                        p0_rresp    <= 2'b00;
                        p0_rlast    <= (p0_rd_len == {LEN_W{1'b0}});
                    end
                    p0_rd_lat_cnt <= p0_rd_lat_cnt + 8'd1;
                end
                RD_BURST: begin
                    if (p0_rvalid && p0_rready) begin
                        if (p0_rlast) begin
                            p0_rvalid  <= 1'b0;
                            p0_rlast   <= 1'b0;
                            p0_rd_state <= RD_IDLE;
                        end else begin
                            p0_rd_cnt  <= p0_rd_cnt + 1;
                            p0_rd_addr <= p0_rd_addr + 1;
                            p0_rdata   <= mem[(p0_rd_addr + 1) & ADDR_MASK[ADDR_W-1:0]];
                            p0_rlast   <= (p0_rd_cnt + 1 == p0_rd_len);
                        end
                    end
                end
                default: p0_rd_state <= RD_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Port 1: Read FSM (activation prefetch)
    // =====================================================================
    reg [1:0]        p1_rd_state;
    reg [ID_W-1:0]   p1_rd_id;
    reg [ADDR_W-1:0] p1_rd_addr;
    reg [LEN_W-1:0]  p1_rd_len;
    reg [LEN_W-1:0]  p1_rd_cnt;
    reg [7:0]         p1_rd_lat_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_rd_state  <= RD_IDLE;
            p1_arready   <= 1'b1;
            p1_rvalid    <= 1'b0;
            p1_rlast     <= 1'b0;
            p1_rdata     <= {DATA_W{1'b0}};
            p1_rresp     <= 2'b00;
            p1_rid       <= {ID_W{1'b0}};
            p1_rd_id     <= {ID_W{1'b0}};
            p1_rd_addr   <= {ADDR_W{1'b0}};
            p1_rd_len    <= {LEN_W{1'b0}};
            p1_rd_cnt    <= {LEN_W{1'b0}};
            p1_rd_lat_cnt <= 8'd0;
        end else begin
            case (p1_rd_state)
                RD_IDLE: begin
                    p1_arready <= 1'b1;
                    p1_rvalid  <= 1'b0;
                    p1_rlast   <= 1'b0;
                    if (p1_arvalid && p1_arready) begin
                        p1_rd_id      <= p1_arid;
                        p1_rd_addr    <= p1_araddr;
                        p1_rd_len     <= p1_arlen;
                        p1_rd_cnt     <= {LEN_W{1'b0}};
                        p1_rd_lat_cnt <= 8'd0;
                        p1_rd_state   <= RD_LAT;
                        p1_arready    <= 1'b0;
                    end
                end
                RD_LAT: begin
                    if (p1_rd_lat_cnt == RD_LATENCY_CYCLES - 1) begin
                        p1_rd_state <= RD_BURST;
                        p1_rvalid   <= 1'b1;
                        p1_rid      <= p1_rd_id;
                        p1_rdata    <= mem[p1_rd_addr & ADDR_MASK[ADDR_W-1:0]];
                        p1_rresp    <= 2'b00;
                        p1_rlast    <= (p1_rd_len == {LEN_W{1'b0}});
                    end
                    p1_rd_lat_cnt <= p1_rd_lat_cnt + 8'd1;
                end
                RD_BURST: begin
                    if (p1_rvalid && p1_rready) begin
                        if (p1_rlast) begin
                            p1_rvalid  <= 1'b0;
                            p1_rlast   <= 1'b0;
                            p1_rd_state <= RD_IDLE;
                        end else begin
                            p1_rd_cnt  <= p1_rd_cnt + 1;
                            p1_rd_addr <= p1_rd_addr + 1;
                            p1_rdata   <= mem[(p1_rd_addr + 1) & ADDR_MASK[ADDR_W-1:0]];
                            p1_rlast   <= (p1_rd_cnt + 1 == p1_rd_len);
                        end
                    end
                end
                default: p1_rd_state <= RD_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Port 2: Write FSM (flush — write-only)
    // =====================================================================
    localparam WR_IDLE = 2'd0;
    localparam WR_DATA = 2'd1;
    localparam WR_RESP = 2'd2;

    reg [1:0]        p2_wr_state;
    reg [ID_W-1:0]   p2_wr_id;
    reg [ADDR_W-1:0] p2_wr_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p2_wr_state  <= WR_IDLE;
            p2_awready   <= 1'b1;
            p2_wready    <= 1'b0;
            p2_bvalid    <= 1'b0;
            p2_bresp     <= 2'b00;
            p2_bid       <= {ID_W{1'b0}};
            p2_wr_id     <= {ID_W{1'b0}};
            p2_wr_addr   <= {ADDR_W{1'b0}};
        end else begin
            case (p2_wr_state)
                WR_IDLE: begin
                    p2_awready <= 1'b1;
                    p2_wready  <= 1'b0;
                    p2_bvalid  <= 1'b0;
                    if (p2_awvalid && p2_awready) begin
                        p2_wr_id     <= p2_awid;
                        p2_wr_addr   <= p2_awaddr;
                        p2_wr_state  <= WR_DATA;
                        p2_awready   <= 1'b0;
                        p2_wready    <= 1'b1;
                    end
                end
                WR_DATA: begin
                    if (p2_wvalid && p2_wready) begin
                        mem[p2_wr_addr & ADDR_MASK[ADDR_W-1:0]] <= p2_wdata;
                        p2_wr_addr <= p2_wr_addr + 1;
                        if (p2_wlast) begin
                            p2_wready   <= 1'b0;
                            p2_wr_state <= WR_RESP;
                        end
                    end
                end
                WR_RESP: begin
                    p2_bvalid <= 1'b1;
                    p2_bid    <= p2_wr_id;
                    p2_bresp  <= 2'b00;
                    if (p2_bvalid && p2_bready) begin
                        p2_bvalid   <= 1'b0;
                        p2_wr_state <= WR_IDLE;
                    end
                end
                default: p2_wr_state <= WR_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Port 3: Read FSM (DMA)
    // =====================================================================
    reg [1:0]        p3_rd_state;
    reg [ID_W-1:0]   p3_rd_id;
    reg [ADDR_W-1:0] p3_rd_addr;
    reg [LEN_W-1:0]  p3_rd_len;
    reg [LEN_W-1:0]  p3_rd_cnt;
    reg [7:0]         p3_rd_lat_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p3_rd_state  <= RD_IDLE;
            p3_arready   <= 1'b1;
            p3_rvalid    <= 1'b0;
            p3_rlast     <= 1'b0;
            p3_rdata     <= {DATA_W{1'b0}};
            p3_rresp     <= 2'b00;
            p3_rid       <= {ID_W{1'b0}};
            p3_rd_id     <= {ID_W{1'b0}};
            p3_rd_addr   <= {ADDR_W{1'b0}};
            p3_rd_len    <= {LEN_W{1'b0}};
            p3_rd_cnt    <= {LEN_W{1'b0}};
            p3_rd_lat_cnt <= 8'd0;
        end else begin
            case (p3_rd_state)
                RD_IDLE: begin
                    p3_arready <= 1'b1;
                    p3_rvalid  <= 1'b0;
                    p3_rlast   <= 1'b0;
                    if (p3_arvalid && p3_arready) begin
                        p3_rd_id      <= p3_arid;
                        p3_rd_addr    <= p3_araddr;
                        p3_rd_len     <= p3_arlen;
                        p3_rd_cnt     <= {LEN_W{1'b0}};
                        p3_rd_lat_cnt <= 8'd0;
                        p3_rd_state   <= RD_LAT;
                        p3_arready    <= 1'b0;
                    end
                end
                RD_LAT: begin
                    if (p3_rd_lat_cnt == RD_LATENCY_CYCLES - 1) begin
                        p3_rd_state <= RD_BURST;
                        p3_rvalid   <= 1'b1;
                        p3_rid      <= p3_rd_id;
                        p3_rdata    <= mem[p3_rd_addr & ADDR_MASK[ADDR_W-1:0]];
                        p3_rresp    <= 2'b00;
                        p3_rlast    <= (p3_rd_len == {LEN_W{1'b0}});
                    end
                    p3_rd_lat_cnt <= p3_rd_lat_cnt + 8'd1;
                end
                RD_BURST: begin
                    if (p3_rvalid && p3_rready) begin
                        if (p3_rlast) begin
                            p3_rvalid  <= 1'b0;
                            p3_rlast   <= 1'b0;
                            p3_rd_state <= RD_IDLE;
                        end else begin
                            p3_rd_cnt  <= p3_rd_cnt + 1;
                            p3_rd_addr <= p3_rd_addr + 1;
                            p3_rdata   <= mem[(p3_rd_addr + 1) & ADDR_MASK[ADDR_W-1:0]];
                            p3_rlast   <= (p3_rd_cnt + 1 == p3_rd_len);
                        end
                    end
                end
                default: p3_rd_state <= RD_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Port 3: Write FSM (DMA)
    // =====================================================================
    reg [1:0]        p3_wr_state;
    reg [ID_W-1:0]   p3_wr_id;
    reg [ADDR_W-1:0] p3_wr_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p3_wr_state  <= WR_IDLE;
            p3_awready   <= 1'b1;
            p3_wready    <= 1'b0;
            p3_bvalid    <= 1'b0;
            p3_bresp     <= 2'b00;
            p3_bid       <= {ID_W{1'b0}};
            p3_wr_id     <= {ID_W{1'b0}};
            p3_wr_addr   <= {ADDR_W{1'b0}};
        end else begin
            case (p3_wr_state)
                WR_IDLE: begin
                    p3_awready <= 1'b1;
                    p3_wready  <= 1'b0;
                    p3_bvalid  <= 1'b0;
                    if (p3_awvalid && p3_awready) begin
                        p3_wr_id     <= p3_awid;
                        p3_wr_addr   <= p3_awaddr;
                        p3_wr_state  <= WR_DATA;
                        p3_awready   <= 1'b0;
                        p3_wready    <= 1'b1;
                    end
                end
                WR_DATA: begin
                    if (p3_wvalid && p3_wready) begin
                        mem[p3_wr_addr & ADDR_MASK[ADDR_W-1:0]] <= p3_wdata;
                        p3_wr_addr <= p3_wr_addr + 1;
                        if (p3_wlast) begin
                            p3_wready   <= 1'b0;
                            p3_wr_state <= WR_RESP;
                        end
                    end
                end
                WR_RESP: begin
                    p3_bvalid <= 1'b1;
                    p3_bid    <= p3_wr_id;
                    p3_bresp  <= 2'b00;
                    if (p3_bvalid && p3_bready) begin
                        p3_bvalid   <= 1'b0;
                        p3_wr_state <= WR_IDLE;
                    end
                end
                default: p3_wr_state <= WR_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Port 4: Read FSM (bias loader)
    // =====================================================================
    reg [1:0]        p4_rd_state;
    reg [ID_W-1:0]   p4_rd_id;
    reg [ADDR_W-1:0] p4_rd_addr;
    reg [LEN_W-1:0]  p4_rd_len;
    reg [LEN_W-1:0]  p4_rd_cnt;
    reg [7:0]         p4_rd_lat_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p4_rd_state  <= RD_IDLE;
            p4_arready   <= 1'b1;
            p4_rvalid    <= 1'b0;
            p4_rlast     <= 1'b0;
            p4_rdata     <= {DATA_W{1'b0}};
            p4_rresp     <= 2'b00;
            p4_rid       <= {ID_W{1'b0}};
            p4_rd_id     <= {ID_W{1'b0}};
            p4_rd_addr   <= {ADDR_W{1'b0}};
            p4_rd_len    <= {LEN_W{1'b0}};
            p4_rd_cnt    <= {LEN_W{1'b0}};
            p4_rd_lat_cnt <= 8'd0;
        end else begin
            case (p4_rd_state)
                RD_IDLE: begin
                    p4_arready <= 1'b1;
                    p4_rvalid  <= 1'b0;
                    p4_rlast   <= 1'b0;
                    if (p4_arvalid && p4_arready) begin
                        p4_rd_id      <= p4_arid;
                        p4_rd_addr    <= p4_araddr;
                        p4_rd_len     <= p4_arlen;
                        p4_rd_cnt     <= {LEN_W{1'b0}};
                        p4_rd_lat_cnt <= 8'd0;
                        p4_rd_state   <= RD_LAT;
                        p4_arready    <= 1'b0;
                    end
                end
                RD_LAT: begin
                    if (p4_rd_lat_cnt == RD_LATENCY_CYCLES - 1) begin
                        p4_rd_state <= RD_BURST;
                        p4_rvalid   <= 1'b1;
                        p4_rid      <= p4_rd_id;
                        p4_rdata    <= mem[p4_rd_addr & ADDR_MASK[ADDR_W-1:0]];
                        p4_rresp    <= 2'b00;
                        p4_rlast    <= (p4_rd_len == {LEN_W{1'b0}});
                    end
                    p4_rd_lat_cnt <= p4_rd_lat_cnt + 8'd1;
                end
                RD_BURST: begin
                    if (p4_rvalid && p4_rready) begin
                        if (p4_rlast) begin
                            p4_rvalid  <= 1'b0;
                            p4_rlast   <= 1'b0;
                            p4_rd_state <= RD_IDLE;
                        end else begin
                            p4_rd_cnt  <= p4_rd_cnt + 1;
                            p4_rd_addr <= p4_rd_addr + 1;
                            p4_rdata   <= mem[(p4_rd_addr + 1) & ADDR_MASK[ADDR_W-1:0]];
                            p4_rlast   <= (p4_rd_cnt + 1 == p4_rd_len);
                        end
                    end
                end
                default: p4_rd_state <= RD_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Memory initialization
    // =====================================================================
    integer init_i;
    initial begin
        for (init_i = 0; init_i < DEPTH; init_i = init_i + 1)
            mem[init_i] = {DATA_W{1'b0}};
    end

endmodule
