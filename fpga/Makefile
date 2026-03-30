# =============================================================================
# fpga/Makefile — Vitis RTL Kernel Build for Alveo U280
# =============================================================================
#
# Targets:
#   make package       — Vivado: package RTL → .xo
#   make package-debug — Vivado: package RTL → .xo (with STEP_DEBUG)
#   make link-prod     — v++: link .xo → .xclbin (hw, 100MHz, spread)
#   make link-debug    — v++: link debug .xo → .xclbin (hw, 100MHz, spread)
#   make link-hw-ila   — v++: link .xo → .xclbin (hw, 100MHz, spread + ILA)
#   make host          — g++: compile XRT host application
#   make link-emu      — v++: link .xo → .xclbin (hw_emu)
#   make run-emu       — Run hardware emulation
#   make run-hw        — Run on real FPGA
#   make clean         — Remove build artifacts
# =============================================================================

# Platform
PLATFORM ?= xilinx_u280_gen3x16_xdma_1_202211_1
PLATFORM_PATH ?= /opt/xilinx/platforms/$(PLATFORM)/$(PLATFORM).xpfm

# Vitis / Vivado — source settings if not already on PATH
VIVADO_SETUP ?= /tools/Xilinx/Vivado/2022.2/settings64.sh
SHELL        := /bin/bash
VPP          := source $(VIVADO_SETUP) && v++
VIVADO       := source $(VIVADO_SETUP) && vivado

# Kernel
KERNEL   := fpga_kernel
XO_FILE  := $(KERNEL).xo
CFG_FILE := connectivity.cfg

# Host
HOST_SRC := host.cpp
HOST_EXE := host
XRT_DIR  := /opt/xilinx/xrt

# Compiler flags
HOST_CXX    := g++
HOST_CFLAGS := -std=c++17 -O2 -I$(XRT_DIR)/include -fmessage-length=0
HOST_LFLAGS := -L$(XRT_DIR)/lib -lOpenCL -lxrt_coreutil -pthread

# Common v++ link flags
FREQ        ?= 250
VPP_LINK    := $(VPP) -t hw --platform $(PLATFORM_PATH) --config $(CFG_FILE) \
		--kernel_frequency $(FREQ)
# Full directives for production (high-frequency) builds
SPREAD_OPTS := --vivado.prop run.impl_1.STEPS.PLACE_DESIGN.ARGS.DIRECTIVE=AltSpreadLogic_high \
		--vivado.prop run.impl_1.STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE=AlternateCLBRouting \
		--vivado.prop run.impl_1.STEPS.OPT_DESIGN.ARGS.DIRECTIVE=ExploreWithRemap

# Minimal directives for fast iteration builds
FAST_OPTS   := --vivado.prop run.impl_1.STEPS.PLACE_DESIGN.ARGS.DIRECTIVE=AltSpreadLogic_high

# Debug .xo (STEP_DEBUG baked in during package)
DEBUG_XO := $(KERNEL)_debug.xo

# RTL deps shared by all package targets
RTL_DEPS := build.tcl kernel.xml rtl/fpga_kernel.v rtl/vitis_control.v $(wildcard ../rtl/*.v ../rtl/*.vh)

# =============================================================================
# Package: RTL → .xo (Vivado batch)
# =============================================================================
.PHONY: package package-debug

package: $(XO_FILE)

$(XO_FILE): $(RTL_DEPS)
	cd .. && $(VIVADO) -mode batch -source fpga/build.tcl -tclargs
	@echo "=== Package complete: $(XO_FILE) ==="

package-debug: $(DEBUG_XO)

$(DEBUG_XO): $(RTL_DEPS)
	cd .. && export STEP_DEBUG=1 && $(VIVADO) -mode batch -source fpga/build.tcl -tclargs
	mv $(XO_FILE) $(DEBUG_XO)
	@echo "=== Package-debug complete: $(DEBUG_XO) ==="

# =============================================================================
# Link: .xo → .xclbin (v++)
# =============================================================================
.PHONY: link-prod link-fast link-chipscope link-debug link-hw-ila link-emu

link-prod: $(XO_FILE) $(CFG_FILE)
	$(VPP_LINK) --link $(XO_FILE) $(SPREAD_OPTS) -o $(KERNEL)_hw.xclbin
	@echo "=== Link-prod complete: $(KERNEL)_hw.xclbin ==="

link-fast: $(XO_FILE) $(CFG_FILE)
	$(VPP) -t hw --platform $(PLATFORM_PATH) --config $(CFG_FILE) \
		--kernel_frequency 50 --link $(XO_FILE) $(FAST_OPTS) -o $(KERNEL)_fast_hw.xclbin
	@echo "=== Link-fast complete: $(KERNEL)_fast_hw.xclbin ==="

link-chipscope: $(XO_FILE) $(CFG_FILE)
	$(VPP_LINK) --dk chipscope:fpga_kernel_1 --link $(XO_FILE) $(SPREAD_OPTS) -o $(KERNEL)_cs_hw.xclbin
	@echo "=== Link-chipscope complete: $(KERNEL)_cs_hw.xclbin ==="

link-debug: $(DEBUG_XO) $(CFG_FILE)
	$(VPP_LINK) --link $(DEBUG_XO) $(SPREAD_OPTS) -o $(KERNEL)_debug_hw.xclbin
	@echo "=== Link-debug complete (STEP_DEBUG): $(KERNEL)_debug_hw.xclbin ==="

link-hw-ila: $(XO_FILE) $(CFG_FILE)
	$(VPP_LINK) --link $(XO_FILE) $(SPREAD_OPTS) \
		--vivado.prop run.impl_1.STEPS.OPT_DESIGN.TCL.POST=insert_ila.tcl \
		-o $(KERNEL)_hw.xclbin
	@echo "=== Link complete (ILA): $(KERNEL)_hw.xclbin ==="

link-emu: $(XO_FILE) $(CFG_FILE)
	$(VPP) -t hw_emu --platform $(PLATFORM_PATH) \
		--link $(XO_FILE) --config $(CFG_FILE) \
		--kernel_frequency $(FREQ) -o $(KERNEL)_hw_emu.xclbin
	@echo "=== Link-emu complete: $(KERNEL)_hw_emu.xclbin ==="

# =============================================================================
# Host application
# =============================================================================
.PHONY: host

$(HOST_EXE): $(HOST_SRC)
	$(HOST_CXX) $(HOST_CFLAGS) -o $@ $< $(HOST_LFLAGS)
	@echo "=== Host build complete ==="

host: $(HOST_EXE)

# =============================================================================
# Run
# =============================================================================
.PHONY: run-emu run-hw

emconfig.json:
	source $(VIVADO_SETUP) && emconfigutil --platform $(PLATFORM_PATH)

run-emu: $(HOST_EXE) $(KERNEL)_hw_emu.xclbin emconfig.json
	source $(VIVADO_SETUP) && source $(XRT_DIR)/setup.sh && XCL_EMULATION_MODE=hw_emu ./$(HOST_EXE) $(KERNEL)_hw_emu.xclbin data/

run-hw: $(HOST_EXE) $(KERNEL)_hw.xclbin
	source $(XRT_DIR)/setup.sh && ./$(HOST_EXE) $(KERNEL)_hw.xclbin data/

# =============================================================================
# Debug register reader (uses xrt::ip, run after kernel timeout + reset)
# =============================================================================
.PHONY: dbg_read

dbg_read: dbg_read.cpp
	$(HOST_CXX) $(HOST_CFLAGS) -o $@ $< $(HOST_LFLAGS)
	@echo "=== dbg_read build complete ==="

# =============================================================================
# Test host
# =============================================================================
XCLBIN_PROD := $(KERNEL)_hw.xclbin

.PHONY: host-test run-test

host-test: host_test.cpp
	$(HOST_CXX) $(HOST_CFLAGS) -o host_test $< $(HOST_LFLAGS)
	@echo "=== host_test build complete ==="

run-test: host_test $(XCLBIN_PROD)
	source $(XRT_DIR)/setup.sh && ./host_test $(XCLBIN_PROD) --all --verbose

# =============================================================================
# Small hw_emu (SIM_SMALL dimensions for fast debug)
# =============================================================================
SMALL_XO     := $(KERNEL)_small.xo
SMALL_XCLBIN := $(KERNEL)_small_hw_emu.xclbin
HOST_EMU_SRC := host_emu.cpp
HOST_EMU_EXE := host_emu

.PHONY: package-small link-emu-small host_emu run-emu-small

package-small: $(SMALL_XO)

$(SMALL_XO): $(RTL_DEPS)
	cd .. && export EMU_SMALL=1 && $(VIVADO) -mode batch -source fpga/build.tcl -tclargs
	@echo "=== Package-small complete: $(SMALL_XO) ==="

link-emu-small: $(SMALL_XCLBIN)

$(SMALL_XCLBIN): $(SMALL_XO) $(CFG_FILE)
	$(VPP) -t hw_emu --platform $(PLATFORM_PATH) \
		--link $(SMALL_XO) --config $(CFG_FILE) \
		--kernel_frequency $(FREQ) -o $@
	@echo "=== Link-emu-small complete: $@ ==="

host_emu: $(HOST_EMU_EXE)

$(HOST_EMU_EXE): $(HOST_EMU_SRC)
	$(HOST_CXX) $(HOST_CFLAGS) -o $@ $< $(HOST_LFLAGS)
	@echo "=== host_emu build complete ==="

run-emu-small: $(HOST_EMU_EXE) $(SMALL_XCLBIN) emconfig.json
	source $(VIVADO_SETUP) && source $(XRT_DIR)/setup.sh && XCL_EMULATION_MODE=hw_emu ./$(HOST_EMU_EXE) $(SMALL_XCLBIN)

# =============================================================================
# Clean
# =============================================================================
.PHONY: clean

clean:
	rm -rf $(HOST_EXE) *.xo *.xclbin *.log *.jou
	rm -rf $(KERNEL)_pkg $(KERNEL)_pkg_ip
	rm -rf _x .Xil .run emconfig.json
	rm -rf *.ltx *.wdb *.wcfg
