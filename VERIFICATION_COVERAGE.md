# Verification Coverage Matrix

This document maps architectural requirements to executable evidence. It is a
requirements-coverage matrix, not a claim of formal proof or code coverage.

Status definitions:

- **Covered**: explicit directed, differential, or long-program checking exists.
- **Partial**: the feature executes, but an important corner or semantic rule is
  not directly checked.
- **Gap**: no sufficient end-to-end checker currently exists.
- **N/A**: intentionally unsupported by the current microarchitecture.

## RV32I Instructions

| Instruction or family | Status | Primary evidence | Notes |
| --- | --- | --- | --- |
| `LUI`, `AUIPC` | Covered | `tb_top_packet_backend_rv32i_smoke`, `tb_top_packet_backend_long_stress` | Result and retirement stream checked |
| `JAL` | Covered | `tb_top_packet_backend_multi_issue_suite`, `tb_top_packet_backend_long_stress` | Includes lane1 JAL and link value |
| `JALR` | Covered | `tb_top_packet_backend_multi_issue_suite`, `tb_top_packet_backend_25test` | Includes lane1 JALR, target-cache miss, dependency, and redirect |
| `BEQ`, `BNE` | Covered | `tb_top_packet_backend_25test`, `tb_top_packet_backend_long_stress` | Taken and not-taken behavior |
| `BLT`, `BGE`, `BLTU`, `BGEU` | Covered | `tb_top_packet_backend_rv32i_smoke`, `tb_top_packet_backend_25test` | Signed and unsigned comparisons |
| `LB`, `LH`, `LW`, `LBU`, `LHU` | Covered | `tb_top_packet_backend_rv32i_smoke`, `tb_lsu_commit_store` | Sign/zero extension and ordered loads |
| `SB`, `SH`, `SW` | Covered | `tb_top_packet_backend_rv32i_smoke`, `tb_lsu_commit_store` | Byte enables, merge, commit gating, and forwarding |
| `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI` | Covered | `tb_top_packet_backend_rv32i_smoke`, `tb_top_packet_backend_long_stress` | Directed and long-program execution |
| `SLLI`, `SRLI`, `SRAI` | Covered | `tb_top_packet_backend_rv32i_smoke`, `tb_top_packet_backend_25test` | Logical and arithmetic shifts |
| `ADD`, `SUB`, `SLL`, `SLT`, `SLTU` | Covered | `tb_top_packet_backend_rv32i_smoke`, `tb_top_packet_backend_long_stress` | Integrated OoO execution |
| `XOR`, `SRL`, `SRA`, `OR`, `AND` | Covered | `tb_top_packet_backend_rv32i_smoke`, `tb_top_packet_backend_25test` | Integrated OoO execution |
| `FENCE` | Covered | `tb_top_packet_backend_fence_smoke` | Serialized after older retirement and LSU/cache drain |
| `FENCE.I` | Covered | `tb_top_packet_backend_fence_smoke` | Same serialization rule; no I-cache invalidation is required because this core has no I-cache |

## RV32F Instructions

| Instruction or family | Status | Primary evidence | Notes |
| --- | --- | --- | --- |
| `FLW`, `FSW` | Covered | `tb_fp_memory_bridge_smoke`, `tb_top_packet_backend_fp_memory_smoke` | FP register domain, precise stores, squash safety |
| `FADD.S`, `FSUB.S` | Covered | `tb_fp_add_sub_unit`, `tb_top_packet_backend_fp_add_sub_smoke`, `tb_fp_softfloat_diff` | All rounding modes and exception flags |
| `FMUL.S` | Covered | `tb_fp_mul_unit`, `tb_top_packet_backend_fp_pipeline_smoke`, `tb_fp_softfloat_diff` | Special values, rounding, integrated pipeline |
| `FDIV.S`, `FSQRT.S` | Covered | `tb_fp_div_sqrt_unit`, `tb_fp_div_sqrt_iterative`, `tb_top_packet_backend_fp_div_sqrt_smoke`, `tb_fp_softfloat_diff` | Multi-cycle backpressure and squash |
| `FMADD.S`, `FMSUB.S`, `FNMSUB.S`, `FNMADD.S` | Covered | `tb_fp_fma_unit`, `tb_top_packet_backend_fp_fma_smoke`, `tb_fp_softfloat_diff` | Three-source rename and single rounding |
| `FSGNJ.S`, `FSGNJN.S`, `FSGNJX.S` | Covered | `tb_fp_simple_unit`, `tb_top_packet_backend_fp_simple_smoke` | Bit-exact sign operations |
| `FMIN.S`, `FMAX.S` | Covered | `tb_fp_simple_unit`, `tb_top_packet_backend_fp_simple_smoke` | NaNs and signed zero |
| `FEQ.S`, `FLT.S`, `FLE.S` | Covered | `tb_fp_simple_unit`, `tb_top_packet_backend_fp_simple_smoke`, `tb_fp_softfloat_diff` | Integer destination and invalid flag behavior |
| `FCVT.W.S`, `FCVT.WU.S` | Covered | `tb_fp_convert_unit`, `tb_top_packet_backend_fp_convert_smoke`, `tb_fp_softfloat_diff` | Rounding and saturation |
| `FCVT.S.W`, `FCVT.S.WU` | Covered | `tb_fp_convert_unit`, `tb_top_packet_backend_fp_convert_smoke`, `tb_fp_softfloat_diff` | Cross-domain dependencies |
| `FMV.X.W`, `FMV.W.X`, `FCLASS.S` | Covered | `tb_fp_simple_unit`, `tb_top_packet_backend_fp_simple_smoke` | Raw bit moves and classification |
| Dynamic rounding through `frm` | Covered | `tb_top_packet_backend_fp_add_sub_smoke`, `tb_fp_softfloat_diff` | `rm=111` path |
| `fflags`, `frm`, `fcsr` | Covered | `tb_fp_infrastructure_smoke`, `tb_top_packet_backend_fp_flags_smoke` | Sticky and precise retirement updates |
| `mstatus.FS=Off` enforcement | Covered | `tb_top_packet_backend_fp_fs_smoke` | Default-Off reset, both issue slots, arithmetic/move, FLW, FSW, and FP CSR accesses trap precisely with no FP or memory side effects |

## CSR, Exceptions, and Interrupts

| Feature | Status | Primary evidence | Notes |
| --- | --- | --- | --- |
| `CSRRW`, `CSRRS`, `CSRRC` | Covered | `tb_top_csr_smoke` | Read/modify/write behavior |
| `CSRRWI`, `CSRRSI`, `CSRRCI` | Covered | `tb_top_csr_smoke` | Immediate forms and old-value return |
| Illegal CSR access | Covered | `tb_top_csr_illegal_smoke`, `tb_top_packet_backend_privilege_smoke` | Unimplemented and insufficient-privilege accesses report `mcause=2` with the instruction in `mtval` |
| U/M privilege transitions | Covered | `tb_top_packet_backend_privilege_smoke` | M-mode bootstrap, `MRET` entry to U-mode, trap entry to M-mode, and return to U-mode |
| U-mode and M-mode `ECALL` | Covered | `tb_top_packet_backend_privilege_smoke`, `tb_top_packet_backend_trap_smoke` | Causes 8 and 11 respectively |
| Privileged `MRET` behavior | Covered | `tb_top_packet_backend_privilege_smoke`, `tb_top_packet_backend_trap_smoke` | U-mode `MRET` is illegal; legal return flushes younger frontend, queues, branch pipeline, LSU, and FP work |
| PMP CSR WARL and Lock behavior | Covered | `tb_top_packet_backend_pmp_smoke` | `pmpcfg0`-`pmpcfg3`, `pmpaddr0`-`pmpaddr15`, per-entry Lock, and locked-TOR predecessor locking |
| U-mode PMP instruction/load/store permissions | Covered | `tb_top_packet_backend_pmp_smoke` | X, R, and W denial generate precise causes 1, 5, and 7 with the fault address in `mtval` |
| M-mode PMP enforcement | Covered | `tb_top_packet_backend_pmp_smoke` | Unlocked restrictive entries are bypassed, locked permissions are enforced, and partial matches still fault |
| `mstatus.MPRV` effective privilege | Covered | `tb_top_packet_backend_pmp_smoke` | M-mode load/store PMP checks use `MPP` while instruction fetch remains at the current privilege |
| Multi-entry PMP priority and address modes | Covered | `tb_top_packet_backend_pmp_smoke` | Sixteen entries, OFF/TOR/NA4/NAPOT, entry15 end-to-end access, lowest-numbered priority, and partial-overlap failure |
| `EBREAK` | Partial | decode/trap RTL | No dedicated end-to-end breakpoint test remains |
| Illegal instruction | Covered | `tb_top_illegal_smoke` | `mepc`, `mcause`, and `mtval` |
| Instruction/load/store address misaligned | Covered | `tb_top_misaligned_smoke` | All three causes and fault address |
| Instruction/load/store access fault | Covered | `tb_top_packet_backend_access_fault_smoke` | Configured instruction and data windows, precise `mepc`/`mcause`/`mtval` |
| `mtvec` direct and vectored modes | Covered | `tb_top_mtvec_mode_smoke` | Exception base and interrupt vector |
| Trap-entry `MIE/MPIE/MPP` and `MRET` restore | Covered | `tb_top_packet_backend_privilege_smoke`, `tb_top_packet_backend_trap_smoke`, `tb_top_packet_backend_interrupt_smoke` | Entry, previous privilege, and return state checked |
| Machine software interrupt | Covered | `tb_top_interrupt_sources_smoke` | Cause, enable, entry, return |
| Machine timer interrupt | Covered | `tb_top_interrupt_sources_smoke` | Cause, enable, entry, return |
| Machine external interrupt | Covered | `tb_top_packet_backend_interrupt_smoke` | End-to-end handler path |
| Level-sensitive interrupt pending/retrigger | Covered | `tb_top_packet_backend_wfi_level_irq_smoke` | A held external source remains pending across trap entry and retriggers after `MRET`; deassertion clears `mip` |
| Interrupt priority: external > software > timer | Covered | `tb_top_interrupt_sources_smoke` | Simultaneous pending sources |
| Precise interrupt with non-empty ROB | Covered | `tb_top_packet_backend_precise_interrupt_smoke` | Interrupts an incomplete cache-miss load, checks head-PC `mepc`, flush, `MRET` replay, and exactly-once handler state |
| Nested interrupts | Covered | `tb_top_packet_backend_nested_interrupt_smoke` | External interrupt nests a software interrupt after the outer handler saves context and reenables `MIE`; both `MRET` paths and restored trap state are checked |
| Exception versus interrupt arbitration | Covered | `tb_top_packet_backend_exception_interrupt_priority` | Synchronous exception wins over a simultaneously pending interrupt |
| `WFI` sleep and wakeup | Covered | `tb_top_packet_backend_wfi_level_irq_smoke` | No retirement while asleep; globally enabled source wakes and traps; locally enabled source with `MIE=0` wakes without a trap |

## Multi-Issue and Recovery

| Scenario | Status | Primary evidence | Notes |
| --- | --- | --- | --- |
| Two-wide fetch, decode, rename, and dispatch | Covered | `tb_fetch_packet_stage`, `tb_decode_packet_stage`, `tb_rename_packet_stage`, `tb_dispatch_packet_stage_dual_issue` | Includes backpressure |
| Same-packet RAW and WAW rename | Covered | `tb_rename_packet_stage`, `tb_rename_dispatch_packet_smoke` | Lane0-to-lane1 bypass |
| `ALU + ALU` issue/writeback | Covered | `tb_rs_2issue`, `tb_top_packet_backend_multi_issue_suite` | Independent lane1 completion |
| `MEM + ALU` issue | Covered | `tb_issue_packet_arbiter`, `tb_top_packet_backend_multi_issue_suite` | One memory slot plus ALU |
| `branch + ALU` issue | Covered | `tb_issue_packet_arbiter`, `tb_top_packet_backend_multi_issue_suite` | Branch remains older lane |
| `branch + MEM` issue | Covered | `tb_top_packet_backend_multi_issue_suite` | Includes dependent load consumer |
| `MEM + MEM` issue | Covered | `tb_issue_packet_arbiter`, `tb_top_packet_backend_mem_mem_dual_issue_smoke` | Two AGUs, two LSU requests, two completions, and in-order retirement |
| `branch + branch` issue | N/A | architectural limit | One branch unit and one checkpoint allocation per packet |
| Dual completion and dual commit | Covered | `tb_execution_stage_dual_alu`, `tb_rob_2w`, `tb_top_packet_backend_multi_issue_suite` | Adjacent in-order retirement |
| Lane1 branch/JAL/JALR | Covered | `tb_top_packet_backend_multi_issue_suite` | Prediction, link, and redirect |
| Branch mispredict recovery | Covered | `tb_top_packet_backend_branch_mispredict_smoke`, `tb_top_packet_backend_25test` | RAT/checkpoint restoration |
| Lane1 wrong-path issue/writeback squash | Covered | `tb_top_packet_backend_lane1_squash_smoke` | Speculative physical write is prevented from retiring |
| Long FP operation squash | Covered | `tb_fp_div_sqrt_iterative`, `tb_fp_execution_pipeline` | Cancellation under branch recovery |
| Checkpoint exhaustion/backpressure | Partial | `tb_top_phase6_multi_checkpoint`, `tb_top_packet_backend_25test` | Directed coverage exists; long randomized saturation is absent |

## Memory Hierarchy

| Feature | Status | Primary evidence | Notes |
| --- | --- | --- | --- |
| D-cache hit, miss, refill, and replacement | Covered | `tb_data_cache_smoke` | Two-way cache behavior |
| Dirty victim writeback | Covered | `tb_data_cache_smoke` | Write-back path |
| Two-bank concurrent hits and misses | Covered | `tb_data_cache_dual_bank` | Independent bank-local refill/writeback state |
| Same-bank request conflict | Covered | `tb_data_cache_dual_bank` | Deterministic port-0 priority and retry |
| Split load/store queues and age ordering | Covered | `tb_load_store_queue` | Dual enqueue/issue, monotonic sequence age, and unresolved-store masks |
| Oldest-first legacy memory scheduling | Covered | `tb_memory_order_queue` | Compatibility queue ordering and backpressure |
| Two outstanding loads and dual completion | Covered | `tb_lsu_nonblocking_2p` | Independent cache banks and physical-register writeback |
| Non-alias load bypass | Covered | `tb_lsu_commit_store` | Bypasses older unrelated store |
| Full and byte-granular store forwarding | Covered | `tb_lsu_commit_store` | Youngest overlapping byte wins |
| Partial-overlap load stall | Covered | `tb_lsu_commit_store` | Waits until committed store drains |
| Commit-gated store visibility | Covered | `tb_lsu_commit_store`, `tb_fp_memory_bridge_smoke` | Integer and FP stores |
| Wrong-path store suppression | Covered | `tb_lsu_commit_store`, `tb_top_packet_backend_lane1_squash_smoke` | No cache/backing-memory side effect |
| Two concurrent cache misses | Covered | `tb_data_cache_dual_bank`, `tb_lsu_nonblocking_2p` | One active miss tracker per bank |
| Multiple same-bank misses | N/A | architectural limit | A bank accepts one miss transaction at a time |
| Speculative load violation detection/replay | Covered | `tb_load_store_queue`, `tb_top_packet_backend_memory_replay_smoke`, `tb_top_packet_backend_long_stress` | Sticky oldest-first replay survives concurrent violations, blocks retirement, restores committed state, flushes, and restarts at the load |
| I-cache coherency and shared memory arbitration | Gap | none | No production I-cache/D-cache shared bus |

## Long-Program and Differential Evidence

| Campaign | Status | Evidence | Scope |
| --- | --- | --- | --- |
| Deterministic RV32I long stress | Covered | `tb_top_packet_backend_long_stress` | 10K-class static image, ordered retirement oracle, final GPR state |
| Multi-seed RV32I stress | Covered | stress seeds documented in `README.md` | More than 41K dynamic retirements |
| RV32F SoftFloat differential | Covered | `tb_fp_softfloat_diff` | 10,880 deterministic vectors, result bits and flags |
| Controlled 1-wide versus 2-wide IPC | Covered | `tb_top_packet_backend_ipc_compare` | Independent ALU, dependency chain, MEM+ALU |
| Official architectural certification | Gap | not in the active release flow | No official ACT pass is claimed |
| Constrained-random UVM generation | N/A | not in active flow | `riscv-dv` requires a supported UVM simulator |

## Simulation Invariants

The following immediate assertions are active in simulation and removed by
`SYNTHESIS`:

| State domain | Invariants |
| --- | --- |
| ROB | occupancy equals valid entries; head validity; legal dual commit; push capacity; unique packet tags |
| Integer RAT | x0 maps to p0; p0 remains mapped; nonzero destinations never allocate p0; dual allocations differ |
| Integer free pool | bounded count; legal allocation/pop; disjoint mapped/free/allocated sets; unique dual allocation |
| Checkpoints | one branch allocation per packet; no active-ID reuse; no self or inactive dependencies |
| LSQ | lane1 issue requires lane0; replay clears on full flush; age and unresolved-store masks are checked by directed tests |
| Store buffer and LSU | only committed, live stores reach memory; squashed stores cannot commit or send; duplicate completion tags are forbidden |
| Banked D-cache | an even set count is required; two requests can never be accepted into the same bank in one cycle |
| Retirement | lane1 requires lane0; consecutive order numbers; unique dual-retire tags; integer x0 is never reported written |
| Memory replay | a violating load in either retirement lane cannot commit normally |

These checks detect internal corruption at the first violating cycle rather
than waiting for a final architectural mismatch.

## Release Gate

Before an architecture milestone or GitHub release:

```tcl
source scripts/run_regression.tcl
run_regression full
run_regression performance
run_regression stress
```

The release is acceptable only when every testbench prints its own `PASS`
banner, the Tcl helper reports zero launch/runtime failures, and no assertion
error appears in the XSim console.
