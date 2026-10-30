# Run from Vivado's Tcl Console with: source scripts/rebuild_bitstream.tcl
# Also supports Vivado batch mode when no project is open.
set repair_script [info script]
if {[file pathtype $repair_script] eq "relative"} {
    set repair_script [file join [pwd] $repair_script]
}
set repair_root [file dirname [file dirname $repair_script]]
if {[current_project -quiet] eq ""} {
    open_project [file join $repair_root GPT_6_S2_01_I-FDP_project.xpr]
}
set repair_run [get_runs synth_1]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 $repair_run
set_property INCREMENTAL_CHECKPOINT {} $repair_run
foreach repair_dcp [get_files -quiet -all *My_Top_Module.dcp] {
    if {![file exists $repair_dcp]} {
        remove_files $repair_dcp
    }
}
source [file join $repair_root scripts add_team_sources.tcl]
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "BITSTREAM_REBUILD_STATUS: [get_property STATUS [get_runs impl_1]]"
if {![string match {*Complete*} [get_property STATUS [get_runs impl_1]]]} {
    error "Bitstream build did not complete; check synthesis and implementation runme.log files."
}
