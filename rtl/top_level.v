`include "defines.vh"

// =============================================================================
// top_level.v — HBM-Based Transformer Inference Top Level
// =============================================================================
//
// Architecture:
//   Per engine (4x): sim_hbm_port(wgt) + tile_loader(wgt) +
//                    sim_hbm_port(act) + tile_loader(act) +
//                    matmul_controller
//   Shared:          tiling_engine, uram_accum_buf,
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
    wire [HBM_ADDR_W-1:0]      host_output_base;
    wire                        host_decode_mode;
    wire [DIM_W-1:0]            host_cache_len;

    // =========================================================================
    // FSM ↔ Tiling Engine (Matmul Command)
    // =========================================================================
    wire                        fsm_mm_cmd_valid;
    wire [2:0]                  fsm_mm_cmd_op;
    wire [DIM_W-1:0]            fsm_mm_cmd_m, fsm_mm_cmd_k, fsm_mm_cmd_n;
    wire [HBM_ADDR_W-1:0]      fsm_mm_cmd_a_base, fsm_mm_cmd_b_base;
    wire [HBM_ADDR_W-1:0]      fsm_mm_cmd_a_stride, fsm_mm_cmd_b_stride;
    wire [7:0]                  fsm_mm_cmd_out_col_offset;
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
    wire [DIM_W-1:0]            fsm_nm_addr_offset;

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
    wire [15:0]                adp_rd_addr;
    wire [DATA_WIDTH-1:0]      adp_rd_data;
    wire                        adp_rd_valid;
    wire                        adp_wr_en;
    wire [15:0]                adp_wr_addr;
    wire [DATA_WIDTH-1:0]      adp_wr_data;

    // =========================================================================
    // FSM ↔ Sub-Unit Control
    // =========================================================================
    wire                        fsm_sm_start;
    wire [DIM_W-1:0]            fsm_sm_seq_len;
    wire [DIM_W-1:0]            fsm_sm_row_idx;
    wire [3:0]                  fsm_sm_scale_shift;
    wire                        sm_done;

    wire                        fsm_ln_start;
    wire [DIM_W-1:0]            fsm_ln_dim;
    wire                        ln_done;

    wire                        fsm_act_start;
    wire [DIM_W-1:0]            fsm_act_dim;
    wire                        act_unit_done;

    wire                        fsm_res_start;
    wire [DIM_W-1:0]            fsm_res_dim;
    wire                        res_done;

    wire                        fsm_qu_start;
    wire [DIM_W-1:0]            fsm_qu_dim;
    wire [HBM_ADDR_W-1:0]      fsm_qu_src_base, fsm_qu_dst_base;
    wire                        qu_done;

    wire [5:0]                  current_state;
    wire [DIM_W-1:0]            current_layer;

    // =========================================================================
    // Tiling Engine ↔ Per-Engine Command Buses
    // =========================================================================
    wire [N_ENG-1:0]                te_eng_cmd_valid;
    wire [3*N_ENG-1:0]              te_eng_cmd_op;
    wire [DIM_W*N_ENG-1:0]         te_eng_cmd_m, te_eng_cmd_k, te_eng_cmd_n;
    wire [HBM_ADDR_W*N_ENG-1:0]   te_eng_cmd_a_base, te_eng_cmd_b_base;
    wire [HBM_ADDR_W*N_ENG-1:0]   te_eng_cmd_a_stride, te_eng_cmd_b_stride;
    wire [URAM_ROW_W*N_ENG-1:0]   te_eng_cmd_out_row;
    wire [URAM_COL_W*N_ENG-1:0]   te_eng_cmd_out_col_word;
    wire [N_ENG-1:0]                eng_cmd_ready, eng_cmd_done;

    // =========================================================================
    // Per-Engine URAM Write Buses (packed for uram_accum_buf)
    // =========================================================================
    wire [N_ENG-1:0]                eng_uram_wr_en;
    wire [URAM_ROW_W*N_ENG-1:0]   eng_uram_wr_row;
    wire [URAM_COL_W*N_ENG-1:0]   eng_uram_wr_col_word;
    wire [BUS_WIDTH*N_ENG-1:0]    eng_uram_wr_data;
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
    wire [7:0]  ln_gamma, ln_beta;
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
        .output_base(host_output_base),
        .decode_mode(host_decode_mode),
        .cache_len(host_cache_len),
        .done(host_done),
        .busy(host_busy),
        .current_state(current_state[4:0]),
        .current_layer(current_layer),
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
        .output_base(host_output_base),
        .decode_mode(host_decode_mode),
        .cache_len(host_cache_len),
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
        .done(host_done),
        .busy(host_busy),
        .weight_base(host_weight_base),
        .act_base(host_act_base),
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
        .sm_scale_shift(fsm_sm_scale_shift),
        .sm_done(sm_done),
        .ln_start(fsm_ln_start),
        .ln_dim(fsm_ln_dim),
        .ln_done(ln_done),
        .act_start(fsm_act_start),
        .act_dim(fsm_act_dim),
        .act_done(act_unit_done),
        .res_start(fsm_res_start),
        .res_dim(fsm_res_dim),
        .res_done(res_done),
        .quant_start(fsm_qu_start),
        .quant_dim(fsm_qu_dim),
        .quant_src_base(fsm_qu_src_base),
        .quant_dst_base(fsm_qu_dst_base),
        .quant_done(qu_done),
        .current_state(current_state),
        .current_layer(current_layer)
    );

    // =========================================================================
    // Tiling Engine
    // =========================================================================
    tiling_engine #(
        .N_ENG(N_ENG), .TILE(TILE_SIZE), .DIM_W(DIM_W),
        .URAM_ROW_W(URAM_ROW_W), .URAM_COL_W(URAM_COL_W)
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
        .cmd_ready(mm_cmd_ready),
        .cmd_done(mm_cmd_done),
        .eng_cmd_valid(te_eng_cmd_valid),
        .eng_cmd_op(te_eng_cmd_op),
        .eng_cmd_m(te_eng_cmd_m),
        .eng_cmd_k(te_eng_cmd_k),
        .eng_cmd_n(te_eng_cmd_n),
        .eng_cmd_a_base(te_eng_cmd_a_base),
        .eng_cmd_b_base(te_eng_cmd_b_base),
        .eng_cmd_a_stride(te_eng_cmd_a_stride),
        .eng_cmd_b_stride(te_eng_cmd_b_stride),
        .eng_cmd_out_row(te_eng_cmd_out_row),
        .eng_cmd_out_col_word(te_eng_cmd_out_col_word),
        .eng_cmd_ready(eng_cmd_ready),
        .eng_cmd_done(eng_cmd_done)
    );

    // =========================================================================
    // Per-Engine: sim_hbm_port(wgt) + tile_loader(wgt) +
    //             sim_hbm_port(act) + tile_loader(act) +
    //             matmul_controller
    // =========================================================================
    genvar e;
    generate
        for (e = 0; e < N_ENG; e = e + 1) begin : gen_eng
            // ----- AXI wires: weight tile_loader ↔ weight HBM -----
            wire [ID_W-1:0]        wgt_arid;
            wire [HBM_ADDR_W-1:0] wgt_araddr;
            wire [LEN_W-1:0]      wgt_arlen;
            wire                   wgt_arvalid, wgt_arready;
            wire [ID_W-1:0]        wgt_rid;
            wire [BUS_WIDTH-1:0]  wgt_rdata;
            wire [1:0]            wgt_rresp;
            wire                   wgt_rlast, wgt_rvalid, wgt_rready;

            // ----- AXI wires: act tile_loader ↔ act HBM -----
            wire [ID_W-1:0]        act_arid;
            wire [HBM_ADDR_W-1:0] act_araddr;
            wire [LEN_W-1:0]      act_arlen;
            wire                   act_arvalid, act_arready;
            wire [ID_W-1:0]        act_rid;
            wire [BUS_WIDTH-1:0]  act_rdata;
            wire [1:0]            act_rresp;
            wire                   act_rlast, act_rvalid, act_rready;

            // ----- tile_loader ↔ matmul_controller (weight) -----
            wire        wgt_lc_valid, wgt_lc_ready, wgt_lc_done;
            wire [HBM_ADDR_W-1:0] wgt_lc_base, wgt_lc_stride;
            wire [5:0]  wgt_lc_rows;
            wire        wgt_lr_en;
            wire [5:0]  wgt_lr_addr;
            wire [BUS_WIDTH-1:0] wgt_lr_data;
            wire        wgt_lr_valid;

            // ----- tile_loader ↔ matmul_controller (activation) -----
            wire        act_lc_valid, act_lc_ready, act_lc_done;
            wire [HBM_ADDR_W-1:0] act_lc_base, act_lc_stride;
            wire [5:0]  act_lc_rows;
            wire        act_lr_en;
            wire [5:0]  act_lr_addr;
            wire [BUS_WIDTH-1:0] act_lr_data;
            wire        act_lr_valid;

            // ---- Weight HBM (read-only) ----
`ifndef FPGA_TARGET
            sim_hbm_port #(.DEPTH(SIM_HBM_DEPTH), .RD_LATENCY_CYCLES(HBM_RD_LATENCY)) u_hbm_wgt (
                .clk(clk), .rst_n(rst_n),
                .s_axi_arid(wgt_arid), .s_axi_araddr(wgt_araddr),
                .s_axi_arlen(wgt_arlen), .s_axi_arvalid(wgt_arvalid),
                .s_axi_arready(wgt_arready),
                .s_axi_rid(wgt_rid), .s_axi_rdata(wgt_rdata),
                .s_axi_rresp(wgt_rresp), .s_axi_rlast(wgt_rlast),
                .s_axi_rvalid(wgt_rvalid), .s_axi_rready(wgt_rready),
                // Write channels tied off
                .s_axi_awid({ID_W{1'b0}}), .s_axi_awaddr({HBM_ADDR_W{1'b0}}),
                .s_axi_awlen({LEN_W{1'b0}}), .s_axi_awvalid(1'b0),
                .s_axi_awready(),
                .s_axi_wdata({BUS_WIDTH{1'b0}}), .s_axi_wlast(1'b0),
                .s_axi_wvalid(1'b0), .s_axi_wready(),
                .s_axi_bid(), .s_axi_bresp(), .s_axi_bvalid(),
                .s_axi_bready(1'b0)
            );
`endif

            // ---- Weight Tile Loader ----
            tile_loader #(.TILE(TILE_SIZE)) u_tl_wgt (
                .clk(clk), .rst_n(rst_n),
                .cmd_valid(wgt_lc_valid), .cmd_ready(wgt_lc_ready),
                .cmd_hbm_base(wgt_lc_base), .cmd_tile_rows(wgt_lc_rows),
                .cmd_stride(wgt_lc_stride), .cmd_done(wgt_lc_done),
                .m_axi_arid(wgt_arid), .m_axi_araddr(wgt_araddr),
                .m_axi_arlen(wgt_arlen), .m_axi_arvalid(wgt_arvalid),
                .m_axi_arready(wgt_arready),
                .m_axi_rid(wgt_rid), .m_axi_rdata(wgt_rdata),
                .m_axi_rresp(wgt_rresp), .m_axi_rlast(wgt_rlast),
                .m_axi_rvalid(wgt_rvalid), .m_axi_rready(wgt_rready),
                .local_rd_en(wgt_lr_en), .local_rd_addr(wgt_lr_addr),
                .local_rd_data(wgt_lr_data), .local_rd_valid(wgt_lr_valid)
            );

            // ---- Activation HBM (read-only) ----
`ifndef FPGA_TARGET
            sim_hbm_port #(.DEPTH(SIM_HBM_DEPTH), .RD_LATENCY_CYCLES(HBM_RD_LATENCY)) u_hbm_act (
                .clk(clk), .rst_n(rst_n),
                .s_axi_arid(act_arid), .s_axi_araddr(act_araddr),
                .s_axi_arlen(act_arlen), .s_axi_arvalid(act_arvalid),
                .s_axi_arready(act_arready),
                .s_axi_rid(act_rid), .s_axi_rdata(act_rdata),
                .s_axi_rresp(act_rresp), .s_axi_rlast(act_rlast),
                .s_axi_rvalid(act_rvalid), .s_axi_rready(act_rready),
                // Write channels tied off
                .s_axi_awid({ID_W{1'b0}}), .s_axi_awaddr({HBM_ADDR_W{1'b0}}),
                .s_axi_awlen({LEN_W{1'b0}}), .s_axi_awvalid(1'b0),
                .s_axi_awready(),
                .s_axi_wdata({BUS_WIDTH{1'b0}}), .s_axi_wlast(1'b0),
                .s_axi_wvalid(1'b0), .s_axi_wready(),
                .s_axi_bid(), .s_axi_bresp(), .s_axi_bvalid(),
                .s_axi_bready(1'b0)
            );
`endif

            // ---- Activation Tile Loader ----
            tile_loader #(.TILE(TILE_SIZE)) u_tl_act (
                .clk(clk), .rst_n(rst_n),
                .cmd_valid(act_lc_valid), .cmd_ready(act_lc_ready),
                .cmd_hbm_base(act_lc_base), .cmd_tile_rows(act_lc_rows),
                .cmd_stride(act_lc_stride), .cmd_done(act_lc_done),
                .m_axi_arid(act_arid), .m_axi_araddr(act_araddr),
                .m_axi_arlen(act_arlen), .m_axi_arvalid(act_arvalid),
                .m_axi_arready(act_arready),
                .m_axi_rid(act_rid), .m_axi_rdata(act_rdata),
                .m_axi_rresp(act_rresp), .m_axi_rlast(act_rlast),
                .m_axi_rvalid(act_rvalid), .m_axi_rready(act_rready),
                .local_rd_en(act_lr_en), .local_rd_addr(act_lr_addr),
                .local_rd_data(act_lr_data), .local_rd_valid(act_lr_valid)
            );

            // ---- Matmul Controller ----
            matmul_controller #(
                .URAM_ROW_W(URAM_ROW_W), .URAM_COL_W(URAM_COL_W)
            ) u_mc (
                .clk(clk), .rst_n(rst_n),
                .cmd_valid(te_eng_cmd_valid[e]),
                .cmd_op(te_eng_cmd_op[e*3 +: 3]),
                .cmd_m(te_eng_cmd_m[e*DIM_W +: DIM_W]),
                .cmd_k(te_eng_cmd_k[e*DIM_W +: DIM_W]),
                .cmd_n(te_eng_cmd_n[e*DIM_W +: DIM_W]),
                .cmd_a_base(te_eng_cmd_a_base[e*HBM_ADDR_W +: HBM_ADDR_W]),
                .cmd_b_base(te_eng_cmd_b_base[e*HBM_ADDR_W +: HBM_ADDR_W]),
                .cmd_a_stride(te_eng_cmd_a_stride[e*HBM_ADDR_W +: HBM_ADDR_W]),
                .cmd_b_stride(te_eng_cmd_b_stride[e*HBM_ADDR_W +: HBM_ADDR_W]),
                .cmd_out_row(te_eng_cmd_out_row[e*URAM_ROW_W +: URAM_ROW_W]),
                .cmd_out_col_word(te_eng_cmd_out_col_word[e*URAM_COL_W +: URAM_COL_W]),
                .cmd_ready(eng_cmd_ready[e]),
                .cmd_done(eng_cmd_done[e]),
                // Weight tile_loader
                .wgt_load_cmd_valid(wgt_lc_valid),
                .wgt_load_cmd_ready(wgt_lc_ready),
                .wgt_load_hbm_base(wgt_lc_base),
                .wgt_load_tile_rows(wgt_lc_rows),
                .wgt_load_stride(wgt_lc_stride),
                .wgt_load_cmd_done(wgt_lc_done),
                .wgt_local_rd_en(wgt_lr_en),
                .wgt_local_rd_addr(wgt_lr_addr),
                .wgt_local_rd_data(wgt_lr_data),
                .wgt_local_rd_valid(wgt_lr_valid),
                // Activation tile_loader
                .act_load_cmd_valid(act_lc_valid),
                .act_load_cmd_ready(act_lc_ready),
                .act_load_hbm_base(act_lc_base),
                .act_load_tile_rows(act_lc_rows),
                .act_load_stride(act_lc_stride),
                .act_load_cmd_done(act_lc_done),
                .act_local_rd_en(act_lr_en),
                .act_local_rd_addr(act_lr_addr),
                .act_local_rd_data(act_lr_data),
                .act_local_rd_valid(act_lr_valid),
                // URAM write
                .uram_wr_en(eng_uram_wr_en[e]),
                .uram_wr_row(eng_uram_wr_row[e*URAM_ROW_W +: URAM_ROW_W]),
                .uram_wr_col_word(eng_uram_wr_col_word[e*URAM_COL_W +: URAM_COL_W]),
                .uram_wr_data(eng_uram_wr_data[e*BUS_WIDTH +: BUS_WIDTH]),
                .uram_wr_accept(eng_uram_wr_accept[e])
            );
        end
    endgenerate

    // =========================================================================
    // FPGA Target: Wire generate-internal AXI signals to flat module ports
    // =========================================================================
`ifdef FPGA_TARGET
    // Weight tile loader AXI ports (read-only, 2 engines)
    assign m_axi_wgt0_arid    = gen_eng[0].wgt_arid;
    assign m_axi_wgt0_araddr  = gen_eng[0].wgt_araddr;
    assign m_axi_wgt0_arlen   = gen_eng[0].wgt_arlen;
    assign m_axi_wgt0_arvalid = gen_eng[0].wgt_arvalid;
    assign m_axi_wgt0_rready  = gen_eng[0].wgt_rready;

    assign m_axi_wgt1_arid    = gen_eng[1].wgt_arid;
    assign m_axi_wgt1_araddr  = gen_eng[1].wgt_araddr;
    assign m_axi_wgt1_arlen   = gen_eng[1].wgt_arlen;
    assign m_axi_wgt1_arvalid = gen_eng[1].wgt_arvalid;
    assign m_axi_wgt1_rready  = gen_eng[1].wgt_rready;

    // Activation tile loader AXI ports (read-only, 2 engines)
    assign m_axi_act0_arid    = gen_eng[0].act_arid;
    assign m_axi_act0_araddr  = gen_eng[0].act_araddr;
    assign m_axi_act0_arlen   = gen_eng[0].act_arlen;
    assign m_axi_act0_arvalid = gen_eng[0].act_arvalid;
    assign m_axi_act0_rready  = gen_eng[0].act_rready;

    assign m_axi_act1_arid    = gen_eng[1].act_arid;
    assign m_axi_act1_araddr  = gen_eng[1].act_araddr;
    assign m_axi_act1_arlen   = gen_eng[1].act_arlen;
    assign m_axi_act1_arvalid = gen_eng[1].act_arvalid;
    assign m_axi_act1_rready  = gen_eng[1].act_rready;

    // Weight tile loader read responses (from external HBM → internal wires)
    assign gen_eng[0].wgt_arready = m_axi_wgt0_arready;
    assign gen_eng[0].wgt_rid     = m_axi_wgt0_rid;
    assign gen_eng[0].wgt_rdata   = m_axi_wgt0_rdata;
    assign gen_eng[0].wgt_rresp   = m_axi_wgt0_rresp;
    assign gen_eng[0].wgt_rlast   = m_axi_wgt0_rlast;
    assign gen_eng[0].wgt_rvalid  = m_axi_wgt0_rvalid;

    assign gen_eng[1].wgt_arready = m_axi_wgt1_arready;
    assign gen_eng[1].wgt_rid     = m_axi_wgt1_rid;
    assign gen_eng[1].wgt_rdata   = m_axi_wgt1_rdata;
    assign gen_eng[1].wgt_rresp   = m_axi_wgt1_rresp;
    assign gen_eng[1].wgt_rlast   = m_axi_wgt1_rlast;
    assign gen_eng[1].wgt_rvalid  = m_axi_wgt1_rvalid;

    // Activation tile loader read responses
    assign gen_eng[0].act_arready = m_axi_act0_arready;
    assign gen_eng[0].act_rid     = m_axi_act0_rid;
    assign gen_eng[0].act_rdata   = m_axi_act0_rdata;
    assign gen_eng[0].act_rresp   = m_axi_act0_rresp;
    assign gen_eng[0].act_rlast   = m_axi_act0_rlast;
    assign gen_eng[0].act_rvalid  = m_axi_act0_rvalid;

    assign gen_eng[1].act_arready = m_axi_act1_arready;
    assign gen_eng[1].act_rid     = m_axi_act1_rid;
    assign gen_eng[1].act_rdata   = m_axi_act1_rdata;
    assign gen_eng[1].act_rresp   = m_axi_act1_rresp;
    assign gen_eng[1].act_rlast   = m_axi_act1_rlast;
    assign gen_eng[1].act_rvalid  = m_axi_act1_rvalid;

`endif

    // =========================================================================
    // URAM Read Port Mux (flush vs adapter — FSM mutual exclusion)
    // =========================================================================
    wire                   uram_rd_en_mux;
    wire [URAM_ROW_W-1:0] uram_rd_row_mux;
    wire [URAM_COL_W-1:0] uram_rd_col_mux;
    wire [BUS_WIDTH-1:0]  uram_rd_data_mux;
    wire                   uram_rd_valid_mux;

    assign uram_rd_en_mux  = uf_uram_rd_en | adp_uram_rd_en;
    assign uram_rd_row_mux = uf_uram_rd_en ? uf_uram_rd_row : adp_uram_rd_row;
    assign uram_rd_col_mux = uf_uram_rd_en ? uf_uram_rd_col_word : adp_uram_rd_col_word;

    // Broadcast read data/valid to both consumers
    assign uf_uram_rd_data  = uram_rd_data_mux;
    assign uf_uram_rd_valid = uram_rd_valid_mux;

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
    // URAM Flush + Flush HBM Port (write-only)
    // =========================================================================
    wire [ID_W-1:0]        fl_awid;
    wire [HBM_ADDR_W-1:0] fl_awaddr;
    wire [LEN_W-1:0]      fl_awlen;
    wire                   fl_awvalid, fl_awready;
    wire [BUS_WIDTH-1:0]  fl_wdata;
    wire                   fl_wlast, fl_wvalid, fl_wready;
    wire [ID_W-1:0]        fl_bid;
    wire [1:0]            fl_bresp;
    wire                   fl_bvalid, fl_bready;

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
        .m_axi_awid(fl_awid), .m_axi_awaddr(fl_awaddr),
        .m_axi_awlen(fl_awlen), .m_axi_awvalid(fl_awvalid),
        .m_axi_awready(fl_awready),
        .m_axi_wdata(fl_wdata), .m_axi_wlast(fl_wlast),
        .m_axi_wvalid(fl_wvalid), .m_axi_wready(fl_wready),
        .m_axi_bid(fl_bid), .m_axi_bresp(fl_bresp),
        .m_axi_bvalid(fl_bvalid), .m_axi_bready(fl_bready)
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
    sim_hbm_port #(.DEPTH(SIM_HBM_DEPTH), .RD_LATENCY_CYCLES(HBM_RD_LATENCY)) u_hbm_flush (
        .clk(clk), .rst_n(rst_n),
        // Read channels tied off
        .s_axi_arid({ID_W{1'b0}}), .s_axi_araddr({HBM_ADDR_W{1'b0}}),
        .s_axi_arlen({LEN_W{1'b0}}), .s_axi_arvalid(1'b0),
        .s_axi_arready(),
        .s_axi_rid(), .s_axi_rdata(), .s_axi_rresp(),
        .s_axi_rlast(), .s_axi_rvalid(), .s_axi_rready(1'b0),
        // Write channels from uram_flush
        .s_axi_awid(fl_awid), .s_axi_awaddr(fl_awaddr),
        .s_axi_awlen(fl_awlen), .s_axi_awvalid(fl_awvalid),
        .s_axi_awready(fl_awready),
        .s_axi_wdata(fl_wdata), .s_axi_wlast(fl_wlast),
        .s_axi_wvalid(fl_wvalid), .s_axi_wready(fl_wready),
        .s_axi_bid(fl_bid), .s_axi_bresp(fl_bresp),
        .s_axi_bvalid(fl_bvalid), .s_axi_bready(fl_bready)
    );
`endif

    // =========================================================================
    // URAM NM Adapter (scalar 16-bit ↔ URAM 256-bit bridge)
    // =========================================================================
    uram_nm_adapter #(
        .ROW_W(URAM_ROW_W), .COL_W(URAM_COL_W)
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
        .uram_rd_valid(uram_rd_valid_mux),
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
    sim_hbm_port #(.DEPTH(SIM_HBM_DEPTH), .RD_LATENCY_CYCLES(HBM_RD_LATENCY)) u_hbm_dma (
        .clk(clk), .rst_n(rst_n),
        .s_axi_arid(dma_axi_arid), .s_axi_araddr(dma_axi_araddr),
        .s_axi_arlen(dma_axi_arlen), .s_axi_arvalid(dma_axi_arvalid),
        .s_axi_arready(dma_axi_arready),
        .s_axi_rid(dma_axi_rid), .s_axi_rdata(dma_axi_rdata),
        .s_axi_rresp(dma_axi_rresp), .s_axi_rlast(dma_axi_rlast),
        .s_axi_rvalid(dma_axi_rvalid), .s_axi_rready(dma_axi_rready),
        .s_axi_awid(dma_axi_awid), .s_axi_awaddr(dma_axi_awaddr),
        .s_axi_awlen(dma_axi_awlen), .s_axi_awvalid(dma_axi_awvalid),
        .s_axi_awready(dma_axi_awready),
        .s_axi_wdata(dma_axi_wdata), .s_axi_wlast(dma_axi_wlast),
        .s_axi_wvalid(dma_axi_wvalid), .s_axi_wready(dma_axi_wready),
        .s_axi_bid(dma_axi_bid), .s_axi_bresp(dma_axi_bresp),
        .s_axi_bvalid(dma_axi_bvalid), .s_axi_bready(dma_axi_bready)
    );
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
                         au_rd_en  ? au_rd_addr :
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
                         au_wr_en  ? au_wr_addr :
                                     res_wr_addr;
    assign adp_wr_data = sm_wr_en  ? sm_wr_data :
                         ln_wr_en  ? ln_wr_data :
                         au_wr_en  ? au_wr_data :
                                     res_wr_data;

    // --- act_dma read mux (HBM-only sources) ---
    assign dma_rd_en   = ln_param_rd_en | res_sub_rd_en;
    assign dma_rd_addr = ln_param_rd_en ? ln_param_addr : res_sub_addr;

    // LN params from act_dma (HBM weight space)
    assign ln_gamma = dma_rd_data[7:0];
    assign ln_beta  = dma_rd_data[15:8];

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
        .scale_shift(fsm_sm_scale_shift),
        .busy(), .done(sm_done),
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
        .DATA_W(DATA_WIDTH), .OUT_W(DATA_WIDTH), .PARAM_W(8),
        .DIM_W(DIM_W), .MAX_DIM(MODEL_DIM)
    ) u_layernorm (
        .clk(clk), .rst_n(rst_n),
        .start(fsm_ln_start), .dim(fsm_ln_dim),
        .busy(), .done(ln_done),
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
    // Activation Unit (ReLU)
    // =========================================================================
    activation_unit #(
        .DATA_WIDTH(DATA_WIDTH), .MAX_DIM(MODEL_DIM)
    ) u_activation (
        .clk(clk), .rst_n(rst_n),
        .start(fsm_act_start), .dim(fsm_act_dim),
        .done(act_unit_done), .busy(),
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
        .done(res_done), .busy(),
        .res_rd_en(res_rd_en), .res_rd_addr(res_rd_addr),
        .res_rd_data(res_rd_data), .res_rd_valid(res_rd_valid),
        .sub_rd_en(res_sub_rd_en), .sub_rd_addr(res_sub_addr),
        .sub_rd_data(res_sub_data), .sub_rd_valid(res_sub_valid),
        .out_wr_en(res_wr_en), .out_wr_addr(res_wr_addr),
        .out_wr_data(res_wr_data)
    );

    // =========================================================================
    // Quant Layer (INT16 → INT8)
    // =========================================================================
    // TODO: quant_layer needs proper HBM adapter for 256-bit bus interface.
    // For now, memory ports are tied off. Functional integration in Phase 6.
    quant_layer #(
        .IN_W(DATA_WIDTH), .OUT_W(8), .BURST(BUS_ELEMS),
        .FRAC(15), .ADDR_W(ADDR_WIDTH), .DIM_W(DIM_W)
    ) u_quant_layer (
        .clk(clk), .rst_n(rst_n),
        .start(fsm_qu_start), .dim(fsm_qu_dim),
        .src_base(fsm_qu_src_base[ADDR_WIDTH-1:0]),
        .dst_base(fsm_qu_dst_base[ADDR_WIDTH-1:0]),
        .done(qu_done), .busy(),
        .mem_rd_en(qu_rd_en), .mem_rd_addr(qu_rd_addr),
        .mem_rd_data(qu_rd_data), .mem_rd_valid(qu_rd_valid),
        .mem_wr_en(qu_wr_en), .mem_wr_addr(qu_wr_addr),
        .mem_wr_data(qu_wr_data)
    );

    // Quant layer memory: tied off for now (no HBM adapter yet)
    assign qu_rd_data  = {BUS_WIDTH{1'b0}};
    assign qu_rd_valid = 1'b0;

endmodule
