# Owner: Shared integration - all roles; Role 4 (Marcus) coordinates project setup.
# In the Vivado Tcl Console, with the team's .xpr open:
# source scripts/add_team_sources.tcl
# Safe to repeat: adds missing files and refreshes include paths/compile order.
# Templates end in .example and are deliberately excluded.

if {[llength [get_projects -quiet]] != 1} {
    error "Open the team's Vivado project before sourcing this script."
}

# Use the open project's directory even if the Tcl Console is elsewhere.
set lp_repo_root [get_property DIRECTORY [current_project]]
set lp_source_dir [file join $lp_repo_root GPT_6_S2_01_I-FDP_project.srcs sources_1 new]

proc lp_find_hdl {directory} {
    set found [list]
    foreach item [lsort [glob -nocomplain -directory $directory *]] {
        if {[file isdirectory $item]} {
            set found [concat $found [lp_find_hdl $item]]
        } elseif {[string tolower [file extension $item]] in {.v .sv .vhd .vhdl .vh .svh}} {
            lappend found $item
        }
    }
    return $found
}

set lp_sources [get_filesets sources_1]
set lp_known_files [list]
foreach lp_file [get_files -quiet -of_objects $lp_sources] {
    lappend lp_known_files [file normalize $lp_file]
}
foreach lp_path [lp_find_hdl $lp_source_dir] {
    if {[lsearch -exact $lp_known_files [file normalize $lp_path]] < 0} {
        # add_files expects a Tcl list; keep a path containing spaces as one item.
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
