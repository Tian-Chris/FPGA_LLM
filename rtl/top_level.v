`include "defines.vh"

// =============================================================================
// top_level.v — URAM Prefetch Transformer Inference Top Level
// =============================================================================
//
// Architecture:
//   Shared prefetch: hbm_prefetch(wgt) + uram_prefetch_buf(wgt) +
//                    hbm_prefetch(act) + uram_prefetch_buf(act)
//   Per engine:      matmul_controller (reads from prefetch URAMs)
//   Shared:          tiling_engine (coordinates prefetch + dispatch),
//                    uram_accum_buf,
//                    uram_flush + sim_hbm_port(flush),
//                    uram_nm_adapter (scalar↔URAM bridge),
//                    act_dma + sim_hbm_port(dma)
//   Non-matmul:      softmax, layernorm, activation, residual_add
//                    data R/W via uram_nm_adapter (URAM),
//                    LN params + res_sub via act_dma (HBM)
//   Control:         host_interface (AXI-Lite), fsm_controller
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

module diffusion_transformer_top #(
    parameter AXI_ADDR_WIDTH  = 32,
    parameter AXI_DATA_WIDTH  = 32,
    parameter SIM_HBM_DEPTH   = 65536,
    parameter SINGLE_MATMUL   = 0,
    parameter HBM_RD_LATENCY  = 2,    // sim_hbm_port initial read latency
    parameter URAM_RD_LATENCY = 1,    // uram_accum_buf read latency
    parameter ID_W_PARAM      = 4     // AXI ID width
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // AXI-Lite Slave Interface for host control
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,
    output wire [1:0]                   s_axi_bresp,
    output wire                         s_axi_bvalid,
    input  wire                         s_axi_bready,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,
    output wire [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    output wire                         s_axi_rvalid,
    input  wire                         s_axi_rready,

    output wire                         irq_done

`ifdef FPGA_TARGET
    ,
    // Interrupt
    output wire                         interrupt,

    // --- 4 AXI4 Read-Only Master Ports: Weight + Act Tile Loaders (2 engines) ---
    // Weight tile loaders (2x, read-only AR+R)
    output wire [ID_W_PARAM-1:0]        m_axi_wgt0_arid,
    output wire [HBM_ADDR_W-1:0]       m_axi_wgt0_araddr,
    output wire [7:0]                   m_axi_wgt0_arlen,
    output wire                         m_axi_wgt0_arvalid,
    input  wire                         m_axi_wgt0_arready,
    input  wire [ID_W_PARAM-1:0]        m_axi_wgt0_rid,
    input  wire [BUS_WIDTH-1:0]        m_axi_wgt0_rdata,
    input  wire [1:0]                   m_axi_wgt0_rresp,
    input  wire                         m_axi_wgt0_rlast,
    input  wire                         m_axi_wgt0_rvalid,
    output wire                         m_axi_wgt0_rready,

    output wire [ID_W_PARAM-1:0]        m_axi_wgt1_arid,
    output wire [HBM_ADDR_W-1:0]       m_axi_wgt1_araddr,
    output wire [7:0]                   m_axi_wgt1_arlen,
    output wire                         m_axi_wgt1_arvalid,
    input  wire                         m_axi_wgt1_arready,
    input  wire [ID_W_PARAM-1:0]        m_axi_wgt1_rid,
    input  wire [BUS_WIDTH-1:0]        m_axi_wgt1_rdata,
    input  wire [1:0]                   m_axi_wgt1_rresp,
    input  wire                         m_axi_wgt1_rlast,
    input  wire                         m_axi_wgt1_rvalid,
    output wire                         m_axi_wgt1_rready,

    // Activation tile loaders (2x, read-only AR+R)
    output wire [ID_W_PARAM-1:0]        m_axi_act0_arid,
    output wire [HBM_ADDR_W-1:0]       m_axi_act0_araddr,
    output wire [7:0]                   m_axi_act0_arlen,
    output wire                         m_axi_act0_arvalid,
    input  wire                         m_axi_act0_arready,
    input  wire [ID_W_PARAM-1:0]        m_axi_act0_rid,
    input  wire [BUS_WIDTH-1:0]        m_axi_act0_rdata,
    input  wire [1:0]                   m_axi_act0_rresp,
    input  wire                         m_axi_act0_rlast,
    input  wire                         m_axi_act0_rvalid,
    output wire                         m_axi_act0_rready,

    output wire [ID_W_PARAM-1:0]        m_axi_act1_arid,
    output wire [HBM_ADDR_W-1:0]       m_axi_act1_araddr,
    output wire [7:0]                   m_axi_act1_arlen,
    output wire                         m_axi_act1_arvalid,
    input  wire                         m_axi_act1_arready,
    input  wire [ID_W_PARAM-1:0]        m_axi_act1_rid,
    input  wire [BUS_WIDTH-1:0]        m_axi_act1_rdata,
    input  wire [1:0]                   m_axi_act1_rresp,
    input  wire                         m_axi_act1_rlast,
    input  wire                         m_axi_act1_rvalid,
    output wire                         m_axi_act1_rready,

    // --- Flush HBM Port (write-only AW+W+B) ---
    output wire [ID_W_PARAM-1:0]        m_axi_fl_awid,
    output wire [HBM_ADDR_W-1:0]       m_axi_fl_awaddr,
    output wire [7:0]                   m_axi_fl_awlen,
    output wire                         m_axi_fl_awvalid,
    input  wire                         m_axi_fl_awready,
    output wire [BUS_WIDTH-1:0]        m_axi_fl_wdata,
    output wire                         m_axi_fl_wlast,
    output wire                         m_axi_fl_wvalid,
    input  wire                         m_axi_fl_wready,
    input  wire [ID_W_PARAM-1:0]        m_axi_fl_bid,
    input  wire [1:0]                   m_axi_fl_bresp,
    input  wire                         m_axi_fl_bvalid,
    output wire                         m_axi_fl_bready,

    // --- DMA HBM Port (read+write: AR+R+AW+W+B) ---
    output wire [ID_W_PARAM-1:0]        m_axi_dma_arid,
    output wire [HBM_ADDR_W-1:0]       m_axi_dma_araddr,
    output wire [7:0]                   m_axi_dma_arlen,
    output wire                         m_axi_dma_arvalid,
    input  wire                         m_axi_dma_arready,
    input  wire [ID_W_PARAM-1:0]        m_axi_dma_rid,
    input  wire [BUS_WIDTH-1:0]        m_axi_dma_rdata,
    input  wire [1:0]                   m_axi_dma_rresp,
    input  wire                         m_axi_dma_rlast,
    input  wire                         m_axi_dma_rvalid,
    output wire                         m_axi_dma_rready,
    output wire [ID_W_PARAM-1:0]        m_axi_dma_awid,
    output wire [HBM_ADDR_W-1:0]       m_axi_dma_awaddr,
    output wire [7:0]                   m_axi_dma_awlen,
    output wire                         m_axi_dma_awvalid,
    input  wire                         m_axi_dma_awready,
    output wire [BUS_WIDTH-1:0]        m_axi_dma_wdata,
    output wire                         m_axi_dma_wlast,
    output wire                         m_axi_dma_wvalid,
    input  wire                         m_axi_dma_wready,
    input  wire [ID_W_PARAM-1:0]        m_axi_dma_bid,
    input  wire [1:0]                   m_axi_dma_bresp,
    input  wire                         m_axi_dma_bvalid,
    output wire                         m_axi_dma_bready
`endif
);

    // =========================================================================
    // Local Parameters
    // =========================================================================
    localparam DIM_W      = 16;
    localparam N_ENG      = NUM_ENGINES;        // 4
    localparam ID_W       = ID_W_PARAM;
    localparam LEN_W      = 8;
    localparam URAM_ROW_W = $clog2(URAM_ROWS);  // 10
    localparam URAM_COL_W = $clog2(URAM_COL_WORDS); // 8 (was 6, URAM_COLS=4096)

    // =========================================================================
    // Host Interface Signals
    // =========================================================================
    wire                        host_start;
    wire [DIM_W-1:0]            host_batch_size;
    wire [DIM_W-1:0]            host_seq_len;
    wire                        host_done;
    wire                        host_busy;
    wire [HBM_ADDR_W-1:0]      host_weight_base;
    wire [HBM_ADDR_W-1:0]      host_act_base;
    wire [HBM_ADDR_W-1:0]      host_kv_base;
    wire [HBM_ADDR_W-1:0]      host_output_base;
    wire                        host_decode_mode;
    wire [DIM_W-1:0]            host_cache_len;
    wire [DIM_W-1:0]            host_num_layers;
    wire [HBM_ADDR_W-1:0]      host_debug_base;

    // =========================================================================
    // FSM ↔ Debug Writer
    // =========================================================================
    wire                        fsm_dbg_wr_valid;
    wire [HBM_ADDR_W-1:0]      fsm_dbg_wr_addr;
    wire [255:0]                fsm_dbg_wr_data;
    wire                        dbg_wr_done;
    wire                        dbg_wr_busy;

    // FSM ↔ URAM Checkpoint Read
    wire                        fsm_chk_uram_rd_en;
    wire [9:0]                  fsm_chk_uram_rd_row;
    wire [7:0]                  fsm_chk_uram_rd_col;
    wire [255:0]                fsm_chk_uram_rd_data;
    wire                        fsm_chk_uram_rd_valid;

    // =========================================================================
    // FSM ↔ Tiling Engine (Matmul Command)
    // =========================================================================
    wire                        fsm_mm_cmd_valid;
    wire [2:0]                  fsm_mm_cmd_op;
    wire [DIM_W-1:0]            fsm_mm_cmd_m, fsm_mm_cmd_k, fsm_mm_cmd_n;
    wire [HBM_ADDR_W-1:0]      fsm_mm_cmd_a_base, fsm_mm_cmd_b_base;
    wire [HBM_ADDR_W-1:0]      fsm_mm_cmd_a_stride, fsm_mm_cmd_b_stride;
    wire [7:0]                  fsm_mm_cmd_out_col_offset;
    wire                        fsm_mm_cmd_has_bias;
    wire [HBM_ADDR_W-1:0]      fsm_mm_cmd_bias_base;
    wire [DIM_W-1:0]            fsm_mm_cmd_bias_words;
    wire                        mm_cmd_ready, mm_cmd_done;

    // =========================================================================
    // FSM ↔ URAM Flush
    // =========================================================================
    wire                        fsm_uf_start;
    wire [9:0]                  fsm_uf_num_rows;
    wire [7:0]                  fsm_uf_num_col_words;
    wire [7:0]                  fsm_uf_start_col;
    wire [HBM_ADDR_W-1:0]      fsm_uf_hbm_base, fsm_uf_hbm_stride;
    wire                        uf_done;

    // =========================================================================
    // FSM ↔ act_dma
    // =========================================================================
    wire [HBM_ADDR_W-1:0]      fsm_dma_rd_base, fsm_dma_wr_base;
    wire                        fsm_dma_flush;
    wire                        dma_flush_done;

    // =========================================================================
    // FSM ↔ Non-Matmul Adapter
    // =========================================================================
    wire [3:0]                  fsm_nm_cfg_col_bits;
    wire                        fsm_nm_adapter_flush;
    wire                        nm_adapter_flush_done;
    wire [NM_ADDR_W-1:0]        fsm_nm_addr_offset;

    // =========================================================================
    // URAM NM Adapter ↔ URAM
    // =========================================================================
    wire                        adp_uram_rd_en;
    wire [URAM_ROW_W-1:0]      adp_uram_rd_row;
    wire [URAM_COL_W-1:0]      adp_uram_rd_col_word;
    wire                        adp_uram_wr_en;
    wire [URAM_ROW_W-1:0]      adp_uram_wr_row;
    wire [URAM_COL_W-1:0]      adp_uram_wr_col_word;
    wire [BUS_WIDTH-1:0]       adp_uram_wr_data;

    // Adapter scalar port wires
    wire                        adp_rd_en;
    wire [NM_ADDR_W-1:0]      adp_rd_addr;
    wire [DATA_WIDTH-1:0]      adp_rd_data;
    wire                        adp_rd_valid;
    wire                        adp_wr_en;
    wire [NM_ADDR_W-1:0]      adp_wr_addr;
    wire [DATA_WIDTH-1:0]      adp_wr_data;

    // =========================================================================
    // FSM ↔ Sub-Unit Control
    // =========================================================================
    wire                        fsm_sm_start;
    wire [DIM_W-1:0]            fsm_sm_seq_len;
    wire [DIM_W-1:0]            fsm_sm_row_idx;
    wire [15:0]                 fsm_sm_scale_factor;
    wire                        sm_done, sm_busy;

    wire                        fsm_ln_start;
    wire [DIM_W-1:0]            fsm_ln_dim;
    wire                        ln_done, ln_busy;

    wire                        fsm_act_start;
    wire [DIM_W-1:0]            fsm_act_dim;
    wire                        act_unit_done;
    wire                        act_unit_busy;

    wire                        fsm_res_start;
    wire [DIM_W-1:0]            fsm_res_dim;
    wire                        res_done, res_busy;

    wire                        fsm_qu_start;
    wire [DIM_W-1:0]            fsm_qu_dim;
    wire [HBM_ADDR_W-1:0]      fsm_qu_src_base, fsm_qu_dst_base;
    wire                        qu_done;

    wire [5:0]                  current_state;
    wire [DIM_W-1:0]            current_layer;

    // =========================================================================
    // Tiling Engine ↔ Per-Engine Command Buses (URAM prefetch offsets)
    // =========================================================================
    localparam PF_ROW_W = $clog2(PREFETCH_ROWS);  // 10
    localparam PF_COL_W = $clog2(PREFETCH_COL_WORDS); // 6

    wire [N_ENG-1:0]                te_eng_cmd_valid;
    wire [3*N_ENG-1:0]              te_eng_cmd_op;
    wire [DIM_W*N_ENG-1:0]         te_eng_cmd_m, te_eng_cmd_k, te_eng_cmd_n;
    wire [PF_ROW_W*N_ENG-1:0]     te_eng_cmd_a_row_off, te_eng_cmd_b_row_off;
    wire [PF_COL_W*N_ENG-1:0]     te_eng_cmd_a_col_off, te_eng_cmd_b_col_off;
    wire [URAM_ROW_W*N_ENG-1:0]   te_eng_cmd_out_row;
    wire [URAM_COL_W*N_ENG-1:0]   te_eng_cmd_out_col_word;
    wire [N_ENG-1:0]                te_eng_cmd_first_k_chunk;
    wire [N_ENG-1:0]                te_eng_cmd_last_k_chunk;
    wire [N_ENG-1:0]                eng_cmd_ready, eng_cmd_done;

    // Bias: tiling_engine ↔ matmul_controller
    wire [HBM_ADDR_W-1:0]          te_bias_axi_araddr;
    wire [7:0]                      te_bias_axi_arlen;
    wire                            te_bias_axi_arvalid;
    wire                            te_bias_axi_arready;
    wire [BUS_WIDTH-1:0]           te_bias_axi_rdata;
    wire                            te_bias_axi_rvalid;
    wire                            te_bias_axi_rlast;
    wire                            te_bias_axi_rready;
    wire                            te_bias_loading;
    wire [7:0]                      eng_bias_rd_addr;
    wire [BUS_WIDTH-1:0]           te_bias_rd_data;
    wire                            te_bias_active;

    // =========================================================================
    // Prefetch Command Buses (tiling_engine ↔ hbm_prefetch)
    // =========================================================================
    wire        pf_act_cmd_valid, pf_act_cmd_ready, pf_act_cmd_done;
    wire [HBM_ADDR_W-1:0] pf_act_hbm_base, pf_act_hbm_stride;
    wire [DIM_W-1:0]      pf_act_num_rows;
    wire [DIM_W-1:0]      pf_act_num_col_words;

    wire        pf_wgt_cmd_valid, pf_wgt_cmd_ready, pf_wgt_cmd_done;
    wire [HBM_ADDR_W-1:0] pf_wgt_hbm_base, pf_wgt_hbm_stride;
    wire [DIM_W-1:0]      pf_wgt_num_rows;
    wire [DIM_W-1:0]      pf_wgt_num_col_words;

    // =========================================================================
    // Prefetch URAM Read Buses (per-engine matmul_controller ↔ uram_prefetch_buf)
    // =========================================================================
    wire [N_ENG-1:0]              eng_wgt_uram_rd_en;
    wire [PF_ROW_W*N_ENG-1:0]   eng_wgt_uram_rd_row;
    wire [PF_COL_W*N_ENG-1:0]   eng_wgt_uram_rd_col_word;

    wire [N_ENG-1:0]              eng_act_uram_rd_en;
    wire [PF_ROW_W*N_ENG-1:0]   eng_act_uram_rd_row;
    wire [PF_COL_W*N_ENG-1:0]   eng_act_uram_rd_col_word;

    // Shared read data/valid from prefetch buffers (broadcast to all engines)
    wire [BUS_WIDTH-1:0]  pf_wgt_rd_data;
    wire                   pf_wgt_rd_valid;
    wire [BUS_WIDTH-1:0]  pf_act_rd_data;
    wire                   pf_act_rd_valid;

    // Prefetch URAM write buses (hbm_prefetch → uram_prefetch_buf)
    wire                   pf_wgt_wr_en;
    wire [PF_ROW_W-1:0]  pf_wgt_wr_row;
    wire [PF_COL_W-1:0]  pf_wgt_wr_col_word;
    wire [BUS_WIDTH-1:0] pf_wgt_wr_data;

    wire                   pf_act_wr_en;
    wire [PF_ROW_W-1:0]  pf_act_wr_row;
    wire [PF_COL_W-1:0]  pf_act_wr_col_word;
    wire [BUS_WIDTH-1:0] pf_act_wr_data;

    // =========================================================================
    // Per-Engine URAM Write Buses (packed for uram_accum_buf)
    // =========================================================================
    wire [N_ENG-1:0]                eng_uram_wr_en;
    wire [URAM_ROW_W*N_ENG-1:0]   eng_uram_wr_row;
    wire [URAM_COL_W*N_ENG-1:0]   eng_uram_wr_col_word;
    wire [BUS_WIDTH*N_ENG-1:0]    eng_uram_wr_data;
    wire [N_ENG-1:0]              eng_uram_wr_accum;
    wire [N_ENG-1:0]              eng_uram_wr_accept;

    // =========================================================================
    // URAM Flush ↔ uram_accum_buf Read
    // =========================================================================
    wire                        uf_uram_rd_en;
    wire [URAM_ROW_W-1:0]      uf_uram_rd_row;
    wire [URAM_COL_W-1:0]      uf_uram_rd_col_word;
    wire [BUS_WIDTH-1:0]       uf_uram_rd_data;
    wire                        uf_uram_rd_valid;

    // =========================================================================
    // Non-Matmul Unit Memory Signals (scalar)
    // =========================================================================
    wire        sm_rd_en, sm_wr_en;
    wire [15:0] sm_rd_addr, sm_wr_addr;
    wire [DATA_WIDTH-1:0] sm_rd_data;
    wire [DATA_WIDTH-1:0] sm_wr_data;

    wire        ln_rd_en, ln_wr_en, ln_param_rd_en;
    wire [15:0] ln_rd_addr, ln_wr_addr, ln_param_addr;
    wire [DATA_WIDTH-1:0] ln_rd_data;
    wire [15:0] ln_gamma, ln_beta;
    wire [DATA_WIDTH-1:0] ln_wr_data;

    wire        au_rd_en, au_wr_en;
    wire [15:0] au_rd_addr, au_wr_addr;
    wire [DATA_WIDTH-1:0] au_rd_data, au_wr_data;
    wire        au_rd_valid;

    wire        res_rd_en, res_wr_en, res_sub_rd_en;
    wire [15:0] res_rd_addr, res_wr_addr, res_sub_addr;
    wire [DATA_WIDTH-1:0] res_rd_data, res_wr_data, res_sub_data;
    wire        res_rd_valid, res_sub_valid;

    // Quant layer (256-bit bus interface)
    wire        qu_rd_en, qu_wr_en;
    wire [ADDR_WIDTH-1:0] qu_rd_addr, qu_wr_addr;
    wire [BUS_WIDTH-1:0]  qu_rd_data, qu_wr_data;
    wire        qu_rd_valid;

    // act_dma scalar interface
    wire        dma_rd_en;
    wire [15:0] dma_rd_addr;
    wire [DATA_WIDTH-1:0] dma_rd_data;
    wire        dma_rd_valid;
    wire        dma_wr_en;
    wire [15:0] dma_wr_addr;
    wire [DATA_WIDTH-1:0] dma_wr_data;

    // =========================================================================
    // Host Interface (AXI-Lite)
    // =========================================================================
`ifdef FPGA_TARGET
    vitis_control #(
        .AXI_ADDR_WIDTH(7),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_vitis_ctrl (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr[6:0]), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr[6:0]), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .start(host_start),
        .batch_size(host_batch_size),
        .seq_len(host_seq_len),
        .weight_base(host_weight_base),
        .act_base(host_act_base),
        .kv_base(host_kv_base),
        .output_base(host_output_base),
        .decode_mode(host_decode_mode),
        .cache_len(host_cache_len),
        .done(host_done),
        .busy(host_busy),
        .current_state(current_state[4:0]),
        .current_layer(current_layer),
        .num_layers(host_num_layers),
        .debug_base(host_debug_base),
        .interrupt(interrupt)
    );
`else
    host_interface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_host_if (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .start(host_start),
        .batch_size(host_batch_size),
        .seq_len(host_seq_len),
        .weight_base(host_weight_base),
        .act_base(host_act_base),
        .kv_base(host_kv_base),
        .output_base(host_output_base),
        .decode_mode(host_decode_mode),
        .cache_len(host_cache_len),
        .num_layers(host_num_layers),
        .debug_base(host_debug_base),
        .done(host_done),
        .busy(host_busy),
        .current_state(current_state[4:0]),
        .current_layer(current_layer)
    );
`endif

    assign irq_done = host_done;

    // =========================================================================
    // FSM Controller
    // =========================================================================
    fsm_controller #(
        .MODEL_DIM(MODEL_DIM),
        .INPUT_DIM(INPUT_DIM),
        .F_DIM(F_DIM),
        .NUM_HEADS(NUM_HEADS),
        .MAX_SEQ_LEN(MAX_SEQ_LEN),
        .NUM_DIFF_STEPS(NUM_DIFFUSION_STEPS),
        .SINGLE_MATMUL(SINGLE_MATMUL),
        .ARCH(ARCHITECTURE)
    ) u_fsm (
        .clk(clk), .rst_n(rst_n),
        .start(host_start),
        .batch_size(host_batch_size),
        .seq_len(host_seq_len),
        .decode_mode(host_decode_mode),
        .cache_len(host_cache_len),
        .num_layers(host_num_layers),
        .done(host_done),
        .busy(host_busy),
        .weight_base(host_weight_base),
        .act_base(host_act_base),
        .kv_base(host_kv_base),
        .output_base(host_output_base),
        .mm_cmd_valid(fsm_mm_cmd_valid),
        .mm_cmd_op(fsm_mm_cmd_op),
        .mm_cmd_m(fsm_mm_cmd_m),
        .mm_cmd_k(fsm_mm_cmd_k),
        .mm_cmd_n(fsm_mm_cmd_n),
        .mm_cmd_a_base(fsm_mm_cmd_a_base),
        .mm_cmd_b_base(fsm_mm_cmd_b_base),
        .mm_cmd_a_stride(fsm_mm_cmd_a_stride),
        .mm_cmd_b_stride(fsm_mm_cmd_b_stride),
        .mm_cmd_out_col_offset(fsm_mm_cmd_out_col_offset),
        .mm_cmd_has_bias(fsm_mm_cmd_has_bias),
        .mm_cmd_bias_base(fsm_mm_cmd_bias_base),
        .mm_cmd_bias_words(fsm_mm_cmd_bias_words),
        .mm_cmd_ready(mm_cmd_ready),
        .mm_cmd_done(mm_cmd_done),
        .uram_flush_start(fsm_uf_start),
        .uram_flush_num_rows(fsm_uf_num_rows),
        .uram_flush_num_col_words(fsm_uf_num_col_words),
        .uram_flush_start_col(fsm_uf_start_col),
        .uram_flush_hbm_base(fsm_uf_hbm_base),
        .uram_flush_hbm_stride(fsm_uf_hbm_stride),
        .uram_flush_done(uf_done),
        .nm_cfg_col_bits(fsm_nm_cfg_col_bits),
        .nm_adapter_flush(fsm_nm_adapter_flush),
        .nm_adapter_flush_done(nm_adapter_flush_done),
        .nm_addr_offset(fsm_nm_addr_offset),
        .act_dma_rd_base(fsm_dma_rd_base),
        .act_dma_wr_base(fsm_dma_wr_base),
        .act_dma_flush(fsm_dma_flush),
        .act_dma_flush_done(dma_flush_done),
        .sm_start(fsm_sm_start),
        .sm_seq_len(fsm_sm_seq_len),
        .sm_row_idx(fsm_sm_row_idx),
        .sm_scale_factor(fsm_sm_scale_factor),
        .sm_done(sm_done), .sm_busy(sm_busy),
        .ln_start(fsm_ln_start),
        .ln_dim(fsm_ln_dim),
        .ln_done(ln_done), .ln_busy(ln_busy),
        .act_start(fsm_act_start),
        .act_dim(fsm_act_dim),
        .act_done(act_unit_done),
        .act_busy(act_unit_busy),
        .res_start(fsm_res_start),
        .res_dim(fsm_res_dim),
        .res_done(res_done), .res_busy(res_busy),
        .quant_start(fsm_qu_start),
        .quant_dim(fsm_qu_dim),
        .quant_src_base(fsm_qu_src_base),
        .quant_dst_base(fsm_qu_dst_base),
        .quant_done(qu_done),
        .current_state(current_state),
        .current_layer(current_layer),
        .debug_base(host_debug_base),
        .dbg_wr_valid(fsm_dbg_wr_valid),
        .dbg_wr_addr(fsm_dbg_wr_addr),
        .dbg_wr_data(fsm_dbg_wr_data),
        .dbg_wr_done(dbg_wr_done),
        .dbg_wr_busy(dbg_wr_busy),
        .chk_uram_rd_en(fsm_chk_uram_rd_en),
        .chk_uram_rd_row(fsm_chk_uram_rd_row),
        .chk_uram_rd_col(fsm_chk_uram_rd_col),
        .chk_uram_rd_data(fsm_chk_uram_rd_data),
        .chk_uram_rd_valid(fsm_chk_uram_rd_valid)
    );

    // =========================================================================
    // Tiling Engine
    // =========================================================================
    tiling_engine #(
        .N_ENG(N_ENG), .TILE(TILE_SIZE), .DIM_W(DIM_W),
        .URAM_ROW_W(URAM_ROW_W), .URAM_COL_W(URAM_COL_W),
        .PF_ROW_W(PF_ROW_W), .PF_COL_W(PF_COL_W),
        .PREFETCH_DIM(PREFETCH_ROWS)
    ) u_tiling_engine (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid(fsm_mm_cmd_valid),
        .cmd_op(fsm_mm_cmd_op),
        .cmd_m(fsm_mm_cmd_m),
        .cmd_k(fsm_mm_cmd_k),
        .cmd_n(fsm_mm_cmd_n),
        .cmd_a_base(fsm_mm_cmd_a_base),
        .cmd_b_base(fsm_mm_cmd_b_base),
        .cmd_a_stride(fsm_mm_cmd_a_stride),
        .cmd_b_stride(fsm_mm_cmd_b_stride),
        .cmd_out_col_offset(fsm_mm_cmd_out_col_offset[URAM_COL_W-1:0]),
        .cmd_has_bias(fsm_mm_cmd_has_bias),
        .cmd_bias_base(fsm_mm_cmd_bias_base),
        .cmd_bias_words(fsm_mm_cmd_bias_words),
        .cmd_ready(mm_cmd_ready),
        .cmd_done(mm_cmd_done),
        // Prefetch commands
        .pf_act_cmd_valid(pf_act_cmd_valid),
        .pf_act_cmd_ready(pf_act_cmd_ready),
        .pf_act_cmd_done(pf_act_cmd_done),
        .pf_act_hbm_base(pf_act_hbm_base),
        .pf_act_hbm_stride(pf_act_hbm_stride),
        .pf_act_num_rows(pf_act_num_rows),
        .pf_act_num_col_words(pf_act_num_col_words),
        .pf_wgt_cmd_valid(pf_wgt_cmd_valid),
        .pf_wgt_cmd_ready(pf_wgt_cmd_ready),
        .pf_wgt_cmd_done(pf_wgt_cmd_done),
        .pf_wgt_hbm_base(pf_wgt_hbm_base),
        .pf_wgt_hbm_stride(pf_wgt_hbm_stride),
        .pf_wgt_num_rows(pf_wgt_num_rows),
        .pf_wgt_num_col_words(pf_wgt_num_col_words),
        // Per-engine dispatch
        .eng_cmd_valid(te_eng_cmd_valid),
        .eng_cmd_op(te_eng_cmd_op),
        .eng_cmd_m(te_eng_cmd_m),
        .eng_cmd_k(te_eng_cmd_k),
        .eng_cmd_n(te_eng_cmd_n),
        .eng_cmd_a_row_off(te_eng_cmd_a_row_off),
        .eng_cmd_a_col_off(te_eng_cmd_a_col_off),
        .eng_cmd_b_row_off(te_eng_cmd_b_row_off),
        .eng_cmd_b_col_off(te_eng_cmd_b_col_off),
        .eng_cmd_out_row(te_eng_cmd_out_row),
        .eng_cmd_out_col_word(te_eng_cmd_out_col_word),
        .eng_cmd_first_k_chunk(te_eng_cmd_first_k_chunk),
        .eng_cmd_last_k_chunk(te_eng_cmd_last_k_chunk),
        .eng_cmd_ready(eng_cmd_ready),
        .eng_cmd_done(eng_cmd_done),
        // Bias AXI read (time-shared with weight prefetch port)
        .bias_axi_araddr(te_bias_axi_araddr),
        .bias_axi_arlen(te_bias_axi_arlen),
        .bias_axi_arvalid(te_bias_axi_arvalid),
        .bias_axi_arready(te_bias_axi_arready),
        .bias_axi_rdata(te_bias_axi_rdata),
        .bias_axi_rvalid(te_bias_axi_rvalid),
        .bias_axi_rlast(te_bias_axi_rlast),
        .bias_axi_rready(te_bias_axi_rready),
        .bias_loading(te_bias_loading),
        // Bias read port (matmul controller reads)
        .bias_rd_addr(eng_bias_rd_addr),
        .bias_rd_data(te_bias_rd_data),
        .bias_active(te_bias_active)
    );

    // =========================================================================
    // Per-Engine: matmul_controller (reads from shared prefetch URAMs)
    // =========================================================================
    genvar e;
    generate
        for (e = 0; e < N_ENG; e = e + 1) begin : gen_eng
            matmul_controller #(
                .URAM_ROW_W(URAM_ROW_W), .URAM_COL_W(URAM_COL_W),
                .PF_ROW_W(PF_ROW_W), .PF_COL_W(PF_COL_W)
            ) u_mc (
                .clk(clk), .rst_n(rst_n),
                .cmd_valid(te_eng_cmd_valid[e]),
                .cmd_op(te_eng_cmd_op[e*3 +: 3]),
                .cmd_m(te_eng_cmd_m[e*DIM_W +: DIM_W]),
                .cmd_k(te_eng_cmd_k[e*DIM_W +: DIM_W]),
                .cmd_n(te_eng_cmd_n[e*DIM_W +: DIM_W]),
                .cmd_a_row_off(te_eng_cmd_a_row_off[e*PF_ROW_W +: PF_ROW_W]),
                .cmd_a_col_off(te_eng_cmd_a_col_off[e*PF_COL_W +: PF_COL_W]),
                .cmd_b_row_off(te_eng_cmd_b_row_off[e*PF_ROW_W +: PF_ROW_W]),
                .cmd_b_col_off(te_eng_cmd_b_col_off[e*PF_COL_W +: PF_COL_W]),
                .cmd_out_row(te_eng_cmd_out_row[e*URAM_ROW_W +: URAM_ROW_W]),
                .cmd_out_col_word(te_eng_cmd_out_col_word[e*URAM_COL_W +: URAM_COL_W]),
                .cmd_first_k_chunk(te_eng_cmd_first_k_chunk[e]),
                .cmd_last_k_chunk(te_eng_cmd_last_k_chunk[e]),
                .cmd_has_bias(te_bias_active),
                .cmd_ready(eng_cmd_ready[e]),
                .cmd_done(eng_cmd_done[e]),
                // Weight URAM prefetch read
                .wgt_uram_rd_en(eng_wgt_uram_rd_en[e]),
                .wgt_uram_rd_row(eng_wgt_uram_rd_row[e*PF_ROW_W +: PF_ROW_W]),
                .wgt_uram_rd_col_word(eng_wgt_uram_rd_col_word[e*PF_COL_W +: PF_COL_W]),
                .wgt_uram_rd_data(pf_wgt_rd_data),
                .wgt_uram_rd_valid(pf_wgt_rd_valid),
                // Activation URAM prefetch read
                .act_uram_rd_en(eng_act_uram_rd_en[e]),
                .act_uram_rd_row(eng_act_uram_rd_row[e*PF_ROW_W +: PF_ROW_W]),
                .act_uram_rd_col_word(eng_act_uram_rd_col_word[e*PF_COL_W +: PF_COL_W]),
                .act_uram_rd_data(pf_act_rd_data),
                .act_uram_rd_valid(pf_act_rd_valid),
                // URAM accum write
                .uram_wr_en(eng_uram_wr_en[e]),
                .uram_wr_row(eng_uram_wr_row[e*URAM_ROW_W +: URAM_ROW_W]),
                .uram_wr_col_word(eng_uram_wr_col_word[e*URAM_COL_W +: URAM_COL_W]),
                .uram_wr_data(eng_uram_wr_data[e*BUS_WIDTH +: BUS_WIDTH]),
                .uram_wr_accum(eng_uram_wr_accum[e]),
                .uram_wr_accept(eng_uram_wr_accept[e]),
                // Bias read
                .bias_rd_addr(eng_bias_rd_addr),
                .bias_rd_data(te_bias_rd_data)
            );
        end
    endgenerate

    // =========================================================================
    // Shared URAM Prefetch Buffers + HBM Prefetch DMA Engines
    // =========================================================================
    // With N_ENG=1, no read-port arbitration needed. Engine 0 reads directly.
    // For multi-engine, only engine 0's read signals are connected (single engine debug).

    // --- Weight prefetch URAM buffer ---
    uram_prefetch_buf #(
        .ROWS(PREFETCH_ROWS), .COLS(PREFETCH_COLS),
        .ROW_W(PF_ROW_W), .COL_W(PF_COL_W)
    ) u_pf_wgt_buf (
        .clk(clk),
        .wr_en(pf_wgt_wr_en),
        .wr_row(pf_wgt_wr_row),
        .wr_col_word(pf_wgt_wr_col_word),
        .wr_data(pf_wgt_wr_data),
        .rd_en(eng_wgt_uram_rd_en[0]),
        .rd_row(eng_wgt_uram_rd_row[0*PF_ROW_W +: PF_ROW_W]),
        .rd_col_word(eng_wgt_uram_rd_col_word[0*PF_COL_W +: PF_COL_W]),
        .rd_data(pf_wgt_rd_data),
        .rd_valid(pf_wgt_rd_valid)
    );

    // --- Activation prefetch URAM buffer ---
    uram_prefetch_buf #(
        .ROWS(PREFETCH_ROWS), .COLS(PREFETCH_COLS),
        .ROW_W(PF_ROW_W), .COL_W(PF_COL_W)
    ) u_pf_act_buf (
        .clk(clk),
        .wr_en(pf_act_wr_en),
        .wr_row(pf_act_wr_row),
        .wr_col_word(pf_act_wr_col_word),
        .wr_data(pf_act_wr_data),
        .rd_en(eng_act_uram_rd_en[0]),
        .rd_row(eng_act_uram_rd_row[0*PF_ROW_W +: PF_ROW_W]),
        .rd_col_word(eng_act_uram_rd_col_word[0*PF_COL_W +: PF_COL_W]),
        .rd_data(pf_act_rd_data),
        .rd_valid(pf_act_rd_valid)
    );

    // --- Weight HBM Prefetch DMA ---
    wire [ID_W-1:0]        pf_wgt_arid;
    wire [HBM_ADDR_W-1:0] pf_wgt_araddr;
    wire [LEN_W-1:0]      pf_wgt_arlen;
    wire                   pf_wgt_arvalid, pf_wgt_arready;
    wire [ID_W-1:0]        pf_wgt_rid;
    wire [BUS_WIDTH-1:0]  pf_wgt_rdata;
    wire [1:0]            pf_wgt_rresp;
    wire                   pf_wgt_rlast, pf_wgt_rvalid, pf_wgt_rready;

    hbm_prefetch #(
        .ROW_W(PF_ROW_W), .COL_W(PF_COL_W)
    ) u_pf_wgt (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid(pf_wgt_cmd_valid),
        .cmd_ready(pf_wgt_cmd_ready),
        .cmd_done(pf_wgt_cmd_done),
        .cmd_hbm_base(pf_wgt_hbm_base),
        .cmd_hbm_stride(pf_wgt_hbm_stride),
        .cmd_num_rows(pf_wgt_num_rows),
        .cmd_num_col_words(pf_wgt_num_col_words),
        .m_axi_arid(pf_wgt_arid), .m_axi_araddr(pf_wgt_araddr),
        .m_axi_arlen(pf_wgt_arlen), .m_axi_arvalid(pf_wgt_arvalid),
        .m_axi_arready(pf_wgt_arready),
        .m_axi_rid(pf_wgt_rid), .m_axi_rdata(pf_wgt_rdata),
        .m_axi_rresp(pf_wgt_rresp), .m_axi_rlast(pf_wgt_rlast),
        .m_axi_rvalid(pf_wgt_rvalid), .m_axi_rready(pf_wgt_rready),
        .uram_wr_en(pf_wgt_wr_en),
        .uram_wr_row(pf_wgt_wr_row),
        .uram_wr_col_word(pf_wgt_wr_col_word),
        .uram_wr_data(pf_wgt_wr_data)
    );

    // --- Activation HBM Prefetch DMA ---
    wire [ID_W-1:0]        pf_act_arid;
    wire [HBM_ADDR_W-1:0] pf_act_araddr;
    wire [LEN_W-1:0]      pf_act_arlen;
    wire                   pf_act_arvalid, pf_act_arready;
    wire [ID_W-1:0]        pf_act_rid;
    wire [BUS_WIDTH-1:0]  pf_act_rdata;
    wire [1:0]            pf_act_rresp;
    wire                   pf_act_rlast, pf_act_rvalid, pf_act_rready;

    hbm_prefetch #(
        .ROW_W(PF_ROW_W), .COL_W(PF_COL_W)
    ) u_pf_act (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid(pf_act_cmd_valid),
        .cmd_ready(pf_act_cmd_ready),
        .cmd_done(pf_act_cmd_done),
        .cmd_hbm_base(pf_act_hbm_base),
        .cmd_hbm_stride(pf_act_hbm_stride),
        .cmd_num_rows(pf_act_num_rows),
        .cmd_num_col_words(pf_act_num_col_words),
        .m_axi_arid(pf_act_arid), .m_axi_araddr(pf_act_araddr),
        .m_axi_arlen(pf_act_arlen), .m_axi_arvalid(pf_act_arvalid),
        .m_axi_arready(pf_act_arready),
        .m_axi_rid(pf_act_rid), .m_axi_rdata(pf_act_rdata),
        .m_axi_rresp(pf_act_rresp), .m_axi_rlast(pf_act_rlast),
        .m_axi_rvalid(pf_act_rvalid), .m_axi_rready(pf_act_rready),
        .uram_wr_en(pf_act_wr_en),
        .uram_wr_row(pf_act_wr_row),
        .uram_wr_col_word(pf_act_wr_col_word),
        .uram_wr_data(pf_act_wr_data)
    );

    // =========================================================================
    // FPGA Target: Wire prefetch AXI to module ports, tie off unused ports
    // =========================================================================
`ifdef FPGA_TARGET
    // wgt0 → weight prefetch DMA
    assign m_axi_wgt0_arid    = pf_wgt_arid;
    assign m_axi_wgt0_araddr  = pf_wgt_araddr;
    assign m_axi_wgt0_arlen   = pf_wgt_arlen;
    assign m_axi_wgt0_arvalid = pf_wgt_arvalid;
    assign m_axi_wgt0_rready  = pf_wgt_rready;
    assign pf_wgt_arready     = m_axi_wgt0_arready;
    assign pf_wgt_rid         = m_axi_wgt0_rid;
    assign pf_wgt_rdata       = m_axi_wgt0_rdata;
    assign pf_wgt_rresp       = m_axi_wgt0_rresp;
    assign pf_wgt_rlast       = m_axi_wgt0_rlast;
    assign pf_wgt_rvalid      = m_axi_wgt0_rvalid;

    // act0 → activation prefetch DMA
    assign m_axi_act0_arid    = pf_act_arid;
    assign m_axi_act0_araddr  = pf_act_araddr;
    assign m_axi_act0_arlen   = pf_act_arlen;
    assign m_axi_act0_arvalid = pf_act_arvalid;
    assign m_axi_act0_rready  = pf_act_rready;
    assign pf_act_arready     = m_axi_act0_arready;
    assign pf_act_rid         = m_axi_act0_rid;
    assign pf_act_rdata       = m_axi_act0_rdata;
    assign pf_act_rresp       = m_axi_act0_rresp;
    assign pf_act_rlast       = m_axi_act0_rlast;
    assign pf_act_rvalid      = m_axi_act0_rvalid;

    // wgt1 → bias loader
    assign m_axi_wgt1_arid    = {ID_W_PARAM{1'b0}};
    assign m_axi_wgt1_araddr  = te_bias_axi_araddr;
    assign m_axi_wgt1_arlen   = te_bias_axi_arlen;
    assign m_axi_wgt1_arvalid = te_bias_axi_arvalid;
    assign m_axi_wgt1_rready  = te_bias_axi_rready;
    assign te_bias_axi_arready = m_axi_wgt1_arready;
    assign te_bias_axi_rdata   = m_axi_wgt1_rdata;
    assign te_bias_axi_rvalid  = m_axi_wgt1_rvalid;
    assign te_bias_axi_rlast   = m_axi_wgt1_rlast;

    // act1 → tied off (kept for Vitis port layout)
    assign m_axi_act1_arid    = {ID_W_PARAM{1'b0}};
    assign m_axi_act1_araddr  = {HBM_ADDR_W{1'b0}};
    assign m_axi_act1_arlen   = 8'd0;
    assign m_axi_act1_arvalid = 1'b0;
    assign m_axi_act1_rready  = 1'b0;

`else
    // Simulation: shared HBM — ports 0/1 read-only, port 2 write-only, port 3 read+write
    // Declared here; flush and DMA ports connected below via assign
    wire [ID_W-1:0]        hbm_p2_bid;
    wire [1:0]             hbm_p2_bresp;
    wire                   hbm_p2_bvalid;
    wire                   hbm_p2_awready;
    wire                   hbm_p2_wready;

    wire [ID_W-1:0]        hbm_p3_rid;
    wire [BUS_WIDTH-1:0]   hbm_p3_rdata;
    wire [1:0]             hbm_p3_rresp;
    wire                   hbm_p3_rlast;
    wire                   hbm_p3_rvalid;
    wire                   hbm_p3_arready;
    wire [ID_W-1:0]        hbm_p3_bid;
    wire [1:0]             hbm_p3_bresp;
    wire                   hbm_p3_bvalid;
    wire                   hbm_p3_awready;
    wire                   hbm_p3_wready;

    sim_hbm #(
        .DEPTH(SIM_HBM_DEPTH),
        .RD_LATENCY_CYCLES(HBM_RD_LATENCY)
    ) u_hbm (
        .clk(clk), .rst_n(rst_n),
        // Port 0: weight prefetch (read-only) — unchanged
        .p0_arid(pf_wgt_arid), .p0_araddr(pf_wgt_araddr),
        .p0_arlen(pf_wgt_arlen), .p0_arvalid(pf_wgt_arvalid),
        .p0_arready(pf_wgt_arready),
        .p0_rid(pf_wgt_rid), .p0_rdata(pf_wgt_rdata),
        .p0_rresp(pf_wgt_rresp), .p0_rlast(pf_wgt_rlast),
        .p0_rvalid(pf_wgt_rvalid), .p0_rready(pf_wgt_rready),
        // Port 1: activation prefetch (read-only)
        .p1_arid(pf_act_arid), .p1_araddr(pf_act_araddr),
        .p1_arlen(pf_act_arlen), .p1_arvalid(pf_act_arvalid),
        .p1_arready(pf_act_arready),
        .p1_rid(pf_act_rid), .p1_rdata(pf_act_rdata),
        .p1_rresp(pf_act_rresp), .p1_rlast(pf_act_rlast),
        .p1_rvalid(pf_act_rvalid), .p1_rready(pf_act_rready),
        // Port 2: flush (write-only)
        .p2_awid(fl_awid), .p2_awaddr(fl_awaddr),
        .p2_awlen(fl_awlen), .p2_awvalid(fl_awvalid),
        .p2_awready(hbm_p2_awready),
        .p2_wdata(fl_wdata), .p2_wlast(fl_wlast),
        .p2_wvalid(fl_wvalid), .p2_wready(hbm_p2_wready),
        .p2_bid(hbm_p2_bid), .p2_bresp(hbm_p2_bresp),
        .p2_bvalid(hbm_p2_bvalid), .p2_bready(fl_bready),
        // Port 3: DMA (read+write)
        .p3_arid(dma_axi_arid), .p3_araddr(dma_axi_araddr),
        .p3_arlen(dma_axi_arlen), .p3_arvalid(dma_axi_arvalid),
        .p3_arready(hbm_p3_arready),
        .p3_rid(hbm_p3_rid), .p3_rdata(hbm_p3_rdata),
        .p3_rresp(hbm_p3_rresp), .p3_rlast(hbm_p3_rlast),
        .p3_rvalid(hbm_p3_rvalid), .p3_rready(dma_axi_rready),
        .p3_awid(dma_axi_awid), .p3_awaddr(dma_axi_awaddr),
        .p3_awlen(dma_axi_awlen), .p3_awvalid(dma_axi_awvalid),
        .p3_awready(hbm_p3_awready),
        .p3_wdata(dma_axi_wdata), .p3_wlast(dma_axi_wlast),
        .p3_wvalid(dma_axi_wvalid), .p3_wready(hbm_p3_wready),
        .p3_bid(hbm_p3_bid), .p3_bresp(hbm_p3_bresp),
        .p3_bvalid(hbm_p3_bvalid), .p3_bready(dma_axi_bready),
        // Port 4: bias loader (read-only)
        .p4_arid({ID_W{1'b0}}), .p4_araddr(te_bias_axi_araddr),
        .p4_arlen(te_bias_axi_arlen), .p4_arvalid(te_bias_axi_arvalid),
        .p4_arready(te_bias_axi_arready),
        .p4_rid(), .p4_rdata(te_bias_axi_rdata),
        .p4_rresp(), .p4_rlast(te_bias_axi_rlast),
        .p4_rvalid(te_bias_axi_rvalid), .p4_rready(te_bias_axi_rready)
    );
`endif

    // =========================================================================
    // URAM Read Port Mux (flush vs adapter vs checkpoint — FSM mutual exclusion)
    // =========================================================================
    wire                   uram_rd_en_mux;
    wire [URAM_ROW_W-1:0] uram_rd_row_mux;
    wire [URAM_COL_W-1:0] uram_rd_col_mux;
    wire [BUS_WIDTH-1:0]  uram_rd_data_mux;
    wire                   uram_rd_valid_mux;

    assign uram_rd_en_mux  = uf_uram_rd_en | adp_uram_rd_en | fsm_chk_uram_rd_en;
    assign uram_rd_row_mux = uf_uram_rd_en   ? uf_uram_rd_row :
                             adp_uram_rd_en  ? adp_uram_rd_row :
                                               fsm_chk_uram_rd_row[URAM_ROW_W-1:0];
    assign uram_rd_col_mux = uf_uram_rd_en   ? uf_uram_rd_col_word :
                             adp_uram_rd_en  ? adp_uram_rd_col_word :
                                               fsm_chk_uram_rd_col[URAM_COL_W-1:0];

    // URAM read ownership tracking — gate rd_valid per consumer
    // Shift register matches URAM_RD_LATENCY to align valid with the issuer
    reg [URAM_RD_LATENCY-1:0] uram_rd_owner_is_flush;
    reg [URAM_RD_LATENCY-1:0] uram_rd_owner_is_chk;
    integer sr_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uram_rd_owner_is_flush <= {URAM_RD_LATENCY{1'b0}};
            uram_rd_owner_is_chk   <= {URAM_RD_LATENCY{1'b0}};
        end else begin
            uram_rd_owner_is_flush[0] <= uf_uram_rd_en;
            uram_rd_owner_is_chk[0]   <= fsm_chk_uram_rd_en;
            for (sr_i = 1; sr_i < URAM_RD_LATENCY; sr_i = sr_i + 1) begin
                uram_rd_owner_is_flush[sr_i] <= uram_rd_owner_is_flush[sr_i-1];
                uram_rd_owner_is_chk[sr_i]   <= uram_rd_owner_is_chk[sr_i-1];
            end
        end
    end
    wire uram_rd_for_flush = uram_rd_owner_is_flush[URAM_RD_LATENCY-1];
    wire uram_rd_for_chk   = uram_rd_owner_is_chk[URAM_RD_LATENCY-1];
    wire adp_uram_rd_valid = uram_rd_valid_mux & ~uram_rd_for_flush & ~uram_rd_for_chk;

    assign uf_uram_rd_data  = uram_rd_data_mux;
    assign uf_uram_rd_valid = uram_rd_valid_mux & uram_rd_for_flush;

    // Checkpoint URAM read data/valid back to FSM
    assign fsm_chk_uram_rd_data  = uram_rd_data_mux;
    assign fsm_chk_uram_rd_valid = uram_rd_valid_mux & uram_rd_for_chk;

    // =========================================================================
    // URAM Accumulation Buffer
    // =========================================================================
    uram_accum_buf #(
        .ROWS(URAM_ROWS), .COLS(URAM_COLS),
        .N_ENG(N_ENG), .ROW_W(URAM_ROW_W), .COL_W(URAM_COL_W),
        .RD_LATENCY(URAM_RD_LATENCY)
    ) u_uram (
        .clk(clk), .rst_n(rst_n), .clear(1'b0),
        .eng_wr_en(eng_uram_wr_en),
        .eng_wr_row(eng_uram_wr_row),
        .eng_wr_col_word(eng_uram_wr_col_word),
        .eng_wr_data(eng_uram_wr_data),
        .eng_wr_accum(eng_uram_wr_accum),
        .eng_wr_accept(eng_uram_wr_accept),
        .nm_wr_en(adp_uram_wr_en),
        .nm_wr_row(adp_uram_wr_row),
        .nm_wr_col_word(adp_uram_wr_col_word),
        .nm_wr_data(adp_uram_wr_data),
        .rd_en(uram_rd_en_mux),
        .rd_row(uram_rd_row_mux),
        .rd_col_word(uram_rd_col_mux),
        .rd_data(uram_rd_data_mux),
        .rd_valid(uram_rd_valid_mux)
    );

    // =========================================================================
    // URAM Flush + Debug Writer + Flush HBM Port (write-only, muxed)
    // =========================================================================

    // Flush port signals (to HBM — muxed between uram_flush and debug_writer)
    wire [ID_W-1:0]        fl_awid;
    wire [HBM_ADDR_W-1:0] fl_awaddr;
    wire [LEN_W-1:0]      fl_awlen;
    wire                   fl_awvalid, fl_awready;
    wire [BUS_WIDTH-1:0]  fl_wdata;
    wire                   fl_wlast, fl_wvalid, fl_wready;
    wire [ID_W-1:0]        fl_bid;
    wire [1:0]            fl_bresp;
    wire                   fl_bvalid, fl_bready;

    // uram_flush AXI signals (before mux)
    wire [ID_W-1:0]        uf_awid;
    wire [HBM_ADDR_W-1:0] uf_awaddr;
    wire [LEN_W-1:0]      uf_awlen;
    wire                   uf_awvalid;
    wire                   uf_awready_from_mux;
    wire [BUS_WIDTH-1:0]  uf_wdata;
    wire                   uf_wlast, uf_wvalid;
    wire                   uf_wready_from_mux;
    wire [ID_W-1:0]        uf_bid_from_mux;
    wire [1:0]            uf_bresp_from_mux;
    wire                   uf_bvalid_from_mux;
    wire                   uf_bready;

    // debug_writer AXI signals (before mux)
    wire [ID_W-1:0]        dbg_awid;
    wire [HBM_ADDR_W-1:0] dbg_awaddr;
    wire [LEN_W-1:0]      dbg_awlen;
    wire                   dbg_awvalid;
    wire [BUS_WIDTH-1:0]  dbg_wdata;
    wire                   dbg_wlast, dbg_wvalid;
    wire [ID_W-1:0]        dbg_bid;
    wire [1:0]            dbg_bresp;
    wire                   dbg_bvalid;
    wire                   dbg_bready;
    wire                   dbg_awready_from_mux;
    wire                   dbg_wready_from_mux;

    // Mux select: debug_writer active when it's busy or has a valid write
    wire dbg_active = dbg_wr_busy | fsm_dbg_wr_valid;

    // synthesis translate_off
    // Mutual exclusion assertion
    always @(posedge clk) begin
        if (rst_n && dbg_active && (uf_awvalid || uf_wvalid))
            $display("[ASSERT FAIL %0t] flush port contention: dbg_active=%b uf_awvalid=%b uf_wvalid=%b",
                     $time, dbg_active, uf_awvalid, uf_wvalid);
    end
    // synthesis translate_on

    // AXI write channel mux
    assign fl_awid    = dbg_active ? dbg_awid    : uf_awid;
    assign fl_awaddr  = dbg_active ? dbg_awaddr  : uf_awaddr;
    assign fl_awlen   = dbg_active ? dbg_awlen   : uf_awlen;
    assign fl_awvalid = dbg_active ? dbg_awvalid : uf_awvalid;
    assign fl_wdata   = dbg_active ? dbg_wdata   : uf_wdata;
    assign fl_wlast   = dbg_active ? dbg_wlast   : uf_wlast;
    assign fl_wvalid  = dbg_active ? dbg_wvalid  : uf_wvalid;
    assign fl_bready  = dbg_active ? dbg_bready  : uf_bready;

    // Route AXI responses back to the active master
    assign uf_awready_from_mux  = dbg_active ? 1'b0 : fl_awready;
    assign uf_wready_from_mux   = dbg_active ? 1'b0 : fl_wready;
    assign uf_bid_from_mux      = fl_bid;
    assign uf_bresp_from_mux    = fl_bresp;
    assign uf_bvalid_from_mux   = dbg_active ? 1'b0 : fl_bvalid;

    assign dbg_awready_from_mux = dbg_active ? fl_awready : 1'b0;
    assign dbg_wready_from_mux  = dbg_active ? fl_wready  : 1'b0;
    assign dbg_bid              = fl_bid;
    assign dbg_bresp            = fl_bresp;
    assign dbg_bvalid           = dbg_active ? fl_bvalid  : 1'b0;

    uram_flush #(
        .ROW_W(URAM_ROW_W), .COL_W(URAM_COL_W)
    ) u_uram_flush (
        .clk(clk), .rst_n(rst_n),
        .start(fsm_uf_start),
        .num_rows(fsm_uf_num_rows[URAM_ROW_W-1:0]),
        .num_col_words(fsm_uf_num_col_words[URAM_COL_W-1:0]),
        .start_col_word(fsm_uf_start_col[URAM_COL_W-1:0]),
        .hbm_base(fsm_uf_hbm_base),
        .hbm_stride(fsm_uf_hbm_stride),
        .done(uf_done),
        .uram_rd_en(uf_uram_rd_en),
        .uram_rd_row(uf_uram_rd_row),
        .uram_rd_col_word(uf_uram_rd_col_word),
        .uram_rd_data(uf_uram_rd_data),
        .uram_rd_valid(uf_uram_rd_valid),
        .m_axi_awid(uf_awid), .m_axi_awaddr(uf_awaddr),
        .m_axi_awlen(uf_awlen), .m_axi_awvalid(uf_awvalid),
        .m_axi_awready(uf_awready_from_mux),
        .m_axi_wdata(uf_wdata), .m_axi_wlast(uf_wlast),
        .m_axi_wvalid(uf_wvalid), .m_axi_wready(uf_wready_from_mux),
        .m_axi_bid(uf_bid_from_mux), .m_axi_bresp(uf_bresp_from_mux),
        .m_axi_bvalid(uf_bvalid_from_mux), .m_axi_bready(uf_bready)
    );

    // Debug Writer — single-beat AXI4 write master
    debug_writer u_debug_writer (
        .clk(clk), .rst_n(rst_n),
        .write_valid(fsm_dbg_wr_valid),
        .write_addr(fsm_dbg_wr_addr),
        .write_data(fsm_dbg_wr_data),
        .write_done(dbg_wr_done),
        .write_busy(dbg_wr_busy),
        .m_axi_awid(dbg_awid), .m_axi_awaddr(dbg_awaddr),
        .m_axi_awlen(dbg_awlen), .m_axi_awvalid(dbg_awvalid),
        .m_axi_awready(dbg_awready_from_mux),
        .m_axi_wdata(dbg_wdata), .m_axi_wlast(dbg_wlast),
        .m_axi_wvalid(dbg_wvalid), .m_axi_wready(dbg_wready_from_mux),
        .m_axi_bid(dbg_bid), .m_axi_bresp(dbg_bresp),
        .m_axi_bvalid(dbg_bvalid), .m_axi_bready(dbg_bready)
    );

`ifdef FPGA_TARGET
    // FPGA: flush AXI signals exposed as module ports
    assign m_axi_fl_awid    = fl_awid;
    assign m_axi_fl_awaddr  = fl_awaddr;
    assign m_axi_fl_awlen   = fl_awlen;
    assign m_axi_fl_awvalid = fl_awvalid;
    assign fl_awready       = m_axi_fl_awready;
    assign m_axi_fl_wdata   = fl_wdata;
    assign m_axi_fl_wlast   = fl_wlast;
    assign m_axi_fl_wvalid  = fl_wvalid;
    assign fl_wready        = m_axi_fl_wready;
    assign fl_bid           = m_axi_fl_bid;
    assign fl_bresp         = m_axi_fl_bresp;
    assign fl_bvalid        = m_axi_fl_bvalid;
    assign m_axi_fl_bready  = fl_bready;
`else
    // Flush port connected to sim_hbm port 2 (shared memory)
    assign fl_awready = hbm_p2_awready;
    assign fl_wready  = hbm_p2_wready;
    assign fl_bid     = hbm_p2_bid;
    assign fl_bresp   = hbm_p2_bresp;
    assign fl_bvalid  = hbm_p2_bvalid;
`endif

    // =========================================================================
    // URAM NM Adapter (scalar 16-bit ↔ URAM 256-bit bridge)
    // =========================================================================
    uram_nm_adapter #(
        .ROW_W(URAM_ROW_W), .COL_W(URAM_COL_W), .SCALAR_AW(NM_ADDR_W)
    ) u_nm_adapter (
        .clk(clk), .rst_n(rst_n),
        .cfg_col_bits(fsm_nm_cfg_col_bits),
        .rd_en(adp_rd_en),
        .rd_addr(adp_rd_addr),
        .rd_data(adp_rd_data),
        .rd_valid(adp_rd_valid),
        .wr_en(adp_wr_en),
        .wr_addr(adp_wr_addr),
        .wr_data(adp_wr_data),
        .flush(fsm_nm_adapter_flush),
        .flush_done(nm_adapter_flush_done),
        .uram_rd_en(adp_uram_rd_en),
        .uram_rd_row(adp_uram_rd_row),
        .uram_rd_col_word(adp_uram_rd_col_word),
        .uram_rd_data(uram_rd_data_mux),
        .uram_rd_valid(adp_uram_rd_valid),
        .uram_wr_en(adp_uram_wr_en),
        .uram_wr_row(adp_uram_wr_row),
        .uram_wr_col_word(adp_uram_wr_col_word),
        .uram_wr_data(adp_uram_wr_data)
    );

    // =========================================================================
    // act_dma + DMA HBM Port (read+write)
    // =========================================================================
    wire [ID_W-1:0]        dma_axi_arid;
    wire [HBM_ADDR_W-1:0] dma_axi_araddr;
    wire [LEN_W-1:0]      dma_axi_arlen;
    wire                   dma_axi_arvalid, dma_axi_arready;
    wire [ID_W-1:0]        dma_axi_rid;
    wire [BUS_WIDTH-1:0]  dma_axi_rdata;
    wire [1:0]            dma_axi_rresp;
    wire                   dma_axi_rlast, dma_axi_rvalid, dma_axi_rready;

    wire [ID_W-1:0]        dma_axi_awid;
    wire [HBM_ADDR_W-1:0] dma_axi_awaddr;
    wire [LEN_W-1:0]      dma_axi_awlen;
    wire                   dma_axi_awvalid, dma_axi_awready;
    wire [BUS_WIDTH-1:0]  dma_axi_wdata;
    wire                   dma_axi_wlast, dma_axi_wvalid, dma_axi_wready;
    wire [ID_W-1:0]        dma_axi_bid;
    wire [1:0]            dma_axi_bresp;
    wire                   dma_axi_bvalid, dma_axi_bready;

    act_dma u_act_dma (
        .clk(clk), .rst_n(rst_n),
        .cfg_rd_base(fsm_dma_rd_base),
        .cfg_wr_base(fsm_dma_wr_base),
        .rd_en(dma_rd_en),
        .rd_addr(dma_rd_addr),
        .rd_data(dma_rd_data),
        .rd_valid(dma_rd_valid),
        .wr_en(dma_wr_en),
        .wr_addr(dma_wr_addr),
        .wr_data(dma_wr_data),
        .flush(fsm_dma_flush),
        .flush_done(dma_flush_done),
        .m_axi_arid(dma_axi_arid), .m_axi_araddr(dma_axi_araddr),
        .m_axi_arlen(dma_axi_arlen), .m_axi_arvalid(dma_axi_arvalid),
        .m_axi_arready(dma_axi_arready),
        .m_axi_rid(dma_axi_rid), .m_axi_rdata(dma_axi_rdata),
        .m_axi_rresp(dma_axi_rresp), .m_axi_rlast(dma_axi_rlast),
        .m_axi_rvalid(dma_axi_rvalid), .m_axi_rready(dma_axi_rready),
        .m_axi_awid(dma_axi_awid), .m_axi_awaddr(dma_axi_awaddr),
        .m_axi_awlen(dma_axi_awlen), .m_axi_awvalid(dma_axi_awvalid),
        .m_axi_awready(dma_axi_awready),
        .m_axi_wdata(dma_axi_wdata), .m_axi_wlast(dma_axi_wlast),
        .m_axi_wvalid(dma_axi_wvalid), .m_axi_wready(dma_axi_wready),
        .m_axi_bid(dma_axi_bid), .m_axi_bresp(dma_axi_bresp),
        .m_axi_bvalid(dma_axi_bvalid), .m_axi_bready(dma_axi_bready)
    );

`ifdef FPGA_TARGET
    // FPGA: DMA AXI signals exposed as module ports
    assign m_axi_dma_arid    = dma_axi_arid;
    assign m_axi_dma_araddr  = dma_axi_araddr;
    assign m_axi_dma_arlen   = dma_axi_arlen;
    assign m_axi_dma_arvalid = dma_axi_arvalid;
    assign dma_axi_arready   = m_axi_dma_arready;
    assign dma_axi_rid       = m_axi_dma_rid;
    assign dma_axi_rdata     = m_axi_dma_rdata;
    assign dma_axi_rresp     = m_axi_dma_rresp;
    assign dma_axi_rlast     = m_axi_dma_rlast;
    assign dma_axi_rvalid    = m_axi_dma_rvalid;
    assign m_axi_dma_rready  = dma_axi_rready;
    assign m_axi_dma_awid    = dma_axi_awid;
    assign m_axi_dma_awaddr  = dma_axi_awaddr;
    assign m_axi_dma_awlen   = dma_axi_awlen;
    assign m_axi_dma_awvalid = dma_axi_awvalid;
    assign dma_axi_awready   = m_axi_dma_awready;
    assign m_axi_dma_wdata   = dma_axi_wdata;
    assign m_axi_dma_wlast   = dma_axi_wlast;
    assign m_axi_dma_wvalid  = dma_axi_wvalid;
    assign dma_axi_wready    = m_axi_dma_wready;
    assign dma_axi_bid       = m_axi_dma_bid;
    assign dma_axi_bresp     = m_axi_dma_bresp;
    assign dma_axi_bvalid    = m_axi_dma_bvalid;
    assign m_axi_dma_bready  = dma_axi_bready;
`else
    // DMA port connected to sim_hbm port 3 (shared memory)
    assign dma_axi_arready = hbm_p3_arready;
    assign dma_axi_rid     = hbm_p3_rid;
    assign dma_axi_rdata   = hbm_p3_rdata;
    assign dma_axi_rresp   = hbm_p3_rresp;
    assign dma_axi_rlast   = hbm_p3_rlast;
    assign dma_axi_rvalid  = hbm_p3_rvalid;
    assign dma_axi_awready = hbm_p3_awready;
    assign dma_axi_wready  = hbm_p3_wready;
    assign dma_axi_bid     = hbm_p3_bid;
    assign dma_axi_bresp   = hbm_p3_bresp;
    assign dma_axi_bvalid  = hbm_p3_bvalid;
`endif

    // =========================================================================
    // Non-Matmul Routing: URAM Adapter + act_dma Split
    // =========================================================================
    // Data reads/writes → uram_nm_adapter (URAM path):
    //   softmax, layernorm data, activation, residual_add main
    // HBM-only reads → act_dma:
    //   layernorm params (gamma/beta), residual_add sub (skip connection)

    // --- Adapter read mux (only one unit active at a time) ---
    assign adp_rd_en = sm_rd_en | ln_rd_en | au_rd_en | res_rd_en;
    assign adp_rd_addr = sm_rd_en  ? (sm_rd_addr + fsm_nm_addr_offset) :
                         ln_rd_en  ? (ln_rd_addr + fsm_nm_addr_offset) :
                         au_rd_en  ? (au_rd_addr + fsm_nm_addr_offset) :
                                     res_rd_addr;
    // Read data from adapter → units
    assign sm_rd_data  = adp_rd_data;
    assign ln_rd_data  = adp_rd_data;
    assign au_rd_data  = adp_rd_data;
    assign au_rd_valid = adp_rd_valid;

    // --- Adapter write mux ---
    assign adp_wr_en = sm_wr_en | ln_wr_en | au_wr_en | res_wr_en;
    assign adp_wr_addr = sm_wr_en  ? (sm_wr_addr + fsm_nm_addr_offset) :
                         ln_wr_en  ? (ln_wr_addr + fsm_nm_addr_offset) :
                         au_wr_en  ? (au_wr_addr + fsm_nm_addr_offset) :
                                     res_wr_addr;
    assign adp_wr_data = sm_wr_en  ? sm_wr_data :
                         ln_wr_en  ? ln_wr_data :
                         au_wr_en  ? au_wr_data :
                                     res_wr_data;

    // --- act_dma read mux (HBM-only sources) ---
    assign dma_rd_en   = ln_param_rd_en | res_sub_rd_en;
    assign dma_rd_addr = ln_param_rd_en ? ln_param_addr : res_sub_addr;

    // LN params from act_dma (HBM weight space)
    // Interleaved FP16: gamma[i] at addr 2*i, beta[i] at addr 2*i+1
    // Both ports see the same 16-bit DMA word; layernorm reads alternately
    assign ln_gamma = dma_rd_data;
    assign ln_beta  = dma_rd_data;

    // Residual sub data from act_dma (HBM activation space)
    assign res_sub_data  = dma_rd_data;
    assign res_sub_valid = dma_rd_valid;

    // --- Residual_add main path from adapter ---
    assign res_rd_data  = adp_rd_data;
    assign res_rd_valid = adp_rd_valid;

    // --- act_dma write: disabled (no write path through act_dma) ---
    assign dma_wr_en   = 1'b0;
    assign dma_wr_addr = 16'd0;
    assign dma_wr_data = {DATA_WIDTH{1'b0}};

    // =========================================================================
    // Softmax
    // =========================================================================
    softmax #(
        .DATA_W(DATA_WIDTH), .OUT_W(DATA_WIDTH), .MAX_LEN(MAX_SEQ_LEN),
        .CAUSAL(1)
    ) u_softmax (
        .clk(clk), .rst_n(rst_n),
        .start(fsm_sm_start), .seq_len(fsm_sm_seq_len),
        .row_idx(fsm_sm_row_idx),
        .scale_factor(fsm_sm_scale_factor),
        .busy(sm_busy), .done(sm_done),
        .in_rd_en(sm_rd_en), .in_rd_addr(sm_rd_addr),
        .in_rd_data(sm_rd_data),
        .in_rd_valid(adp_rd_valid),
        .out_wr_en(sm_wr_en), .out_wr_addr(sm_wr_addr),
        .out_wr_data(sm_wr_data)
    );

    // =========================================================================
    // LayerNorm
    // =========================================================================
    layernorm #(
        .DATA_W(DATA_WIDTH), .OUT_W(DATA_WIDTH), .PARAM_W(16),
        .DIM_W(DIM_W), .MAX_DIM(MODEL_DIM)
    ) u_layernorm (
        .clk(clk), .rst_n(rst_n),
        .start(fsm_ln_start), .dim(fsm_ln_dim),
        .busy(ln_busy), .done(ln_done),
        .in_rd_en(ln_rd_en), .in_rd_addr(ln_rd_addr),
        .in_rd_data(ln_rd_data),
        .in_rd_valid(adp_rd_valid),       // Data from URAM adapter
        .param_rd_en(ln_param_rd_en), .param_rd_addr(ln_param_addr),
        .gamma_data(ln_gamma), .beta_data(ln_beta),
        .param_rd_valid(dma_rd_valid),     // Params from act_dma (HBM)
        .out_wr_en(ln_wr_en), .out_wr_addr(ln_wr_addr),
        .out_wr_data(ln_wr_data)
    );

    // =========================================================================
    // Activation Unit (GELU)
    // =========================================================================
    activation_unit #(
        .DATA_WIDTH(DATA_WIDTH), .MAX_DIM(MODEL_DIM)
    ) u_activation (
        .clk(clk), .rst_n(rst_n),
        .start(fsm_act_start), .dim(fsm_act_dim),
        .done(act_unit_done), .busy(act_unit_busy),
        .mem_rd_en(au_rd_en), .mem_rd_addr(au_rd_addr),
        .mem_rd_data(au_rd_data), .mem_rd_valid(au_rd_valid),
        .mem_wr_en(au_wr_en), .mem_wr_addr(au_wr_addr),
        .mem_wr_data(au_wr_data)
    );

    // =========================================================================
    // Residual Add
    // =========================================================================
    residual_add #(
        .DATA_WIDTH(DATA_WIDTH), .DIM_WIDTH(DIM_W), .MAX_DIM(MODEL_DIM)
    ) u_residual_add (
        .clk(clk), .rst_n(rst_n),
        .start(fsm_res_start), .dim(fsm_res_dim),
        .done(res_done), .busy(res_busy),
        .res_rd_en(res_rd_en), .res_rd_addr(res_rd_addr),
        .res_rd_data(res_rd_data), .res_rd_valid(res_rd_valid),
        .sub_rd_en(res_sub_rd_en), .sub_rd_addr(res_sub_addr),
        .sub_rd_data(res_sub_data), .sub_rd_valid(res_sub_valid),
        .out_wr_en(res_wr_en), .out_wr_addr(res_wr_addr),
        .out_wr_data(res_wr_data)
    );

    // Quant layer removed (FP16 pipeline — no INT8 quantization needed)
    assign qu_done = 1'b1;

endmodule
