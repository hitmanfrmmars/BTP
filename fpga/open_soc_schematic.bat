@echo off
REM Opens the SoC synthesized design in Vivado GUI for schematic viewing.
REM 
REM Once Vivado opens:
REM   1. Click "Open Synthesized Design" in the Flow Navigator (left panel)
REM   2. Click "Schematic" in the toolbar (or Window -> Schematic)
REM   3. You'll see the block-level diagram of the full SoC
REM   4. Double-click any block to drill down into its internals
REM   5. To export: File -> Export -> Export Schematic as PDF
REM

set VIVADO_PATH=C:\Xilinx\Vivado\2024.2\bin
"%VIVADO_PATH%\vivado.bat" -mode gui C:\project_sim\fpga\reports\soc_elaborated.dcp
