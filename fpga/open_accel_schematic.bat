@echo off
REM Opens the Accelerator synthesized design in Vivado GUI for schematic viewing.
REM 
REM Once Vivado opens:
REM   1. Click "Open Implemented Design" in the Flow Navigator (left panel)
REM   2. Click "Schematic" in the toolbar (or Window -> Schematic)
REM   3. You'll see the accelerator block diagram
REM   4. Double-click any block to drill down
REM   5. To export: File -> Export -> Export Schematic as PDF
REM

set VIVADO_PATH=C:\Xilinx\Vivado\2024.2\bin
"%VIVADO_PATH%\vivado.bat" -mode gui C:\project_sim\fpga\reports\accel_post_route.dcp
