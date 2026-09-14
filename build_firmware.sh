#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPGA_FIRMWARE_DIR="$SCRIPT_DIR/tinyQV-projects/rv2a03_fpga"
ASIC_FIRMWARE_DIR="$SCRIPT_DIR/tinyQV-projects/rv2a03_asic"
LEGACY_DIR="$SCRIPT_DIR/tinyQV-projects/rv2a03_test"
CONSOLE60K_HEX="$SCRIPT_DIR/FPGA/GOWIN/console60k/src/rv2a03_test.hex"
NANO20K_HEX="$SCRIPT_DIR/FPGA/GOWIN/nano20k/src/rv2a03_test.hex"

TARGET="all"
CLEAN=0
SIM=0
NO_COPY_HEX=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target|-target|-t)
            TARGET="$2"
            shift 2
            ;;
        --target=*)
            TARGET="${1#*=}"
            shift
            ;;
        --clean|-clean|-c)
            CLEAN=1
            shift
            ;;
        --sim|-sim)
            SIM=1
            shift
            ;;
        --no-copy-hex)
            NO_COPY_HEX=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo "============================================================"
echo "   TinyQV RV2A03 Dual-Target Firmware Build System (Bash)  "
echo "   Targets: FPGA (Tang 60K/20K) & ASIC (TTSKY25a EVK)      "
echo "   Selected: $TARGET                                       "
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

build_project() {
    local proj_dir="$1"
    local proj_name="$2"

    if [ ! -d "$proj_dir" ]; then
        echo "[ERROR] Project directory not found: $proj_dir"
        exit 1
    fi

    echo ""
    echo "------------------------------------------------------------"
    echo "  Building $proj_name..."
    echo "------------------------------------------------------------"

    if [ "$CLEAN" -eq 1 ]; then
        echo "[INFO] Cleaning $proj_name..."
        make -C "$proj_dir" clean
    fi

    local extra_cflags=""
    if [ "$SIM" -eq 1 ]; then
        extra_cflags="CFLAGS=-DSIM"
    fi

    make -C "$proj_dir" all $extra_cflags

    local bin_file="$proj_dir/${proj_name}.bin"
    local hex_file="$proj_dir/${proj_name}.hex"

    if [ -f "$bin_file" ]; then
        local bin_size
        bin_size=$(stat -c%s "$bin_file" 2>/dev/null || stat -f%z "$bin_file" 2>/dev/null || wc -c < "$bin_file")
        echo "[OK] $proj_name built successfully! ($bin_size bytes)"
        echo "  Binary : $bin_file"
        echo "  Hex    : $hex_file"
    fi
}

# 1. Build FPGA Target
if [ "$TARGET" = "all" ] || [ "$TARGET" = "fpga" ]; then
    build_project "$FPGA_FIRMWARE_DIR" "rv2a03_fpga"

    # Also build legacy rv2a03_test for backward compatibility
    if [ -d "$LEGACY_DIR" ]; then
        build_project "$LEGACY_DIR" "rv2a03_test"
    fi

    if [ "$NO_COPY_HEX" -eq 0 ]; then
        echo "Updating FPGA project hex files..."
        local_fpga_hex="$FPGA_FIRMWARE_DIR/rv2a03_fpga.hex"
        if [ -d "$(dirname "$CONSOLE60K_HEX")" ]; then
            cp -f "$local_fpga_hex" "$CONSOLE60K_HEX"
            echo "[OK] Updated: FPGA/GOWIN/console60k/src/rv2a03_test.hex"
        fi
        if [ -d "$(dirname "$NANO20K_HEX")" ]; then
            cp -f "$local_fpga_hex" "$NANO20K_HEX"
            echo "[OK] Updated: FPGA/GOWIN/nano20k/src/rv2a03_test.hex"
        fi
    fi
fi

# 2. Build ASIC Target
if [ "$TARGET" = "all" ] || [ "$TARGET" = "asic" ]; then
    build_project "$ASIC_FIRMWARE_DIR" "rv2a03_asic"

    asic_bin="$ASIC_FIRMWARE_DIR/rv2a03_asic.bin"
    asic_size=$(stat -c%s "$asic_bin" 2>/dev/null || stat -f%z "$asic_bin" 2>/dev/null || wc -c < "$asic_bin")

    echo ""
    echo "------------------------------------------------------------"
    echo "  TTSKY25a EVK Flashing Instructions                        "
    echo "------------------------------------------------------------"
    echo "  Target Chip   : TinyQV Sky25a Berzerk (Slot 14)"
    echo "  Binary File   : $asic_bin"
    echo "  Binary Size   : $asic_size bytes"
    echo "  Web Programmer: https://program.tinyqv.com"
    echo "  CLI Command   : python -m tt_commander program flash rv2a03_asic.bin"
fi

echo ""
echo "============================================================"
echo "   Firmware Build Complete!                                 "
echo "============================================================"
