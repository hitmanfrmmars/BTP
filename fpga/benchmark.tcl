# ============================================================================
# GEMM Accelerator Benchmarking Script
# Generates performance analysis reports from implementation results
# Usage: vivado -mode batch -source benchmark.tcl
# ============================================================================

set proj_dir "./vivado_project"

# Open implemented design
open_project "${proj_dir}/gemm_accelerator.xpr"
open_run impl_1

puts "============================================================"
puts "GEMM Accelerator Performance Analysis"
puts "============================================================"

# ---- Resource Utilization Summary ----
puts "\n--- Resource Utilization ---"
set util_rpt [report_utilization -return_string]
puts $util_rpt

# Extract key metrics
set lut_used  [get_property SLICE_LUTS [get_design_analysis]]
set ff_used   [get_property SLICE_REGISTERS [get_design_analysis]]
set bram_used [get_property BLOCK_RAMS [get_design_analysis]]
set dsp_used  [get_property DSPS [get_design_analysis]]

puts "\nKey Resources:"
puts "  LUTs:  $lut_used"
puts "  FFs:   $ff_used"
puts "  BRAMs: $bram_used"
puts "  DSPs:  $dsp_used"

# ---- Timing Analysis ----
puts "\n--- Timing Analysis ---"
set timing_rpt [report_timing_summary -return_string]
puts $timing_rpt

# Worst negative slack
set wns [get_property SLACK [get_timing_paths -max_paths 1]]
puts "\nWorst Negative Slack (WNS): ${wns} ns"

# Maximum achievable frequency
set period 10.0
set fmax [expr {1000.0 / ($period - $wns)}]
puts "Estimated Fmax: ${fmax} MHz"

# ---- Performance Projections ----
puts "\n--- Performance Projections ---"

# 4x4 GEMM: ~16 cycles with streaming controller
set cycles_4x4 16
set gops_4x4 [expr {16.0 * 4 / $cycles_4x4}]  ;# 16 MACs * 4 passes / 16 cycles
puts "  4x4 GEMM: $cycles_4x4 cycles -> [format %.2f $gops_4x4] ops/cycle"

# Peak throughput at Fmax
set peak_gops [expr {16.0 * $fmax / 1000.0}]
puts "  Peak throughput: [format %.2f $peak_gops] GOPS @ [format %.1f $fmax] MHz"

# Effective throughput (accounting for overhead)
set eff_util 0.25  ;# ~25% utilization for single tiles
set eff_gops [expr {$peak_gops * $eff_util}]
puts "  Effective throughput: [format %.2f $eff_gops] GOPS"

# ---- Power Analysis ----
puts "\n--- Power Analysis ---"
set power_rpt [report_power -return_string]
puts $power_rpt

# ---- Model-specific projections ----
puts "\n--- Workload Projections ---"

# MNIST FC layer: 784 x 128 x 10
set mnist_ops [expr {784 * 128 * 2 + 128 * 10 * 2}]
set mnist_cycles [expr {int(ceil(784.0/4) * ceil(128.0/4) * ceil(4.0/4) * $cycles_4x4)}]
puts "  MNIST FC (784x128 + 128x10): $mnist_ops ops, ~$mnist_cycles cycles"

# CIFAR-10 Conv 3x3 first layer: im2col -> 1024 x 27 x 32
set cifar_ops [expr {1024 * 27 * 32 * 2}]
puts "  CIFAR-10 Conv1 (1024x27x32 GEMM): $cifar_ops ops"

# Keyword spotting DS-CNN
set kws_ops [expr {250 * 64 * 2 + 64 * 12 * 2}]
puts "  KWS DS-CNN FC (250x64 + 64x12): $kws_ops ops"

# ---- Roofline Analysis ----
puts "\n--- Roofline Analysis ---"
# Operational intensity = ops / bytes_transferred
# 4x4 tile: 64 ops, loads 32 bytes A + 32 bytes B = 64 bytes -> OI = 1.0
set oi_4x4 1.0
puts "  4x4 tile operational intensity: $oi_4x4 ops/byte"
puts "  System is compute-bound when OI > [format %.2f [expr {$peak_gops / 0.4}]] (at 400 MB/s bandwidth)"
puts "  System is memory-bound when OI < [format %.2f [expr {$peak_gops / 0.4}]]"

puts "\n============================================================"
puts "Benchmarking complete."
puts "============================================================"
