# Out-of-Order RISC-V CPU Design

This repository contains a Vivado-based RTL implementation of a **single-issue out-of-order RISC-V CPU** developed in SystemVerilog. The project started from a staged academic CPU design flow and was extended into a more modern OoO microarchitecture with speculative execution, branch prediction, register renaming, and multi-checkpoint recovery.

The current design is not a superscalar core. It is a **single-fetch, single-rename, single-issue** processor, but it already supports the key mechanisms that define an out-of-order backend:

- register renaming
- physical register file
- reservation station based scheduling
- reorder buffer based in-order commit
- speculative execution and recovery
- multiple branch checkpoints in flight

## Features

### Core Microarchitecture

- **Register renaming**
  - RAT-based architectural-to-physical register mapping
  - free physical register pool
  - old physical register reclamation at commit
- **Out-of-order execution**
  - reservation station for waiting and wakeup
  - issue arbitration based on ready operations
  - functional unit dispatch separated from in-order retirement
- **In-order commit**
  - ROB tracks destination mapping, completion state, and retirement order
  - precise architectural state is maintained through ordered commit

### Speculation and Control Flow

- **Speculative execution**
  - younger instructions may execute before older branches resolve
  - wrong-path instructions are squashed before commit
- **Multiple checkpoints in flight**
  - rename/free-list recovery supports more than one unresolved branch
  - selective squash uses speculation masks rather than a single global speculative state
- **Branch prediction frontend**
  - BHT for direction prediction
  - BTB for target prediction
  - JALR target cache for indirect jump/call prediction
  - redirect and recovery path after branch resolution

### Memory and ISA Support

The design currently supports the subset of RV32I functionality needed by the project testbenches and trace-driven programs, including:

- integer ALU operations such as `lui`, `addi`, `ori`, `and`, `sub`, `sra`, `sltiu`
- conditional branches
- `jal`
- `jalr`
- `lw`
- `sw`
- `lbu`
- `sh`

## Project Structure

### Main RTL

Main source files are under:

`OoO_RISC_V_CPU_DESIGN.srcs/sources_1/new`

Key modules include:

- `top.sv` - top-level CPU integration
- `fetch_stage.sv` - fetch, prediction, redirect control
- `decode_stage.sv` - instruction decode and control generation
- `rename_stage.sv` - RAT/free-list/checkpoint handling
- `dispatch_stage.sv` / `dispatch_logic.sv` - ROB/RS allocation and dispatch control
- `rs.sv` - reservation station
- `rob.sv` - reorder buffer
- `execution_stage.sv` - ALU, branch, LSU integration and completion routing
- `lsu.sv` - load/store unit
- `reg_file.sv` / `RAT.sv` / `free_pool.sv` - rename backend structures

### Simulation

Simulation testbenches are under:

`OoO_RISC_V_CPU_DESIGN.srcs/sim_1/new`

Notable top-level validation testbenches:

- `tb_top_phase4_speculative.sv`
- `tb_top_phase5_jal_predictor.sv`
- `tb_top_phase5_jalr_predictor.sv`
- `tb_top_phase5_bht_training.sv`
- `tb_top_phase5_btb.sv`
- `tb_top_phase6_multi_checkpoint.sv`
- `tb_trace_25r.sv`
- `tb_trace_25test.sv`
- `tb_trace_25swr.sv`
- `tb_trace_25jswr.sv`

## Validation Status

The current version has passed both staged microarchitectural tests and trace-driven program checks.

### Microarchitectural Tests

The design has been exercised for:

- speculative execution
- redirect and recovery behavior
- JAL prediction
- JALR prediction
- BHT training
- BTB behavior
- multiple simultaneous checkpoints

### Trace-Driven Tests

The following trace-based tests are passing:

- `25r`
- `25test`
- `25swr`
- `25jswr`

These tests cover ALU behavior, branch/loop behavior, memory operations, byte/halfword-related access patterns, and function-call/return style control flow.

## How to Open and Run

### Vivado Project

Open the Vivado project file:

`OoO_RISC_V_CPU_DESIGN.xpr`

This project has been developed and simulated with:

- **Vivado Simulator 2019.1**

### Running a Testbench

Typical flow in Vivado:

1. Open the project.
2. Set the desired simulation source as the top module.
3. Launch simulation.
4. Run the generated Tcl script or execute simulation manually.

Example trace testbenches:

- `tb_trace_25r`
- `tb_trace_25test`
- `tb_trace_25swr`
- `tb_trace_25jswr`

## Current Scope and Limitations

- The core is **single-issue**, not superscalar.
- It is intended as an **OoO prototype / educational microarchitecture**, not a full production RISC-V implementation.
- ISA coverage is partial and focused on the subset needed for the implemented tests.
- The design emphasizes microarchitectural mechanisms rather than full system integration, CSR support, exception handling, or software toolchain boot support.

## Summary

At this stage, the project demonstrates a working **single-issue out-of-order RISC-V CPU** with:

- register renaming
- reservation-station scheduling
- ROB-based in-order commit
- speculative execution
- branch prediction
- multi-checkpoint recovery
- successful execution of multiple trace-driven validation programs

This makes it a solid foundation for future extensions such as:

- return address stack (RAS)
- stronger branch predictors
- load/store speculation improvements
- store-to-load forwarding
- wider issue / superscalar execution
