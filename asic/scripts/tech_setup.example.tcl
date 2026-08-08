# Copy this file outside version control or point ASIC_TECH_SETUP at an
# equivalent foundry/library configuration. Do not commit proprietary paths.
set TARGET_LIBRARY_FILES [list \
    /absolute/path/to/slow_corner_standard_cells.db \
]

# Optional additional memories or IO libraries used only for linking.
set EXTRA_LINK_LIBRARY_FILES [list]

# Baseline target: 200 MHz before clock-tree synthesis.
set CLOCK_PERIOD_NS 5.000

# Optional names used by downstream scripts and report headers.
set PROCESS_CORNER slow
set VOLTAGE_CORNER nominal
set TEMPERATURE_CORNER 125C
