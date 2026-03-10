# build.tcl — Package test_kernel as a Vitis .xo
set path_to_hdl "."
set path_to_packaged "xo_pkg"
set path_to_tmp_project "tmp_prj"

create_project -force kernel_pack $path_to_tmp_project
add_files [glob $path_to_hdl/*.v]
set_property file_type SystemVerilog [get_files *.v]
update_compile_order -fileset sources_1

# Package IP
ipx::package_project -root_dir $path_to_packaged -vendor user.org -library kernel \
    -taxonomy /KernelIP -import_files -set_current false

ipx::unload_core $path_to_packaged/component.xml
ipx::edit_ip_in_project -upgrade true -name tmp_edit_project \
    -directory $path_to_packaged $path_to_packaged/component.xml

set core [ipx::current_core]
set_property core_revision 1 $core
set_property sdx_kernel true $core
set_property sdx_kernel_type rtl $core
set_property vitis_drc {ctrl_protocol ap_ctrl_hs} $core

# s_axi_control
ipx::associate_bus_interfaces -busif s_axi_control -clock ap_clk $core

# m_axi_hbm0
ipx::associate_bus_interfaces -busif m_axi_hbm0 -clock ap_clk $core

# Merge kernel.xml
set fd [open "kernel.xml" r]
set xml [read $fd]
close $fd
set_property xpm_libraries {XPM_MEMORY XPM_FIFO} $core
ipx::merge_project_changes ports $core
ipx::merge_project_changes hdl_parameters $core

set_property driver_value 0 [ipx::get_ports -filter "direction==in" -of_objects $core]

ipx::update_checksums $core
ipx::save_core $core
close_project -delete

# Package .xo
package_xo -xo_path test_kernel.xo -kernel_name test_kernel \
    -ip_directory $path_to_packaged -kernel_xml kernel.xml -force

puts "=== XO packaged: test_kernel.xo ==="
