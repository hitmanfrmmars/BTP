@echo off
REM ============================================================
REM Run all v2 module tests using Icarus Verilog
REM ============================================================

echo ============================================================
echo  GEMM Accelerator v2 - Full Test Suite
echo ============================================================

set PASS=0
set FAIL=0

REM --- Test 1: Scratchpad Memory ---
echo.
echo --- Test: Scratchpad Memory ---
iverilog -o sim_spad.vvp rtl/scratchpad_mem.v testbench/tb_scratchpad_mem.v
if %errorlevel% neq 0 (set /a FAIL+=1 & goto t2)
vvp sim_spad.vvp
if %errorlevel% neq 0 (set /a FAIL+=1) else (set /a PASS+=1)

:t2
REM --- Test 2: MAC Unit v2 ---
echo.
echo --- Test: MAC Unit v2 ---
iverilog -o sim_mac_v2.vvp rtl/mac_unit_v2.v testbench/tb_mac_unit_v2.v
if %errorlevel% neq 0 (set /a FAIL+=1 & goto t3)
vvp sim_mac_v2.vvp
if %errorlevel% neq 0 (set /a FAIL+=1) else (set /a PASS+=1)

:t3
REM --- Test 3: MAC Array v2 ---
echo.
echo --- Test: MAC Array v2 ---
iverilog -o sim_arr_v2.vvp rtl/mac_unit_v2.v rtl/mac_array_v2.v testbench/tb_mac_array_v2.v
if %errorlevel% neq 0 (set /a FAIL+=1 & goto t4)
vvp sim_arr_v2.vvp
if %errorlevel% neq 0 (set /a FAIL+=1) else (set /a PASS+=1)

:t4
REM --- Test 4: DMA Engine ---
echo.
echo --- Test: DMA Engine ---
iverilog -o sim_dma_v2.vvp rtl/scratchpad_mem.v rtl/dma_engine.v testbench/tb_dma_engine.v
if %errorlevel% neq 0 (set /a FAIL+=1 & goto t5)
vvp sim_dma_v2.vvp
if %errorlevel% neq 0 (set /a FAIL+=1) else (set /a PASS+=1)

:t5
REM --- Test 5: Matmul Controller v2 ---
echo.
echo --- Test: Matmul Controller v2 ---
iverilog -o sim_ctrl_v2.vvp rtl/scratchpad_mem.v rtl/mac_unit_v2.v rtl/mac_array_v2.v rtl/matmul_controller_v2.v testbench/tb_matmul_controller_v2.v
if %errorlevel% neq 0 (set /a FAIL+=1 & goto t6)
vvp sim_ctrl_v2.vvp
if %errorlevel% neq 0 (set /a FAIL+=1) else (set /a PASS+=1)

:t6
REM --- Test 6: Tiling Engine ---
echo.
echo --- Test: Tiling Engine ---
iverilog -o sim_tile.vvp rtl/tiling_engine.v testbench/tb_tiling_engine.v
if %errorlevel% neq 0 (set /a FAIL+=1 & goto t7)
vvp sim_tile.vvp
if %errorlevel% neq 0 (set /a FAIL+=1) else (set /a PASS+=1)

:t7
REM --- Test 7: Full Accelerator ---
echo.
echo --- Test: Full GEMM Accelerator ---
iverilog -o sim_accel.vvp rtl/scratchpad_mem.v rtl/scratchpad_double_buf.v rtl/mac_unit_v2.v rtl/mac_array_v2.v rtl/dma_engine.v rtl/matmul_controller_v2.v rtl/tiling_engine.v rtl/gemm_regfile.v rtl/gemm_custom_insn.v rtl/gemm_accelerator_top.v testbench/tb_gemm_accelerator.v
if %errorlevel% neq 0 (set /a FAIL+=1 & goto summary)
vvp sim_accel.vvp
if %errorlevel% neq 0 (set /a FAIL+=1) else (set /a PASS+=1)

:summary
echo.
echo ============================================================
echo  Test Summary: %PASS% passed, %FAIL% failed
echo ============================================================
