This is an RTL transformer project targeting the Alveo U280.
FPGA server: yangzi (SSH). Build and run on server, develop locally.

├── rtl/
│   ├── activation.v        simple relu
│   ├── agu.v               address generation (LEGACY, not used in prefetch architecture)
│   ├── bram_controller.v   needs to be replaced with vivado ip bram/uram and hbm
│   ├── defines.vh          centralized parameters (UPDATED: prefetch buffers, fixed SIM_SMALL dims)
│   ├── fsm_controller.v
│   ├── hbm_prefetch.v      NEW: central HBM-to-URAM DMA engine
│   ├── host_interface.v
│   ├── layernorm.v
│   ├── mac_unit.v          single pipelined MAC for DSP48E2 mapping
│   ├── matmul_engine.v     32x32 engine + controller (UPDATED: URAM prefetch read)
│   ├── mem_arbiter.v       round-robin arbiter (LEGACY, not used in prefetch architecture)
│   ├── positional_embedding.v
│   ├── quant_layer.v
│   ├── residual_add.v
│   ├── sim_hbm_port.v      HBM simulation stub
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
        BUS_WIDTH=256, BUS_ELEMS=16, DATA_WIDTH=16, ACC_WIDTH=32
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

    matmul_engine (UPDATED: acc_shift port)
    Purpose: 32x32 outer-product MAC engine using 1024 mac_unit instances.
    Parameters: TILE (32), DATA_W (16), ACC_W (32), OUT_W (16), BUS_W (256), BUS_EL (16)
    Key Ports:
        Control: start, op_type[2:0], busy, done, compute_done
        Data A: a_valid, a_data[BUS_W-1:0]
        Data B: b_valid, b_data[BUS_W-1:0]
        Tile: tile_start, tile_done, tile_row[4:0], tile_col[4:0], first_tile
        Output: out_valid, out_data[BUS_W-1:0], out_row[4:0], out_col[4:0]
        Backpressure: out_stall
        Shift: acc_shift[3:0] — arithmetic right-shift applied before INT32→INT16 saturation

    matmul_controller (REWRITTEN for URAM prefetch)
    Purpose: Per-engine wrapper. Reads tile data from shared URAM prefetch buffers.
        No tile_loader or HBM access — data pre-loaded into URAM by hbm_prefetch.
        K-loop: reads from URAM, streams into engine, waits for compute, advances offsets.
        Output goes to URAM accumulation buffer.
    Parameters: DATA_W (16), OUT_W (16), ACC_W (32), TILE (32), BUS_W (256), DIM_W (16),
        HBM_ADDR_W (28), URAM_ROW_W (10), URAM_COL_W (6), PF_ROW_W (10), PF_COL_W (6)
    Key Ports:
        Command: cmd_valid, cmd_op[2:0], cmd_m/k/n[DIM_W-1:0],
            cmd_a_row_off[PF_ROW_W-1:0], cmd_a_col_off[PF_COL_W-1:0],
            cmd_b_row_off[PF_ROW_W-1:0], cmd_b_col_off[PF_COL_W-1:0],
            cmd_out_row[URAM_ROW_W-1:0], cmd_out_col_word[URAM_COL_W-1:0],
            cmd_acc_shift[3:0], cmd_ready, cmd_done
        Weight URAM Read: wgt_uram_rd_en, wgt_uram_rd_row[PF_ROW_W-1:0],
            wgt_uram_rd_col_word[PF_COL_W-1:0], wgt_uram_rd_data[BUS_W-1:0], wgt_uram_rd_valid
        Act URAM Read: act_uram_rd_en, act_uram_rd_row[PF_ROW_W-1:0],
            act_uram_rd_col_word[PF_COL_W-1:0], act_uram_rd_data[BUS_W-1:0], act_uram_rd_valid
        URAM Write: uram_wr_en/row/col_word/data, uram_wr_accept
    FSM: ST_IDLE → ST_TILE_START → ST_FEED_A → ST_FEED_B → ST_WAIT_COMPUTE → ST_NEXT_K → ST_FLUSH → ST_DONE
    (No ST_LOAD_CMD / ST_WAIT_LOAD — data already in URAM)

tiling_engine.v (tiling_engine) — REWRITTEN for URAM prefetch
    Purpose: Master tile dispatcher with URAM prefetch coordination.
        Outer loops iterate K and N in chunks of PREFETCH_DIM.
        For each chunk: prefetch act+wgt buffers, dispatch all tiles, wait.
        Engines receive chunk-relative URAM offsets (no HBM addresses).
    Parameters: N_ENG (1), TILE (32), DIM_W (16), URAM_ROW_W (10), URAM_COL_W (6),
        PF_ROW_W (10), PF_COL_W (6), PREFETCH_DIM (1024)
    Key Ports:
        Command (from FSM): cmd_valid, cmd_op, cmd_m/k/n, cmd_a/b_base/stride,
            cmd_out_col_offset, cmd_acc_shift[3:0], cmd_ready, cmd_done
        Prefetch Act: pf_act_cmd_valid/ready/done, pf_act_hbm_base/stride,
            pf_act_num_rows[DIM_W-1:0], pf_act_num_col_words[DIM_W-1:0]
        Prefetch Wgt: pf_wgt_cmd_valid/ready/done, pf_wgt_hbm_base/stride,
            pf_wgt_num_rows[DIM_W-1:0], pf_wgt_num_col_words[DIM_W-1:0]
        Per-engine: eng_cmd_valid, eng_cmd_op, eng_cmd_m/k/n,
            eng_cmd_a_row_off/a_col_off/b_row_off/b_col_off,
            eng_cmd_out_row/out_col_word, eng_cmd_acc_shift[4*N_ENG-1:0],
            eng_cmd_ready/done
    FSM: ST_IDLE → ST_SETUP → ST_K_CHUNK_SETUP → ST_N_CHUNK_SETUP →
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
        - 2× sim_hbm_port for prefetch (u_hbm_pf_wgt, u_hbm_pf_act) [sim only]
        - FPGA_TARGET: wgt0→pf_wgt, act0→pf_act, other engine ports tied off
    Parameters: SIM_HBM_DEPTH (65536), SINGLE_MATMUL (0), HBM_RD_LATENCY (2),
        URAM_RD_LATENCY (1), ID_W_PARAM (4)

// ============================================================================
// UNCHANGED MODULES
// ============================================================================

mac_unit.v — Single pipelined MAC (3-stage: reg inputs, multiply, accumulate)
activation.v — ReLU
layernorm.v — 3-pass LN (mean, variance, normalize) with BRAM + pipeline
softmax.v — 3-pass softmax with causal masking + attention scaling
residual_add.v — Element-wise saturating residual addition
quant_layer.v — Dynamic symmetric INT16→INT8 quantization
uram_accum_buf.v — URAM output accumulation buffer (write serialization arbiter, clearing_out output, eng_wr_accum for k-chunk accumulation)
uram_flush.v — URAM-to-HBM flush controller (AXI4 write bursts)
uram_nm_adapter.v — Scalar ↔ URAM 256-bit bridge (SCALAR_AW=20 for wide addressing)
act_dma.v — Scalar-to-AXI DMA bridge for LN params
sim_hbm_port.v — HBM simulation stub (AXI4 read/write backed by reg array)
fsm_controller.v — Step-table FSM (18 states incl S_CLEAR_WAIT, GPT-2 pre-norm program, NM_ADDR_W=20 for wide nm_addr_offset, S_ACT_RUN processes row-by-row like S_LN_RUN, eng_cmd_first_k_chunk for k-chunk accumulation, per-layer KV cache via kv_base input + layer_kv_base wire)
host_interface.v — AXI-Lite slave for host control (regs: 0x00-0x24 incl kv_base at 0x24)

// ============================================================================
// FPGA DEPLOYMENT (fpga/)
// ============================================================================

fpga/rtl/vitis_control.v — Vitis ap_ctrl_hs AXI-Lite slave
fpga/rtl/fpga_kernel.v — Vitis RTL kernel wrapper (port renaming, address conversion)
fpga/kernel.xml — Vitis kernel descriptor (6 m_axi ports, 11 args incl kv_ptr at 0x58)
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
