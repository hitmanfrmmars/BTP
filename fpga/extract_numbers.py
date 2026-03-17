#!/usr/bin/env python3
"""Extract paper-ready performance numbers from benchmark + synthesis results."""

# Benchmark results (from tb_benchmark simulation)
bench = [
    {"size": 4,  "sw_cyc": 15367,  "hw_cyc": 99},
    {"size": 8,  "sw_cyc": 113699, "hw_cyc": 465},
    {"size": 16, "sw_cyc": 894291, "hw_cyc": 3105},
]

# Synthesis results (from Vivado reports)
fmax_accel = 100.5
fmax_soc   = 101.8
pwr_accel_dyn = 0.043   # Watts, dynamic only
pwr_soc_dyn   = 0.064
pwr_soc_total = 0.149

array_size = 4

sep = "=" * 72
line = "-" * 72

print(sep)
print("  GEMM Accelerator Performance Summary")
print("  Target: Artix-7 xc7a100tcsg324-1 @ 100 MHz")
print("  MAC Array: 4x4 (16 int8 MACs per cycle)")
print(sep)
print()

# --- Speedup table ---
print("--- Speedup: Hardware Accelerator vs. PicoRV32 Software ---")
print(f"{'Size':>6s} {'SW Cycles':>12s} {'HW Cycles':>12s} {'Speedup':>10s} {'MACs':>8s} {'HW Util%':>10s}")
print(line)

for b in bench:
    s = b["size"]
    total_macs = 2 * s * s * s
    speedup = b["sw_cyc"] / b["hw_cyc"]
    min_cyc = total_macs / 16
    utilization = (min_cyc / b["hw_cyc"]) * 100
    print(f"  {s}x{s:<3d} {b['sw_cyc']:>11,d} {b['hw_cyc']:>11,d} {speedup:>9.1f}x {total_macs:>7,d} {utilization:>9.1f}%")

print()

# --- Throughput table ---
print("--- Throughput at 100 MHz ---")
hdr = f"{'Size':>6s} {'HW Cycles':>11s} {'MACs':>7s} {'Cyc/MAC':>9s} {'GOPS':>10s} {'GOPS/W dyn':>11s} {'GOPS/W SoC':>11s}"
print(hdr)
print(line)

for b in bench:
    s = b["size"]
    total_macs = 2 * s * s * s
    cyc_per_mac = b["hw_cyc"] / total_macs
    gops = (total_macs / b["hw_cyc"]) * (fmax_accel / 1000)
    gops_dyn = gops / pwr_accel_dyn
    gops_soc = gops / pwr_soc_dyn
    print(f"  {s}x{s:<3d} {b['hw_cyc']:>10,d} {total_macs:>7,d} {cyc_per_mac:>9.3f} {gops:>10.4f} {gops_dyn:>11.2f} {gops_soc:>11.2f}")

print()

# --- FPGA utilization ---
print("--- FPGA Resource Utilization ---")
print(f"  {'Resource':<30s} {'Accel Only':>12s} {'Full SoC':>12s}")
print(f"  {'Slice LUTs':<30s} {'1,921':>12s} {'2,822':>12s}")
print(f"  {'Slice Registers':<30s} {'2,065':>12s} {'2,373':>12s}")
print(f"  {'Block RAM (RAMB36)':<30s} {'2':>12s} {'34':>12s}")
print(f"  {'DSP48E1':<30s} {'22':>12s} {'22':>12s}")
print(f"  {'Fmax (MHz)':<30s} {fmax_accel:>12.1f} {fmax_soc:>12.1f}")
print(f"  {'Dynamic Power (mW)':<30s} {pwr_accel_dyn*1000:>12.0f} {pwr_soc_dyn*1000:>12.0f}")
print(f"  {'Total On-Chip Power (mW)':<30s} {'127':>12s} {'149':>12s}")

print()

# --- Key paper metrics ---
s = 16
total_macs = 2 * s * s * s
hw_cyc = 3105
sw_cyc = 894291
gops = (total_macs / hw_cyc) * (fmax_accel / 1000)
speedup = sw_cyc / hw_cyc

print("--- Key Paper Metrics (16x16 GEMM, int8) ---")
print(f"  Speedup over PicoRV32 SW:     {speedup:.0f}x")
print(f"  Throughput:                    {gops:.4f} GOPS")
print(f"  Energy Eff. (accel dynamic):   {gops / pwr_accel_dyn:.2f} GOPS/W")
print(f"  Energy Eff. (SoC dynamic):     {gops / pwr_soc_dyn:.2f} GOPS/W")
print(f"  Area Efficiency:               {gops / 1921 * 1000:.2f} MOPS/LUT")

print()
print("--- 8x8 Array Projection (analytical) ---")
proj_cyc = hw_cyc / 4
gops_8x8 = (total_macs / proj_cyc) * (fmax_accel / 1000)
print(f"  Projected Throughput (8x8):    {gops_8x8:.4f} GOPS")
print(f"  Projected GOPS/W (est 2x pwr): {gops_8x8 / (pwr_soc_dyn * 2):.2f} GOPS/W")

print()
print(sep)
