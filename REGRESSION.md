# Regression Guide

This project is validated with Vivado Simulator 2019.1. The current mainline
integration top is `top_packet_backend`.

Before running a regression in Vivado, update compile order if sources were
added or the active simulation top changed:

```tcl
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
```

## Quick Mainline Regression

Run this set after most packet-backend changes:

```text
tb_top_packet_backend_rv32i_smoke
tb_top_packet_backend_25test
tb_top_packet_backend_trap_smoke
tb_top_packet_backend_interrupt_smoke
tb_top_packet_backend_perf_counter_smoke
```

## Multi-Issue Regression

Run this set after changing rename, dispatch, issue, reservation stations,
execution lanes, writeback, ROB completion, or commit:

```text
tb_rs_2issue
tb_issue_packet_arbiter
tb_dispatch_packet_stage_dual_issue
tb_reg_file_2w
tb_rob_2w
tb_rename_dispatch_packet_smoke
tb_top_packet_backend_alu_alu_dual_issue_smoke
tb_top_packet_backend_alu_mem_dual_issue_smoke
tb_top_packet_backend_dual_commit_smoke
tb_top_packet_backend_lane1_wakeup_smoke
tb_top_packet_backend_lane1_squash_smoke
```

## Control and Trap Regression

Run this set after changing branch redirect, checkpoint recovery, CSR/system
execution, trap entry, interrupt entry, or MRET:

```text
tb_top_packet_backend_branch_mispredict_smoke
tb_top_packet_backend_trap_smoke
tb_top_packet_backend_interrupt_smoke
tb_top_trap_smoke
tb_top_interrupt_smoke
tb_top_interrupt_sources_smoke
```

## Memory Regression

Run this set after changing LSU, cache, data memory, load/store decode, or
alignment exception logic:

```text
tb_data_cache_smoke
tb_top_packet_backend_rv32i_smoke
tb_top_packet_backend_alu_mem_dual_issue_smoke
tb_top_misaligned_smoke
```

## Full Milestone Smoke Set

This is the recommended set before pushing a major milestone:

```text
tb_fetch_packet_stage
tb_decode_packet_stage
tb_rs_2issue
tb_issue_packet_arbiter
tb_dispatch_packet_stage_dual_issue
tb_reg_file_2w
tb_rob_2w
tb_rename_dispatch_packet_smoke
tb_data_cache_smoke
tb_top_packet_backend_rv32i_smoke
tb_top_packet_backend_25test
tb_top_packet_backend_trap_smoke
tb_top_packet_backend_interrupt_smoke
tb_top_packet_backend_perf_counter_smoke
tb_top_packet_backend_alu_alu_dual_issue_smoke
tb_top_packet_backend_alu_mem_dual_issue_smoke
tb_top_packet_backend_dual_commit_smoke
tb_top_packet_backend_branch_mispredict_smoke
tb_top_packet_backend_lane1_squash_smoke
```

## Current Milestone Notes

- `top_packet_backend` is the active mainline integration top.
- `top.sv` remains as a legacy scalar-oriented compatibility path.
- Memory operations are still restricted to one LSU path and are issued on
  lane0.
- CSR/system operations are intentionally serialized as single-issue operations.
- The packet backend supports selected true dual-issue combinations:
  `ALU+ALU`, `MEM+ALU`, and `branch+ALU`.
