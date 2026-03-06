// =============================================================================
// test_kernel.v — Minimal Vitis kernel to test ap_ctrl_hs handshake
// =============================================================================
// No HBM ports. Just AXI-Lite control. The "FSM" starts on ap_start,
// waits a configurable number of cycles (from batch_size arg), then
// asserts done. Host reads back seq_len to verify args were written correctly.
// =============================================================================

module test_kernel #(
    parameter C_S_AXI_CONTROL_ADDR_WIDTH = 7,
    parameter C_S_AXI_CONTROL_DATA_WIDTH = 32
)(
    input  wire                                    ap_clk,
    input  wire                                    ap_rst_n,
    output wire                                    interrupt,

    // AXI-Lite slave (s_axi_control)
    input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]   s_axi_control_awaddr,
    input  wire                                    s_axi_control_awvalid,
    output wire                                    s_axi_control_awready,
    input  wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]   s_axi_control_wdata,
    input  wire [C_S_AXI_CONTROL_DATA_WIDTH/8-1:0] s_axi_control_wstrb,
    input  wire                                    s_axi_control_wvalid,
    output wire                                    s_axi_control_wready,
    output wire [1:0]                              s_axi_control_bresp,
    output wire                                    s_axi_control_bvalid,
    input  wire                                    s_axi_control_bready,
    input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]   s_axi_control_araddr,
    input  wire                                    s_axi_control_arvalid,
    output wire                                    s_axi_control_arready,
    output wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]   s_axi_control_rdata,
    output wire [1:0]                              s_axi_control_rresp,
    output wire                                    s_axi_control_rvalid,
    input  wire                                    s_axi_control_rready
);

    // Wires from vitis_control to our mini-FSM
    wire        ctrl_start;
    wire [15:0] ctrl_batch_size;
    wire [15:0] ctrl_seq_len;
    wire [27:0] ctrl_weight_base;
    wire [27:0] ctrl_act_base;
    wire [27:0] ctrl_output_base;
    wire        ctrl_decode_mode;
    wire [15:0] ctrl_cache_len;

    reg         fsm_done;
    reg         fsm_busy;
    reg  [4:0]  fsm_state;
    reg  [15:0] fsm_layer;

    // =========================================================================
    // Instantiate the real vitis_control (the module under test)
    // =========================================================================
    vitis_control #(
        .AXI_ADDR_WIDTH(C_S_AXI_CONTROL_ADDR_WIDTH),
        .AXI_DATA_WIDTH(C_S_AXI_CONTROL_DATA_WIDTH)
    ) u_ctrl (
        .clk(ap_clk),
        .rst_n(ap_rst_n),
        .s_axi_awaddr(s_axi_control_awaddr),
        .s_axi_awvalid(s_axi_control_awvalid),
        .s_axi_awready(s_axi_control_awready),
        .s_axi_wdata(s_axi_control_wdata),
        .s_axi_wstrb(s_axi_control_wstrb),
        .s_axi_wvalid(s_axi_control_wvalid),
        .s_axi_wready(s_axi_control_wready),
        .s_axi_bresp(s_axi_control_bresp),
        .s_axi_bvalid(s_axi_control_bvalid),
        .s_axi_bready(s_axi_control_bready),
        .s_axi_araddr(s_axi_control_araddr),
        .s_axi_arvalid(s_axi_control_arvalid),
        .s_axi_arready(s_axi_control_arready),
        .s_axi_rdata(s_axi_control_rdata),
        .s_axi_rresp(s_axi_control_rresp),
        .s_axi_rvalid(s_axi_control_rvalid),
        .s_axi_rready(s_axi_control_rready),
        .start(ctrl_start),
        .batch_size(ctrl_batch_size),
        .seq_len(ctrl_seq_len),
        .weight_base(ctrl_weight_base),
        .act_base(ctrl_act_base),
        .output_base(ctrl_output_base),
        .decode_mode(ctrl_decode_mode),
        .cache_len(ctrl_cache_len),
        .done(fsm_done),
        .busy(fsm_busy),
        .current_state(fsm_state),
        .current_layer(fsm_layer),
        .interrupt(interrupt)
    );

    // =========================================================================
    // Minimal FSM: start -> count batch_size cycles -> done
    // =========================================================================
    localparam S_IDLE = 5'd0;
    localparam S_RUN  = 5'd1;
    localparam S_DONE = 5'd2;

    reg [4:0]  state;
    reg [15:0] counter;

    always @(posedge ap_clk or negedge ap_rst_n) begin
        if (!ap_rst_n) begin
            state    <= S_IDLE;
            counter  <= 16'd0;
            fsm_done <= 1'b0;
            fsm_busy <= 1'b0;
            fsm_state <= 5'd0;
            fsm_layer <= 16'd0;
        end else begin
            fsm_done  <= 1'b0;
            fsm_state <= state;

            case (state)
                S_IDLE: begin
                    fsm_busy <= 1'b0;
                    if (ctrl_start) begin
                        fsm_busy <= 1'b1;
                        // Use batch_size as cycle count (min 1)
                        counter <= (ctrl_batch_size == 0) ? 16'd1 : ctrl_batch_size;
                        state   <= S_RUN;
                    end
                end
                S_RUN: begin
                    counter <= counter - 16'd1;
                    if (counter == 16'd1) begin
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    fsm_done <= 1'b1;
                    fsm_busy <= 1'b0;
                    state    <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
