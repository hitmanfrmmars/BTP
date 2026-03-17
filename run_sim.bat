@echo off
REM Simulation script for Windows with Icarus Verilog
REM Usage: run_sim.bat [testbench_name]
REM Example: run_sim.bat tb_multiplier_8bit

if "%1"=="" (
    echo Usage: run_sim.bat [testbench_name]
    echo Available testbenches:
    echo   - tb_multiplier_8bit
    echo   - tb_mac_array
    echo   - tb_top
    exit /b 1
)

set TB_NAME=%1

echo Compiling RTL and testbench...
iverilog -o sim_%TB_NAME%.vvp ^
    rtl/multiplier_8bit.v ^
    rtl/mac_unit.v ^
    rtl/mac_array.v ^
    rtl/scratchpad_mem.v ^
    rtl/dma_controller.v ^
    rtl/top.v ^
    testbench/%TB_NAME%.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    vvp sim_%TB_NAME%.vvp
    echo.
    echo Waveform saved to %TB_NAME%.vcd
    echo View with: gtkwave %TB_NAME%.vcd
) else (
    echo Compilation failed!
    exit /b 1
)


