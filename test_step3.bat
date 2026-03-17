@echo off
REM Test Step 3: Single Data Load
echo ========================================
echo   Step 3: Single Data Load Test
echo ========================================
echo.
echo Compiling controller, scratchpad, and testbench...
iverilog -g2009 -o sim_step3.vvp rtl/matmul_controller.v rtl/scratchpad_mem.v testbench/tb_matmul_step3.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    echo.
    vvp sim_step3.vvp
    echo.
    echo Waveform saved to tb_matmul_step3.vcd
    echo View with: gtkwave tb_matmul_step3.vcd
) else (
    echo Compilation failed!
    exit /b 1
)


