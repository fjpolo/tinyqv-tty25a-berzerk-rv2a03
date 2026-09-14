# 03. Peripheral Bus Protocol & Timing

## 1. Overview

The **TinyQV Peripheral Bus** is a synchronous, memory-mapped on-chip bus protocol engineered specifically for ultra-low area overhead on ASIC shuttles while supporting full 8-bit, 16-bit, and 32-bit CPU transactions with optional flow control (wait-states).

Unlike complex industry buses like AMBA AXI or AHB, the TinyQV Peripheral Bus eliminates separate address phase, response phase, and complex burst channels, condensing all CPU-to-peripheral communication into a streamlined, deterministic register interface.

---

## 2. Bus Signal Definitions

```
                     +----------------------------------+
                     |         TinyQV SoC Core          |
                     +----------------------------------+
                                |            ^
               address[5:0]     |            |  data_out[31:0]
               data_in[31:0]    |            |  data_ready
               data_write_n[1:0]|            |  user_interrupt
               data_read_n[1:0] v            |
                     +----------------------------------+
                     |    Peripheral (e.g. RV2A03)      |
                     +----------------------------------+
```

| Signal Name | Direction | Width | Polarity | Description |
| :--- | :---: | :---: | :---: | :--- |
| `clk` | Input | 1 | Pos. Edge | Main system clock (64 MHz nominal ASIC, 27 MHz FPGA). |
| `rst_n` | Input | 1 | Active-Low | Synchronous system reset (0 = Reset state, 1 = Normal operation). |
| `address` | Input | 6 | High | Sub-peripheral byte/word address offset (`0x00` – `0x3F`). |
| `data_in` | Input | 32 | High | Write data from CPU. Bottom 8, 16, or 32 bits are valid depending on `data_write_n`. |
| `data_write_n` | Input | 2 | Active-Low | Write strobe and transfer width specifier. |
| `data_read_n` | Input | 2 | Active-Low | Read request and expected transfer width specifier. |
| `data_out` | Output | 32 | High | Read data returned from peripheral to CPU. |
| `data_ready` | Output | 1 | Active-High | Flow control / completion handshake (1 = ready, 0 = wait). |
| `user_interrupt` | Output | 1 | Active-High | Dedicated interrupt line routed directly to CPU core. |

---

## 3. Transfer Width Encodings: `data_write_n` & `data_read_n`

To eliminate complex byte-enable masks (`wstrb[3:0]`), TinyQV utilizes a 2-bit encoded control strobe:

| Binary (`[1:0]`) | Transfer Type | Active Width | Notes |
| :---: | :---: | :---: | :--- |
| `2'b11` | **IDLE / NO ACCESS** | None | Default bus resting state. No read or write occurs. |
| `2'b00` | **BYTE ACCESS** | **8-bit** | Valid data on `data_in[7:0]` or `data_out[7:0]`. |
| `2'b01` | **HALFWORD ACCESS**| **16-bit** | Valid data on bits `[15:0]`. |
| `2'b10` | **WORD ACCESS** | **32-bit** | Valid data across full `[31:0]`. |

> [!NOTE]
> `data_write_n` and `data_read_n` are active-low signals where `2'b11` indicates an inactive cycle.

In Verilog, decoding a write strobe is as concise as:
```verilog
// Detects any active write transaction (8, 16, or 32-bit):
wire is_writing = (data_write_n != 2'b11);

// Detects a specific 8-bit byte write:
wire is_byte_write = (data_write_n == 2'b00);
```

---

## 4. Bus Transaction Timing & Waveforms

### 4.1 Single-Cycle Zero-Wait-State Write
Most fast register blocks (such as the RV2A03 APU control registers) complete writes in a single clock cycle. The peripheral keeps `data_ready = 1` permanently asserted.

```
Cycle:            1           2           3
            +-----+     +-----+     +-----+
clk         |     |     |     |     |     |
        ----+     +-----+     +-----+     +-----
            +-----------------------+
address     |      Offset 0x20      |
        ----+-----------------------+-----------
            +-----------------------+
data_in     |    0x01 (CFG_CE)      |
        ----+-----------------------+-----------
        ----+                       +-----------
data_write_n|     2'b00 (8-bit)     | 2'b11 (Idle)
            +-----------------------+
        ----------------------------------------
data_ready  (Always asserted = 1)
        ----------------------------------------
```

1. **Cycle 1**: CPU places the target `address` (e.g. `0x20`), `data_in` (`0x01`), and asserts `data_write_n` (`2'b00`).
2. **Cycle 2 (Rising Edge)**: Peripheral registers sample `data_in` on the rising clock edge.
3. **Cycle 2**: Bus returns to idle (`data_write_n = 2'b11`). Transaction complete with 0 wait-states.

### 4.2 Single-Cycle Zero-Wait-State Read
For combinatorially multiplexed read paths, the read data is valid during the same clock cycle that `address` is presented:

```
Cycle:            1           2           3
            +-----+     +-----+     +-----+
clk         |     |     |     |     |     |
        ----+     +-----+     +-----+     +-----
            +-----------------------+
address     |      Offset 0x24      |
        ----+-----------------------+-----------
        ----+                       +-----------
data_read_n |     2'b00 (8-bit)     | 2'b11 (Idle)
            +-----------------------+
            +-----------------------+
data_out    |      Sample MSB       |
        ----+-----------------------+-----------
        ----------------------------------------
data_ready  (Always asserted = 1)
        ----------------------------------------
```

### 4.3 Multi-Cycle Wait-State Handshake (`data_ready = 0`)
When interfacing with slower peripherals (e.g. external SPI flash, multi-cycle CORDIC, division, or RSA accelerators), the peripheral deasserts `data_ready` to stall the CPU pipeline:

```
Cycle:            1           2           3           4
            +-----+     +-----+     +-----+     +-----+
clk         |     |     |     |     |     |     |     |
        ----+     +-----+     +-----+     +-----+     +-----
            +-----------------------------------+
address     |            Offset 0x04            |
        ----+-----------------------------------+-------
        ----+                                   +-------
data_read_n |           2'b10 (32-bit)          | 2'b11 (Idle)
            +-----------------------------------+
                                    +-----------+
data_out    <--- Invalid / Calculating -------->| Result Valid |
                                    +-----------+
                    +---------------------------+-------
data_ready  ________|          WAIT             | READY
                                                +-------
```

* **Stall Condition**: As long as `data_ready == 0` during an active read or write cycle, the TinyQV CPU halts its instruction execution pipeline.
* **Completion**: Once computation finishes, the peripheral asserts `data_ready = 1` and presents valid `data_out`. The CPU latches the result on the next rising clock edge and resumes execution.

---

## 5. Typical Verilog Implementation Skeleton

Below is the standard template used across TinyQV peripheral modules:

```verilog
module tqvp_my_peripheral (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  ui_in,
    output wire [7:0]  uo_out,

    input  wire [5:0]  address,
    input  wire [31:0] data_in,
    input  wire [1:0]  data_write_n,
    input  wire [1:0]  data_read_n,

    output wire [31:0] data_out,
    output wire        data_ready,
    output wire        user_interrupt
);

    // Internal Registers
    reg [7:0] reg_ctrl;
    reg [31:0] reg_data;

    // 1. Write Handler
    always @(posedge clk) begin
        if (!rst_n) begin
            reg_ctrl <= 8'h00;
            reg_data <= 32'h0;
        end else if (data_write_n != 2'b11) begin
            case (address)
                6'h00: reg_ctrl <= data_in[7:0];
                6'h04: reg_data <= data_in;
                default: ;
            endcase
        end
    end

    // 2. Read Multiplexer
    reg [31:0] read_comb;
    always @(*) begin
        case (address)
            6'h00:   read_comb = {24'h0, reg_ctrl};
            6'h04:   read_comb = reg_data;
            default: read_comb = 32'h0;
        endcase
    end

    assign data_out       = read_comb;
    assign data_ready     = 1'b1; // Zero-wait-state single cycle access
    assign user_interrupt = 1'b0;

endmodule
```
