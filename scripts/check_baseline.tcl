# Owner: Shared integration - all roles; synthesis checks.
# Run with Vivado batch mode, passing this script's absolute path to -source.
# Creates an in-memory synthesis project; it does not overwrite the team's .xpr.
set lp_repo_root [file dirname [file dirname [file join [pwd] [info script]]]]
set lp_source_dir [file join $lp_repo_root GPT_6_S2_01_I-FDP_project.srcs sources_1 new]
set lp_report_dir [file join $lp_repo_root tmp baseline_synthesis]
file mkdir $lp_report_dir
create_project -in_memory -part xc7a35tcpg236-1
add_files -norecurse [glob -directory $lp_source_dir *.v]
add_files -norecurse [glob -directory $lp_source_dir *.vhd]
set_property include_dirs [list $lp_source_dir] [get_filesets sources_1]
set_property top My_Top_Module [get_filesets sources_1]
update_compile_order -fileset sources_1
synth_design -top My_Top_Module -part xc7a35tcpg236-1
read_xdc [file join $lp_repo_root GPT_6_S2_01_I-FDP_project.srcs constrs_1 new Basys3_Master.xdc]
if {[llength [get_cells -hierarchical -filter {IS_BLACKBOX == 1}]] != 0} {
    error "Unresolved black boxes remain after baseline synthesis."
}
report_utilization -file [file join $lp_report_dir utilization.rpt]
report_timing_summary -file [file join $lp_report_dir timing.rpt]
puts "PASS: baseline synthesis and constraints loaded. Reports: $lp_report_dir"
close_project
