// =============================================================================
// uram_accum_buf.v — URAM Output Accumulation Buffer
// =============================================================================
//
// 1024×1024 × INT16 buffer for matmul output accumulation.
// Column-sharded write ports: each engine writes to non-overlapping column
// ranges, so no arbitration is needed on writes.
// Single read port for flush/DMA readback.
//
// Write serialization: A round-robin arbiter selects one writer per cycle
// from {clear, nm_adapter, engines}. This produces a simple dual-port
// RAM template (1 write always + 1 read always) that Vivado can infer
// as URAM. Engines receive backpressure via eng_wr_accept.
//
// In simulation: same serialized write path (matches FPGA behavior).
// In synthesis:  (* ram_style = "ultra" *) for Vivado URAM inference.
// =============================================================================

`include "defines.vh"

module uram_accum_buf #(
    parameter ROWS    = 1024,
    parameter COLS    = 1024,
    parameter DATA_W  = 16,
    parameter BUS_W   = 256,
    parameter N_ENG   = 6,
    parameter ROW_W   = $clog2(ROWS),           // 10
    parameter COL_W   = $clog2(COLS / (BUS_W / DATA_W)), // 6 (64 words per row)
    parameter RD_LATENCY = 1   // Read latency: 1=current, 2-4=realistic URAM
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Clear — zero the buffer for a new matmul
    input  wire                 clear,

    // -----------------------------------------------------------------
    // Per-engine write ports (column-sharded, non-overlapping)
    // -----------------------------------------------------------------
    input  wire [N_ENG-1:0]         eng_wr_en,
    input  wire [ROW_W*N_ENG-1:0]   eng_wr_row,
    input  wire [COL_W*N_ENG-1:0]   eng_wr_col_word,
    input  wire [BUS_W*N_ENG-1:0]   eng_wr_data,
    input  wire [N_ENG-1:0]         eng_wr_accum,      // 1=add to existing (k-chunk accumulation)

    // Per-engine write accept (one-hot grant from arbiter)
    output reg  [N_ENG-1:0]         eng_wr_accept,

    // -----------------------------------------------------------------
    // Non-matmul write port (from uram_nm_adapter)
    // FSM guarantees mutual exclusion with engine writes.
    // -----------------------------------------------------------------
    input  wire                 nm_wr_en,
    input  wire [ROW_W-1:0]    nm_wr_row,
    input  wire [COL_W-1:0]    nm_wr_col_word,
    input  wire [BUS_W-1:0]    nm_wr_data,

    // -----------------------------------------------------------------
    // Flush read port (single reader — uram_flush unit)
    // -----------------------------------------------------------------
    input  wire                 rd_en,
    input  wire [ROW_W-1:0]    rd_row,
    input  wire [COL_W-1:0]    rd_col_word,
    output reg  [BUS_W-1:0]    rd_data,
    output reg                  rd_valid
);

    localparam BUS_EL    = BUS_W / DATA_W;       // 16
    localparam WORDS     = COLS / BUS_EL;        // 64
    localparam ADDR_W    = ROW_W + COL_W;

    // =====================================================================
    // Storage — 1024 rows × 64 words × 256-bit
    // =====================================================================
    // Flatten to [ROWS * WORDS] for Vivado URAM inference.
    // Simple dual-port template: one write always + one read always.
    (* ram_style = "ultra" *)
    reg [BUS_W-1:0] mem [0:ROWS * WORDS - 1];

    // =====================================================================
    // Clear logic — done over multiple cycles (background)
    // =====================================================================
    (* mark_debug = "true" *) reg         clearing;
    reg [ADDR_W-1:0] clear_idx;
    localparam CLEAR_MAX = ROWS * WORDS - 1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clearing  <= 1'b0;
            clear_idx <= 0;
        end else if (clear) begin
            clearing  <= 1'b1;
            clear_idx <= 0;
        end else if (clearing) begin
            if (clear_idx == CLEAR_MAX[ADDR_W-1:0])
                clearing <= 1'b0;
            else
                clear_idx <= clear_idx + 1;
        end
    end

    // =====================================================================
    // Write Arbiter — round-robin among engines, priority to clear/nm_wr
    // =====================================================================
    // Selects one writer per cycle. Produces a single (addr, data, en)
    // tuple for the memory write port.
    //
    // Priority: clearing > nm_wr > engines (round-robin)
    //
    // The round-robin pointer advances past the accepted engine each
    // cycle an engine write is granted.

    localparam ENG_W = $clog2(N_ENG > 1 ? N_ENG : 2);
    reg [ENG_W-1:0] arb_ptr;

    // Write mux outputs (combinational)
    reg                  wr_en_mux;
    reg [ADDR_W-1:0]     wr_addr_mux;
    reg [BUS_W-1:0]      wr_data_mux;
    reg                  wr_accum_mux;  // 1=read-modify-write accumulation

    // Arbiter winner tracking
    reg                  arb_eng_found;
    reg [ENG_W-1:0]      arb_winner;

    // Pre-computed priority order (rotated by arb_ptr)
    reg [ENG_W-1:0] pri_idx [0:N_ENG-1];
    integer p, pri_sum_i;

    always @(*) begin
        for (p = 0; p < N_ENG; p = p + 1) begin
            pri_sum_i = arb_ptr + p;
            if (pri_sum_i >= N_ENG)
                pri_idx[p] = pri_sum_i - N_ENG;
            else
                pri_idx[p] = pri_sum_i;
        end
    end

    integer e;
    always @(*) begin
        wr_en_mux    = 1'b0;
        wr_addr_mux  = {ADDR_W{1'b0}};
        wr_data_mux  = {BUS_W{1'b0}};
        wr_accum_mux = 1'b0;
        eng_wr_accept = {N_ENG{1'b0}};
        arb_eng_found = 1'b0;
        arb_winner    = {ENG_W{1'b0}};

        if (clearing) begin
            // Highest priority: clear
            wr_en_mux   = 1'b1;
            wr_addr_mux = clear_idx;
            wr_data_mux = {BUS_W{1'b0}};
        end else if (nm_wr_en) begin
            // Second priority: non-matmul adapter write
            wr_en_mux   = 1'b1;
            wr_addr_mux = nm_wr_row * WORDS + nm_wr_col_word;
            wr_data_mux = nm_wr_data;
        end else begin
            // Round-robin among engines using pre-computed priority order
            for (e = 0; e < N_ENG; e = e + 1) begin
                if (!arb_eng_found && eng_wr_en[pri_idx[e]]) begin
                    arb_eng_found              = 1'b1;
                    arb_winner                 = pri_idx[e];
                    wr_en_mux                  = 1'b1;
                    wr_addr_mux                = eng_wr_row[pri_idx[e] * ROW_W +: ROW_W] * WORDS +
                                                 eng_wr_col_word[pri_idx[e] * COL_W +: COL_W];
                    wr_data_mux                = eng_wr_data[pri_idx[e] * BUS_W +: BUS_W];
                    wr_accum_mux               = eng_wr_accum[pri_idx[e]];
                    eng_wr_accept[pri_idx[e]]  = 1'b1;
                end
            end
        end
    end

    // Advance round-robin pointer when an engine write is accepted
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_ptr <= {ENG_W{1'b0}};
        end else if (arb_eng_found) begin
            if (arb_winner == N_ENG - 1)
                arb_ptr <= {ENG_W{1'b0}};
            else
                arb_ptr <= arb_winner + 1;
        end
    end

    // =====================================================================
    // Port A: Single Write with optional accumulation
    // =====================================================================
    // When wr_accum_mux=1, perform element-wise INT16 addition with saturation
    // (read-modify-write). This implements k-chunk accumulation for matmuls
    // where K > PREFETCH_DIM.
    //
    // The read of mem[addr] in a non-blocking assignment uses the OLD value
    // (read-before-write), which is correct for accumulation.
    // =====================================================================
    integer acc_i;
    reg signed [DATA_W:0] acc_sum;  // DATA_W+1 bits for overflow detection
    reg [BUS_W-1:0] acc_result;

    always @(*) begin
        acc_result = {BUS_W{1'b0}};
        acc_sum = 0;
        for (acc_i = 0; acc_i < BUS_EL; acc_i = acc_i + 1) begin
            acc_sum = $signed(mem[wr_addr_mux][acc_i*DATA_W +: DATA_W]) +
                      $signed(wr_data_mux[acc_i*DATA_W +: DATA_W]);
            // Saturate to INT16
            if (acc_sum > 32767)
                acc_result[acc_i*DATA_W +: DATA_W] = 16'h7fff;
            else if (acc_sum < -32768)
                acc_result[acc_i*DATA_W +: DATA_W] = 16'h8000;
            else
                acc_result[acc_i*DATA_W +: DATA_W] = acc_sum[DATA_W-1:0];
        end
    end

    always @(posedge clk) begin
        if (wr_en_mux) begin
            if (wr_accum_mux)
                mem[wr_addr_mux] <= acc_result;
            else
                mem[wr_addr_mux] <= wr_data_mux;
        end
    end

    // =====================================================================
    // Port B: Flush Read — configurable latency pipeline (RD_LATENCY cycles)
    // =====================================================================
    // Stage 0 is the registered memory read. Stages 1..RD_LATENCY-1 are
    // additional delay registers. Output is taken from the last stage.
    // When RD_LATENCY=1, the for-loop body never executes (0 iterations).
    reg [BUS_W-1:0] rd_pipe_data  [0:RD_LATENCY-1];
    reg             rd_pipe_valid [0:RD_LATENCY-1];
    integer s;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s = 0; s < RD_LATENCY; s = s + 1) begin
                rd_pipe_data[s]  <= {BUS_W{1'b0}};
                rd_pipe_valid[s] <= 1'b0;
            end
        end else begin
            // Stage 0: registered memory read
            rd_pipe_valid[0] <= rd_en;
            if (rd_en)
                rd_pipe_data[0] <= mem[rd_row * WORDS + rd_col_word];
            // Stages 1..RD_LATENCY-1: shift register (no iterations when RD_LATENCY=1)
            for (s = 1; s < RD_LATENCY; s = s + 1) begin
                rd_pipe_data[s]  <= rd_pipe_data[s-1];
                rd_pipe_valid[s] <= rd_pipe_valid[s-1];
            end
        end
    end

    // Connect output from last pipeline stage
    always @(*) begin
        rd_data  = rd_pipe_data[RD_LATENCY-1];
        rd_valid = rd_pipe_valid[RD_LATENCY-1];
    end

    // =====================================================================
    // Simulation init — zero memory
    // =====================================================================
    integer init_i;
    initial begin
        for (init_i = 0; init_i < ROWS * WORDS; init_i = init_i + 1)
            mem[init_i] = {BUS_W{1'b0}};
    end

endmodule
