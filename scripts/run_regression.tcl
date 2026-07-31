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
            tb_top_packet_backend_misaligned_smoke
            tb_top_packet_backend_access_fault_smoke
            tb_top_packet_backend_exception_interrupt_priority
            tb_top_packet_backend_fence_smoke
            tb_top_packet_backend_privilege_smoke
            tb_top_packet_backend_pmp_smoke
            tb_top_packet_backend_interrupt_smoke
            tb_top_packet_backend_precise_interrupt_smoke
            tb_top_packet_backend_nested_interrupt_smoke
            tb_top_packet_backend_wfi_level_irq_smoke
        }
        multi_issue {
            tb_fetch_packet_stage
            tb_rename_packet_stage
            tb_rs_2issue
            tb_dispatch_packet_logic
            tb_issue_packet_arbiter
            tb_dispatch_packet_stage_dual_issue
            tb_rat_dis_packet_splitter
            tb_reg_file_2w
            tb_rob_2w
            tb_top_packet_backend_multi_issue_suite
            tb_top_packet_backend_mem_mem_dual_issue_smoke
            tb_top_packet_backend_lane1_squash_smoke
            tb_top_packet_backend_25test
        }
        memory {
            tb_data_cache_smoke
            tb_data_cache_dual_bank
            tb_memory_order_queue
            tb_load_store_queue
            tb_lsu_commit_store
            tb_lsu_nonblocking_2p
            tb_top_packet_backend_mem_mem_dual_issue_smoke
            tb_top_packet_backend_memory_replay_smoke
            tb_top_packet_backend_multi_issue_suite
            tb_top_packet_backend_rv32i_smoke
            tb_top_misaligned_smoke
            tb_top_packet_backend_misaligned_smoke
            tb_top_packet_backend_access_fault_smoke
            tb_top_packet_backend_fence_smoke
        }
        memory_core {
            tb_data_cache_smoke
            tb_data_cache_dual_bank
            tb_load_store_queue
            tb_lsu_commit_store
            tb_lsu_nonblocking_2p
        }
        memory_dual {
            tb_data_cache_dual_bank
            tb_load_store_queue
            tb_lsu_nonblocking_2p
            tb_top_packet_backend_mem_mem_dual_issue_smoke
            tb_top_packet_backend_memory_replay_smoke
            tb_top_packet_backend_rv32i_smoke
            tb_top_packet_backend_25test
        }
        memory_replay {
            tb_top_packet_backend_memory_replay_smoke
        }
        invariants {
            tb_reg_alias_table_2w
            tb_free_pool_2w
            tb_rob_2w
            tb_lsu_commit_store
            tb_top_packet_backend_misaligned_smoke
            tb_top_packet_backend_access_fault_smoke
            tb_top_packet_backend_exception_interrupt_priority
            tb_top_packet_backend_fence_smoke
            tb_top_packet_backend_privilege_smoke
            tb_top_packet_backend_pmp_smoke
            tb_top_packet_backend_precise_interrupt_smoke
            tb_top_packet_backend_nested_interrupt_smoke
            tb_top_packet_backend_wfi_level_irq_smoke
            tb_top_packet_backend_25test
        }
        performance {
            tb_top_packet_backend_ipc_compare
        }
        stress {
            tb_top_packet_backend_long_stress
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
            tb_top_packet_backend_fp_fs_smoke
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
            tb_top_packet_backend_fp_fs_smoke
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
            tb_rat_dis_packet_splitter
            tb_reg_file_2w
            tb_reg_alias_table_2w
            tb_free_pool_2w
            tb_rob_2w
            tb_data_cache_smoke
            tb_data_cache_dual_bank
            tb_memory_order_queue
            tb_load_store_queue
            tb_lsu_commit_store
            tb_lsu_nonblocking_2p
            tb_top_packet_backend_mem_mem_dual_issue_smoke
            tb_top_packet_backend_memory_replay_smoke
            tb_top_packet_backend_multi_issue_suite
            tb_top_packet_backend_ipc_compare
            tb_top_packet_backend_long_stress
            tb_top_packet_backend_lane1_squash_smoke
            tb_top_packet_backend_rv32i_smoke
            tb_top_packet_backend_25test
            tb_top_packet_backend_trap_smoke
            tb_top_packet_backend_misaligned_smoke
            tb_top_packet_backend_access_fault_smoke
            tb_top_packet_backend_exception_interrupt_priority
            tb_top_packet_backend_fence_smoke
            tb_top_packet_backend_privilege_smoke
            tb_top_packet_backend_pmp_smoke
            tb_top_packet_backend_interrupt_smoke
            tb_top_packet_backend_precise_interrupt_smoke
            tb_top_packet_backend_nested_interrupt_smoke
            tb_top_packet_backend_wfi_level_irq_smoke
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

proc regression_banner_status {tb} {
    set project_dir [get_property DIRECTORY [current_project]]
    set project_name [get_property NAME [current_project]]
    set log_path [file join \
        $project_dir \
        "${project_name}.sim" \
        "sim_1" \
        "behav" \
        "xsim" \
        "simulate.log"]

    if {![file exists $log_path]} {
        return "missing"
    }

    set log_file [open $log_path r]
    set log_text [read $log_file]
    close $log_file

    if {[string first "==== $tb PASS ====" $log_text] >= 0} {
        return "pass"
    }
    if {[string first "==== $tb FAIL" $log_text] >= 0} {
        return "fail"
    }
    return "missing"
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
    set functional_failures 0
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

        set run_time 100000ns
        if {$tb eq "tb_top_packet_backend_long_stress"} {
            set run_time 1000000ns
        }
        set run_failed [catch {run $run_time} message]
        if {$run_failed} {
            puts "ERROR: simulation command failed for $tb"
            puts $message
            incr launch_failures
        }

        # XSim may not flush simulate.log until the simulation is closed.
        catch {close_sim}
        after 100

        if {!$run_failed} {
            set banner_status [regression_banner_status $tb]
            if {$banner_status eq "fail"} {
                puts "ERROR: functional FAIL banner reported by $tb"
                incr functional_failures
            } elseif {$banner_status eq "missing"} {
                puts "ERROR: no PASS/FAIL banner reported by $tb"
                incr functional_failures
            }
        }
    }

    puts ""
    puts "==== '$suite' regression finished; launch/runtime failures: $launch_failures; functional failures: $functional_failures ===="
}

proc list_regression_suites {} {
    foreach suite [lsort [array names ::ooo_regression::suites]] {
        puts "$suite: $::ooo_regression::suites($suite)"
    }
}
