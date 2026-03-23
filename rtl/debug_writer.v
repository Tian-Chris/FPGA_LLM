// =============================================================================
// debug_writer.v — Minimal Single-Beat AXI4 Write Master for Debug Tracing
// =============================================================================
//
// Writes a single 256-bit word per transaction to HBM via AXI4.
// Used by fsm_controller to log debug records at state transitions.
//
// States: IDLE → AW → W → B → IDLE
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module debug_writer #(
    parameter ID_W   = 4,
    parameter LEN_W  = 8
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Command interface (from fsm_controller)
    input  wire                     write_valid,
    input  wire [HBM_ADDR_W-1:0]   write_addr,
    input  wire [255:0]             write_data,
    output reg                      write_done,
    output wire                     write_busy,

    // AXI4 Write Master (to HBM)
    output reg  [ID_W-1:0]         m_axi_awid,
    output reg  [HBM_ADDR_W-1:0]  m_axi_awaddr,
    output reg  [LEN_W-1:0]       m_axi_awlen,
    output reg                     m_axi_awvalid,
    input  wire                    m_axi_awready,

    output reg  [255:0]            m_axi_wdata,
    output reg                     m_axi_wlast,
    output reg                     m_axi_wvalid,
    input  wire                    m_axi_wready,

    input  wire [ID_W-1:0]        m_axi_bid,
    input  wire [1:0]             m_axi_bresp,
    input  wire                    m_axi_bvalid,
    output reg                     m_axi_bready
);

    localparam S_IDLE = 2'd0;
    localparam S_AW   = 2'd1;
    localparam S_W    = 2'd2;
    localparam S_B    = 2'd3;

    reg [1:0] state;

    assign write_busy = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            write_done    <= 1'b0;
            m_axi_awid    <= {ID_W{1'b0}};
            m_axi_awaddr  <= {HBM_ADDR_W{1'b0}};
            m_axi_awlen   <= {LEN_W{1'b0}};
            m_axi_awvalid <= 1'b0;
            m_axi_wdata   <= 256'd0;
            m_axi_wlast   <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
        end else begin
            write_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (write_valid) begin
                        // Latch address and data, issue AW
                        m_axi_awaddr  <= write_addr;
                        m_axi_awlen   <= {LEN_W{1'b0}};  // single beat (len=0)
                        m_axi_awid    <= {ID_W{1'b0}};
                        m_axi_awvalid <= 1'b1;
                        m_axi_wdata   <= write_data;
                        m_axi_wlast   <= 1'b1;
                        m_axi_wvalid  <= 1'b1;
                        state         <= S_AW;
                    end
                end

                S_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                    end
                    // Both AW and W accepted → wait for B
                    if ((!m_axi_awvalid || (m_axi_awvalid && m_axi_awready)) &&
                        (!m_axi_wvalid  || (m_axi_wvalid  && m_axi_wready))) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b0;
                        m_axi_wlast   <= 1'b0;
                        m_axi_bready  <= 1'b1;
                        state         <= S_B;
                    end
                end

                S_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        write_done   <= 1'b1;
                        state        <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
