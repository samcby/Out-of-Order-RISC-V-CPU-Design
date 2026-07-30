# Out-of-Order RV32IF CPU Design

This repository contains a SystemVerilog implementation of a speculative,
out-of-order RV32IF processor developed in Vivado 2019.1. The current mainline
is a packetized 2-wide superscalar core with register renaming, reservation
stations, precise in-order retirement, branch recovery, U/M privilege modes,
sixteen-entry physical memory protection, machine traps and interrupts,
IEEE-754 binary32 execution, and a cached memory hierarchy.

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

## ISA and Privileged Architecture

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
- `fence` and `fence.i` use a serialized backend path; they wait for older
  retirement and a quiescent LSU/cache before completing

### CSR and System Instructions

- `csrrw`, `csrrs`, `csrrc`
- `csrrwi`, `csrrsi`, `csrrci`
- `ecall`, `ebreak`, `mret`, `wfi`

Implemented machine CSRs:

- `mstatus`
- `mie`
- `mtvec`
- `mepc`
- `mcause`
- `mtval`
- `mip`
- `pmpcfg0`-`pmpcfg3`
- `pmpaddr0`-`pmpaddr15`

CSR privilege is checked against the current U/M mode. Unimplemented,
read-only-write, or insufficient-privilege accesses raise an
illegal-instruction exception.

The core implements the standard minimum of sixteen statically prioritized PMP
entries with OFF, TOR, NA4, and NAPOT addressing, R/W/X permissions, and the
architectural Lock bit. U-mode instruction fetches, loads, and stores are
checked before entering the existing precise access-fault path. The
lowest-numbered entry matching any accessed byte wins, and an entry that only
partially covers an access causes a fault. Unlocked entries are bypassed in
M-mode; locked entries also constrain M-mode. Locking a TOR entry additionally
locks its preceding address register. The reset value gives entry zero a
full-address-space RWX TOR region so existing bare-metal programs remain
compatible until M-mode software installs a stricter policy. `mstatus.MPRV`
is implemented for M-mode loads and stores: when set, PMP checks use the U/M
mode encoded in `MPP`, while instruction fetch continues to use the current
privilege.

### Traps and Interrupts

Supported synchronous exceptions include:

- Instruction address misaligned
- Instruction access fault
- Illegal instruction
- Breakpoint
- Load address misaligned
- Load access fault
- Store address misaligned
- Store access fault
- User-mode ECALL
- Machine-mode ECALL

Supported machine interrupts:

1. External interrupt
2. Software interrupt
3. Timer interrupt

This order is also the implemented interrupt priority. `mtvec` direct and
vectored modes are supported. The core boots in M-mode and can enter U-mode
with `MRET`. Trap entry records the previous privilege in `MPP`, enters M-mode,
and updates `mepc`, `mcause`, `mtval`, `MIE`, and `MPIE`. `MRET` restores the
saved privilege and interrupt-enable state, redirects to `mepc`, and flushes
all younger frontend and backend work.

Pending interrupts retire any already-complete architectural prefix first.
When the oldest ROB entry is still incomplete, the core takes the interrupt
without draining younger work, records that entry's PC in `mepc`, flushes all
speculative state, and replays the interrupted instruction after `MRET`.
Nested machine interrupts are supported through the standard software-managed
protocol: an outer handler saves the single `mstatus`/`mepc`/`mcause` context,
reenables `MIE`, services an inner interrupt, then restores the outer context
before its final `MRET`. Architectural trap flushes also invalidate every
in-flight branch-pipeline entry so stale redirects cannot escape recovery.

The software, timer, and external interrupt pins are modeled as level-sensitive
sources. A line that remains asserted stays visible in `mip` and can retrigger
after `MRET`; deasserting the line clears the pending bit. `WFI` retires at a
precise serialized boundary and then blocks younger dispatch. A locally enabled
pending interrupt wakes the core even when global `mstatus.MIE` is clear; trap
entry still requires the normal global-enable rule. This permits wake-without-
trap behavior as well as ordinary interrupt-driven wakeup.

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
- `fence` and `fence.i` complete only after older instructions retire and all
  buffered or in-flight data-memory operations drain

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
- `csr_file.sv`: machine CSR, U/M privilege, PMP, and trap state

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
run_regression invariants
run_regression performance
run_regression stress
run_regression full
```

The script changes only the `sim_1` top and closes each simulation before
starting the next one.

See [`REGRESSION.md`](REGRESSION.md) for the exact suite contents and the
retired-test coverage mapping. See
[`VERIFICATION_COVERAGE.md`](VERIFICATION_COVERAGE.md) for requirement-level
coverage, known gaps, and the release gate.

### Simulation Invariants

Critical internal invariants are checked automatically during simulation for
the ROB, integer RAT, free pool, branch checkpoints, precise store buffer, and
dual retirement interface. These assertions detect corruption at the cycle it
occurs and are excluded from synthesis with `SYNTHESIS`.

### IPC Characterization

`top_packet_backend` has an `ENABLE_2WIDE` parameter. Its default value is
`1`, preserving the mainline architecture. Setting it to `0` simultaneously
limits fetch, issue, and commit to one instruction per cycle while retaining
the same predictor, queues, execution units, cache, and memory latency.

The comparison test is:

```text
tb_top_packet_backend_ipc_compare
```

It runs 1-wide and 2-wide instances side by side on identical programs and
reports:

- active cycles
- committed instructions
- IPC
- 2-wide speedup over the 1-wide baseline
- dual-fetch, dual-issue, and dual-commit activity

The initial workloads cover independent ALU instructions, a dependency chain,
and paired memory-plus-ALU traffic. Measurement begins after program loading
and ends when the same sentinel instruction commits in each core.

Measured with Vivado Simulator 2019.1:

| Workload | 2-wide IPC | 1-wide IPC | Cycle speedup |
| --- | ---: | ---: | ---: |
| Independent ALU | 1.368 | 0.812 | 1.684x |
| Dependency chain | 0.481 | 0.473 | 1.019x |
| Memory plus ALU | 0.286 | 0.243 | 1.175x |

The independent workload demonstrates the available superscalar throughput.
The dependency chain remains effectively single-issue, as expected from its
RAW dependency on every instruction. The mixed workload gains from paired
MEM+ALU issue but remains limited by the single blocking LSU and cache path.

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
- `fence.i` has no separate instruction-cache invalidation action because the
  current frontend has no instruction cache
- No I-cache/D-cache shared bus or memory arbiter
- No virtual memory
- U-mode and M-mode only; no S-mode or trap delegation
- PMP uses sixteen entries and 4-byte grain, but Smepmp enhancements are not
  implemented
- Interrupt entry does not share a cycle with normal retirement; a pending
  interrupt first retires the currently complete ROB prefix, then takes at the
  next incomplete precise boundary
- `WFI` implements architectural sleep/wakeup but does not add technology-
  specific clock gating; ASIC clock/power gating remains an implementation step

## RV32F Support

The floating-point implementation includes:

- production reset with `mstatus.FS=Off`
- precise illegal-instruction traps for every FP opcode and FP CSR access while
  `mstatus.FS=Off`, with no FPU, LSU, FP-CSR, or FP-register side effects
- `mstatus.FS` transition to Dirty only when committed FP work modifies
  architectural FP state
- complete RV32F instruction-class decoding
- explicit integer-to-FP and FP-to-integer register routing
- independent 128-entry floating-point physical register storage
- two FP writeback ports and same-packet readiness handling
- two-wide FP RAT/free-pool allocation with RAW and WAW bypass
- FP checkpoint save/restore synchronized with integer control flow
- precise reclamation of retired FP mappings, including architectural `f0`
- `fflags`, `frm`, and `fcsr` state with sticky exception flags
- illegal detection for reserved rounding-mode encodings
- ROB destination-domain metadata for integer versus FP retirement
- FLW/FSW transport through the production ordered LSU and cache
- commit-gated and squash-safe floating-point stores
- register-domain-aware RS/MOQ wakeup and writeback
- integrated integer and FP physical register files
- end-to-end FLW/FSW execution from the packet frontend
- writable and renameable architectural `f0`
- exact FP execution integrated into both ALU issue slots
- `FSGNJ.S`, `FSGNJN.S`, and `FSGNJX.S`
- `FMIN.S` and `FMAX.S`, including NaN and signed-zero selection
- `FEQ.S`, `FLT.S`, and `FLE.S`, including NaN and signed-zero behavior
- `FCLASS.S`, `FMV.X.W`, and `FMV.W.X`
- `FADD.S` and `FSUB.S` with RNE, RTZ, RDN, RUP, and RMM
- `FMUL.S` with the same static and dynamic rounding modes
- `FCVT.W.S`, `FCVT.WU.S`, `FCVT.S.W`, and `FCVT.S.WU`
- shared multi-cycle `FDIV.S` and `FSQRT.S`
- single-rounding `FMADD.S`, `FMSUB.S`, `FNMSUB.S`, and `FNMADD.S`
- three-source FP rename, PRF reads, RS readiness, and dual-writeback wakeup
- cross-domain integer/FP dependencies through rename, wakeup, and writeback
- dynamic rounding through `frm` when the instruction uses `rm=111`
- binary32 NaN, infinity, subnormal, signed-zero, overflow, underflow, and
  inexact handling for add/subtract/multiply/divide/square root
- divide-by-zero and invalid-operation flag generation for long FP operations
- long-operation backpressure, branch-squash cancellation, and precise
  completion through the ROB
- independent three-cycle FP pipelines on both ALU issue lanes
- one-result-per-cycle FP pipeline throughput with completion backpressure
- speculation-mask tracking and wrong-path cancellation inside the FP pipelines
- integer-to-FP and FP-to-integer dependency wakeup through the normal OoO path
- per-instruction FP exception flags carried in the ROB
- precise `fflags` updates at retirement, including dual-commit flag merging
- speculative FP exceptions discarded by branch recovery
- software-visible `fflags`, `frm`, and `fcsr` through serialized CSR accesses

Run this milestone with:

```tcl
run_regression floating
```

The floating-point arithmetic cores are also checked against Berkeley
SoftFloat 3e using 10,880 deterministic vectors. The differential test covers
all five RISC-V rounding modes, arithmetic, divide/square root, all four fused
multiply-add sign variants, integer conversions, comparisons, result bits,
and `NV/DZ/OF/UF/NX` flags:

```tcl
run_regression softfloat
```

The checked-in vector file lets Vivado run this test without a C compiler or a
local SoftFloat installation. To regenerate it with the fixed default seed:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/generate_softfloat_vectors.ps1
```

The script downloads SoftFloat into the workspace-level `.deps` directory,
builds its RISC-V specialization with MinGW, and rewrites
`fp_softfloat_vectors.txt`. Use `-RandomVectorsPerCase` and `-Seed` to run a
larger or differently seeded campaign before a release.

The implemented instruction-level datapath now covers the RV32F computational,
conversion, comparison, move/classification, load/store, CSR-state, and
disabled-state trap families. Future FP work is primarily implementation
quality and broader randomized validation, including replacing the current
divide/square-root numeric core with a smaller digit-recurrence datapath
without changing its shared multi-cycle issue/completion contract.

## Long-Program Stress Verification

The packet backend includes a generator-independent long-program verification
path:

- `IMEM_DEPTH_BYTES` and `DMEM_WORDS` top-level parameters propagate to the
  fetch memory and cache backing memory
- the default 4 KiB instruction / 1 KiB data memories remain unchanged for
  fast smoke regressions
- the checked-in stress test selects 64 KiB instruction and data memories
- the ROB preserves the retiring PC and instruction word
- two registered `retire_trace_t` records report in-order retirement with a
  monotonic 64-bit order number
- each trace record includes PC, instruction, integer/FP destination, write
  value, FP flags, branch/store classification, and the internal ROB tag

`tb_top_packet_backend_long_stress` loads a word-oriented HEX image directly,
uses retirement of `x31=1` as its completion protocol, maintains an independent
architectural GPR mirror, checks every retired PC/instruction against a strict
ordered stream, checks every integer register write against a per-PC oracle,
checks all final GPRs, detects retirement deadlock, and emits
`rv32i_long_stress_retire.csv`.

The default deterministic campaign contains 10,439 static RV32I instructions and
mixes ALU dependencies, dual-issue opportunities, byte/halfword/word
load-store traffic, taken and not-taken branches, `jal`, and `jalr`. With the
default seed it retires 10,282 dynamic instructions in 15,555 active cycles
(IPC 0.661) with 3,968 dual-retire cycles in Vivado Simulator 2019.1.

The same 700-block campaign has also passed seeds `0x1892027`, `0x5eed1234`,
and `0xc0ffee`, bringing the validated multi-seed total to 41,128 dynamic
retirements.

Regenerate it with:

```powershell
python scripts/generate_rv32i_long_stress.py
```

Select another deterministic workload with `--seed`, or change its length
with `--blocks`:

```powershell
python scripts/generate_rv32i_long_stress.py --seed 0x5eed1234 --blocks 700
```

Then run:

```tcl
run_regression stress
```

External `riscv-dv`/Spike and ACT4 certification flows are not part of this
release. Their simulator, toolchain, memory-map, and platform-contract
requirements remain future verification work; no official certification pass
is claimed.

The RTL counts active cycles, committed instructions, issue mix, dual issue,
stalls, and dual commit. The configurable width mode provides a controlled
single-width baseline without relying on the structurally different legacy
`top.sv`.

Generated Vivado output such as `.Xil`, `.runs`, `.sim`, `.cache`, logs,
journals, and waveform databases should not be committed.
