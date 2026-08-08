# Portable pre-layout constraints for the packet backend.
# Override CLOCK_PERIOD_NS before sourcing this file when sweeping frequency.
if {![info exists CLOCK_PERIOD_NS]} {
    set CLOCK_PERIOD_NS 5.000
}

set IO_DELAY_NS [expr {$CLOCK_PERIOD_NS * 0.10}]
set CLOCK_UNCERTAINTY_NS [expr {$CLOCK_PERIOD_NS * 0.02}]

create_clock -name core_clk -period $CLOCK_PERIOD_NS [get_ports clk]
set_clock_uncertainty $CLOCK_UNCERTAINTY_NS [get_clocks core_clk]

set data_inputs [get_ports {
    software_irq timer_irq external_irq load_en load_addr* load_instr_byte*
}]
set_input_delay $IO_DELAY_NS -clock core_clk $data_inputs
set_output_delay $IO_DELAY_NS -clock core_clk [all_outputs]

# Reset assertion is asynchronous. Reset release must be synchronized by the
# chip-level reset controller and is excluded from functional data timing.
set_false_path -from [get_ports rst_n]
