# ============================================================
# Makefile for PicoRV32 GEMM SoC Firmware
# ============================================================
#
# Prerequisites:
#   - RISC-V GCC toolchain (riscv32-unknown-elf-gcc or riscv64-unknown-elf-gcc)
#   - Python 3 (for bin2hex conversion)
#
# Install the toolchain:
#   Windows:  Download from https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases
#             Add the bin/ directory to your PATH.
#   Linux:    sudo apt install gcc-riscv64-unknown-elf
#             (set CROSS=riscv64-unknown-elf- and ARCH=-march=rv32i -mabi=ilp32)
#   macOS:    brew install riscv-gnu-toolchain
#
# Usage:
#   make                 Build firmware.hex
#   make disasm          Show disassembly
#   make size            Show section sizes
#   make clean           Remove build artifacts
#   make sim             Copy firmware.hex to testbench directory
# ============================================================

# Toolchain -- xPack RISC-V GCC (override CROSS to change prefix/path)
CROSS   ?= C:/Users/aryan/Downloads/xpack-riscv-none-elf-gcc-15.2.0-1-win32-x64/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump
SIZE     = $(CROSS)size

# Python
PYTHON  ?= C:/Users/aryan/AppData/Local/Programs/Python/Python313/python.exe

# Architecture flags (rv32im enables hardware MUL instructions)
ARCH    ?= -march=rv32im -mabi=ilp32

# Compiler flags
CFLAGS   = $(ARCH) -Os -Wall -Wextra \
           -ffreestanding -nostdlib -nostartfiles \
           -Iinclude

# Linker flags (-lgcc kept for ABI compat; RV32IM uses native mul)
LDFLAGS  = $(ARCH) -nostdlib -nostartfiles \
           -Tlink.ld -Wl,--gc-sections \
           -Wl,-Map=build/firmware.map \
           -lgcc

# Common source
ASM_SRC  = src/crt0.S
DRV_SRC  = src/gemm_accel.c

# Build directory
BUILD    = build

# Total memory words (128KB / 4 = 32768)
MEM_WORDS = 32768

# ============================================================
# Firmware targets -- each produces $(BUILD)/<name>.hex
#   make firmware       (default -- demo main.c)
#   make stress_test    (21-pattern stress test)
#   make nn_layers      (FC + Conv2D NN layer demo)
#   make benchmark      (SW vs HW benchmark)
#   make all            (build all targets)
# ============================================================

TARGETS = firmware stress_test nn_layers benchmark mnist_inference

.PHONY: all clean disasm size sim $(TARGETS)

all: $(TARGETS)

$(BUILD):
	mkdir -p $(BUILD)

# Assemble startup code (shared by all targets)
$(BUILD)/crt0.o: src/crt0.S | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# Compile C sources
$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# Compile driver (shared)
$(BUILD)/gemm_accel.o: src/gemm_accel.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# Generic rule: link name.elf from crt0.o + gemm_accel.o + name.o
define BUILD_FW
$(BUILD)/$(1).elf: $(BUILD)/crt0.o $(BUILD)/gemm_accel.o $(BUILD)/$(1).o link.ld
	$(CC) $(LDFLAGS) -o $$@ $(BUILD)/crt0.o $(BUILD)/gemm_accel.o $(BUILD)/$(1).o

$(BUILD)/$(1).bin: $(BUILD)/$(1).elf
	$(OBJCOPY) -O binary $$< $$@

$(BUILD)/$(1).hex: $(BUILD)/$(1).bin
	$(PYTHON) bin2hex.py $$< $$@ $(MEM_WORDS)

$(1): $(BUILD)/$(1).hex
	@echo "Built $(BUILD)/$(1).hex"
endef

# Map firmware target to main.c (the original demo)
$(BUILD)/main.o: src/main.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/firmware.elf: $(BUILD)/crt0.o $(BUILD)/gemm_accel.o $(BUILD)/main.o link.ld
	$(CC) $(LDFLAGS) -o $@ $(BUILD)/crt0.o $(BUILD)/gemm_accel.o $(BUILD)/main.o

$(BUILD)/firmware.bin: $(BUILD)/firmware.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/firmware.hex: $(BUILD)/firmware.bin
	$(PYTHON) bin2hex.py $< $@ $(MEM_WORDS)

firmware: $(BUILD)/firmware.hex
	@echo "Built $(BUILD)/firmware.hex"

# Generate build rules for non-default targets
$(eval $(call BUILD_FW,stress_test))
$(eval $(call BUILD_FW,nn_layers))
$(eval $(call BUILD_FW,benchmark))
$(eval $(call BUILD_FW,mnist_inference))

# Copy chosen firmware to testbench directory
sim: firmware
	cp $(BUILD)/firmware.hex ../testbench/firmware.hex
	@echo "firmware.hex copied to ../testbench/"

sim-stress: stress_test
	cp $(BUILD)/stress_test.hex ../testbench/stress_test.hex
	@echo "stress_test.hex copied to ../testbench/"

sim-nn: nn_layers
	cp $(BUILD)/nn_layers.hex ../testbench/nn_layers.hex
	@echo "nn_layers.hex copied to ../testbench/"

sim-bench: benchmark
	cp $(BUILD)/benchmark.hex ../testbench/benchmark.hex
	@echo "benchmark.hex copied to ../testbench/"

sim-mnist: mnist_inference
	cp $(BUILD)/mnist_inference.hex ../testbench/mnist_inference.hex
	@echo "mnist_inference.hex copied to ../testbench/"

sim-all: sim sim-stress sim-nn sim-bench sim-mnist

# Disassembly listing (default firmware)
disasm: $(BUILD)/firmware.elf
	$(OBJDUMP) -d -M no-aliases $<

# Section sizes (default firmware)
size: $(BUILD)/firmware.elf
	$(SIZE) $<

clean:
	rm -rf $(BUILD)
