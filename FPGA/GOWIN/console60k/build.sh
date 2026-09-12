#!/usr/bin/env bash
# ==============================================================================
# Gowin EDA Build & Flash Script for Sipeed Tang Console 60K
# Project: TinyQV RISC-V SoC with RV2A03 NES APU
# Target: GW5AT-LV60PG484AC1/I0
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TARGET="${1:-all}"

echo "============================================================"
echo "   Sipeed Tang Console 60K - Gowin EDA Build Flow"
echo "   Project: TinyQV RISC-V SoC + RV2A03 APU"
echo "   Target : $TARGET"
echo "============================================================"

# Auto-detect gw_sh executable
GW_SH=""
if command -v gw_sh &> /dev/null; then
    GW_SH="gw_sh"
elif command -v gw_sh.exe &> /dev/null; then
    GW_SH="gw_sh.exe"
else
    # Check common Windows paths when running from Git Bash / MSYS2 / WSL
    for p in \
        "/c/Gowin/Gowin_V1.9.12_x64/IDE/bin/gw_sh.exe" \
        "/c/Gowin/Gowin_V1.9.11_x64/IDE/bin/gw_sh.exe" \
        "/c/Gowin/Gowin_V1.9.10_x64/IDE/bin/gw_sh.exe" \
        "/c/Gowin/Gowin_V1.9.9_x64/IDE/bin/gw_sh.exe" \
        "C:/Gowin/Gowin_V1.9.12_x64/IDE/bin/gw_sh.exe" \
        "C:/Gowin/Gowin_V1.9.11_x64/IDE/bin/gw_sh.exe" \
        "C:/Gowin/Gowin_V1.9.9_x64/IDE/bin/gw_sh.exe"; do
        if [ -f "$p" ]; then
            GW_SH="$p"
            break
        fi
    done
fi

if [ -z "$GW_SH" ]; then
    echo "ERROR: gw_sh not found! Please ensure Gowin EDA is installed or in PATH."
    exit 1
fi

echo "[OK] Found Gowin Shell: $GW_SH"

# Clean if requested
if [ "$TARGET" = "clean" ]; then
    echo "Cleaning build artifacts..."
    rm -rf impl console60k.gprj.user
    echo "[OK] Cleaned."
    exit 0
fi

# Run Gowin Tcl flow
"$GW_SH" build.tcl "$TARGET"

BITSTREAM="impl/pnr/console60k.fs"
if [ "$TARGET" = "all" ] && [ -f "$BITSTREAM" ]; then
    SIZE=$(du -h "$BITSTREAM" | cut -f1)
    echo "============================================================"
    echo "  BUILD SUCCESSFUL!"
    echo "  Bitstream: $BITSTREAM ($SIZE)"
    echo "============================================================"
fi
