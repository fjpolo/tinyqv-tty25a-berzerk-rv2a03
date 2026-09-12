/*
 * TinyQV RV2A03 NES APU SoC - Top Level for Sipeed Tang 60K Retro Console
 * Target FPGA: Gowin Arora V GW5AT-LV60PG484AC1/I0 (GW5AT-60B)
 *
 * Interfaces:
 * - Clock: 50 MHz crystal oscillator (Pin V22)
 * - Reset: S0 User Button (Pin AA13, active-low)
 * - User Button: S1 / MODE Button (Pin AB13, active-low)
 * - UART: BL616 USB-Serial bridge (Pin U15 TX, Pin V14 RX) @ 115200 baud
 * - Lower PMOD (PMOD0): MUSE PMOD-AUDIO v1.2 (PAM8403 Amplifier + Loudspeaker)
 *     - Pin V19: Left Audio Channel -> Loudspeaker header (J2)
 *     - Pin V18: Right Audio Channel -> 3.5mm Headphone Jack
 * - Upper PMOD (PMOD1): PMOD-LEDx8 (8 Status / Activity LEDs)
 * - Onboard Audio: I2S Class-D DAC (Pins Y17, AB17, AA16, Y14)
 * - Onboard Status LEDs: Pins G11, U12
 */

`default_nettype wire

module tangconsole60k_top (
    input  wire       sys_clk_50m, // 50 MHz onboard crystal oscillator (Pin V22)
    input  wire       btn_rst_n,   // S0 button (Pin AA13, active-low: 0 = pressed, 1 = released)
    input  wire       btn_user_n,  // S1 / MODE button (Pin AB13, active-low)

    // USB-UART interface to onboard BL616 microcontroller
    output wire       uart_tx,     // FPGA TX -> BL616 RX (Pin U15)
    input  wire       uart_rx,     // FPGA RX <- BL616 TX (Pin V14)

    // Lower PMOD (PMOD0): MUSE PMOD-AUDIO v1.2 (PAM8403 Class-D Amplifier)
    output wire       pmod_audio_l, // Left Channel -> drives J2 Loudspeaker (Pin V19)
    output wire       pmod_audio_r, // Right Channel -> drives 3.5mm Jack (Pin V18)

    // Upper PMOD (PMOD1): PMOD-LEDx8 (8 Status & Activity LEDs)
    output wire [7:0] pmod_led,     // PMOD1 pins: [7]=W19, [6]=W20, [5]=F19, [4]=F20, [3]=E22, [2]=D22, [1]=E21, [0]=D21

    // Onboard Console I2S Audio DAC
    output wire       hp_bck,      // I2S Bit Clock (Pin Y17)
    output wire       hp_ws,       // I2S Word Select / LRCLK (Pin AB17)
    output wire       hp_din,      // I2S Serial Audio Data (Pin AA16)
    output wire       pa_en        // Power Amplifier Enable (Pin Y14, 1.5V)
);

    // -------------------------------------------------------------------------
    // Clock Generation: 50 MHz -> 27 MHz via Gowin Arora V PLLA
    // -------------------------------------------------------------------------
    wire sys_clk;    // 27.000 MHz system clock
    wire pll_locked; // PLL lock status

    gowin_pll_50_to_27 u_pll (
        .clkin (sys_clk_50m),
        .reset (1'b0),
        .clkout(sys_clk),
        .lock  (pll_locked)
    );

    // -------------------------------------------------------------------------
    // Reset Synchronizer & Power-On Reset (POR)
    // -------------------------------------------------------------------------
    // Tang Console S0 button (AA13) is active-LOW.
    reg [2:0] btn_rst_sync = 3'b000;
    always @(posedge sys_clk or negedge pll_locked) begin
        if (!pll_locked)
            btn_rst_sync <= 3'b000;
        else
            btn_rst_sync <= {btn_rst_sync[1:0], btn_rst_n};
    end
    wire rst_n_raw = btn_rst_sync[2] & pll_locked;

    // Power-on reset counter: holds reset for ~38 ms (2^20 cycles @ 27 MHz)
    // after bitstream configuration, and debounces button release.
    reg [19:0] por_cnt = 20'hFFFFF;
    reg        rst_sync_n = 1'b0;

    always @(posedge sys_clk or negedge rst_n_raw) begin
        if (!rst_n_raw) begin
            por_cnt    <= 20'hFFFFF;
            rst_sync_n <= 1'b0;
        end else if (por_cnt != 20'd0) begin
            por_cnt    <= por_cnt - 20'd1;
            rst_sync_n <= 1'b0;
        end else begin
            rst_sync_n <= 1'b1;
        end
    end

    // Enable onboard amplifier once reset is released
    assign pa_en = rst_sync_n;

    // -------------------------------------------------------------------------
    // User Button (S1 / MODE) Synchronizer
    // -------------------------------------------------------------------------
    reg [1:0] user_btn_sync = 2'b11;
    always @(posedge sys_clk) begin
        user_btn_sync <= {user_btn_sync[0], btn_user_n};
    end
    wire user_key = ~user_btn_sync[1]; // Active-high in logic

    // -------------------------------------------------------------------------
    // TinyQV SoC Core Instantiation
    // -------------------------------------------------------------------------
    wire [7:0]  uo_out;
    wire [15:0] raw_audio_sample;

    tinyQV_top #(
        .CLOCK_MHZ(27)
    ) u_tinyqv (
        .clk         (sys_clk),
        .rst_n       (rst_sync_n),
        .ui_in       ({uart_rx, 6'b000000, user_key}),
        .uo_out      (uo_out),
        .audio_sample(raw_audio_sample)
    );

    // TinyQV primary peripheral UART TX is mapped to uo_out[0]
    assign uart_tx = uo_out[0];

    // -------------------------------------------------------------------------
    // Audio PCM Scaling & Conditioning
    // -------------------------------------------------------------------------
    // Convert unipolar APU sample to 16-bit signed PCM centered at 0:
    // When muted (raw_audio_sample == 0), output exact digital silence (0).
    // When active, scale to symmetric AC waveform (-16384 .. +16384).
    reg signed [15:0] pcm_audio;
    always @(posedge sys_clk or negedge rst_sync_n) begin
        if (!rst_sync_n) begin
            pcm_audio <= 16'sd0;
        end else begin
            if (raw_audio_sample == 16'd0) begin
                pcm_audio <= 16'sd0;
            end else begin
                pcm_audio <= $signed({raw_audio_sample[5:0], 10'b0}) - 16'sd16384;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Delta-Sigma 1-Bit DAC for MUSE PMOD-AUDIO v1.2 (PAM8403 Amplifier)
    // -------------------------------------------------------------------------
    // Converts 16-bit PCM audio samples to high-speed 1-bit PDM stream.
    // The RC input filter of the PAM8403 demodulates this into pure analog audio,
    // directly driving the loudspeaker on header J2!
    wire pdm_audio;

    delta_sigma_dac u_pdm_dac (
        .clk       (sys_clk),
        .rst_n     (rst_sync_n),
        .sample_in (raw_audio_sample),
        .pdm_out   (pdm_audio)
    );

    // Drive both Left and Right PMOD channels so both the loudspeaker on J2
    // and the 3.5mm headphone jack receive the audio signal
    assign pmod_audio_l = pdm_audio;
    assign pmod_audio_r = pdm_audio;

    // -------------------------------------------------------------------------
    // I2S Audio Transmitter for Onboard Console DAC
    // -------------------------------------------------------------------------
    // 27 MHz / 18 = 1.5 MHz BCLK -> 46.875 kHz audio sample rate (32 bits/frame)
    i2s_tx #(
        .CLK_HZ (27_000_000),
        .BCLK_HZ( 1_500_000)
    ) u_i2s (
        .clk      (sys_clk),
        .rst_n    (rst_sync_n),
        .sample_l (pcm_audio),
        .sample_r (pcm_audio),
        .i2s_bclk (hp_bck),
        .i2s_lrclk(hp_ws),
        .i2s_din  (hp_din)
    );

    // -------------------------------------------------------------------------
    // Activity Detectors & Blinkers
    // -------------------------------------------------------------------------
    reg [24:0] heartbeat_cnt;
    always @(posedge sys_clk or negedge rst_sync_n) begin
        if (!rst_sync_n)
            heartbeat_cnt <= 25'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 25'd1;
    end

    // Pulse stretcher for UART TX activity LED
    reg [20:0] uart_act_cnt;
    always @(posedge sys_clk or negedge rst_sync_n) begin
        if (!rst_sync_n)
            uart_act_cnt <= 21'd0;
        else if (uart_tx == 1'b0) // start or data bit
            uart_act_cnt <= 21'h1FFFFF;
        else if (|uart_act_cnt)
            uart_act_cnt <= uart_act_cnt - 21'd1;
    end

    // Pulse stretcher for Audio activity LED
    reg [20:0] audio_act_cnt;
    always @(posedge sys_clk or negedge rst_sync_n) begin
        if (!rst_sync_n)
            audio_act_cnt <= 21'd0;
        else if (raw_audio_sample != 16'd0)
            audio_act_cnt <= 21'h1FFFFF;
        else if (|audio_act_cnt)
            audio_act_cnt <= audio_act_cnt - 21'd1;
    end

    // Audio PDM level accumulator for LED 5
    reg [15:0] pdm_density_cnt;
    reg [15:0] pdm_density_accum;
    reg        pdm_led_state;
    always @(posedge sys_clk or negedge rst_sync_n) begin
        if (!rst_sync_n) begin
            pdm_density_cnt   <= 16'd0;
            pdm_density_accum <= 16'd0;
            pdm_led_state     <= 1'b0;
        end else begin
            pdm_density_cnt <= pdm_density_cnt + 16'd1;
            if (pdm_audio)
                pdm_density_accum <= pdm_density_accum + 16'd1;
            if (pdm_density_cnt == 16'hFFFF) begin
                // Turn on if audio waveform is actively oscillating
                pdm_led_state     <= (|audio_act_cnt) & (pdm_density_accum[14]);
                pdm_density_accum <= 16'd0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // PMOD-LEDx8 Outputs (Upper PMOD / PMOD1)
    // -------------------------------------------------------------------------
    // PMOD-LEDx8 LEDs turn ON when driven HIGH (1 = ON, 0 = OFF)
    assign pmod_led[0] = heartbeat_cnt[23];    // LED 0: Heartbeat (~1.6 Hz)
    assign pmod_led[1] = heartbeat_cnt[24];    // LED 1: Slower heartbeat (~0.8 Hz)
    assign pmod_led[2] = ~rst_sync_n;          // LED 2: ON while in reset
    assign pmod_led[3] = |uart_act_cnt;        // LED 3: Blinking during UART TX activity
    assign pmod_led[4] = |audio_act_cnt;       // LED 4: ON when APU audio is playing
    assign pmod_led[5] = pdm_led_state;        // LED 5: Live PDM audio activity level
    assign pmod_led[6] = uo_out[1];            // LED 6: APU IRQ / Status
    assign pmod_led[7] = pll_locked;           // LED 7: 50M -> 27M PLL locked

endmodule
