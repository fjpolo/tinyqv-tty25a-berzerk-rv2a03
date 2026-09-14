# 04. Nintendo NES APU Architecture

## 1. Introduction: The Sound of the 8-Bit Generation

The **Nintendo Entertainment System (NES)** and **Famicom** audio system was built into the system's main CPU chip:
* **Ricoh 2A03** (NTSC: North America & Japan) — Clocked at **1.789773 MHz** (Master crystal $21.47727\text{ MHz} \div 12$).
* **Ricoh 2A07** (PAL: Europe & Australia) — Clocked at **1.662607 MHz** (Master crystal $26.601712\text{ MHz} \div 16$).

The audio subsystem, known as the **Audio Processing Unit (APU)**, contains **five dedicated sound synthesis channels**: two pulse (square) wave generators, one triangle wave generator, one pseudo-random noise generator, and one 1-bit delta modulation (DMC) sample channel.

```
                      +---------------------------------------+
                      |         Ricoh 2A03 NES APU            |
                      +---------------------------------------+
                      |                                       |
                      |  [Pulse 1]  ----+                     |
                      |                 |--> [Pulse Mixer]----+
                      |  [Pulse 2]  ----+                     |
                      |                                       |--> [Audio Out]
                      |  [Triangle] ----+                     |
                      |  [Noise]    ----+--> [TND Mixer]------+
                      |  [DMC]      ----+                     |
                      |                                       |
                      +---------------------------------------+
```

---

## 2. The Five Sound Synthesis Channels

### 2.1 Pulse Channels 1 & 2 (Square Waves)
* **Register Addresses**:
  * Pulse 1: `$4000` (Volume/Duty), `$4001` (Sweep), `$4002` (Timer Low), `$4003` (Timer High / Length).
  * Pulse 2: `$4004` (Volume/Duty), `$4005` (Sweep), `$4006` (Timer Low), `$4007` (Timer High / Length).
* **Duty Cycles**: An 8-step sequencer outputs one of four duty waveforms:
  * `00` (12.5%): Thin, nasally reed sound.
  * `01` (25.0%): Classic bright lead tone.
  * `10` (50.0%): Hollow, round clarinet/flute tone (symmetric square wave).
  * `11` (75.0% / negated 25%): Functionally identical to 25% with inverted phase.
* **Volume & Envelope Generator**: 4-bit volume control (16 levels). Can operate in constant volume mode or as an automatic linear decay envelope.
* **Hardware Sweep Unit**: Automatically alters the 11-bit frequency timer up or down at programmable rates without CPU intervention. Essential for sound effects like jumping, falling, lasers, and pitch bends.
  * *Original Hardware Quirk*: Pulse 1 sweep unit subtracts the period using two's complement (`~period`), whereas Pulse 2 subtracts using ones' complement (`~period + 1`), creating a 1-unit pitch discrepancy when sweeping down.
* **Frequency Timer**: 11-bit divider:
  $$f_{\text{pulse}} = \frac{f_{\text{CPU}}}{16 \times (t + 1)}$$

### 2.2 Triangle Channel
* **Register Addresses**: `$4008` (Linear Counter / Halt), `$400A` (Timer Low), `$400B` (Timer High / Length).
* **Waveform Generation**: A 32-step sequencer cycles through values:
  $$15, 14, 13, \dots, 1, 0, 0, 1, \dots, 14, 15$$
  producing a stepped triangle/pseudo-sine wave.
* **No Volume Control**: The triangle wave is always at full amplitude when running. Volume dynamics can only be simulated by changing note duration.
* **Dual Length Counters**:
  * **Linear Counter**: High-resolution 7-bit counter clocked at 240 Hz (frame counter) allowing ultra-short, punchy bass notes.
  * **Length Counter**: Standard 5-bit duration timer.
* **Frequency**: Runs twice as fast as the pulse channels:
  $$f_{\text{triangle}} = \frac{f_{\text{CPU}}}{32 \times (t + 1)}$$

### 2.3 Noise Channel
* **Register Addresses**: `$400C` (Volume/Envelope), `$400E` (Mode & Period), `$400F` (Length Counter).
* **Sound Generation**: A 15-bit Galois Linear Feedback Shift Register (LFSR) generates pseudo-random binary states.
* **Mode Bit (Bit 7 of `$400E`)**:
  * `Mode 0` (15-bit long sequence): $2^{15} - 1 = 32,767$ bit pseudorandom white noise (used for explosions, snare drums, hi-hats, wind, waves).
  * `Mode 1` (93-bit short sequence): Taps bit 6 instead of bit 1, collapsing into a 93-step repeating cycle. Produces a harsh, robotic, metallic buzz (used for robotic voices, laser hums, and low engine drones).
* **Pitch Table**: 16 hardcoded timer frequencies selected by the lower 4 bits of `$400E`.

### 2.4 Delta Modulation Channel (DMC)
* **Register Addresses**: `$4010` (Frequency/Flags), `$4011` (Direct Load), `$4012` (Sample Address), `$4013` (Sample Length).
* **Sound Generation**: Plays 1-bit Delta-Pulse-Code-Modulation (DPCM) audio samples directly from 6502 CPU memory ($C000–$FFFF).
  * 1-bit input adds $+2$ or $-2$ to a 7-bit accumulator.
* **Direct DAC Access (`$4011`)**: The CPU can write 7-bit raw PCM values directly to the internal DAC at high frequencies (used by games like *Skate or Die* and *Ghostbusters* for speech).
* **Direct Memory Access (DMA)**: When reading samples, the DMC halts the 6502 CPU for 1–4 cycles per byte to fetch sample data.
* **Hardware Interrupt (DMC IRQ)**: Triggers an interrupt when sample playback completes.

---

## 3. The Frame Counter ($4017)

The APU does not rely on CPU software loops to update note envelopes and length counters. Instead, an internal sequencer called the **Frame Counter** runs at roughly 240 Hz (NTSC) or 200 Hz (PAL):

```
+-------------------------------------------------------------+
|               4-Step Mode (Bit 7 = 0)                       |
|  Step 1 (60 Hz)  : Envelopes & Linear Counter               |
|  Step 2 (120 Hz) : Envelopes, Linear Counter, Length, Sweep |
|  Step 3 (180 Hz) : Envelopes & Linear Counter               |
|  Step 4 (240 Hz) : Envelopes, Linear, Length, Sweep + IRQ   |
+-------------------------------------------------------------+
|               5-Step Mode (Bit 7 = 1)                       |
|  Step 1          : Envelopes & Linear Counter               |
|  Step 2          : Envelopes, Linear Counter, Length, Sweep |
|  Step 3          : Envelopes & Linear Counter               |
|  Step 4          : (Silent / Idle)                          |
|  Step 5          : Envelopes, Linear Counter, Length, Sweep |
|  (No Frame IRQ generated in 5-step mode)                    |
+-------------------------------------------------------------+
```

---

## 4. The Original Non-Linear Analog Mixer

One of the most defining acoustic characteristics of the real NES is that its audio channels were **not** summed digitally. Instead, each channel's output drove an analog resistor-transistor current network.

Because the channels pull against shared load resistors, the mixing is highly **non-linear**:

### 1. Pulse Wave Non-Linear Mixing Formula:
$$\text{Pulse Out} = \frac{95.88}{\frac{8128}{\text{pulse1} + \text{pulse2}} + 100}$$

### 2. Triangle, Noise, and DMC (TND) Non-Linear Mixing Formula:
$$\text{TND Out} = \frac{159.79}{\frac{1}{\frac{\text{triangle}}{8227} + \frac{\text{noise}}{12241} + \frac{\text{dmc}}{22638}} + 100}$$

### Acoustic Impact of Non-Linear Mixing:
* **Compression**: When both pulse channels play loudly together, their combined volume does not double; instead, it softly saturates and compresses.
* **Warmth**: Heavy low-frequency triangle bass gently ducks high-frequency noise hits, creating the punchy, coherent soundstage celebrated in retro gaming.
