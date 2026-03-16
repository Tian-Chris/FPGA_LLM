//untested
// =============================================================================
// positional_embedding
// =============================================================================
//   output[t] = input[t] + pos_embed[t]
// Bitwidths:
//   - Input/Output: INT16
//   - Position embeddings: INT8
// =============================================================================

module positional_embedding #(
    parameter DATA_WIDTH   = 16,
    parameter POS_WIDTH    = 8, 
    parameter DIM_WIDTH    = 16,
    parameter ADDR_WIDTH   = 20,
    parameter MODEL_DIM    = 256,
    parameter MAX_SEQ_LEN  = 128
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Control
    input  wire                     start,
    input  wire [DIM_WIDTH-1:0]     seq_len,
    output reg                      done,
    output reg                      busy,

    // Position embedding base address
    input  wire [ADDR_WIDTH-1:0]    pos_embed_base,

    // Input token embeddings
    output reg                      in_rd_en,
    output reg  [ADDR_WIDTH-1:0]    in_rd_addr,
    input  wire [DATA_WIDTH-1:0]    in_rd_data,
    input  wire                     in_rd_valid,

    // Position embedding read
    output reg                      pos_rd_en,
    output reg  [ADDR_WIDTH-1:0]    pos_rd_addr,
    input  wire [POS_WIDTH-1:0]     pos_rd_data,
    input  wire                     pos_rd_valid,

    // Output
    output reg                      out_wr_en,
    output reg  [ADDR_WIDTH-1:0]    out_wr_addr,
    output reg  [DATA_WIDTH-1:0]    out_wr_data
);

    // State machine
    reg [1:0] state;
    localparam ST_IDLE    = 2'd0;
    localparam ST_PROCESS = 2'd1;
    localparam ST_DONE    = 2'd2;

    reg [DIM_WIDTH-1:0] seq_len_r;
    reg [DIM_WIDTH-1:0] t_idx;              // Token index
    reg [DIM_WIDTH-1:0] d_idx;              // Dimension index
    reg [ADDR_WIDTH-1:0] pos_base_r;

    // Pipeline
    reg in_valid_r, pos_valid_r;
    reg signed [DATA_WIDTH-1:0] in_data_r;
    reg signed [POS_WIDTH-1:0] pos_data_r;
    reg [ADDR_WIDTH-1:0] addr_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            in_rd_en  <= 1'b0;
            pos_rd_en <= 1'b0;
            out_wr_en <= 1'b0;
        end else begin
            done      <= 1'b0;
            in_rd_en  <= 1'b0;
            pos_rd_en <= 1'b0;
            out_wr_en <= 1'b0;

            // Pipeline
            in_valid_r  <= in_rd_valid;
            pos_valid_r <= pos_rd_valid;
            in_data_r   <= $signed(in_rd_data);
            pos_data_r  <= $signed(pos_rd_data);
            addr_r      <= in_rd_addr;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state      <= ST_PROCESS;
                        busy       <= 1'b1;
                        seq_len_r  <= seq_len;
                        pos_base_r <= pos_embed_base;
                        t_idx      <= 0;
                        d_idx      <= 0;
                    end
                end

                ST_PROCESS: begin
                    // Read input and position embedding
                    in_rd_en    <= 1'b1;
                    pos_rd_en   <= 1'b1;
                    in_rd_addr  <= t_idx * MODEL_DIM + d_idx;
                    pos_rd_addr <= pos_base_r + t_idx * MODEL_DIM + d_idx;

                    // Advance indices
                    if (d_idx == MODEL_DIM - 1) begin
                        d_idx <= 0;
                        if (t_idx == seq_len_r - 1) begin
                            // Done with all tokens
                        end else begin
                            t_idx <= t_idx + 1;
                        end
                    end else begin
                        d_idx <= d_idx + 1;
                    end

                    // Output with addition
                    if (in_valid_r && pos_valid_r) begin
                        out_wr_en   <= 1'b1;
                        out_wr_addr <= addr_r;
                        // Add position embedding (sign-extend POS_WIDTH to DATA_WIDTH)
                        out_wr_data <= saturate_add(in_data_r,
                                                    {{(DATA_WIDTH-POS_WIDTH){pos_data_r[POS_WIDTH-1]}},
                                                     pos_data_r});
                    end

                    // Check completion
                    if (t_idx == seq_len_r - 1 && d_idx == MODEL_DIM - 1 &&
                        !in_valid_r && !pos_valid_r) begin
                        state <= ST_DONE;
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

    function [DATA_WIDTH-1:0] saturate_add;
        input signed [DATA_WIDTH-1:0] a;
        input signed [DATA_WIDTH-1:0] b;
        reg signed [DATA_WIDTH:0] sum;
        begin
            sum = a + b;
            if (sum > $signed({{1{1'b0}}, {(DATA_WIDTH-1){1'b1}}}))
                saturate_add = {1'b0, {(DATA_WIDTH-1){1'b1}}};
            else if (sum < $signed({{1{1'b1}}, {(DATA_WIDTH-1){1'b0}}}))
                saturate_add = {1'b1, {(DATA_WIDTH-1){1'b0}}};
            else
                saturate_add = sum[DATA_WIDTH-1:0];
        end
    endfunction

endmodule
