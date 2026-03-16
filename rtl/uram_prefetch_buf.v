// =============================================================================
// uram_prefetch_buf.v — 1024x1024 INT16 URAM Prefetch Buffer
// =============================================================================
//
// Simple dual-port buffer for prefetched matrix chunks from HBM.
// Write port: bulk fill from hbm_prefetch DMA engine.
// Read port: tile extraction by matmul_controller.
//
// Organization: ROWS rows x COL_WORDS 256-bit words per row.
// Default 1024 rows x 64 words = 57 URAMs.
// 1-cycle registered read latency.
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module uram_prefetch_buf #(
    parameter ROWS    = 1024,
    parameter COLS    = 1024,
    parameter DATA_W  = 16,
    parameter BUS_W   = 256,
    parameter ROW_W   = $clog2(ROWS),                    // 10
    parameter COL_W   = $clog2(COLS / (BUS_W / DATA_W))  // 6 (64 words per row)
)(
    input  wire                 clk,

    // -----------------------------------------------------------------
    // Write port (from hbm_prefetch)
    // -----------------------------------------------------------------
    input  wire                 wr_en,
    input  wire [ROW_W-1:0]    wr_row,
    input  wire [COL_W-1:0]    wr_col_word,
    input  wire [BUS_W-1:0]    wr_data,

    // -----------------------------------------------------------------
    // Read port (from matmul_controller)
    // -----------------------------------------------------------------
    input  wire                 rd_en,
    input  wire [ROW_W-1:0]    rd_row,
    input  wire [COL_W-1:0]    rd_col_word,
    output reg  [BUS_W-1:0]    rd_data,
    output reg                  rd_valid
);

    localparam BUS_EL = BUS_W / DATA_W;       // 16
    localparam WORDS  = COLS / BUS_EL;        // 64
    localparam ADDR_W = ROW_W + COL_W;

    // =====================================================================
    // Storage — simple dual-port (1 write + 1 read)
    // =====================================================================
    (* ram_style = "ultra" *)
    reg [BUS_W-1:0] mem [0:ROWS * WORDS - 1];

    // =====================================================================
    // Port A: Write
    // =====================================================================
    always @(posedge clk) begin
        if (wr_en)
            mem[wr_row * WORDS + wr_col_word] <= wr_data;
    end

    // =====================================================================
    // Port B: Read — 1-cycle registered latency
    // =====================================================================
    always @(posedge clk) begin
        rd_valid <= rd_en;
        if (rd_en)
            rd_data <= mem[rd_row * WORDS + rd_col_word];
    end

    // =====================================================================
    // Simulation init — zero memory
    // =====================================================================
    integer init_i;
    initial begin
        rd_data  = {BUS_W{1'b0}};
        rd_valid = 1'b0;
        for (init_i = 0; init_i < ROWS * WORDS; init_i = init_i + 1)
            mem[init_i] = {BUS_W{1'b0}};
    end

endmodule
