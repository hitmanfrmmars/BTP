@echo off
REM Test for MAC Unit (multiply-accumulate)
echo Compiling MAC unit and testbench...
iverilog -g2009 -o sim_mac_unit.vvp rtl/mac_unit.v testbench/tb_mac_unit.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    echo.
    vvp sim_mac_unit.vvp
    echo.
    echo Waveform saved to tb_mac_unit.vcd
    echo View with: gtkwave tb_mac_unit.vcd
) else (
    echo Compilation failed!
    exit /b 1
)


