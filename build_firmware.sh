#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="$SCRIPT_DIR/tinyQV-projects/rv2a03_test"
CONSOLE60K_HEX="$SCRIPT_DIR/FPGA/GOWIN/console60k/src/rv2a03_test.hex"
NANO20K_HEX="$SCRIPT_DIR/FPGA/GOWIN/nano20k/src/rv2a03_test.hex"

echo "============================================================"
echo "   TinyQV RV2A03 Firmware Build System (Bash)              "
echo "   Source: tinyQV-projects/rv2a03_test                     "
echo "============================================================"

# Check toolchain
RISCV_TOOLCHAIN="${RISCV_TOOLCHAIN:-/opt/tinyQV}"
if [ -d "$RISCV_TOOLCHAIN/bin" ]; then
    export PATH="$RISCV_TOOLCHAIN/bin:$PATH"
fi

if ! command -v riscv32-unknown-elf-gcc &> /dev/null; then
    echo "[ERROR] riscv32-unknown-elf-gcc not found in PATH or $RISCV_TOOLCHAIN/bin"
    exit 1
fi

CLEAN=0
SIM=0
NO_COPY_HEX=0

for arg in "$@"; do
    case "$arg" in
        --clean|-clean|-c)
            CLEAN=1
            ;;
        --sim|-sim)
            SIM=1
            ;;
        --no-copy-hex)
            NO_COPY_HEX=1
            ;;
        *)
            ;;
    esac
done

if [ "$CLEAN" -eq 1 ]; then
    echo "[INFO] Cleaning previous build artifacts..."
    make -C "$FIRMWARE_DIR" clean
fi

echo "Building RV2A03 firmware..."
EXTRA_CFLAGS=""
if [ "$SIM" -eq 1 ]; then
    EXTRA_CFLAGS="CFLAGS=-DSIM"
fi

make -C "$FIRMWARE_DIR" all $EXTRA_CFLAGS

BIN_FILE="$FIRMWARE_DIR/rv2a03_test.bin"
HEX_FILE="$FIRMWARE_DIR/rv2a03_test.hex"

if [ -f "$BIN_FILE" ]; then
    BIN_SIZE=$(stat -c%s "$BIN_FILE" 2>/dev/null || stat -f%z "$BIN_FILE" 2>/dev/null || wc -c < "$BIN_FILE")
    BRAM_CAP=32768
    PCT=$(awk "BEGIN {printf \"%.1f\", ($BIN_SIZE / $BRAM_CAP) * 100}")
    echo "------------------------------------------------------------"
    echo "  Memory Utilization Report                                 "
    echo "------------------------------------------------------------"
    echo "  Binary File : $BIN_FILE"
    echo "  Binary Size : $BIN_SIZE bytes / $BRAM_CAP bytes ($PCT% of 32KB BRAM)"
    echo "  Hex File    : $HEX_FILE"
fi

if [ "$NO_COPY_HEX" -eq 0 ]; then
    echo "Updating FPGA project hex files..."
    if [ -d "$(dirname "$CONSOLE60K_HEX")" ]; then
        cp -f "$HEX_FILE" "$CONSOLE60K_HEX"
        echo "[OK] Updated: FPGA/GOWIN/console60k/src/rv2a03_test.hex"
    fi
    if [ -d "$(dirname "$NANO20K_HEX")" ]; then
        cp -f "$HEX_FILE" "$NANO20K_HEX"
        echo "[OK] Updated: FPGA/GOWIN/nano20k/src/rv2a03_test.hex"
    fi
fi

echo "============================================================"
echo "   Firmware Build Complete!                                 "
echo "============================================================"
