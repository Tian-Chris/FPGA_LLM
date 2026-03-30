// =============================================================================
// uram_accum_buf.v — URAM Output Accumulation Buffer
// =============================================================================
//
// 1024×1024 × FP16 buffer for matmul output accumulation.
// Column-sharded write ports: each engine writes to non-overlapping column
// ranges, so no arbitration is needed on writes.
// Single read port for flush/DMA readback.
//
// Write serialization: A round-robin arbiter selects one writer per cycle
// from {clear, nm_adapter, engines}. This produces a simple dual-port
// RAM template (1 write always + 1 read always) that Vivado can infer
// as URAM. Engines receive backpressure via eng_wr_accept.
//
// Accumulation pipeline: When eng_wr_accum=1, the write becomes a 2-cycle
// read-modify-write operation. Cycle 1 issues a read on the shared read
// port; cycle 2 computes fp16_add and writes back. The arbiter stalls
// during the writeback cycle.
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
    // Simple dual-port template: one write port + one read port,
    // each in a separate always @(posedge clk) block with NO async reset.
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
    // Accumulation Pipeline — 2-cycle read-modify-write
    // =====================================================================
    // Cycle N:   acc_rd_start fires, read port reads old value from URAM
    // Cycle N+1: acc_pending=1, compute fp16_add, write result via write port
    //            Arbiter is stalled (no new writes accepted)
    reg                  acc_pending;
    reg [ADDR_W-1:0]    acc_addr_r;
    reg [BUS_W-1:0]     acc_data_r;

    // =====================================================================
    // Write Arbiter — round-robin among engines, priority to clear/nm_wr
    // =====================================================================
    // Priority: acc_pending (stall) > clearing > nm_wr > engines (round-robin)

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

        if (acc_pending) begin
            // Stall: accumulation writeback owns the write port this cycle
        end else if (clearing) begin
            // Highest priority: clear
            wr_en_mux   = 1'b1;
            wr_addr_mux = clear_idx;
            wr_data_mux = {BUS_W{1'b0}};
        end else if (nm_wr_en) begin
            // Second priority: non-matmul adapter write
            wr_en_mux   = 1'b1;
            wr_addr_mux = {nm_wr_row, nm_wr_col_word};
            wr_data_mux = nm_wr_data;
        end else begin
            // Round-robin among engines using pre-computed priority order
            for (e = 0; e < N_ENG; e = e + 1) begin
                if (!arb_eng_found && eng_wr_en[pri_idx[e]]) begin
                    arb_eng_found              = 1'b1;
                    arb_winner                 = pri_idx[e];
                    wr_en_mux                  = 1'b1;
                    wr_addr_mux                = {eng_wr_row[pri_idx[e] * ROW_W +: ROW_W],
                                                  eng_wr_col_word[pri_idx[e] * COL_W +: COL_W]};
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
    // Accumulation FSM
    // =====================================================================
    // acc_rd_start: the arbiter accepted an accumulate write; issue read
    wire acc_rd_start = wr_en_mux && wr_accum_mux && !acc_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_pending <= 1'b0;
        end else if (acc_rd_start) begin
            acc_pending <= 1'b1;
            acc_addr_r  <= wr_addr_mux;
            acc_data_r  <= wr_data_mux;
        end else begin
            acc_pending <= 1'b0;
        end
    end

    // =====================================================================
    // Port B: Shared Read Port (flush + accumulation)
    // =====================================================================
    // Flush reads and accumulation reads are mutually exclusive:
    //   - Flush reads happen after matmul (no engine writes)
    //   - Accumulation reads happen during matmul (no flush reads)
    // acc_rd_start takes priority if they ever overlap (defensive).
    wire                rd_en_int   = acc_rd_start || rd_en;
    wire [ADDR_W-1:0]  rd_addr_int = acc_rd_start ? wr_addr_mux
                                                   : {rd_row, rd_col_word};

    // URAM registered read output — NO async reset (required for URAM inference)
    // Pipeline stage 0 is the URAM output register itself.
    // Stages 1..RD_LATENCY-1 are additional delay registers.
    reg [BUS_W-1:0] rd_pipe_data [0:RD_LATENCY-1];
    integer s;

    always @(posedge clk) begin
        // Stage 0: URAM registered output (conditional enable)
        if (rd_en_int)
            rd_pipe_data[0] <= mem[rd_addr_int];
        // Stages 1+: pipeline shift (unconditional)
        for (s = 1; s < RD_LATENCY; s = s + 1)
            rd_pipe_data[s] <= rd_pipe_data[s-1];
    end

    // Flush valid pipeline (async reset on valid bits is fine — not URAM fabric)
    reg [RD_LATENCY-1:0] rd_valid_sr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_valid_sr <= {RD_LATENCY{1'b0}};
        else begin
            rd_valid_sr[0] <= rd_en && !acc_rd_start;
            for (s = 1; s < RD_LATENCY; s = s + 1)
                rd_valid_sr[s] <= rd_valid_sr[s-1];
        end
    end

    // Connect output from last pipeline stage
    always @(*) begin
        rd_data  = rd_pipe_data[RD_LATENCY-1];
        rd_valid = rd_valid_sr[RD_LATENCY-1];
    end

    // =====================================================================
    // Accumulation: FP16 element-wise add (combinational on registered data)
    // =====================================================================
    // rd_pipe_data[0] holds the old URAM value (registered previous cycle).
    // acc_data_r holds the new engine data (registered previous cycle).
    // Both inputs are registered, so this combinational logic is fine for timing.
    integer acc_i;
    reg [BUS_W-1:0] acc_result;

    always @(*) begin
        acc_result = {BUS_W{1'b0}};
        for (acc_i = 0; acc_i < BUS_EL; acc_i = acc_i + 1) begin
            acc_result[acc_i*DATA_W +: DATA_W] = fp16_add_comb(
                rd_pipe_data[0][acc_i*DATA_W +: DATA_W],
                acc_data_r[acc_i*DATA_W +: DATA_W]
            );
        end
    end

    // =====================================================================
    // Port A: Write Port
    // =====================================================================
    // Mux between direct writes (clear/nm/engine) and accumulation writeback.
    // acc_pending has exclusive use of the write port on its cycle.
    // MUST be in a separate always block from the read port for URAM inference.
    wire                mem_wr_en   = acc_pending || (wr_en_mux && !wr_accum_mux);
    wire [ADDR_W-1:0]  mem_wr_addr = acc_pending ? acc_addr_r  : wr_addr_mux;
    wire [BUS_W-1:0]   mem_wr_data = acc_pending ? acc_result  : wr_data_mux;


    always @(posedge clk) begin
        if (mem_wr_en)
            mem[mem_wr_addr] <= mem_wr_data;
    end

    // =====================================================================
    // Combinational FP16 adder for k-chunk accumulation
    // =====================================================================
    function [15:0] fp16_add_comb;
        input [15:0] a, b;
        reg        a_s, b_s, lg_s, sm_s, res_s, eff_sub;
        reg [4:0]  a_e, b_e, lg_e, sm_e;
        reg [9:0]  a_m, b_m, lg_mr, sm_mr;
        reg        a_z, b_z;
        reg [4:0]  ediff;
        reg [3:0]  shift;
        reg [13:0] lg_ext, sm_ext, aligned, restored;
        reg        sticky;
        reg [14:0] sum_m;
        reg [3:0]  lzc;
        reg [14:0] norm_m;
        reg [5:0]  norm_e;
        reg        norm_sticky;
        reg [9:0]  fmant;
        reg        g, r, s_all, rup;
        reg [10:0] rounded;
        reg [9:0]  rmant;
        reg [5:0]  rexp;
        integer    k;
        begin
            a_s = a[15]; a_e = a[14:10]; a_m = a[9:0];
            b_s = b[15]; b_e = b[14:10]; b_m = b[9:0];
            a_z = (a_e == 5'd0); b_z = (b_e == 5'd0);

            if ((a_e == 5'd31) || (b_e == 5'd31)) begin
                // Inf/NaN passthrough
                if (a_e == 5'd31 && a_m != 0)
                    fp16_add_comb = a;
                else if (b_e == 5'd31 && b_m != 0)
                    fp16_add_comb = b;
                else
                    fp16_add_comb = (a_e == 5'd31) ? a : b;
            end else if (a_z && b_z) begin
                fp16_add_comb = {a_s & b_s, 15'd0};
            end else if (a_z) begin
                fp16_add_comb = b;
            end else if (b_z) begin
                fp16_add_comb = a;
            end else begin
                if (a_e > b_e || (a_e == b_e && a_m >= b_m)) begin
                    lg_s = a_s; lg_e = a_e; lg_mr = a_m;
                    sm_s = b_s; sm_e = b_e; sm_mr = b_m;
                end else begin
                    lg_s = b_s; lg_e = b_e; lg_mr = b_m;
                    sm_s = a_s; sm_e = a_e; sm_mr = a_m;
                end
                res_s = lg_s;
                eff_sub = lg_s ^ sm_s;
                ediff = lg_e - sm_e;
                shift = (ediff > 5'd14) ? 4'd14 : ediff[3:0];
                lg_ext = {1'b1, lg_mr, 3'b000};
                sm_ext = {1'b1, sm_mr, 3'b000};
                aligned = sm_ext >> shift;
                restored = aligned << shift;
                sticky = (restored != sm_ext);

                if (eff_sub)
                    sum_m = {1'b0, lg_ext} - {1'b0, aligned} - {14'd0, sticky};
                else
                    sum_m = {1'b0, lg_ext} + {1'b0, aligned};

                if (sum_m == 15'd0) begin
                    fp16_add_comb = 16'd0;
                end else begin
                    lzc = 4'd15;
                    for (k = 14; k >= 0; k = k - 1) begin
                        if (sum_m[k] && lzc == 4'd15)
                            lzc = 14 - k;
                    end
                    norm_sticky = sticky;
                    if (lzc == 4'd0) begin
                        norm_sticky = sticky | sum_m[0];
                        norm_m = {1'b0, sum_m[14:1]};
                        norm_e = {1'b0, lg_e} + 6'd1;
                    end else if (lzc == 4'd1) begin
                        norm_m = sum_m;
                        norm_e = {1'b0, lg_e};
                    end else begin
                        norm_m = sum_m << (lzc - 4'd1);
                        norm_e = {1'b0, lg_e} - {2'd0, lzc} + 6'd1;
                    end
                    fmant = norm_m[12:3];
                    g = norm_m[2]; r = norm_m[1];
                    s_all = norm_m[0] | norm_sticky;
                    rup = g && (r || s_all || fmant[0]);
                    rounded = {1'b0, fmant} + {10'd0, rup};
                    if (rounded[10]) begin
                        rmant = 10'd0; rexp = norm_e + 6'd1;
                    end else begin
                        rmant = rounded[9:0]; rexp = norm_e;
                    end
                    // rexp[5] set means norm_e wrapped negative (lzc > lg_e+1):
                    // flush to zero before the >= 31 overflow check fires.
                    if (rexp[5] || rexp == 6'd0)
                        fp16_add_comb = {res_s, 15'd0};
                    else if (rexp >= 6'd31)
                        fp16_add_comb = {res_s, 5'b11111, 10'd0};
                    else
                        fp16_add_comb = {res_s, rexp[4:0], rmant};
                end
            end
        end
    endfunction

    // =====================================================================
    // Simulation init — zero memory (synthesis-excluded to avoid loop limit)
    // =====================================================================
    // synthesis translate_off
    integer init_i;
    initial begin
        for (init_i = 0; init_i < ROWS * WORDS; init_i = init_i + 1)
            mem[init_i] = {BUS_W{1'b0}};
    end
    // synthesis translate_on

endmodule
