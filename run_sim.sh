#!/bin/bash
# Simulation script for Icarus Verilog
# Usage: ./run_sim.sh [testbench_name]
# Example: ./run_sim.sh tb_multiplier_8bit

if [ -z "$1" ]; then
    echo "Usage: ./run_sim.sh [testbench_name]"
    echo "Available testbenches:"
    echo "  - tb_multiplier_8bit"
    echo "  - tb_mac_array"
    echo "  - tb_top"
    exit 1
fi

TB_NAME=$1

echo "Compiling RTL and testbench..."
iverilog -o sim_${TB_NAME} \
    rtl/multiplier_8bit.v \
    rtl/mac_unit.v \
    rtl/mac_array.v \
    rtl/scratchpad_mem.v \
    rtl/dma_controller.v \
    rtl/top.v \
    testbench/${TB_NAME}.v

if [ $? -eq 0 ]; then
    echo "Compilation successful!"
    echo "Running simulation..."
    vvp sim_${TB_NAME}
    echo ""
    echo "Waveform saved to ${TB_NAME}.vcd"
    echo "View with: gtkwave ${TB_NAME}.vcd"
else
    echo "Compilation failed!"
    exit 1
fi


