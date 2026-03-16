# =============================================================================
# test_ctrl/Makefile — Minimal Vitis kernel to test ap_ctrl_hs handshake
# =============================================================================
# Targets:
#   make package   — Vivado: package RTL → .xo
#   make link-emu  — v++: link → hw_emu .xclbin  (~5 min)
#   make link-hw   — v++: link → hw .xclbin       (~30 min, no HBM)
#   make host      — compile host app
#   make run-emu   — run in hw_emu
#   make run-hw    — run on real FPGA
# =============================================================================

PLATFORM ?= xilinx_u280_gen3x16_xdma_1_202211_1
PLATFORM_PATH ?= /opt/xilinx/platforms/$(PLATFORM)/$(PLATFORM).xpfm

VIVADO_SETUP ?= /tools/Xilinx/Vivado/2022.2/settings64.sh
SHELL        := /bin/bash
VPP          := source $(VIVADO_SETUP) && v++
VIVADO       := source $(VIVADO_SETUP) && vivado

KERNEL   := test_kernel
XO_FILE  := $(KERNEL).xo
CFG_FILE := connectivity.cfg

TARGET   ?= hw_emu
XCLBIN   := $(KERNEL)_$(TARGET).xclbin

HOST_SRC := host.cpp
HOST_EXE := host
XRT_DIR  := /opt/xilinx/xrt

HOST_CXX    := g++
HOST_CFLAGS := -std=c++17 -O2 -I$(XRT_DIR)/include -fmessage-length=0
HOST_LFLAGS := -L$(XRT_DIR)/lib -lOpenCL -lxrt_coreutil -pthread

# =============================================================================
# Package: RTL → .xo
# =============================================================================
.PHONY: package
package: $(XO_FILE)

$(XO_FILE): build.tcl kernel.xml test_kernel.v vitis_control.v
	$(VIVADO) -mode batch -source build.tcl
	@echo "=== Package complete: $(XO_FILE) ==="

# =============================================================================
# Link: .xo → .xclbin
# =============================================================================
.PHONY: link-emu link-hw

link-emu: TARGET := hw_emu
link-emu: $(KERNEL)_hw_emu.xclbin

link-hw: TARGET := hw
link-hw: $(KERNEL)_hw.xclbin

$(KERNEL)_%.xclbin: $(XO_FILE) $(CFG_FILE)
	$(VPP) -t $* --platform $(PLATFORM_PATH) \
		--link $(XO_FILE) \
		--config $(CFG_FILE) \
		--kernel_frequency 200 \
		-o $@
	@echo "=== Link complete: $@ ==="

# =============================================================================
# Host
# =============================================================================
.PHONY: host
host: $(HOST_EXE)

$(HOST_EXE): $(HOST_SRC)
	$(HOST_CXX) $(HOST_CFLAGS) -o $@ $< $(HOST_LFLAGS)
	@echo "=== Host build complete ==="

# =============================================================================
# Run
# =============================================================================
.PHONY: run-emu run-hw

emconfig.json:
	source $(VIVADO_SETUP) && emconfigutil --platform $(PLATFORM_PATH)

run-emu: $(HOST_EXE) $(KERNEL)_hw_emu.xclbin emconfig.json
	source $(VIVADO_SETUP) && source $(XRT_DIR)/setup.sh && \
		XCL_EMULATION_MODE=hw_emu ./$(HOST_EXE) $(KERNEL)_hw_emu.xclbin

run-hw: $(HOST_EXE) $(KERNEL)_hw.xclbin
	source $(XRT_DIR)/setup.sh && ./$(HOST_EXE) $(KERNEL)_hw.xclbin

# Full test: package + link hw_emu + run
.PHONY: test
test:
	$(MAKE) package && $(MAKE) link-emu && $(MAKE) host && $(MAKE) run-emu

# =============================================================================
# Clean
# =============================================================================
.PHONY: clean
clean:
	rm -rf $(HOST_EXE) *.xo *.xclbin *.log *.jou
	rm -rf xo_pkg tmp_prj _x .Xil .run emconfig.json
	rm -rf *.ltx *.wdb *.wcfg
