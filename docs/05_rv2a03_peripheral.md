# 05. RV2A03 Peripheral & Differences vs Real APU

## 1. Overview & Silicon Instance

The **RV2A03** is an open-source hardware implementation of the Nintendo NES Audio Processing Unit (APU), tailored by **@fjpolo** for the **TinyQV RISC-V SoC** on the **Tiny Tapeout Sky25a** shuttle (project instance `ttsky25a-tinyQV-fjpolo-rv2a03`, named **Berzerk**).

It occupies **Slot 14** (`0x8000380` - `0x80003BF`) on the TinyQV on-chip peripheral bus and provides authentic 8-bit chiptune synthesis with direct 16-bit digital PCM sample readout.

### Silicon Layout & 3D Visualization

* **2D ASIC GDSII Layout**:

  ![RV2A03 ASIC 2D GDS Layout](https://camo.githubusercontent.com/cac6e18a82b61a7fb0bae33d039d30e6a5a63dab5986ba3d7df82a8f59b8f89e/68747470733a2f2f666a706f6c6f2e6769746875622e696f2f74696e7971762d7276326130332f6764735f72656e6465722e706e67)

* **Interactive 3D GDS Viewer**:
  Explore the fabricated Skywater 130nm standard cells, metal layers, and routing in your browser:
  - 🌐 **[Open Interactive 3D GDS Viewer](https://fjpolo.github.io/tinyqv-rv2a03/)** *(powered by Tiny Tapeout WebGL GDS Viewer)*
  - 🔗 Direct WebGL Model URL: [https://gds-viewer.tinytapeout.com/?process=SKY130&model=https%3A%2F%2Ffjpolo.github.io%2Ftinyqv-rv2a03%2Ftinytapeout.gds](https://gds-viewer.tinytapeout.com/?process=SKY130&model=https%3A%2F%2Ffjpolo.github.io%2Ftinyqv-rv2a03%2Ftinytapeout.gds)

```
                     +---------------------------------------+
                     |         RV2A03 Peripheral             |
                     +---------------------------------------+
                     |  TinyQV Bus: 0x8000380 - 0x80003BF    |
                     |  Base Clock: 64 MHz (ASIC) / 27 MHz   |
                     |  Divider   : /12 (CPU_DIV_N = 11)     |
                     +---------------------------------------+
                                |
             +------------------+------------------+
             |                  |                  |
     +---------------+  +---------------+  +---------------+
     | Square 1 & 2  |  | Triangle Chan |  |  Noise Chan   |
     | (Duty/Sweep)  |  | (32-Step)     |  |  (15-bit LFSR)|
     +---------------+  +---------------+  +---------------+
             |                  |                  |
             +------------------+------------------+
                                |
                      +-------------------+
                      |   Digital Mixer   |
                      +-------------------+
                                |
             +------------------+------------------+
             |                                     |
     +---------------+                     +---------------+
     | Reg 0x24/0x25 |                     | uo_out[1]: IRQ|
     | 16-bit PCM Out|                     | uo_out[2]: CE |
     +---------------+                     +---------------+
```

---

## 2. Hardware Architecture & Module Hierarchy

* **`tqvp_fjpolo_rv2a03`**: Top-level bus adapter interfacing with the TinyQV 32-bit peripheral bus.
* **`APU`**: Core audio engine adapted from Kitrinx's open-source NES APU.
* **`SquareChan`**: Dual pulse wave generators with independent 8-step duty sequencers, sweep units, envelope generators, and length counters.
* **`TriangleChan`**: 32-step stepped triangle generator with high-resolution linear counter and length counter.
* **`NoiseChan`**: 15-bit Galois LFSR pseudo-random noise generator with mode select (32,767-step white noise vs 93-step metallic buzz).
* **`APUMixer`**: High-speed digital linear summing network yielding 16-bit PCM output.
* **`FrameCtr`**: 4-step/5-step frame sequencer generating quarter-frame (240 Hz) and half-frame (120 Hz) clocks.

---

## 3. Register Memory Map

The peripheral occupies **64 bytes** at base address `0x8000380`.

### 3.1 Direct APU Registers (`0x00` - `0x17`)
These registers mirror the original Nintendo NES memory map at `$4000`–`$4017`:

| Offset | NES Equiv. | Name | Description |
| :---: | :---: | :--- | :--- |
| `0x00` | `$4000` | `SQ1_VOL` | Pulse 1: Duty cycle (`[7:6]`), Loop/Halt (`[5]`), Const Vol (`[4]`), Volume/Envelope (`[3:0]`). |
| `0x01` | `$4001` | `SQ1_SWEEP` | Pulse 1 Sweep: Enable (`[7]`), Period (`[6:4]`), Negate (`[3]`), Shift (`[2:0]`). |
| `0x02` | `$4002` | `SQ1_LO` | Pulse 1 Frequency: 8-bit timer low period. |
| `0x03` | `$4003` | `SQ1_HI` | Pulse 1 Length & Pitch: Length index (`[7:3]`), timer high 3 bits (`[2:0]`). |
| `0x04` | `$4004` | `SQ2_VOL` | Pulse 2: Duty cycle (`[7:6]`), Loop/Halt (`[5]`), Const Vol (`[4]`), Volume/Envelope (`[3:0]`). |
| `0x05` | `$4005` | `SQ2_SWEEP` | Pulse 2 Sweep: Enable (`[7]`), Period (`[6:4]`), Negate (`[3]`), Shift (`[2:0]`). |
| `0x06` | `$4006` | `SQ2_LO` | Pulse 2 Frequency: 8-bit timer low period. |
| `0x07` | `$4007` | `SQ2_HI` | Pulse 2 Length & Pitch: Length index (`[7:3]`), timer high 3 bits (`[2:0]`). |
| `0x08` | `$4008` | `TRI_LINEAR`| Triangle: Length counter halt / linear counter reload value (`[6:0]`). |
| `0x0A` | `$400A` | `TRI_LO` | Triangle Frequency: 8-bit timer low period. |
| `0x0B` | `$400B` | `TRI_HI` | Triangle Length & Pitch: Length index (`[7:3]`), timer high 3 bits (`[2:0]`). |
| `0x0C` | `$400C` | `NOISE_VOL` | Noise: Loop/Halt (`[5]`), Const Vol (`[4]`), Volume/Envelope (`[3:0]`). |
| `0x0E` | `$400E` | `NOISE_LO` | Noise Mode & Period: Mode (`[7]`: 0=32767 white, 1=93 metallic), Period index (`[3:0]`). |
| `0x0F` | `$400F` | `NOISE_HI` | Noise Length: Length counter load index (`[7:3]`). |
| `0x15` | `$4015` | `STATUS` | Channel Enable (W) / Status (R): `[3]`=Noise, `[2]`=Triangle, `[1]`=Square 2, `[0]`=Square 1. |
| `0x17` | `$4017` | `FRAME_CNT` | Frame Counter: Mode (`[7]`: 0=4-step, 1=5-step), Interrupt Inhibit (`[6]`). |

### 3.2 Extended TinyQV Control & Sample Registers (`0x20` - `0x25`)

| Offset | Name | Type | Description |
| :---: | :--- | :---: | :--- |
| **`0x20`** | `CONFIG0` | R/W | **Configuration 0**:<br/>• Bit 0: `CE` (Clock Enable — must be set to 1 to activate APU)<br/>• Bit 1: `US` (Allow Ultrasound / High-frequency override)<br/>• Bit 2: `isMMC5` (Enable MMC5 expansion square channels) |
| **`0x22`** | `STATUS0` | R | **Status 0**:<br/>• Bit 0: Data Output Ready<br/>• Bit 1: `IRQ` active flag |
| **`0x23`** | `DATA_IN` | R/W | **Command Data Input**: Auxiliary byte write port for external sequencer commands. |
| **`0x24`** | `OUTPUT_MSB`| R | **Audio Sample MSB**: Upper 8 bits `[15:8]` of instantaneous mixed 16-bit PCM audio sample. |
| **`0x25`** | `OUTPUT_LSB`| R | **Audio Sample LSB**: Lower 8 bits `[7:0]` of instantaneous mixed 16-bit PCM audio sample. |

---

## 4. Hardware I/O Pin Mappings

When Slot 14 is routed to the output pins via `FUNC_SEL`, `uo_out[7:0]` delivers:

* **`uo_out[0]`**: Connected to `ui_in[0]` (used for UART TX passthrough).
* **`uo_out[1]`**: **`apu_IRQ`** — Direct active-high interrupt output from the APU Frame Counter.
* **`uo_out[2]`**: **`apu_o_ce`** — Audio sample clock enable strobe (~1.78 MHz on ASIC / ~2.25 MHz on FPGA).
* **`uo_out[7:3]`**: Passthrough of input pins `ui_in[7:3]`.

---

## 5. Differences & Limitations Compared to Original Ricoh 2A03

The table below contrasts the RV2A03 silicon implementation against the original Nintendo Ricoh 2A03:

| Feature / Property | Original Nintendo Ricoh 2A03 | TinyQV RV2A03 Silicon (Slot 14) | Impact / Rationale |
| :--- | :--- | :--- | :--- |
| **DMC (DPCM) Channel** | **Present** (Plays 1-bit samples via DMA from 6502 memory) | **Omitted** (`DmcIrq` tied to 0; no DAC/DMA) | **Area Constraints**: Storing sample DMA logic would exceed Tiny Tapeout tile limits. No voice clips or DPCM drums. |
| **Mixing Technology** | **Non-Linear Resistor Ladder** (Analog current summation) | **Digital Linear Summing** (16-bit digital adder) | Digital mixer is perfectly clean and linear; does not exhibit analog soft-compression saturation. |
| **PCM Output Access** | **None** (Only analog output pins available) | **Direct 16-bit Digital Readout** (`0x24` / `0x25`) | Software on RISC-V can read instantaneous 16-bit PCM samples to stream over UART, record to SD, or DSP filter. |
| **Clock Frequency** | Fixed NTSC **1.789773 MHz** | Divided from SoC clock: **5.333 MHz** (ASIC) / **2.25 MHz** (FPGA) | Firmware must adjust timer frequency calculation (`APU_PULSE_CLOCK_BASE`) to achieve pitch-perfect tuning. |
| **MMC5 Expansion Mode** | Requires external MMC5 cartridge chip | **Built-in** (Toggle via `CONFIG0` bit 2) | Provides optional MMC5-compatible duty modes on square channels. |
| **Ultrasound Frequencies**| Hard-clipped by analog filters | **Software Controllable** (Toggle via `CONFIG0` bit 1) | Allows generating frequencies above 20 kHz for ultrasonic experiments. |

---

## 6. Silicon Errata & Firmware Workarounds (Taped-Out Silicon)

Because the physical ASIC silicon for the Sky25a shuttle is frozen, several hardware quirks exist and are mitigated in software:

### 1. Triangle Channel DC Leak (Errata #1)
* **Hardware Quirk**: In `TriangleChan`, the output multiplexer is:
  ```verilog
  assign Sample = (applied_period > 1 || allow_us) ? (SeqPos[3:0] ^ {4{~SeqPos[4]}}) : sample_latch;
  ```
  It lacks a gating check on `Enabled` or linear counter zero. When muted via register `$4015`, the sequencer stops advancing, but **continues to output whatever DC level it stopped on (0–15)**.
* **Firmware Workaround**: Always call `rv2a03_mute()`, which clears the triangle linear counter (`0x08 = 0x00`) before disabling channels.

### 2. Noise Channel Delayed Muting (Errata #2)
* **Hardware Quirk**: `NoiseChan` checks length counter `~lc` rather than immediate channel `~Enabled`. When muted with looping envelope active, the noise channel can continue outputting volume for up to 79 ms until the frame counter ticks.
* **Firmware Workaround**: Firmware explicitly writes volume 0 (`0x30`) to register `$400C` whenever muting the noise channel.

### 3. Register `$4015` Write Sampling Window
* **Hardware Quirk**: The write strobe for channel enable register `$4015` is sampled on `apu_ce_sync`, which is only active during 8 out of every 12 system clock cycles.
* **Firmware Workaround**: The SDK driver (`rv2a03_enable_channels()`) writes to `$4015` across a 16-cycle burst to guarantee the write lands squarely in the active sampling window.
