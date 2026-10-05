// Standard-refresh experimental variant. Original wrapper remains untouched.
`timescale 1 ps / 1 ps
module mf_pllbase_sdram (
    input wire refclk, rst,
    output wire outclk_0, outclk_1, outclk_2, outclk_3, outclk_4, locked
);
    mf_pllbase_sdram_0002 mf_pllbase_sdram_inst (
        .refclk(refclk), .rst(rst),
        .outclk_0(outclk_0), .outclk_1(outclk_1),
        .outclk_2(outclk_2), .outclk_3(outclk_3),
        .outclk_4(outclk_4), .locked(locked)
    );
endmodule
