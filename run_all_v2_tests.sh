#!/bin/bash
# ============================================================
# Run all v2 module tests using Icarus Verilog
# ============================================================

echo "============================================================"
echo " GEMM Accelerator v2 - Full Test Suite"
echo "============================================================"

PASS=0
FAIL=0

run_test() {
    local name="$1"
    shift
    echo ""
    echo "--- Test: $name ---"
    if iverilog -o sim_temp.vvp "$@"; then
        if vvp sim_temp.vvp; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
        rm -f sim_temp.vvp
    else
        echo "COMPILE ERROR: $name"
        FAIL=$((FAIL + 1))
    fi
}

run_test "Scratchpad Memory" \
    rtl/scratchpad_mem.v testbench/tb_scratchpad_mem.v

run_test "MAC Unit v2" \
    rtl/mac_unit_v2.v testbench/tb_mac_unit_v2.v

run_test "MAC Array v2" \
    rtl/mac_unit_v2.v rtl/mac_array_v2.v testbench/tb_mac_array_v2.v

run_test "DMA Engine" \
    rtl/scratchpad_mem.v rtl/dma_engine.v testbench/tb_dma_engine.v

run_test "Matmul Controller v2" \
    rtl/scratchpad_mem.v rtl/mac_unit_v2.v rtl/mac_array_v2.v \
    rtl/matmul_controller_v2.v testbench/tb_matmul_controller_v2.v

run_test "Tiling Engine" \
    rtl/tiling_engine.v testbench/tb_tiling_engine.v

run_test "Full GEMM Accelerator" \
    rtl/scratchpad_mem.v rtl/scratchpad_double_buf.v \
    rtl/mac_unit_v2.v rtl/mac_array_v2.v rtl/dma_engine.v \
    rtl/matmul_controller_v2.v rtl/tiling_engine.v \
    rtl/gemm_regfile.v rtl/gemm_custom_insn.v \
    rtl/gemm_accelerator_top.v testbench/tb_gemm_accelerator.v

echo ""
echo "============================================================"
echo " Test Summary: $PASS passed, $FAIL failed"
echo "============================================================"
