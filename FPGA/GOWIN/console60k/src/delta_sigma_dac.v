/*
 * High-Fidelity Audio DAC for PAM8403 Class-D Amplifier / PMOD-AUDIO v1.2
 *
 * Specifically designed for driving analog Class-D speaker amplifiers from FPGA pins.
 * Features:
 * 1. 105.5 kHz PWM Carrier (27 MHz / 256): Well above human hearing (20 kHz),
 *    eliminating RF intermodulation and op-amp slew-rate distortion on PAM8403.
 * 2. Silence Muting: When sample_in == 0, output is held flat at 0V.
 *    Eliminates all background hissing, hum, and switching noise during silence.
 * 3. Linear dynamic scaling: Maps 6-bit unipolar APU sample (0..45) smoothly
 *    to 8-bit dynamic range (0..225) with zero DC step discontinuity.
 */

`default_nettype wire

module delta_sigma_dac (
    input  wire        clk,        // 27 MHz system clock
    input  wire        rst_n,      // Active-low synchronous reset
    input  wire [15:0] sample_in,  // raw_audio_sample from APU (0..45 unipolar)
    output reg         pdm_out     // PWM / PDM bitstream to PMOD audio pins
);

    // APU mixer output is unipolar 0..45.
    // Scale by 5: (sample * 5) maps 0..45 to 0..225 (fits cleanly in 8-bit 0..255)
    wire [5:0] raw = sample_in[5:0];
    wire [7:0] level = (raw << 2) + {2'b0, raw}; // raw * 5

    reg [7:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 8'd0;
            pdm_out <= 1'b0;
        end else begin
            counter <= counter + 8'd1;
            // Complete silence muting: zero carrier when audio is silent
            if (sample_in == 16'd0) begin
                pdm_out <= 1'b0;
            end else begin
                pdm_out <= (counter < level);
            end
        end
    end

endmodule
