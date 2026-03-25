This is an RTL transformer project targeting the Alveo U280.
FPGA server: yangzi (SSH). Build and run on server, develop locally.

├── rtl/
│   ├── activation.v        GELU via 512-entry LUT (FP16→FP16)
│   ├── agu.v               address generation (LEGACY, not used in prefetch architecture)
│   ├── bram_controller.v   needs to be replaced with vivado ip bram/uram and hbm
│   ├── defines.vh          centralized parameters (FP16/FP32, SCALE_FACTOR)
│   ├── fsm_controller.v
│   ├── hbm_prefetch.v      NEW: central HBM-to-URAM DMA engine
│   ├── host_interface.v
│   ├── layernorm.v
│   ├── fp_funcs.vh         shared FP16/FP32 combinational functions (include-guarded)
│   ├── mac_unit.v          legacy INT16 MAC (replaced by fp_mac_unit in matmul_engine)
│   ├── matmul_engine.v     32x32 engine + controller (UPDATED: URAM prefetch read)
│   ├── mem_arbiter.v       round-robin arbiter (LEGACY, not used in prefetch architecture)
│   ├── positional_embedding.v
│   ├── quant_layer.v       legacy INT16→INT8 (removed from top_level, file retained)
│   ├── residual_add.v
│   ├── sim_hbm.v            NEW: 4-port shared-memory HBM sim (replaces 4× sim_hbm_port in sim)
│   ├── sim_hbm_port.v      HBM simulation stub (legacy, still used by non-multi tests)
│   ├── debug_writer.v       NEW: single-beat AXI4 write master for FSM debug trace
│   ├── softmax.v
│   ├── tile_loader.v       LEGACY (replaced by hbm_prefetch + uram_prefetch_buf)
│   ├── tiling_engine.v     REWRITTEN: prefetch coordination + K/N chunk loops
│   ├── top_level.v         REWRITTEN: shared prefetch instances, no per-engine HBM
│   ├── uram_accum_buf.v    URAM output accumulation buffer
│   ├── uram_flush.v        URAM-to-HBM flush controller
│   ├── uram_nm_adapter.v   scalar↔URAM bridge for non-matmul units
│   ├── uram_prefetch_buf.v NEW: 1024×1024 URAM prefetch buffer
│   └── act_dma.v           scalar-to-AXI DMA bridge
├── scripts/
│   ├── verilator_small.f   Verilator flags (SIM_SMALL)
│   ├── verilator_1k.f      Verilator flags (SIM_1K)
│   └── verilator_decode.f  Verilator flags (decode mode test, SIM_1K)
├── tasks/                  contains summary todo and lessons
├── tb/
│   ├── tb_top.v            SIM_SMALL integration test
│   ├── tb_top_1k.v         SIM_1K full pipeline test
│   ├── tb_top_decode.v     Decode mode test (prefill + decode)
│   └── tb_top_matmul1k.v   Single matmul test (1024×1024)
├── verify/
│   ├── golden/             Python golden models
│   ├── test_top.py         SIM_SMALL test (MODEL_DIM=64, F_DIM=128)
│   ├── test_top_1k.py      SIM_1K test (MODEL_DIM=1024, F_DIM=4096)
│   └── test_decode_1k.py   Decode mode test
├── fpga/
│   ├── rtl/fpga_kernel.v   Vitis RTL kernel wrapper
│   ├── rtl/vitis_control.v Vitis ap_ctrl_hs AXI-Lite slave
│   ├── kernel.xml          Vitis kernel descriptor
│   ├── connectivity.cfg    HBM bank mapping
│   ├── build.tcl           Vivado packaging script
│   ├── host.cpp            GPT-2 host application
│   ├── gpt2_bpe.h          BPE tokenizer
│   └── Makefile            Build orchestration (150 MHz target)

// ============================================================================
// ARCHITECTURE: Centralized URAM Prefetch (Current)
// ============================================================================
//
// Before (per tile, per K-step):
//   HBM ──AXI──► tile_loader_wgt [64×256b BRAM] ──► matmul_engine
//   HBM ──AXI──► tile_loader_act [64×256b BRAM] ──► matmul_engine
//   (× N_ENG engines = 2N AXI read ports, constant HBM traffic)
//
// After (per matmul command):
//   HBM ──AXI──► hbm_prefetch ──► uram_prefetch_buf(wgt) [shared URAM]
//   HBM ──AXI──► hbm_prefetch ──► uram_prefetch_buf(act) [shared URAM]
//   (load once, then engines read tiles from URAM with 1-cycle latency)
//   uram_wgt_buf ──► matmul_controller ──► matmul_engine
//   uram_act_buf ──► matmul_controller ──► matmul_engine
//
// Only 2 AXI HBM read ports needed (down from 4+ per engine pair).
// Eliminates routing congestion through HBM crossbar.
// ~30× speedup by removing per-tile HBM latency.

// ============================================================================
// KEY PARAMETERS (defines.vh)
// ============================================================================

defines.vh
    SIM_SMALL (pass -DSIM_SMALL):
        MODEL_DIM=64, F_DIM=128, NUM_HEADS=2, HEAD_DIM=32,
        MAX_SEQ_LEN=32, INPUT_DIM=64, URAM_ROWS=32, URAM_COLS=128,
        PREFETCH_ROWS=128, PREFETCH_COLS=128
    SIM_1K (pass -DSIM_1K):
        MODEL_DIM=1024, F_DIM=4096, NUM_HEADS=16, HEAD_DIM=64,
        MAX_SEQ_LEN=128, URAM_ROWS=1024, URAM_COLS=4096,
        PREFETCH_ROWS=1024, PREFETCH_COLS=1024
    Hardware: NUM_ENGINES=1 (single engine for debug phase), TILE_SIZE=32,
        BUS_WIDTH=256, BUS_ELEMS=16, DATA_WIDTH=16 (FP16), ACC_WIDTH=32 (FP32)
    SCALE_FACTOR: FP16 1/√HEAD_DIM (0x3000 for HEAD_DIM=64, 0x31A8 for HEAD_DIM=32)
    HBM: HBM_ADDR_W=28, HBM_DATA_W=256
    URAM: URAM_COL_WORDS=URAM_COLS/BUS_ELEMS
    Prefetch: PREFETCH_COL_WORDS=PREFETCH_COLS/BUS_ELEMS

// ============================================================================
// NEW MODULES (URAM Prefetch Architecture)
// ============================================================================

uram_prefetch_buf.v (uram_prefetch_buf)
    Purpose: Simple dual-port URAM buffer for prefetched matrix chunks from HBM.
        Write port: bulk fill from hbm_prefetch DMA engine.
        Read port: tile extraction by matmul_controller.
        1-cycle registered read latency. (* ram_style = "ultra" *) for Vivado URAM inference.
    Parameters: ROWS (1024), COLS (1024), DATA_W (16), BUS_W (256),
        ROW_W ($clog2(ROWS)), COL_W ($clog2(COLS/(BUS_W/DATA_W)))
    Key Ports:
        Write: wr_en, wr_row[ROW_W-1:0], wr_col_word[COL_W-1:0], wr_data[BUS_W-1:0]
        Read: rd_en, rd_row[ROW_W-1:0], rd_col_word[COL_W-1:0] → rd_data[BUS_W-1:0], rd_valid
    Internal: mem[ROWS*WORDS-1:0], address = row * WORDS + col_word

hbm_prefetch.v (hbm_prefetch)
    Purpose: Central HBM-to-URAM DMA engine. Reads rectangular matrix chunk from HBM.
        Issues one AXI4 burst per row (num_col_words beats per row).
        Count fields use DIM_W (16-bit) to avoid truncation.
    Parameters: HBM_ADDR_W (28), BUS_W (256), ROW_W (10), COL_W (6),
        DIM_W (16), ID_W (4), LEN_W (8)
    Key Ports:
        Command: cmd_valid, cmd_ready, cmd_done,
            cmd_hbm_base[HBM_ADDR_W-1:0], cmd_hbm_stride[HBM_ADDR_W-1:0],
            cmd_num_rows[DIM_W-1:0], cmd_num_col_words[DIM_W-1:0]
        AXI4 Read Master: m_axi_arid/araddr/arlen/arvalid/arready,
            m_axi_rid/rdata/rresp/rlast/rvalid/rready
        URAM Write: uram_wr_en, uram_wr_row[ROW_W-1:0], uram_wr_col_word[COL_W-1:0],
            uram_wr_data[BUS_W-1:0]
    FSM: PF_IDLE → PF_AR → PF_DATA → PF_DONE

// ============================================================================
// UPDATED MODULES (URAM Prefetch Architecture)
// ============================================================================

matmul_engine.v

    matmul_engine (UPDATED: FP16×FP16→FP32 with handshake-based pipeline + bias)
    Purpose: 32x32 outer-product MAC engine using 1024 fp_mac_unit instances.
    Parameters: TILE (32), DATA_W (16), ACC_W (32), OUT_W (16), BUS_W (256), BUS_EL (16)
    Key Ports:
        Control: start, op_type[2:0], busy, done, compute_done
        Data A: a_valid, a_data[BUS_W-1:0]
        Data B: b_valid, b_data[BUS_W-1:0]
        Tile: tile_start, tile_done, tile_row[4:0], tile_col[4:0], first_tile
        Output: out_valid, out_data[BUS_W-1:0], out_row[4:0], out_col[4:0]
        Backpressure: out_stall
    Output conversion: FP32→FP16 via fp32_to_fp16_func (replaces saturate+shift)

    matmul_controller (REWRITTEN for URAM prefetch + bias)
    Purpose: Per-engine wrapper. Reads tile data from shared URAM prefetch buffers.
        No tile_loader or HBM access — data pre-loaded into URAM by hbm_prefetch.
        K-loop: reads from URAM, streams into engine, waits for compute, advances offsets.
        Output goes to URAM accumulation buffer. Bias added on last k-chunk output.
    Parameters: DATA_W (16), OUT_W (16), ACC_W (32), TILE (32), BUS_W (256), DIM_W (16),
        HBM_ADDR_W (28), URAM_ROW_W (10), URAM_COL_W (6), PF_ROW_W (10), PF_COL_W (6)
    Key Ports:
        Command: cmd_valid, cmd_op[2:0], cmd_m/k/n[DIM_W-1:0],
            cmd_a_row_off[PF_ROW_W-1:0], cmd_a_col_off[PF_COL_W-1:0],
            cmd_b_row_off[PF_ROW_W-1:0], cmd_b_col_off[PF_COL_W-1:0],
            cmd_out_row[URAM_ROW_W-1:0], cmd_out_col_word[URAM_COL_W-1:0],
            cmd_first_k_chunk, cmd_last_k_chunk, cmd_has_bias,
            cmd_acc_shift[3:0], cmd_ready, cmd_done
        Bias: bias_rd_addr[7:0] → bias_rd_data[BUS_W-1:0] (reads from tiling_engine bias_buf)
        Weight URAM Read: wgt_uram_rd_en, wgt_uram_rd_row[PF_ROW_W-1:0],
            wgt_uram_rd_col_word[PF_COL_W-1:0], wgt_uram_rd_data[BUS_W-1:0], wgt_uram_rd_valid
        Act URAM Read: act_uram_rd_en, act_uram_rd_row[PF_ROW_W-1:0],
            act_uram_rd_col_word[PF_COL_W-1:0], act_uram_rd_data[BUS_W-1:0], act_uram_rd_valid
        URAM Write: uram_wr_en/row/col_word/data, uram_wr_accept
    FSM: ST_IDLE → ST_TILE_START → ST_FEED_A → ST_FEED_B → ST_WAIT_COMPUTE → ST_NEXT_K → ST_FLUSH → ST_DONE
    (No ST_LOAD_CMD / ST_WAIT_LOAD — data already in URAM)

tiling_engine.v (tiling_engine) — REWRITTEN for URAM prefetch + bias
    Purpose: Master tile dispatcher with URAM prefetch coordination.
        Outer loops iterate K and N in chunks of PREFETCH_DIM.
        For each chunk: prefetch act+wgt buffers, dispatch all tiles, wait.
        Engines receive chunk-relative URAM offsets (no HBM addresses).
        Bias support: loads bias vector from HBM into bias_buf[256] via AXI burst
        before first k-chunk. Provides bias_rd_addr/bias_rd_data to matmul engines.
    Parameters: N_ENG (1), TILE (32), DIM_W (16), URAM_ROW_W (10), URAM_COL_W (6),
        PF_ROW_W (10), PF_COL_W (6), PREFETCH_DIM (1024)
    Key Ports:
        Command (from FSM): cmd_valid, cmd_op, cmd_m/k/n, cmd_a/b_base/stride,
            cmd_out_col_offset, cmd_has_bias, cmd_ready, cmd_done
        Bias AXI: bias_axi_araddr/arlen/arvalid/arready, bias_axi_rdata/rvalid/rready
        Prefetch Act: pf_act_cmd_valid/ready/done, pf_act_hbm_base/stride,
            pf_act_num_rows[DIM_W-1:0], pf_act_num_col_words[DIM_W-1:0]
        Prefetch Wgt: pf_wgt_cmd_valid/ready/done, pf_wgt_hbm_base/stride,
            pf_wgt_num_rows[DIM_W-1:0], pf_wgt_num_col_words[DIM_W-1:0]
        Per-engine: eng_cmd_valid, eng_cmd_op, eng_cmd_m/k/n,
            eng_cmd_a_row_off/a_col_off/b_row_off/b_col_off,
            eng_cmd_out_row/out_col_word,
            eng_cmd_first_k_chunk, eng_cmd_last_k_chunk,
            eng_cmd_ready/done
        Bias read: bias_rd_addr[7:0] → bias_rd_data[BUS_W-1:0], bias_active
    FSM: ST_IDLE → ST_SETUP → ST_BIAS_LOAD → ST_K_CHUNK_SETUP → ST_N_CHUNK_SETUP →
         ST_PREFETCH_CMD → ST_WAIT_PREFETCH → ST_DISPATCH → ST_WAIT →
         ST_NEXT_N_CHUNK → ST_NEXT_K_CHUNK → ST_DONE
    Key: pf_act_done_r/pf_wgt_done_r latch done pulses (may arrive on different cycles)

top_level.v (diffusion_transformer_top) — REWRITTEN for prefetch
    Architecture:
        Shared prefetch: hbm_prefetch(wgt) + uram_prefetch_buf(wgt) +
                        hbm_prefetch(act) + uram_prefetch_buf(act)
        Per engine (N_ENG=1): matmul_controller (reads from prefetch URAMs)
        Shared: tiling_engine, uram_accum_buf, uram_flush, uram_nm_adapter, act_dma
        Control: host_interface/vitis_control + fsm_controller
    Key changes from old architecture:
        - No tile_loader instances (replaced by shared hbm_prefetch)
        - No per-engine sim_hbm_port instances
        - 2× uram_prefetch_buf (wgt + act) outside generate block
        - 2× hbm_prefetch (wgt + act) outside generate block
        - 1× sim_hbm (4-port shared memory) replaces 4× sim_hbm_port [sim only]
        - debug_writer instance, flush port mux (dbg_active selects debug vs uram_flush)
        - FPGA_TARGET: wgt0→pf_wgt, act0→pf_act, other engine ports tied off
    Parameters: SIM_HBM_DEPTH (65536→2097152 for multi), SINGLE_MATMUL (0), HBM_RD_LATENCY (2),
        URAM_RD_LATENCY (1), ID_W_PARAM (4)

// ============================================================================
// UNCHANGED MODULES
// ============================================================================

mac_unit.v — Legacy INT16 MAC (retained in RTL_ALL, replaced by fp_mac_unit in matmul_engine)
fp_mac_unit.v — FP16×FP16→FP32 MAC (5-stage pipeline: fp16_mult + fp32_add)
activation.v — GELU via 512-entry LUT. Combinational LUT lookup from mem_rd_data (no pipeline regs). gelu_lut.hex loaded at init.
layernorm.v — FP16/FP32 LN (mean, variance, Quake rsqrt, normalize). PARAM_W=16 (FP16 gamma/beta). Interleaved param reads: gamma[i] at addr 2*i, beta[i] at addr 2*i+1.
softmax.v — FP16 softmax: scale_factor[15:0] (FP16 multiplier), 256-entry exp LUT, Newton-Raphson reciprocal. Causal masking.
residual_add.v — FP16 element-wise addition (fp16_add_comb from fp_funcs.vh)
quant_layer.v — Legacy INT16→INT8 (removed from top_level, file retained)
uram_accum_buf.v — URAM output accumulation buffer (write serialization arbiter, clearing_out output, eng_wr_accum for k-chunk accumulation)
uram_flush.v — URAM-to-HBM flush controller (AXI4 write bursts)
uram_nm_adapter.v — Scalar ↔ URAM 256-bit bridge (SCALAR_AW=20 for wide addressing)
act_dma.v — Scalar-to-AXI DMA bridge for LN params
sim_hbm_port.v — HBM simulation stub (AXI4 read/write backed by reg array)
sim_hbm.v — NEW: 4-port shared-memory HBM sim model. Single reg array backing 4 independent AXI4 port FSMs (P0=pf_wgt RO, P1=pf_act RO, P2=flush WO, P3=dma RW). Configurable RD_LATENCY_CYCLES. Replaces 4× sim_hbm_port in top_level `ifndef FPGA_TARGET`.
debug_writer.v — NEW: Minimal single-beat AXI4 write master (S_IDLE→S_AW→S_B→S_IDLE). Inputs: write_valid, write_addr, write_data[255:0]. Outputs: write_done, write_busy. Used by FSM to write 256-bit debug records to HBM.
fsm_controller.v — Step-table FSM (19 states incl S_STEP_DBG_FLUSH, GPT-2 pre-norm program, NM_ADDR_W=20 for wide nm_addr_offset, S_ACT_RUN processes row-by-row like S_LN_RUN, eng_cmd_first_k_chunk for k-chunk accumulation, per-layer KV cache via kv_base input + layer_kv_base wire). sm_scale_factor[15:0] (FP16, replaces sm_scale_shift[3:0]). num_layers input (runtime layer count), debug_base input, dbg_wr_valid/addr/data outputs. Bias support: mm_cmd_has_bias, mm_cmd_bias_base[HBM_ADDR_W-1:0], mm_cmd_bias_words[DIM_W-1:0] outputs per matmul step. Bias offsets: LAYER_BIAS_QKV_OFFSET, LAYER_BIAS_PROJ_OFFSET, LAYER_BIAS_FFN1_OFFSET, LAYER_BIAS_FFN2_OFFSET. STEP_DEBUG: S_STEP_DBG_FLUSH state flushes full URAM to output_base + running offset after every non-END step (compile-time ifdef).
host_interface.v — AXI-Lite slave for host control (regs: 0x00-0x2C incl kv_base at 0x24, num_layers at 0x28, debug_base at 0x2C)

// ============================================================================
// FPGA DEPLOYMENT (fpga/)
// ============================================================================

fpga/rtl/vitis_control.v — Vitis ap_ctrl_hs AXI-Lite slave (scalar regs: batch_size, seq_len, decode_mode, cache_len, kv_base, num_layers, debug_base; pointer regs: weight_ptr, act_ptr, output_ptr)
fpga/rtl/fpga_kernel.v — Vitis RTL kernel wrapper (port renaming, address conversion)
fpga/kernel.xml — Vitis kernel descriptor (6 m_axi ports, 13 args incl kv_base at 0x58, num_layers at 0x60, debug_base at 0x68)
fpga/connectivity.cfg — HBM bank mapping (unchanged, tied-off ports harmless)
fpga/build.tcl — Vivado packaging script
fpga/host.cpp — GPT-2 host application (BPE tokenizer, embedding, FPGA invocation)
fpga/Makefile — Build targets (150 MHz kernel_frequency)

// ============================================================================
// FPGA MANAGEMENT COMMANDS (Server: yangzi, U280 BDF: 0000:3b:00.1)
// ============================================================================
//
// List all FPGAs:
//   xbutil examine
//
// Full status report (ERT state, memory, CU idle/busy):
//   xbutil examine -d 0000:3b:00.1 -r all
//
// Check loaded xclbin and compute unit status:
//   xbutil examine -d 0000:3b:00.1 -r dynamic-regions
//
// Reset stuck FPGA:
//   xbutil reset -d 0000:3b:00.1
//
// Device indices: U200=0 (0000:d9:00.1), U280=1 (0000:3b:00.1)
// Note: host.cpp uses xrt::device(1) for U280, but xbutil needs BDF format
