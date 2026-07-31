# Headless wrapper around run_regression.tcl.
#
# Usage:
#   vivado -mode batch -source scripts/run_regression_batch.tcl \
#          -tclargs memory

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ".."]]
set suite [expr {[llength $argv] > 0 ? [lindex $argv 0] : "quick"}]

open_project [file join $project_dir "OoO_RISC_V_CPU_DESIGN.xpr"]
source [file join $script_dir "run_regression.tcl"]
run_regression $suite
close_project
