@echo off
setlocal

set CROSS=C:\Users\aryan\Downloads\xpack-riscv-none-elf-gcc-15.2.0-1-win32-x64\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-
set CC=%CROSS%gcc.exe
set OBJCOPY=%CROSS%objcopy.exe
set SIZE=%CROSS%size.exe
set PYTHON=C:\Users\aryan\AppData\Local\Programs\Python\Python313\python.exe
set ARCH=-march=rv32im -mabi=ilp32
set BUILD=build
set TB=..\testbench
set MEM=32768

if not exist %BUILD% mkdir %BUILD%

echo === Building benchmark ===
%CC% %ARCH% -Os -ffreestanding -nostdlib -nostartfiles -Iinclude -c -o %BUILD%\crt0.o src\crt0.S
if errorlevel 1 goto :fail
%CC% %ARCH% -Os -Wall -Wextra -ffreestanding -nostdlib -nostartfiles -Iinclude -c -o %BUILD%\gemm_accel.o src\gemm_accel.c
if errorlevel 1 goto :fail
%CC% %ARCH% -Os -Wall -Wextra -ffreestanding -nostdlib -nostartfiles -Iinclude -c -o %BUILD%\benchmark.o src\benchmark.c
if errorlevel 1 goto :fail
%CC% %ARCH% -nostdlib -nostartfiles -Tlink.ld -Wl,--gc-sections -o %BUILD%\benchmark.elf %BUILD%\crt0.o %BUILD%\gemm_accel.o %BUILD%\benchmark.o -lgcc
if errorlevel 1 goto :fail
%OBJCOPY% -O binary %BUILD%\benchmark.elf %BUILD%\benchmark.bin
%PYTHON% bin2hex.py %BUILD%\benchmark.bin %BUILD%\benchmark.hex %MEM%
copy /Y %BUILD%\benchmark.hex %TB%\benchmark.hex >nul
%SIZE% %BUILD%\benchmark.elf
echo.

echo === Building stress_test ===
%CC% %ARCH% -Os -Wall -Wextra -ffreestanding -nostdlib -nostartfiles -Iinclude -c -o %BUILD%\stress_test.o src\stress_test.c
if errorlevel 1 goto :fail
%CC% %ARCH% -nostdlib -nostartfiles -Tlink.ld -Wl,--gc-sections -o %BUILD%\stress_test.elf %BUILD%\crt0.o %BUILD%\gemm_accel.o %BUILD%\stress_test.o -lgcc
if errorlevel 1 goto :fail
%OBJCOPY% -O binary %BUILD%\stress_test.elf %BUILD%\stress_test.bin
%PYTHON% bin2hex.py %BUILD%\stress_test.bin %BUILD%\stress_test.hex %MEM%
copy /Y %BUILD%\stress_test.hex %TB%\stress_test.hex >nul
copy /Y %BUILD%\stress_test.hex %TB%\stress_test_fast.hex >nul
%SIZE% %BUILD%\stress_test.elf
echo.

echo === Building nn_layers ===
%CC% %ARCH% -Os -Wall -Wextra -ffreestanding -nostdlib -nostartfiles -Iinclude -c -o %BUILD%\nn_layers.o src\nn_layers.c
if errorlevel 1 goto :fail
%CC% %ARCH% -nostdlib -nostartfiles -Tlink.ld -Wl,--gc-sections -o %BUILD%\nn_layers.elf %BUILD%\crt0.o %BUILD%\gemm_accel.o %BUILD%\nn_layers.o -lgcc
if errorlevel 1 goto :fail
%OBJCOPY% -O binary %BUILD%\nn_layers.elf %BUILD%\nn_layers.bin
%PYTHON% bin2hex.py %BUILD%\nn_layers.bin %BUILD%\nn_layers.hex %MEM%
copy /Y %BUILD%\nn_layers.hex %TB%\nn_layers.hex >nul
%SIZE% %BUILD%\nn_layers.elf
echo.

echo === Building nn_inference ===
%CC% %ARCH% -Os -Wall -Wextra -ffreestanding -nostdlib -nostartfiles -Iinclude -c -o %BUILD%\nn_inference.o src\nn_inference.c
if errorlevel 1 goto :fail
%CC% %ARCH% -nostdlib -nostartfiles -Tlink.ld -Wl,--gc-sections -o %BUILD%\nn_inference.elf %BUILD%\crt0.o %BUILD%\gemm_accel.o %BUILD%\nn_inference.o -lgcc
if errorlevel 1 goto :fail
%OBJCOPY% -O binary %BUILD%\nn_inference.elf %BUILD%\nn_inference.bin
%PYTHON% bin2hex.py %BUILD%\nn_inference.bin %BUILD%\nn_inference.hex %MEM%
copy /Y %BUILD%\nn_inference.hex %TB%\nn_inference.hex >nul
%SIZE% %BUILD%\nn_inference.elf
echo.

echo === Building mnist_inference ===
%CC% %ARCH% -Os -Wall -Wextra -ffreestanding -nostdlib -nostartfiles -Iinclude -c -o %BUILD%\mnist_inference.o src\mnist_inference.c
if errorlevel 1 goto :fail
%CC% %ARCH% -nostdlib -nostartfiles -Tlink.ld -Wl,--gc-sections -o %BUILD%\mnist_inference.elf %BUILD%\crt0.o %BUILD%\gemm_accel.o %BUILD%\mnist_inference.o -lgcc
if errorlevel 1 goto :fail
%OBJCOPY% -O binary %BUILD%\mnist_inference.elf %BUILD%\mnist_inference.bin
%PYTHON% bin2hex.py %BUILD%\mnist_inference.bin %BUILD%\mnist_inference.hex %MEM%
copy /Y %BUILD%\mnist_inference.hex %TB%\mnist_inference.hex >nul
%SIZE% %BUILD%\mnist_inference.elf
echo.

echo === All firmware built with rv32im ===
goto :eof

:fail
echo BUILD FAILED
exit /b 1
