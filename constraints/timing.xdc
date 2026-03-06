# =============================================================================
# timing.xdc - Timing Constraints for Diffusion Transformer FPGA
# =============================================================================

# -----------------------------------------------------------------------------
# Clock Definition
# -----------------------------------------------------------------------------
# Primary clock - adjust frequency based on target FPGA
# 100 MHz default
create_clock -period 10.000 -name clk [get_ports clk]

# -----------------------------------------------------------------------------
# Clock Uncertainty
# -----------------------------------------------------------------------------
set_clock_uncertainty 0.500 [get_clocks clk]

# -----------------------------------------------------------------------------
# Input Delays (AXI-Lite Interface)
# -----------------------------------------------------------------------------
# Assuming external source is synchronous with setup/hold margins
set_input_delay -clock clk -max 3.000 [get_ports {s_axi_*}]
set_input_delay -clock clk -min 1.000 [get_ports {s_axi_*}]

# -----------------------------------------------------------------------------
# Output Delays (AXI-Lite Interface)
# -----------------------------------------------------------------------------
set_output_delay -clock clk -max 3.000 [get_ports {s_axi_*}]
set_output_delay -clock clk -min 1.000 [get_ports {s_axi_*}]

# IRQ output
set_output_delay -clock clk -max 3.000 [get_ports irq_done]
set_output_delay -clock clk -min 1.000 [get_ports irq_done]

# -----------------------------------------------------------------------------
# Reset Timing
# -----------------------------------------------------------------------------
# Asynchronous reset - treat as false path for timing analysis
# but ensure proper synchronization in design
set_false_path -from [get_ports rst_n]

# -----------------------------------------------------------------------------
# Multi-Cycle Paths
# -----------------------------------------------------------------------------
# BRAM reads have 1-cycle latency built into controller
# No additional multi-cycle constraints needed for basic operation

# -----------------------------------------------------------------------------
# Max Delay Constraints for Critical Paths
# -----------------------------------------------------------------------------
# Matmul accumulator paths (may need relaxation for high utilization)
# set_max_delay 8.000 -from [get_cells -hier -filter {NAME =~ *u_matmul*acc*}] \
#                     -to   [get_cells -hier -filter {NAME =~ *u_matmul*acc*}]

# -----------------------------------------------------------------------------
# False Paths
# -----------------------------------------------------------------------------
# Configuration registers (written once, read many)
# set_false_path -from [get_cells -hier -filter {NAME =~ *batch_size*}]
# set_false_path -from [get_cells -hier -filter {NAME =~ *seq_len*}]

# -----------------------------------------------------------------------------
# Physical Constraints (Optional)
# -----------------------------------------------------------------------------
# Uncomment and modify for specific FPGA board

# # Clock pin (example for Artix-7)
# set_property PACKAGE_PIN E3 [get_ports clk]
# set_property IOSTANDARD LVCMOS33 [get_ports clk]

# # Reset pin
# set_property PACKAGE_PIN C12 [get_ports rst_n]
# set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# -----------------------------------------------------------------------------
# BRAM Optimization
# -----------------------------------------------------------------------------
# Allow block RAM inference
set_property BLOCK_POWER_OPT ON [current_design]

# -----------------------------------------------------------------------------
# DSP Optimization
# -----------------------------------------------------------------------------
# Use DSP slices for multiplication in matmul engine
set_property DSP_CASCADING ON [current_design]
