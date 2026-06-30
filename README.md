# Out-of-Order RV32I CPU Design

This repository contains a SystemVerilog implementation of a speculative,
out-of-order RV32I processor developed in Vivado 2019.1. The current mainline
is a packetized 2-wide superscalar core with register renaming, reservation
stations, precise in-order retirement, branch recovery, machine-mode traps and
interrupts, and a cached memory hierarchy.

The active design top is:

```text
top_packet_backend
```

`top.sv` is retained as a legacy scalar integration path. New architecture
work and full-system validation should target `top_packet_backend.sv`.

## Architecture Summary

The mainline core can transport up to two instructions per cycle through the
frontend and backend:

```text
2-wide fetch
    -> 2-wide decode
    -> 2-wide rename
    -> 2-wide dispatch
    -> FU-specific reservation stations
    -> up to 2 issues per cycle
    -> dual completion/writeback
    -> up to 2 in-order commits per cycle
```

### Frontend

- Two-instruction fetch packets
- Independent lane validity and backpressure
- Lane1 support for conditional branches, `JAL`, and `JALR`
- BHT conditional-branch direction prediction
- BTB direct target prediction
- JALR target cache
- JALR miss wait until the execution target is known
- Redirect support for misprediction, trap, interrupt, and `MRET`

A lane0 control-flow instruction terminates its packet. A control-flow
instruction may occupy lane1 when lane0 is non-control, preserving the older
lane0 instruction while allowing the packet to redirect.

### Rename and Speculation

- RAT-based architectural-to-physical register mapping
- Two physical-register allocations per cycle
- Intra-packet RAW and WAW handling
- Lane0-to-lane1 same-packet rename bypass
- Multiple branch checkpoints
- Per-instruction speculation masks
- Selective wrong-path squash and RAT restoration
- Up to two old physical registers returned at commit

### Scheduling and Execution

- Functional-unit-specific reservation stations
- Two-enqueue/two-issue ALU reservation station
- Oldest-ready scheduling
- ALU, branch, LSU, and CSR/system execution paths
- Independent second ALU execution and writeback path
- CSR/system instruction serialization for precise side effects

Implemented dual-issue combinations include:

- `ALU + ALU`
- `MEM + ALU`
- `branch + ALU`
- `branch + MEM`

The core has one branch unit and one LSU. Therefore `branch + branch` and
`MEM + MEM` are not supported in the same cycle.

### ROB, Completion, and Commit

- Two ROB allocations per cycle
- Multiple completion ports
- Independent lane1 ALU completion
- Branch completion and recovery
- Up to two adjacent completed entries committed in order
- Precise physical-register reclamation
- Wrong-path register and memory operations squashed before retirement

## ISA and Machine-Mode Support

The current integer target is RV32I.

### RV32I

- R-type ALU: `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`,
  `or`, `and`
- I-type ALU: `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`,
  `srli`, `srai`
- Upper immediates: `lui`, `auipc`
- Branches: `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu`
- Jumps: `jal`, `jalr`
- Loads: `lb`, `lh`, `lw`, `lbu`, `lhu`
- Stores: `sb`, `sh`, `sw`
- `fence` is treated as a no-op in this prototype

### CSR and System Instructions

- `csrrw`, `csrrs`, `csrrc`
- `csrrwi`, `csrrsi`, `csrrci`
- `ecall`, `ebreak`, `mret`

Implemented machine CSRs:

- `mstatus`
- `mie`
- `mtvec`
- `mepc`
- `mcause`
- `mtval`
- `mip`

Unimplemented or illegal CSR accesses raise an illegal-instruction exception.

### Traps and Interrupts

Supported synchronous exceptions include:

- Instruction address misaligned
- Illegal instruction
- Breakpoint
- Load address misaligned
- Store address misaligned
- Machine-mode ECALL

Supported machine interrupts:

1. External interrupt
2. Software interrupt
3. Timer interrupt

This order is also the implemented interrupt priority. `mtvec` direct and
vectored modes are supported. Trap entry updates `mepc`, `mcause`, `mtval`,
`MIE`, `MPIE`, and `MPP`; `MRET` restores the corresponding machine status and
redirects to `mepc`.

Interrupts are currently taken at a safe ROB-empty boundary rather than being
injected at the commit head.

## Memory System

The packet backend uses:

```text
Reservation station
    -> memory order queue
    -> LSU and precise store buffer
    -> 2-way write-back D-cache
    -> variable-latency backing memory
```

### Memory Ordering and LSU

- Multi-entry memory operation queue
- Oldest-first memory operation selection
- One active LSU/cache request at a time
- Address-aware load/store disambiguation
- Non-aliasing loads may bypass older stores
- Byte-granular store-to-load forwarding
- Youngest overlapping store wins each forwarded byte
- Loads wait when older stores cover only part of the requested value
- Store address/data capture completes the ROB entry
- Store memory side effects occur only after ROB commit
- Wrong-path stores are removed before modifying the cache

The current structures provide practical load/store ordering but are not yet a
fully speculative, high-bandwidth load-store queue.

### D-cache

- Two-way set associative
- Four words per cache line by default
- Valid, dirty, tag, and data arrays
- Per-set pseudo-LRU replacement
- Write-back and write-allocate behavior
- Dirty victim writeback
- Multi-beat refill and writeback
- Hit, miss, and writeback counters

The D-cache is blocking and does not yet contain MSHRs.

## Project Structure

```text
OoO_RISC_V_CPU_DESIGN.srcs/sources_1/new   RTL
OoO_RISC_V_CPU_DESIGN.srcs/sim_1/new       testbenches
scripts                                    regression helpers
OoO_RISC_V_CPU_DESIGN.xpr                  Vivado project
REGRESSION.md                              detailed regression guide
```

Important RTL modules:

- `top_packet_backend.sv`: current 2-wide integration top
- `fetch_packet_stage.sv`: packet fetch and prediction
- `decode_packet_stage.sv`: two-lane decode
- `rename_packet_stage.sv`: two-lane rename and checkpoint allocation
- `dispatch_packet_stage.sv`: packet dispatch and ROB integration
- `rs.sv`: reservation stations and two-issue ALU scheduling
- `issue_packet_arbiter.sv`: cross-FU issue pairing
- `execution_stage.sv`: ALU, branch, LSU, CSR, and completion integration
- `rob_2w.sv`: two-wide ROB allocation and commit
- `reg_file_2w.sv`: multi-port physical register file
- `memory_order_queue.sv`: ordered memory scheduling
- `lsu.sv`: loads, precise stores, and forwarding
- `data_cache.sv`: write-back D-cache
- `csr_file.sv`: machine CSR and trap state

## Validation

The project is tested with Vivado Simulator 2019.1. The consolidated mainline
suite and the `quick` regression pass with no launch/runtime failures. Tests
are organized into three layers:

1. **Consolidated mainline suites** for fast architecture-level confidence.
2. **Subsystem tests** for frontend, rename, issue, ROB, LSU, and cache changes.
3. **Legacy directed tests** retained for precise diagnosis and historical
   milestone coverage.

### Consolidated Multi-Issue Suite

The preferred multi-issue architecture smoke is:

```text
tb_top_packet_backend_multi_issue_suite
```

It runs three programs in one elaboration and covers:

- `ALU + ALU`
- `MEM + ALU`
- `branch + ALU`
- `branch + MEM`
- lane1 writeback and dependent wakeup
- dual commit
- lane1 conditional branch, `JAL`, and `JALR`
- JALR miss wait and execution redirect
- same-packet lane0-to-lane1 JALR dependency
- wrong-path register suppression

Six focused integration smokes that duplicated these scenarios were retired
after the consolidated suite and quick regression passed. Module-level and
unique corner-case tests remain available for diagnosis.

### One-Command Regression

After opening the Vivado project, run the following in the Vivado Tcl console:

```tcl
source scripts/run_regression.tcl
run_regression quick
```

Available groups:

```tcl
list_regression_suites
run_regression quick
run_regression multi_issue
run_regression memory
run_regression full
```

The script changes only the `sim_1` top and closes each simulation before
starting the next one.

See [`REGRESSION.md`](REGRESSION.md) for the exact suite contents and the
retired-test coverage mapping.

## Opening the Project

Open:

```text
OoO_RISC_V_CPU_DESIGN.xpr
```

Recommended tool version:

```text
Vivado 2019.1
```

Confirm that the design top is `top_packet_backend`. The simulation top may be
changed to any testbench or selected automatically by
`scripts/run_regression.tcl`.

Incremental simulation is disabled in `sim_1` because Vivado 2019.1 can crash
while restoring stale incremental snapshots after package or hierarchy
changes.

## Current Limitations

- Maximum width is two instructions
- One LSU and one branch unit
- No `MEM + MEM` or `branch + branch` issue
- CSR/system operations are serialized
- Blocking D-cache with no MSHRs
- No I-cache/D-cache shared bus or memory arbiter
- No virtual memory
- Machine-mode-oriented privilege support only
- Interrupts wait for a ROB-empty safe point
- No floating-point extension yet

## Next Architecture Stage

The 2-wide integer architecture is functionally complete enough to serve as
the base for the next major feature. Before floating-point work begins, the
recommended closeout is:

1. Run the `full` regression group before the next architecture transition.
2. Record IPC and dual-issue utilization on representative programs.
3. Establish the packet backend as the baseline for floating-point work.

The RTL already counts committed instructions, issue mix, dual issue, stalls,
and dual commit. A future IPC comparison only needs a clearly defined cycle
window and a scalar-width compatibility run of the same program; it does not
require another backend redesign.

Generated Vivado output such as `.Xil`, `.runs`, `.sim`, `.cache`, logs,
journals, and waveform databases should not be committed.
