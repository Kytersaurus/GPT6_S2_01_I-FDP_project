# Owner: Shared integration - all roles; Role 4 (Marcus) coordinates project setup.
# In the Vivado Tcl Console, with the team's .xpr open:
# source scripts/add_team_sources.tcl
# Safe to repeat: adds missing files and refreshes include paths/compile order.
# Design files live together beside My_Top_Module.v.

if {[llength [get_projects -quiet]] != 1} {
    error "Open the team's Vivado project before sourcing this script."
}

# Use the open project's directory even if the Tcl Console is elsewhere.
set lp_repo_root [get_property DIRECTORY [current_project]]
set lp_source_dir [file join $lp_repo_root GPT_6_S2_01_I-FDP_project.srcs sources_1 new]

# Absolute patterns avoid a -directory path error in this Windows Tcl runtime.
set lp_hdl_files [glob -nocomplain \
    $lp_source_dir/*.v $lp_source_dir/*.sv $lp_source_dir/*.vhd \
    $lp_source_dir/*.vhdl $lp_source_dir/*.vh $lp_source_dir/*.svh \
    $lp_source_dir/*.mem]

set lp_sources [get_filesets sources_1]
foreach lp_path [lsort $lp_hdl_files] {
    if {[llength [get_files -quiet -of_objects $lp_sources $lp_path]] == 0} {
        add_files -fileset sources_1 -norecurse [list $lp_path]
    }
}

set lp_include_dirs [get_property include_dirs $lp_sources]
if {[lsearch -exact $lp_include_dirs $lp_source_dir] < 0} {
    lappend lp_include_dirs $lp_source_dir
}
set_property include_dirs $lp_include_dirs $lp_sources
set_property top My_Top_Module $lp_sources
update_compile_order -fileset sources_1
puts "Team sources registered from $lp_source_dir"

# Keep GUI/rebuild runs on the validated 100 MHz implementation flow.
set lp_impl_run [get_runs -quiet impl_1]
if {[llength $lp_impl_run] == 1} {
    set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $lp_impl_run
    set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $lp_impl_run
    set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $lp_impl_run
}
