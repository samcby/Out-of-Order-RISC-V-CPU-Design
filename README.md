# Out-of-Order RV32I CPU Design

This repository contains a Vivado/SystemVerilog implementation of an
out-of-order RV32I RISC-V CPU. The project began as a staged academic CPU
design and has been extended into a more complete OoO microarchitecture with
register renaming, speculative execution, branch prediction, machine-mode CSRs,
traps, interrupts, exceptions, a write-back D-cache, and an active 2-wide
multi-issue backend upgrade path.

`top_packet_backend.sv` is the current primary integration top and is selected
as the Vivado project design top. The original `top.sv` path remains available
as a legacy compatibility target for scalar-oriented validation. The packetized
backend implements the current multi-issue work: 2-wide fetch/decode transport,
2-wide rename/dispatch/ROB allocation, dual writeback, dual commit, and selected
true dual-issue combinations.

## Current Highlights

- Out-of-order backend with a packetized 2-wide upgrade path
- 2-wide fetch/decode packet transport in the packet backend
- 2-wide rename allocation with intra-packet dependency bypass
- 2-wide ROB allocation and dual in-order commit
- Dual physical-register writeback support
- True dual-issue support for selected FU combinations, including branch+ALU, ALU+ALU, and MEM+ALU
- RV32I integer instruction coverage used by the validation suite
- Register renaming with a physical register file
- Reservation-station based scheduling
- Reorder-buffer based in-order commit
- Branch speculation with checkpointed rename recovery
- BHT, BTB, and JALR target prediction
- Machine-mode CSR support
- ECALL, EBREAK, MRET, trap entry, and trap return
- Machine software, timer, and external interrupts
- Interrupt priority: external > software > timer
- `mtvec` direct and vectored modes
- Synchronous exception support for illegal instructions and misaligned access
- Request/response LSU memory path
- 2-way set-associative write-back D-cache
- 4-word cache lines with multi-beat refill and dirty writeback
- Directed cache smoke tests for hit/miss, spatial locality, replacement, and writeback behavior

## Microarchitecture

### Frontend and Prediction

The original frontend fetches one instruction at a time and includes
lightweight branch prediction structures. The packet backend adds a 2-wide
fetch packet stage that can carry two sequential instructions when the first
lane is not a control-flow instruction.

- BHT for conditional branch direction prediction
- BTB for direct branch and jump targets
- JALR target cache for indirect jump target prediction
- Redirect handling for branch recovery, traps, interrupts, and MRET

### Rename and Speculation

The rename stage maps architectural registers to physical registers and
supports speculative execution through checkpoints.

- RAT-based architectural-to-physical register mapping
- Free physical register pool
- Old physical register reclamation at commit
- Multiple checkpoint support for unresolved branches
- Speculation masks for selective squash and checkpoint resolution
- Packet rename path with two physical-register allocations per cycle
- Intra-packet RAW/WAW handling so lane1 can see lane0 rename results

### Dispatch, Scheduling, and Execution

Instructions are dispatched into a ROB and functional-unit specific reservation
stations. Ready operations can issue out of program order, while architectural
state is retired in order.

- ALU reservation station
- Load/store reservation station
- Branch reservation station
- Issue arbitration across functional units
- ALU, branch, LSU, and CSR/system execution paths
- LSU request/response protocol for variable-latency memory responses
- Packet dispatch path with 2-wide ROB enqueue
- Packet issue arbitration for paired issue when FU constraints allow it
- Lane1 ALU execution path with independent writeback
- Conservative single-issue handling for CSR/system operations

Current packet backend issue combinations include:

- `branch + ALU`
- `ALU + ALU`
- `MEM + ALU`
- single ALU
- single MEM
- single branch
- single CSR/system operation

Memory operations remain restricted to lane0 because the design still has a
single LSU request path. This gives useful dual-issue throughput without
introducing a second memory port, a full LSQ, or memory-ordering hazards yet.

### Commit and Recovery

The ROB maintains in-order retirement and completion tracking.

- In-order commit
- ROB completion updates from ALU/LSU/branch paths
- Branch squash of wrong-path instructions
- Separate handling for branch recovery versus trap/interrupt redirect
- Commit-time physical register reclamation
- Packet backend dual commit for two adjacent completed ROB entries
- Dual old-physical-register return to the free pool

## ISA Support

The project targets RV32I integer behavior for the current validation suite.

### Integer and Control-Flow Instructions

Supported instruction groups include:

- R-type ALU: `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and`
- I-type ALU: `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai`
- Upper immediates: `lui`, `auipc`
- Branches: `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu`
- Jumps: `jal`, `jalr`
- Loads: `lb`, `lh`, `lw`, `lbu`, `lhu`
- Stores: `sb`, `sh`, `sw`
- Fence treated as a no-op for this prototype

### CSR and System Instructions

The core supports the CSR instruction forms used by the machine-mode tests:

- `csrrw`, `csrrs`, `csrrc`
- `csrrwi`, `csrrsi`, `csrrci`
- `ecall`
- `ebreak`
- `mret`

Implemented machine CSRs:

- `mstatus`
- `mie`
- `mtvec`
- `mepc`
- `mcause`
- `mtval`
- `mip`

CSR legality checks are performed during decode. Accesses to unimplemented
CSRs are converted into illegal-instruction traps.

## Trap, Exception, and Interrupt Support

The CPU includes a machine-mode trap skeleton suitable for the current OoO
prototype.

### Trap Entry

On trap or interrupt entry:

- `mepc` is written with the faulting or interrupted PC
- `mcause` is written with the trap cause
- `mtval` is written with the instruction or address when applicable
- `mstatus.MPIE` receives the previous `mstatus.MIE`
- `mstatus.MIE` is cleared
- `mstatus.MPP` is set to machine mode

### MRET

On `mret`:

- `mstatus.MIE` is restored from `mstatus.MPIE`
- `mstatus.MPIE` is set
- `mstatus.MPP` is cleared
- Fetch redirects to `mepc`

### Interrupts

Supported machine interrupts:

- Machine software interrupt: `mcause = 0x80000003`
- Machine timer interrupt: `mcause = 0x80000007`
- Machine external interrupt: `mcause = 0x8000000b`

Current priority:

1. Machine external interrupt
2. Machine software interrupt
3. Machine timer interrupt

Interrupts are taken at a ROB-empty safe point in this prototype. This keeps
the current implementation simple and avoids introducing a full commit-time
interrupt injection mechanism before the next major architecture stage.

### Exceptions

Supported synchronous exceptions:

- Instruction address misaligned: `mcause = 0`
- Illegal instruction: `mcause = 2`
- Breakpoint: `mcause = 3`
- Load address misaligned: `mcause = 4`
- Store address misaligned: `mcause = 6`
- ECALL from machine mode: `mcause = 11`

### MTVEC Modes

The implementation supports:

- Direct mode: `mtvec[1:0] = 00`
- Vectored mode: `mtvec[1:0] = 01`

For synchronous exceptions, the target is always `BASE = mtvec & ~3`.
For interrupts in vectored mode, the target is `BASE + 4 * cause`.

## Memory System

The memory subsystem has been upgraded from a simple combinational array into a
request/response path with a small write-back D-cache.

### LSU and Memory Request Path

The LSU now issues explicit memory requests and waits for memory responses.
This allows the rest of the backend to tolerate variable-latency memory access.

Current LSU behavior:

- One pending memory operation at a time
- Request/response protocol between LSU and D-cache
- Branch squash support for wrong-path memory operations
- Load response writeback through the normal ROB completion path
- Store completion after cache/memory acknowledgement

Because the project does not yet include a full load-store queue, the LSU
reservation station is intentionally constrained to avoid younger loads
bypassing older stores.

### D-cache

The D-cache is a small blocking cache designed to exercise realistic cache
control behavior without introducing non-blocking MSHR complexity yet.

Current D-cache features:

- 2-way set-associative organization
- Configurable total line count
- Configurable words per line
- Default 4-word cache lines
- Valid, tag, dirty, and data arrays per set/way
- 1-bit pseudo-LRU style replacement per set
- Write-back store policy
- Dirty victim writeback
- Multi-beat refill from backing memory
- Multi-beat dirty line writeback
- Hit, miss, and writeback counters for directed validation

The current structure is:

```text
LSU -> D-cache -> data_memory
```

The next memory-system refinement would be to decouple `data_memory` from the
D-cache and introduce a shared memory interface or arbiter. That would prepare
the design for I-cache/D-cache sharing, memory-mapped IO, and bus-style
backpressure. For now, the current D-cache is sufficient to move on to the
multi-issue CPU architecture stage.

## Project Structure

Main RTL sources:

```text
OoO_RISC_V_CPU_DESIGN.srcs/sources_1/new
```

Important modules:

- `top_packet_backend.sv`: primary packetized 2-wide backend integration top
- `top.sv`: legacy scalar-oriented CPU integration path
- `defines_pkg.sv`: shared parameters, control structs, constants
- `fetch_stage.sv`: fetch, prediction, redirect control
- `fetch_packet_stage.sv`: 2-wide packet fetch stage
- `fetch_packet_adapter.sv`: compatibility adapter from scalar fetch to packet transport
- `decode_controller.sv`: instruction decode and legality checks
- `decode_stage.sv`: decode pipeline stage
- `decode_lane.sv`: reusable per-lane decode logic
- `decode_packet_stage.sv`: 2-wide packet decode stage
- `rename_stage.sv`: RAT, free-list, and checkpoint handling
- `rename_packet_stage.sv`: 2-wide rename and checkpoint allocation
- `RAT_2w.sv`: 2-wide register alias table
- `free_pool_2w.sv`: 2-wide physical-register free pool
- `dispatch_stage.sv`: ROB/RS dispatch and CSR serialization
- `dispatch_logic.sv`: dispatch routing
- `dispatch_packet_stage.sv`: packet dispatch, 2-wide ROB enqueue, and issue arbitration
- `dispatch_packet_logic.sv`: per-packet dispatch routing
- `rs.sv`: reservation station
- `rob.sv`: reorder buffer
- `rob_2w.sv`: 2-wide allocation/completion/commit reorder buffer
- `issue_packet_arbiter.sv`: packet issue selection across ALU, LSU, and branch RS outputs
- `execution_stage.sv`: ALU/LSU/branch/CSR integration
- `csr_file.sv`: machine CSR state and trap entry/return behavior
- `branch.sv`: branch resolution and target generation
- `lsu.sv`: load/store unit with request/response cache interface
- `data_cache.sv`: 2-way write-back D-cache
- `data_memory.sv`: variable-latency backing memory model
- `reg_file.sv`: physical register file
- `RAT.sv`: register alias table
- `free_pool.sv`: physical register free list

Simulation sources:

```text
OoO_RISC_V_CPU_DESIGN.srcs/sim_1/new
```

## Validation Status

The design has been tested with Vivado Simulator 2019.1.

For a compact, milestone-oriented test checklist, see
[`REGRESSION.md`](REGRESSION.md).

### Recommended Regression Sets

For day-to-day development, the following groups are the most useful smoke
regressions.

#### Packet Backend Quick Regression

Run these after most packet-backend changes:

```text
tb_fetch_packet_stage
tb_decode_packet_stage
tb_rs_2issue
tb_issue_packet_arbiter
tb_dispatch_packet_stage_dual_issue
tb_top_packet_backend_rv32i_smoke
tb_top_packet_backend_25test
```

#### Multi-Issue Datapath Regression

Run these after changes to rename, dispatch, issue, execution, PRF, or ROB
logic:

```text
tb_reg_file_2w
tb_rob_2w
tb_rename_dispatch_packet_smoke
tb_top_packet_backend_alu_alu_dual_issue_smoke
tb_top_packet_backend_alu_mem_dual_issue_smoke
tb_top_packet_backend_dual_commit_smoke
tb_top_packet_backend_lane1_wakeup_smoke
tb_top_packet_backend_lane1_squash_smoke
tb_top_packet_backend_perf_counter_smoke
```

#### Control, Trap, and Interrupt Regression

Run these after redirect, branch, CSR, trap, interrupt, or checkpoint changes:

```text
tb_top_packet_backend_branch_mispredict_smoke
tb_top_packet_backend_trap_smoke
tb_top_packet_backend_interrupt_smoke
tb_top_trap_smoke
tb_top_interrupt_smoke
tb_top_interrupt_sources_smoke
```

#### Memory Regression

Run these after LSU, cache, memory, store, or load-alignment changes:

```text
tb_data_cache_smoke
tb_top_rv32i_smoke
tb_top_misaligned_smoke
tb_top_packet_backend_rv32i_smoke
tb_top_packet_backend_alu_mem_dual_issue_smoke
```

### Core RV32I and Trace Tests

Passing smoke and trace tests include:

- `tb_top_rv32i_smoke`
- `tb_trace_25r`
- `tb_trace_25test`
- `tb_trace_25swr`
- `tb_trace_25jswr`

### CSR, Trap, Exception, and Interrupt Tests

Passing validation tests include:

- `tb_top_csr_smoke`
- `tb_top_csr_illegal_smoke`
- `tb_top_trap_smoke`
- `tb_top_interrupt_smoke`
- `tb_top_interrupt_sources_smoke`
- `tb_top_illegal_smoke`
- `tb_top_misaligned_smoke`
- `tb_top_mtvec_mode_smoke`

### Cache and Memory Tests

Passing memory-system validation includes:

- `tb_data_cache_smoke`

This directed cache test covers:

- load miss and line refill
- same-line hit after refill
- store hit into a dirty line
- 2-way same-set residency
- pseudo-LRU replacement behavior
- dirty victim writeback
- multi-word line writeback correctness

### Packet Backend and Multi-Issue Tests

Passing packet-backend validation includes:

- `tb_fetch_packet_adapter`
- `tb_fetch_packet_stage`
- `tb_decode_packet_stage`
- `tb_decode_packet_lane0_adapter`
- `tb_rename_packet_stage`
- `tb_reg_alias_table_2w`
- `tb_free_pool_2w`
- `tb_reg_file_2w`
- `tb_rob_2w`
- `tb_dispatch_packet_logic`
- `tb_dispatch_packet_stage`
- `tb_dispatch_packet_stage_dual_issue`
- `tb_issue_packet_arbiter`
- `tb_rs_2issue`
- `tb_execution_stage_dual_alu`
- `tb_execution_stage_branch_lane1_complete`
- `tb_rat_dis_packet_splitter`
- `tb_rename_dispatch_packet_smoke`
- `tb_top_packet_backend_rv32i_smoke`
- `tb_top_packet_backend_25test`
- `tb_top_packet_backend_trap_smoke`
- `tb_top_packet_backend_interrupt_smoke`
- `tb_top_packet_backend_dual_alu_smoke`
- `tb_top_packet_backend_dual_commit_smoke`
- `tb_top_packet_backend_alu_alu_dual_issue_smoke`
- `tb_top_packet_backend_alu_mem_dual_issue_smoke`
- `tb_top_packet_backend_perf_counter_smoke`
- `tb_top_packet_backend_branch_mispredict_smoke`
- `tb_top_packet_backend_lane1_squash_smoke`
- `tb_top_packet_backend_lane1_wakeup_smoke`

These tests cover:

- 2-wide packet transport and backpressure
- 2-wide decode and lane validity
- 2-wide rename allocation
- same-packet rename bypass
- 2-wide ROB allocation and completion
- dual writeback into the physical register file
- lane1 ALU wakeup of dependent RS entries
- independent lane1 ALU completion alongside branch completion
- dual in-order commit and dual free-list return
- branch+ALU dual issue
- ALU+ALU dual enqueue and dual issue through the 2-issue ALU reservation station
- age-prioritized ready selection in the 2-issue ALU reservation station
- MEM+ALU dual issue with MEM on lane0 and ALU on lane1
- packet-backend performance counters for fetch, rename, dispatch, issue mix, writeback, commit, and stalls
- integrated performance smoke coverage for branch+ALU, ALU+ALU, and MEM+ALU dual issue
- packet-backend CSR/system single-issue serialization during trap and interrupt flows
- lane1 branch decode/dispatch into the branch RS and redirect recovery
- wrong-path lane1 execution followed by precise squash
- packet backend compatibility with RV32I, trap, interrupt, and 25test programs

### Speculation and Predictor Tests

Earlier staged tests cover:

- speculative execution and squash
- redirect/recovery behavior
- JAL prediction
- JALR prediction
- BHT training
- BTB behavior
- multiple simultaneous checkpoints

Representative tests:

- `tb_top_phase4_speculative`
- `tb_top_phase4_redirect`
- `tb_top_phase5_jal_predictor`
- `tb_top_phase5_jalr_predictor`
- `tb_top_phase5_bht_training`
- `tb_top_phase5_btb`
- `tb_top_phase6_multi_checkpoint`

## How to Open and Run

Open the Vivado project file:

```text
OoO_RISC_V_CPU_DESIGN.xpr
```

Recommended tool version:

```text
Vivado 2019.1
```

The `sources_1` design top is expected to be:

```text
top_packet_backend
```

Use `top.sv` only when intentionally validating the older scalar integration
path.

Typical simulation flow:

1. Open the project in Vivado.
2. Set the desired testbench as the simulation top.
3. Launch simulation.
4. Run the generated Tcl script or run manually in the simulator console.

Example simulation tops:

```text
tb_top_rv32i_smoke
tb_data_cache_smoke
tb_top_csr_smoke
tb_top_trap_smoke
tb_top_interrupt_sources_smoke
tb_top_illegal_smoke
tb_top_misaligned_smoke
tb_top_mtvec_mode_smoke
tb_trace_25test
tb_top_packet_backend_rv32i_smoke
tb_top_packet_backend_25test
tb_top_packet_backend_dual_alu_smoke
tb_top_packet_backend_dual_commit_smoke
tb_top_packet_backend_alu_mem_dual_issue_smoke
tb_top_packet_backend_perf_counter_smoke
tb_top_packet_backend_interrupt_smoke
```

## Scope and Limitations

This project is a CPU microarchitecture prototype, not a complete SoC.

Current limitations:

- The original `top.sv` path is still scalar-oriented
- The packet backend is partially 2-wide, not a complete superscalar core yet
- Lane1 currently supports ordinary ALU execution, not memory or CSR/system execution
- Memory operations issue through one LSU path and are placed on lane0
- Blocking D-cache, not non-blocking
- No MSHR support
- No full load-store queue or store-to-load forwarding
- No unified memory arbiter between I-cache and D-cache yet
- No virtual memory
- No full privilege-level stack beyond machine-mode oriented behavior
- Interrupts are taken at a safe ROB-empty point rather than precise commit injection
- Memory ordering and load/store speculation are intentionally simple
- No floating-point extension yet

## Multi-Issue Upgrade Status

The project is now in the controlled multi-issue upgrade stage. The design does
not attempt to become fully superscalar in one jump; instead, each architectural
boundary is widened and validated independently.

Completed packet-backend steps:

- 2-wide instruction packet types and pipeline interfaces
- 2-wide fetch/decode packet transport
- 2-wide rename allocation
- intra-packet dependency handling
- 2-wide ROB allocation
- dispatch into FU-specific reservation stations
- issue packet arbitration
- 2-enqueue/2-issue ALU reservation station path
- age-tagged oldest-ready selection for the 2-issue ALU reservation station
- second ALU execution lane
- dual physical-register writeback
- dual ROB completion ports
- independent lane1 ALU completion port separated from branch resolution completion
- dual in-order commit
- branch+ALU dual issue
- ALU+ALU same-packet dispatch plus dual issue from ready ALU RS entries
- MEM+ALU dual issue using MEM on lane0 and ALU on lane1
- internal performance counters for packet flow, dual issue mix, lane1 writeback, dual writeback, dual commit, and pipeline stalls
- directed wrong-path lane1 squash tests
- directed lane1 wakeup tests

Reasonable next steps:

1. Add broader packet-backend regression tests for mixed RV32I programs.
2. Continue treating `top_packet_backend.sv` as the mainline top-level and keep `top.sv` as a legacy compatibility path.
3. Gradually port any remaining scalar-top tests to packet-backend equivalents when they still provide unique coverage.
4. Consider deeper memory-system work such as a load-store queue or non-blocking D-cache.
5. Begin broader performance-oriented superscalar tuning after the packet backend remains stable across the recommended regressions.

## Repository Notes

The repository is intended to track source RTL, simulation testbenches, the
Vivado project file, and lightweight project metadata. Generated Vivado output
such as `.Xil`, `.runs`, `.sim`, `.cache`, logs, journals, and waveform
databases should not be committed.
