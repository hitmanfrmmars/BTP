@echo off
REM Vivado XSIM simulation script
REM Usage: run_vivado.bat [testbench_name]

if "%1"=="" (
    echo Usage: run_vivado.bat [testbench_name]
    echo Available testbenches:
    echo   - tb_multiplier_8bit
    echo   - tb_mac_array
    echo   - tb_top
    exit /b 1
)

set TB_NAME=%1

echo Compiling with Vivado XSIM...
xvlog --sv rtl/multiplier_8bit.v rtl/mac_unit.v rtl/mac_array.v rtl/scratchpad_mem.v rtl/dma_controller.v rtl/top.v testbench/%TB_NAME%.v

if %ERRORLEVEL% EQU 0 (
    echo Elaborating design...
    xelab -debug typical %TB_NAME% -s sim_%TB_NAME%
    
    echo Running simulation...
    xsim sim_%TB_NAME% -runall
) else (
    echo Compilation failed!
    exit /b 1
)


