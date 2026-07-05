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
| `FENCE` | Partial | decode and RV32I smoke path | Treated as a no-op; ordering semantics are not implemented |
| `FENCE.I` | Gap | none | No instruction-cache synchronization mechanism |

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
| `mstatus.FS=Off` enforcement | Gap | none | Software-visible FS state exists, but disabled-state traps are not enforced |

## CSR, Exceptions, and Interrupts

| Feature | Status | Primary evidence | Notes |
| --- | --- | --- | --- |
| `CSRRW`, `CSRRS`, `CSRRC` | Covered | `tb_top_csr_smoke` | Read/modify/write behavior |
| `CSRRWI`, `CSRRSI`, `CSRRCI` | Covered | `tb_top_csr_smoke` | Immediate forms and old-value return |
| Illegal CSR access | Covered | `tb_top_csr_illegal_smoke` | `mcause=2`, instruction in `mtval` |
| `ECALL` and `MRET` | Covered | `tb_top_packet_backend_trap_smoke`, `tb_top_trap_smoke` | Precise entry, handler, and return |
| `EBREAK` | Partial | decode/trap RTL | No dedicated end-to-end breakpoint test remains |
| Illegal instruction | Covered | `tb_top_illegal_smoke` | `mepc`, `mcause`, and `mtval` |
| Instruction/load/store address misaligned | Covered | `tb_top_misaligned_smoke` | All three causes and fault address |
| Instruction/load/store access fault | Gap | none | No protection or bus-fault model |
| `mtvec` direct and vectored modes | Covered | `tb_top_mtvec_mode_smoke` | Exception base and interrupt vector |
| Trap-entry `MIE/MPIE/MPP` and `MRET` restore | Covered | `tb_top_packet_backend_trap_smoke`, `tb_top_packet_backend_interrupt_smoke` | Entry and return state checked |
| Machine software interrupt | Covered | `tb_top_interrupt_sources_smoke` | Cause, enable, entry, return |
| Machine timer interrupt | Covered | `tb_top_interrupt_sources_smoke` | Cause, enable, entry, return |
| Machine external interrupt | Covered | `tb_top_packet_backend_interrupt_smoke` | End-to-end handler path |
| Interrupt priority: external > software > timer | Covered | `tb_top_interrupt_sources_smoke` | Simultaneous pending sources |
| Nested interrupts | Gap | none | Current entry policy waits for a safe ROB-empty boundary |
| Exception versus interrupt arbitration | Partial | trap and interrupt smokes | Each path is checked independently, not in the same cycle |

## Multi-Issue and Recovery

| Scenario | Status | Primary evidence | Notes |
| --- | --- | --- | --- |
| Two-wide fetch, decode, rename, and dispatch | Covered | `tb_fetch_packet_stage`, `tb_decode_packet_stage`, `tb_rename_packet_stage`, `tb_dispatch_packet_stage_dual_issue` | Includes backpressure |
| Same-packet RAW and WAW rename | Covered | `tb_rename_packet_stage`, `tb_rename_dispatch_packet_smoke` | Lane0-to-lane1 bypass |
| `ALU + ALU` issue/writeback | Covered | `tb_rs_2issue`, `tb_top_packet_backend_multi_issue_suite` | Independent lane1 completion |
| `MEM + ALU` issue | Covered | `tb_issue_packet_arbiter`, `tb_top_packet_backend_multi_issue_suite` | One LSU plus ALU |
| `branch + ALU` issue | Covered | `tb_issue_packet_arbiter`, `tb_top_packet_backend_multi_issue_suite` | Branch remains older lane |
| `branch + MEM` issue | Covered | `tb_top_packet_backend_multi_issue_suite` | Includes dependent load consumer |
| `MEM + MEM` issue | N/A | architectural limit | One LSU |
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
| Oldest-first memory scheduling | Covered | `tb_memory_order_queue` | Queue ordering and backpressure |
| Non-alias load bypass | Covered | `tb_lsu_commit_store` | Bypasses older unrelated store |
| Full and byte-granular store forwarding | Covered | `tb_lsu_commit_store` | Youngest overlapping byte wins |
| Partial-overlap load stall | Covered | `tb_lsu_commit_store` | Waits until committed store drains |
| Commit-gated store visibility | Covered | `tb_lsu_commit_store`, `tb_fp_memory_bridge_smoke` | Integer and FP stores |
| Wrong-path store suppression | Covered | `tb_lsu_commit_store`, `tb_top_packet_backend_lane1_squash_smoke` | No cache/backing-memory side effect |
| Multiple outstanding misses | N/A | architectural limit | Blocking cache, no MSHRs |
| Speculative load violation detection/replay | Gap | none | Loads only bypass when current disambiguation permits it |
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
| Store buffer | only committed, live stores reach memory; squashed stores cannot commit or send; writeback implies a valid response |
| Retirement | lane1 requires lane0; consecutive order numbers; unique dual-retire tags; integer x0 is never reported written |

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
