#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

# The platform SDC has already called derive_pll_clocks.
source [file join [file dirname [info script]] pocket_clock_model.sdc]

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group [get_clocks -nowarn { ic|mp1|mf_pllbase*_inst|altera_pll_i|*[0].*|divclk \
          ic|mp1|mf_pllbase*_inst|altera_pll_i|*[1].*|divclk \
          ic|mp1|mf_pllbase*_inst|altera_pll_i|*[4].*|divclk \
          ic|mp1|mf_pllbase*_inst|altera_pll_i|outclk_wire[0] \
          ic|mp1|mf_pllbase*_inst|altera_pll_i|outclk_wire[1] \
          ic|mp1|mf_pllbase*_inst|altera_pll_i|outclk_wire[4] }] \
 -group [get_clocks -nowarn { ic|mp1|mf_pllbase*_inst|altera_pll_i|*[2].*|divclk \
          ic|mp1|mf_pllbase*_inst|altera_pll_i|outclk_wire[2] }] \
 -group [get_clocks -nowarn { ic|mp1|mf_pllbase*_inst|altera_pll_i|*[3].*|divclk \
          ic|mp1|mf_pllbase*_inst|altera_pll_i|outclk_wire[3] }] \
 -group { ic|audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

derive_clock_uncertainty

# Removed inherited ic|nes exceptions: this SNES design has no such instance.
# Do not retarget them to ic|snes or the standard SDRAM controller. The sys,
# PSRAM and standard SDRAM transfers remain related and single-cycle timed.
