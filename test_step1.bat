@echo off
REM Test Step 1: State Machine Skeleton
echo ========================================
echo   Step 1: State Machine Skeleton Test
echo ========================================
echo.
echo Compiling controller and testbench...
iverilog -g2009 -o sim_step1.vvp rtl/matmul_controller.v testbench/tb_matmul_step1.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    echo.
    vvp sim_step1.vvp
    echo.
    echo Waveform saved to tb_matmul_step1.vcd
    echo View with: gtkwave tb_matmul_step1.vcd
) else (
    echo Compilation failed!
    exit /b 1
)


