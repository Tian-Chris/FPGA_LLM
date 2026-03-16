`include "defines.vh"
module activation_unit #(
    parameter DATA_WIDTH = 16,
    parameter MAX_DIM    = 256
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Control
    input  wire                     start,
    input  wire [15:0]              dim,
    output reg                      done,
    output reg                      busy,

    // Memory interface
    output reg                      mem_rd_en,
    output reg  [15:0]              mem_rd_addr,
    input  wire [DATA_WIDTH-1:0]    mem_rd_data,
    input  wire                     mem_rd_valid,

    output reg                      mem_wr_en,
    output reg  [15:0]              mem_wr_addr,
    output reg  [DATA_WIDTH-1:0]    mem_wr_data
);

    reg [1:0] state;
    localparam ST_IDLE    = 2'd0;
    localparam ST_PROCESS = 2'd1;
    localparam ST_DONE    = 2'd2;
    reg [15:0] dim_r, idx;

    reg relu_valid;
    reg [DATA_WIDTH-1:0] relu_out;

    reg [15:0] wr_addr_pipe1, wr_addr_pipe2;
    reg rd_inflight;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            mem_rd_en <= 1'b0;
            mem_wr_en <= 1'b0;
            idx       <= 0;
            relu_valid <= 1'b0;
            relu_out   <= 0;
            rd_inflight <= 1'b0;
        end else begin
            done      <= 1'b0;
            mem_rd_en <= 1'b0;
            mem_wr_en <= 1'b0;

            // Inline ReLU pipeline stage
            relu_valid <= mem_rd_valid;
            relu_out   <= ($signed(mem_rd_data) < 0) ? 0 : mem_rd_data;

            // Pipeline write address
            wr_addr_pipe1 <= mem_rd_addr;
            wr_addr_pipe2 <= wr_addr_pipe1;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state       <= ST_PROCESS;
                        busy        <= 1'b1;
                        dim_r       <= dim;
                        idx         <= 0;
                        rd_inflight <= 1'b0;
                    end
                end

                ST_PROCESS: begin
                    // Write takes priority (adapter drops reads during writes)
                    if (relu_valid) begin
                        mem_wr_en   <= 1'b1;
                        mem_wr_addr <= wr_addr_pipe2;
                        mem_wr_data <= relu_out;
                    end

                    // Issue read only when no write this cycle
                    if (idx < dim_r && !rd_inflight && !relu_valid) begin
                        mem_rd_en   <= 1'b1;
                        mem_rd_addr <= idx;
                        idx         <= idx + 1;
                        rd_inflight <= 1'b1;
                    end

                    if (mem_rd_valid)
                        rd_inflight <= 1'b0;

                    if (idx == dim_r && !relu_valid && !mem_rd_en && !rd_inflight) begin
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

endmodule
