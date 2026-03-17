@echo off
REM Simple test for 8-bit multiplier only
echo Compiling 8-bit multiplier and testbench...
iverilog -g2009 -o sim_mult.vvp rtl/multiplier_8bit.v testbench/tb_multiplier_8bit.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    echo.
    vvp sim_mult.vvp
    echo.
    echo Waveform saved to tb_multiplier_8bit.vcd
    echo View with: gtkwave tb_multiplier_8bit.vcd
) else (
    echo Compilation failed!
    exit /b 1
)


