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
        performance {
            tb_top_packet_backend_ipc_compare
        }
        softfloat {
            tb_fp_softfloat_diff
        }
        floating {
            tb_fp_infrastructure_smoke
            tb_fp_rename_smoke
            tb_fp_memory_bridge_smoke
            tb_fp_domain_wakeup_smoke
            tb_top_packet_backend_fp_memory_smoke
            tb_fp_simple_unit
            tb_top_packet_backend_fp_simple_smoke
            tb_top_packet_backend_fp_flags_smoke
            tb_fp_add_sub_unit
            tb_top_packet_backend_fp_add_sub_smoke
            tb_fp_mul_unit
            tb_fp_convert_unit
            tb_fp_div_sqrt_unit
            tb_fp_div_sqrt_iterative
            tb_fp_fma_unit
            tb_fp_softfloat_diff
            tb_fp_execution_pipeline
            tb_top_packet_backend_fp_pipeline_smoke
            tb_top_packet_backend_fp_convert_smoke
            tb_top_packet_backend_fp_div_sqrt_smoke
            tb_top_packet_backend_fp_fma_smoke
        }
        full {
            tb_fp_infrastructure_smoke
            tb_fp_rename_smoke
            tb_fp_memory_bridge_smoke
            tb_fp_domain_wakeup_smoke
            tb_top_packet_backend_fp_memory_smoke
            tb_fp_simple_unit
            tb_top_packet_backend_fp_simple_smoke
            tb_top_packet_backend_fp_flags_smoke
            tb_fp_add_sub_unit
            tb_top_packet_backend_fp_add_sub_smoke
            tb_fp_mul_unit
            tb_fp_convert_unit
            tb_fp_div_sqrt_unit
            tb_fp_div_sqrt_iterative
            tb_fp_fma_unit
            tb_fp_softfloat_diff
            tb_fp_execution_pipeline
            tb_top_packet_backend_fp_pipeline_smoke
            tb_top_packet_backend_fp_convert_smoke
            tb_top_packet_backend_fp_div_sqrt_smoke
            tb_top_packet_backend_fp_fma_smoke
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
            tb_top_packet_backend_ipc_compare
            tb_top_packet_backend_lane1_squash_smoke
            tb_top_packet_backend_rv32i_smoke
            tb_top_packet_backend_25test
            tb_top_packet_backend_trap_smoke
            tb_top_packet_backend_interrupt_smoke
        }
    }
}

proc prepare_regression_top {tb} {
    set source_set [get_filesets sources_1]
    set sim_set [get_filesets sim_1]

    # Vivado 2019.1 persists hierarchy-derived AutoDisabled state in the XPR.
    # Without explicitly enabling the new top, the first test after switching
    # suites can compile the previous top's source closure and then fail to
    # elaborate the requested design unit.
    foreach source_file [get_files -all -of_objects $source_set] {
        catch {set_property AUTO_DISABLED false $source_file}
        catch {set_property IS_ENABLED true $source_file}
    }

    set target_files [get_files -quiet -all -of_objects $sim_set "*${tb}.sv"]
    if {[llength $target_files] == 0} {
        set project_dir [get_property DIRECTORY [current_project]]
        set source_path [file normalize [file join \
            $project_dir \
            "OoO_RISC_V_CPU_DESIGN.srcs" \
            "sim_1" \
            "new" \
            "${tb}.sv"]]

        # A GUI session keeps the project model in memory. If a testbench was
        # added to the XPR externally, register it without requiring a reopen.
        if {[file exists $source_path]} {
            add_files -norecurse -fileset sim_1 $source_path
            set target_files [get_files -quiet -all \
                -of_objects $sim_set "*${tb}.sv"]
        }
    }

    if {[llength $target_files] == 0} {
        error "Simulation source for top '$tb' is not present in sim_1."
    }

    foreach target_file $target_files {
        catch {set_property AUTO_DISABLED false $target_file}
        catch {set_property IS_ENABLED true $target_file}
        catch {set_property USED_IN_SIMULATION true $target_file}
    }

    set_property top $tb $sim_set
    catch {update_compile_order -fileset sources_1}
    catch {update_compile_order -fileset sim_1}
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
        if {[catch {prepare_regression_top $tb} message]} {
            puts "ERROR: failed to prepare $tb"
            puts $message
            incr launch_failures
            continue
        }

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
