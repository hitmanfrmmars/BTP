$ErrorActionPreference = "Stop"

$CROSS = "C:/Users/aryan/Downloads/xpack-riscv-none-elf-gcc-15.2.0-1-win32-x64/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-"
$CC = "${CROSS}gcc.exe"
$OBJCOPY = "${CROSS}objcopy.exe"
$PYTHON = "C:/Users/aryan/AppData/Local/Programs/Python/Python313/python.exe"

$ARCH = "-march=rv32im -mabi=ilp32"
$CFLAGS = "$ARCH -Os -Wall -Wextra -ffreestanding -nostdlib -nostartfiles -Iinclude"
$MEM_WORDS = 32768

$BUILD = "build"
$TB = "../testbench"

if (-not (Test-Path $BUILD)) { New-Item -ItemType Directory -Path $BUILD -Force | Out-Null }

function Build-Firmware {
    param([string]$Name, [string[]]$CSources)
    
    Write-Host "=== Building $Name ===" -ForegroundColor Cyan
    
    # Compile crt0.S
    $cmd = "$CC $ARCH -Os -ffreestanding -nostdlib -nostartfiles -Iinclude -c -o $BUILD/crt0.o src/crt0.S"
    Write-Host "  [ASM] crt0.S"
    Invoke-Expression $cmd
    
    # Compile each C source
    $objs = @("$BUILD/crt0.o")
    foreach ($src in $CSources) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($src)
        $cmd = "$CC $ARCH -Os -Wall -Wextra -ffreestanding -nostdlib -nostartfiles -Iinclude -c -o $BUILD/$base.o $src"
        Write-Host "  [CC]  $src"
        Invoke-Expression $cmd
        $objs += "$BUILD/$base.o"
    }
    
    # Link
    $objStr = $objs -join " "
    $cmd = "$CC $ARCH -nostdlib -nostartfiles -Tlink.ld -Wl,--gc-sections -o $BUILD/$Name.elf $objStr -lgcc"
    Write-Host "  [LD]  $Name.elf"
    Invoke-Expression $cmd
    
    # objcopy
    $cmd = "$OBJCOPY -O binary $BUILD/$Name.elf $BUILD/$Name.bin"
    Write-Host "  [BIN] $Name.bin"
    Invoke-Expression $cmd
    
    # hex
    $cmd = "$PYTHON bin2hex.py $BUILD/$Name.bin $BUILD/$Name.hex $MEM_WORDS"
    Write-Host "  [HEX] $Name.hex"
    Invoke-Expression $cmd
    
    # Copy to testbench
    Copy-Item "$BUILD/$Name.hex" "$TB/$Name.hex" -Force
    Write-Host "  [CP]  -> $TB/$Name.hex" -ForegroundColor Green
    
    # Size
    & "${CROSS}size.exe" "$BUILD/$Name.elf"
    Write-Host ""
}

# Build all firmware targets
Build-Firmware "benchmark" @("src/gemm_accel.c", "src/benchmark.c")
Build-Firmware "stress_test" @("src/gemm_accel.c", "src/stress_test.c")
Build-Firmware "nn_layers" @("src/gemm_accel.c", "src/nn_layers.c")
Build-Firmware "mnist_inference" @("src/gemm_accel.c", "src/mnist_inference.c")

Write-Host "=== All firmware built with rv32im ===" -ForegroundColor Green
