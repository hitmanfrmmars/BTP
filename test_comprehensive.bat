@echo off
echo ========================================
echo   Comprehensive End-to-End Test
echo   Multiple Test Cases
echo ========================================
echo.
echo Compiling full accelerator system...

iverilog -g2009 -o sim_comprehensive.vvp ^
    rtl/scratchpad_mem.v ^
    rtl/mac_unit.v ^
    rtl/mac_array.v ^
    rtl/matmul_controller.v ^
    rtl/dma_controller.v ^
    rtl/top.v ^
    testbench/tb_top_comprehensive.v

if %ERRORLEVEL% NEQ 0 (
    echo Compilation failed!
    exit /b 1
)

echo Compilation successful!
echo Running comprehensive test suite...
echo.

vvp sim_comprehensive.vvp

echo.
echo Waveform saved to tb_top_comprehensive.vcd
echo View with: gtkwave tb_top_comprehensive.vcd


