# TinyQV RV2A03 NES APU for Sipeed Tang Nano 20K

This folder contains the complete, self-contained FPGA project for running the **TinyQV RISC-V SoC** with the **RV2A03 NES APU Sound Peripheral** on the **Sipeed Tang Nano 20K** FPGA board.

---

## 1. Features & Architecture

- **FPGA Chip**: Gowin Arora **GW2AR-LV18QN88C8/I7** (`GW2AR-18C`)
- **CPU**: TinyQV 32-bit RISC-V CPU core running at **27 MHz** (fully synchronous from onboard crystal)
- **Sound Peripheral**: Integrated RV2A03 NES APU in Slot 14 (Pulse 1, Pulse 2, Triangle, Noise, Hardware Mixer)
- **Audio Output**: Direct digital **I2S interface** driving the onboard **MAX98357A** Class-D speaker amplifier at 46.875 kHz 16-bit PCM
- **Serial Interface**: USB-UART connection through the onboard BL616 microcontroller at **115,200 baud** (8N1)
- **Autonomous Boot**: Inferred Gowin Block RAM (BSRAM) pre-loaded with firmware (`rv2a03_test.hex`). The SoC boots and executes tests automatically upon FPGA power-up/configuration.
- **RTL Errata Fixes**: Includes the digital hardware fixes for Triangle DC leakage, Noise delayed muting, and Square gating.

---

## 2. Pin Mapping Table (`nano20k.cst`)

| Signal Name | FPGA Pin | Direction | Description |
|:---|:---|:---|:---|
| `sys_clk` | **Pin 4** | Input | 27 MHz onboard crystal oscillator |
| `rst_n` | **Pin 88** | Input | S1 User Button (Active-Low Reset, internal pull-up) |
| `key2` | **Pin 87** | Input | S2 User Button (Active-Low, internal pull-up) |
| `uart_tx` | **Pin 69** | Output | FPGA UART TX $\rightarrow$ BL616 USB-Serial RX |
| `uart_rx` | **Pin 70** | Input | FPGA UART RX $\leftarrow$ BL616 USB-Serial TX |
| `pa_en` | **Pin 51** | Output | MAX98357A Amplifier Enable (High = Enabled) |
| `i2s_bclk` | **Pin 56** | Output | I2S Bit Clock (~1.5 MHz) |
| `i2s_lrclk`| **Pin 55** | Output | I2S Word Select / LRCLK (~46.875 kHz) |
| `i2s_din` | **Pin 54** | Output | I2S Serial Audio Data |
| `led[0]` | **Pin 15** | Output | LED 0: Heartbeat blinker (~1.6 Hz) |
| `led[1]` | **Pin 16** | Output | LED 1: Reset active indicator |
| `led[2]` | **Pin 17** | Output | LED 2: UART TX activity |
| `led[3]` | **Pin 18** | Output | LED 3: Audio playing indicator |
| `led[4]` | **Pin 19** | Output | LED 4: Audio amplifier enable status |
| `led[5]` | **Pin 20** | Output | LED 5: Slower heartbeat blinker (~0.8 Hz) |

*(Note: Tang Nano 20K LEDs are active-low: `0` = ON, `1` = OFF)*

---

## 3. Directory Structure

```
FPGA/GOWIN/nano20k/
├── nano20k.gprj           # Gowin EDA project file
├── nano20k.cst            # Physical pin constraints file
├── README.md              # This guide
└── src/
    ├── tangnano20k_top.v  # Top-level module (clock, I2S bridge, LEDs)
    ├── i2s_tx.v           # Philips I2S transmitter for MAX98357A
    ├── tinyqv_top.v       # TinyQV SoC wrapper
    ├── peripherals.v      # Peripheral bus router
    ├── peripheral.v       # RV2A03 peripheral interface (Slot 14)
    ├── apu.v              # RV2A03 APU core (Pulse1, Pulse2, Tri, Noi, Mixer)
    ├── sim_qspi.v         # QSPI memory controller
    ├── bram.v             # Block RAM initialized with firmware
    ├── rv2a03_test.hex    # Pre-compiled firmware image (128KB hex)
    ├── peri_uart.v        # Peripheral UART wrapper
    ├── tqvp_uart_tx.v     # Peripheral UART TX module
    ├── tqvp_uart_rx.v     # Peripheral UART RX module
    ├── peri_byte_empty.v  # Stub for unused byte peripherals
    ├── peri_full_empty.v  # Stub for unused full peripherals
    ├── peri_byte_example.v# Example byte peripheral
    ├── peri_full_example.v# Example full peripheral
    └── tinyqv/            # TinyQV RISC-V CPU core sources
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

## 4. How to Build

### Option A: Automated Command Line (Recommended)

From the workspace root or from this directory, run the build script:

```powershell
# From workspace root (Windows Command Prompt or PowerShell):
.\build_gowin.bat

# Or directly from PowerShell:
.\build_gowin.bat -Clean              # Clean and rebuild from scratch
.\build_gowin.bat -Target syn         # Logic synthesis only
.\build_gowin.bat -Scan               # Detect connected USB-JTAG cables and FPGA
.\build_gowin.bat -Flash sram         # Build and load directly to Tang Nano 20K SRAM
.\build_gowin.bat -Flash flash        # Build and write to persistent onboard embFlash
```

From Linux / Git Bash / WSL:
```bash
./build_gowin.sh                      # Full synthesis, PnR, and bitstream generation
./build_gowin.sh syn                  # Synthesis only
./build_gowin.sh clean                # Clean build directory
```

The script automatically locates your Gowin installation (e.g., `C:\Gowin\Gowin_V1.9.12_x64`), configures all options, runs `gw_sh`, and outputs the bitstream to `impl/pnr/nano20k.fs`.

---

### Option B: Gowin EDA GUI

#### Step 1: Open the Project
1. Launch **Gowin EDA** (v1.9.8, v1.9.9, v1.9.12 or higher).
2. Go to **File $\rightarrow$ Open Project...**.
3. Select `FPGA/GOWIN/nano20k/nano20k.gprj`.
4. Verify that the target device is set to:
   - **Series**: `GW2AR`
   - **Device**: `GW2AR-18C`
   - **Package**: `QN88`
   - **Part Number**: `GW2AR-LV18QN88C8/I7`

#### Step 2: Synthesize and Place & Route
1. In the **Process** pane on the left, double-click **Place & Route** (or right-click **Place & Route** $\rightarrow$ **Rerun All**).
2. Gowin EDA will synthesize the design, place and route it, and generate the bitstream file:
   `impl/pnr/nano20k.fs`.

---

## 5. Programming the Tang Nano 20K

1. Connect the Tang Nano 20K to your computer using a USB Type-C cable.
2. Open **Programmer** inside Gowin EDA (or launch `Programmer.exe`).
3. Click **Scan Device**. You should see `GW2AR-18C` detected via the onboard BL616 USB-JTAG bridge.
4. Set the programming operation:
   - **For Volatile RAM Test (fastest)**:
     - Access Mode: `SRAM Mode`
     - Operation: `SRAM Program`
     - File: `impl/pnr/nano20k.fs`
     - Click **Program/Configure**.
   - **For Permanent Non-Volatile Boot (survives power cycle)**:
     - Access Mode: `Embedded Flash Mode`
     - Operation: `embFlash Erase, Program`
     - File: `impl/pnr/nano20k.fs`
     - Click **Program/Configure**.

---

## 6. Verifying Operation

### A. Onboard LEDs
Once programmed, you should observe:
- **LED 0 & LED 5**: Blinking in a heartbeat pattern (~1.6 Hz and ~0.8 Hz).
- **LED 2**: Blinking during UART transmissions.
- **LED 3**: Illuminating whenever the APU is playing audio.
- **LED 4**: Continuously ON (verifying `pa_en` is active high).

### B. Serial Monitor (UART Output)
1. Open your preferred serial terminal (PuTTY, TeraTerm, VS Code Serial Monitor, or Arduino IDE Serial Monitor).
2. Select the COM port assigned to the Tang Nano 20K (BL616 USB Serial Port).
3. Set the baud rate to **`115200`**, **8 Data Bits**, **No Parity**, **1 Stop Bit** (`115200 8N1`).
4. Press the **S1** button on the board to reset the CPU. You will see:
   ```text
   === RV2A03 FIRMWARE SIMULATION ===
   [TEST 1] Testing Square Channel 1 (440 Hz)... PASS (20/20 samples, peak: 18)
   [TEST 2] Testing Square Channel 2 (440 Hz)... PASS (20/20 samples, peak: 18)
   [TEST 3] Testing Triangle Channel (440 Hz)... PASS (20/20 samples, peak: 15)
   [TEST 4] Testing Noise Channel.............. PASS (20/20 samples, peak: 12)
   [TEST 5] Testing All Channels Simultaneously. PASS (20/20 samples, combined peak: 24)

   -----------------------------------------------------
   Test Results: 5/5 tests passed successfully.
   -----------------------------------------------------

   Playing NES Chiptune Demo...
   ```

### C. Audio Output
- Connect a small 4–8 $\Omega$ speaker or 3.5mm jack to the MAX98357A speaker pads on the Tang Nano 20K board.
- You will hear:
  1. Square Channel 1 tone (440 Hz).
  2. Square Channel 2 tone (440 Hz).
  3. Triangle Channel pure bass tone.
  4. Noise Channel burst.
  5. Multi-channel combined chord.
  6. The NES chiptune musical melody demo!
