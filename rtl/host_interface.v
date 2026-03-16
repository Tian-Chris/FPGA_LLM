// =============================================================================
// host_interface.v - AXI-Lite Host Interface
// =============================================================================
//
// AXI-Lite slave for host CPU control. Provides HBM base address registers
// for the inference pipeline. Weight loading is done via PCIe XDMA (out of
// scope for this module) — host only sets base addresses.
//
// Register Map:
//   0x00: Control Register
//         [0]: Start inference (write 1 to start)
//   0x04: Status Register (read-only)
//         [0]: Busy
//         [1]: Done
//         [2]: Done sticky (cleared on start)
//         [7:4]: Current state
//         [15:8]: Current layer
//   0x08: Batch Size
//   0x0C: Sequence Length
//   0x10: Weight HBM Base [27:0] (word address)
//   0x14: Activation HBM Base [27:0]
//   0x18: Output HBM Base [27:0]
//   0x1C: Decode Mode [0] (0=prefill, 1=decode)
//   0x20: Cache Length [15:0] (valid K/V rows already in cache)
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module host_interface #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32,
    parameter DIM_WIDTH      = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // AXI-Lite Slave Interface
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                         s_axi_awvalid,
    output reg                          s_axi_awready,
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                         s_axi_wvalid,
    output reg                          s_axi_wready,
    output reg  [1:0]                   s_axi_bresp,
    output reg                          s_axi_bvalid,
    input  wire                         s_axi_bready,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                         s_axi_arvalid,
    output reg                          s_axi_arready,
    output reg  [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]                   s_axi_rresp,
    output reg                          s_axi_rvalid,
    input  wire                         s_axi_rready,

    // Control outputs to FSM
    (* mark_debug = "true" *) output reg                          start,
    output reg  [DIM_WIDTH-1:0]         batch_size,
    output reg  [DIM_WIDTH-1:0]         seq_len,

    // HBM base address outputs
    output reg  [HBM_ADDR_W-1:0]       weight_base,
    output reg  [HBM_ADDR_W-1:0]       act_base,
    output reg  [HBM_ADDR_W-1:0]       kv_base,
    output reg  [HBM_ADDR_W-1:0]       output_base,

    // Decode mode outputs
    output reg                          decode_mode,
    output reg  [DIM_WIDTH-1:0]         cache_len,

    // Status inputs from FSM
    input  wire                         done,
    input  wire                         busy,
    input  wire [4:0]                   current_state,
    input  wire [DIM_WIDTH-1:0]         current_layer
);

    // -------------------------------------------------------------------------
    // Register Addresses
    // -------------------------------------------------------------------------
    localparam ADDR_CONTROL     = 8'h00;
    localparam ADDR_STATUS      = 8'h04;
    localparam ADDR_BATCH_SIZE  = 8'h08;
    localparam ADDR_SEQ_LEN    = 8'h0C;
    localparam ADDR_WEIGHT_BASE = 8'h10;
    localparam ADDR_ACT_BASE    = 8'h14;
    localparam ADDR_OUTPUT_BASE = 8'h18;
    localparam ADDR_DECODE_MODE = 8'h1C;
    localparam ADDR_CACHE_LEN   = 8'h20;
    localparam ADDR_KV_BASE     = 8'h24;

    // -------------------------------------------------------------------------
    // Internal Registers
    // -------------------------------------------------------------------------
    reg start_pulse;
    reg done_sticky;

    // Write state machine
    reg [1:0] wr_state;
    localparam WR_IDLE = 2'd0;
    localparam WR_DATA = 2'd1;
    localparam WR_RESP = 2'd2;

    reg [7:0] wr_addr_latch;

    // Read state machine
    reg [1:0] rd_state;
    localparam RD_IDLE = 2'd0;
    localparam RD_DATA = 2'd1;

    // -------------------------------------------------------------------------
    // AXI Write Channel
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            start_pulse   <= 1'b0;
            batch_size    <= 16'd1;
            seq_len       <= 16'd64;
            weight_base   <= {HBM_ADDR_W{1'b0}};
            act_base      <= {HBM_ADDR_W{1'b0}};
            kv_base       <= {HBM_ADDR_W{1'b0}};
            output_base   <= {HBM_ADDR_W{1'b0}};
            decode_mode   <= 1'b0;
            cache_len     <= {DIM_WIDTH{1'b0}};
        end else begin
            start_pulse <= 1'b0;

            case (wr_state)
                WR_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;

                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_addr_latch <= s_axi_awaddr[7:0];
                        s_axi_awready <= 1'b0;
                    end

                    if (s_axi_wvalid && s_axi_wready) begin
                        s_axi_wready <= 1'b0;
                        wr_state <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    case (wr_addr_latch)
                        ADDR_CONTROL: begin
                            if (s_axi_wdata[0]) start_pulse <= 1'b1;
                        end
                        ADDR_BATCH_SIZE: begin
                            batch_size <= s_axi_wdata[DIM_WIDTH-1:0];
                        end
                        ADDR_SEQ_LEN: begin
                            seq_len <= s_axi_wdata[DIM_WIDTH-1:0];
                        end
                        ADDR_WEIGHT_BASE: begin
                            weight_base <= s_axi_wdata[HBM_ADDR_W-1:0];
                        end
                        ADDR_ACT_BASE: begin
                            act_base <= s_axi_wdata[HBM_ADDR_W-1:0];
                        end
                        ADDR_KV_BASE: begin
                            kv_base <= s_axi_wdata[HBM_ADDR_W-1:0];
                        end
                        ADDR_OUTPUT_BASE: begin
                            output_base <= s_axi_wdata[HBM_ADDR_W-1:0];
                        end
                        ADDR_DECODE_MODE: begin
                            decode_mode <= s_axi_wdata[0];
                        end
                        ADDR_CACHE_LEN: begin
                            cache_len <= s_axi_wdata[DIM_WIDTH-1:0];
                        end
                    endcase

                    wr_state <= WR_RESP;
                end

                WR_RESP: begin
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= 2'b00;

                    if (s_axi_bready && s_axi_bvalid) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // Start signal generation (single cycle pulse)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start <= 1'b0;
        end else begin
            start <= start_pulse && !busy;
        end
    end

    // -------------------------------------------------------------------------
    // AXI Read Channel
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_arready <= 1'b1;

                    if (s_axi_arvalid && s_axi_arready) begin
                        s_axi_arready <= 1'b0;

                        case (s_axi_araddr[7:0])
                            ADDR_CONTROL: begin
                                s_axi_rdata <= 32'd0;
                            end
                            ADDR_STATUS: begin
                                s_axi_rdata <= {16'd0,
                                               current_layer[7:0],
                                               3'd0, current_state,
                                               5'd0, done_sticky, done, busy};
                            end
                            ADDR_BATCH_SIZE: begin
                                s_axi_rdata <= {16'd0, batch_size};
                            end
                            ADDR_SEQ_LEN: begin
                                s_axi_rdata <= {16'd0, seq_len};
                            end
                            ADDR_WEIGHT_BASE: begin
                                s_axi_rdata <= {{(32-HBM_ADDR_W){1'b0}}, weight_base};
                            end
                            ADDR_ACT_BASE: begin
                                s_axi_rdata <= {{(32-HBM_ADDR_W){1'b0}}, act_base};
                            end
                            ADDR_KV_BASE: begin
                                s_axi_rdata <= {{(32-HBM_ADDR_W){1'b0}}, kv_base};
                            end
                            ADDR_OUTPUT_BASE: begin
                                s_axi_rdata <= {{(32-HBM_ADDR_W){1'b0}}, output_base};
                            end
                            ADDR_DECODE_MODE: begin
                                s_axi_rdata <= {31'd0, decode_mode};
                            end
                            ADDR_CACHE_LEN: begin
                                s_axi_rdata <= {16'd0, cache_len};
                            end
                            default: begin
                                s_axi_rdata <= 32'hDEADBEEF;
                            end
                        endcase

                        rd_state <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    s_axi_rvalid <= 1'b1;
                    s_axi_rresp  <= 2'b00;

                    if (s_axi_rready && s_axi_rvalid) begin
                        s_axi_rvalid <= 1'b0;
                        rd_state     <= RD_IDLE;
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Done Sticky Flag
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_sticky <= 1'b0;
        end else begin
            if (done)
                done_sticky <= 1'b1;
            else if (start_pulse)
                done_sticky <= 1'b0;
        end
    end

endmodule
