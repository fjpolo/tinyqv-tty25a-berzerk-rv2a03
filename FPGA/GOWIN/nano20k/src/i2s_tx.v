/*
 * Standard Philips I2S Audio Transmitter for MAX98357A
 * Target: Sipeed Tang Nano 20K (GW2AR-LV18QN88C8/I7)
 *
 * Transmits 16-bit PCM stereo audio (L/R) over I2S (BCLK, LRCLK/WS, DIN).
 * Signals change on BCLK falling edge and are sampled on BCLK rising edge.
 */

`default_nettype wire

module i2s_tx #(
    parameter CLK_HZ  = 54_000_000,
    parameter BCLK_HZ =  1_500_000 // 1.5 MHz BCLK -> 46.875 kHz Sample Rate (32 BCLKs per frame)
) (
    input  wire        clk,        // System clock
    input  wire        rst_n,      // Active-low asynchronous reset

    input  wire [15:0] sample_l,   // Left channel 16-bit signed PCM sample
    input  wire [15:0] sample_r,   // Right channel 16-bit signed PCM sample

    output reg         i2s_bclk,   // Bit Clock out (Pin 56)
    output reg         i2s_lrclk,  // Word Select / Left-Right Clock (Pin 55): 0=Left, 1=Right
    output reg         i2s_din     // Serial Audio Data out (Pin 54)
);

    // Clock divider for BCLK: toggle every DIV_CNT cycles
    localparam DIV_CNT = CLK_HZ / (2 * BCLK_HZ);
    reg [7:0] clk_cnt;

    // Bit counter: 0..31 (32 BCLKs per audio frame, 16 Left + 16 Right)
    reg [4:0] bit_cnt;

    // Shift registers for audio data
    reg [15:0] shift_l;
    reg [15:0] shift_r;

    // Clock divider: generate BCLK
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt  <= 8'd0;
            i2s_bclk <= 1'b0;
        end else begin
            if (clk_cnt >= (DIV_CNT - 1)) begin
                clk_cnt  <= 8'd0;
                i2s_bclk <= ~i2s_bclk;
            end else begin
                clk_cnt  <= clk_cnt + 8'd1;
            end
        end
    end

    // Detect falling edge of BCLK (where transmitter changes data)
    wire bclk_fall = (clk_cnt == (DIV_CNT - 1)) && (i2s_bclk == 1'b1);

    // I2S state machine clocked on falling edge of BCLK
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt   <= 5'd0;
            i2s_lrclk <= 1'b1;
            i2s_din   <= 1'b0;
            shift_l   <= 16'd0;
            shift_r   <= 16'd0;
        end else if (bclk_fall) begin
            bit_cnt <= bit_cnt + 5'd1;

            case (bit_cnt)
                5'd0: begin
                    // Start of Left channel frame: LRCLK falls to 0
                    // In Philips I2S, MSB appears 1 BCLK cycle after LRCLK transition
                    i2s_lrclk <= 1'b0;
                    i2s_din   <= 1'b0; // 1-cycle delay slot
                    shift_l   <= sample_l;
                    shift_r   <= sample_r;
                end

                5'd1, 5'd2, 5'd3, 5'd4, 5'd5, 5'd6, 5'd7,
                5'd8, 5'd9, 5'd10, 5'd11, 5'd12, 5'd13, 5'd14, 5'd15: begin
                    // Transmit Left channel MSB down to LSB
                    i2s_din <= shift_l[15];
                    shift_l <= {shift_l[14:0], 1'b0};
                end

                5'd16: begin
                    // Start of Right channel frame: LRCLK rises to 1
                    i2s_lrclk <= 1'b1;
                    i2s_din   <= 1'b0; // 1-cycle delay slot
                end

                5'd17, 5'd18, 5'd19, 5'd20, 5'd21, 5'd22, 5'd23,
                5'd24, 5'd25, 5'd26, 5'd27, 5'd28, 5'd29, 5'd30, 5'd31: begin
                    // Transmit Right channel MSB down to LSB
                    i2s_din <= shift_r[15];
                    shift_r <= {shift_r[14:0], 1'b0};
                end
            endcase
        end
    end

endmodule
