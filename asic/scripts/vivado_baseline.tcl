set script_dir [file dirname [file normalize [info script]]]
set asic_dir [file normalize [file join $script_dir ".."]]
set repo_root [file normalize [file join $asic_dir ".."]]
set build_dir [file join $asic_dir build vivado_proxy]
set report_dir [file join $asic_dir reports vivado_proxy]
set top_name top_packet_backend
# WebPACK-supported proxy part. Device capacity is intentionally not treated
# as an implementation target; this run is only a portable RTL mapping check.
set target_part xc7a35tcpg236-1
set CLOCK_PERIOD_NS 5.000

file mkdir $build_dir
file mkdir $report_dir

source [file join $script_dir load_manifest.tcl]
set rtl_files [load_rtl_manifest $repo_root \
    [file join $asic_dir rtl_files.f]]

create_project -in_memory -part $target_part
set_property target_language Verilog [current_project]
read_verilog -sv $rtl_files

synth_design -top $top_name -part $target_part -mode out_of_context \
    -flatten_hierarchy rebuilt
source [file join $asic_dir constraints top_packet_backend.sdc]
write_checkpoint -force [file join $build_dir ${top_name}.dcp]

report_utilization -hierarchical -file \
    [file join $report_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -report_unconstrained -file \
    [file join $report_dir timing_summary.rpt]
report_high_fanout_nets -timing -max_nets 100 -file \
    [file join $report_dir high_fanout.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_methodology -file [file join $report_dir methodology.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]

puts "Vivado portability proxy complete."
puts "This is not an ASIC PPA result."
puts "Reports: $report_dir"
exit
