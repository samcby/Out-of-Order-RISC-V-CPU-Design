set script_dir [file dirname [file normalize [info script]]]
set asic_dir [file normalize [file join $script_dir ".."]]
set repo_root [file normalize [file join $asic_dir ".."]]
set build_dir [file join $asic_dir build dc]
set report_dir [file join $asic_dir reports dc]
set top_name top_packet_backend

if {![info exists ::env(ASIC_TECH_SETUP)]} {
    error "Set ASIC_TECH_SETUP to a Tcl file defining TARGET_LIBRARY_FILES."
}
source [file normalize $::env(ASIC_TECH_SETUP)]

if {![info exists TARGET_LIBRARY_FILES] ||
    [llength $TARGET_LIBRARY_FILES] == 0} {
    error "TARGET_LIBRARY_FILES must contain at least one Liberty .db file."
}
if {![info exists EXTRA_LINK_LIBRARY_FILES]} {
    set EXTRA_LINK_LIBRARY_FILES [list]
}
if {![info exists CLOCK_PERIOD_NS]} {
    set CLOCK_PERIOD_NS 5.000
}

file mkdir $build_dir
file mkdir $report_dir

set_app_var target_library $TARGET_LIBRARY_FILES
set_app_var link_library [concat "*" $TARGET_LIBRARY_FILES \
                          $EXTRA_LINK_LIBRARY_FILES]
set_app_var hdlin_check_no_latch true
set_app_var verilogout_no_tri true

source [file join $script_dir load_manifest.tcl]
set rtl_files [load_rtl_manifest $repo_root \
    [file join $asic_dir rtl_files.f]]

analyze -format sverilog -define {SYNTHESIS} $rtl_files
elaborate $top_name
current_design $top_name
link

redirect -file [file join $report_dir check_design_precompile.rpt] {
    check_design
}

source [file join $asic_dir constraints top_packet_backend.sdc]
set_fix_multiple_port_nets -all -buffer_constants
set_max_area 0

compile_ultra -no_autoungroup

redirect -file [file join $report_dir check_design_postcompile.rpt] {
    check_design
}
redirect -file [file join $report_dir qor.rpt] {
    report_qor
}
redirect -file [file join $report_dir area.rpt] {
    report_area -hierarchy
}
redirect -file [file join $report_dir timing_setup.rpt] {
    report_timing -delay_type max -max_paths 50 -input_pins -nets
}
redirect -file [file join $report_dir timing_hold.rpt] {
    report_timing -delay_type min -max_paths 20 -input_pins -nets
}
redirect -file [file join $report_dir constraints.rpt] {
    report_constraint -all_violators
}
redirect -file [file join $report_dir power_vectorless.rpt] {
    report_power -analysis_effort low
}

write -format ddc -hierarchy -output \
    [file join $build_dir ${top_name}.ddc]
write -format verilog -hierarchy -output \
    [file join $build_dir ${top_name}_mapped.v]
write_sdc [file join $build_dir ${top_name}_mapped.sdc]

puts "ASIC synthesis complete."
puts "Netlist: [file join $build_dir ${top_name}_mapped.v]"
puts "Reports: $report_dir"
exit
