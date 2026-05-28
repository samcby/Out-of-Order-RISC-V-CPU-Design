# Out-of-Order RV32I CPU Design

This repository contains a Vivado/SystemVerilog implementation of a
single-issue out-of-order RISC-V CPU. The project began as a staged academic
CPU design and has been extended into a more complete OoO microarchitecture
with register renaming, speculative execution, branch prediction, precise-ish
trap handling, machine-mode CSRs, and interrupt support.

The core is intentionally not superscalar yet. It is a single-fetch,
single-rename, single-issue design, but it implements many of the key
mechanisms used in modern out-of-order processors.

## Current Highlights

- Single-issue out-of-order backend
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

## Microarchitecture

### Frontend and Prediction

The frontend fetches one instruction at a time and includes lightweight branch
prediction structures:

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

### Dispatch, Scheduling, and Execution

Instructions are dispatched into a ROB and functional-unit specific reservation
stations. Ready operations can issue out of program order, while architectural
state is retired in order.

- ALU reservation station
- Load/store reservation station
- Branch reservation station
- Issue arbitration across functional units
- ALU, branch, LSU, and CSR/system execution paths

### Commit and Recovery

The ROB maintains in-order retirement and completion tracking.

- In-order commit
- ROB completion updates from ALU/LSU/branch paths
- Branch squash of wrong-path instructions
- Separate handling for branch recovery versus trap/interrupt redirect
- Commit-time physical register reclamation

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

## Project Structure

Main RTL sources:

```text
OoO_RISC_V_CPU_DESIGN.srcs/sources_1/new
```

Important modules:

- `top.sv`: top-level CPU integration
- `defines_pkg.sv`: shared parameters, control structs, constants
- `fetch_stage.sv`: fetch, prediction, redirect control
- `decode_controller.sv`: instruction decode and legality checks
- `decode_stage.sv`: decode pipeline stage
- `rename_stage.sv`: RAT, free-list, and checkpoint handling
- `dispatch_stage.sv`: ROB/RS dispatch and CSR serialization
- `dispatch_logic.sv`: dispatch routing
- `rs.sv`: reservation station
- `rob.sv`: reorder buffer
- `execution_stage.sv`: ALU/LSU/branch/CSR integration
- `csr_file.sv`: machine CSR state and trap entry/return behavior
- `branch.sv`: branch resolution and target generation
- `lsu.sv`: load/store unit
- `reg_file.sv`: physical register file
- `RAT.sv`: register alias table
- `free_pool.sv`: physical register free list

Simulation sources:

```text
OoO_RISC_V_CPU_DESIGN.srcs/sim_1/new
```

## Validation Status

The design has been tested with Vivado Simulator 2019.1.

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

Typical simulation flow:

1. Open the project in Vivado.
2. Set the desired testbench as the simulation top.
3. Launch simulation.
4. Run the generated Tcl script or run manually in the simulator console.

Example simulation tops:

```text
tb_top_rv32i_smoke
tb_top_csr_smoke
tb_top_trap_smoke
tb_top_interrupt_sources_smoke
tb_top_illegal_smoke
tb_top_misaligned_smoke
tb_top_mtvec_mode_smoke
tb_trace_25test
```

## Scope and Limitations

This project is a CPU microarchitecture prototype, not a complete SoC.

Current limitations:

- Single-issue, not superscalar
- No instruction/data cache hierarchy beyond the current simple instruction memory model
- No virtual memory
- No full privilege-level stack beyond machine-mode oriented behavior
- Interrupts are taken at a safe ROB-empty point rather than precise commit injection
- Memory ordering and load/store speculation are intentionally simple
- No floating-point extension yet

## Suggested Next Steps

Possible future extensions:

- Add a stronger memory subsystem and data cache
- Add store-to-load forwarding
- Add more complete precise exception handling at commit
- Move toward multi-issue dispatch and issue
- Add a return address stack
- Add floating-point extensions
- Improve regression automation outside the Vivado GUI

## Repository Notes

The repository is intended to track source RTL, simulation testbenches, the
Vivado project file, and lightweight project metadata. Generated Vivado output
such as `.Xil`, `.runs`, `.sim`, `.cache`, logs, journals, and waveform
databases should not be committed.
