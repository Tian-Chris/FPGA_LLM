// host.cpp — Minimal test: write scalar args, start kernel, poll for done
#include <iostream>
#include <chrono>
#include <cstdlib>
#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "experimental/xrt_ini.h"

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <xclbin>\n";
        return 1;
    }

    const char* xclbin_path = argv[1];

    // Scalar args to write
    uint32_t batch_size  = 10;    // kernel will count 10 cycles then done
    uint32_t seq_len     = 0xBEEF; // magic value to verify args arrive correctly
    uint32_t decode_mode = 0;
    uint32_t cache_len   = 42;

    std::cout << "=== test_ctrl: ap_ctrl_hs handshake test ===\n";
    std::cout << "  batch_size=" << batch_size
              << " seq_len=0x" << std::hex << seq_len << std::dec
              << " cache_len=" << cache_len << "\n";

    // Open device
    std::cout << "Opening device...\n";
    auto device = xrt::device(1);

    std::cout << "Loading xclbin: " << xclbin_path << "\n";
    auto uuid = device.load_xclbin(xclbin_path);

    std::cout << "Creating kernel handle...\n";
    auto kernel = xrt::kernel(device, uuid, "test_kernel");

    // Run kernel with scalar args only (no buffer objects)
    std::cout << "Starting kernel...\n";
    auto t0 = std::chrono::high_resolution_clock::now();
    auto run = kernel(batch_size, seq_len, decode_mode, cache_len);

    // Poll with timeout — check every 100ms for up to 10s
    bool timed_out = true;
    for (int p = 0; p < 100; ++p) {
        auto state = run.wait(std::chrono::milliseconds(100));
        if (p < 10 || (p % 10) == 0) {
            std::cout << "  Poll[" << p << "]: state=" << static_cast<int>(state) << "\n";
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
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    if (timed_out) {
        std::cerr << "FAIL: Kernel timed out after 10s\n";
        system("xbutil examine -d 0000:3b:00.1 --report dynamic-regions 2>&1");
        return 1;
    }

    std::cout << "PASS: Kernel completed in " << ms << " ms\n";

    // Run a second time to verify re-start works
    std::cout << "\nRunning kernel a second time...\n";
    auto run2 = kernel(batch_size, seq_len, decode_mode, cache_len);
    auto state2 = run2.wait(std::chrono::milliseconds(5000));
    if (state2 == ERT_CMD_STATE_COMPLETED) {
        std::cout << "PASS: Second run completed\n";
    } else {
        std::cerr << "FAIL: Second run state=" << static_cast<int>(state2) << "\n";
        return 1;
    }

    std::cout << "\n=== All tests passed ===\n";
    return 0;
}
