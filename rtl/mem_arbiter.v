`include "defines.vh"

// =============================================================================
// mem_arbiter.v - Round-Robin Memory Arbiter for Multi-Engine Activation BRAM
// =============================================================================
//
// Arbitrates NUM_ENGINES engines sharing a single activation BRAM port.
// Supports burst grants: once granted, an engine keeps the bus for
// LOADS_PER_ROW consecutive reads to reduce switching overhead.
//
// Separate read and write arbitration.
// =============================================================================

module mem_arbiter #(
    parameter N_ENG   = 6,
    parameter ADDR_W  = 20,
    parameter BUS_W   = 256,
    parameter WR_W    = 256,           // Write data width (BUS_W)
    parameter BURST   = 2             // LOADS_PER_ROW: consecutive grants
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Per-engine read request interface
    input  wire [N_ENG-1:0]     eng_rd_req,
    input  wire [ADDR_W*N_ENG-1:0] eng_rd_addr,
    output reg  [N_ENG-1:0]     eng_rd_grant,
    output wire [BUS_W-1:0]     eng_rd_data,      // Broadcast to all engines
    output reg  [N_ENG-1:0]     eng_rd_valid,

    // Per-engine write request interface
    input  wire [N_ENG-1:0]     eng_wr_req,
    input  wire [ADDR_W*N_ENG-1:0] eng_wr_addr,
    input  wire [WR_W*N_ENG-1:0]   eng_wr_data,
    output reg  [N_ENG-1:0]     eng_wr_grant,

    // Single output to activation BRAM
    output reg                  mem_rd_en,
    output reg  [ADDR_W-1:0]    mem_rd_addr,
    input  wire [BUS_W-1:0]     mem_rd_data,
    input  wire                 mem_rd_valid,

    output reg                  mem_wr_en,
    output reg  [ADDR_W-1:0]    mem_wr_addr,
    output reg  [WR_W-1:0]      mem_wr_data
);

    // Broadcast read data to all engines
    assign eng_rd_data = mem_rd_data;

    // =========================================================================
    // Read Arbitration (Round-Robin with Burst)
    // =========================================================================
    reg [$clog2(N_ENG)-1:0] rd_last_grant;
    reg [$clog2(BURST)-1:0] rd_burst_cnt;
    reg                     rd_burst_active;
    reg [$clog2(N_ENG)-1:0] rd_burst_eng;

    // Track which engine was granted for rd_valid routing
    reg [$clog2(N_ENG)-1:0] rd_grant_pipe;

    integer ri;

    // Find next requesting engine after rd_last_grant (round-robin)
    reg [$clog2(N_ENG)-1:0] rd_next;
    reg rd_found;

    always @(*) begin
        rd_found = 1'b0;
        rd_next  = rd_last_grant;

        // Priority scan starting from engine after last grant
        for (ri = 0; ri < N_ENG; ri = ri + 1) begin
            if (!rd_found) begin
                if (eng_rd_req[(rd_last_grant + 1 + ri) % N_ENG]) begin
                    rd_next  = (rd_last_grant + 1 + ri) % N_ENG;
                    rd_found = 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_last_grant  <= 0;
            rd_burst_cnt   <= 0;
            rd_burst_active <= 1'b0;
            rd_burst_eng   <= 0;
            mem_rd_en      <= 1'b0;
            mem_rd_addr    <= 0;
            eng_rd_grant   <= 0;
            rd_grant_pipe  <= 0;
        end else begin
            mem_rd_en    <= 1'b0;
            eng_rd_grant <= 0;

            if (rd_burst_active) begin
                // Continue burst for current engine
                if (eng_rd_req[rd_burst_eng]) begin
                    mem_rd_en    <= 1'b1;
                    mem_rd_addr  <= eng_rd_addr[rd_burst_eng*ADDR_W +: ADDR_W];
                    eng_rd_grant[rd_burst_eng] <= 1'b1;
                    rd_grant_pipe <= rd_burst_eng;

                    if (rd_burst_cnt == BURST - 1) begin
                        rd_burst_active <= 1'b0;
                        rd_burst_cnt    <= 0;
                    end else begin
                        rd_burst_cnt <= rd_burst_cnt + 1;
                    end
                end else begin
                    // Engine stopped requesting mid-burst
                    rd_burst_active <= 1'b0;
                    rd_burst_cnt    <= 0;
                end
            end else if (rd_found) begin
                // New grant
                mem_rd_en    <= 1'b1;
                mem_rd_addr  <= eng_rd_addr[rd_next*ADDR_W +: ADDR_W];
                eng_rd_grant[rd_next] <= 1'b1;
                rd_last_grant <= rd_next;
                rd_grant_pipe <= rd_next;

                if (BURST > 1) begin
                    rd_burst_active <= 1'b1;
                    rd_burst_eng    <= rd_next;
                    rd_burst_cnt    <= 1;
                end
            end
        end
    end

    // Route rd_valid back to the engine that was granted
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eng_rd_valid <= 0;
        end else begin
            eng_rd_valid <= 0;
            if (mem_rd_valid)
                eng_rd_valid[rd_grant_pipe] <= 1'b1;
        end
    end

    // =========================================================================
    // Write Arbitration (Round-Robin, no burst needed)
    // =========================================================================
    reg [$clog2(N_ENG)-1:0] wr_last_grant;

    reg [$clog2(N_ENG)-1:0] wr_next;
    reg wr_found;
    integer wi;

    always @(*) begin
        wr_found = 1'b0;
        wr_next  = wr_last_grant;

        for (wi = 0; wi < N_ENG; wi = wi + 1) begin
            if (!wr_found) begin
                if (eng_wr_req[(wr_last_grant + 1 + wi) % N_ENG]) begin
                    wr_next  = (wr_last_grant + 1 + wi) % N_ENG;
                    wr_found = 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_last_grant <= 0;
            mem_wr_en     <= 1'b0;
            mem_wr_addr   <= 0;
            mem_wr_data   <= 0;
            eng_wr_grant  <= 0;
        end else begin
            mem_wr_en    <= 1'b0;
            eng_wr_grant <= 0;

            if (wr_found) begin
                mem_wr_en    <= 1'b1;
                mem_wr_addr  <= eng_wr_addr[wr_next*ADDR_W +: ADDR_W];
                mem_wr_data  <= eng_wr_data[wr_next*WR_W +: WR_W];
                eng_wr_grant[wr_next] <= 1'b1;
                wr_last_grant <= wr_next;
            end
        end
    end

endmodule
