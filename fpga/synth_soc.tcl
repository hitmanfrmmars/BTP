# ============================================================
# Vivado Non-Project Mode: Full GEMM SoC (PicoRV32 + Accelerator)
# Target: Artix-7 xc7a100tcsg324-1
# ============================================================

set PART      xc7a100tcsg324-1
set TOP       gemm_soc_synth_wrapper
set RPRT_DIR  reports
set RTL_DIR   ../rtl

# Create reports directory
file mkdir $RPRT_DIR

# Read RTL sources (SystemVerilog for unpacked array support)
read_verilog -sv [list \
    $RTL_DIR/gemm_synth_wrapper.v \
    $RTL_DIR/gemm_soc_synth_top.v \
    $RTL_DIR/dpram_bytewrite.v \
    $RTL_DIR/riscv/picorv32.v \
    $RTL_DIR/gemm_accelerator_top.v \
    $RTL_DIR/gemm_pcpi_adapter.v \
    $RTL_DIR/gemm_regfile.v \
    $RTL_DIR/tiling_engine.v \
    $RTL_DIR/dma_engine.v \
    $RTL_DIR/scratchpad_double_buf.v \
    $RTL_DIR/scratchpad_mem.v \
    $RTL_DIR/matmul_controller_v2.v \
    $RTL_DIR/mac_array_v2.v \
    $RTL_DIR/mac_unit_v2.v \
]

# Read constraints
read_xdc constraints.xdc

# ---- Synthesize (out-of-context: no IOBUFs, no pin assignment needed) ----
synth_design -top $TOP -part $PART -flatten_hierarchy rebuilt -mode out_of_context
report_utilization -file $RPRT_DIR/soc_utilization_synth.rpt
report_timing_summary -file $RPRT_DIR/soc_timing_synth.rpt

# ---- Optimize ----
opt_design

# ---- Place ----
place_design
report_utilization -file $RPRT_DIR/soc_utilization_placed.rpt

# ---- Route ----
route_design

# ---- Post-route reports ----
report_utilization -file $RPRT_DIR/soc_utilization.rpt
report_utilization -hierarchical -file $RPRT_DIR/soc_utilization_hier.rpt
report_timing_summary -file $RPRT_DIR/soc_timing.rpt
report_timing -nworst 10 -file $RPRT_DIR/soc_timing_detail.rpt
report_power -file $RPRT_DIR/soc_power.rpt
report_clock_utilization -file $RPRT_DIR/soc_clock_util.rpt

# ---- Save checkpoint for GUI schematic viewing ----
# Open with: vivado reports/soc_post_route.dcp  (then Schematic view)
write_checkpoint -force $RPRT_DIR/soc_post_route.dcp

# ---- Print summary to console ----
puts "============================================"
puts "  GEMM SoC Synthesis Complete"
puts "============================================"
puts ""

set wns [get_property SLACK [get_timing_paths -max_paths 1]]
set clk_period 10.0
set fmax [expr {1000.0 / ($clk_period - $wns)}]
puts [format "  Worst Negative Slack (WNS): %.3f ns" $wns]
puts [format "  Estimated Fmax:             %.1f MHz" $fmax]
puts ""
puts "  Reports written to: $RPRT_DIR/soc_*.rpt"
puts "============================================"
