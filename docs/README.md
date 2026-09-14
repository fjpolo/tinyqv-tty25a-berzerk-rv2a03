# TinyQV & RV2A03 Sound Peripheral Documentation

Welcome to the technical architecture and reference documentation for the **TinyQV RISC-V SoC** and the **RV2A03 NES APU Sound Peripheral** on the **Tiny Tapeout Sky25a** shuttle and Gowin FPGAs.

---

## Documentation Index

This directory provides deep-dive architectural specifications, bus protocol references, hardware registers, and comparative analyses:

| Chapter | Document | Topics Covered |
| :--- | :--- | :--- |
| **01** | [**TinyQV SoC Architecture**](01_tinyqv_architecture.md) | RISC-V `rv32ec_zcb_zicond` core, 28-bit/24-bit addressing, hardcoded pointers (`gp`, `tp`), XIP QSPI Flash cache, PSRAM memory layout, system registers (`DEBUG`, `TIME`, `GPIO`, `UART`). |
| **02** | [**Peripherals & Slot Allocation**](02_peripherals_and_slots.md) | Peripheral slot organization (Full, Simple, Extended), GPIO multiplexing (`FUNC_SEL`), pinout configurations (`ui_in`, `uo_out`), `AUDIO_FUNC_SEL`, and system integration. |
| **03** | [**Peripheral Bus Protocol & Timing**](03_peripheral_bus_protocol.md) | Synchronous bus interface, address decoding (`0x8000000`), byte/halfword/word enables (`data_write_n`, `data_read_n`), `data_ready` handshake, bus cycle waveforms, and wait-state handling. |
| **04** | [**Nintendo NES APU Architecture**](04_nes_apu_architecture.md) | Original Ricoh 2A03/2A07 sound chip, Pulse 1 & 2 channels, Triangle channel, LFSR Noise generator, DMC (DPCM) channel, Frame Counter sequencer (4-step/5-step), and non-linear analog mixer. |
| **05** | [**RV2A03 Peripheral & Differences vs Real APU**](05_rv2a03_peripheral.md) | Silicon implementation (Slot 14), register map (`0x00`-`0x25`), digital mixer, direct 16-bit PCM readout, silicon errata (DC leak & gating quirks), and comprehensive differences/limitations vs the original Ricoh 2A03. |

---

## System Architecture High-Level Block Diagram

```mermaid
graph TD
    subgraph "External Memory (QSPI)"
        Flash["QSPI Flash (XIP Code: 0x0000000)"]
        PSRAM["QSPI PSRAM (RAM A/B: 0x1000000)"]
    end

    subgraph "TinyQV SoC (Skywater 130nm / FPGA)"
        Core["TinyQV Core (RV32EC + Zcb + Zicond)"]
        Cache["QSPI XIP Controller & Cache"]
        TP["tp Register = 0x8000000 (Fast I/O)"]
        SysRegs["System Peripherals<br/>- Debug (0x8000000)<br/>- Time/MTIME (0x800002C)<br/>- GPIO (0x8000040)<br/>- UART (0x8000080)"]
        BusCtrl["Peripheral Bus Arbiter & Address Decoder"]
    end

    subgraph "Peripheral Slots (0x8000000+)"
        P3["Slot 3: Gamepad PMOD"]
        P8["Slot 8: PRISM Core"]
        P14["Slot 14: RV2A03 NES APU (0x8000380)"]
        PX["Slots 16-39: Other Contributed IP"]
    end

    subgraph "RV2A03 NES APU (Slot 14)"
        Pulse["Pulse 1 & 2 Generators"]
        Tri["Triangle Wave Generator"]
        Noi["LFSR Noise Generator"]
        Mix["Digital Linear Mixer (16-bit PCM)"]
        OutRegs["Extended Sample Registers (0x24/0x25)"]
    end

    subgraph "Physical I/O (PMOD Headers)"
        UART_TX["uo_out[0]: UART TX"]
        IRQ_PIN["uo_out[1]: apu_IRQ"]
        CE_PIN["uo_out[2]: apu_o_ce"]
        AUDIO_DAC["uo_out[7] / PMOD: PWM / Delta-Sigma DAC"]
    end

    Core <--> Cache
    Cache <--> Flash
    Cache <--> PSRAM
    Core <--> SysRegs
    Core <--> BusCtrl

    BusCtrl --> P3
    BusCtrl --> P8
    BusCtrl --> P14
    BusCtrl --> PX

    P14 --> Pulse
    P14 --> Tri
    P14 --> Noi
    Pulse --> Mix
    Tri --> Mix
    Noi --> Mix
    Mix --> OutRegs
    P14 --> IRQ_PIN
    P14 --> CE_PIN
    SysRegs --> UART_TX
    Mix -.-> AUDIO_DAC
```

---

## Quick Navigation

* To understand how the CPU boots and accesses memory: **[Chapter 01: TinyQV SoC Architecture](01_tinyqv_architecture.md)**
* To learn how to build or connect a new peripheral: **[Chapter 02: Peripherals & Slots](02_peripherals_and_slots.md)** & **[Chapter 03: Bus Protocol](03_peripheral_bus_protocol.md)**
* To understand classical NES chiptune synthesis: **[Chapter 04: Nintendo NES APU Architecture](04_nes_apu_architecture.md)**
* To program, debug, or inspect our silicon chip: **[Chapter 05: RV2A03 Peripheral & Comparison](05_rv2a03_peripheral.md)**
* **Silicon Visualization**:
  - 🖼️ [2D ASIC GDSII Layout Render](https://camo.githubusercontent.com/cac6e18a82b61a7fb0bae33d039d30e6a5a63dab5986ba3d7df82a8f59b8f89e/68747470733a2f2f666a706f6c6f2e6769746875622e696f2f74696e7971762d7276326130332f6764735f72656e6465722e706e67)
  - 🌐 [Interactive 3D GDS WebGL Viewer](https://fjpolo.github.io/tinyqv-rv2a03/)
