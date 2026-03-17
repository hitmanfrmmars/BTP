@echo off
echo ========================================
echo   Step 8: End-to-End Integration Test
echo ========================================
echo.
echo Compiling full accelerator system...

iverilog -g2009 -o sim_step8.vvp ^
    rtl/scratchpad_mem.v ^
    rtl/mac_unit.v ^
    rtl/mac_array.v ^
    rtl/matmul_controller.v ^
    rtl/dma_controller.v ^
    rtl/top.v ^
    testbench/tb_top_complete.v

if %ERRORLEVEL% NEQ 0 (
    echo Compilation failed!
    exit /b 1
)

echo Compilation successful!
echo Running end-to-end simulation...
echo.

vvp sim_step8.vvp

echo.
echo Waveform saved to tb_top_complete.vcd
echo View with: gtkwave tb_top_complete.vcd


