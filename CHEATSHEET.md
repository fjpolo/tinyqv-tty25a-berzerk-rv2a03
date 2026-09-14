# TinyQV Sky25a Berzerk (RV2A03) — Project Cheatsheet

A concise, comprehensive reference guide and command cheatsheet for the **TinyQV RISC-V SoC** with the **RV2A03 NES APU Sound Peripheral** on Tiny Tapeout Sky25a and Gowin FPGAs (Tang Console 60K & Tang Nano 20K).

---

## Table of Contents
1. [Fast Lane: Most Common Commands](#1-fast-lane-most-common-commands)
2. [Workspace Architecture & Components](#2-workspace-architecture--components)
3. [Firmware Build System](#3-firmware-build-system)
4. [FPGA Build & Flashing (Tang Console 60K)](#4-fpga-build--flashing-tang-console-60k)
5. [FPGA Build & Flashing (Tang Nano 20K)](#5-fpga-build--flashing-tang-nano-20k)
6. [Serial Monitor & Telemetry (115200 8N1)](#6-serial-monitor--telemetry-115200-8n1)
7. [Simulation & Waveform Analysis](#7-simulation--waveform-analysis)
8. [TinyQV C SDK & RV2A03 Driver API](#8-tinyqv-c-sdk--rv2a03-driver-api)
9. [MicroPython Runtime](#9-micropython-runtime)
10. [ASIC Tapeout Flow (OpenLane)](#10-asic-tapeout-flow-openlane)
11. [Git Submodule Maintenance](#11-git-submodule-maintenance)
12. [Hardware Pinouts & Diagnostics](#12-hardware-pinouts--diagnostics)

---

## 1. Fast Lane: Most Common Commands

| Task | Platform / Shell | Command |
| :--- | :--- | :--- |
| **Compile firmware & sync hex** | PowerShell / CMD | `.\build_firmware.bat` |
| **Clean & recompile firmware** | PowerShell / CMD | `.\build_firmware.bat -Clean` |
| **Compile firmware (Linux / WSL)** | Bash | `./build_firmware.sh --clean` |
| **End-to-End: Firmware $\rightarrow$ Bitstream $\rightarrow$ Flash Console 60K** | PowerShell / CMD | `.\build_firmware.bat -RebuildFpga console60k -Flash sram` |
| **End-to-End: Firmware $\rightarrow$ Bitstream $\rightarrow$ Flash Nano 20K** | PowerShell / CMD | `.\build_firmware.bat -RebuildFpga nano20k -Flash flash` |
| **Build Console 60K FPGA bitstream** | PowerShell / CMD | `.\build_console60k.bat` |
| **Flash Console 60K bitstream (SRAM)** | PowerShell / CMD | `.\build_console60k.bat -Flash sram` |
| **Flash Console 60K bitstream (SPI Flash)** | PowerShell / CMD | `.\build_console60k.bat -Flash flash` |
| **Flash existing Console 60K bitstream (no build)**| PowerShell / CMD | `.\build_console60k.bat -NoBuild -Flash sram` |
| **Build Nano 20K FPGA bitstream** | PowerShell / CMD | `.\build_gowin.bat` |
| **Flash Nano 20K bitstream (SPI Flash)** | PowerShell / CMD | `.\build_gowin.bat -Flash flash` |
| **Scan connected Gowin USB cables** | PowerShell / CMD | `.\build_console60k.bat -Scan` |
| **Open Console 60K Serial Monitor (COM19)** | PowerShell / CMD | `.\serial_monitor_console60k.bat` |
| **Open Nano 20K Serial Monitor (COM17)** | PowerShell / CMD | `.\serial_monitor.bat` |
| **List detected COM ports** | PowerShell | `.\serial_monitor.ps1 -List` |
| **Run SoC cocotb Simulation** | WSL / Linux Bash | `./run_rv2a03_simulation.sh` |
| **Run SoC Simulation with VCD waves** | WSL / Linux Bash | `./build_and_sim.sh rv2a03_test 1` |
| **View simulation waveforms** | Linux / GUI | `gtkwave tb_qspi.vcd tb_apu.gtkw` |

---

## 2. Workspace Architecture & Components

| Directory | Submodule / Repository | Configured Branch | Purpose |
| :--- | :--- | :--- | :--- |
| `tinyQV-projects/rv2a03_test` | `fjpolo/tinyQV-projects` | `dev/20290907` | RV2A03 self-checking testsuite & chiptune demo |
| `tinyQV-sdk-fjpolo` | `fjpolo/tinyQV-sdk-fjpolo` | `main` | C runtime, linker scripts, and RV2A03 peripheral driver |
| `FPGA/GOWIN/console60k` | Local Workspace | `master` | Gowin Arora V GW5AT-60B FPGA implementation |
| `FPGA/GOWIN/nano20k` | Local Workspace | `master` | Gowin GW2AR-18C FPGA implementation |
| `tinyqv-rv2a03` | `fjpolo/tinyqv-rv2a03` | `main` | Standalone RV2A03 hardware IP & cocotb unit tests |
| `ttsky25a-tinyQV-fjpolo-rv2a03` | `fjpolo/ttsky25a-tinyQV-fjpolo-rv2a03` | `fjpolo/RV2A03` | Full SoC Sky25a ASIC hardening (OpenLane) |
| `micropython` | `MichaelBell/micropython` | `tinyqv-sky25a` | MicroPython runtime port for TinyQV |

- **Toolchain**: GCC 15 `riscv32ec-15.1.0-tqv-2.0` (`rv32ec_zcb_zicond` / `ilp32e`) installed at `/opt/tinyQV` in WSL or native Windows.
- **On-chip BRAM ceiling**: **32 KB (32,768 bytes)**. Firmware binary must remain under this limit.

---

## 3. Firmware Build System

The firmware build scripts automatically compile the C firmware in `tinyQV-projects/rv2a03_test`, verify binary size against the 32 KB BRAM ceiling, and synchronize `rv2a03_test.hex` to both `FPGA/GOWIN/console60k/src/` and `FPGA/GOWIN/nano20k/src/`.

### Windows PowerShell / CMD (`build_firmware.bat` / `build_firmware.ps1`)

```powershell
# Standard compilation & hex copy:
.\build_firmware.bat

# Clean previous build artifacts and compile from scratch:
.\build_firmware.bat -Clean

# Compile with simulation flags (CFLAGS="-DSIM" for fast clocks):
.\build_firmware.bat -Sim

# Compile without copying hex to FPGA projects:
.\build_firmware.bat -NoCopyHex

# Full end-to-end pipeline: compile firmware, update hex, rebuild bitstream, and flash FPGA:
.\build_firmware.bat -RebuildFpga console60k -Flash sram
.\build_firmware.bat -RebuildFpga console60k -Flash flash
.\build_firmware.bat -RebuildFpga nano20k -Flash flash
```

### Linux / WSL (`build_firmware.sh`)

```bash
# Standard compilation:
./build_firmware.sh

# Clean & rebuild:
./build_firmware.sh --clean

# Fast simulation build:
./build_firmware.sh --sim

# Build without syncing hex:
./build_firmware.sh --no-copy-hex
```

### Manual Firmware Compilation (Inside Submodule)

```bash
# Compile SDK libraries first (if not built):
make -C tinyQV-sdk-fjpolo

# Build rv2a03_test firmware:
cd tinyQV-projects/rv2a03_test
make clean
make

# Build other demo projects (e.g. donut):
cd tinyQV-projects/donut
make TINYQV_SDK=../../tinyQV-sdk-fjpolo
```

---

## 4. FPGA Build & Flashing (Tang Console 60K)

- **FPGA Chip**: Gowin Arora V **GW5AT-LV60PG484AC1/I0** (`GW5AT-60B`)
- **Clock**: 50 MHz oscillator synthesized to 27.000 MHz via Arora V PLLA
- **Audio**: Delta-Sigma DAC $\rightarrow$ PAM8403 amplifier & oval speaker on lower PMOD (PMOD0)
- **LEDs**: 8-LED bar on upper PMOD (PMOD1)
- **UART**: 115200 8N1 via onboard BL616 MCU (typically `COM19`)

### Commands (Root Workspace)

```powershell
# 1. Full build (Synthesis + Place & Route + Bitstream):
.\build_console60k.bat

# 2. Flash bitstream directly to SRAM (volatile, immediate testing):
.\build_console60k.bat -Flash sram

# 3. Flash bitstream to persistent onboard SPI Flash:
.\build_console60k.bat -Flash flash

# 4. Flash existing bitstream directly without re-synthesizing:
.\build_console60k.bat -NoBuild -Flash sram
.\build_console60k.bat -NoBuild -Flash flash

# 5. Clean build folder and rebuild:
.\build_console60k.bat -Clean

# 6. Scan JTAG cables & devices:
.\build_console60k.bat -Scan
```

### Commands (Inside `FPGA/GOWIN/console60k/`)

```powershell
# PowerShell:
.\build.ps1 -Flash sram
.\build.ps1 -Flash flash
.\build.ps1 -Target syn    # Synthesis only
.\build.ps1 -Target pnr    # Place & Route only

# Bash (Linux / MSYS2):
./build.sh
```

---

## 5. FPGA Build & Flashing (Tang Nano 20K)

- **FPGA Chip**: Gowin **GW2AR-LV18QN88C8/I7** (`GW2AR-18C`)
- **Clock**: 27.000 MHz onboard oscillator
- **Audio**: MAX98357A I2S Class-D amplifier (16-bit 46.875 kHz stereo PCM)
- **UART**: 115200 8N1 via onboard BL616 MCU (typically `COM17`)

### Commands (Root Workspace)

```powershell
# 1. Full build (Synthesis + Place & Route + Bitstream):
.\build_gowin.bat

# 2. Flash bitstream to persistent onboard SPI Flash (exFlash mode 8):
.\build_gowin.bat -Flash flash

# 3. Flash bitstream to volatile SRAM:
.\build_gowin.bat -Flash sram

# 4. Flash existing bitstream without re-compiling:
.\build_gowin.bat -NoBuild -Flash flash

# 5. Clean build folder and rebuild:
.\build_gowin.bat -Clean

# 6. Scan JTAG cables & devices:
.\build_gowin.bat -Scan
```

### Generic Gowin Script (`build_gowin.ps1`)

```powershell
# Target specific board from PowerShell:
.\build_gowin.ps1 -Board console60k -Flash sram
.\build_gowin.ps1 -Board nano20k -Flash flash
```

---

## 6. Serial Monitor & Telemetry (115200 8N1)

Both FPGA targets output real-time boot status, self-test results, and chiptune song logs over UART at **115,200 baud, 8 data bits, no parity, 1 stop bit**.

### Tang Console 60K (COM19)

```powershell
# One-click launch (auto-detects COM19 / BL616):
.\serial_monitor_console60k.bat

# PowerShell direct with options:
.\serial_monitor_console60k.ps1
.\serial_monitor_console60k.ps1 -Port COM19
.\serial_monitor_console60k.ps1 -Port COM19 -LogFile console60k_uart.log
.\serial_monitor_console60k.ps1 -List
```

### Tang Nano 20K (COM17)

```powershell
# One-click launch (auto-detects COM17 / USB-Serial):
.\serial_monitor.bat

# PowerShell direct with options:
.\serial_monitor.ps1
.\serial_monitor.ps1 -Port COM17
.\serial_monitor.ps1 -Port COM17 -LogFile nano20k_uart.log
.\serial_monitor.ps1 -List

# Python CLI monitor (cross-platform):
python serial_monitor.py COM17 115200
```

### VS Code Task Integration
- Press `Ctrl+Shift+P` $\rightarrow$ **`Tasks: Run Task`** $\rightarrow$ select **`Serial Monitor: Tang Nano 20K (115200)`**.

### Expected UART Output & Synthesizer Interface
Upon boot, the firmware runs the 5/5 self-test suite and opens the live interactive NES Synthesizer & Soundboard:

```text
=====================================================
  TinyQV RV2A03 NES APU Sound Peripheral Testsuite  
  Target: Sky25a Berzerk (Peripheral Index 14)      
=====================================================

[TEST 1] Testing Square Channel 1 (440 Hz)... PASS
[TEST 2] Testing Square Channel 2 (440 Hz)... PASS
[TEST 3] Testing Triangle Channel (440 Hz)... PASS
[TEST 4] Testing Noise Channel.............. PASS
[TEST 5] Testing All Channels Simultaneously... PASS

-----------------------------------------------------
Test Results: 5/5 tests passed successfully.
-----------------------------------------------------

  ============================================================
     TinyQV RV2A03 NES APU LIVE SYNTHESIZER & SOUNDBOARD      
        Target: Sky25a Berzerk | QWERTZ / QWERTY Ready        
  ============================================================

  PIANO KEYS (Chromatic 1.5 Octaves):
    Black:       [W]   [E]         [T]   [Z]   [U]         [O]   [P]
                 C#    D#          F#    G#    A#          C#    D#
    White:    [A]   [S]   [D]   [F]   [G]   [H]   [J]   [K]
               C     D     E     F     G     A     B     C+
    * Tip: Both 'Z' (QWERTZ) and 'Y' (QWERTY) play G#!

  CHANNELS:   [1] Pulse 1 (Lead)    [2] Pulse 2 (Harmony)
              [3] Triangle (Bass)   [4] Noise (Percussion)

  CONTROLS:   [Q] Cycle Duty Cycle (12.5%, 25%, 50%, 75%)
              [<-] / [->] Octave Down / Up   (Range 2-6)  (or , / .)
              [v]  / [^]  Volume Down / Up   (Range 0-15) (or - / +)
              [SPACE] Mute Note              [M] Mute All

  SOUNDBOARD: [C] Coin!    [B] Jump!       [X] Explosion!  [L] Laser!
              [V] 1-Up!    [N] Snare Hit   [9/I] Barrel Drum (Boom!)
              [0/D] Cycle Barrel Distortion (0:Clean -> 1:Warm -> 2:Fuzz -> 3:Doom)

  JUKEBOX:    [5] Super Mario Bros. Theme
              [6] Berzerk APU Theme
              [7] Zelda Secret Fanfare

  SYSTEM:     [R] Dump APU Regs     [*] Run 5/5 Self-Test
              [?] Show this Guide
  ============================================================
```

---

## 7. Simulation & Waveform Analysis

### Full SoC cocotb Simulation (C Firmware Executing in Verilog)

The top-level test bench runs the actual compiled RISC-V firmware against the complete TinyQV SoC and RV2A03 peripheral in Icarus Verilog:

```bash
# Run simulation (fast execution, no waveform dump):
./run_rv2a03_simulation.sh

# Run simulation and generate VCD waveform (tb_qspi.vcd):
./build_and_sim.sh rv2a03_test 1

# Run simulation and generate FST waveform (tb_qspi.fst):
./build_and_sim.sh rv2a03_test fst

# Clean and simulate with VCD:
./build_and_sim.sh rv2a03_test 1 --clean
```

### Standalone RV2A03 Peripheral IP Simulation (`tinyqv-rv2a03`)

```bash
cd tinyqv-rv2a03/test
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
make -B
```

### Waveform Inspection & Audio Extraction

```bash
# Open waveforms with predefined signal layout:
gtkwave tb_qspi.vcd tb_apu.gtkw

# Inspect extracted audio signals from VCD:
python parse_vcd.py

# Audio files generated during testbench:
# - rv2a03_audio.wav          (Testsuite tones)
# - rv2a03_chiptune_full.wav  (Full chiptune playback)
```

> [!NOTE]
> Detailed hardware analysis of taped-out ASIC silicon quirks (such as the unmuted Triangle DC leak and length counter gating) is documented in [`RV2A03_APU_ERRATA.md`](file:///c:/Workspace/ASIC/tinyqv-tty25a-berzerk-rv2a03/RV2A03_APU_ERRATA.md).

---

## 8. TinyQV C SDK & RV2A03 Driver API

The C SDK is located at [`tinyQV-sdk-fjpolo`](file:///c:/Workspace/ASIC/tinyqv-tty25a-berzerk-rv2a03/tinyQV-sdk-fjpolo/).

### Building the SDK Libraries
```bash
cd tinyQV-sdk-fjpolo
make clean
make
```
Produces `start.o`, `tinyQV.a`, `tinyQV-sim.a`, and `tinyQV-berzerk.a`.

### Register Memory Map (Peripheral Slot 14 / Index 14)
Base Address: `0x8000380` (Direct APU register window mapped to NES `$4000`–`$401F`).

| Offset | Register Name | Description |
| :--- | :--- | :--- |
| `+0x00` | `RV2A03_REG_SQ1_VOL` | Square 1 Duty (`b7:6`), Length Counter Halt (`b5`), Constant Vol (`b4`), Volume (`b3:0`) |
| `+0x02` | `RV2A03_REG_SQ1_LO` | Square 1 Timer Low 8 bits |
| `+0x03` | `RV2A03_REG_SQ1_HI` | Square 1 Length Counter Load (`b7:3`), Timer High 3 bits (`b2:0`) |
| `+0x04` | `RV2A03_REG_SQ2_VOL` | Square 2 Duty, Halt, Volume |
| `+0x06` | `RV2A03_REG_SQ2_LO` | Square 2 Timer Low 8 bits |
| `+0x07` | `RV2A03_REG_SQ2_HI` | Square 2 Length Counter Load, Timer High 3 bits |
| `+0x08` | `RV2A03_REG_TRI_LINEAR` | Triangle Linear Counter Control / Halt (`b7`), Linear Counter Reload (`b6:0`) |
| `+0x0A` | `RV2A03_REG_TRI_LO` | Triangle Timer Low 8 bits |
| `+0x0B` | `RV2A03_REG_TRI_HI` | Triangle Length Counter Load (`b7:3`), Timer High 3 bits (`b2:0`) |
| `+0x0C` | `RV2A03_REG_NOISE_VOL` | Noise Halt (`b5`), Constant Vol (`b4`), Volume (`b3:0`) |
| `+0x0E` | `RV2A03_REG_NOISE_LO` | Noise Loop (`b7`), Period Index (`b3:0`) |
| `+0x0F` | `RV2A03_REG_NOISE_HI` | Noise Length Counter Load (`b7:3`) |
| `+0x15` | `RV2A03_REG_SND_CHN` | Channel Enable: Noise (`b3`), Triangle (`b2`), Square 2 (`b1`), Square 1 (`b0`) |
| `+0x24` | `RV2A03_REG_SAMPLE_HI` | 16-bit Mixed Audio Sample MSB |
| `+0x25` | `RV2A03_REG_SAMPLE_LO` | 16-bit Mixed Audio Sample LSB |

### C Driver API Cheat Sheet (`#include <peripherals/rv2a03.h>`)

```c
#include <tinyQV.h>
#include <peripherals/rv2a03.h>

// 1. Initialize peripheral and un-mute
rv2a03_init();

// 2. Enable channels
rv2a03_enable_channels(RV2A03_STATUS_SQ1_ENABLE | RV2A03_STATUS_TRI_ENABLE);

// 3. Play Square 1 Note (Duty 50%, Vol 12, timer calculated from MIDI note)
uint16_t sq_timer = rv2a03_midi_to_pulse_timer(RV2A03_NOTE_A4); // 440 Hz
rv2a03_set_pulse1(RV2A03_DUTY_50, 12, true, true, sq_timer, 0x1E);

// 4. Play Triangle Note (Bass note, timer shifted by 1 for triangle pitch)
uint16_t tri_timer = rv2a03_midi_to_pulse_timer(RV2A03_NOTE_A3) >> 1;
rv2a03_set_triangle(0x7F, true, tri_timer, 0x1E);

// 5. Play Noise
rv2a03_set_noise(false, 10, true, true, 0x05, 0x10);

// 6. Read 16-bit mixed hardware sample
uint16_t sample = rv2a03_read_sample();

// 7. Mute all channels
rv2a03_mute();
```

---

## 9. MicroPython Runtime

The `micropython` submodule contains the TinyQV port for interactive Python REPL over UART.

```bash
# 1. Build host cross-compiler:
cd micropython
make -C mpy-cross

# 2. Build TinyQV port firmware:
cd ports/tinyQV
make submodules
make TINYQV_SDK=../../../tinyQV-sdk-fjpolo

# 3. Flashing & Connecting:
# Upload build/firmware.bin using TinyQV Web Programmer (https://program.tinyqv.com)
# Connect serial monitor at 115200 baud to access the Python REPL ('>>>')
```

---

## 10. ASIC Tapeout Flow (OpenLane)

The full SoC Sky25a shuttle implementation is managed in [`ttsky25a-tinyQV-fjpolo-rv2a03`](file:///c:/Workspace/ASIC/tinyqv-tty25a-berzerk-rv2a03/ttsky25a-tinyQV-fjpolo-rv2a03/).

```bash
cd ttsky25a-tinyQV-fjpolo-rv2a03

# Run complete OpenLane synthesis and PnR flow:
./run_flow.sh

# Run SoC cocotb regression tests:
cd test
make -f test_basic.mk
make prog
```

---

## 11. Git Submodule Maintenance

This umbrella repository tracks specific commit pointers for each submodule.

### Updating Submodules to Latest Upstream
```bash
# Pull and merge latest commits on tracked branches:
git submodule update --remote --merge
```

### Making Modifications Inside a Submodule
```bash
# 1. Enter the submodule:
cd tinyQV-projects

# 2. Make sure you are on a branch (not detached HEAD):
git checkout dev/20290907

# 3. Commit and push your changes to the submodule repository:
git commit -am "My feature or fix"
git push origin dev/20290907

# 4. Return to root superproject and record the updated commit pointer:
cd ..
git add tinyQV-projects
git commit -m "chore: update tinyQV-projects submodule pointer"
git push origin master
```

---

## 12. Hardware Pinouts & Diagnostics

### Sipeed Tang Console 60K (GW5AT-60B)

```
+-------------------------------------------------------------+
|                                    [HDMI]                   |
|                                  +--------+                 |
|                                  | PMOD 1 | (Upper: LEDs)   |
|                                  +--------+                 |
|                                  | PMOD 0 | (Lower: Audio)  |
|                                  +--------+                 |
|                                                             |
|           Sipeed Tang Console 60K (GW5AT-60B)               |
+-------------------------------------------------------------+
```

- **Reset Button**: **S0** (`AA13`, active-low)
- **Clock Oscillator**: 50 MHz (`V22`) $\rightarrow$ PLLA synthesizes 27.000 MHz
- **Lower PMOD (PMOD0) — Audio PAM8403 Amplifier (`MUSE PMOD-AUDIO v1.2`)**:
  - `pmod_audio_out` (PWM DAC): **K21** (Pin 1)
  - `pmod_audio_sd` (Shutdown / Mute): **J21** (Pin 4)
  - Output connects to oval speaker (J2) and 3.5mm stereo headphone jack
- **Upper PMOD (PMOD1) — 8-LED Status Bar (`PMOD-LEDx8`)**:
  - `pmod_led[0]` (**W19**): Fast Heartbeat (~1.6 Hz)
  - `pmod_led[1]` (**W20**): Reset Active Indicator
  - `pmod_led[2]` (**F19**): UART TX Activity Blinker
  - `pmod_led[3]` (**F20**): Audio Playing Indicator
  - `pmod_led[4]` (**E22**): Amplifier Enabled Indicator
  - `pmod_led[5]` (**D22**): Medium Heartbeat (~0.8 Hz)
  - `pmod_led[6]` (**E21**): Test Suite Passed Indicator
  - `pmod_led[7]` (**D21**): Slow Heartbeat (~0.4 Hz)
- **UART Port**: BL616 USB-Serial on `COM19` (`tx`: **V14**, `rx`: **U14**) at 115200 8N1

### Sipeed Tang Nano 20K (GW2AR-18C)

- **Reset Button**: **S1** (Pin `88`, active-high reset with debouncer, near HDMI port)
- **Clock Oscillator**: 27.000 MHz onboard crystal (Pin `4`)
- **Audio Output**: Onboard **MAX98357A** I2S amplifier:
  - `BCLK`: Pin `54`
  - `LRCLK`: Pin `55`
  - `DIN`: Pin `56`
- **Diagnostic LEDs (Active-Low)**:
  - `LED[0]` (Pin `15`): Heartbeat 0 (~1.6 Hz)
  - `LED[1]` (Pin `16`): Reset state
  - `LED[2]` (Pin `17`): UART TX activity
  - `LED[3]` (Pin `18`): Audio active
  - `LED[4]` (Pin `19`): Audio amplifier enabled
  - `LED[5]` (Pin `20`): Heartbeat 1 (~0.8 Hz)
- **UART Port**: BL616 USB-Serial on `COM17` (`tx`: Pin `69` via `uo_out[0]`) at 115200 8N1

---

## 13. Interactive UART NES Synthesizer & Soundboard

The testsuite firmware boots directly into an interactive, zero-latency synthesizer and soundboard REPL accessible via ANSI terminal or PowerShell monitor (`.\serial_monitor.bat`).

### Keyboard Controls & Keymaps

#### Piano Keyboard (Chromatic 1.5 Octaves)
- **White Keys (Home Row)**: `A` (C), `S` (D), `D` (E), `F` (F), `G` (G), `H` (A, 440 Hz), `J` (B), `K` (C+ high octave)
- **Black Keys (Top Row)**: `W` (C#), `E` (D#), `T` (F#), `Z`/`Y` (G#, QWERTZ & QWERTY supported), `U` (A#), `O` (C#+), `P` (D#+)

#### Soundboard Retro SFX
- `B`: **Barrel Drum** (Deep 808-style pitch drop + noise strike + multi-mode hardware distortion)
- `0` / `D`: **Cycle Distortion**:
  - `Level 0`: Clean Acoustic (Smooth kick drum)
  - `Level 1`: Warm Saturation (Soft clipping & punch)
  - `Level 2`: Metallic Fuzz (High-frequency clipping)
  - `Level 3`: Industrial Doom (Hard clipping + wavefold decay)
- `9` / `I`: **Jump!** (Ascending square pitch sweep)
- `C`: **Coin!** (Mario B5 $\rightarrow$ E6 arpeggio)
- `X`: **Explosion!** (Low-frequency noise rumble)
- `L` / `8`: **Laser / Warp!** (Descending square chirp)
- `V`: **1-Up!** (Ascending major arpeggio)
- `N`: **Snare Hit** (Crisp noise crack)

#### Channel Selection & Controls
- `1` / `2` / `3` / `4`: Select active channel (Pulse 1 Lead, Pulse 2 Harmony, Triangle Bass, Noise Percussion)
- `<-` / `->` (Arrow Keys): Octave Down / Up (range: Octaves 2–6)
- `v` / `^` (Arrow Keys): Volume Down / Up (range: 0–15)
- `Q`: Cycle Pulse Duty Cycle (`12.5%`, `25%`, `50%`, `75%`)
- `5` / `6` / `7`: Jukebox (`5`: Mario Bros., `6`: Berzerk Theme, `7`: Zelda Fanfare)
- `SPACE` / `M`: Mute active note / all channels
- `R`: Dump APU hardware registers to terminal
- `*`: Run 5/5 hardware self-test

