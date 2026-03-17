@echo off
REM ModelSim/QuestaSim simulation script
REM Usage: run_modelsim.bat [testbench_name]

if "%1"=="" (
    echo Usage: run_modelsim.bat [testbench_name]
    echo Available testbenches:
    echo   - tb_multiplier_8bit
    echo   - tb_mac_array
    echo   - tb_top
    exit /b 1
)

set TB_NAME=%1

echo Compiling with ModelSim...
vlog rtl/multiplier_8bit.v rtl/mac_unit.v rtl/mac_array.v rtl/scratchpad_mem.v rtl/dma_controller.v rtl/top.v testbench/%TB_NAME%.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    vsim -c %TB_NAME% -do "run -all; quit -f"
) else (
    echo Compilation failed!
    exit /b 1
)


