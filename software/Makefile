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

# Architecture flags
ARCH    ?= -march=rv32i -mabi=ilp32

# Compiler flags
CFLAGS   = $(ARCH) -Os -Wall -Wextra \
           -ffreestanding -nostdlib -nostartfiles \
           -Iinclude

# Linker flags
LDFLAGS  = $(ARCH) -nostdlib -nostartfiles \
           -Tlink.ld -Wl,--gc-sections \
           -Wl,-Map=build/firmware.map

# Source files
ASM_SRC  = src/crt0.S
C_SRC    = src/gemm_accel.c src/main.c

# Build directory
BUILD    = build

# Object files
ASM_OBJ  = $(BUILD)/crt0.o
C_OBJ    = $(patsubst src/%.c,$(BUILD)/%.o,$(C_SRC))
ALL_OBJ  = $(ASM_OBJ) $(C_OBJ)

# Targets
ELF      = $(BUILD)/firmware.elf
BIN      = $(BUILD)/firmware.bin
HEX      = $(BUILD)/firmware.hex

# Total memory words (128KB / 4 = 32768)
MEM_WORDS = 32768

# ============================================================

.PHONY: all clean disasm size sim

all: $(HEX)

$(BUILD):
	mkdir -p $(BUILD)

# Assemble startup code
$(BUILD)/crt0.o: src/crt0.S | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# Compile C sources
$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# Link
$(ELF): $(ALL_OBJ) link.ld
	$(CC) $(LDFLAGS) -o $@ $(ALL_OBJ)

# Extract flat binary
$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

# Convert to $readmemh hex format
$(HEX): $(BIN)
	$(PYTHON) bin2hex.py $< $@ $(MEM_WORDS)

# Copy to testbench directory for simulation
sim: $(HEX)
	cp $(HEX) ../testbench/firmware.hex
	@echo "firmware.hex copied to ../testbench/"

# Disassembly listing
disasm: $(ELF)
	$(OBJDUMP) -d -M no-aliases $<

# Section sizes
size: $(ELF)
	$(SIZE) $<

clean:
	rm -rf $(BUILD)
