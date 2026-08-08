set script_dir [file dirname [file normalize [info script]]]
set asic_dir [file normalize [file join $script_dir ".."]]
set build_dir [file join $asic_dir build dc]
set report_dir [file join $asic_dir reports pt]
set top_name top_packet_backend

if {![info exists ::env(ASIC_TECH_SETUP)]} {
    error "Set ASIC_TECH_SETUP to the technology setup used for synthesis."
}
source [file normalize $::env(ASIC_TECH_SETUP)]

if {![info exists TARGET_LIBRARY_FILES] ||
    [llength $TARGET_LIBRARY_FILES] == 0} {
    error "TARGET_LIBRARY_FILES must contain at least one Liberty .db file."
}
if {![info exists EXTRA_LINK_LIBRARY_FILES]} {
    set EXTRA_LINK_LIBRARY_FILES [list]
}

file mkdir $report_dir
set_app_var link_path [concat "*" $TARGET_LIBRARY_FILES \
                       $EXTRA_LINK_LIBRARY_FILES]

read_verilog [file join $build_dir ${top_name}_mapped.v]
current_design $top_name
link_design $top_name
read_sdc [file join $build_dir ${top_name}_mapped.sdc]

if {[info exists ::env(ASIC_SPEF)] &&
    [file exists $::env(ASIC_SPEF)]} {
    read_parasitics $::env(ASIC_SPEF)
}

redirect -file [file join $report_dir check_timing.rpt] {
    check_timing -verbose
}
redirect -file [file join $report_dir timing_setup.rpt] {
    report_timing -delay_type max -max_paths 100 \
        -input_pins -nets -transition_time -capacitance
}
redirect -file [file join $report_dir timing_hold.rpt] {
    report_timing -delay_type min -max_paths 50 \
        -input_pins -nets -transition_time -capacitance
}
redirect -file [file join $report_dir constraints.rpt] {
    report_constraint -all_violators
}
redirect -file [file join $report_dir coverage.rpt] {
    report_analysis_coverage
}

puts "PrimeTime baseline complete. Reports: $report_dir"
exit
