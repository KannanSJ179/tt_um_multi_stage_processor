# Design name (must match top module)
set ::env(DESIGN_NAME) "tt_um_multi_stage_processor"

# Source files
set ::env(VERILOG_FILES) [glob $::env(DESIGN_DIR)/*.v]

# Clock (required even if simple)
set ::env(CLOCK_PORT) "clk"
set ::env(CLOCK_PERIOD) "100"

# Core utilization (safe default)
set ::env(FP_CORE_UTIL) 30

# Placement density
set ::env(PL_TARGET_DENSITY) 0.4

# Enable macro usage
set ::env(MACRO_PLACEMENT_CFG) ""

# Include macro LEF
set ::env(EXTRA_LEFS) [glob $::env(DESIGN_DIR)/macro/*.lef]

# Include macro GDS (will be added later properly)
set ::env(EXTRA_GDS_FILES) [glob $::env(DESIGN_DIR)/macro/*.gds]
