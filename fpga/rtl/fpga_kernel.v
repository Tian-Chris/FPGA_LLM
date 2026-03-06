// =============================================================================
// fpga_kernel.v — Vitis RTL Kernel Top-Level Wrapper
// =============================================================================
//
// Wraps diffusion_transformer_top for Vitis RTL kernel flow on Alveo U280.
// Responsibilities:
//   1. Port renaming (clk→ap_clk, rst_n→ap_rst_n)
//   2. AXI sideband tie-offs (SIZE, BURST, CACHE, PROT, LOCK, QOS, WSTRB)
//   3. Address conversion: 28-bit word addr → 33-bit byte addr (<<5)
//   4. Read-only port write channel tie-offs
//   5. Write-only port read channel tie-offs
//
// All 6 AXI master ports use 256-bit data (32-byte), hence ARSIZE/AWSIZE=5.
// =============================================================================

// Ensure FPGA_TARGET is defined — project-level verilog_define does not
// propagate into the packaged IP used by Vitis hw_emu elaboration.
`ifndef FPGA_TARGET
`define FPGA_TARGET
`endif

`include "defines.vh"

module fpga_kernel #(
    parameter C_S_AXI_CONTROL_ADDR_WIDTH = 7,
    parameter C_S_AXI_CONTROL_DATA_WIDTH = 32,
    parameter C_M_AXI_ADDR_WIDTH         = 33,   // byte address
    parameter C_M_AXI_DATA_WIDTH         = 256,
    parameter C_M_AXI_ID_WIDTH           = 4
)(
    // Vitis standard clock/reset
    input  wire                                    ap_clk,
    input  wire                                    ap_rst_n,

    // Interrupt
    output wire                                    interrupt,

    // AXI-Lite slave (s_axi_control)
    input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]   s_axi_control_awaddr,
    input  wire                                    s_axi_control_awvalid,
    output wire                                    s_axi_control_awready,
    input  wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]   s_axi_control_wdata,
    input  wire [C_S_AXI_CONTROL_DATA_WIDTH/8-1:0] s_axi_control_wstrb,
    input  wire                                    s_axi_control_wvalid,
    output wire                                    s_axi_control_wready,
    output wire [1:0]                              s_axi_control_bresp,
    output wire                                    s_axi_control_bvalid,
    input  wire                                    s_axi_control_bready,
    input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]   s_axi_control_araddr,
    input  wire                                    s_axi_control_arvalid,
    output wire                                    s_axi_control_arready,
    output wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]   s_axi_control_rdata,
    output wire [1:0]                              s_axi_control_rresp,
    output wire                                    s_axi_control_rvalid,
    input  wire                                    s_axi_control_rready,

    // === 6 AXI4 Master Ports to HBM ===
    // Port naming: m_axi_hbm00-01 (wgt), hbm06-07 (act), hbm12 (flush), hbm13 (dma)

    // --- hbm00-01: Weight tile loaders (read-only, 2 engines) ---
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm00_arid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm00_araddr,
    output wire [7:0]                      m_axi_hbm00_arlen,
    output wire [2:0]                      m_axi_hbm00_arsize,
    output wire [1:0]                      m_axi_hbm00_arburst,
    output wire [1:0]                      m_axi_hbm00_arlock,
    output wire [3:0]                      m_axi_hbm00_arcache,
    output wire [2:0]                      m_axi_hbm00_arprot,
    output wire [3:0]                      m_axi_hbm00_arqos,
    output wire                            m_axi_hbm00_arvalid,
    input  wire                            m_axi_hbm00_arready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm00_rid,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm00_rdata,
    input  wire [1:0]                      m_axi_hbm00_rresp,
    input  wire                            m_axi_hbm00_rlast,
    input  wire                            m_axi_hbm00_rvalid,
    output wire                            m_axi_hbm00_rready,
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm00_awid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm00_awaddr,
    output wire [7:0]                      m_axi_hbm00_awlen,
    output wire [2:0]                      m_axi_hbm00_awsize,
    output wire [1:0]                      m_axi_hbm00_awburst,
    output wire [1:0]                      m_axi_hbm00_awlock,
    output wire [3:0]                      m_axi_hbm00_awcache,
    output wire [2:0]                      m_axi_hbm00_awprot,
    output wire [3:0]                      m_axi_hbm00_awqos,
    output wire                            m_axi_hbm00_awvalid,
    input  wire                            m_axi_hbm00_awready,
    output wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm00_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_hbm00_wstrb,
    output wire                            m_axi_hbm00_wlast,
    output wire                            m_axi_hbm00_wvalid,
    input  wire                            m_axi_hbm00_wready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm00_bid,
    input  wire [1:0]                      m_axi_hbm00_bresp,
    input  wire                            m_axi_hbm00_bvalid,
    output wire                            m_axi_hbm00_bready,

    // hbm01
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm01_arid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm01_araddr,
    output wire [7:0]                      m_axi_hbm01_arlen,
    output wire [2:0]                      m_axi_hbm01_arsize,
    output wire [1:0]                      m_axi_hbm01_arburst,
    output wire [1:0]                      m_axi_hbm01_arlock,
    output wire [3:0]                      m_axi_hbm01_arcache,
    output wire [2:0]                      m_axi_hbm01_arprot,
    output wire [3:0]                      m_axi_hbm01_arqos,
    output wire                            m_axi_hbm01_arvalid,
    input  wire                            m_axi_hbm01_arready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm01_rid,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm01_rdata,
    input  wire [1:0]                      m_axi_hbm01_rresp,
    input  wire                            m_axi_hbm01_rlast,
    input  wire                            m_axi_hbm01_rvalid,
    output wire                            m_axi_hbm01_rready,
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm01_awid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm01_awaddr,
    output wire [7:0]                      m_axi_hbm01_awlen,
    output wire [2:0]                      m_axi_hbm01_awsize,
    output wire [1:0]                      m_axi_hbm01_awburst,
    output wire [1:0]                      m_axi_hbm01_awlock,
    output wire [3:0]                      m_axi_hbm01_awcache,
    output wire [2:0]                      m_axi_hbm01_awprot,
    output wire [3:0]                      m_axi_hbm01_awqos,
    output wire                            m_axi_hbm01_awvalid,
    input  wire                            m_axi_hbm01_awready,
    output wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm01_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_hbm01_wstrb,
    output wire                            m_axi_hbm01_wlast,
    output wire                            m_axi_hbm01_wvalid,
    input  wire                            m_axi_hbm01_wready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm01_bid,
    input  wire [1:0]                      m_axi_hbm01_bresp,
    input  wire                            m_axi_hbm01_bvalid,
    output wire                            m_axi_hbm01_bready,

    // --- hbm06-07: Activation tile loaders (read-only, 2 engines) ---
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm06_arid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm06_araddr,
    output wire [7:0]                      m_axi_hbm06_arlen,
    output wire [2:0]                      m_axi_hbm06_arsize,
    output wire [1:0]                      m_axi_hbm06_arburst,
    output wire [1:0]                      m_axi_hbm06_arlock,
    output wire [3:0]                      m_axi_hbm06_arcache,
    output wire [2:0]                      m_axi_hbm06_arprot,
    output wire [3:0]                      m_axi_hbm06_arqos,
    output wire                            m_axi_hbm06_arvalid,
    input  wire                            m_axi_hbm06_arready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm06_rid,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm06_rdata,
    input  wire [1:0]                      m_axi_hbm06_rresp,
    input  wire                            m_axi_hbm06_rlast,
    input  wire                            m_axi_hbm06_rvalid,
    output wire                            m_axi_hbm06_rready,
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm06_awid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm06_awaddr,
    output wire [7:0]                      m_axi_hbm06_awlen,
    output wire [2:0]                      m_axi_hbm06_awsize,
    output wire [1:0]                      m_axi_hbm06_awburst,
    output wire [1:0]                      m_axi_hbm06_awlock,
    output wire [3:0]                      m_axi_hbm06_awcache,
    output wire [2:0]                      m_axi_hbm06_awprot,
    output wire [3:0]                      m_axi_hbm06_awqos,
    output wire                            m_axi_hbm06_awvalid,
    input  wire                            m_axi_hbm06_awready,
    output wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm06_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_hbm06_wstrb,
    output wire                            m_axi_hbm06_wlast,
    output wire                            m_axi_hbm06_wvalid,
    input  wire                            m_axi_hbm06_wready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm06_bid,
    input  wire [1:0]                      m_axi_hbm06_bresp,
    input  wire                            m_axi_hbm06_bvalid,
    output wire                            m_axi_hbm06_bready,

    // hbm07
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm07_arid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm07_araddr,
    output wire [7:0]                      m_axi_hbm07_arlen,
    output wire [2:0]                      m_axi_hbm07_arsize,
    output wire [1:0]                      m_axi_hbm07_arburst,
    output wire [1:0]                      m_axi_hbm07_arlock,
    output wire [3:0]                      m_axi_hbm07_arcache,
    output wire [2:0]                      m_axi_hbm07_arprot,
    output wire [3:0]                      m_axi_hbm07_arqos,
    output wire                            m_axi_hbm07_arvalid,
    input  wire                            m_axi_hbm07_arready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm07_rid,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm07_rdata,
    input  wire [1:0]                      m_axi_hbm07_rresp,
    input  wire                            m_axi_hbm07_rlast,
    input  wire                            m_axi_hbm07_rvalid,
    output wire                            m_axi_hbm07_rready,
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm07_awid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm07_awaddr,
    output wire [7:0]                      m_axi_hbm07_awlen,
    output wire [2:0]                      m_axi_hbm07_awsize,
    output wire [1:0]                      m_axi_hbm07_awburst,
    output wire [1:0]                      m_axi_hbm07_awlock,
    output wire [3:0]                      m_axi_hbm07_awcache,
    output wire [2:0]                      m_axi_hbm07_awprot,
    output wire [3:0]                      m_axi_hbm07_awqos,
    output wire                            m_axi_hbm07_awvalid,
    input  wire                            m_axi_hbm07_awready,
    output wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm07_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_hbm07_wstrb,
    output wire                            m_axi_hbm07_wlast,
    output wire                            m_axi_hbm07_wvalid,
    input  wire                            m_axi_hbm07_wready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm07_bid,
    input  wire [1:0]                      m_axi_hbm07_bresp,
    input  wire                            m_axi_hbm07_bvalid,
    output wire                            m_axi_hbm07_bready,

    // --- hbm12: Flush (write-only) ---
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm12_arid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm12_araddr,
    output wire [7:0]                      m_axi_hbm12_arlen,
    output wire [2:0]                      m_axi_hbm12_arsize,
    output wire [1:0]                      m_axi_hbm12_arburst,
    output wire [1:0]                      m_axi_hbm12_arlock,
    output wire [3:0]                      m_axi_hbm12_arcache,
    output wire [2:0]                      m_axi_hbm12_arprot,
    output wire [3:0]                      m_axi_hbm12_arqos,
    output wire                            m_axi_hbm12_arvalid,
    input  wire                            m_axi_hbm12_arready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm12_rid,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm12_rdata,
    input  wire [1:0]                      m_axi_hbm12_rresp,
    input  wire                            m_axi_hbm12_rlast,
    input  wire                            m_axi_hbm12_rvalid,
    output wire                            m_axi_hbm12_rready,
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm12_awid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm12_awaddr,
    output wire [7:0]                      m_axi_hbm12_awlen,
    output wire [2:0]                      m_axi_hbm12_awsize,
    output wire [1:0]                      m_axi_hbm12_awburst,
    output wire [1:0]                      m_axi_hbm12_awlock,
    output wire [3:0]                      m_axi_hbm12_awcache,
    output wire [2:0]                      m_axi_hbm12_awprot,
    output wire [3:0]                      m_axi_hbm12_awqos,
    output wire                            m_axi_hbm12_awvalid,
    input  wire                            m_axi_hbm12_awready,
    output wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm12_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_hbm12_wstrb,
    output wire                            m_axi_hbm12_wlast,
    output wire                            m_axi_hbm12_wvalid,
    input  wire                            m_axi_hbm12_wready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm12_bid,
    input  wire [1:0]                      m_axi_hbm12_bresp,
    input  wire                            m_axi_hbm12_bvalid,
    output wire                            m_axi_hbm12_bready,

    // --- hbm13: DMA (read+write) ---
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm13_arid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm13_araddr,
    output wire [7:0]                      m_axi_hbm13_arlen,
    output wire [2:0]                      m_axi_hbm13_arsize,
    output wire [1:0]                      m_axi_hbm13_arburst,
    output wire [1:0]                      m_axi_hbm13_arlock,
    output wire [3:0]                      m_axi_hbm13_arcache,
    output wire [2:0]                      m_axi_hbm13_arprot,
    output wire [3:0]                      m_axi_hbm13_arqos,
    output wire                            m_axi_hbm13_arvalid,
    input  wire                            m_axi_hbm13_arready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm13_rid,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm13_rdata,
    input  wire [1:0]                      m_axi_hbm13_rresp,
    input  wire                            m_axi_hbm13_rlast,
    input  wire                            m_axi_hbm13_rvalid,
    output wire                            m_axi_hbm13_rready,
    output wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm13_awid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_hbm13_awaddr,
    output wire [7:0]                      m_axi_hbm13_awlen,
    output wire [2:0]                      m_axi_hbm13_awsize,
    output wire [1:0]                      m_axi_hbm13_awburst,
    output wire [1:0]                      m_axi_hbm13_awlock,
    output wire [3:0]                      m_axi_hbm13_awcache,
    output wire [2:0]                      m_axi_hbm13_awprot,
    output wire [3:0]                      m_axi_hbm13_awqos,
    output wire                            m_axi_hbm13_awvalid,
    input  wire                            m_axi_hbm13_awready,
    output wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_hbm13_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_hbm13_wstrb,
    output wire                            m_axi_hbm13_wlast,
    output wire                            m_axi_hbm13_wvalid,
    input  wire                            m_axi_hbm13_wready,
    input  wire [C_M_AXI_ID_WIDTH-1:0]    m_axi_hbm13_bid,
    input  wire [1:0]                      m_axi_hbm13_bresp,
    input  wire                            m_axi_hbm13_bvalid,
    output wire                            m_axi_hbm13_bready
);

    // =========================================================================
    // Internal wires from top_level (28-bit word addresses)
    // =========================================================================
    localparam IDW = C_M_AXI_ID_WIDTH;
    localparam AW  = HBM_ADDR_W;     // 28-bit word address
    localparam DW  = C_M_AXI_DATA_WIDTH;

    // Weight tile loader AXI signals (2x, read-only)
    wire [IDW-1:0] top_wgt_arid    [0:1];
    wire [AW-1:0]  top_wgt_araddr  [0:1];
    wire [7:0]     top_wgt_arlen   [0:1];
    wire           top_wgt_arvalid [0:1];
    wire           top_wgt_arready [0:1];
    wire [IDW-1:0] top_wgt_rid     [0:1];
    wire [DW-1:0]  top_wgt_rdata   [0:1];
    wire [1:0]     top_wgt_rresp   [0:1];
    wire           top_wgt_rlast   [0:1];
    wire           top_wgt_rvalid  [0:1];
    wire           top_wgt_rready  [0:1];

    // Activation tile loader AXI signals (2x, read-only)
    wire [IDW-1:0] top_act_arid    [0:1];
    wire [AW-1:0]  top_act_araddr  [0:1];
    wire [7:0]     top_act_arlen   [0:1];
    wire           top_act_arvalid [0:1];
    wire           top_act_arready [0:1];
    wire [IDW-1:0] top_act_rid     [0:1];
    wire [DW-1:0]  top_act_rdata   [0:1];
    wire [1:0]     top_act_rresp   [0:1];
    wire           top_act_rlast   [0:1];
    wire           top_act_rvalid  [0:1];
    wire           top_act_rready  [0:1];

    // Flush AXI signals (write-only)
    wire [IDW-1:0] top_fl_awid;
    wire [AW-1:0]  top_fl_awaddr;
    wire [7:0]     top_fl_awlen;
    wire           top_fl_awvalid, top_fl_awready;
    wire [DW-1:0]  top_fl_wdata;
    wire           top_fl_wlast, top_fl_wvalid, top_fl_wready;
    wire [IDW-1:0] top_fl_bid;
    wire [1:0]     top_fl_bresp;
    wire           top_fl_bvalid, top_fl_bready;

    // DMA AXI signals (read+write)
    wire [IDW-1:0] top_dma_arid;
    wire [AW-1:0]  top_dma_araddr;
    wire [7:0]     top_dma_arlen;
    wire           top_dma_arvalid, top_dma_arready;
    wire [IDW-1:0] top_dma_rid;
    wire [DW-1:0]  top_dma_rdata;
    wire [1:0]     top_dma_rresp;
    wire           top_dma_rlast, top_dma_rvalid, top_dma_rready;
    wire [IDW-1:0] top_dma_awid;
    wire [AW-1:0]  top_dma_awaddr;
    wire [7:0]     top_dma_awlen;
    wire           top_dma_awvalid, top_dma_awready;
    wire [DW-1:0]  top_dma_wdata;
    wire           top_dma_wlast, top_dma_wvalid, top_dma_wready;
    wire [IDW-1:0] top_dma_bid;
    wire [1:0]     top_dma_bresp;
    wire           top_dma_bvalid, top_dma_bready;

    // =========================================================================
    // Instantiate the design
    // =========================================================================
    diffusion_transformer_top #(
        .AXI_ADDR_WIDTH(C_S_AXI_CONTROL_ADDR_WIDTH),
        .AXI_DATA_WIDTH(C_S_AXI_CONTROL_DATA_WIDTH),
        .ID_W_PARAM(C_M_AXI_ID_WIDTH)
    ) u_top (
        .clk(ap_clk),
        .rst_n(ap_rst_n),

        // AXI-Lite control
        .s_axi_awaddr(s_axi_control_awaddr),
        .s_axi_awvalid(s_axi_control_awvalid),
        .s_axi_awready(s_axi_control_awready),
        .s_axi_wdata(s_axi_control_wdata),
        .s_axi_wstrb(s_axi_control_wstrb),
        .s_axi_wvalid(s_axi_control_wvalid),
        .s_axi_wready(s_axi_control_wready),
        .s_axi_bresp(s_axi_control_bresp),
        .s_axi_bvalid(s_axi_control_bvalid),
        .s_axi_bready(s_axi_control_bready),
        .s_axi_araddr(s_axi_control_araddr),
        .s_axi_arvalid(s_axi_control_arvalid),
        .s_axi_arready(s_axi_control_arready),
        .s_axi_rdata(s_axi_control_rdata),
        .s_axi_rresp(s_axi_control_rresp),
        .s_axi_rvalid(s_axi_control_rvalid),
        .s_axi_rready(s_axi_control_rready),
        .irq_done(),
        .interrupt(interrupt),

        // Weight tile loaders
        .m_axi_wgt0_arid(top_wgt_arid[0]),     .m_axi_wgt0_araddr(top_wgt_araddr[0]),
        .m_axi_wgt0_arlen(top_wgt_arlen[0]),   .m_axi_wgt0_arvalid(top_wgt_arvalid[0]),
        .m_axi_wgt0_arready(top_wgt_arready[0]),
        .m_axi_wgt0_rid(top_wgt_rid[0]),       .m_axi_wgt0_rdata(top_wgt_rdata[0]),
        .m_axi_wgt0_rresp(top_wgt_rresp[0]),   .m_axi_wgt0_rlast(top_wgt_rlast[0]),
        .m_axi_wgt0_rvalid(top_wgt_rvalid[0]), .m_axi_wgt0_rready(top_wgt_rready[0]),

        .m_axi_wgt1_arid(top_wgt_arid[1]),     .m_axi_wgt1_araddr(top_wgt_araddr[1]),
        .m_axi_wgt1_arlen(top_wgt_arlen[1]),   .m_axi_wgt1_arvalid(top_wgt_arvalid[1]),
        .m_axi_wgt1_arready(top_wgt_arready[1]),
        .m_axi_wgt1_rid(top_wgt_rid[1]),       .m_axi_wgt1_rdata(top_wgt_rdata[1]),
        .m_axi_wgt1_rresp(top_wgt_rresp[1]),   .m_axi_wgt1_rlast(top_wgt_rlast[1]),
        .m_axi_wgt1_rvalid(top_wgt_rvalid[1]), .m_axi_wgt1_rready(top_wgt_rready[1]),

        // Activation tile loaders
        .m_axi_act0_arid(top_act_arid[0]),     .m_axi_act0_araddr(top_act_araddr[0]),
        .m_axi_act0_arlen(top_act_arlen[0]),   .m_axi_act0_arvalid(top_act_arvalid[0]),
        .m_axi_act0_arready(top_act_arready[0]),
        .m_axi_act0_rid(top_act_rid[0]),       .m_axi_act0_rdata(top_act_rdata[0]),
        .m_axi_act0_rresp(top_act_rresp[0]),   .m_axi_act0_rlast(top_act_rlast[0]),
        .m_axi_act0_rvalid(top_act_rvalid[0]), .m_axi_act0_rready(top_act_rready[0]),

        .m_axi_act1_arid(top_act_arid[1]),     .m_axi_act1_araddr(top_act_araddr[1]),
        .m_axi_act1_arlen(top_act_arlen[1]),   .m_axi_act1_arvalid(top_act_arvalid[1]),
        .m_axi_act1_arready(top_act_arready[1]),
        .m_axi_act1_rid(top_act_rid[1]),       .m_axi_act1_rdata(top_act_rdata[1]),
        .m_axi_act1_rresp(top_act_rresp[1]),   .m_axi_act1_rlast(top_act_rlast[1]),
        .m_axi_act1_rvalid(top_act_rvalid[1]), .m_axi_act1_rready(top_act_rready[1]),

        // Flush port
        .m_axi_fl_awid(top_fl_awid),       .m_axi_fl_awaddr(top_fl_awaddr),
        .m_axi_fl_awlen(top_fl_awlen),     .m_axi_fl_awvalid(top_fl_awvalid),
        .m_axi_fl_awready(top_fl_awready),
        .m_axi_fl_wdata(top_fl_wdata),     .m_axi_fl_wlast(top_fl_wlast),
        .m_axi_fl_wvalid(top_fl_wvalid),   .m_axi_fl_wready(top_fl_wready),
        .m_axi_fl_bid(top_fl_bid),         .m_axi_fl_bresp(top_fl_bresp),
        .m_axi_fl_bvalid(top_fl_bvalid),   .m_axi_fl_bready(top_fl_bready),

        // DMA port
        .m_axi_dma_arid(top_dma_arid),       .m_axi_dma_araddr(top_dma_araddr),
        .m_axi_dma_arlen(top_dma_arlen),     .m_axi_dma_arvalid(top_dma_arvalid),
        .m_axi_dma_arready(top_dma_arready),
        .m_axi_dma_rid(top_dma_rid),         .m_axi_dma_rdata(top_dma_rdata),
        .m_axi_dma_rresp(top_dma_rresp),     .m_axi_dma_rlast(top_dma_rlast),
        .m_axi_dma_rvalid(top_dma_rvalid),   .m_axi_dma_rready(top_dma_rready),
        .m_axi_dma_awid(top_dma_awid),       .m_axi_dma_awaddr(top_dma_awaddr),
        .m_axi_dma_awlen(top_dma_awlen),     .m_axi_dma_awvalid(top_dma_awvalid),
        .m_axi_dma_awready(top_dma_awready),
        .m_axi_dma_wdata(top_dma_wdata),     .m_axi_dma_wlast(top_dma_wlast),
        .m_axi_dma_wvalid(top_dma_wvalid),   .m_axi_dma_wready(top_dma_wready),
        .m_axi_dma_bid(top_dma_bid),         .m_axi_dma_bresp(top_dma_bresp),
        .m_axi_dma_bvalid(top_dma_bvalid),   .m_axi_dma_bready(top_dma_bready)
    );

    // =========================================================================
    // Address Conversion + Sideband Tie-offs (read-only ports: hbm00-01, hbm06-07)
    // =========================================================================
    // Macro-like pattern for read-only ports: addr shift, sideband tie-off,
    // write channel tie-off

    // --- Weight ports hbm00-01 ---
    `define WIRE_RD_ONLY_PORT(HBM_N, ARR, IDX) \
        assign m_axi_``HBM_N``_arid    = ARR``_arid[IDX]; \
        assign m_axi_``HBM_N``_araddr  = {ARR``_araddr[IDX], 5'b00000}; \
        assign m_axi_``HBM_N``_arlen   = ARR``_arlen[IDX]; \
        assign m_axi_``HBM_N``_arsize  = 3'b101; \
        assign m_axi_``HBM_N``_arburst = 2'b01; \
        assign m_axi_``HBM_N``_arlock  = 2'b00; \
        assign m_axi_``HBM_N``_arcache = 4'b0011; \
        assign m_axi_``HBM_N``_arprot  = 3'b000; \
        assign m_axi_``HBM_N``_arqos   = 4'b0000; \
        assign m_axi_``HBM_N``_arvalid = ARR``_arvalid[IDX]; \
        assign ARR``_arready[IDX]      = m_axi_``HBM_N``_arready; \
        assign ARR``_rid[IDX]          = m_axi_``HBM_N``_rid; \
        assign ARR``_rdata[IDX]        = m_axi_``HBM_N``_rdata; \
        assign ARR``_rresp[IDX]        = m_axi_``HBM_N``_rresp; \
        assign ARR``_rlast[IDX]        = m_axi_``HBM_N``_rlast; \
        assign ARR``_rvalid[IDX]       = m_axi_``HBM_N``_rvalid; \
        assign m_axi_``HBM_N``_rready  = ARR``_rready[IDX]; \
        assign m_axi_``HBM_N``_awid    = {C_M_AXI_ID_WIDTH{1'b0}}; \
        assign m_axi_``HBM_N``_awaddr  = {C_M_AXI_ADDR_WIDTH{1'b0}}; \
        assign m_axi_``HBM_N``_awlen   = 8'd0; \
        assign m_axi_``HBM_N``_awsize  = 3'b101; \
        assign m_axi_``HBM_N``_awburst = 2'b01; \
        assign m_axi_``HBM_N``_awlock  = 2'b00; \
        assign m_axi_``HBM_N``_awcache = 4'b0011; \
        assign m_axi_``HBM_N``_awprot  = 3'b000; \
        assign m_axi_``HBM_N``_awqos   = 4'b0000; \
        assign m_axi_``HBM_N``_awvalid = 1'b0; \
        assign m_axi_``HBM_N``_wdata   = {C_M_AXI_DATA_WIDTH{1'b0}}; \
        assign m_axi_``HBM_N``_wstrb   = {(C_M_AXI_DATA_WIDTH/8){1'b0}}; \
        assign m_axi_``HBM_N``_wlast   = 1'b0; \
        assign m_axi_``HBM_N``_wvalid  = 1'b0; \
        assign m_axi_``HBM_N``_bready  = 1'b0;

    `WIRE_RD_ONLY_PORT(hbm00, top_wgt, 0)
    `WIRE_RD_ONLY_PORT(hbm01, top_wgt, 1)

    `WIRE_RD_ONLY_PORT(hbm06, top_act, 0)
    `WIRE_RD_ONLY_PORT(hbm07, top_act, 1)

    `undef WIRE_RD_ONLY_PORT

    // =========================================================================
    // hbm12: Flush port (write-only) — tie off read channels
    // =========================================================================
    // Read channel tie-offs
    assign m_axi_hbm12_arid    = {C_M_AXI_ID_WIDTH{1'b0}};
    assign m_axi_hbm12_araddr  = {C_M_AXI_ADDR_WIDTH{1'b0}};
    assign m_axi_hbm12_arlen   = 8'd0;
    assign m_axi_hbm12_arsize  = 3'b101;
    assign m_axi_hbm12_arburst = 2'b01;
    assign m_axi_hbm12_arlock  = 2'b00;
    assign m_axi_hbm12_arcache = 4'b0011;
    assign m_axi_hbm12_arprot  = 3'b000;
    assign m_axi_hbm12_arqos   = 4'b0000;
    assign m_axi_hbm12_arvalid = 1'b0;
    assign m_axi_hbm12_rready  = 1'b0;

    // Write channels: address conversion + sideband tie-offs
    assign m_axi_hbm12_awid    = top_fl_awid;
    assign m_axi_hbm12_awaddr  = {top_fl_awaddr, 5'b00000};
    assign m_axi_hbm12_awlen   = top_fl_awlen;
    assign m_axi_hbm12_awsize  = 3'b101;
    assign m_axi_hbm12_awburst = 2'b01;
    assign m_axi_hbm12_awlock  = 2'b00;
    assign m_axi_hbm12_awcache = 4'b0011;
    assign m_axi_hbm12_awprot  = 3'b000;
    assign m_axi_hbm12_awqos   = 4'b0000;
    assign m_axi_hbm12_awvalid = top_fl_awvalid;
    assign top_fl_awready      = m_axi_hbm12_awready;
    assign m_axi_hbm12_wdata   = top_fl_wdata;
    assign m_axi_hbm12_wstrb   = {(C_M_AXI_DATA_WIDTH/8){1'b1}};  // all bytes valid
    assign m_axi_hbm12_wlast   = top_fl_wlast;
    assign m_axi_hbm12_wvalid  = top_fl_wvalid;
    assign top_fl_wready       = m_axi_hbm12_wready;
    assign top_fl_bid          = m_axi_hbm12_bid;
    assign top_fl_bresp        = m_axi_hbm12_bresp;
    assign top_fl_bvalid       = m_axi_hbm12_bvalid;
    assign m_axi_hbm12_bready  = top_fl_bready;

    // =========================================================================
    // hbm13: DMA port (read+write)
    // =========================================================================
    // Read channels
    assign m_axi_hbm13_arid    = top_dma_arid;
    assign m_axi_hbm13_araddr  = {top_dma_araddr, 5'b00000};
    assign m_axi_hbm13_arlen   = top_dma_arlen;
    assign m_axi_hbm13_arsize  = 3'b101;
    assign m_axi_hbm13_arburst = 2'b01;
    assign m_axi_hbm13_arlock  = 2'b00;
    assign m_axi_hbm13_arcache = 4'b0011;
    assign m_axi_hbm13_arprot  = 3'b000;
    assign m_axi_hbm13_arqos   = 4'b0000;
    assign m_axi_hbm13_arvalid = top_dma_arvalid;
    assign top_dma_arready     = m_axi_hbm13_arready;
    assign top_dma_rid         = m_axi_hbm13_rid;
    assign top_dma_rdata       = m_axi_hbm13_rdata;
    assign top_dma_rresp       = m_axi_hbm13_rresp;
    assign top_dma_rlast       = m_axi_hbm13_rlast;
    assign top_dma_rvalid      = m_axi_hbm13_rvalid;
    assign m_axi_hbm13_rready  = top_dma_rready;

    // Write channels
    assign m_axi_hbm13_awid    = top_dma_awid;
    assign m_axi_hbm13_awaddr  = {top_dma_awaddr, 5'b00000};
    assign m_axi_hbm13_awlen   = top_dma_awlen;
    assign m_axi_hbm13_awsize  = 3'b101;
    assign m_axi_hbm13_awburst = 2'b01;
    assign m_axi_hbm13_awlock  = 2'b00;
    assign m_axi_hbm13_awcache = 4'b0011;
    assign m_axi_hbm13_awprot  = 3'b000;
    assign m_axi_hbm13_awqos   = 4'b0000;
    assign m_axi_hbm13_awvalid = top_dma_awvalid;
    assign top_dma_awready     = m_axi_hbm13_awready;
    assign m_axi_hbm13_wdata   = top_dma_wdata;
    assign m_axi_hbm13_wstrb   = {(C_M_AXI_DATA_WIDTH/8){1'b1}};
    assign m_axi_hbm13_wlast   = top_dma_wlast;
    assign m_axi_hbm13_wvalid  = top_dma_wvalid;
    assign top_dma_wready      = m_axi_hbm13_wready;
    assign top_dma_bid         = m_axi_hbm13_bid;
    assign top_dma_bresp       = m_axi_hbm13_bresp;
    assign top_dma_bvalid      = m_axi_hbm13_bvalid;
    assign m_axi_hbm13_bready  = top_dma_bready;

endmodule
