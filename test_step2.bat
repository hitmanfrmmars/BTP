@echo off
REM Test Step 2: Address Calculation
echo ========================================
echo   Step 2: Address Calculation Test
echo ========================================
echo.
echo Compiling controller and testbench...
iverilog -g2009 -o sim_step2.vvp rtl/matmul_controller.v testbench/tb_matmul_step2.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    echo.
    vvp sim_step2.vvp
    echo.
    echo Waveform saved to tb_matmul_step2.vcd
    echo View with: gtkwave tb_matmul_step2.vcd
) else (
    echo Compilation failed!
    exit /b 1
)


