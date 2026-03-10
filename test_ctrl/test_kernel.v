// =============================================================================
// test_kernel.v — Minimal Vitis kernel: AXI-Lite control + single HBM R/W
// =============================================================================
// On ap_start: read 1x256-bit word from output_base, invert bits, write back.
// This tests the full HBM read+write path through the Vitis shell.
// =============================================================================

module test_kernel #(
    parameter C_S_AXI_CONTROL_ADDR_WIDTH = 7,
    parameter C_S_AXI_CONTROL_DATA_WIDTH = 32,
    parameter C_M_AXI_ADDR_WIDTH         = 64,
    parameter C_M_AXI_DATA_WIDTH         = 256
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
    input  wire                                    s_axi_control_rready,

    // AXI4 master to HBM (single port)
    output wire [C_M_AXI_ADDR_WIDTH-1:0]           m_axi_hbm0_awaddr,
    output wire [7:0]                              m_axi_hbm0_awlen,
    output wire [2:0]                              m_axi_hbm0_awsize,
    output wire [1:0]                              m_axi_hbm0_awburst,
    output wire                                    m_axi_hbm0_awvalid,
    input  wire                                    m_axi_hbm0_awready,
    output wire [C_M_AXI_DATA_WIDTH-1:0]           m_axi_hbm0_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0]         m_axi_hbm0_wstrb,
    output wire                                    m_axi_hbm0_wlast,
    output wire                                    m_axi_hbm0_wvalid,
    input  wire                                    m_axi_hbm0_wready,
    input  wire [1:0]                              m_axi_hbm0_bresp,
    input  wire                                    m_axi_hbm0_bvalid,
    output wire                                    m_axi_hbm0_bready,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]           m_axi_hbm0_araddr,
    output wire [7:0]                              m_axi_hbm0_arlen,
    output wire [2:0]                              m_axi_hbm0_arsize,
    output wire [1:0]                              m_axi_hbm0_arburst,
    output wire                                    m_axi_hbm0_arvalid,
    input  wire                                    m_axi_hbm0_arready,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]           m_axi_hbm0_rdata,
    input  wire [1:0]                              m_axi_hbm0_rresp,
    input  wire                                    m_axi_hbm0_rlast,
    input  wire                                    m_axi_hbm0_rvalid,
    output wire                                    m_axi_hbm0_rready
);

    // =========================================================================
    // Wires from vitis_control
    // =========================================================================
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
    reg  [4:0]  fsm_state_out;
    reg  [15:0] fsm_layer;

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
        .current_state(fsm_state_out),
        .current_layer(fsm_layer),
        .interrupt(interrupt)
    );

    // =========================================================================
    // HBM byte address from output_base (28-bit word addr -> 64-bit byte addr)
    // =========================================================================
    wire [63:0] hbm_addr = {31'b0, ctrl_output_base, 5'b0};

    // =========================================================================
    // FSM: read 1 word, invert, write back
    // =========================================================================
    localparam S_IDLE = 5'd0;
    localparam S_AR   = 5'd1;  // issue read address
    localparam S_R    = 5'd2;  // wait for read data
    localparam S_AW   = 5'd3;  // issue write address
    localparam S_W    = 5'd4;  // issue write data
    localparam S_B    = 5'd5;  // wait for write response
    localparam S_DONE = 5'd6;

    reg [4:0]  state;
    reg [C_M_AXI_DATA_WIDTH-1:0] rd_data;

    // AXI read channel
    reg        ar_valid;
    reg        r_ready;

    // AXI write channel
    reg        aw_valid;
    reg        w_valid;
    reg        b_ready;

    // Static AXI signals (single-beat burst)
    assign m_axi_hbm0_araddr  = hbm_addr;
    assign m_axi_hbm0_arlen   = 8'd0;     // 1 beat
    assign m_axi_hbm0_arsize  = 3'd5;     // 32 bytes = 256 bits
    assign m_axi_hbm0_arburst = 2'b01;    // INCR
    assign m_axi_hbm0_arvalid = ar_valid;
    assign m_axi_hbm0_rready  = r_ready;

    assign m_axi_hbm0_awaddr  = hbm_addr;
    assign m_axi_hbm0_awlen   = 8'd0;     // 1 beat
    assign m_axi_hbm0_awsize  = 3'd5;     // 32 bytes
    assign m_axi_hbm0_awburst = 2'b01;    // INCR
    assign m_axi_hbm0_awvalid = aw_valid;
    assign m_axi_hbm0_wdata   = ~rd_data; // inverted data
    assign m_axi_hbm0_wstrb   = {(C_M_AXI_DATA_WIDTH/8){1'b1}};
    assign m_axi_hbm0_wlast   = 1'b1;     // single beat
    assign m_axi_hbm0_wvalid  = w_valid;
    assign m_axi_hbm0_bready  = b_ready;

    always @(posedge ap_clk or negedge ap_rst_n) begin
        if (!ap_rst_n) begin
            state         <= S_IDLE;
            rd_data       <= {C_M_AXI_DATA_WIDTH{1'b0}};
            ar_valid      <= 1'b0;
            r_ready       <= 1'b0;
            aw_valid      <= 1'b0;
            w_valid       <= 1'b0;
            b_ready       <= 1'b0;
            fsm_done      <= 1'b0;
            fsm_busy      <= 1'b0;
            fsm_state_out <= 5'd0;
            fsm_layer     <= 16'd0;
        end else begin
            fsm_done      <= 1'b0;
            fsm_state_out <= state;

            case (state)
                S_IDLE: begin
                    fsm_busy <= 1'b0;
                    if (ctrl_start) begin
                        fsm_busy <= 1'b1;
                        ar_valid <= 1'b1;
                        r_ready  <= 1'b1;
                        state    <= S_AR;
                    end
                end

                S_AR: begin
                    if (m_axi_hbm0_arready) begin
                        ar_valid <= 1'b0;
                        state    <= S_R;
                    end
                end

                S_R: begin
                    if (m_axi_hbm0_rvalid) begin
                        rd_data <= m_axi_hbm0_rdata;
                        r_ready <= 1'b0;
                        aw_valid <= 1'b1;
                        state    <= S_AW;
                    end
                end

                S_AW: begin
                    if (m_axi_hbm0_awready) begin
                        aw_valid <= 1'b0;
                        w_valid  <= 1'b1;
                        state    <= S_W;
                    end
                end

                S_W: begin
                    if (m_axi_hbm0_wready) begin
                        w_valid <= 1'b0;
                        b_ready <= 1'b1;
                        state   <= S_B;
                    end
                end

                S_B: begin
                    if (m_axi_hbm0_bvalid) begin
                        b_ready <= 1'b0;
                        state   <= S_DONE;
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
