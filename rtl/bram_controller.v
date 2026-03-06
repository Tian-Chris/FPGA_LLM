// =============================================================================
// bram_controller
// Description:
//   - Weight BRAM: Read-only during inference, written by host at init
//   - Activation BRAM: Double-buffered
//   - Data: Configurable (8-bit for weights, 16-bit for accumulators)
// =============================================================================

`include "defines.vh"

module bram_controller #(
    parameter DEPTH      = 300,    // Number of entries
    parameter DATA_W     = 8,        // Data width per entry
    parameter ADDR_W     = 16,       // Address width
    parameter NUM_BANKS  = 4,        // Number of parallel banks
    parameter INIT_FILE  = ""      // Optional initialization file
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Port A - compute interface
    input  wire                     pa_en,
    input  wire                     pa_we,
    input  wire [ADDR_W-1:0]        pa_addr,
    input  wire [DATA_W*NUM_BANKS-1:0] pa_wdata,
    output reg  [DATA_W*NUM_BANKS-1:0] pa_rdata,
    output reg                      pa_valid,

    // Port B - host interface
    input  wire                     pb_en,
    input  wire                     pb_we,
    input  wire [ADDR_W-1:0]        pb_addr,
    input  wire [DATA_W*NUM_BANKS-1:0] pb_wdata,
    output reg  [DATA_W*NUM_BANKS-1:0] pb_rdata,
    output reg                      pb_valid
);

    // -------------------------------------------------------------------------
    // BRAM Storage
    // -------------------------------------------------------------------------
    reg [DATA_W-1:0] mem_bank [0:NUM_BANKS-1][0:DEPTH-1];

    integer i, j;

    // -------------------------------------------------------------------------
    // Initialization for simulation
    // -------------------------------------------------------------------------
    initial begin
        if (INIT_FILE != "") begin
            // $readmemh(INIT_FILE, mem_bank); // Would need per-bank files
        end else begin
            // Initialize to zero
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                for (j = 0; j < DEPTH; j = j + 1) begin
                    mem_bank[i][j] = {DATA_W{1'b0}};
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Port A
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pa_rdata <= {(DATA_W*NUM_BANKS){1'b0}};
            pa_valid <= 1'b0;
        end else begin
            pa_valid <= pa_en;

            if (pa_en) begin
                if (pa_we) begin
                    // Write operation - write to all banks
                    for (i = 0; i < NUM_BANKS; i = i + 1) begin
                        mem_bank[i][pa_addr] <= pa_wdata[i*DATA_W +: DATA_W];
                    end
                end else begin
                    // Read operation - read from all banks
                    for (i = 0; i < NUM_BANKS; i = i + 1) begin
                        pa_rdata[i*DATA_W +: DATA_W] <= mem_bank[i][pa_addr];
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Port B
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pb_rdata <= {(DATA_W*NUM_BANKS){1'b0}};
            pb_valid <= 1'b0;
        end else begin
            pb_valid <= pb_en;

            if (pb_en) begin
                if (pb_we) begin
                    for (i = 0; i < NUM_BANKS; i = i + 1) begin
                        mem_bank[i][pb_addr] <= pb_wdata[i*DATA_W +: DATA_W];
                    end
                end else begin
                    for (i = 0; i < NUM_BANKS; i = i + 1) begin
                        pb_rdata[i*DATA_W +: DATA_W] <= mem_bank[i][pb_addr];
                    end
                end
            end
        end
    end
endmodule


// =============================================================================
// weight_bram
// =============================================================================

module weight_bram #(
    parameter DEPTH     = 300,  //random number
    parameter DATA_W    = 8,    // INT8 weights
    parameter ADDR_W    = 20,
    parameter NUM_BANKS = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Host interface for weight loading
    input  wire                     host_we,
    input  wire [ADDR_W-1:0]        host_addr,
    input  wire [DATA_W*NUM_BANKS-1:0] host_wdata,
    output wire                     host_ready,

    // Compute interface for inference (read-only)
    input  wire                     comp_en,
    input  wire [ADDR_W-1:0]        comp_addr,
    output wire [DATA_W*NUM_BANKS-1:0] comp_rdata,
    output wire                     comp_valid
);

    wire [DATA_W*NUM_BANKS-1:0] pa_rdata_internal;
    reg  comp_valid_r;

    bram_controller #(
        .DEPTH(DEPTH),
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .NUM_BANKS(NUM_BANKS)
    ) bram_inst (
        .clk(clk),
        .rst_n(rst_n),

        .pa_en(comp_en),
        .pa_we(1'b0),               // read only
        .pa_addr(comp_addr),
        .pa_wdata({(DATA_W*NUM_BANKS){1'b0}}),
        .pa_rdata(comp_rdata),
        .pa_valid(comp_valid),

        .pb_en(host_we),
        .pb_we(host_we),
        .pb_addr(host_addr),
        .pb_wdata(host_wdata),
        .pb_rdata(),
        .pb_valid()
    );

    assign host_ready = 1'b1;

endmodule


// =============================================================================
// activation_bram
// =============================================================================

module activation_bram #(
    parameter DEPTH     = 300,
    parameter DATA_W    = 16,               // INT16 for accumulated activations
    parameter ADDR_W    = 17,
    parameter NUM_BANKS = 8   // half of weight since int16 vs int8
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Buffer select (0=A, 1=B)
    input  wire                     read_buf_sel,
    input  wire                     write_buf_sel,

    // Read interface (from read buffer via Port A)
    input  wire                     rd_en,
    input  wire [ADDR_W-1:0]        rd_addr,
    output wire [DATA_W*NUM_BANKS-1:0] rd_data,
    output wire                     rd_valid,

    // Write interface (to write buffer via Port B)
    input  wire                     wr_en,
    input  wire [ADDR_W-1:0]        wr_addr,
    input  wire [DATA_W*NUM_BANKS-1:0] wr_data,

    // Secondary read interface (from write buffer via Port B)
    // Used by residual_add to read from both buffers simultaneously
    input  wire                     rd2_en,
    input  wire [ADDR_W-1:0]       rd2_addr,
    output wire [DATA_W*NUM_BANKS-1:0] rd2_data,
    output wire                     rd2_valid
);

    wire [DATA_W*NUM_BANKS-1:0] buf_a_rdata, buf_b_rdata;
    wire buf_a_valid, buf_b_valid;

    // Secondary read (rd2) from write buffer via Port B
    wire [DATA_W*NUM_BANKS-1:0] buf_a_rd2_rdata, buf_b_rd2_rdata;
    wire buf_a_rd2_valid, buf_b_rd2_valid;

    // Port B mux: write or secondary read (mutually exclusive)
    wire        buf_a_pb_en   = (wr_en & ~write_buf_sel) | (rd2_en & write_buf_sel);
    wire        buf_a_pb_we   = wr_en & ~write_buf_sel;
    wire [ADDR_W-1:0] buf_a_pb_addr = (wr_en & ~write_buf_sel) ? wr_addr : rd2_addr;

    wire        buf_b_pb_en   = (wr_en & write_buf_sel) | (rd2_en & ~write_buf_sel);
    wire        buf_b_pb_we   = wr_en & write_buf_sel;
    wire [ADDR_W-1:0] buf_b_pb_addr = (wr_en & write_buf_sel) ? wr_addr : rd2_addr;

    // Buffer A
    bram_controller #(
        .DEPTH(DEPTH),
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .NUM_BANKS(NUM_BANKS)
    ) buffer_a (
        .clk(clk),
        .rst_n(rst_n),

        .pa_en(rd_en & ~read_buf_sel),
        .pa_we(1'b0),
        .pa_addr(rd_addr),
        .pa_wdata({(DATA_W*NUM_BANKS){1'b0}}),
        .pa_rdata(buf_a_rdata),
        .pa_valid(buf_a_valid),

        .pb_en(buf_a_pb_en),
        .pb_we(buf_a_pb_we),
        .pb_addr(buf_a_pb_addr),
        .pb_wdata(wr_data),
        .pb_rdata(buf_a_rd2_rdata),
        .pb_valid(buf_a_rd2_valid)
    );

    // Buffer B
    bram_controller #(
        .DEPTH(DEPTH),
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .NUM_BANKS(NUM_BANKS)
    ) buffer_b (
        .clk(clk),
        .rst_n(rst_n),

        .pa_en(rd_en & read_buf_sel),
        .pa_we(1'b0),
        .pa_addr(rd_addr),
        .pa_wdata({(DATA_W*NUM_BANKS){1'b0}}),
        .pa_rdata(buf_b_rdata),
        .pa_valid(buf_b_valid),

        .pb_en(buf_b_pb_en),
        .pb_we(buf_b_pb_we),
        .pb_addr(buf_b_pb_addr),
        .pb_wdata(wr_data),
        .pb_rdata(buf_b_rd2_rdata),
        .pb_valid(buf_b_rd2_valid)
    );

    assign rd_data  = read_buf_sel ? buf_b_rdata : buf_a_rdata;
    assign rd_valid = read_buf_sel ? buf_b_valid : buf_a_valid;
    assign rd2_data  = write_buf_sel ? buf_a_rd2_rdata : buf_b_rd2_rdata;
    assign rd2_valid = write_buf_sel ? buf_a_rd2_valid : buf_b_rd2_valid;

endmodule
