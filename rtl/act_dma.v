// =============================================================================
// act_dma.v — Scalar-to-AXI DMA Bridge for Non-Matmul Units
// =============================================================================
//
// Bridges scalar 16-bit-addressed single-element reads/writes from non-matmul
// units (softmax, layernorm, activation, residual_add) to AXI4 burst
// reads/writes on a shared HBM channel.
//
// Read path: one-word (256-bit) read cache. On hit, returns element in 1 cycle.
// On miss, fetches from HBM (AXI read), caches the word, returns element.
//
// Write path: one-word write buffer with per-element dirty tracking. On word
// boundary cross, flushes buffer to HBM (AXI write). On flush signal, writes
// remaining dirty data.
//
// FSM sets cfg_rd_base and cfg_wr_base before each non-matmul operation.
// Address translation: hbm_addr = cfg_base + scalar_addr / BUS_EL
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module act_dma #(
    parameter DATA_W      = 16,
    parameter BUS_W       = 256,
    parameter HBM_ADDR_W  = 28,
    parameter SCALAR_AW   = 16,     // Scalar address width (from non-matmul units)
    parameter ID_W        = 4,
    parameter LEN_W       = 8
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // -----------------------------------------------------------------
    // Configuration (from FSM controller)
    // -----------------------------------------------------------------
    input  wire [HBM_ADDR_W-1:0]  cfg_rd_base,     // HBM base for reads
    input  wire [HBM_ADDR_W-1:0]  cfg_wr_base,     // HBM base for writes

    // -----------------------------------------------------------------
    // Scalar read interface (from non-matmul unit)
    // -----------------------------------------------------------------
    input  wire                    rd_en,
    input  wire [SCALAR_AW-1:0]   rd_addr,
    output reg  [DATA_W-1:0]      rd_data,
    output reg                     rd_valid,

    // -----------------------------------------------------------------
    // Scalar write interface (from non-matmul unit)
    // -----------------------------------------------------------------
    input  wire                    wr_en,
    input  wire [SCALAR_AW-1:0]   wr_addr,
    input  wire [DATA_W-1:0]      wr_data,

    // -----------------------------------------------------------------
    // Flush control
    // -----------------------------------------------------------------
    input  wire                    flush,           // Force write buffer flush
    output reg                     flush_done,

    // -----------------------------------------------------------------
    // AXI4 Read Address Channel
    // -----------------------------------------------------------------
    output reg  [ID_W-1:0]        m_axi_arid,
    output reg  [HBM_ADDR_W-1:0] m_axi_araddr,
    output reg  [LEN_W-1:0]      m_axi_arlen,
    output reg                    m_axi_arvalid,
    input  wire                   m_axi_arready,

    // -----------------------------------------------------------------
    // AXI4 Read Data Channel
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]       m_axi_rid,
    input  wire [BUS_W-1:0]      m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                   m_axi_rlast,
    input  wire                   m_axi_rvalid,
    output reg                    m_axi_rready,

    // -----------------------------------------------------------------
    // AXI4 Write Address Channel
    // -----------------------------------------------------------------
    output reg  [ID_W-1:0]        m_axi_awid,
    output reg  [HBM_ADDR_W-1:0] m_axi_awaddr,
    output reg  [LEN_W-1:0]      m_axi_awlen,
    output reg                    m_axi_awvalid,
    input  wire                   m_axi_awready,

    // -----------------------------------------------------------------
    // AXI4 Write Data Channel
    // -----------------------------------------------------------------
    output reg  [BUS_W-1:0]      m_axi_wdata,
    output reg                    m_axi_wlast,
    output reg                    m_axi_wvalid,
    input  wire                   m_axi_wready,

    // -----------------------------------------------------------------
    // AXI4 Write Response Channel
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]       m_axi_bid,
    input  wire [1:0]            m_axi_bresp,
    input  wire                   m_axi_bvalid,
    output reg                    m_axi_bready
);

    // =====================================================================
    // Constants
    // =====================================================================
    localparam BUS_EL    = BUS_W / DATA_W;              // 16
    localparam EL_IDX_W  = $clog2(BUS_EL);              // 4
    localparam WORD_AW   = SCALAR_AW - EL_IDX_W;        // 12

    // =====================================================================
    // Address decomposition
    // =====================================================================
    wire [WORD_AW-1:0]  rd_word_addr  = rd_addr[SCALAR_AW-1:EL_IDX_W];
    wire [EL_IDX_W-1:0] rd_el_idx     = rd_addr[EL_IDX_W-1:0];
    wire [WORD_AW-1:0]  wr_word_addr  = wr_addr[SCALAR_AW-1:EL_IDX_W];
    wire [EL_IDX_W-1:0] wr_el_idx     = wr_addr[EL_IDX_W-1:0];

    // =====================================================================
    // Read Cache (1 word)
    // =====================================================================
    reg [BUS_W-1:0]     rcache_data;
    reg [WORD_AW-1:0]   rcache_tag;
    reg                  rcache_valid;

    // Pending read
    reg                  rd_pending;
    reg [EL_IDX_W-1:0]  rd_el_pending;

    // =====================================================================
    // Write Buffer (1 word)
    // =====================================================================
    reg [BUS_W-1:0]     wbuf_data;
    reg [WORD_AW-1:0]   wbuf_tag;
    reg                  wbuf_dirty;

    // =====================================================================
    // AXI FSM
    // =====================================================================
    localparam AX_IDLE     = 3'd0;
    localparam AX_RD_AR    = 3'd1;   // Issue read address
    localparam AX_RD_DATA  = 3'd2;   // Wait for read data
    localparam AX_WR_AW    = 3'd3;   // Issue write address
    localparam AX_WR_DATA  = 3'd4;   // Issue write data
    localparam AX_WR_RESP  = 3'd5;   // Wait for write response
    reg [2:0] ax_state;

    // After write buffer flush, what to do next
    reg        wr_after_flush;         // 1: pending write after flush, 0: return to idle
    reg [WORD_AW-1:0]  wr_pending_word;
    reg [EL_IDX_W-1:0] wr_pending_el;
    reg [DATA_W-1:0]   wr_pending_data;

    // Read miss: need to fetch from HBM
    reg [WORD_AW-1:0]  rd_miss_word;

    // Flush request tracking
    reg flush_pending;

    // =====================================================================
    // Read Hit Detection (combinational)
    // =====================================================================
    wire rd_cache_hit = rd_en && rcache_valid && (rcache_tag == rd_word_addr);

    // =====================================================================
    // Main Logic
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data        <= {DATA_W{1'b0}};
            rd_valid       <= 1'b0;
            rd_pending     <= 1'b0;
            rd_el_pending  <= {EL_IDX_W{1'b0}};
            rcache_data    <= {BUS_W{1'b0}};
            rcache_tag     <= {WORD_AW{1'b0}};
            rcache_valid   <= 1'b0;
            wbuf_data      <= {BUS_W{1'b0}};
            wbuf_tag       <= {WORD_AW{1'b0}};
            wbuf_dirty     <= 1'b0;
            ax_state       <= AX_IDLE;
            wr_after_flush <= 1'b0;
            wr_pending_word <= {WORD_AW{1'b0}};
            wr_pending_el  <= {EL_IDX_W{1'b0}};
            wr_pending_data <= {DATA_W{1'b0}};
            rd_miss_word   <= {WORD_AW{1'b0}};
            flush_pending  <= 1'b0;
            flush_done     <= 1'b0;
            m_axi_arid     <= {ID_W{1'b0}};
            m_axi_araddr   <= {HBM_ADDR_W{1'b0}};
            m_axi_arlen    <= {LEN_W{1'b0}};
            m_axi_arvalid  <= 1'b0;
            m_axi_rready   <= 1'b0;
            m_axi_awid     <= {ID_W{1'b0}};
            m_axi_awaddr   <= {HBM_ADDR_W{1'b0}};
            m_axi_awlen    <= {LEN_W{1'b0}};
            m_axi_awvalid  <= 1'b0;
            m_axi_wdata    <= {BUS_W{1'b0}};
            m_axi_wlast    <= 1'b0;
            m_axi_wvalid   <= 1'b0;
            m_axi_bready   <= 1'b0;
        end else begin
            rd_valid   <= 1'b0;
            flush_done <= 1'b0;

            // =============================================================
            // Read: cache hit → return immediately
            // =============================================================
            if (rd_cache_hit) begin
                rd_data  <= rcache_data[rd_el_idx * DATA_W +: DATA_W];
                rd_valid <= 1'b1;
            end

            // =============================================================
            // Write: same word → merge into buffer
            // =============================================================
            if (wr_en && ax_state == AX_IDLE) begin
                if (wbuf_dirty && wbuf_tag != wr_word_addr) begin
                    // Word boundary cross: flush current buffer first
                    wr_after_flush  <= 1'b1;
                    wr_pending_word <= wr_word_addr;
                    wr_pending_el   <= wr_el_idx;
                    wr_pending_data <= wr_data;
                    ax_state        <= AX_WR_AW;
                end else begin
                    // Same word or clean buffer: merge
                    wbuf_data[wr_el_idx * DATA_W +: DATA_W] <= wr_data;
                    wbuf_tag   <= wr_word_addr;
                    wbuf_dirty <= 1'b1;
                end
            end

            // =============================================================
            // Read: cache miss → initiate AXI read
            // =============================================================
            if (rd_en && !rd_cache_hit && ax_state == AX_IDLE && !rd_pending) begin
                rd_pending    <= 1'b1;
                rd_el_pending <= rd_el_idx;
                rd_miss_word  <= rd_word_addr;
                ax_state      <= AX_RD_AR;
            end

            // =============================================================
            // Flush request
            // =============================================================
            if (flush && !flush_pending && ax_state == AX_IDLE) begin
                if (wbuf_dirty) begin
                    flush_pending   <= 1'b1;
                    wr_after_flush  <= 1'b0;
                    ax_state        <= AX_WR_AW;
                end else begin
                    flush_done <= 1'b1;
                end
            end

            // =============================================================
            // AXI State Machine
            // =============================================================
            case (ax_state)
                AX_IDLE: begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                end

                // ---------------------------------------------------------
                // Read: issue AR
                // ---------------------------------------------------------
                AX_RD_AR: begin
                    m_axi_arid    <= {ID_W{1'b0}};
                    m_axi_araddr  <= cfg_rd_base + {{(HBM_ADDR_W-WORD_AW){1'b0}}, rd_miss_word};
                    m_axi_arlen   <= {LEN_W{1'b0}};   // Single beat
                    m_axi_arvalid <= 1'b1;
                    m_axi_rready  <= 1'b0;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        ax_state      <= AX_RD_DATA;
                    end
                end

                // ---------------------------------------------------------
                // Read: receive data
                // ---------------------------------------------------------
                AX_RD_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready  <= 1'b0;
                        rcache_data   <= m_axi_rdata;
                        rcache_tag    <= rd_miss_word;
                        rcache_valid  <= 1'b1;
                        // Return the requested element
                        rd_data       <= m_axi_rdata[rd_el_pending * DATA_W +: DATA_W];
                        rd_valid      <= 1'b1;
                        rd_pending    <= 1'b0;
                        ax_state      <= AX_IDLE;
                    end
                end

                // ---------------------------------------------------------
                // Write: issue AW
                // ---------------------------------------------------------
                AX_WR_AW: begin
                    m_axi_awid    <= {ID_W{1'b0}};
                    m_axi_awaddr  <= cfg_wr_base + {{(HBM_ADDR_W-WORD_AW){1'b0}}, wbuf_tag};
                    m_axi_awlen   <= {LEN_W{1'b0}};   // Single beat
                    m_axi_awvalid <= 1'b1;
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        ax_state      <= AX_WR_DATA;
                    end
                end

                // ---------------------------------------------------------
                // Write: issue W data
                // ---------------------------------------------------------
                AX_WR_DATA: begin
                    m_axi_wdata  <= wbuf_data;
                    m_axi_wlast  <= 1'b1;
                    m_axi_wvalid <= 1'b1;
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        wbuf_dirty   <= 1'b0;
                        ax_state     <= AX_WR_RESP;
                    end
                end

                // ---------------------------------------------------------
                // Write: wait for response
                // ---------------------------------------------------------
                AX_WR_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        if (flush_pending) begin
                            flush_pending <= 1'b0;
                            flush_done    <= 1'b1;
                            ax_state      <= AX_IDLE;
                        end else if (wr_after_flush) begin
                            // Apply the pending write to a fresh buffer
                            wbuf_data <= {BUS_W{1'b0}};
                            wbuf_data[wr_pending_el * DATA_W +: DATA_W] <= wr_pending_data;
                            wbuf_tag      <= wr_pending_word;
                            wbuf_dirty    <= 1'b1;
                            wr_after_flush <= 1'b0;
                            ax_state      <= AX_IDLE;
                        end else begin
                            ax_state <= AX_IDLE;
                        end
                    end
                end

                default: ax_state <= AX_IDLE;
            endcase
        end
    end

endmodule
