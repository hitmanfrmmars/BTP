@echo off
REM Test Step 4: Single MAC Operation
echo ========================================
echo   Step 4: Single MAC Operation Test
echo ========================================
echo.
echo Compiling controller, scratchpad, MAC, and testbench...
iverilog -g2009 -o sim_step4.vvp rtl/matmul_controller.v rtl/scratchpad_mem.v rtl/mac_unit.v testbench/tb_matmul_step4.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    echo.
    vvp sim_step4.vvp
    echo.
    echo Waveform saved to tb_matmul_step4.vcd
    echo View with: gtkwave tb_matmul_step4.vcd
) else (
    echo Compilation failed!
    exit /b 1
)


