# Synthesize the actual collision ROM port, then export a functional netlist.
set lp_runtime [lindex $argv 0]
foreach lp_package [glob -nocomplain -types d -directory [file join $lp_runtime data XilinxTclStore support] *] {lappend ::auto_path $lp_package}
foreach lp_package [glob -nocomplain -types d -directory [file join $lp_runtime data XilinxTclStore tclapp] */*] {lappend ::auto_path $lp_package}
set lp_root [lindex $argv 1]
set lp_src [file join $lp_root GPT_6_S2_01_I-FDP_project.srcs sources_1 new]
set lp_work [file join $lp_root tmp map_solidity_synthesis]
file mkdir $lp_work
set lp_wrapper [file join $lp_work map_mask_fixed.v]
set lp_file [open $lp_wrapper w]
puts $lp_file {module map_mask_fixed(input wire clk,map_id,input wire signed [10:0] x,y,output wire solid,output wire [2:0] draw_class);
level_map rom(.map_id(map_id),.draw_clk(clk),.draw_x(x),.draw_y(y),.draw_class(draw_class),.query_clk(clk),.query_map_id(map_id),.query_x(x),.query_y(y),.query_class(),.query_solid(solid));
endmodule}
close $lp_file
create_project -in_memory -part xc7a35tcpg236-1
add_files -norecurse [concat [list $lp_wrapper [file join $lp_src level_map.v]] [glob -directory $lp_src *.mem]]
set_property include_dirs [list $lp_src] [get_filesets sources_1]
synth_design -top map_mask_fixed -part xc7a35tcpg236-1
write_verilog -force -mode funcsim [file join $lp_work map_mask_netlist.v]
report_utilization -file [file join $lp_work utilization.rpt]
close_project
puts "PASS collision ROM netlist exported"
