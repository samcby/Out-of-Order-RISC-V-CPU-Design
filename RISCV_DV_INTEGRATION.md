# RISCV-DV Integration Plan

This checkpoint prepares the RTL for long random programs without adding the
generator-facing testbench yet.

## DUT Configuration

The first target should be a machine-mode, bare-metal `RV32IF` core:

- XLEN: 32
- privilege: machine mode only
- address translation: BARE
- enabled ISA groups: RV32I and RV32F
- disabled extensions: M, A, C, D, V
- misaligned load/store execution: disabled; the DUT traps instead
- random interrupts, debug mode, PMP, and MMU tests: disabled initially

Recommended long-test instance parameters:

```systemverilog
top_packet_backend #(
    .ENABLE_2WIDE(1'b1),
    .IMEM_DEPTH_BYTES(64 * 1024),
    .DMEM_WORDS(16 * 1024)
) dut (...);
```

The default small memories remain useful for fast smoke regressions.

## Retirement Contract

`top_packet_backend` exports two registered `retire_trace_t` records. Lane 0
always precedes lane 1 in architectural order. `order` increments once for
every committed instruction, including instructions without a destination
register.

The initial Spike comparison should use:

- `order`
- `pc`
- `instr`
- `rd_wen`
- `rd_is_fp`
- `rd`
- `rd_wdata`
- `fp_flags`

Stores and branches are classified in the trace. Detailed memory transaction
fields and precise trap metadata can be added when memory and exception random
tests are enabled.

## Next Milestone

1. Add a generic HEX loader for instruction and initialized data sections.
2. Add a `tohost`-style pass/fail and timeout protocol.
3. Emit DUT retirement CSV from both trace lanes.
4. Generate and compile a 1,000-instruction arithmetic-only RV32I program.
5. Run the ELF in Spike and compare normalized commit traces.
6. Increase to branch/hazard, memory, and RV32F campaigns.
7. Enable controlled exceptions and interrupts only after deterministic
   instruction-level comparison is stable.
