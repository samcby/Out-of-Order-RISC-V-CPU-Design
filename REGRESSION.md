# Regression Guide

The current design top is `top_packet_backend`. Validation targets Vivado
Simulator 2019.1.

## Recommended Workflow

Open `OoO_RISC_V_CPU_DESIGN.xpr`, then source the regression helper from the
Vivado Tcl console:

```tcl
source scripts/run_regression.tcl
list_regression_suites
run_regression quick
```

The helper automatically closes the active simulation, selects each simulation
top, launches XSim, and advances the simulation. It does not delete, disable,
or rewrite any testbench.

Available groups:

| Group | Purpose |
| --- | --- |
| `quick` | Mainline architecture confidence after ordinary RTL changes |
| `multi_issue` | Frontend, rename, issue, execution, writeback, and commit |
| `memory` | Cache, memory ordering, forwarding, and precise stores |
| `full` | Milestone regression before a push or architecture transition |

Every testbench prints its own `PASS` or `FAIL` banner. The Tcl script reports
launch/runtime errors, while assertion results remain visible in the console.

## Consolidated Architecture Test

`tb_top_packet_backend_multi_issue_suite` is the first consolidated
testbench. It reuses one `top_packet_backend` instance and runs three isolated
programs separated by reset:

### Scenario 1: Issue Mix

- `branch + ALU`
- `MEM + ALU`
- `ALU + ALU`
- lane1 writeback
- dependent wakeup
- dual commit
- performance counters

### Scenario 2: Branch + Memory

- branch and memory issue in the same cycle
- slot1 load completion
- dependent load consumer
- ROB drain

### Scenario 3: Lane1 Control Flow

- lane1 conditional branch
- lane1 `JAL`
- lane1 `JALR`
- same-packet lane0-to-lane1 RAW dependency
- JALR target-cache miss wait
- execution redirect
- wrong-path suppression

## Suite Contents

### Quick

```text
tb_top_packet_backend_multi_issue_suite
tb_top_packet_backend_rv32i_smoke
tb_top_packet_backend_25test
tb_top_packet_backend_trap_smoke
tb_top_packet_backend_interrupt_smoke
```

### Multi-Issue

```text
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
```

### Memory

```text
tb_data_cache_smoke
tb_memory_order_queue
tb_lsu_commit_store
tb_top_packet_backend_multi_issue_suite
tb_top_packet_backend_rv32i_smoke
tb_top_misaligned_smoke
```

### Full

```text
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
```

## Retired Integration Tests

After the consolidated suite and `quick` regression passed, the following
duplicated integration smokes were removed:

| Retired test | Replacement coverage |
| --- | --- |
| `tb_top_packet_backend_alu_alu_dual_issue_smoke` | Scenario 1 |
| `tb_top_packet_backend_alu_mem_dual_issue_smoke` | Scenario 1 |
| `tb_top_packet_backend_branch_mem_dual_issue_smoke` | Scenario 2 |
| `tb_top_packet_backend_dual_commit_smoke` | Scenario 1 |
| `tb_top_packet_backend_perf_counter_smoke` | Scenario 1 |
| `tb_top_packet_backend_lane1_control_smoke` | Scenario 3 |

Their checks are represented in
`tb_top_packet_backend_multi_issue_suite`; the Git history remains the source
for recovering an old focused test if a future failure requires it.

### Tests That Should Remain Separate

These tests exercise distinct DUT boundaries or corner cases and should not be
merged merely to reduce the file count:

- `tb_rs_2issue`
- `tb_issue_packet_arbiter`
- `tb_reg_file_2w`
- `tb_rob_2w`
- `tb_memory_order_queue`
- `tb_lsu_commit_store`
- `tb_data_cache_smoke`
- `tb_top_packet_backend_lane1_squash_smoke`
- `tb_top_packet_backend_25test`
- trap and interrupt tests

Keeping these focused makes failures much easier to localize.

## Manual Fallback

If the Tcl runner cannot launch because XSim holds `simulate.log`:

1. Cancel any active `run` command.
2. Execute `catch {close_sim}` in the Vivado Tcl console.
3. Close duplicate Vivado or XSim processes using the same project.
4. Source the script again and rerun the requested group.

Incremental simulation is intentionally disabled for `sim_1` to avoid stale
snapshot restore failures in Vivado 2019.1.
