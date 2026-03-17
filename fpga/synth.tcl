# ============================================================================
# GEMM Accelerator Vivado Synthesis & Implementation Script
# Target: Xilinx Artix-7 (xc7a100tcsg324-1)
# Usage: vivado -mode batch -source synth.tcl
# ============================================================================

# Project settings
set proj_name "gemm_accelerator"
set proj_dir  "./vivado_project"
set part      "xc7a100tcsg324-1"
set top       "gemm_accelerator_top"

# RTL source files (relative to fpga/ directory)
set rtl_dir "../rtl"
set rtl_files [list \
    "${rtl_dir}/scratchpad_mem.v" \
    "${rtl_dir}/scratchpad_double_buf.v" \
    "${rtl_dir}/mac_unit_v2.v" \
    "${rtl_dir}/mac_array_v2.v" \
    "${rtl_dir}/dma_engine.v" \
    "${rtl_dir}/matmul_controller_v2.v" \
    "${rtl_dir}/tiling_engine.v" \
    "${rtl_dir}/gemm_regfile.v" \
    "${rtl_dir}/gemm_custom_insn.v" \
    "${rtl_dir}/gemm_accelerator_top.v" \
]

set xdc_file "constraints.xdc"

# Create project
create_project $proj_name $proj_dir -part $part -force

# Add RTL sources
foreach f $rtl_files {
    add_files -norecurse $f
}

# Add constraints
add_files -fileset constrs_1 -norecurse $xdc_file

# Set top module
set_property top $top [current_fileset]

# ---- Synthesis ----
puts "================================================================"
puts "Starting synthesis..."
puts "================================================================"

# Synthesis settings for area + timing optimization
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]

launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check synthesis status
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

puts "Synthesis completed successfully."

# ---- Post-synthesis reports ----
open_run synth_1

# Utilization report
report_utilization -file "${proj_dir}/reports/utilization_synth.rpt"

# Timing summary (post-synth estimate)
report_timing_summary -file "${proj_dir}/reports/timing_synth.rpt" -delay_type max

# ---- Implementation (Place & Route) ----
puts "================================================================"
puts "Starting implementation..."
puts "================================================================"

set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

puts "Implementation completed successfully."

# ---- Post-implementation reports ----
open_run impl_1

# Timing
report_timing_summary -file "${proj_dir}/reports/timing_impl.rpt" -delay_type max
report_timing -max_paths 20 -file "${proj_dir}/reports/timing_paths.rpt"

# Utilization
report_utilization -file "${proj_dir}/reports/utilization_impl.rpt"
report_utilization -hierarchical -file "${proj_dir}/reports/utilization_hier.rpt"

# Power
report_power -file "${proj_dir}/reports/power.rpt"

# DRC
report_drc -file "${proj_dir}/reports/drc.rpt"

# Clock networks
report_clock_networks -file "${proj_dir}/reports/clock_networks.rpt"
report_clock_utilization -file "${proj_dir}/reports/clock_utilization.rpt"

puts "================================================================"
puts "All reports generated in ${proj_dir}/reports/"
puts "Bitstream: ${proj_dir}/${proj_name}.runs/impl_1/${top}.bit"
puts "================================================================"
