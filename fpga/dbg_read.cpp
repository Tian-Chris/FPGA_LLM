// dbg_read.cpp — Read FSM debug registers from fpga_kernel via xrt::ip
//
// Usage: ./dbg_read <xclbin>
//
// Run this AFTER the main host times out and exits (or after xbutil reset).
// It opens the CU in unmanaged mode and reads the debug registers directly.

#include <iostream>
#include <cstdint>
#include "xrt/xrt_device.h"
#include "xrt/xrt_ip.h"

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <xclbin>\n";
        return 1;
    }

    // Register offsets (match vitis_control.v)
    constexpr uint32_t REG_CTRL       = 0x00;
    constexpr uint32_t REG_BATCH_SIZE = 0x10;
    constexpr uint32_t REG_SEQ_LEN    = 0x18;
    constexpr uint32_t REG_DECODE     = 0x38;
    constexpr uint32_t REG_CACHE_LEN  = 0x40;
    constexpr uint32_t REG_DBG_STATE  = 0x48;
    constexpr uint32_t REG_DBG_LAYER  = 0x50;

    const char* fsm_names[] = {
        "IDLE", "DECODE", "LN_RUN", "QKV_MM", "QKV_FL",
        "ATT_SCORE", "ATT_SM", "ATT_SM_FL", "ATT_OUT", "ATT_OUT_FL",
        "MM_RUN", "ACT_RUN", "RES_RUN", "UF_RUN", "NEXT_STEP",
        "DONE", "OUTPUT_COPY"
    };

    try {
        std::cout << "Opening device 1 (U280)...\n";
        xrt::device device(1);

        std::cout << "Loading xclbin: " << argv[1] << "\n";
        auto uuid = device.load_xclbin(argv[1]);

        std::cout << "Opening CU in unmanaged mode...\n";
        xrt::ip ip(device, uuid, "fpga_kernel:{fpga_kernel_1}");

        // Read all interesting registers
        uint32_t ctrl      = ip.read_register(REG_CTRL);
        uint32_t batch     = ip.read_register(REG_BATCH_SIZE);
        uint32_t seq       = ip.read_register(REG_SEQ_LEN);
        uint32_t decode    = ip.read_register(REG_DECODE);
        uint32_t cache_len = ip.read_register(REG_CACHE_LEN);
        uint32_t dbg_st    = ip.read_register(REG_DBG_STATE);
        uint32_t dbg_ly    = ip.read_register(REG_DBG_LAYER);

        const char* sname = (dbg_st < 17) ? fsm_names[dbg_st] : "???";

        std::cout << "\n=== FPGA Kernel Debug Registers ===\n";
        std::cout << "  CTRL:       0x" << std::hex << ctrl << std::dec << "\n";
        std::cout << "    ap_start=" << (ctrl & 1)
                  << " ap_done=" << ((ctrl >> 1) & 1)
                  << " ap_idle=" << ((ctrl >> 2) & 1)
                  << " ap_ready=" << ((ctrl >> 3) & 1)
                  << " auto_restart=" << ((ctrl >> 7) & 1) << "\n";
        std::cout << "  batch_size: " << batch << "\n";
        std::cout << "  seq_len:    " << seq << "\n";
        std::cout << "  decode:     " << decode << "\n";
        std::cout << "  cache_len:  " << cache_len << "\n";
        std::cout << "  FSM state:  " << dbg_st << " (" << sname << ")\n";
        std::cout << "  FSM layer:  " << dbg_ly << "\n";

    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
