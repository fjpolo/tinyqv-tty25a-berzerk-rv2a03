#!/usr/bin/env bash
# ==============================================================================
# TinyQV RV2A03 Firmware Build & SoC Simulation Script
# ==============================================================================
set -e

# Resolve repository root directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROG="${1:-rv2a03_test}"
WAVES_ARG="${2:-1}"

VCD=0
WAVES=0
if [ "$WAVES_ARG" = "1" ] || [ "$WAVES_ARG" = "vcd" ]; then
    VCD=1
    WAVE_TYPE="VCD"
elif [ "$WAVES_ARG" = "fst" ]; then
    WAVES=1
    WAVE_TYPE="FST"
else
    WAVE_TYPE="OFF"
fi

echo "======================================================"
echo "  TinyQV Build & Simulation: ${PROG} (Waves: ${WAVE_TYPE})"
echo "======================================================"

# 1. Build SDK runtime libraries if needed
if [ ! -f "$REPO_ROOT/tinyQV-sdk-fjpolo/start.o" ] || [ ! -f "$REPO_ROOT/tinyQV-sdk-fjpolo/tinyQV.a" ]; then
    echo ""
    echo "--- [1/3] Building TinyQV SDK runtime libraries ---"
    make -C "$REPO_ROOT/tinyQV-sdk-fjpolo"
fi

# 2. Build Firmware Application
echo ""
echo "--- [2/3] Compiling firmware project: ${PROG} ---"
PROG_DIR="$REPO_ROOT/tinyQV-projects/${PROG}"
if [ ! -d "$PROG_DIR" ]; then
    echo "ERROR: Project directory not found: $PROG_DIR"
    exit 1
fi

make -C "$PROG_DIR" clean
make -C "$PROG_DIR" CFLAGS="-DSIM"


HEX_SRC="$PROG_DIR/${PROG}.hex"
if [ ! -f "$HEX_SRC" ]; then
    echo "ERROR: Hex file was not generated: $HEX_SRC"
    exit 1
fi

# Deploy hex to simulation test directory and pad to 128KB (131072 words) to eliminate $readmemh warning
SIM_DIR="$REPO_ROOT/ttsky25a-tinyQV-fjpolo-rv2a03/test"
echo "Deploying and padding ${PROG}.hex to 128KB -> ${SIM_DIR}/"
python3 -c "
with open('$HEX_SRC', 'r') as f:
    words = f.read().split()
target = 131072
if len(words) < target:
    words += ['00'] * (target - len(words))
with open('$SIM_DIR/${PROG}.hex', 'w') as f:
    for i in range(0, target, 4):
        f.write(' ' + ' '.join(words[i:i+4]) + '\n')
"




# 3. Run cocotb Simulation
echo ""
echo "--- [3/3] Running SoC simulation with cocotb ---"
cd "$SIM_DIR"

# Activate Python virtual environment
if [ -f "$REPO_ROOT/tinyqv-rv2a03/test/.venv/bin/activate" ]; then
    source "$REPO_ROOT/tinyqv-rv2a03/test/.venv/bin/activate"
elif [ -f "$REPO_ROOT/ttsky25a-tinyQV-fjpolo-rv2a03/test/.venv/bin/activate" ]; then
    source "$REPO_ROOT/ttsky25a-tinyQV-fjpolo-rv2a03/test/.venv/bin/activate"
else
    echo "WARNING: No .venv found. Running with system Python environment."
fi

# Clean previous simulation results and build cache
rm -rf sim_build results.xml
export PYTHONUNBUFFERED=1
make -f test_prog.mk PROG="${PROG}" VCD="${VCD}" WAVES="${WAVES}"

# Copy artifacts to repository root for convenient user access
if [ -f "$SIM_DIR/tb_qspi.vcd" ]; then
    cp "$SIM_DIR/tb_qspi.vcd" "$REPO_ROOT/tb_qspi.vcd"
    echo "Waveform file created: $REPO_ROOT/tb_qspi.vcd"
fi
if [ -f "$SIM_DIR/rv2a03_audio.wav" ]; then
    cp "$SIM_DIR/rv2a03_audio.wav" "$REPO_ROOT/rv2a03_audio.wav"
    echo "Audio WAV file created: $REPO_ROOT/rv2a03_audio.wav"
fi


echo ""
echo "======================================================"
echo "  Build & Simulation Finished Successfully!"
echo "======================================================"
