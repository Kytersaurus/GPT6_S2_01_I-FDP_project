# Owner: Shared integration - archive successful Vivado programming files.
# Runs after Write Bitstream for this project's impl_1 run.
set lp_archive_root [file dirname [file dirname [info script]]]
# Use the explicit project path: this Vivado installation can shorten pwd incorrectly.
set lp_bit_file [file join $lp_archive_root GPT_6_S2_01_I-FDP_project.runs impl_1 My_Top_Module.bit]
if {![file exists $lp_bit_file]} { error "Bitstream not found: $lp_bit_file" }
set lp_build_time [file mtime $lp_bit_file]
set lp_build_date [clock format $lp_build_time -format %Y-%m-%d -timezone +0800]
set lp_build_clock [clock format $lp_build_time -format %H%M%S -timezone +0800]
set lp_relative_file "$lp_build_date/${lp_build_clock}_My_Top_Module.bit"
set lp_archive_dir [file join $lp_archive_root bitstreams]
set lp_archived_file [file join $lp_archive_dir $lp_relative_file]
file mkdir [file dirname $lp_archived_file]
file copy -force $lp_bit_file $lp_archived_file
set lp_latest [open [file join $lp_archive_dir LATEST.txt] w]
puts $lp_latest $lp_relative_file
close $lp_latest
puts "Archived bitstream: $lp_archived_file"
