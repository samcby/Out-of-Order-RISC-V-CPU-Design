# ASIC Synthesis and Timing Baseline

This directory provides a vendor-neutral RTL manifest, baseline constraints,
and reference scripts for synthesis and static timing analysis of
`top_packet_backend`. The production RTL remains plain SystemVerilog and does
not instantiate FPGA primitives, Xilinx XPMs, or vendor floating-point IP.

The flow is intended to make the design reproducible in an ASIC toolchain. It
is not a tapeout flow by itself: a real standard-cell library, SRAM macros,
physical design, DFT, clock-tree synthesis, power analysis, and signoff checks
are still required.

## Contents

```text
rtl_files.f                         ordered production RTL manifest
constraints/top_packet_backend.sdc baseline 200 MHz timing constraints
scripts/dc_synth.tcl                Synopsys Design Compiler synthesis
scripts/pt_sta.tcl                  Synopsys PrimeTime STA
scripts/tech_setup.example.tcl      technology-library template
scripts/vivado_baseline.tcl         FPGA mapping proxy for structural checks
run_vivado_baseline.ps1             Windows wrapper for the proxy run
```

Generated netlists, checkpoints, and reports are written below `asic/build`
and `asic/reports`; both directories are intentionally ignored by Git.

## Portability Check

Run the manifest and vendor-dependency check before synthesis:

```powershell
python scripts/check_asic_portability.py
```

The checker verifies that every manifest entry exists, the production top is
included, and the synthesis closure does not contain common Xilinx primitives,
libraries, or FPGA-only mapping attributes.

## Design Compiler

Copy `scripts/tech_setup.example.tcl` outside the repository or create an
equivalent project-local file. Populate `TARGET_LIBRARY_FILES` with real
Liberty `.db` files and add macro or IO libraries to
`EXTRA_LINK_LIBRARY_FILES` as needed.

On Linux:

```bash
export ASIC_TECH_SETUP=/absolute/path/to/tech_setup.tcl
dc_shell -f asic/scripts/dc_synth.tcl
```

The script analyzes the manifest with `SYNTHESIS` defined, elaborates
`top_packet_backend`, applies the shared SDC, runs `compile_ultra`, and writes
the mapped Verilog, DDC, SDC, area, timing, constraint, and vectorless-power
reports.

## PrimeTime

After Design Compiler completes:

```bash
export ASIC_TECH_SETUP=/absolute/path/to/tech_setup.tcl
pt_shell -f asic/scripts/pt_sta.tcl
```

Set `ASIC_SPEF` to a post-layout SPEF when parasitics are available. Without
it, the PrimeTime run is a pre-layout mapped-netlist baseline.

## Vivado Structural Proxy

Vivado is used only as an available synthesis engine to detect structural RTL
problems before a real ASIC library is supplied. It is not the target
technology and the result is not ASIC PPA.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File asic/run_vivado_baseline.ps1
```

The checked 2019.1 proxy run used a 5.000 ns clock and produced:

| Check | Result |
| --- | ---: |
| Production RTL files | 43 |
| Combinational loops | 0 |
| Unclocked register/latch pins | 0 |
| LUT logic cells | 217,979 |
| Flip-flops | 80,138 |
| DSP cells | 87 |
| Inferred BRAM | 0 |
| Worst setup slack | -390.086 ns |
| Worst data path | 394.931 ns |

The zero-loop and zero-unclocked-pin results are the useful acceptance gates.
The resource counts and timing are diagnostic only. Large asynchronous,
multi-ported register, cache, and memory arrays are expanded into logic rather
than mapped to ASIC SRAM macros; the small proxy FPGA is therefore heavily
over capacity. The long setup path also shows that the current behavioral
floating-point and queue structures do not meet 200 MHz without macroization,
pipelining, and technology-aware optimization.

## Synthesis Semantics

Simulation resets memory and physical-register data arrays for deterministic
testbench observability. Under `SYNTHESIS`, only architectural control state,
valid bits, tags, and readiness state are reset; bulk data arrays are not
reset. A real SoC integration must provide boot/program loading and replace
large inferred arrays with technology-specific SRAM wrappers or generated
macros while preserving the RTL interfaces.

The current top-level program-load ports are verification conveniences, not a
final tapeout interface. A production wrapper should replace them with a boot
ROM, debug loader, or instruction/data bus.

## Next ASIC Steps

1. Wrap the fetch memory, data memory, cache arrays, physical register files,
   and large queues behind explicit memory interfaces and map them to SRAM
   macros.
2. Provide foundry standard-cell, SRAM, and IO libraries with explicit PVT and
   RC corners.
3. Refine SDC for generated clocks, IO timing, false paths, multicycle paths,
   reset synchronization, and clock-domain assumptions.
4. Pipeline or redesign the longest FP and queue-selection paths, then repeat
   synthesis and STA until the target frequency closes.
5. Add scan/DFT, clock-tree and power intent, floorplanning, place-and-route,
   extraction, SI/IR/EM analysis, equivalence checking, and gate-level checks.
