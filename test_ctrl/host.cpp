// host.cpp — Test HBM read/write: kernel reads 1 word, inverts bits, writes back
//
// Usage:
//   ./host <xclbin>              — single HBM R/W test
//   ./host <xclbin> stress <N>   — run N iterations in a loop (overnight test)
//
#include <iostream>
#include <chrono>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"

static constexpr size_t BUF_SIZE = 4096;  // 4 KB (minimum page)
static constexpr int WORD_BYTES = 32;     // 256 bits = 32 bytes

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <xclbin> [stress <iterations>]\n";
        return 1;
    }

    const char* xclbin_path = argv[1];
    bool stress_mode = (argc > 2 && std::string(argv[2]) == "stress");
    int iterations = (argc > 3) ? std::atoi(argv[3]) : 1000;
    if (!stress_mode) iterations = 1;

    std::cout << "=== test_ctrl: HBM read/write test ===\n";
    if (stress_mode)
        std::cout << "  Stress mode: " << iterations << " iterations\n";

    // Open device
    std::cout << "Opening device...\n";
    auto device = xrt::device(1);

    std::cout << "Loading xclbin: " << xclbin_path << "\n";
    auto uuid = device.load_xclbin(xclbin_path);

    std::cout << "Creating kernel handle...\n";
    auto kernel = xrt::kernel(device, uuid, "test_kernel");

    // Allocate HBM buffer — group_id(2) matches arg id=2 (output_ptr)
    std::cout << "Allocating HBM buffer (" << BUF_SIZE << " bytes)...\n";
    xrt::bo bo_buf(device, BUF_SIZE, kernel.group_id(2));
    auto buf = bo_buf.map<uint32_t*>();

    int pass_count = 0;
    int fail_count = 0;
    auto t_start = std::chrono::high_resolution_clock::now();

    for (int iter = 0; iter < iterations; ++iter) {
        // Fill buffer with known pattern (changes each iteration)
        uint32_t seed = 0xDEADBEEF ^ static_cast<uint32_t>(iter);
        for (int i = 0; i < WORD_BYTES / 4; ++i) {
            buf[i] = seed + static_cast<uint32_t>(i);
        }

        // Save expected result (bitwise NOT of first 256-bit word)
        uint32_t expected[WORD_BYTES / 4];
        for (int i = 0; i < WORD_BYTES / 4; ++i) {
            expected[i] = ~buf[i];
        }

        // Sync to device
        bo_buf.sync(XCL_BO_SYNC_BO_TO_DEVICE);

        // Run kernel: scalar args are unused, just need the buffer pointer
        auto run = kernel(0, 0, bo_buf, 0, 0);

        // Poll for completion
        bool timed_out = true;
        for (int p = 0; p < 100; ++p) {
            auto state = run.wait(std::chrono::milliseconds(100));
            if (stress_mode && p > 0 && (p % 10) == 0) {
                std::cout << "  [iter=" << iter << "] Poll[" << p
                          << "]: state=" << static_cast<int>(state) << "\n";
            }
            if (state == ERT_CMD_STATE_COMPLETED) {
                timed_out = false;
                break;
            }
            if (state == ERT_CMD_STATE_ERROR || state == ERT_CMD_STATE_ABORT) {
                std::cerr << "ERROR: Kernel error state " << static_cast<int>(state)
                          << " at iter=" << iter << "\n";
                return 1;
            }
        }

        if (timed_out) {
            std::cerr << "FAIL: Kernel timed out at iter=" << iter << "\n";
            return 1;
        }

        // Sync back from device
        bo_buf.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

        // Verify
        bool ok = true;
        for (int i = 0; i < WORD_BYTES / 4; ++i) {
            if (buf[i] != expected[i]) {
                ok = false;
                if (!stress_mode || fail_count < 5) {
                    std::cerr << "  MISMATCH [iter=" << iter << " word=" << i
                              << "]: got=0x" << std::hex << buf[i]
                              << " expected=0x" << expected[i] << std::dec << "\n";
                }
            }
        }

        if (ok) {
            pass_count++;
            if (!stress_mode) {
                std::cout << "PASS: HBM read/write verified (data inverted correctly)\n";
                // Print first few words for confirmation
                std::cout << "  Input:  0x" << std::hex << (seed) << "\n";
                std::cout << "  Output: 0x" << buf[0] << std::dec << "\n";
            }
        } else {
            fail_count++;
        }

        // Progress in stress mode
        if (stress_mode && ((iter + 1) % 100 == 0 || iter == iterations - 1)) {
            auto elapsed = std::chrono::duration<double>(
                std::chrono::high_resolution_clock::now() - t_start).count();
            std::cout << "  Progress: " << (iter + 1) << "/" << iterations
                      << " pass=" << pass_count << " fail=" << fail_count
                      << " elapsed=" << elapsed << "s\n";
        }
    }

    if (stress_mode) {
        auto total = std::chrono::duration<double>(
            std::chrono::high_resolution_clock::now() - t_start).count();
        std::cout << "\n=== Stress test complete ===\n";
        std::cout << "  Iterations: " << iterations << "\n";
        std::cout << "  Pass: " << pass_count << " Fail: " << fail_count << "\n";
        std::cout << "  Total time: " << total << "s\n";
    }

    return (fail_count > 0) ? 1 : 0;
}
