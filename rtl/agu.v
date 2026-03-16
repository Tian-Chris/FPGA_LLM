`include "defines.vh"

// =============================================================================
// agu.v - Address Generation Unit for 32x32 Tiled Matmul
// =============================================================================
//
// Generates memory addresses for tiled matrix multiplication.
// Supports multi-cycle loads: each TILE-element row requires LOADS_PER_ROW
// consecutive bus reads (2 reads for 32 elements at 16 per 256-bit bus).
//
// Address granularity: BUS_ELEMS elements per address unit.
// =============================================================================

module agu #(
    parameter ADDR_W      = 20,
    parameter DIM_W       = 16,
    parameter TILE_W      = 5         // $clog2(32) = 5
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Control interface
    input  wire                 start,
    input  wire [2:0]           op_type,
    output reg                  busy,
    output reg                  done,

    // Matrix dimensions (in elements)
    input  wire [DIM_W-1:0]     dim_m,
    input  wire [DIM_W-1:0]     dim_k,
    input  wire [DIM_W-1:0]     dim_n,

    // Base addresses (in bus-word units)
    input  wire [ADDR_W-1:0]    base_a,
    input  wire [ADDR_W-1:0]    base_b,
    input  wire [ADDR_W-1:0]    base_c,

    // Stride configuration (in bus-word units: row_elements / BUS_ELEMS)
    input  wire [DIM_W-1:0]     stride_a,
    input  wire [DIM_W-1:0]     stride_b,
    input  wire [DIM_W-1:0]     stride_c,

    // Address outputs
    output reg                  addr_valid,
    output reg                  load_phase,     // 0 = Loading A, 1 = Loading B
    output reg  [ADDR_W-1:0]    addr_a,
    output reg  [ADDR_W-1:0]    addr_b,
    output reg  [ADDR_W-1:0]    addr_c,
    output reg                  is_write,

    // Tile information
    output reg  [TILE_W-1:0]    tile_row,
    output reg  [TILE_W-1:0]    tile_col,
    output reg                  tile_start,
    output reg                  tile_done,
    output reg  [DIM_W-1:0]     k_idx
);

    localparam TILE_SIZE     = 1 << TILE_W;          // 32
    localparam LOADS_PER_ROW = TILE_SIZE / BUS_ELEMS; // 2

    // Internal Registers
    reg [DIM_W-1:0] tile_m_idx;
    reg [DIM_W-1:0] tile_n_idx;
    reg [DIM_W-1:0] tile_k_idx;

    reg [TILE_W-1:0] local_m;
    reg [TILE_W-1:0] local_k;
    reg [$clog2(LOADS_PER_ROW)-1:0] load_sub_idx;  // Sub-word index within row

    reg [DIM_W-1:0] num_m_tiles;
    reg [DIM_W-1:0] num_n_tiles;
    reg [DIM_W-1:0] num_k_tiles;

    // State machine
    reg [2:0] state;
    localparam ST_IDLE      = 3'd0;
    localparam ST_INIT      = 3'd1;
    localparam ST_LOAD_A    = 3'd2;
    localparam ST_LOAD_B    = 3'd6;
    localparam ST_WRITE     = 3'd3;
    localparam ST_NEXT_TILE = 3'd4;
    localparam ST_DONE      = 3'd5;

    reg [2:0] op_type_r;
    reg transpose_b;

    // -------------------------------------------------------------------------
    // Tile count calculations
    // -------------------------------------------------------------------------
    wire [DIM_W-1:0] m_tiles = (dim_m + TILE_SIZE - 1) >> TILE_W;
    wire [DIM_W-1:0] n_tiles = (dim_n + TILE_SIZE - 1) >> TILE_W;
    wire [DIM_W-1:0] k_tiles = (dim_k + TILE_SIZE - 1) >> TILE_W;

    // -------------------------------------------------------------------------
    // Address Calculations
    // -------------------------------------------------------------------------
    // Global element indices
    wire [DIM_W-1:0] global_m = (tile_m_idx << TILE_W) + {{(DIM_W-TILE_W){1'b0}}, local_m};
    wire [DIM_W-1:0] global_k_base = (tile_k_idx << TILE_W);
    wire [DIM_W-1:0] global_n_base = (tile_n_idx << TILE_W);
    wire [DIM_W-1:0] global_k_elem = global_k_base + {{(DIM_W-TILE_W){1'b0}}, local_k};

    // A address: base_a + row * stride_a + (k_tile_offset + sub_word) in bus words
    // For A: each row is stride_a bus words wide. Within a tile, k offset = tile_k_idx * (TILE/BUS_ELEMS) + load_sub_idx
    wire [ADDR_W-1:0] addr_a_calc = base_a + (global_m * stride_a) +
                                    (global_k_base >> $clog2(BUS_ELEMS)) +
                                    {{(ADDR_W-1){1'b0}}, load_sub_idx};

    // B address: depends on transpose
    // Normal: B[k][n], addr = base_b + k_elem * stride_b + n_tile_offset + sub_word
    // Transposed: B[n][k], addr = base_b + n_row * stride_b + k_offset + sub_word
    wire [ADDR_W-1:0] addr_b_calc = transpose_b ?
        (base_b + ((global_n_base + {{(DIM_W-TILE_W){1'b0}}, local_k}) * stride_b) +
         (global_k_base >> $clog2(BUS_ELEMS)) + {{(ADDR_W-1){1'b0}}, load_sub_idx}) :
        (base_b + (global_k_elem * stride_b) +
         (global_n_base >> $clog2(BUS_ELEMS)) + {{(ADDR_W-1){1'b0}}, load_sub_idx});

    // C address: base_c + row * stride_c + n_tile_offset + sub_word
    wire [ADDR_W-1:0] addr_c_calc = base_c + (global_m * stride_c) +
                                    (global_n_base >> $clog2(BUS_ELEMS)) +
                                    {{(ADDR_W-1){1'b0}}, load_sub_idx};

    // Bounds checking
    wire in_bounds_m = global_m < dim_m;
    wire in_bounds_k = global_k_base < dim_k;
    wire in_bounds_n = global_n_base < dim_n;

    // -------------------------------------------------------------------------
    // Main State Machine
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            addr_valid   <= 1'b0;
            load_phase   <= 1'b0;
            is_write     <= 1'b0;
            tile_start   <= 1'b0;
            tile_done    <= 1'b0;
            {tile_m_idx, tile_n_idx, tile_k_idx} <= 0;
            {local_m, local_k}     <= 0;
            load_sub_idx <= 0;
            op_type_r    <= 0;
            transpose_b  <= 1'b0;
        end else begin
            addr_valid <= 1'b0;
            load_phase <= 1'b0;
            tile_start <= 1'b0;
            tile_done  <= 1'b0;
            done       <= 1'b0;
            is_write   <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state       <= ST_INIT;
                        busy        <= 1'b1;
                        op_type_r   <= op_type;
                        transpose_b <= (op_type == OP_MATMUL_T);
                    end
                end

                ST_INIT: begin
                    num_m_tiles <= m_tiles;
                    num_n_tiles <= n_tiles;
                    num_k_tiles <= k_tiles;
                    {tile_m_idx, tile_n_idx, tile_k_idx} <= 0;
                    {local_m, local_k} <= 0;
                    load_sub_idx <= 0;
                    tile_start   <= 1'b1;
                    state        <= ST_LOAD_A;
                end

                // ---------------------------------------------------------
                // Load A: iterate rows (local_m), each row = LOADS_PER_ROW reads
                // ---------------------------------------------------------
                ST_LOAD_A: begin
                    if (in_bounds_m && in_bounds_k) begin
                        addr_valid <= 1'b1;
                        addr_a     <= addr_a_calc;
                        tile_row   <= local_m;
                    end

                    if (load_sub_idx == LOADS_PER_ROW - 1) begin
                        // All sub-words for this row done
                        load_sub_idx <= 0;
                        if (local_m == TILE_SIZE - 1 || global_m == dim_m - 1) begin
                            local_m <= 0;
                            local_k <= 0;
                            load_sub_idx <= 0;
                            state   <= ST_LOAD_B;
                        end else begin
                            local_m <= local_m + 1;
                        end
                    end else begin
                        load_sub_idx <= load_sub_idx + 1;
                    end
                end

                // ---------------------------------------------------------
                // Load B: iterate k-rows (local_k), each row = LOADS_PER_ROW reads
                // ---------------------------------------------------------
                ST_LOAD_B: begin
                    load_phase <= 1'b1;
                    if (in_bounds_k && in_bounds_n) begin
                        addr_valid <= 1'b1;
                        addr_b     <= addr_b_calc;
                        tile_col   <= local_k;
                        k_idx      <= global_k_elem;
                    end

                    if (load_sub_idx == LOADS_PER_ROW - 1) begin
                        load_sub_idx <= 0;
                        if (local_k == TILE_SIZE - 1 || global_k_base + {{(DIM_W-TILE_W){1'b0}}, local_k} == dim_k - 1) begin
                            if (tile_k_idx == num_k_tiles - 1) begin
                                tile_done <= 1'b1;
                                {local_k, local_m} <= 0;
                                load_sub_idx <= 0;
                                state     <= ST_WRITE;
                            end else begin
                                tile_k_idx <= tile_k_idx + 1;
                                {local_m, local_k} <= 0;
                                load_sub_idx <= 0;
                                state      <= ST_LOAD_A;
                            end
                        end else begin
                            local_k <= local_k + 1;
                        end
                    end else begin
                        load_sub_idx <= load_sub_idx + 1;
                    end
                end

                // ---------------------------------------------------------
                // Write: iterate rows, each row = LOADS_PER_ROW writes
                // (Actually output serialization is handled by engine,
                //  AGU just signals write phase for address generation)
                // ---------------------------------------------------------
                ST_WRITE: begin
                    if (in_bounds_m && in_bounds_n) begin
                        addr_valid <= 1'b1;
                        addr_c     <= addr_c_calc;
                        is_write   <= 1'b1;
                    end

                    if (load_sub_idx == LOADS_PER_ROW - 1) begin
                        load_sub_idx <= 0;
                        if (local_m == TILE_SIZE - 1 || global_m == dim_m - 1) begin
                            local_m <= 0;
                            load_sub_idx <= 0;
                            state   <= ST_NEXT_TILE;
                        end else begin
                            local_m <= local_m + 1;
                        end
                    end else begin
                        load_sub_idx <= load_sub_idx + 1;
                    end
                end

                ST_NEXT_TILE: begin
                    load_sub_idx <= 0;
                    if (tile_n_idx == num_n_tiles - 1) begin
                        tile_n_idx <= 0;
                        if (tile_m_idx == num_m_tiles - 1) begin
                            state <= ST_DONE;
                        end else begin
                            tile_m_idx <= tile_m_idx + 1;
                            tile_k_idx <= 0;
                            tile_start <= 1'b1;
                            state      <= ST_LOAD_A;
                        end
                    end else begin
                        tile_n_idx <= tile_n_idx + 1;
                        tile_k_idx <= 0;
                        tile_start <= 1'b1;
                        state      <= ST_LOAD_A;
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
