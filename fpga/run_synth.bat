@echo off
REM ============================================================
REM GEMM Accelerator FPGA Synthesis Runner
REM
REM Usage: run_synth.bat [accel|soc|both]
REM   accel  - Synthesize accelerator only
REM   soc    - Synthesize full SoC
REM   both   - Synthesize both (default)
REM
REM Requires: Vivado in PATH (run from Vivado command prompt)
REM   or set VIVADO_PATH below.
REM ============================================================

set VIVADO_PATH=C:\Xilinx\Vivado\2024.2\bin
set PATH=%VIVADO_PATH%;%PATH%

set TARGET=%1
if "%TARGET%"=="" set TARGET=both

cd /d "%~dp0"

if "%TARGET%"=="accel" goto :accel
if "%TARGET%"=="soc" goto :soc
if "%TARGET%"=="both" goto :both
echo Unknown target: %TARGET%
echo Usage: run_synth.bat [accel^|soc^|both]
exit /b 1

:both
:accel
echo.
echo ========================================
echo  Synthesizing GEMM Accelerator Only
echo ========================================
echo.
vivado -mode batch -source synth_accel.tcl -log reports/accel_synth.log -journal reports/accel_synth.jou
if errorlevel 1 (
    echo ERROR: Accelerator synthesis failed. Check reports/accel_synth.log
    if "%TARGET%"=="accel" exit /b 1
)
if "%TARGET%"=="accel" goto :done

:soc
echo.
echo ========================================
echo  Synthesizing Full GEMM SoC
echo ========================================
echo.
vivado -mode batch -source synth_soc.tcl -log reports/soc_synth.log -journal reports/soc_synth.jou
if errorlevel 1 (
    echo ERROR: SoC synthesis failed. Check reports/soc_synth.log
    exit /b 1
)

:done
echo.
echo ========================================
echo  Synthesis complete. Reports in:
echo    fpga\reports\
echo ========================================
dir /b reports\*.rpt 2>nul
