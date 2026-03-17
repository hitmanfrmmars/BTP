# ============================================================
# Timing constraints for GEMM Accelerator FPGA synthesis
# Target: Xilinx Artix-7 (xc7a100tcsg324-1)
# Out-of-context mode: only clock constraint needed
# ============================================================

# Primary clock: 100 MHz (10 ns period)
create_clock -period 10.000 -name sys_clk [get_ports clk]
