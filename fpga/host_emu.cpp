// =============================================================================
// host_emu.cpp — Minimal hw_emu test host for SIM_SMALL FPGA kernel
// =============================================================================
//
// Self-contained: no tokenizer, no data files, no embeddings.
// Fills buffers with small non-zero INT16 values and runs the kernel.
//
// Usage: ./host_emu <xclbin>
//
// SIM_SMALL dims (from defines.vh):
//   MODEL_DIM=64, F_DIM=128, NUM_HEADS=2, MAX_SEQ_LEN=32, NUM_ENC_LAYERS=1
//   BUS_ELEMS=16, WORD_BYTES=32, MODEL_STRIDE=4
// =============================================================================

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <thread>

#include "xrt/xrt_bo.h"
#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"

// SIM_SMALL constants (must match defines.vh SIM_SMALL)
static constexpr int MODEL_DIM    = 32;
static constexpr int BUS_ELEMS    = 16;
static constexpr int WORD_BYTES   = 32;
static constexpr int MODEL_STRIDE = MODEL_DIM / BUS_ELEMS;  // 2

// Buffer sizes (generous for small dims)
static constexpr size_t WEIGHT_BUF_SIZE = 1 * 1024 * 1024;   // 1 MB
static constexpr size_t ACT_BUF_SIZE    = 256 * 1024;         // 256 KB
static constexpr size_t OUTPUT_BUF_SIZE = 64 * 1024;          // 64 KB

// Test parameters
static constexpr int SEQ_LEN   = 1;
static constexpr int BATCH_SIZE = 1;

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <xclbin>\n";
        return 1;
    }
    const char* xclbin_path = argv[1];

    // -----------------------------------------------------------------
    // Open device and load xclbin
    // -----------------------------------------------------------------
    std::cout << "Opening device 0...\n";
    xrt::device device(0);

    std::cout << "Loading xclbin: " << xclbin_path << "\n";
    auto uuid = device.load_xclbin(xclbin_path);

    std::cout << "Creating kernel handle...\n";
    xrt::kernel kernel(device, uuid, "fpga_kernel");

    // -----------------------------------------------------------------
    // Allocate device buffers
    // -----------------------------------------------------------------
    std::cout << "Allocating buffers (wgt=" << WEIGHT_BUF_SIZE / 1024 << "KB"
              << " act=" << ACT_BUF_SIZE / 1024 << "KB"
              << " out=" << OUTPUT_BUF_SIZE / 1024 << "KB)...\n";

    xrt::bo bo_weight(device, WEIGHT_BUF_SIZE, kernel.group_id(2));
    xrt::bo bo_act   (device, ACT_BUF_SIZE,    kernel.group_id(4));
    xrt::bo bo_output(device, OUTPUT_BUF_SIZE,  kernel.group_id(7));

    auto weight_map = bo_weight.map<int16_t*>();
    auto act_map    = bo_act.map<int16_t*>();
    auto output_map = bo_output.map<int16_t*>();

    // -----------------------------------------------------------------
    // Fill weight buffer with small non-zero values
    // -----------------------------------------------------------------
    std::cout << "Filling weight buffer...\n";
    size_t wgt_elems = WEIGHT_BUF_SIZE / sizeof(int16_t);
    for (size_t i = 0; i < wgt_elems; ++i) {
        // Small values: cycle through 1..8 to avoid overflow in matmul
        weight_map[i] = static_cast<int16_t>((i % 8) + 1);
    }

    // -----------------------------------------------------------------
    // Fill activation buffer: SEQ_LEN rows x MODEL_DIM elements
    // -----------------------------------------------------------------
    std::cout << "Filling activation buffer (" << SEQ_LEN << " x " << MODEL_DIM << ")...\n";
    std::memset(act_map, 0, ACT_BUF_SIZE);

    for (int s = 0; s < SEQ_LEN; ++s) {
        for (int d = 0; d < MODEL_DIM; ++d) {
            int word_in_row  = d / BUS_ELEMS;
            int elem_in_word = d % BUS_ELEMS;
            size_t idx = static_cast<size_t>(
                (s * MODEL_STRIDE + word_in_row) * (WORD_BYTES / sizeof(int16_t))
                + elem_in_word);
            // Small non-zero values to avoid LN divide-by-zero
            act_map[idx] = static_cast<int16_t>((s * MODEL_DIM + d) % 7 + 1);
        }
    }

    // Clear output
    std::memset(output_map, 0, OUTPUT_BUF_SIZE);

    // -----------------------------------------------------------------
    // Sync all buffers to device
    // -----------------------------------------------------------------
    std::cout << "Syncing buffers to device...\n";
    bo_weight.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    bo_act.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    bo_output.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    // -----------------------------------------------------------------
    // Run kernel (prefill mode)
    // -----------------------------------------------------------------
    uint32_t batch_size  = BATCH_SIZE;
    uint32_t seq_len     = SEQ_LEN;
    uint32_t decode_mode = 0;
    uint32_t cache_len   = 0;

    std::cout << "\n=== Running kernel: batch=" << batch_size
              << " seq=" << seq_len
              << " decode=" << decode_mode << " ===\n";

    std::cout << "  wgt_addr=0x" << std::hex << bo_weight.address()
              << " act_addr=0x" << bo_act.address()
              << " out_addr=0x" << bo_output.address() << std::dec << "\n";

    auto t0 = std::chrono::high_resolution_clock::now();

    std::cout << "Launching kernel..." << std::flush;
    auto run = kernel(batch_size, seq_len,
                      bo_weight, bo_weight,       // args 2-3: hbm00+01
                      bo_act, bo_act, bo_act,     // args 4-6: hbm06+07+12(flush)
                      bo_output,                  // arg 7: hbm13(dma/output)
                      decode_mode, cache_len);    // args 8-9
    std::cout << " launched. Polling...\n" << std::flush;

    // -----------------------------------------------------------------
    // Poll with 120s timeout (hw_emu is slow)
    // -----------------------------------------------------------------
    bool timed_out = true;
    int poll_count = 120000;  // 120000 x 1ms = 120s

    for (int p = 0; p < poll_count; ++p) {
        auto state = run.wait(std::chrono::milliseconds(1));

        // Print status periodically (~every 1s, plus first 10)
        if (p < 10 || (p % 1000) == 0) {
            auto elapsed = std::chrono::duration<double>(
                std::chrono::high_resolution_clock::now() - t0).count();
            uint32_t fsm_state = kernel.read_register(0x48);
            uint32_t fsm_layer = kernel.read_register(0x50);
            std::cout << "  Poll[" << p << "] " << elapsed << "s: ert="
                      << static_cast<int>(state)
                      << " fsm=" << fsm_state
                      << " layer=" << fsm_layer << std::endl;
        }

        if (state == ERT_CMD_STATE_COMPLETED) {
            timed_out = false;
            break;
        }
        if (state == ERT_CMD_STATE_ERROR || state == ERT_CMD_STATE_ABORT) {
            std::cerr << "ERROR: Kernel error state: " << static_cast<int>(state) << "\n";
            return 1;
        }
    }

    auto t1 = std::chrono::high_resolution_clock::now();
    double elapsed_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    if (timed_out) {
        std::cerr << "\nFAIL: Kernel timed out after " << elapsed_ms / 1000.0 << "s\n";
        std::cerr << "  FSM is stuck — add $display debug to XSim for diagnosis.\n";
        return 1;
    }

    std::cout << "\n=== Kernel completed in " << elapsed_ms << " ms ===\n";

    // -----------------------------------------------------------------
    // Read back output
    // -----------------------------------------------------------------
    bo_output.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

    std::cout << "Output (first " << MODEL_DIM << " int16 values, row 0):\n  ";
    for (int d = 0; d < MODEL_DIM && d < 32; ++d) {
        int word_in_row  = d / BUS_ELEMS;
        int elem_in_word = d % BUS_ELEMS;
        size_t idx = static_cast<size_t>(
            word_in_row * (WORD_BYTES / sizeof(int16_t)) + elem_in_word);
        std::cout << output_map[idx] << " ";
    }
    std::cout << "...\n";

    std::cout << "\nPASS: hw_emu SIM_SMALL kernel completed successfully.\n";
    return 0;
}
