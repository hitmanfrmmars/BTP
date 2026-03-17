# ============================================================
# Generate SoC Schematic PDFs from saved checkpoint
# Run with: vivado -mode batch -source gen_schematic.tcl
# OR open in GUI: vivado reports/soc_post_route.dcp
# ============================================================

set RPRT_DIR  C:/project_sim/fpga/reports
set RTL_DIR   C:/project_sim/rtl

# Re-synthesize minimally just to get the schematic
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

read_xdc C:/project_sim/fpga/constraints.xdc

synth_design -top gemm_soc_synth_wrapper -part xc7a100tcsg324-1 -flatten_hierarchy none -mode out_of_context

# Save checkpoint (can be opened in Vivado GUI for interactive schematic)
write_checkpoint -force $RPRT_DIR/soc_elaborated.dcp

# Try schematic generation
catch {write_schematic -format pdf -scope all -force $RPRT_DIR/soc_schematic_full.pdf} result
puts "write_schematic all: $result"

catch {write_schematic -format pdf -scope current_page -force $RPRT_DIR/soc_schematic_top.pdf} result
puts "write_schematic top: $result"

# Hierarchy report (always works, text-based)
report_hierarchy -file $RPRT_DIR/soc_hierarchy.rpt

puts "Done. Files in $RPRT_DIR"
puts "To view schematic interactively:"
puts "  vivado $RPRT_DIR/soc_elaborated.dcp"
puts "  Then: Flow -> Open Synthesized Design -> Schematic"
