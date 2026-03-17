@echo off
REM Test for DMA Controller
echo Compiling DMA Controller, Scratchpad Memory, and testbench...
iverilog -g2009 -o sim_dma.vvp rtl/dma_controller.v rtl/scratchpad_mem.v testbench/tb_dma_controller.v

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo Running simulation...
    echo.
    vvp sim_dma.vvp
    echo.
    echo Waveform saved to tb_dma_controller.vcd
    echo View with: gtkwave tb_dma_controller.vcd
) else (
    echo Compilation failed!
    exit /b 1
)


