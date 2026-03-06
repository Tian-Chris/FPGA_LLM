// =============================================================================
// vitis_control.v — Vitis ap_ctrl_hs AXI-Lite Slave (FPGA target only)
// =============================================================================
//
// Standard Vitis kernel control register file. Replaces host_interface.v for
// FPGA deployment. Implements the ap_ctrl_hs protocol expected by XRT.
//
// Register Map (Vitis standard):
//   0x00: Control   [0] ap_start, [1] ap_done, [2] ap_idle, [3] ap_ready
//                   [7] auto_restart
//   0x04: GIE       [0] global interrupt enable
//   0x08: IER       [0] ap_done interrupt enable
//   0x0C: ISR       [0] ap_done interrupt status (write-1-to-clear)
//   0x10: batch_size [31:0]
//   0x18: seq_len    [31:0]
//   0x20: weight_ptr [31:0] (low)
//   0x24: weight_ptr [63:32] (high)
//   0x28: act_ptr    [31:0] (low)
//   0x2C: act_ptr    [63:32] (high)
//   0x30: output_ptr [31:0] (low)
//   0x34: output_ptr [63:32] (high)
//   0x38: decode_mode[31:0]
//   0x40: cache_len  [31:0]
//
// Compatible with Verilator: no X/Z, no SystemVerilog.
// =============================================================================

`include "defines.vh"

module vitis_control #(
    parameter AXI_ADDR_WIDTH = 7,
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
    output wire [1:0]                   s_axi_bresp,
    output reg                          s_axi_bvalid,
    input  wire                         s_axi_bready,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                         s_axi_arvalid,
    output reg                          s_axi_arready,
    output reg  [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    output reg                          s_axi_rvalid,
    input  wire                         s_axi_rready,

    // Control outputs to FSM (same interface as host_interface)
    output reg                          start,
    output reg  [DIM_WIDTH-1:0]         batch_size,
    output reg  [DIM_WIDTH-1:0]         seq_len,
    output wire [HBM_ADDR_W-1:0]       weight_base,
    output wire [HBM_ADDR_W-1:0]       act_base,
    output wire [HBM_ADDR_W-1:0]       output_base,
    output reg                          decode_mode,
    output reg  [DIM_WIDTH-1:0]         cache_len,

    // Status inputs from FSM
    input  wire                         done,
    input  wire                         busy,
    input  wire [4:0]                   current_state,
    input  wire [DIM_WIDTH-1:0]         current_layer,

    // Interrupt output
    output wire                         interrupt
);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;

    // Register addresses
    localparam ADDR_CTRL        = 7'h00;
    localparam ADDR_GIE         = 7'h04;
    localparam ADDR_IER         = 7'h08;
    localparam ADDR_ISR         = 7'h0C;
    localparam ADDR_BATCH_SIZE  = 7'h10;
    localparam ADDR_SEQ_LEN     = 7'h18;
    localparam ADDR_WEIGHT_LO   = 7'h20;
    localparam ADDR_WEIGHT_HI   = 7'h24;
    localparam ADDR_ACT_LO      = 7'h28;
    localparam ADDR_ACT_HI      = 7'h2C;
    localparam ADDR_OUTPUT_LO   = 7'h30;
    localparam ADDR_OUTPUT_HI   = 7'h34;
    localparam ADDR_DECODE_MODE = 7'h38;
    localparam ADDR_CACHE_LEN   = 7'h40;

    // -------------------------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------------------------
    reg         ap_start;
    reg         ap_done;
    reg         ap_idle;
    reg         auto_restart;
    reg         gie;
    reg         ier;
    reg         isr;

    // 64-bit pointer registers
    reg [31:0]  weight_ptr_lo, weight_ptr_hi;
    reg [31:0]  act_ptr_lo,    act_ptr_hi;
    reg [31:0]  output_ptr_lo, output_ptr_hi;

    assign interrupt = gie & ier & isr;

    // Byte-to-word address conversion: word_addr[27:0] = byte_addr[32:5]
    assign weight_base = {weight_ptr_hi[0], weight_ptr_lo[31:5]};
    assign act_base    = {act_ptr_hi[0],    act_ptr_lo[31:5]};
    assign output_base = {output_ptr_hi[0], output_ptr_lo[31:5]};

    // Done pulse detection
    reg done_r;
    wire done_pulse = done & ~done_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) done_r <= 1'b0;
        else        done_r <= done;
    end

    // -------------------------------------------------------------------------
    // Write Channel State Machine
    // -------------------------------------------------------------------------
    // AW and W can arrive in any order. Track both independently and only
    // proceed when both have been captured.
    reg [1:0] wr_state;
    localparam WR_IDLE = 2'd0;
    localparam WR_EXEC = 2'd1;
    localparam WR_RESP = 2'd2;
    reg [6:0]  wr_addr_latch;
    reg [31:0] wr_data_latch;
    reg        aw_done;  // AW handshake captured
    reg        w_done;   // W  handshake captured

    // Write-channel: capture address + data, produce response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            wr_addr_latch <= 7'd0;
            wr_data_latch <= 32'd0;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    // Accept both channels simultaneously
                    if (!aw_done) s_axi_awready <= 1'b1;
                    if (!w_done)  s_axi_wready  <= 1'b1;

                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_addr_latch <= s_axi_awaddr[6:0];
                        s_axi_awready <= 1'b0;
                        aw_done       <= 1'b1;
                    end
                    if (s_axi_wvalid && s_axi_wready) begin
                        wr_data_latch <= s_axi_wdata;
                        s_axi_wready  <= 1'b0;
                        w_done        <= 1'b1;
                    end

                    // Both captured? (check combinationally for same-cycle)
                    if ((aw_done || (s_axi_awvalid && s_axi_awready)) &&
                        (w_done  || (s_axi_wvalid  && s_axi_wready))) begin
                        wr_state      <= WR_EXEC;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b0;
                    end
                end
                WR_EXEC: begin
                    aw_done  <= 1'b0;
                    w_done   <= 1'b0;
                    wr_state <= WR_RESP;
                end
                WR_RESP: begin
                    s_axi_bvalid <= 1'b1;
                    if (s_axi_bready && s_axi_bvalid) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end
                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // Write strobe: pulses for one cycle when both addr+data are ready
    wire wr_fire = (wr_state == WR_EXEC);

    // -------------------------------------------------------------------------
    // Read Channel State Machine
    // -------------------------------------------------------------------------
    reg [1:0] rd_state;
    localparam RD_IDLE = 2'd0;
    localparam RD_DATA = 2'd1;
    reg        rd_ctrl_fired;  // flag: control register was read

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            rd_ctrl_fired <= 1'b0;
        end else begin
            rd_ctrl_fired <= 1'b0;
            case (rd_state)
                RD_IDLE: begin
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        s_axi_arready <= 1'b0;
                        case (s_axi_araddr[6:0])
                            ADDR_CTRL: begin
                                // Bit[7]=auto_restart [3]=ap_ready [2]=ap_idle [1]=ap_done [0]=ap_start
                                // ap_ready = ap_done for non-pipelined kernel (ap_ctrl_hs)
                                s_axi_rdata <= {24'd0, auto_restart,
                                                3'd0, ap_done, ap_idle, ap_done, ap_start};
                                rd_ctrl_fired <= 1'b1;
                            end
                            ADDR_GIE:         s_axi_rdata <= {31'd0, gie};
                            ADDR_IER:         s_axi_rdata <= {31'd0, ier};
                            ADDR_ISR:         s_axi_rdata <= {31'd0, isr};
                            ADDR_BATCH_SIZE:  s_axi_rdata <= {16'd0, batch_size};
                            ADDR_SEQ_LEN:     s_axi_rdata <= {16'd0, seq_len};
                            ADDR_WEIGHT_LO:   s_axi_rdata <= weight_ptr_lo;
                            ADDR_WEIGHT_HI:   s_axi_rdata <= weight_ptr_hi;
                            ADDR_ACT_LO:      s_axi_rdata <= act_ptr_lo;
                            ADDR_ACT_HI:      s_axi_rdata <= act_ptr_hi;
                            ADDR_OUTPUT_LO:   s_axi_rdata <= output_ptr_lo;
                            ADDR_OUTPUT_HI:   s_axi_rdata <= output_ptr_hi;
                            ADDR_DECODE_MODE: s_axi_rdata <= {31'd0, decode_mode};
                            ADDR_CACHE_LEN:   s_axi_rdata <= {16'd0, cache_len};
                            default:          s_axi_rdata <= 32'd0;
                        endcase
                        rd_state <= RD_DATA;
                    end
                end
                RD_DATA: begin
                    s_axi_rvalid <= 1'b1;
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
    // Unified Control Register Logic (single always block, no multi-driver)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ap_start      <= 1'b0;
            ap_done       <= 1'b0;
            ap_idle       <= 1'b1;
            auto_restart  <= 1'b0;
            gie           <= 1'b0;
            ier           <= 1'b0;
            isr           <= 1'b0;
            start         <= 1'b0;
            batch_size    <= 16'd1;
            seq_len       <= 16'd64;
            weight_ptr_lo <= 32'd0;
            weight_ptr_hi <= 32'd0;
            act_ptr_lo    <= 32'd0;
            act_ptr_hi    <= 32'd0;
            output_ptr_lo <= 32'd0;
            output_ptr_hi <= 32'd0;
            decode_mode   <= 1'b0;
            cache_len     <= {DIM_WIDTH{1'b0}};
        end else begin
            start <= 1'b0;  // default: single-cycle pulse

            // --- AXI write register updates ---
            if (wr_fire) begin
                case (wr_addr_latch)
                    ADDR_CTRL: begin
                        if (wr_data_latch[0]) ap_start    <= 1'b1;
                        if (wr_data_latch[7]) auto_restart <= 1'b1;
                    end
                    ADDR_GIE:         gie           <= wr_data_latch[0];
                    ADDR_IER:         ier           <= wr_data_latch[0];
                    ADDR_ISR: begin
                        if (wr_data_latch[0]) isr <= 1'b0;  // write-1-to-clear
                    end
                    ADDR_BATCH_SIZE:  batch_size    <= wr_data_latch[DIM_WIDTH-1:0];
                    ADDR_SEQ_LEN:     seq_len       <= wr_data_latch[DIM_WIDTH-1:0];
                    ADDR_WEIGHT_LO:   weight_ptr_lo <= wr_data_latch;
                    ADDR_WEIGHT_HI:   weight_ptr_hi <= wr_data_latch;
                    ADDR_ACT_LO:      act_ptr_lo    <= wr_data_latch;
                    ADDR_ACT_HI:      act_ptr_hi    <= wr_data_latch;
                    ADDR_OUTPUT_LO:   output_ptr_lo <= wr_data_latch;
                    ADDR_OUTPUT_HI:   output_ptr_hi <= wr_data_latch;
                    ADDR_DECODE_MODE: decode_mode   <= wr_data_latch[0];
                    ADDR_CACHE_LEN:   cache_len     <= wr_data_latch[DIM_WIDTH-1:0];
                    default: ;
                endcase
            end

            // --- ap_ctrl_hs protocol ---

            // ap_start: launch kernel when idle
            if (ap_start && ap_idle) begin
                start    <= 1'b1;
                ap_idle  <= 1'b0;
                ap_start <= 1'b0;
            end

            // ap_done: set on done pulse from FSM
            if (done_pulse) begin
                ap_done <= 1'b1;
                ap_idle <= 1'b1;
                isr     <= 1'b1;
                // Auto-restart
                if (auto_restart)
                    ap_start <= 1'b1;
            end

            // ap_done: clear-on-read of control register
            if (rd_ctrl_fired) begin
                ap_done <= 1'b0;
            end
        end
    end

endmodule
