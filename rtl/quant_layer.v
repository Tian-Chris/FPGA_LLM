`include "defines.vh"

// =============================================================================
// quant_layer.v  –  Dynamic Per-Tensor INT16 → INT8 Quantization
// =============================================================================
//
// True symmetric per-tensor quantization:
//   scale     = abs_max / 127
//   q[i]      = clamp(round(x[i] / scale), -128, 127)
//             = clamp(round(x[i] * 127 / abs_max), -128, 127)
//
// Fixed-point implementation:
//   inv_scale = floor((127 << FRAC) / abs_max)   [computed once in ST_SCALE]
//   q[i]      = clamp(round(x[i] * inv_scale >> FRAC), -128, 127)
//
// Three-pass FSM:
//   ST_SCAN  – read every BRAM word, track running abs_max
//   ST_SCALE – one clock to register inv_scale (division result)
//   ST_QUANT – re-read and quantize; pair two words per write
//
// Memory bus layout (matches the activation BRAM):
//   Each BRAM address holds BURST (=8) x INT16 = 128 bits (one "row-half").
//   After quantization, two reads produce one write of 2*BURST INT8 = 128 bits,
//   so the output occupies half as many BRAM addresses as the input.
//   In-place (src_base == dst_base) is safe: write addr = read_pair / 2 < read addr.
//
// Parameters:
//   IN_W  – element input width  (16 for INT16)
//   OUT_W – element output width (8  for INT8)
//   BURST – elements per BRAM word (= TILE_SIZE/2 = 8)
//   FRAC  – fractional bits for fixed-point scale (15 gives ±1 ULP accuracy)
// =============================================================================

module quant_layer #(
    parameter IN_W   = 16,
    parameter OUT_W  = 8,
    parameter BURST  = 8,
    parameter FRAC   = 15,
    parameter ADDR_W = 20,
    parameter DIM_W  = 16
)(
    input  wire              clk,
    input  wire              rst_n,

    // Control
    input  wire              start,
    input  wire [DIM_W-1:0]  dim,        // INT16 elements to quantize (divisible by BURST*2)
    input  wire [ADDR_W-1:0] src_base,
    input  wire [ADDR_W-1:0] dst_base,
    output reg               done,
    output reg               busy,

    // Memory read – BURST INT16 per word (128-bit BRAM bus)
    output reg                    mem_rd_en,
    output reg  [ADDR_W-1:0]      mem_rd_addr,
    input  wire [IN_W*BURST-1:0]  mem_rd_data,
    input  wire                   mem_rd_valid,

    // Memory write – 2*BURST INT8 per word (same 128-bit width)
    output reg                    mem_wr_en,
    output reg  [ADDR_W-1:0]      mem_wr_addr,
    output reg  [IN_W*BURST-1:0]  mem_wr_data
);

    // -------------------------------------------------------------------------
    // States
    // -------------------------------------------------------------------------
    localparam ST_IDLE  = 3'd0;
    localparam ST_SCAN  = 3'd1;
    localparam ST_SCALE = 3'd2;
    localparam ST_QUANT = 3'd3;
    localparam ST_DONE  = 3'd4;

    reg [2:0] state;

    // -------------------------------------------------------------------------
    // Registered command
    // -------------------------------------------------------------------------
    reg [DIM_W-1:0]  n_words;       // dim / BURST  = number of 128-bit reads
    reg [ADDR_W-1:0] src_base_r;
    reg [ADDR_W-1:0] dst_base_r;

    // -------------------------------------------------------------------------
    // Counters
    // -------------------------------------------------------------------------
    reg [DIM_W-1:0]  scan_idx;      // scan read index    (0 .. n_words-1)
    reg [DIM_W-1:0]  quant_rd_idx;  // quant read index   (0 .. n_words-1)
    reg [DIM_W-1:0]  quant_wr_idx;  // quant write index  (0 .. n_words/2-1)

    // -------------------------------------------------------------------------
    // Abs-max (17 bits: safely represents abs(-32768) = 32768)
    // -------------------------------------------------------------------------
    reg [IN_W:0] abs_max;

    // -------------------------------------------------------------------------
    // Scale factor: inv_scale = (127 << FRAC) / abs_max
    //   Max value: 127 * 2^15 = 4,161,536  <  2^22  → 22 bits
    // -------------------------------------------------------------------------
    reg [21:0] inv_scale;

    // -------------------------------------------------------------------------
    // Pair buffer: lower-half quantized word waiting for its upper partner
    // -------------------------------------------------------------------------
    reg [OUT_W*BURST-1:0] lo_buf;    // 8 INT8 = 64 bits
    reg                   lo_valid;

    // =========================================================================
    // Functions
    // =========================================================================

    // -------------------------------------------------------------------------
    // abs_of: signed IN_W → unsigned (IN_W+1)
    // Uses 17-bit negation so abs(-32768) = 32768 is representable.
    // -------------------------------------------------------------------------
    function [IN_W:0] abs_of;
        input [IN_W-1:0] val;
        begin
            if (val[IN_W-1])
                abs_of = {1'b0, ~val} + {{IN_W{1'b0}}, 1'b1};  // 17-bit 2's complement
            else
                abs_of = {1'b0, val};
        end
    endfunction

    // -------------------------------------------------------------------------
    // word_abs_max: find max absolute value across BURST elements in one word.
    // -------------------------------------------------------------------------
    function [IN_W:0] word_abs_max;
        input [IN_W*BURST-1:0] data;
        integer k;
        reg [IN_W:0] cur, a;
        begin
            cur = 0;
            for (k = 0; k < BURST; k = k + 1) begin
                a = abs_of(data[k*IN_W +: IN_W]);
                if (a > cur) cur = a;
            end
            word_abs_max = cur;
        end
    endfunction

    // -------------------------------------------------------------------------
    // quantize_word: scale + round + saturate all BURST elements.
    // Returns OUT_W*BURST = 64 bits (8 INT8 packed).
    //
    // q = clamp(round(elem * iscale >> FRAC), -128, 127)
    //
    // Product width: signed 16 × unsigned 22 → 38-bit signed intermediate.
    // Result after >> FRAC is bounded to [-127, 127] by construction,
    // but the saturation guard covers any rounding edge cases.
    // -------------------------------------------------------------------------
    function [OUT_W*BURST-1:0] quantize_word;
        input [IN_W*BURST-1:0] data;
        input [21:0]           iscale;
        integer k;
        reg signed [IN_W-1:0] elem;
        reg signed [38:0]     prod;   // 16 + 22 + sign = 39 bits
        reg [OUT_W-1:0]       q;
        reg [OUT_W*BURST-1:0] result;
        begin
            result = {(OUT_W*BURST){1'b0}};
            for (k = 0; k < BURST; k = k + 1) begin
                elem = $signed(data[k*IN_W +: IN_W]);
                // Multiply, then add half-LSB for round-to-nearest
                prod = $signed(elem) * $signed({1'b0, iscale});
                prod = prod + (39'sd1 <<< (FRAC - 1));
                // Arithmetic right-shift
                prod = prod >>> FRAC;
                // Saturate to INT8
                if      ($signed(prod) > $signed(39'sd127))
                    q = {1'b0, {(OUT_W-1){1'b1}}};   // +127
                else if ($signed(prod) < -$signed(39'sd128))
                    q = {1'b1, {(OUT_W-1){1'b0}}};   // -128
                else
                    q = prod[OUT_W-1:0];
                result[k*OUT_W +: OUT_W] = q;
            end
            quantize_word = result;
        end
    endfunction

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            mem_rd_en    <= 1'b0;
            mem_wr_en    <= 1'b0;
            abs_max      <= 0;
            inv_scale    <= 0;
            lo_valid     <= 1'b0;
            lo_buf       <= 0;
            n_words      <= 0;
            scan_idx     <= 0;
            quant_rd_idx <= 0;
            quant_wr_idx <= 0;
            src_base_r   <= 0;
            dst_base_r   <= 0;
        end else begin
            done      <= 1'b0;
            mem_rd_en <= 1'b0;
            mem_wr_en <= 1'b0;

            case (state)

                // -------------------------------------------------------
                ST_IDLE: begin
                    if (start) begin
                        state        <= ST_SCAN;
                        busy         <= 1'b1;
                        src_base_r   <= src_base;
                        dst_base_r   <= dst_base;
                        n_words      <= dim >> $clog2(BURST);  // dim / BURST
                        scan_idx     <= 0;
                        quant_rd_idx <= 0;
                        quant_wr_idx <= 0;
                        abs_max      <= 0;
                        lo_valid     <= 1'b0;
                    end
                end

                // -------------------------------------------------------
                // Pass 1: read every BRAM word, track running abs_max
                // -------------------------------------------------------
                ST_SCAN: begin
                    if (scan_idx < n_words) begin
                        mem_rd_en   <= 1'b1;
                        mem_rd_addr <= src_base_r + scan_idx;
                        scan_idx    <= scan_idx + 1;
                    end

                    if (mem_rd_valid) begin
                        if (word_abs_max(mem_rd_data) > abs_max)
                            abs_max <= word_abs_max(mem_rd_data);
                    end

                    // All reads issued and last valid consumed
                    if (scan_idx == n_words && !mem_rd_valid)
                        state <= ST_SCALE;
                end

                // -------------------------------------------------------
                // Compute inv_scale (one registered clock cycle)
                // -------------------------------------------------------
                ST_SCALE: begin
                    if (abs_max == 0)
                        inv_scale <= 0;
                    else
                        inv_scale <= (22'd127 << FRAC) / abs_max;
                    state <= ST_QUANT;
                end

                // -------------------------------------------------------
                // Pass 2: quantize BRAM words in pairs, write 16 INT8 each
                //   Read 0 → lo_buf (8 INT8)
                //   Read 1 + lo_buf → write {hi_8_int8, lo_8_int8} = 128 bits
                // -------------------------------------------------------
                ST_QUANT: begin
                    if (quant_rd_idx < n_words) begin
                        mem_rd_en    <= 1'b1;
                        mem_rd_addr  <= src_base_r + quant_rd_idx;
                        quant_rd_idx <= quant_rd_idx + 1;
                    end

                    if (mem_rd_valid) begin
                        if (!lo_valid) begin
                            lo_buf   <= quantize_word(mem_rd_data, inv_scale);
                            lo_valid <= 1'b1;
                        end else begin
                            mem_wr_en    <= 1'b1;
                            mem_wr_addr  <= dst_base_r + quant_wr_idx;
                            // [127:64] = upper 8 INT8, [63:0] = lower 8 INT8
                            mem_wr_data  <= {quantize_word(mem_rd_data, inv_scale), lo_buf};
                            quant_wr_idx <= quant_wr_idx + 1;
                            lo_valid     <= 1'b0;
                        end
                    end

                    if (quant_rd_idx == n_words && !mem_rd_valid && !lo_valid)
                        state <= ST_DONE;
                end

                // -------------------------------------------------------
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
