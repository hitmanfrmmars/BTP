@echo off
REM Test Step 5: Four-Pass Dot Product
echo ========================================
echo   Step 5: Four-Pass Dot Product Test
echo ========================================
echo.
echo Compiling controller, scratchpad, MAC, and testbench...
iverilog -g2009 -o sim_step5.vvp rtl/matmul_controller.v rtl/scratchpad_mem.v rtl/mac_unit.v testbench/tb_matmul_step5.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    echo.
    vvp sim_step5.vvp
    echo.
    echo Waveform saved to tb_matmul_step5.vcd
    echo View with: gtkwave tb_matmul_step5.vcd
) else (
    echo Compilation failed!
    exit /b 1
)


