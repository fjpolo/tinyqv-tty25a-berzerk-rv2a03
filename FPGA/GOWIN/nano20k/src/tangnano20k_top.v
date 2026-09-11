/*
 * TinyQV RV2A03 NES APU SoC - Top Level for Sipeed Tang Nano 20K
 * Target FPGA: Gowin GW2AR-LV18QN88C8/I7 (GW2AR-18C)
 *
 * Interfaces:
 * - Clock: 27 MHz crystal oscillator (Pin 4)
 * - Reset: S1 User Button (Pin 88, active-low)
 * - User Key 2: S2 User Button (Pin 87, active-low)
 * - UART: BL616 USB-Serial bridge (Pin 69 TX, Pin 70 RX) @ 115200 baud
 * - Audio: Onboard MAX98357A I2S Class-D DAC (Pins 51, 54, 55, 56)
 * - LEDs: 6 User LEDs (Pins 15-20, active-low)
 */

`default_nettype wire

module tangnano20k_top (
    input  wire       sys_clk,   // 27 MHz onboard crystal (Pin 4)
    input  wire       rst_n,     // S1 user button (Pin 88, active-low)
    input  wire       key2,      // S2 user button (Pin 87, active-low)

    // USB-UART interface to onboard BL616 microcontroller
    output wire       uart_tx,   // FPGA TX -> BL616 RX (Pin 69)
    input  wire       uart_rx,   // FPGA RX <- BL616 TX (Pin 70)

    // Onboard MAX98357A I2S Class-D amplifier
    output wire       pa_en,     // Power Amplifier Enable (Pin 51, Active-High)
    output wire       i2s_bclk,  // Bit Clock (Pin 56)
    output wire       i2s_lrclk, // Word Select / Frame Clock (Pin 55)
    output wire       i2s_din,   // Serial Audio Data (Pin 54)

    // Onboard status LEDs (Pins 15-20, Active-Low)
    output wire [5:0] led
);

    // -------------------------------------------------------------------------
    // Power Amplifier Enable
    // -------------------------------------------------------------------------
    // Turn on MAX98357A amplifier once reset is released
    reg pa_en_reg;
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n)
            pa_en_reg <= 1'b0;
        else
            pa_en_reg <= 1'b1;
    end
    assign pa_en = pa_en_reg;

    // -------------------------------------------------------------------------
    // Reset Synchronizer
    // -------------------------------------------------------------------------
    reg [2:0] rst_sync;
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n)
            rst_sync <= 3'b000;
        else
            rst_sync <= {rst_sync[1:0], 1'b1};
    end
    wire rst_sync_n = rst_sync[2];

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
        .ui_in       ({uart_rx, 6'b000000, ~key2}),
        .uo_out      (uo_out),
        .audio_sample(raw_audio_sample)
    );

    // TinyQV UART output is mapped to uo_out[6]
    assign uart_tx = uo_out[6];

    // -------------------------------------------------------------------------
    // Audio PCM Scaling & Conditioning
    // -------------------------------------------------------------------------
    // Convert 0..32 unipolar APU sample to 16-bit signed PCM centered at 0:
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
                // Shift by 10 bits and subtract midpoint 16384
                pcm_audio <= $signed({raw_audio_sample[5:0], 10'b0}) - 16'sd16384;
            end
        end
    end

    // -------------------------------------------------------------------------
    // I2S Audio Transmitter for MAX98357A
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
        .i2s_bclk (i2s_bclk),
        .i2s_lrclk(i2s_lrclk),
        .i2s_din  (i2s_din)
    );

    // -------------------------------------------------------------------------
    // Status LEDs (Active-Low: 0 = ON, 1 = OFF)
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

    assign led[0] = ~heartbeat_cnt[23]; // Heartbeat (~1.6 Hz)
    assign led[1] = rst_sync_n;         // ON when in reset
    assign led[2] = ~(|uart_act_cnt);   // ON during UART TX activity
    assign led[3] = ~(|audio_act_cnt);  // ON when Audio is playing
    assign led[4] = ~pa_en;             // ON when PA amplifier enabled
    assign led[5] = ~heartbeat_cnt[24]; // Slower heartbeat (~0.8 Hz)

endmodule
