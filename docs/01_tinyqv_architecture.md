# 01. TinyQV SoC Architecture

## 1. Overview & Project Genesis

**TinyQV** is an open-source, ultra-compact 32-bit RISC-V System-on-Chip (SoC) designed by **Mike Bell** for the **Tiny Tapeout** collaborative multi-project ASIC shuttles (manufactured on the Skywater 130nm process node via Efabless).

To fit within the extreme silicon area and pin constraints of Tiny Tapeout (standard tile footprint: 160µm × 100µm per tile, shared QSPI pins), TinyQV makes targeted architectural trade-offs:
1. **Compressed Instruction Footprint**: Minimizes code footprint and memory bandwidth over external serial flash.
2. **Hardcoded Architectural Pointers**: Bypasses full 32-bit `lui` / `auipc` address generation instructions for rapid I/O access.
3. **Plug-and-Play Community Peripherals**: A standardized on-chip peripheral bus allowing dozens of designers to embed custom hardware blocks into unified peripheral slots.

---

## 2. RISC-V CPU Core: `rv32ec_zcb_zicond`

The TinyQV processor implements the **RV32EC** instruction set architecture with the **Zcb** and **Zicond** standard extensions:

```
                  +----------------------------------------------+
                  |                 TinyQV Core                  |
                  +----------------------------------------------+
                  | - RV32E   : 16 General-Purpose Registers     |
                  | - C       : Standard 16-bit Compressed Instructions |
                  | - Zcb     : Code Size Reduction Extensions   |
                  | - Zicond  : Conditional Operations (No Branch) |
                  +----------------------------------------------+
```

### Architectural Subsets & Extensions

* **RV32E (Embedded Base)**:
  * Restricts the general-purpose register file to **16 registers** (`x0` through `x15`) instead of 32.
  * Slices the register file silicon area in half, conserving precious routing and standard cell area.
  * Standard calling convention: `ilp32e`.

* **C (Compressed Instructions)**:
  * Implements 16-bit compressed encodings for the most frequent instructions (`c.lw`, `c.sw`, `c.j`, `c.jal`, `c.li`, `c.addi`, `c.mv`).
  * Yields typical code size reductions of 25–35%, critical when running out of small internal memories (32 KB BRAM on FPGA) or reading instructions over QSPI.

* **Zcb (Code Size Reduction Extension)**:
  * Extends compressed encodings to byte/halfword operations:
    * `c.lbu` (load byte unsigned), `c.lhu` (load halfword unsigned)
    * `c.sb` (store byte), `c.sh` (store halfword)
    * `c.zext.b`, `c.sext.b`, `c.zext.h`, `c.sext.h` (sign/zero extension)
    * `c.mul` (16-bit compressed integer multiply)

* **Zicond (Conditional Operations)**:
  * Adds `czero.eqz` (conditional zero if equal to zero) and `czero.nez` (conditional zero if not equal to zero).
  * Eliminates branch instructions for simple ternary assignments (`a = (cond) ? b : 0`), preventing pipeline flushes.

---

## 3. Architecture Constraints & Hardware Pointers

To conserve standard cells, TinyQV features several unique microarchitectural characteristics:

### 1. 28-bit Address Space & 24-bit Program Space
* **Physical Memory**: 28-bit addressing (`0x0000000` through `0xFFFFFFF`).
* **Program Execution**: Program counters are limited to 24-bit space (`0x0000000` through `0x0FFFFFF`), allowing up to 16 MB of executable flash.

### 2. Hardcoded Architectural Registers (`gp` and `tp`)
On traditional RISC-V processors, accessing memory-mapped I/O requires a 2-instruction sequence (`lui` followed by `lw`/`sw`). TinyQV hardcodes two architectural registers in hardware at reset:

* **Global Pointer (`gp`)**: Hardcoded to `0x1000400` (the base of external RAM / PSRAM).
* **Thread Pointer (`tp`)**: Hardcoded to `0x8000000` (the base of the Memory-Mapped Peripheral Space).

> [!TIP]
> Because `tp` is permanently locked to `0x8000000`, the compiler and inline assembly can read or write any system register or peripheral using a single 16-bit compressed instruction:
> ```assembly
> sw a0, 0x40(tp)    # Stores a0 to 0x8000040 (GPIO OUT register) in 1 clock cycle!
> lw a1, 0x80(tp)    # Loads UART RX data from 0x8000080 in 1 clock cycle!
> ```

---

## 4. System Memory Map

```
0x0000000 +---------------------------------------------+
          | External QSPI Flash (Executable via XIP)    |
          | - 16 MB address space                       |
          | - FPGA: Mapped to 32 KB Dual-Port BRAM      |
0x0FFFFFF +---------------------------------------------+
0x1000000 +---------------------------------------------+
          | External QSPI PSRAM - Bank A (8 MB)         |
          | - Base global pointer gp = 0x1000400        |
0x17FFFFF +---------------------------------------------+
0x1800000 +---------------------------------------------+
          | External QSPI PSRAM - Bank B (8 MB)         |
0x1FFFFFF +---------------------------------------------+
          | [ Reserved Space ]                          |
0x8000000 +---------------------------------------------+
          | System Debug Registers                      |
0x8000040 +---------------------------------------------+
          | GPIO & Pin Function Select (FUNC_SEL)       |
0x8000080 +---------------------------------------------+
          | Hardware UART (115,200 baud)                |
0x80000C0 +---------------------------------------------+
          | Full User Peripheral Slots 3 - 15 (64B each)|
          | * Slot 14 (0x8000380): RV2A03 NES APU       |
0x8000400 +---------------------------------------------+
          | Simple Byte Peripheral Slots 0 - 15 (16B)   |
0x8000600 +---------------------------------------------+
          | Extended User Peripheral Slots 16 - 23 (64B)|
0x80007FF +---------------------------------------------+
          | [ Reserved Peripheral Space ]               |
0xFFFFF00 +---------------------------------------------+
          | MTIME & MTIMECMP (32-bit Hardware Timer)    |
0xFFFFF07 +---------------------------------------------+
```

---

## 5. Core System Peripherals

### 5.1 Debug Subsystem (`0x8000000` - `0x8000033`)
* `0x8000008` (R): **ID Register** — Returns ASCII identifier `0x41` ('A') representing TinyQV instance.
* `0x800000C` (R/W): **SEL Register** — Controls debug override on `uo_out[7:6]`. When bit is low, pin is used for internal hardware debugging; when high, peripheral control is allowed.
* `0x8000018` (W): **DEBUG_UART_DATA** — Single-byte direct debug transmit register.
* `0x800001C` (R): **DEBUG_STATUS** — Bit 0 indicates if debug UART TX is busy.

### 5.2 GPIO Controller & Multiplexer (`0x8000040` - `0x800007F`)
* `0x8000040` (R/W): **OUT Register** — Directly sets output pin states when pin function is set to GPIO.
* `0x8000044` (R): **IN Register** — Reads current logic levels on `ui_in[7:0]` (2-cycle synchronizer).
* `0x8000050` (R/W): **AUDIO_FUNC_SEL** — Dedicated audio routing mux to `uo_out[7]`.
* `0x8000060` - `0x800007F` (R/W): **FUNC_SEL[0..7]** — 32-bit registers assigning each output pin (`uo_out[0]` through `uo_out[7]`) to a peripheral index.

### 5.3 Hardware UART Controller (`0x8000080` - `0x80000BF`)
* `0x8000080` (W): **TX_DATA** — Transmit FIFO write register.
* `0x8000080` (R): **RX_DATA** — Receive buffer read register.
* `0x8000084` (R): **STATUS**:
  * `bit 0`: `tx_busy` (1 = transmitter active; do not write).
  * `bit 1`: `rx_available` (1 = unread byte waiting in buffer).
* `0x8000088` (R/W): **DIVIDER** — 13-bit clock divider:
  $$\text{DIVIDER} = \frac{f_{\text{clk}}}{\text{Baudrate}}$$
  *(e.g., at 64 MHz: $64,000,000 / 115,200 \approx 555$; at 27 MHz: $27,000,000 / 115,200 \approx 234$)*.
* `0x800008C` (R/W): **RX_SELECT** — `0` = `ui_in[7]` (default), `1` = `ui_in[3]`.

### 5.4 Real-Time Timer: MTIME (`0xFFFFF00` - `0xFFFFF07`)
TinyQV implements a standard RISC-V style 32-bit real-time counter:
* `0x800002C` (R/W): **MTIME_DIVIDER** — Sets prescaler to divide clock down to 1 MHz. Bits 0 and 1 are hardwired to `1`, dividing by multiples of 4 MHz.
* `0xFFFFF00` (R/W): **MTIME** — 32-bit microsecond counter. Increments every 1 µs.
* `0xFFFFF04` (R/W): **MTIMECMP** — Compare register. When `MTIME >= MTIMECMP`, hardware timer interrupt is asserted.

---

## 6. Execution Models: Physical ASIC vs. FPGA Emulation

| Attribute | Physical ASIC Silicon (Sky25a) | FPGA Emulation (Gowin Tang Console 60K / Nano 20K) |
| :--- | :--- | :--- |
| **System Clock** | **64 MHz** nominal | **27 MHz** synthesized via PLL |
| **Boot Memory** | External SPI/QSPI Flash (Winbond W25Q16/32) | On-chip 32 KB Dual-Port Block RAM (SP/DP BRAM) |
| **Execution Path** | eXecute-In-Place (XIP) via onboard 4-way cache | Direct single-cycle BRAM fetch at address `0x00000000` |
| **Data RAM** | External QSPI PSRAM (APMemory 64Mb) | Shared within 32 KB BRAM memory map |
| **Binary Format** | Raw contiguous binary (`.bin`) flashed to QSPI | Verilog text hex memory file (`.hex`) loaded at bitstream generation |
