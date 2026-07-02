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
top, re-enables that top when Vivado has persisted it as `AutoDisabled`,
launches XSim, and advances the simulation. It does not delete, disable, or
rewrite any testbench.

Available groups:

| Group | Purpose |
| --- | --- |
| `quick` | Mainline architecture confidence after ordinary RTL changes |
| `multi_issue` | Frontend, rename, issue, execution, writeback, and commit |
| `memory` | Cache, memory ordering, forwarding, and precise stores |
| `performance` | Controlled 1-wide versus 2-wide IPC comparison |
| `softfloat` | Deterministic Berkeley SoftFloat differential vectors |
| `floating` | RV32F infrastructure, memory transport, and exact FP execution |
| `full` | Milestone regression before a push or architecture transition |

Every testbench prints its own `PASS` or `FAIL` banner. The Tcl script reports
launch/runtime errors, while assertion results remain visible in the console.

## Floating-Point Infrastructure

`tb_fp_infrastructure_smoke` is the first RV32F milestone test. It validates:

- FLW/FSW register-file routing
- arithmetic, fused, compare, move, and conversion decode classes
- reserved rounding-mode rejection
- independent floating-point physical registers with two writeback ports
- same-packet floating-point readiness dependencies
- dual-lane FP RAT allocation with same-packet RAW and WAW bypass
- FP RAT/free-pool checkpoint restore
- retirement recycling of initial FP mappings, including `f0`
- writable `f0`
- `fflags`, `frm`, and `fcsr` aliasing and sticky exception flags
- ROB preservation of integer-versus-FP destination metadata
- FLW payload transport through the ordered LSU and cache
- commit-gated FSW visibility and precise squash behavior
- integer and FP physical-register domain isolation during wakeup
- end-to-end FLW/FSW execution through the packet backend
- writable, renamed architectural `f0` in the integrated backend
- exact sign-injection, min/max, comparison, classification, and bit-move execution
- integer/FP cross-domain dependencies through the integrated packet backend
- ROB-carried FP exception metadata and retirement-only `fflags` updates
- suppression of exception flags from squashed speculative FP operations
- rounded `FADD.S`/`FSUB.S` across all five static rounding modes
- rounded and saturating signed/unsigned `FCVT` operations in both directions
- `FDIV.S` and `FSQRT.S` special cases, rounding, and subnormal handling
- shared long-latency busy/backpressure and speculative squash behavior
- all four three-source fused multiply-add sign variants
- proof that fused execution preserves product bits until the single rounding
- third-source RAT, PRF, RS readiness, and wakeup behavior
- dynamic rounding through `frm`
- software-visible `fflags`, `frm`, and `fcsr` CSR accesses
- 10,880 SoftFloat differential vectors across all arithmetic rounding modes

The floating group uses `tb_fp_infrastructure_smoke` for decode, PRF, and CSR
state, `tb_fp_rename_smoke` for speculative rename and recovery, and
`tb_fp_memory_bridge_smoke` for ROB and ordered-memory transport.
`tb_fp_domain_wakeup_smoke` proves that equal integer and FP physical-register
numbers cannot cross-wake. `tb_top_packet_backend_fp_memory_smoke` executes
FLW/FSW from the real packet frontend through rename, dispatch, LSU, ROB,
writeback, and retirement. `tb_fp_simple_unit` checks IEEE-754 bit-level edge
cases, while `tb_top_packet_backend_fp_simple_smoke` executes `FSGNJX.S`,
`FMIN.S`, `FMAX.S`, `FEQ.S`, `FLT.S`, `FLE.S`, `FCLASS.S`, `FMV.X.W`, and
`FMV.W.X` through the integrated 2-wide backend.
`tb_top_packet_backend_fp_flags_smoke` executes a signaling-NaN comparison on
both a squashed path and a committed path to prove precise `NV` updates.
`tb_fp_add_sub_unit` covers finite arithmetic, cancellation, ties, directed
rounding, overflow, NaN, infinity, and subnormal cases.
`tb_top_packet_backend_fp_add_sub_smoke` verifies dynamic rounding, cross-domain
CSR state, precise `NX`, and immediate software readback through the real OoO
backend.
`tb_fp_mul_unit` covers normal, subnormal, overflow, invalid, NaN, and signed
zero multiplication behavior. `tb_fp_execution_pipeline` verifies three-cycle
latency, output backpressure, metadata preservation, and speculative squash.
`tb_top_packet_backend_fp_pipeline_smoke` proves dual-lane FP issue, `FMUL.S`,
and dependent pipelined `FADD.S` execution through the complete backend.
`tb_fp_convert_unit` covers conversion boundaries, saturation, and all rounding
directions, while `tb_top_packet_backend_fp_convert_smoke` verifies integer/FP
cross-domain dependencies and sticky `NX` through the complete backend.
`tb_fp_div_sqrt_unit` covers division, square root, divide-by-zero, invalid
operations, directed rounding, and tiny values. `tb_fp_div_sqrt_iterative`
checks occupancy, result backpressure, and squash cancellation.
`tb_top_packet_backend_fp_div_sqrt_smoke` proves that the shared long-latency
unit coexists with continued integer and short-pipeline FP issue.
`tb_fp_fma_unit` checks all four fused sign variants, special values, and a
single-rounding case that differs from separate multiply/add execution.
`tb_top_packet_backend_fp_fma_smoke` validates three-source rename/read/wakeup,
dual-lane fused issue, and dependent FMA execution through the complete backend.

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

### Performance

```text
tb_top_packet_backend_ipc_compare
```

This test instantiates two otherwise identical packet backends. One uses the
default 2-wide mode and the other sets `ENABLE_2WIDE=0`, disabling the second
fetch lane, second issue slot, and second commit port. A sentinel commit
captures the active-cycle and committed-instruction counters for each core.

Current validated results:

```text
independent_alu:  1.368 IPC vs 0.812 IPC, 1.684x speedup
dependency_chain: 0.481 IPC vs 0.473 IPC, 1.019x speedup
memory_plus_alu:  0.286 IPC vs 0.243 IPC, 1.175x speedup
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
tb_top_packet_backend_ipc_compare
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
