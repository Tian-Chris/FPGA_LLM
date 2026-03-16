# =============================================================================
# fpga/Makefile — Vitis RTL Kernel Build for Alveo U280
# =============================================================================
#
# Targets:
#   make package    — Vivado: package RTL → .xo
#   make link-emu   — v++: link .xo → .xclbin (hw_emu)
#   make link-hw    — v++: link .xo → .xclbin (hw)
#   make host       — g++: compile XRT host application
#   make run-emu    — Run hardware emulation
#   make run-hw     — Run on real FPGA
#   make clean      — Remove build artifacts
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

# Targets
TARGET   ?= hw_emu
XCLBIN   := $(KERNEL)_$(TARGET).xclbin

# Host
HOST_SRC := host.cpp
HOST_EXE := host
XRT_DIR  := /opt/xilinx/xrt

# Compiler flags
HOST_CXX    := g++
HOST_CFLAGS := -std=c++17 -O2 -I$(XRT_DIR)/include -fmessage-length=0
HOST_LFLAGS := -L$(XRT_DIR)/lib -lOpenCL -lxrt_coreutil -pthread

# =============================================================================
# Package: RTL → .xo (Vivado batch)
# =============================================================================
.PHONY: package
package: $(XO_FILE)

$(XO_FILE): build.tcl kernel.xml rtl/fpga_kernel.v rtl/vitis_control.v $(wildcard ../rtl/*.v ../rtl/*.vh)
	cd .. && $(VIVADO) -mode batch -source fpga/build.tcl -tclargs
	@echo "=== Package complete: $(XO_FILE) ==="

# =============================================================================
# Link: .xo → .xclbin (v++)
# =============================================================================
.PHONY: link-emu link-hw link-hw-spread

link-emu: TARGET := hw_emu
link-emu: $(KERNEL)_hw_emu.xclbin

link-hw: TARGET := hw
link-hw: $(KERNEL)_hw.xclbin

$(KERNEL)_%.xclbin: $(XO_FILE) $(CFG_FILE)
	$(VPP) -t $* --platform $(PLATFORM_PATH) \
		--link $(XO_FILE) \
		--config $(CFG_FILE) \
		--kernel_frequency 150 \
		--dk chipscope:fpga_kernel_1 \
		-o $@
	@echo "=== Link complete: $@ ==="

link-hw-spread: $(XO_FILE) $(CFG_FILE)
	$(VPP) -t hw --platform $(PLATFORM_PATH) \
		--link $(XO_FILE) \
		--config $(CFG_FILE) \
		--kernel_frequency 150 \
		--dk chipscope:fpga_kernel_1 \
		--vivado.prop run.impl_1.STEPS.PLACE_DESIGN.ARGS.DIRECTIVE=AltSpreadLogic_high \
		--vivado.prop run.impl_1.STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE=AlternateCLBRouting \
		--vivado.prop run.impl_1.STEPS.OPT_DESIGN.ARGS.DIRECTIVE=ExploreWithRemap \
		-o $(KERNEL)_hw.xclbin
	@echo "=== Link complete (AltSpreadLogic_high): $(KERNEL)_hw.xclbin ==="

link-hw-ila: $(XO_FILE) $(CFG_FILE)
	$(VPP) -t hw --platform $(PLATFORM_PATH) \
		--link $(XO_FILE) \
		--config $(CFG_FILE) \
		--kernel_frequency 150 \
		--dk chipscope:fpga_kernel_1 \
		--vivado.prop run.impl_1.STEPS.PLACE_DESIGN.ARGS.DIRECTIVE=AltSpreadLogic_high \
		--vivado.prop run.impl_1.STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE=AlternateCLBRouting \
		--vivado.prop run.impl_1.STEPS.OPT_DESIGN.ARGS.DIRECTIVE=ExploreWithRemap \
		--vivado.prop run.impl_1.STEPS.OPT_DESIGN.TCL.POST=insert_ila.tcl \
		-o $(KERNEL)_hw.xclbin
	@echo "=== Link complete (ILA + AltSpreadLogic_high): $(KERNEL)_hw.xclbin ==="

# =============================================================================
# Host application
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

# Generate emconfig for hw_emu
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
# Small hw_emu (SIM_SMALL dimensions for fast debug)
# =============================================================================
SMALL_XO     := $(KERNEL)_small.xo
SMALL_XCLBIN := $(KERNEL)_small_hw_emu.xclbin
HOST_EMU_SRC := host_emu.cpp
HOST_EMU_EXE := host_emu

.PHONY: package-small link-emu-small host_emu run-emu-small

package-small: $(SMALL_XO)

$(SMALL_XO): build.tcl kernel.xml rtl/fpga_kernel.v rtl/vitis_control.v $(wildcard ../rtl/*.v ../rtl/*.vh)
	cd .. && export EMU_SMALL=1 && $(VIVADO) -mode batch -source fpga/build.tcl -tclargs
	@echo "=== Package-small complete: $(SMALL_XO) ==="

link-emu-small: $(SMALL_XCLBIN)

$(SMALL_XCLBIN): $(SMALL_XO) $(CFG_FILE)
	$(VPP) -t hw_emu --platform $(PLATFORM_PATH) \
		--link $(SMALL_XO) \
		--config $(CFG_FILE) \
		--kernel_frequency 150 \
		-o $@
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
