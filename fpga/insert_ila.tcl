# =============================================================================
# insert_ila.tcl — Create ILA core for mark_debug nets after opt_design
# =============================================================================
# Usage: passed to v++ via:
#   --vivado.prop run.impl_1.STEPS.OPT_DESIGN.TCL.POST=insert_ila.tcl
#
# Finds all nets with MARK_DEBUG=true in the design, creates a single ILA
# core, and connects them. The ILA uses the kernel clock automatically.
# =============================================================================

# Find all mark_debug nets
set debug_nets [get_nets -hierarchical -filter {MARK_DEBUG == true}]

if {[llength $debug_nets] == 0} {
    puts "INSERT_ILA: No MARK_DEBUG nets found — skipping ILA insertion"
    return
}

puts "INSERT_ILA: Found [llength $debug_nets] MARK_DEBUG nets:"
foreach n $debug_nets {
    puts "  $n"
}

# Find the kernel clock (ap_clk)
set clk_net [get_nets -hierarchical -filter {NAME =~ "*ap_clk*"}]
if {[llength $clk_net] == 0} {
    puts "INSERT_ILA: ERROR — cannot find ap_clk, skipping ILA insertion"
    return
}
# Take the first match if multiple
set clk_net [lindex $clk_net 0]
puts "INSERT_ILA: Using clock: $clk_net"

# Create debug core
create_debug_core u_ila_user ila

# Configure ILA: 4096 samples, basic trigger
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_user]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_user]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_user]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_user]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_user]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_user]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_user]

# Connect clock
set_property port_width 1 [get_debug_ports u_ila_user/clk]
connect_debug_port u_ila_user/clk $clk_net

# Connect all debug nets as probes
set probe_idx 0
foreach net $debug_nets {
    if {$probe_idx == 0} {
        # First probe already exists (probe0)
        set_property port_width 1 [get_debug_ports u_ila_user/probe0]
        connect_debug_port u_ila_user/probe0 [list $net]
    } else {
        # Create additional probes
        create_debug_port u_ila_user probe
        set pname "u_ila_user/probe${probe_idx}"
        set_property port_width 1 [get_debug_ports $pname]
        connect_debug_port $pname [list $net]
    }
    incr probe_idx
}

puts "INSERT_ILA: Created ILA with $probe_idx probes, 4096 depth"
