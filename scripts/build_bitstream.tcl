# Generate bitstream for Laggy Piggies on Basys3
set lp_repo_root [file dirname [file dirname [file join [pwd] [info script]]]]
set lp_source_dir [file join $lp_repo_root GPT_6_S2_01_I-FDP_project.srcs sources_1 new]
set lp_output_dir [file join $lp_repo_root tmp bitstream_build]
file mkdir $lp_output_dir

create_project -in_memory -part xc7a35tcpg236-1
add_files -norecurse [glob -directory $lp_source_dir *.v]
add_files -norecurse [glob -directory $lp_source_dir *.vhd]
set_property include_dirs [list $lp_source_dir] [get_filesets sources_1]
set_property top My_Top_Module [get_filesets sources_1]
update_compile_order -fileset sources_1

# Synthesis
synth_design -top My_Top_Module -part xc7a35tcpg236-1
read_xdc [file join $lp_repo_root GPT_6_S2_01_I-FDP_project.srcs constrs_1 new Basys3_Master.xdc]

# Implementation
opt_design
place_design
phys_opt_design
route_design

# Reports
report_utilization -file [file join $lp_output_dir utilization_routed.rpt]
report_timing_summary -file [file join $lp_output_dir timing_routed.rpt]

# Bitstream
write_bitstream -force [file join $lp_output_dir My_Top_Module.bit]
puts "SUCCESS: Bitstream generated at [file join $lp_output_dir My_Top_Module.bit]"
close_project
