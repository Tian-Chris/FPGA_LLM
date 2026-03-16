// =============================================================================
// uram_flush.v — URAM-to-HBM Flush Controller
// =============================================================================
//
// After tiling_engine completes a matmul, the FSM triggers a URAM flush to
// write the result back to HBM. Reads rows from uram_accum_buf via its read
// port, writes to HBM via AXI4 write bursts (one burst per row).
//
// Blocking: reads one row at a time, writes to HBM, waits for response.
// Simple and correct — optimize with deeper pipelining later if needed.
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module uram_flush #(
    parameter BUS_W       = 256,
    parameter HBM_ADDR_W  = 28,
    parameter ID_W        = 4,
    parameter LEN_W       = 8,
    parameter ROW_W       = 10,    // $clog2(URAM_ROWS)
    parameter COL_W       = 8      // $clog2(URAM_COL_WORDS) — was 6, now 8 for URAM_COLS=4096
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // -----------------------------------------------------------------
    // Control interface (from FSM)
    // -----------------------------------------------------------------
    input  wire                     start,
    input  wire [ROW_W-1:0]        num_rows,        // Max row index (count - 1)
    input  wire [COL_W-1:0]        num_col_words,   // Max col word index per row (count - 1)
    input  wire [COL_W-1:0]        start_col_word,  // Starting URAM column word (for multi-head flush)
    input  wire [HBM_ADDR_W-1:0]  hbm_base,        // HBM destination base address
    input  wire [HBM_ADDR_W-1:0]  hbm_stride,      // HBM word stride between rows
    (* mark_debug = "true" *) output reg                     done,

    // -----------------------------------------------------------------
    // URAM read port (to uram_accum_buf)
    // -----------------------------------------------------------------
    output reg                     uram_rd_en,
    output reg  [ROW_W-1:0]       uram_rd_row,
    output reg  [COL_W-1:0]       uram_rd_col_word,
    input  wire [BUS_W-1:0]       uram_rd_data,
    input  wire                    uram_rd_valid,

    // -----------------------------------------------------------------
    // AXI4 Write Address Channel (master → HBM)
    // -----------------------------------------------------------------
    output reg  [ID_W-1:0]        m_axi_awid,
    output reg  [HBM_ADDR_W-1:0] m_axi_awaddr,
    output reg  [LEN_W-1:0]      m_axi_awlen,
    (* mark_debug = "true" *) output reg                    m_axi_awvalid,
    (* mark_debug = "true" *) input  wire                   m_axi_awready,

    // -----------------------------------------------------------------
    // AXI4 Write Data Channel
    // -----------------------------------------------------------------
    output reg  [BUS_W-1:0]      m_axi_wdata,
    output reg                    m_axi_wlast,
    (* mark_debug = "true" *) output reg                    m_axi_wvalid,
    (* mark_debug = "true" *) input  wire                   m_axi_wready,

    // -----------------------------------------------------------------
    // AXI4 Write Response Channel
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]       m_axi_bid,
    input  wire [1:0]            m_axi_bresp,
    (* mark_debug = "true" *) input  wire                   m_axi_bvalid,
    output reg                    m_axi_bready
);

    // =====================================================================
    // FSM States
    // =====================================================================
    localparam FL_IDLE    = 3'd0;
    localparam FL_AW      = 3'd1;   // Issue write address for current row
    localparam FL_RD_URAM = 3'd2;   // Read words from URAM + write to HBM
    localparam FL_WR_RESP = 3'd3;   // Wait for write response
    localparam FL_DONE    = 3'd4;

    (* mark_debug = "true" *) reg [2:0]              fl_state;
    (* mark_debug = "true" *) reg [ROW_W-1:0]        cur_row;         // Current flush row index
    reg [ROW_W-1:0]        num_rows_r;
    reg [COL_W-1:0]        num_col_words_r;
    reg [COL_W-1:0]        start_col_r;
    reg [HBM_ADDR_W-1:0]  hbm_addr_r;      // Current HBM write address
    reg [HBM_ADDR_W-1:0]  hbm_stride_r;

    // Read/write counters
    (* mark_debug = "true" *) reg [COL_W-1:0]        rd_col_cnt;      // URAM read column counter
    (* mark_debug = "true" *) reg [COL_W-1:0]        wr_beat_cnt;     // AXI write beat counter
    reg                    rd_done;         // All URAM reads issued for current row
    reg                    rd_inflight;     // 1 if URAM read issued, response pending

    // Small FIFO between URAM read and AXI write (2-entry, registered)
    reg [BUS_W-1:0]        fifo_data [0:1];
    reg [1:0]              fifo_wr_ptr;
    reg [1:0]              fifo_rd_ptr;
    reg [1:0]              fifo_count;
    wire                   fifo_empty = (fifo_count == 0);
    wire                   fifo_full  = (fifo_count == 2'd2);

    // =====================================================================
    // Main FSM
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fl_state        <= FL_IDLE;
            done            <= 1'b0;
            cur_row         <= {ROW_W{1'b0}};
            num_rows_r      <= {ROW_W{1'b0}};
            num_col_words_r <= {COL_W{1'b0}};
            hbm_addr_r      <= {HBM_ADDR_W{1'b0}};
            hbm_stride_r    <= {HBM_ADDR_W{1'b0}};
            uram_rd_en      <= 1'b0;
            uram_rd_row     <= {ROW_W{1'b0}};
            uram_rd_col_word <= {COL_W{1'b0}};
            rd_col_cnt      <= {COL_W{1'b0}};
            wr_beat_cnt     <= {COL_W{1'b0}};
            rd_done         <= 1'b0;
            rd_inflight     <= 1'b0;
            m_axi_awid      <= {ID_W{1'b0}};
            m_axi_awaddr    <= {HBM_ADDR_W{1'b0}};
            m_axi_awlen     <= {LEN_W{1'b0}};
            m_axi_awvalid   <= 1'b0;
            m_axi_wdata     <= {BUS_W{1'b0}};
            m_axi_wlast     <= 1'b0;
            m_axi_wvalid    <= 1'b0;
            m_axi_bready    <= 1'b0;
            fifo_wr_ptr     <= 2'd0;
            fifo_rd_ptr     <= 2'd0;
            fifo_count      <= 2'd0;
        end else begin
            done       <= 1'b0;
            uram_rd_en <= 1'b0;

            case (fl_state)
                // ---------------------------------------------------------
                FL_IDLE: begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    if (start) begin
                        fl_state        <= FL_AW;
                        num_rows_r      <= num_rows;
                        num_col_words_r <= num_col_words;
                        start_col_r     <= start_col_word;
                        hbm_addr_r      <= hbm_base;
                        hbm_stride_r    <= hbm_stride;
                        cur_row         <= {ROW_W{1'b0}};
                    end
                end

                // ---------------------------------------------------------
                // Issue AXI write address for current row
                // ---------------------------------------------------------
                FL_AW: begin
                    m_axi_awid    <= {ID_W{1'b0}};
                    m_axi_awaddr  <= hbm_addr_r;
                    m_axi_awlen   <= num_col_words_r;
                    m_axi_awvalid <= 1'b1;
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        fl_state      <= FL_RD_URAM;
                        rd_col_cnt    <= start_col_r;
                        wr_beat_cnt   <= {COL_W{1'b0}};
                        rd_done       <= 1'b0;
                        rd_inflight   <= 1'b0;
                        fifo_wr_ptr   <= 2'd0;
                        fifo_rd_ptr   <= 2'd0;
                        fifo_count    <= 2'd0;
                    end
                end

                // ---------------------------------------------------------
                // Read words from URAM + write data to HBM (pipelined)
                // ---------------------------------------------------------
                FL_RD_URAM: begin
                    // Issue URAM reads (one at a time, guard against FIFO overflow)
                    // rd_inflight prevents issuing while a read response is pending,
                    // ensuring the 2-entry FIFO never overflows from pipeline latency.
                    if (!rd_done && !fifo_full && !rd_inflight) begin
                        uram_rd_en       <= 1'b1;
                        uram_rd_row      <= cur_row;
                        uram_rd_col_word <= rd_col_cnt;
                        rd_col_cnt       <= rd_col_cnt + 1;
                        rd_inflight      <= 1'b1;
                        if (rd_col_cnt == start_col_r + num_col_words_r)
                            rd_done <= 1'b1;
                    end

                    // Capture URAM read data into FIFO
                    if (uram_rd_valid) begin
                        fifo_data[fifo_wr_ptr[0]] <= uram_rd_data;
                        fifo_wr_ptr <= fifo_wr_ptr + 1;
                        rd_inflight <= 1'b0;
                        fifo_count  <= fifo_count + (m_axi_wvalid && m_axi_wready ? 2'd0 : 2'd1);
                    end else if (m_axi_wvalid && m_axi_wready) begin
                        fifo_count <= fifo_count - 1;
                    end

                    // Drive AXI W channel from FIFO
                    if (!fifo_empty && !(m_axi_wvalid && !m_axi_wready)) begin
                        m_axi_wdata  <= fifo_data[fifo_rd_ptr[0]];
                        m_axi_wlast  <= (wr_beat_cnt == num_col_words_r);
                        m_axi_wvalid <= 1'b1;
                    end

                    // W channel handshake
                    if (m_axi_wvalid && m_axi_wready) begin
                        fifo_rd_ptr <= fifo_rd_ptr + 1;
                        wr_beat_cnt <= wr_beat_cnt + 1;
                        if (wr_beat_cnt == num_col_words_r) begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_bready <= 1'b1;
                            fl_state     <= FL_WR_RESP;
                        end else begin
                            m_axi_wvalid <= 1'b0;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Wait for write response
                // ---------------------------------------------------------
                FL_WR_RESP: begin
                    m_axi_bready <= 1'b1;
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        if (cur_row == num_rows_r) begin
                            fl_state <= FL_DONE;
                        end else begin
                            cur_row    <= cur_row + 1;
                            hbm_addr_r <= hbm_addr_r + hbm_stride_r;
                            fl_state   <= FL_AW;
                        end
                    end
                end

                // ---------------------------------------------------------
                FL_DONE: begin
                    done     <= 1'b1;
                    fl_state <= FL_IDLE;
                end

                default: fl_state <= FL_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Init FIFO for simulation
    // =====================================================================
    integer init_i;
    initial begin
        for (init_i = 0; init_i < 2; init_i = init_i + 1)
            fifo_data[init_i] = {BUS_W{1'b0}};
    end

endmodule
