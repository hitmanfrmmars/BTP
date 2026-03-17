@echo off
REM Test Step 6: Parallel (All 16 MACs)
echo ========================================
echo   Step 6: Parallel MAC Array Test
echo ========================================
echo.
echo Compiling controller, scratchpad, MAC array, and testbench...
iverilog -g2009 -o sim_step6.vvp rtl/matmul_controller.v rtl/scratchpad_mem.v rtl/mac_unit.v rtl/mac_array.v testbench/tb_matmul_step6.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    echo.
    vvp sim_step6.vvp
    echo.
    echo Waveform saved to tb_matmul_step6.vcd
    echo View with: gtkwave tb_matmul_step6.vcd
) else (
    echo Compilation failed!
    exit /b 1
)


