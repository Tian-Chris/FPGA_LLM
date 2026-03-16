// =============================================================================
// mac_unit.v - Single Pipelined Multiply-Accumulate Unit
// =============================================================================
//
// Maps to one DSP48E2 on Xilinx UltraScale+:
//   Stage 1: Registered inputs (A1/B1 regs on DSP48E2)
//   Stage 2: Registered multiply (M reg on DSP48E2)
//   Stage 3: Accumulate (P reg on DSP48E2)
//
// Total latency: 3 cycles from input to acc_out update.
// This matches the DSP48E2's optimal A1->M->P pipeline configuration.
//
// Inputs:  a_in [DATA_W-1:0], b_in [DATA_W-1:0]
// Output:  acc_out [ACC_W-1:0]
// Control: clear (reset accumulator), enable (gate MAC operation)
// =============================================================================

module mac_unit #(
    parameter DATA_W = 16,
    parameter ACC_W  = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     clear,
    input  wire                     enable,

    input  wire signed [DATA_W-1:0] a_in,
    input  wire signed [DATA_W-1:0] b_in,

    output reg  signed [ACC_W-1:0]  acc_out
);

    // Stage 1: Registered inputs (breaks routing path into DSP)
    reg signed [DATA_W-1:0] a_r;
    reg signed [DATA_W-1:0] b_r;
    reg                     enable_s1;
    reg                     clear_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r       <= 0;
            b_r       <= 0;
            enable_s1 <= 1'b0;
            clear_s1  <= 1'b0;
        end else begin
            a_r       <= a_in;
            b_r       <= b_in;
            enable_s1 <= enable;
            clear_s1  <= clear;
        end
    end

    // Stage 2: Registered multiply
    reg signed [2*DATA_W-1:0] product_r;
    reg                       enable_s2;
    reg                       clear_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_r <= 0;
            enable_s2 <= 1'b0;
            clear_s2  <= 1'b0;
        end else begin
            product_r <= a_r * b_r;
            enable_s2 <= enable_s1;
            clear_s2  <= clear_s1;
        end
    end

    // Stage 3: Accumulate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= 0;
        end else if (clear_s2) begin
            acc_out <= 0;
        end else if (enable_s2) begin
            acc_out <= acc_out + product_r[ACC_W-1:0];
        end
    end

endmodule
