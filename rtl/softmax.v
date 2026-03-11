`include "defines.vh"

module softmax #(
    parameter DATA_W     = 16,              // Input data width (INT16)
    parameter OUT_W      = 16,              // Output width (UINT16)
    parameter MAX_LEN    = 128,             // Maximum sequence length
    parameter EXP_LUT_AW = 8,               // Exp LUT address width
    parameter EXP_LUT_DW = 16,              // Exp LUT data width
    parameter CAUSAL     = 0                // Enable causal masking (future tokens → 0)
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Control interface
    input  wire                 start,
    input  wire [15:0]          seq_len,
    input  wire [15:0]          row_idx,     // Current row index (for causal masking)
    input  wire [3:0]           scale_shift, // Right-shift for attention scaling (÷√head_dim)
    output reg                  busy,
    output reg                  done,

    // Input interface (streaming)
    output reg                  in_rd_en,
    output reg  [15:0]          in_rd_addr,
    input  wire [DATA_W-1:0]    in_rd_data,
    input  wire                 in_rd_valid,

    // Output interface (streaming)
    output reg                  out_wr_en,
    output reg  [15:0]          out_wr_addr,
    output reg  [OUT_W-1:0]     out_wr_data
);

    // -------------------------------------------------------------------------
    // State Machine
    // -------------------------------------------------------------------------
    (* mark_debug = "true" *) reg [2:0] state;
    localparam ST_IDLE      = 3'd0;
    localparam ST_FIND_MAX  = 3'd1;
    localparam ST_COMP_EXP  = 3'd2;
    localparam ST_NORMALIZE = 3'd3;
    localparam ST_DONE      = 3'd4;

    // -------------------------------------------------------------------------
    // Internal Registers
    // -------------------------------------------------------------------------
    reg signed [DATA_W-1:0] max_val;
    reg [31:0] exp_sum;
    reg [15:0] idx;            // Read request counter
    reg [15:0] rx_cnt;         // Valid data receive counter (NEW)
    reg [15:0] len_r;

    (* ram_style = "block" *) reg [EXP_LUT_DW-1:0] exp_buffer [0:MAX_LEN-1];

    // Pipeline registers
    reg signed [DATA_W-1:0] data_r;
    reg valid_r;

    // Read-in-flight tracking (adapter may take >1 cycle on cache miss)
    reg rd_inflight;

    // Scale + causal masking registers (latched on start)
    reg [3:0]  scale_r;
    reg [15:0] row_r;

    // Normalization pipeline registers (NEW)
    reg                  norm_valid_r;
    reg [15:0]           norm_idx_r;
    reg [EXP_LUT_DW-1:0] exp_buf_r;

    // -------------------------------------------------------------------------
    // LUTs (Initialization kept the same)
    // -------------------------------------------------------------------------
    reg [EXP_LUT_DW-1:0] exp_lut [0:(1<<EXP_LUT_AW)-1];
    reg [15:0] recip_lut [0:255];
    integer i;

    initial begin
        for (i = 0; i < (1<<EXP_LUT_AW); i = i + 1) begin
            exp_lut[i] = (i == 255) ? 16'h0100 : (16'h0001 + i[7:0]);
        end
        for (i = 1; i < 256; i = i + 1) begin
            recip_lut[i] = 16'hFFFF / i;
        end
        recip_lut[0] = 16'hFFFF;
    end

    // -------------------------------------------------------------------------
    // Exp Function
    // -------------------------------------------------------------------------
    function [EXP_LUT_DW-1:0] compute_exp;
        input signed [DATA_W-1:0] x;
        input signed [DATA_W-1:0] max_x;
        reg signed [DATA_W-1:0] diff;
        begin
            diff = x - max_x;

            // FIX: Map [-2040, 0] to [0, 255]
            if (diff <= -2040)
                compute_exp = exp_lut[0];
            else 
                compute_exp = exp_lut[(diff + 2040) >> 3]; 
        end
    endfunction

    // -------------------------------------------------------------------------
    // Normalization Function
    // -------------------------------------------------------------------------
    function [OUT_W-1:0] normalize;
        input [EXP_LUT_DW-1:0] exp_val;
        input [31:0] sum;
        reg [31:0] scaled;
        reg [7:0] recip_addr;
        reg [15:0] recip_val;
        begin
            if (sum[23:16] != 0)      recip_addr = sum[23:16];
            else if (sum[15:8] != 0)  recip_addr = sum[15:8];
            else                      recip_addr = (sum[7:0] != 0) ? sum[7:0] : 8'd1;
            
            recip_val = recip_lut[recip_addr];

            // Shifts adjusted for 16-bit output (8 fewer bits shifted)
            if (sum[23:16] != 0)      scaled = (exp_val * recip_val) >> 16;
            else if (sum[15:8] != 0)  scaled = (exp_val * recip_val) >> 8;
            else                      scaled = (exp_val * recip_val);

            if (scaled > 65535)       normalize = 16'hFFFF;
            else                      normalize = scaled[15:0];
        end
    endfunction

    // -------------------------------------------------------------------------
    // Main State Machine
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            in_rd_en     <= 1'b0;
            out_wr_en    <= 1'b0;
            max_val      <= {1'b1, {(DATA_W-1){1'b0}}};
            exp_sum      <= 0;
            idx          <= 0;
            rx_cnt       <= 0;
            rd_inflight  <= 1'b0;
            norm_valid_r <= 1'b0;
        end else begin
            done      <= 1'b0;
            out_wr_en <= 1'b0;

            // Global pipeline stages
            valid_r <= in_rd_valid;
            data_r  <= $signed(in_rd_data) >>> scale_r;  // Apply attention scaling

            case (state)
                ST_IDLE: begin
                    if (start && seq_len > 0) begin
                        state       <= ST_FIND_MAX;
                        busy        <= 1'b1;
                        len_r       <= seq_len;
                        idx         <= 0;
                        rx_cnt      <= 0;
                        rd_inflight <= 1'b0;
                        max_val     <= {1'b1, {(DATA_W-1){1'b0}}};
                        exp_sum     <= 0;
                        scale_r     <= scale_shift;
                        row_r       <= row_idx;
                    end
                end

                ST_FIND_MAX: begin
                    // 1. Issue Memory Reads (one at a time)
                    in_rd_en <= 1'b0;
                    if (idx < len_r && !rd_inflight) begin
                        in_rd_en    <= 1'b1;
                        in_rd_addr  <= idx;
                        idx         <= idx + 1;
                        rd_inflight <= 1'b1;
                    end

                    // 2. Clear inflight on response
                    if (in_rd_valid)
                        rd_inflight <= 1'b0;

                    // 3. Process Received Data (1 cycle after valid)
                    // Causal mask: skip max update for future tokens (col > row)
                    if (valid_r) begin
                        rx_cnt <= rx_cnt + 1;
                        if (CAUSAL == 0 || rx_cnt <= row_r) begin
                            if (data_r > max_val) max_val <= data_r;
                        end
                    end

                    // 4. State Transition
                    if (rx_cnt == len_r) begin
                        state       <= ST_COMP_EXP;
                        idx         <= 0;
                        rx_cnt      <= 0;
                        rd_inflight <= 1'b0;
                    end
                end

                ST_COMP_EXP: begin
                    // 1. Issue Memory Reads (one at a time)
                    in_rd_en <= 1'b0;
                    if (idx < len_r && !rd_inflight) begin
                        in_rd_en    <= 1'b1;
                        in_rd_addr  <= idx;
                        idx         <= idx + 1;
                        rd_inflight <= 1'b1;
                    end

                    // 2. Clear inflight on response
                    if (in_rd_valid)
                        rd_inflight <= 1'b0;

                    // 3. Process Received Data (1 cycle after valid)
                    // Causal mask: future tokens (col > row) get exp=0
                    if (valid_r) begin
                        rx_cnt <= rx_cnt + 1;
                        if (CAUSAL != 0 && rx_cnt > row_r) begin
                            exp_buffer[rx_cnt] <= {EXP_LUT_DW{1'b0}};
                            // Don't add to exp_sum — masked position
                        end else begin
                            exp_buffer[rx_cnt] <= compute_exp(data_r, max_val);
                            exp_sum <= exp_sum + compute_exp(data_r, max_val);
                        end
                    end

                    // 4. State Transition
                    if (rx_cnt == len_r) begin
                        state       <= ST_NORMALIZE;
                        idx         <= 0;
                        rd_inflight <= 1'b0;
                    end
                end

                ST_NORMALIZE: begin
                    // Synchronous read from RAM 
                    if (idx < len_r) begin
                        norm_valid_r <= 1'b1;
                        norm_idx_r   <= idx;
                        exp_buf_r    <= exp_buffer[idx];
                        idx          <= idx + 1;
                    end else begin
                        norm_valid_r <= 1'b0;
                    end

                    // Write output (1 cycle delayed)
                    if (norm_valid_r) begin
                        out_wr_en   <= 1'b1;
                        out_wr_addr <= norm_idx_r;
                        out_wr_data <= normalize(exp_buf_r, exp_sum);
                        
                        if (norm_idx_r == len_r - 1) begin
                            state <= ST_DONE;
                        end
                    end
                end

                ST_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule