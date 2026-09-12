/*
 * Gowin Arora V PLLA wrapper for Tang Console 60K (GW5AT-LV60PG484AC1/I0)
 * Converts 50 MHz onboard crystal oscillator to 27 MHz system clock.
 *
 * Input:  50.000 MHz (V22)
 * VCO:    50 MHz * 27 / 1 = 1350.000 MHz
 * Output: 1350 MHz / 50   = 27.000 MHz
 */

`default_nettype wire

module gowin_pll_50_to_27 (
    input  wire clkin,      // 50 MHz onboard clock
    input  wire reset,      // Active-high reset input
    output wire clkout,     // 27.000 MHz output clock
    output wire lock        // Lock output
);

    wire [7:0] wMdQOut;
    wire [7:0] wMdDIn;
    wire [1:0] wMdOpc;
    wire       wMdAInc;
    wire       pll_lock;
    wire       pll_rst;
    wire       gw_gnd = 1'b0;

    wire clkfbout;
    wire clkout1, clkout2, clkout3, clkout4, clkout5, clkout6;

    PLLA PLLA_inst (
        .LOCK(pll_lock),
        .CLKOUT0(clkout),
        .CLKOUT1(clkout1),
        .CLKOUT2(clkout2),
        .CLKOUT3(clkout3),
        .CLKOUT4(clkout4),
        .CLKOUT5(clkout5),
        .CLKOUT6(clkout6),
        .CLKFBOUT(clkfbout),
        .MDRDO(wMdQOut),
        .CLKIN(clkin),
        .CLKFB(gw_gnd),
        .RESET(pll_rst),
        .PLLPWD(gw_gnd),
        .RESET_I(gw_gnd),
        .RESET_O(gw_gnd),
        .PSSEL({gw_gnd,gw_gnd,gw_gnd}),
        .PSDIR(gw_gnd),
        .PSPULSE(gw_gnd),
        .SSCPOL(gw_gnd),
        .SSCON(gw_gnd),
        .SSCMDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .SSCMDSEL_FRAC({gw_gnd,gw_gnd,gw_gnd}),
        .MDCLK(clkin),
        .MDOPC(wMdOpc),
        .MDAINC(wMdAInc),
        .MDWDI(wMdDIn)
    );

    defparam PLLA_inst.FCLKIN = "50";
    defparam PLLA_inst.IDIV_SEL = 1;
    defparam PLLA_inst.FBDIV_SEL = 1;
    defparam PLLA_inst.MDIV_SEL = 27;
    defparam PLLA_inst.MDIV_FRAC_SEL = 0;
    defparam PLLA_inst.ODIV0_SEL = 50;   // 1350 / 50 = 27.000 MHz
    defparam PLLA_inst.ODIV0_FRAC_SEL = 0;
    defparam PLLA_inst.CLKOUT0_EN = "TRUE";
    defparam PLLA_inst.CLKOUT1_EN = "FALSE";
    defparam PLLA_inst.CLKOUT2_EN = "FALSE";
    defparam PLLA_inst.CLKOUT3_EN = "FALSE";
    defparam PLLA_inst.CLKOUT4_EN = "FALSE";
    defparam PLLA_inst.CLKOUT5_EN = "FALSE";
    defparam PLLA_inst.CLKOUT6_EN = "FALSE";
    defparam PLLA_inst.CLKFB_SEL = "INTERNAL";
    defparam PLLA_inst.CLKOUT0_DT_DIR = 1'b1;
    defparam PLLA_inst.CLKOUT0_DT_STEP = 0;
    defparam PLLA_inst.CLK0_IN_SEL = 1'b0;
    defparam PLLA_inst.CLK0_OUT_SEL = 1'b0;
    defparam PLLA_inst.DYN_DPA_EN = "FALSE";
    defparam PLLA_inst.CLKOUT0_PE_COARSE = 0;
    defparam PLLA_inst.CLKOUT0_PE_FINE = 0;
    defparam PLLA_inst.DYN_PE0_SEL = "FALSE";
    defparam PLLA_inst.DE0_EN = "FALSE";
    defparam PLLA_inst.RESET_I_EN = "FALSE";
    defparam PLLA_inst.RESET_O_EN = "FALSE";
    defparam PLLA_inst.ICP_SEL = 6'bXXXXXX;
    defparam PLLA_inst.LPF_RES = 3'bXXX;
    defparam PLLA_inst.LPF_CAP = 2'b00;
    defparam PLLA_inst.SSC_EN = "FALSE";

    PLL_INIT u_pll_init(
        .I_RST(reset),
        .O_RST(pll_rst),
        .I_LOCK(pll_lock),
        .O_LOCK(lock),
        .I_MD_CLK(clkin),
        .O_MD_INC(wMdAInc),
        .O_MD_OPC(wMdOpc),
        .O_MD_WR_DATA(wMdDIn),
        .I_MD_RD_DATA(wMdQOut),
        .PLL_INIT_BYPASS(1'b0),
        .MDRDO(),
        .MDOPC(2'b00),
        .MDAINC(1'b0),
        .MDWDI(8'h0)
    );
    defparam u_pll_init.CLK_PERIOD = 20;  // 50 MHz = 20 ns
    defparam u_pll_init.MULTI_FAC = 27;   // MDIV_SEL = 27

endmodule
