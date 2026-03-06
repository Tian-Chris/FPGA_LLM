
`timescale 1ns/1ps

`include "defines.vh"

module tb_fsm_controller;

    // -------------------------------------------------------------------------
    // Testbench Parameters (small for fast simulation)
    // -------------------------------------------------------------------------
    localparam ADDR_W         = 20;
    localparam DIM_W          = 16;
    localparam MODEL_DIM      = 16;
    localparam INPUT_DIM      = 8;
    localparam F_DIM          = 32;
    localparam NUM_HEADS      = 2;
    localparam MAX_SEQ_LEN    = 8;
    localparam NUM_ENC_LAYERS = 1;
    localparam NUM_DEN_LAYERS = 1;
    localparam NUM_DIFF_STEPS = 1;

    localparam TIMEOUT_CYCLES = 10000;
    localparam CLK_PERIOD     = 10; // 100MHz clock

    // -------------------------------------------------------------------------
    // DUT Signals
    // -------------------------------------------------------------------------
    reg                     clk;
    reg                     rst_n;

    // Host interface
    reg                     start;
    reg  [DIM_W-1:0]        batch_size;
    reg  [DIM_W-1:0]        seq_len;
    wire                    done;
    wire                    busy;

    // Matmul controller interface
    wire                    mm_cmd_valid;
    wire [2:0]              mm_cmd_op;
    wire [DIM_W-1:0]        mm_cmd_m;
    wire [DIM_W-1:0]        mm_cmd_k;
    wire [DIM_W-1:0]        mm_cmd_n;
    wire [ADDR_W-1:0]       mm_cmd_a_base;
    wire [ADDR_W-1:0]       mm_cmd_b_base;
    wire [ADDR_W-1:0]       mm_cmd_c_base;
    reg                     mm_cmd_ready;
    reg                     mm_cmd_done;

    // Softmax controller interface
    wire                    sm_start;
    wire [DIM_W-1:0]        sm_seq_len;
    reg                     sm_done;

    // LayerNorm controller interface
    wire                    ln_start;
    wire [DIM_W-1:0]        ln_dim;
    wire [ADDR_W-1:0]       ln_param_base;
    reg                     ln_done;

    // Noise scheduler interface
    wire                    ns_start;
    wire [DIM_W-1:0]        ns_step;
    reg                     ns_done;
    reg  [15:0]             ns_alpha;
    reg  [15:0]             ns_sigma;

    // Sonar normalizer interface
    wire                    sn_start;
    wire                    sn_is_input;
    reg                     sn_done;

    // Activation buffer control
    wire                    act_buf_sel;

    // Debug/status outputs
    wire [4:0]              current_state;
    wire [DIM_W-1:0]        current_layer;
    wire [DIM_W-1:0]        current_diff_step;

    // -------------------------------------------------------------------------
    // Testbench Variables
    // -------------------------------------------------------------------------
    integer cycle_count;
    reg test_passed;
    reg idle_seen;
    reg busy_seen;
    reg done_seen;
    reg [4:0] prev_state;

    // Operation completion delay counters
    reg [3:0] mm_delay_cnt;
    reg [3:0] sm_delay_cnt;
    reg [3:0] ln_delay_cnt;
    reg [3:0] ns_delay_cnt;
    reg [3:0] sn_delay_cnt;

    reg mm_pending;
    reg sm_pending;
    reg ln_pending;
    reg ns_pending;
    reg sn_pending;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    fsm_controller #(
        .ADDR_W         (ADDR_W),
        .DIM_W          (DIM_W),
        .MODEL_DIM      (MODEL_DIM),
        .INPUT_DIM      (INPUT_DIM),
        .F_DIM          (F_DIM),
        .NUM_HEADS      (NUM_HEADS),
        .MAX_SEQ_LEN    (MAX_SEQ_LEN),
        .NUM_ENC_LAYERS (NUM_ENC_LAYERS),
        .NUM_DEN_LAYERS (NUM_DEN_LAYERS),
        .NUM_DIFF_STEPS (NUM_DIFF_STEPS)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (start),
        .batch_size         (batch_size),
        .seq_len            (seq_len),
        .done               (done),
        .busy               (busy),
        .mm_cmd_valid       (mm_cmd_valid),
        .mm_cmd_op          (mm_cmd_op),
        .mm_cmd_m           (mm_cmd_m),
        .mm_cmd_k           (mm_cmd_k),
        .mm_cmd_n           (mm_cmd_n),
        .mm_cmd_a_base      (mm_cmd_a_base),
        .mm_cmd_b_base      (mm_cmd_b_base),
        .mm_cmd_c_base      (mm_cmd_c_base),
        .mm_cmd_ready       (mm_cmd_ready),
        .mm_cmd_done        (mm_cmd_done),
        .sm_start           (sm_start),
        .sm_seq_len         (sm_seq_len),
        .sm_done            (sm_done),
        .ln_start           (ln_start),
        .ln_dim             (ln_dim),
        .ln_param_base      (ln_param_base),
        .ln_done            (ln_done),
        .ns_start           (ns_start),
        .ns_step            (ns_step),
        .ns_done            (ns_done),
        .ns_alpha           (ns_alpha),
        .ns_sigma           (ns_sigma),
        .sn_start           (sn_start),
        .sn_is_input        (sn_is_input),
        .sn_done            (sn_done),
        .act_buf_sel        (act_buf_sel),
        .current_state      (current_state),
        .current_layer      (current_layer),
        .current_diff_step  (current_diff_step)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // VCD Dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("scripts/wave.vcd");
        $dumpvars(0, tb_fsm_controller);
    end

    // -------------------------------------------------------------------------
    // Matmul Auto-Response Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mm_cmd_done  <= 1'b0;
            mm_pending   <= 1'b0;
            mm_delay_cnt <= 0;
        end else begin
            mm_cmd_done <= 1'b0; // One-shot pulse

            // Capture new matmul command
            if (mm_cmd_valid && mm_cmd_ready && !mm_pending) begin
                mm_pending   <= 1'b1;
                mm_delay_cnt <= 5; // Complete after 5 cycles
                $display("[%0t] MatMul command received: op=%0d, m=%0d, k=%0d, n=%0d",
                         $time, mm_cmd_op, mm_cmd_m, mm_cmd_k, mm_cmd_n);
            end

            // Countdown to completion
            if (mm_pending) begin
                if (mm_delay_cnt > 0) begin
                    mm_delay_cnt <= mm_delay_cnt - 1;
                end else begin
                    mm_cmd_done  <= 1'b1;
                    mm_pending   <= 1'b0;
                    $display("[%0t] MatMul operation completed", $time);
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Softmax Auto-Response Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sm_done      <= 1'b0;
            sm_pending   <= 1'b0;
            sm_delay_cnt <= 0;
        end else begin
            sm_done <= 1'b0;

            if (sm_start && !sm_pending) begin
                sm_pending   <= 1'b1;
                sm_delay_cnt <= 3; // Complete after 3 cycles
                $display("[%0t] Softmax started: seq_len=%0d", $time, sm_seq_len);
            end

            if (sm_pending) begin
                if (sm_delay_cnt > 0) begin
                    sm_delay_cnt <= sm_delay_cnt - 1;
                end else begin
                    sm_done    <= 1'b1;
                    sm_pending <= 1'b0;
                    $display("[%0t] Softmax completed", $time);
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // LayerNorm Auto-Response Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ln_done      <= 1'b0;
            ln_pending   <= 1'b0;
            ln_delay_cnt <= 0;
        end else begin
            ln_done <= 1'b0;

            if (ln_start && !ln_pending) begin
                ln_pending   <= 1'b1;
                ln_delay_cnt <= 4; // Complete after 4 cycles
                $display("[%0t] LayerNorm started: dim=%0d", $time, ln_dim);
            end

            if (ln_pending) begin
                if (ln_delay_cnt > 0) begin
                    ln_delay_cnt <= ln_delay_cnt - 1;
                end else begin
                    ln_done    <= 1'b1;
                    ln_pending <= 1'b0;
                    $display("[%0t] LayerNorm completed", $time);
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Noise Scheduler Auto-Response Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ns_done      <= 1'b0;
            ns_pending   <= 1'b0;
            ns_delay_cnt <= 0;
        end else begin
            ns_done <= 1'b0;

            if (ns_start && !ns_pending) begin
                ns_pending   <= 1'b1;
                ns_delay_cnt <= 2; // Complete after 2 cycles
                $display("[%0t] Noise scheduler started: step=%0d", $time, ns_step);
            end

            if (ns_pending) begin
                if (ns_delay_cnt > 0) begin
                    ns_delay_cnt <= ns_delay_cnt - 1;
                end else begin
                    ns_done    <= 1'b1;
                    ns_pending <= 1'b0;
                    $display("[%0t] Noise scheduler completed", $time);
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Sonar Normalizer Auto-Response Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sn_done      <= 1'b0;
            sn_pending   <= 1'b0;
            sn_delay_cnt <= 0;
        end else begin
            sn_done <= 1'b0;

            if (sn_start && !sn_pending) begin
                sn_pending   <= 1'b1;
                sn_delay_cnt <= 3; // Complete after 3 cycles
                $display("[%0t] Sonar normalizer started: is_input=%0d", $time, sn_is_input);
            end

            if (sn_pending) begin
                if (sn_delay_cnt > 0) begin
                    sn_delay_cnt <= sn_delay_cnt - 1;
                end else begin
                    sn_done    <= 1'b1;
                    sn_pending <= 1'b0;
                    $display("[%0t] Sonar normalizer completed", $time);
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // State Transition Monitor
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && current_state != prev_state) begin
            $display("[%0t] FSM State: %s (%0d) -> %s (%0d)",
                     $time,
                     get_state_name(prev_state), prev_state,
                     get_state_name(current_state), current_state);
            prev_state <= current_state;
        end
    end

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        // Initialize signals
        rst_n       = 0;
        start       = 0;
        batch_size  = 0;
        seq_len     = 0;
        mm_cmd_ready = 1; // Always ready
        ns_alpha    = 16'h3C00; // FP16: 1.0
        ns_sigma    = 16'h3800; // FP16: 0.5

        // Test tracking
        cycle_count = 0;
        test_passed = 0;
        idle_seen   = 0;
        busy_seen   = 0;
        done_seen   = 0;
        prev_state  = FSM_IDLE;

        $display("========================================");
        $display("FSM Controller Testbench Starting");
        $display("========================================");
        $display("Configuration:");
        $display("  MODEL_DIM=%0d, INPUT_DIM=%0d, F_DIM=%0d", MODEL_DIM, INPUT_DIM, F_DIM);
        $display("  NUM_HEADS=%0d, MAX_SEQ_LEN=%0d", NUM_HEADS, MAX_SEQ_LEN);
        $display("  NUM_ENC_LAYERS=%0d, NUM_DEN_LAYERS=%0d", NUM_ENC_LAYERS, NUM_DEN_LAYERS);
        $display("  NUM_DIFF_STEPS=%0d", NUM_DIFF_STEPS);
        $display("");

        // Reset sequence
        $display("[%0t] Applying reset...", $time);
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        $display("[%0t] Reset released", $time);

        // Verify idle state
        if (current_state == FSM_IDLE && !busy && !done) begin
            $display("[%0t] PASS: FSM in IDLE state", $time);
            idle_seen = 1;
        end else begin
            $display("[%0t] FAIL: Expected IDLE state, got state=%0d, busy=%0d, done=%0d",
                     $time, current_state, busy, done);
        end

        // Start inference
        @(posedge clk);
        $display("");
        $display("[%0t] Starting inference with batch_size=1, seq_len=4", $time);
        batch_size = 1;
        seq_len    = 4;
        start      = 1;
        @(posedge clk);
        start      = 0;

        // Wait a few cycles for busy to assert
        repeat(3) @(posedge clk);

        if (busy) begin
            $display("[%0t] PASS: FSM busy signal asserted", $time);
            busy_seen = 1;
        end else begin
            $display("[%0t] FAIL: FSM busy signal not asserted", $time);
        end

        if (current_state != FSM_IDLE) begin
            $display("[%0t] PASS: FSM transitioned from IDLE (current state=%0d)",
                     $time, current_state);
        end else begin
            $display("[%0t] FAIL: FSM still in IDLE state", $time);
        end

        // Wait for completion or timeout
        $display("");
        $display("[%0t] Waiting for FSM to complete...", $time);
        cycle_count = 0;
        while (!done && cycle_count < TIMEOUT_CYCLES) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            // Check for done pulse
            if (done) begin
                done_seen = 1;
                $display("");
                $display("[%0t] PASS: Done signal asserted after %0d cycles",
                         $time, cycle_count);
                break;
            end
        end

        // Timeout check
        if (cycle_count >= TIMEOUT_CYCLES) begin
            $display("");
            $display("[%0t] FAIL: Timeout after %0d cycles", $time, TIMEOUT_CYCLES);
            $display("  Current state: %s (%0d)", get_state_name(current_state), current_state);
            $display("  Current layer: %0d", current_layer);
            $display("  Current diff step: %0d", current_diff_step);
            $display("  Busy: %0d, Done: %0d", busy, done);
        end

        // Verify FSM returned to IDLE after done
        repeat(3) @(posedge clk);
        if (current_state == FSM_IDLE && !busy) begin
            $display("[%0t] PASS: FSM returned to IDLE state", $time);
        end else begin
            $display("[%0t] WARNING: FSM state=%0d, busy=%0d after done",
                     $time, current_state, busy);
        end

        // Final results
        $display("");
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("  IDLE state verified:  %s", idle_seen ? "PASS" : "FAIL");
        $display("  Busy signal asserted: %s", busy_seen ? "PASS" : "FAIL");
        $display("  Done signal asserted: %s", done_seen ? "PASS" : "FAIL");
        $display("  Total cycles: %0d", cycle_count);

        test_passed = idle_seen && busy_seen && done_seen;

        if (test_passed) begin
            $display("");
            $display("========================================");
            $display("  ALL TESTS PASSED");
            $display("========================================");
        end else begin
            $display("");
            $display("========================================");
            $display("  SOME TESTS FAILED");
            $display("========================================");
        end

        $display("");
        $display("Simulation complete.");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout Monitor
    // -------------------------------------------------------------------------
    initial begin
        #(CLK_PERIOD * TIMEOUT_CYCLES * 2);
        $display("");
        $display("[%0t] ERROR: Simulation timeout - forcing exit", $time);
        $finish;
    end

    // -------------------------------------------------------------------------
    // Helper Function: State Name
    // -------------------------------------------------------------------------
    function [200*8-1:0] get_state_name;
        input [4:0] state;
        begin
            case (state)
                FSM_IDLE:              get_state_name = "FSM_IDLE";
                FSM_LOAD_INPUT:        get_state_name = "FSM_LOAD_INPUT";
                FSM_FRONTEND_PROJ:     get_state_name = "FSM_FRONTEND_PROJ";
                FSM_ADD_POS_EMB:       get_state_name = "FSM_ADD_POS_EMB";
                FSM_SONAR_NORM_IN:     get_state_name = "FSM_SONAR_NORM_IN";
                FSM_CTX_ATTN_QKV:      get_state_name = "FSM_CTX_ATTN_QKV";
                FSM_CTX_ATTN_SCORE:    get_state_name = "FSM_CTX_ATTN_SCORE";
                FSM_CTX_ATTN_SOFTMAX:  get_state_name = "FSM_CTX_ATTN_SOFTMAX";
                FSM_CTX_ATTN_OUT:      get_state_name = "FSM_CTX_ATTN_OUT";
                FSM_CTX_ATTN_PROJ:     get_state_name = "FSM_CTX_ATTN_PROJ";
                FSM_CTX_LN1:           get_state_name = "FSM_CTX_LN1";
                FSM_CTX_FFN1:          get_state_name = "FSM_CTX_FFN1";
                FSM_CTX_FFN_ACT:       get_state_name = "FSM_CTX_FFN_ACT";
                FSM_CTX_FFN2:          get_state_name = "FSM_CTX_FFN2";
                FSM_CTX_LN2:           get_state_name = "FSM_CTX_LN2";
                FSM_DEN_ATTN_QKV:      get_state_name = "FSM_DEN_ATTN_QKV";
                FSM_DEN_ATTN_SCORE:    get_state_name = "FSM_DEN_ATTN_SCORE";
                FSM_DEN_ATTN_SOFTMAX:  get_state_name = "FSM_DEN_ATTN_SOFTMAX";
                FSM_DEN_ATTN_OUT:      get_state_name = "FSM_DEN_ATTN_OUT";
                FSM_DEN_ATTN_PROJ:     get_state_name = "FSM_DEN_ATTN_PROJ";
                FSM_DEN_LN1:           get_state_name = "FSM_DEN_LN1";
                FSM_DEN_FFN1:          get_state_name = "FSM_DEN_FFN1";
                FSM_DEN_FFN_ACT:       get_state_name = "FSM_DEN_FFN_ACT";
                FSM_DEN_FFN2:          get_state_name = "FSM_DEN_FFN2";
                FSM_DEN_LN2:           get_state_name = "FSM_DEN_LN2";
                FSM_NOISE_STEP:        get_state_name = "FSM_NOISE_STEP";
                FSM_SONAR_NORM_OUT:    get_state_name = "FSM_SONAR_NORM_OUT";
                FSM_WRITEBACK:         get_state_name = "FSM_WRITEBACK";
                FSM_DONE:              get_state_name = "FSM_DONE";
                default:               get_state_name = "UNKNOWN";
            endcase
        end
    endfunction

endmodule
