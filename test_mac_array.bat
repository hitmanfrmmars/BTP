@echo off
REM Test for MAC Array (4x4 = 16 MAC units)
echo Compiling MAC Array and testbench...
iverilog -g2009 -o sim_mac_array.vvp rtl/mac_unit.v rtl/mac_array.v testbench/tb_mac_array.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    echo.
    vvp sim_mac_array.vvp
    echo.
    echo Waveform saved to tb_mac_array.vcd
    echo View with: gtkwave tb_mac_array.vcd
) else (
    echo Compilation failed!
    exit /b 1
)


