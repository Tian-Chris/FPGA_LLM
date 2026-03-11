// =============================================================================
// uram_nm_adapter.v — Scalar 16-bit ↔ URAM 256-bit Bridge
// =============================================================================
//
// Bridges scalar 16-bit read/write ports from non-matmul units (softmax,
// layernorm, activation, residual_add) to the 256-bit URAM bus.
//
// - Read cache: 1 bus word. Cache hit = 1 cycle, miss = 2 cycles (URAM read).
// - Write buffer: 1 bus word. Sequential writes to same word merge.
//   Word boundary cross flushes old buffer to URAM, starts new.
// - flush signal commits dirty write buffer to URAM.
// - cfg_col_bits selects address decomposition width (7/10/12).
//
// Address decomposition:
//   row      = flat_addr >> cfg_col_bits
//   col_word = flat_addr[cfg_col_bits-1:4]
//   el_idx   = flat_addr[3:0]
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module uram_nm_adapter #(
    parameter ROW_W  = 10,      // $clog2(URAM_ROWS)
    parameter COL_W  = 8,       // $clog2(URAM_COL_WORDS)
    parameter BUS_W  = 256,
    parameter DATA_W = 16,
    parameter SCALAR_AW = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // -----------------------------------------------------------------
    // Configuration (set by FSM before starting a non-matmul unit)
    // -----------------------------------------------------------------
    input  wire [3:0]               cfg_col_bits,   // 7, 10, or 12

    // -----------------------------------------------------------------
    // Scalar read port (from non-matmul units)
    // -----------------------------------------------------------------
    input  wire                     rd_en,
    input  wire [SCALAR_AW-1:0]    rd_addr,
    output reg  [DATA_W-1:0]       rd_data,
    output reg                      rd_valid,

    // -----------------------------------------------------------------
    // Scalar write port (from non-matmul units)
    // -----------------------------------------------------------------
    input  wire                     wr_en,
    input  wire [SCALAR_AW-1:0]    wr_addr,
    input  wire [DATA_W-1:0]       wr_data,

    // -----------------------------------------------------------------
    // Flush control (commit dirty write buffer to URAM)
    // -----------------------------------------------------------------
    input  wire                     flush,
    output reg                      flush_done,

    // -----------------------------------------------------------------
    // URAM read port (shared with uram_flush via mux in top_level)
    // -----------------------------------------------------------------
    output reg                      uram_rd_en,
    output reg  [ROW_W-1:0]        uram_rd_row,
    output reg  [COL_W-1:0]        uram_rd_col_word,
    input  wire [BUS_W-1:0]        uram_rd_data,
    input  wire                     uram_rd_valid,

    // -----------------------------------------------------------------
    // URAM write port (nm_wr port on uram_accum_buf)
    // -----------------------------------------------------------------
    output reg                      uram_wr_en,
    output reg  [ROW_W-1:0]        uram_wr_row,
    output reg  [COL_W-1:0]        uram_wr_col_word,
    output reg  [BUS_W-1:0]        uram_wr_data
);

    localparam BUS_EL = BUS_W / DATA_W;  // 16
    localparam EL_W   = $clog2(BUS_EL);  // 4

    // =====================================================================
    // Address Decomposition (case statement for Verilator compatibility)
    // =====================================================================
    reg [ROW_W-1:0]  addr_row;
    reg [COL_W-1:0]  addr_col_word;
    reg [EL_W-1:0]   addr_el_idx;

    // Decompose a flat address based on cfg_col_bits
    // col_bits: total column bits (including element index)
    // row = flat >> col_bits, col_word = flat[col_bits-1:4], el = flat[3:0]
    always @(*) begin
        addr_el_idx = rd_en ? rd_addr[EL_W-1:0] : wr_addr[EL_W-1:0];
        case (cfg_col_bits)
            4'd5: begin  // SIM_SMALL: MODEL_DIM=32 or MAX_SEQ_LEN=32
                addr_row      = rd_en ? rd_addr[SCALAR_AW-1:5] : wr_addr[SCALAR_AW-1:5];
                addr_col_word = rd_en ? rd_addr[4:4]            : wr_addr[4:4];
            end
            4'd6: begin  // SIM_SMALL: F_DIM=64
                addr_row      = rd_en ? rd_addr[SCALAR_AW-1:6] : wr_addr[SCALAR_AW-1:6];
                addr_col_word = rd_en ? rd_addr[5:4]            : wr_addr[5:4];
            end
            4'd7: begin
                addr_row      = rd_en ? rd_addr[SCALAR_AW-1:7] : wr_addr[SCALAR_AW-1:7];
                addr_col_word = rd_en ? rd_addr[6:4]            : wr_addr[6:4];
            end
            4'd10: begin
                addr_row      = rd_en ? rd_addr[SCALAR_AW-1:10] : wr_addr[SCALAR_AW-1:10];
                addr_col_word = rd_en ? rd_addr[9:4]             : wr_addr[9:4];
            end
            4'd12: begin
                addr_row      = rd_en ? rd_addr[SCALAR_AW-1:12] : wr_addr[SCALAR_AW-1:12];
                addr_col_word = rd_en ? rd_addr[11:4]            : wr_addr[11:4];
            end
            default: begin
                addr_row      = rd_en ? rd_addr[SCALAR_AW-1:10] : wr_addr[SCALAR_AW-1:10];
                addr_col_word = rd_en ? rd_addr[9:4]             : wr_addr[9:4];
            end
        endcase
    end

    // =====================================================================
    // Read Cache — 1 bus word
    // =====================================================================
    (* mark_debug = "true" *) reg                 cache_valid;
    reg [ROW_W-1:0]     cache_row;
    reg [COL_W-1:0]     cache_col_word;
    reg [BUS_W-1:0]     cache_data;

    wire cache_hit = cache_valid &&
                     (cache_row == addr_row) &&
                     (cache_col_word == addr_col_word);

    // =====================================================================
    // Write Buffer — 1 bus word
    // =====================================================================
    (* mark_debug = "true" *) reg                 wb_dirty;
    reg [ROW_W-1:0]     wb_row;
    reg [COL_W-1:0]     wb_col_word;
    reg [BUS_W-1:0]     wb_data;

    // =====================================================================
    // FSM
    // =====================================================================
    localparam AD_IDLE     = 3'd0;
    localparam AD_RD_WAIT  = 3'd1;   // Waiting for URAM read (cache miss)
    (* mark_debug = "true" *) reg [2:0]   ad_state;
    reg [EL_W-1:0] pending_el_idx;   // Element index for pending read

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ad_state       <= AD_IDLE;
            cache_valid    <= 1'b0;
            cache_row      <= {ROW_W{1'b0}};
            cache_col_word <= {COL_W{1'b0}};
            cache_data     <= {BUS_W{1'b0}};
            wb_dirty       <= 1'b0;
            wb_row         <= {ROW_W{1'b0}};
            wb_col_word    <= {COL_W{1'b0}};
            wb_data        <= {BUS_W{1'b0}};
            rd_data        <= {DATA_W{1'b0}};
            rd_valid       <= 1'b0;
            flush_done     <= 1'b0;
            uram_rd_en     <= 1'b0;
            uram_wr_en     <= 1'b0;
            uram_rd_row    <= {ROW_W{1'b0}};
            uram_rd_col_word <= {COL_W{1'b0}};
            uram_wr_row    <= {ROW_W{1'b0}};
            uram_wr_col_word <= {COL_W{1'b0}};
            uram_wr_data   <= {BUS_W{1'b0}};
            pending_el_idx <= {EL_W{1'b0}};
        end else begin
            // Default: clear one-shot signals
            rd_valid   <= 1'b0;
            flush_done <= 1'b0;
            uram_rd_en <= 1'b0;
            uram_wr_en <= 1'b0;

            case (ad_state)
                // ---------------------------------------------------------
                AD_IDLE: begin
                    // --- Write handling (higher priority than read) ---
                    if (wr_en) begin
                        if (wb_dirty && (wb_row != addr_row || wb_col_word != addr_col_word)) begin
                            // Word boundary cross — flush old write buffer
                            uram_wr_en       <= 1'b1;
                            uram_wr_row      <= wb_row;
                            uram_wr_col_word <= wb_col_word;
                            uram_wr_data     <= wb_data;
                            // Invalidate cache if it covers the flushed location
                            if (cache_valid && cache_row == wb_row && cache_col_word == wb_col_word) begin
                                cache_valid <= 1'b0;
                            end
                        end
                        // Start or merge into write buffer
                        if (!wb_dirty || (wb_row != addr_row || wb_col_word != addr_col_word)) begin
                            // New write buffer word — seed from cache to avoid
                            // read-through returning 0 for unwritten elements
                            wb_dirty    <= 1'b1;
                            wb_row      <= addr_row;
                            wb_col_word <= addr_col_word;
                            if (cache_valid && cache_row == addr_row && cache_col_word == addr_col_word)
                                wb_data <= cache_data;
                            else
                                wb_data <= {BUS_W{1'b0}};
                            wb_data[addr_el_idx * DATA_W +: DATA_W] <= wr_data;
                        end else begin
                            // Merge into existing write buffer
                            wb_data[addr_el_idx * DATA_W +: DATA_W] <= wr_data;
                        end
                    end

                    // --- Read handling ---
                    if (rd_en && !wr_en) begin
                        // Check if write buffer has the data (same location)
                        if (wb_dirty && wb_row == addr_row && wb_col_word == addr_col_word) begin
                            // Read from write buffer
                            rd_data  <= wb_data[addr_el_idx * DATA_W +: DATA_W];
                            rd_valid <= 1'b1;
                        end else if (cache_hit) begin
                            // Cache hit — return immediately
                            rd_data  <= cache_data[addr_el_idx * DATA_W +: DATA_W];
                            rd_valid <= 1'b1;
                        end else begin
                            // Cache miss — issue URAM read
                            uram_rd_en       <= 1'b1;
                            uram_rd_row      <= addr_row;
                            uram_rd_col_word <= addr_col_word;
                            pending_el_idx   <= addr_el_idx;
                            ad_state         <= AD_RD_WAIT;
                        end
                    end

                    // --- Flush handling ---
                    if (flush && !wr_en && !rd_en) begin
                        if (wb_dirty) begin
                            uram_wr_en       <= 1'b1;
                            uram_wr_row      <= wb_row;
                            uram_wr_col_word <= wb_col_word;
                            uram_wr_data     <= wb_data;
                            wb_dirty         <= 1'b0;
                            // Invalidate cache
                            if (cache_valid && cache_row == wb_row && cache_col_word == wb_col_word) begin
                                cache_valid <= 1'b0;
                            end
                        end
                        flush_done <= 1'b1;
                    end
                end

                // ---------------------------------------------------------
                // Wait for URAM read response (cache miss)
                // ---------------------------------------------------------
                AD_RD_WAIT: begin
                    if (uram_rd_valid) begin
                        // Update cache
                        cache_valid    <= 1'b1;
                        cache_row      <= uram_rd_row;      // Reuse the registered addresses
                        cache_col_word <= uram_rd_col_word;
                        cache_data     <= uram_rd_data;
                        // Return scalar element
                        rd_data  <= uram_rd_data[pending_el_idx * DATA_W +: DATA_W];
                        rd_valid <= 1'b1;
                        ad_state <= AD_IDLE;
                    end
                end

                default: ad_state <= AD_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Simulation init
    // =====================================================================
    initial begin
        ad_state       = AD_IDLE;
        cache_valid    = 1'b0;
        wb_dirty       = 1'b0;
        rd_valid       = 1'b0;
        flush_done     = 1'b0;
        uram_rd_en     = 1'b0;
        uram_wr_en     = 1'b0;
    end

endmodule
