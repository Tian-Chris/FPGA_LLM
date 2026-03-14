// =============================================================================
// hbm_prefetch.v — Central HBM-to-URAM DMA Prefetch Engine
// =============================================================================
//
// Reads a rectangular matrix chunk from HBM into a uram_prefetch_buf.
// AXI4 read master with full-row sequential bursts.
//
// Command interface: {hbm_base, num_rows, num_col_words, hbm_stride}
// FSM: IDLE -> AR (issue burst per row) -> DATA (receive, write URAM) -> next row -> DONE
//
// Each row issues one AXI burst of num_col_words beats.
// Rows may be non-contiguous in HBM (stride controls spacing).
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module hbm_prefetch #(
    parameter HBM_ADDR_W = 28,
    parameter BUS_W      = 256,
    parameter ROW_W      = 10,
    parameter COL_W      = 6,
    parameter DIM_W      = 16,
    parameter ID_W       = 4,
    parameter LEN_W      = 8
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // -----------------------------------------------------------------
    // Command interface (from tiling_engine)
    // -----------------------------------------------------------------
    input  wire                     cmd_valid,
    output reg                      cmd_ready,
    output reg                      cmd_done,
    input  wire [HBM_ADDR_W-1:0]   cmd_hbm_base,      // HBM word address of row 0, col 0
    input  wire [HBM_ADDR_W-1:0]   cmd_hbm_stride,    // HBM word stride between rows
    input  wire [DIM_W-1:0]        cmd_num_rows,       // Number of rows to load
    input  wire [DIM_W-1:0]        cmd_num_col_words,  // 256-bit words per row

    // -----------------------------------------------------------------
    // AXI4 Read Address Channel (master -> HBM)
    // -----------------------------------------------------------------
    output reg  [ID_W-1:0]         m_axi_arid,
    output reg  [HBM_ADDR_W-1:0]  m_axi_araddr,
    output reg  [LEN_W-1:0]       m_axi_arlen,
    output reg                     m_axi_arvalid,
    input  wire                    m_axi_arready,

    // -----------------------------------------------------------------
    // AXI4 Read Data Channel (HBM -> master)
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]         m_axi_rid,
    input  wire [BUS_W-1:0]       m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rlast,
    input  wire                    m_axi_rvalid,
    output reg                     m_axi_rready,

    // -----------------------------------------------------------------
    // URAM write port (to uram_prefetch_buf)
    // -----------------------------------------------------------------
    output reg                     uram_wr_en,
    output reg  [ROW_W-1:0]       uram_wr_row,
    output reg  [COL_W-1:0]       uram_wr_col_word,
    output reg  [BUS_W-1:0]       uram_wr_data
);

    // =====================================================================
    // FSM
    // =====================================================================
    localparam PF_IDLE = 2'd0;
    localparam PF_AR   = 2'd1;
    localparam PF_DATA = 2'd2;
    localparam PF_DONE = 2'd3;

    reg [1:0]              pf_state;
    reg [DIM_W-1:0]        cur_row;           // Current row index (0..num_rows-1)
    reg [DIM_W-1:0]        num_rows_r;        // Registered num_rows
    reg [DIM_W-1:0]        num_col_words_r;   // Registered num_col_words
    reg [HBM_ADDR_W-1:0]  hbm_addr_r;        // Current HBM row address
    reg [HBM_ADDR_W-1:0]  stride_r;          // Registered stride
    reg [DIM_W-1:0]        beat_cnt;          // Beat counter within current row

    // =====================================================================
    // FSM Logic
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pf_state        <= PF_IDLE;
            cmd_ready       <= 1'b1;
            cmd_done        <= 1'b0;
            cur_row         <= {DIM_W{1'b0}};
            num_rows_r      <= {DIM_W{1'b0}};
            num_col_words_r <= {DIM_W{1'b0}};
            hbm_addr_r      <= {HBM_ADDR_W{1'b0}};
            stride_r        <= {HBM_ADDR_W{1'b0}};
            beat_cnt        <= {DIM_W{1'b0}};
            m_axi_arid      <= {ID_W{1'b0}};
            m_axi_araddr    <= {HBM_ADDR_W{1'b0}};
            m_axi_arlen     <= {LEN_W{1'b0}};
            m_axi_arvalid   <= 1'b0;
            m_axi_rready    <= 1'b0;
            uram_wr_en      <= 1'b0;
            uram_wr_row     <= {ROW_W{1'b0}};
            uram_wr_col_word <= {COL_W{1'b0}};
            uram_wr_data    <= {BUS_W{1'b0}};
        end else begin
            cmd_done    <= 1'b0;
            uram_wr_en  <= 1'b0;

            case (pf_state)
                // ---------------------------------------------------------
                // IDLE: wait for command
                // ---------------------------------------------------------
                PF_IDLE: begin
                    cmd_ready     <= 1'b1;
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    if (cmd_valid && cmd_ready) begin
                        cmd_ready       <= 1'b0;
                        num_rows_r      <= cmd_num_rows;
                        num_col_words_r <= cmd_num_col_words;
                        hbm_addr_r      <= cmd_hbm_base;
                        stride_r        <= cmd_hbm_stride;
                        cur_row         <= {DIM_W{1'b0}};
                        beat_cnt        <= {DIM_W{1'b0}};
                        pf_state        <= PF_AR;
                    end
                end

                // ---------------------------------------------------------
                // AR: issue read address for current row
                // ---------------------------------------------------------
                PF_AR: begin
                    m_axi_arid    <= {ID_W{1'b0}};
                    m_axi_araddr  <= hbm_addr_r;
                    m_axi_arlen   <= num_col_words_r[LEN_W-1:0] - 1;
                    m_axi_arvalid <= 1'b1;
                    m_axi_rready  <= 1'b0;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        beat_cnt      <= {DIM_W{1'b0}};
                        pf_state      <= PF_DATA;
                    end
                end

                // ---------------------------------------------------------
                // DATA: receive beats, write to URAM
                // ---------------------------------------------------------
                PF_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        uram_wr_en       <= 1'b1;
                        uram_wr_row      <= cur_row[ROW_W-1:0];
                        uram_wr_col_word <= beat_cnt[COL_W-1:0];
                        uram_wr_data     <= m_axi_rdata;
                        beat_cnt         <= beat_cnt + 1;

                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;
                            if (cur_row == num_rows_r - 1) begin
                                // All rows loaded
                                pf_state <= PF_DONE;
                            end else begin
                                // Next row
                                cur_row    <= cur_row + 1;
                                hbm_addr_r <= hbm_addr_r + stride_r;
                                pf_state   <= PF_AR;
                            end
                        end
                    end
                end

                // ---------------------------------------------------------
                // DONE: signal completion
                // ---------------------------------------------------------
                PF_DONE: begin
                    cmd_done <= 1'b1;
                    pf_state <= PF_IDLE;
                end

                default: pf_state <= PF_IDLE;
            endcase
        end
    end

endmodule
