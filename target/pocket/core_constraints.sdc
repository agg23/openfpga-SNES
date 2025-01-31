#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|*[0].*|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|*[2].*|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|*[3].*|divclk } \
 -group { ic|audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

derive_clock_uncertainty

set_multicycle_path -from {ic|nes|sdram|*} -to [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -start -setup 2
set_multicycle_path -from {ic|nes|sdram|*} -to [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -start -hold 1

set_multicycle_path -from [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -to {ic|nes|sdram|*} -setup 2
set_multicycle_path -from [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -to {ic|nes|sdram|*} -hold 1

set_false_path -from {ic|nes|mapper_flags*}
#set_false_path -from {ic|nes|downloading*}
