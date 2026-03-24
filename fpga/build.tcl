# =============================================================================
# build.tcl — Package RTL as Vitis Kernel (.xo) for Alveo U280
# =============================================================================
#
# Usage: vivado -mode batch -source fpga/build.tcl
# Output: fpga/fpga_kernel.xo
#
# =============================================================================

set project_name "fpga_kernel_pkg"
set kernel_name  "fpga_kernel"
if {[info exists ::env(EMU_SMALL)]} {
    set xo_file "[pwd]/fpga/${kernel_name}_small.xo"
} else {
    set xo_file "[pwd]/fpga/${kernel_name}.xo"
}
set rtl_dir      "[pwd]/rtl"
set fpga_rtl_dir "[pwd]/fpga/rtl"
set kernel_xml   "[pwd]/fpga/kernel.xml"

# Part for Alveo U280
set part "xcu280-fsvh2892-2L-e"

# =============================================================================
# Create project
# =============================================================================
create_project -force $project_name fpga/$project_name -part $part

# =============================================================================
# Add RTL sources
# =============================================================================
# Main RTL (exclude sim-only files)
set rtl_files [glob -nocomplain ${rtl_dir}/*.v ${rtl_dir}/*.vh]
set filtered_files {}
foreach f $rtl_files {
    set fname [file tail $f]
    if {$fname ne "sim_hbm_port.v"} {
        lappend filtered_files $f
    }
}
add_files -norecurse $filtered_files

# LUT hex files (for $readmemh during synthesis)
add_files -norecurse [glob -nocomplain ${rtl_dir}/*.hex]

# FPGA-specific RTL
add_files -norecurse [glob ${fpga_rtl_dir}/*.v]

# Set defines.vh include path and verilog defines
if {[info exists ::env(EMU_SMALL)]} {
    set_property verilog_define {FPGA_TARGET SIM_SMALL} [current_fileset]
    puts "INFO: EMU_SMALL mode — using SIM_SMALL dimensions"
} else {
    set_property verilog_define {FPGA_TARGET} [current_fileset]
}
set_property include_dirs $rtl_dir [current_fileset]

# Mark all .v files as SystemVerilog (defines.vh uses root-scope
# parameter/localparam, which requires SV mode in XSim for hw_emu)
foreach f [get_files -of_objects [current_fileset] *.v] {
    set_property file_type SystemVerilog $f
}

# Set fpga_kernel.v as top
set_property top $kernel_name [current_fileset]

update_compile_order -fileset sources_1

# =============================================================================
# Package as IP
# =============================================================================
ipx::package_project -root_dir fpga/${project_name}_ip -vendor user.org \
    -library kernel -taxonomy /KernelIP -import_files -set_current true

# Set kernel properties
set core [ipx::current_core]
set_property sdx_kernel true $core
set_property sdx_kernel_type rtl $core
set_property ipi_drc {ignore_freq_hz true} $core
set_property vitis_drc {ctrl_protocol ap_ctrl_hs} $core

# =============================================================================
# Associate clocks with all AXI interfaces
# =============================================================================
set clk_intf [ipx::get_bus_interfaces ap_clk -of_objects $core]

# s_axi_control
ipx::associate_bus_interfaces -busif s_axi_control -clock ap_clk $core

# All 6 m_axi ports (hbm00-01, hbm06-07, hbm12-13)
foreach port_name {m_axi_hbm00 m_axi_hbm01 m_axi_hbm06 m_axi_hbm07 m_axi_hbm12 m_axi_hbm13} {
    ipx::associate_bus_interfaces -busif $port_name -clock ap_clk $core
}

# =============================================================================
# Set address space parameters for m_axi ports
# =============================================================================
foreach port_name {m_axi_hbm00 m_axi_hbm01 m_axi_hbm06 m_axi_hbm07 m_axi_hbm12 m_axi_hbm13} {
    # Ensure the master address space width is 33 bits (8GB)
    set addr_space [ipx::get_address_spaces ${port_name} -of_objects $core]
    if {$addr_space ne ""} {
        set_property range 8589934592 $addr_space
        set_property width 33 $addr_space
    }
}

# =============================================================================
# Add kernel.xml (must be inside IP root dir for ipx::get_files to work)
# =============================================================================
set ip_root_dir "fpga/${project_name}_ip"
file copy -force $kernel_xml ${ip_root_dir}/kernel.xml
set local_xml "[pwd]/${ip_root_dir}/kernel.xml"

set file_group [ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects $core]
ipx::add_file $local_xml $file_group
set_property type xml [ipx::get_files kernel.xml -of_objects $file_group]

# =============================================================================
# Save and package
# =============================================================================
set_property core_revision 1 $core
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

# =============================================================================
# EMU_SMALL: inject `define SIM_SMALL into the IP copy of fpga_kernel.v
# This ensures XSim sees SIM_SMALL when v++ compiles from the .xo.
# =============================================================================
if {[info exists ::env(EMU_SMALL)]} {
    # Inject into defines.vh — every .v file includes it, and XSim compiles
    # each file as a separate compilation unit so a define in one file
    # doesn't propagate to others.
    set ip_defines "${ip_root_dir}/src/defines.vh"
    if {[file exists $ip_defines]} {
        set fd [open $ip_defines r]
        set orig [read $fd]
        close $fd
        set fd [open $ip_defines w]
        puts $fd "`define SIM_SMALL"
        puts $fd "`define FPGA_TARGET"
        puts -nonewline $fd $orig
        close $fd
        puts "INFO: Injected SIM_SMALL define into $ip_defines"
    } else {
        puts "WARNING: Could not find $ip_defines to inject SIM_SMALL"
    }
}

# =============================================================================
# Package .xo
# =============================================================================
if {[file exists $xo_file]} {
    file delete -force $xo_file
}

package_xo -xo_path $xo_file \
    -kernel_name $kernel_name \
    -ip_directory fpga/${project_name}_ip \
    -kernel_xml $kernel_xml

puts "INFO: Kernel .xo created at $xo_file"

# Cleanup
close_project
