# ============================================================================
# GEMM Accelerator FPGA Programming Script
# Usage: vivado -mode batch -source program.tcl
# ============================================================================

set proj_dir  "./vivado_project"
set top       "gemm_accelerator_top"
set bit_file  "${proj_dir}/gemm_accelerator.runs/impl_1/${top}.bit"

# Open hardware manager
open_hw_manager
connect_hw_server -allow_non_jtag

# Detect hardware target
open_hw_target

# Get FPGA device
set hw_device [get_hw_devices xc7a100t_0]
current_hw_device $hw_device

# Set bitstream file
set_property PROGRAM.FILE $bit_file $hw_device

# Program the FPGA
puts "Programming FPGA with $bit_file ..."
program_hw_devices $hw_device

puts "FPGA programmed successfully!"

# Close
close_hw_target
disconnect_hw_server
close_hw_manager
