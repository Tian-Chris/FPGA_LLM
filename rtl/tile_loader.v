// =============================================================================
// tile_loader.v — HBM-to-Local-BRAM Tile Loader
// =============================================================================
//
// Generic tile loader used for both weight and activation loading.
// Accepts a command (HBM base address, row count, stride), fetches data
// via AXI4 read bursts, and stores it in a local buffer (32 rows × 2
// words/row = 64 × 256-bit words). Matmul engine reads from the local
// buffer via a 1-cycle-latency read port.
//
// Loading is blocking: the loader fills the entire buffer before signaling
// cmd_done. No prefetch or double-buffering (correctness first).
//
// Each tile row is TILE/BUS_ELEMS = 2 consecutive 256-bit words.
// For each row, one AXI burst of 2 beats is issued.
// Rows may be non-contiguous in HBM (stride parameter controls spacing).
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module tile_loader #(
    parameter TILE       = 32,
    parameter BUS_W      = 256,
    parameter DATA_W     = 16,
    parameter HBM_ADDR_W = 28,
    parameter ID_W       = 4,
    parameter LEN_W      = 8
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // -----------------------------------------------------------------
    // Command interface
    // -----------------------------------------------------------------
    input  wire                     cmd_valid,
    output reg                      cmd_ready,
    input  wire [HBM_ADDR_W-1:0]   cmd_hbm_base,     // HBM word address of first row
    input  wire [5:0]               cmd_tile_rows,    // Number of rows to load (1-32)
    input  wire [HBM_ADDR_W-1:0]   cmd_stride,       // HBM word stride between rows
    output reg                      cmd_done,

    // -----------------------------------------------------------------
    // AXI4 Read Address Channel (master → HBM)
    // -----------------------------------------------------------------
    output reg  [ID_W-1:0]         m_axi_arid,
    output reg  [HBM_ADDR_W-1:0]  m_axi_araddr,
    output reg  [LEN_W-1:0]       m_axi_arlen,
    (* mark_debug = "true" *) output reg                     m_axi_arvalid,
    (* mark_debug = "true" *) input  wire                    m_axi_arready,

    // -----------------------------------------------------------------
    // AXI4 Read Data Channel (HBM → master)
    // -----------------------------------------------------------------
    input  wire [ID_W-1:0]         m_axi_rid,
    input  wire [BUS_W-1:0]        m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rlast,
    (* mark_debug = "true" *) input  wire                    m_axi_rvalid,
    output reg                     m_axi_rready,

    // -----------------------------------------------------------------
    // Local buffer read interface (from matmul engine)
    // -----------------------------------------------------------------
    input  wire                    local_rd_en,
    input  wire [5:0]              local_rd_addr,     // 0-63
    output reg  [BUS_W-1:0]       local_rd_data,
    output reg                     local_rd_valid
);

    // =====================================================================
    // Local buffer — 64 words × 256-bit
    // =====================================================================
    localparam BUS_EL       = BUS_W / DATA_W;              // 16
    localparam WORDS_PER_ROW = TILE / BUS_EL;              // 2
    localparam BUF_DEPTH    = TILE * WORDS_PER_ROW;        // 64
    localparam BUF_ADDR_W   = $clog2(BUF_DEPTH);          // 6

    (* ram_style = "block" *) reg [BUS_W-1:0] buf_mem [0:BUF_DEPTH-1];

    // =====================================================================
    // FSM
    // =====================================================================
    localparam LD_IDLE = 2'd0;
    localparam LD_AR   = 2'd1;
    localparam LD_DATA = 2'd2;
    localparam LD_DONE = 2'd3;

    (* mark_debug = "true" *) reg [1:0]              ld_state;
    reg [5:0]              cur_row;         // Current row being loaded (0..tile_rows-1)
    reg [5:0]              tile_rows_r;     // Registered tile_rows
    reg [HBM_ADDR_W-1:0]  hbm_addr_r;     // Current HBM address (accumulator)
    reg [HBM_ADDR_W-1:0]  stride_r;       // Registered stride
    reg [BUF_ADDR_W-1:0]  wr_addr;        // Write pointer into buf_mem

    // =====================================================================
    // FSM Logic
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ld_state      <= LD_IDLE;
            cmd_ready     <= 1'b1;
            cmd_done      <= 1'b0;
            cur_row       <= 6'd0;
            tile_rows_r   <= 6'd0;
            hbm_addr_r    <= {HBM_ADDR_W{1'b0}};
            stride_r      <= {HBM_ADDR_W{1'b0}};
            wr_addr       <= {BUF_ADDR_W{1'b0}};
            m_axi_arid    <= {ID_W{1'b0}};
            m_axi_araddr  <= {HBM_ADDR_W{1'b0}};
            m_axi_arlen   <= {LEN_W{1'b0}};
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
        end else begin
            cmd_done <= 1'b0;

            case (ld_state)
                // ---------------------------------------------------------
                // IDLE: wait for command
                // ---------------------------------------------------------
                LD_IDLE: begin
                    cmd_ready     <= 1'b1;
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    if (cmd_valid && cmd_ready) begin
                        cmd_ready   <= 1'b0;
                        tile_rows_r <= cmd_tile_rows;
                        hbm_addr_r  <= cmd_hbm_base;
                        stride_r    <= cmd_stride;
                        cur_row     <= 6'd0;
                        wr_addr     <= {BUF_ADDR_W{1'b0}};
                        ld_state    <= LD_AR;
                    end
                end

                // ---------------------------------------------------------
                // AR: issue read address for current row
                // ---------------------------------------------------------
                LD_AR: begin
                    m_axi_arid    <= {ID_W{1'b0}};
                    m_axi_araddr  <= hbm_addr_r;
                    m_axi_arlen   <= WORDS_PER_ROW[LEN_W-1:0] - 1;  // 1 (2 beats)
                    m_axi_arvalid <= 1'b1;
                    m_axi_rready  <= 1'b0;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        ld_state      <= LD_DATA;
                    end
                end

                // ---------------------------------------------------------
                // DATA: receive read data beats, write to buffer
                // ---------------------------------------------------------
                LD_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        buf_mem[wr_addr] <= m_axi_rdata;
                        wr_addr <= wr_addr + 1;

                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;
                            if (cur_row == tile_rows_r - 1) begin
                                // All rows loaded
                                ld_state <= LD_DONE;
                            end else begin
                                // Next row
                                cur_row    <= cur_row + 1;
                                hbm_addr_r <= hbm_addr_r + stride_r;
                                ld_state   <= LD_AR;
                            end
                        end
                    end
                end

                // ---------------------------------------------------------
                // DONE: signal completion, return to idle
                // ---------------------------------------------------------
                LD_DONE: begin
                    cmd_done  <= 1'b1;
                    ld_state  <= LD_IDLE;
                end

                default: ld_state <= LD_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Local buffer read — 1-cycle registered latency
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            local_rd_data  <= {BUS_W{1'b0}};
            local_rd_valid <= 1'b0;
        end else begin
            local_rd_valid <= local_rd_en;
            if (local_rd_en)
                local_rd_data <= buf_mem[local_rd_addr];
        end
    end

    // =====================================================================
    // Simulation init — zero buffer
    // =====================================================================
    integer init_i;
    initial begin
        for (init_i = 0; init_i < BUF_DEPTH; init_i = init_i + 1)
            buf_mem[init_i] = {BUS_W{1'b0}};
    end

endmodule
