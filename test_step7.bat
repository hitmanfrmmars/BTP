@echo off
echo ========================================
echo   Step 7: Write-Back Test
echo ========================================
echo.
echo Compiling controller, scratchpad, MAC array, and testbench...

iverilog -g2009 -o sim_step7.vvp ^
    rtl/scratchpad_mem.v ^
    rtl/mac_unit.v ^
    rtl/mac_array.v ^
    rtl/matmul_controller.v ^
    testbench/tb_matmul_step7.v

if %ERRORLEVEL% NEQ 0 (
    echo Compilation failed!
    exit /b 1
)

echo Compilation successful!
echo Running simulation...
echo.

vvp sim_step7.vvp

echo.
echo Waveform saved to tb_matmul_step7.vcd
echo View with: gtkwave tb_matmul_step7.vcd


