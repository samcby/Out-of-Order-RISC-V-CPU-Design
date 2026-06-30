# Source this file from the Vivado Tcl console after opening the project:
#   source scripts/run_regression.tcl
#   run_regression quick
#
# The script changes only the sim_1 top. It does not remove or disable any
# legacy testbench.

namespace eval ooo_regression {
    variable suites
    array set suites {
        quick {
            tb_top_packet_backend_multi_issue_suite
            tb_top_packet_backend_rv32i_smoke
            tb_top_packet_backend_25test
            tb_top_packet_backend_trap_smoke
            tb_top_packet_backend_interrupt_smoke
        }
        multi_issue {
            tb_fetch_packet_stage
            tb_rename_packet_stage
            tb_rs_2issue
            tb_issue_packet_arbiter
            tb_dispatch_packet_stage_dual_issue
            tb_reg_file_2w
            tb_rob_2w
            tb_top_packet_backend_multi_issue_suite
            tb_top_packet_backend_lane1_squash_smoke
            tb_top_packet_backend_25test
        }
        memory {
            tb_data_cache_smoke
            tb_memory_order_queue
            tb_lsu_commit_store
            tb_top_packet_backend_multi_issue_suite
            tb_top_packet_backend_rv32i_smoke
            tb_top_misaligned_smoke
        }
        full {
            tb_fetch_packet_stage
            tb_decode_packet_stage
            tb_rename_packet_stage
            tb_rs_2issue
            tb_issue_packet_arbiter
            tb_dispatch_packet_stage_dual_issue
            tb_reg_file_2w
            tb_rob_2w
            tb_data_cache_smoke
            tb_memory_order_queue
            tb_lsu_commit_store
            tb_top_packet_backend_multi_issue_suite
            tb_top_packet_backend_lane1_squash_smoke
            tb_top_packet_backend_rv32i_smoke
            tb_top_packet_backend_25test
            tb_top_packet_backend_trap_smoke
            tb_top_packet_backend_interrupt_smoke
        }
    }
}

proc run_regression {{suite quick}} {
    if {[current_project -quiet] eq ""} {
        error "Open OoO_RISC_V_CPU_DESIGN.xpr before running regression."
    }

    if {![info exists ::ooo_regression::suites($suite)]} {
        set names [lsort [array names ::ooo_regression::suites]]
        error "Unknown regression suite '$suite'. Available suites: $names"
    }

    set tests $::ooo_regression::suites($suite)
    set total [llength $tests]
    set launch_failures 0
    set index 0

    puts "==== Starting '$suite' regression ($total simulation tops) ===="

    foreach tb $tests {
        incr index
        puts ""
        puts "==== \[$index/$total\] $tb ===="

        catch {close_sim}
        after 100
        set_property top $tb [get_filesets sim_1]

        if {[catch {launch_simulation -simset sim_1 -mode behavioral} message]} {
            puts "ERROR: failed to launch $tb"
            puts $message
            incr launch_failures
            continue
        }

        if {[catch {run 100000ns} message]} {
            puts "ERROR: simulation command failed for $tb"
            puts $message
            incr launch_failures
        }

        catch {close_sim}
        after 100
    }

    puts ""
    puts "==== '$suite' regression finished; launch/runtime failures: $launch_failures ===="
    puts "Review the console for each testbench PASS/FAIL banner."
}

proc list_regression_suites {} {
    foreach suite [lsort [array names ::ooo_regression::suites]] {
        puts "$suite: $::ooo_regression::suites($suite)"
    }
}
