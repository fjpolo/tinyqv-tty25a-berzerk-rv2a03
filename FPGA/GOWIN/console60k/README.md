# TinyQV RV2A03 NES APU for Sipeed Tang Console 60K

This folder contains the complete, self-contained FPGA project for running the **TinyQV RISC-V SoC** with the **RV2A03 NES APU Sound Peripheral** on the **Sipeed Tang Console 60K** (GW5AT-60B retro handheld/console board).

Audio is output directly through a **MUSE PMOD-AUDIO v1.2** loudspeaker module plugged into the lower PMOD socket, complemented by an 8-LED indicator array (**PMOD-LEDx8**) on the upper PMOD socket.

---

## 1. Features & Architecture

- **FPGA Chip**: Gowin Arora V **GW5AT-LV60PG484AC1/I0** (`GW5AT-60B`, PBG484A package, 59,904 LUT4 logic elements)
- **Clock Synthesis**: Arora V **PLLA** converts the onboard 50 MHz oscillator (`V22`) to a precise **27.000 MHz** system clock ($50 \times 27 / 50 = 27\text{ MHz}$, VCO 1350 MHz)
- **CPU**: TinyQV 32-bit RISC-V CPU core running synchronously at **27.000 MHz**
- **Sound Peripheral**: Integrated RV2A03 NES APU in Slot 14 (Pulse 1, Pulse 2, Triangle, Noise, and Hardware Mixer)
- **Audio Output 1 (PMOD Loudspeaker)**:
  - 1st-order **Delta-Sigma DAC** (16-bit PDM accumulator running at 27 MHz)
  - Directly drives the **MUSE PMOD-AUDIO v1.2** module featuring an onboard **PAM8403** 3W stereo Class-D audio power amplifier
  - Output feeds the attached oval speaker (header J2, Left channel) and the 3.5mm stereo headphone jack (Left + Right channels)
- **Audio Output 2 (Onboard Console Audio)**:
  - Philips **I2S interface** driving the console's onboard audio DAC and headphone amplifier
- **Visual Feedback**:
  - **Upper PMOD**: 8-LED status bar (**PMOD-LEDx8**) displaying heartbeats, UART TX activity, reset state, audio playing, and PLL lock
  - **Hardware Status Indicators**: Onboard DONE (`G11`) and READY (`U12`) LEDs driven automatically by FPGA configuration circuitry
- **Serial Interface**: Hardware USB-UART connected to the onboard BL616 microcontroller at **115,200 baud** (8N1)
- **Autonomous Boot**: Inferred Gowin Block RAM (BSRAM) pre-loaded with firmware (`rv2a03_test.hex`). The SoC boots and executes the full self-test suite and chiptune demo automatically upon FPGA configuration.

---

## 2. PMOD Module Configuration & Connections

The Tang Console 60K has two standard 12-pin dual-row PMOD sockets.

```
+-------------------------------------------------------------+
|                                    [HDMI]                   |
|                                  +--------+                 |
|                                  | PMOD 1 | (Upper)         |
|                                  +--------+                 |
|                                  | PMOD 0 | (Lower)         |
|                                  +--------+                 |
|                                                             |
|           Sipeed Tang Console 60K (GW5AT-60B)               |
+-------------------------------------------------------------+
```

### PMOD 1 (Upper Socket) — `PMOD-LEDx8`

| PMOD Pin | Signal Name | FPGA Pin | IO Standard | Description |
|:---|:---|:---|:---|:---|
| Pin 1 | `pmod_led[0]` | **W19** | LVCMOS33 | Heartbeat 0 (Fast blink, ~1.6 Hz) |
| Pin 2 | `pmod_led[1]` | **W20** | LVCMOS33 | Reset active indicator (high during reset) |
| Pin 3 | `pmod_led[2]` | **F19** | LVCMOS33 | UART TX activity blinker |
| Pin 4 | `pmod_led[3]` | **F20** | LVCMOS33 | Audio playing indicator (active sound output) |
| Pin 7 | `pmod_led[4]` | **E22** | LVCMOS33 | Audio amplifier enabled / sound active |
| Pin 8 | `pmod_led[5]` | **D22** | LVCMOS33 | Heartbeat 1 (Medium blink, ~0.8 Hz) |
| Pin 9 | `pmod_led[6]` | **E21** | LVCMOS33 | Test passed indicator |
| Pin 10| `pmod_led[7]` | **D21** | LVCMOS33 | Heartbeat 2 (Slow blink, ~0.4 Hz) |
| Pin 5, 11 | `GND` | GND | POWER | Ground |
| Pin 6, 12 | `3V3` | 3.3V | POWER | 3.3V Power |

*(Note: PMOD-LEDx8 LEDs are active-high: `1` = ON, `0` = OFF).*

### PMOD 0 (Lower Socket) — `MUSE PMOD-AUDIO v1.2`

| PMOD Pin | Signal Name | FPGA Pin | IO Standard | Description |
|:---|:---|:---|:---|:---|
| Pin 1 | `pmod_audio_l` | **V19** | LVCMOS33 | Left Audio Channel PDM (Drives J2 Loudspeaker + 3.5mm Jack) |
| Pin 2 | `pmod_audio_r` | **V18** | LVCMOS33 | Right Audio Channel PDM (Drives 3.5mm Jack Right) |
| Pin 3 | `pmod_io[2]` | **G22** | LVCMOS33 | GPIO (Grounded / Reserved) |
| Pin 4 | `pmod_io[3]` | **G21** | LVCMOS33 | GPIO (Grounded / Reserved) |
| Pin 7 | `pmod_io[4]` | **E18** | LVCMOS33 | GPIO (Grounded / Reserved) |
| Pin 8 | `pmod_io[5]` | **F18** | LVCMOS33 | GPIO (Grounded / Reserved) |
| Pin 9 | `pmod_io[6]` | **C22** | LVCMOS33 | GPIO (Grounded / Reserved) |
| Pin 10| `pmod_io[7]` | **B22** | LVCMOS33 | GPIO (Grounded / Reserved) |
| Pin 5, 11 | `GND` | GND | POWER | Ground reference |
| Pin 6, 12 | `3V3` | 3.3V | POWER | 3.3V Power rail (Powers PAM8403 chip) |

---

## 3. Full Pin Mapping Table (`console60k.cst`)

| Signal Name | FPGA Pin | Bank | Direction | IO Standard | Description |
|:---|:---|:---|:---|:---|:---|
| `sys_clk` | **V22** | Bank 1 | Input | LVCMOS33 | 50.000 MHz onboard oscillator |
| `btn_rst_n` | **AA13** | Bank 4 | Input | LVCMOS15 | S0 Button (Active-Low Hardware Reset) |
| `key_mode_n`| **AB13** | Bank 4 | Input | LVCMOS15 | S1 / MODE Button (Active-Low User Key) |
| `uart_tx` | **U15** | Bank 1 | Output | LVCMOS33 | FPGA UART TX $\rightarrow$ BL616 USB-Serial RX |
| `uart_rx` | **V14** | Bank 1 | Input | LVCMOS33 | FPGA UART RX $\leftarrow$ BL616 USB-Serial TX |
| `pmod_audio_l`| **V19** | Bank 1 | Output | LVCMOS33 | PMOD0 Pin 1: Delta-Sigma Audio (Speaker J2) |
| `pmod_audio_r`| **V18** | Bank 1 | Output | LVCMOS33 | PMOD0 Pin 2: Delta-Sigma Audio (Headphones R) |
| `hp_bck` | **Y17** | Bank 1 | Output | LVCMOS33 | Onboard I2S Bit Clock |
| `hp_ws` | **AB17** | Bank 1 | Output | LVCMOS33 | Onboard I2S Word Select / LRCLK |
| `hp_din` | **AA16** | Bank 1 | Output | LVCMOS33 | Onboard I2S Audio Serial Data |
| `pa_en` | **Y14** | Bank 1 | Output | LVCMOS15 | Onboard Audio Power Amp Enable (Active-High) |
| *(DONE LED)* | **G11** | Bank 0 | Output | Hardware | Dedicated FPGA DONE configuration status LED |
| *(READY LED)*| **U12** | Bank 1 | Output | Hardware | Dedicated FPGA READY configuration status LED |

---

## 4. Directory Structure

```
FPGA/GOWIN/console60k/
├── console60k.gprj           # Gowin EDA project file (target: GW5AT-60B)
├── console60k.cst            # Physical pin constraints file (PBG484A)
├── build.ps1                 # PowerShell build & flash automation script
├── build.bat                 # Windows CMD wrapper
├── build.sh                  # Bash build script (Linux / MSYS2 / Git Bash)
├── build.tcl                 # Gowin EDA Tcl batch script
├── README.md                 # This documentation
└── src/
    ├── tangconsole60k_top.v  # Top-level module (clock PLL, DACs, PMOD, UART)
    ├── gowin_pll_50_to_27.v  # Arora V PLLA (50 MHz in -> 27 MHz out)
    ├── delta_sigma_dac.v     # 1st-order Delta-Sigma 16-bit PDM DAC (for PAM8403)
    ├── i2s_tx.v              # Philips I2S transmitter (for onboard audio DAC)
    ├── tinyqv_top.v          # TinyQV SoC wrapper
    ├── peripherals.v         # Peripheral bus arbiter
    ├── peripheral.v          # RV2A03 APU peripheral interface (Slot 14)
    ├── apu.v                 # RV2A03 APU core (Pulse1, Pulse2, Tri, Noi, Mixer)
    ├── sim_qspi.v            # QSPI memory controller
    ├── bram.v                # Block RAM initialized with firmware
    ├── rv2a03_test.hex       # Pre-compiled firmware image (128KB hex)
    ├── peri_uart.v           # Peripheral UART wrapper
    ├── tqvp_uart_tx.v        # Peripheral UART TX module
    ├── tqvp_uart_rx.v        # Peripheral UART RX module
    ├── peri_byte_empty.v     # Stub for unused byte peripherals
    ├── peri_full_empty.v     # Stub for unused full peripherals
    ├── peri_byte_example.v   # Example byte peripheral
    ├── peri_full_example.v   # Example full peripheral
    └── tinyqv/               # TinyQV RISC-V CPU core sources
        ├── tinyqv.v
        ├── cpu.v
        ├── core.v
        ├── decode.v
        ├── alu.v
        ├── register.v
        ├── latch_reg.v
        ├── mem_ctrl.v
        ├── qspi_ctrl.v
        ├── qspi_flash.v
        ├── counter.v
        ├── time.v
        ├── uart_tx.v
        └── uart_rx.v
```

---

## 5. How to Build & Flash

### Automated Build (PowerShell)

From `FPGA/GOWIN/console60k/`, open PowerShell and run:

```powershell
# 1. Full compilation (Synthesis + Place & Route + Bitstream generation)
.\build.ps1

# 2. Flash bitstream directly into FPGA SRAM (instantaneous testing)
.\build.ps1 -Flash sram

# 3. Flash bitstream into persistent onboard SPI Flash
.\build.ps1 -Flash flash

# 4. Clean build directory and rebuild
.\build.ps1 -Clean

# 5. Scan connected Gowin USB cables and Arora V FPGA
.\build.ps1 -Scan
```

### Windows Command Prompt (`build.bat`)

```cmd
build.bat
build.bat -Flash sram
```

### Bash (`build.sh`)

```bash
chmod +x build.sh
./build.sh
```

### Gowin EDA GUI

1. Launch **Gowin EDA (V1.9.10 or later)**.
2. Open `FPGA/GOWIN/console60k/console60k.gprj`.
3. In the Design tree, right-click `tangconsole60k_top` and verify it is set as Top Module.
4. In the Process window, double-click **Place & Route** (or click **Run All**).
5. Open **Programmer**, connect the Tang Console USB cable, and program `impl/pnr/console60k.fs`.

---

## 6. Verification & Serial Monitor

Connect a serial terminal (PuTTY, Tera Term, minicom, or Arduino Serial Monitor) to the Tang Console's USB-Serial COM port:
- **Baud rate**: `115200`
- **Data bits**: `8`
- **Parity**: `None`
- **Stop bits**: `1`
- **Flow control**: `None`

Upon FPGA configuration or pressing the **S0** reset button (`AA13`), the terminal will output the test suite log followed by chiptune playback:

```
========================================
TinyQV RV2A03 APU Test
========================================

--- Test 1: Register Read/Write ---
Wrote 0x0F to 0x3015, read back: 0x00 (write-only) -> PASS
Wrote pulse1 ctrl, freq, len: -> PASS

--- Test 2: Status Register ---
Status read: 0x00 -> PASS

--- Test 3: Pulse 1 Audio ---
Playing Pulse 1 (A4, 440Hz)...
Playing Pulse 1 (C5, 523Hz)...
Playing Pulse 1 (E5, 659Hz)...

--- Test 4: All Channels ---
Playing Triangle (220Hz)...
Playing Noise (periodic)...
Playing Noise (random)...
Playing Pulse 2 (330Hz)...

--- Test 5: Sound Effects ---
Playing coin sound...
Playing laser sound...
Playing explosion sound...

========================================
All tests completed! (5/5 passed)
========================================
Starting chiptune playback...
```

Simultaneously:
- The **MUSE PMOD-AUDIO v1.2** loudspeaker will play each tone, sound effect, and chiptune melody clearly.
- The volume can be adjusted smoothly using the potentiometer wheel on the PMOD module.
- The **PMOD-LEDx8** will display flashing activity on LED 0 (heartbeat), LED 2 (UART TX), LED 3 (audio output), and LED 6 (test passed).
