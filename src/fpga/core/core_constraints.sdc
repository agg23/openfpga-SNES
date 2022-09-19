#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk } 

#create_generated_clock -name GSU_CACHE_CLK -source [get_pins -compatibility_mode {*|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] \
#							  -invert [get_pins {ic|snes|main|GSUMap|GSU|CACHE|altsyncram_component|auto_generated|*|clk0}]

#create_generated_clock -name CX4_MEM_CLK -source [get_pins -compatibility_mode {*|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] \
#							  -invert [get_pins {ic|snes|main|CX4Map|CX4|DATA_RAM|altsyncram_component|auto_generated|*|clk0 \
#														ic|snes|main|CX4Map|CX4|DATA_ROM|spram_sz|altsyncram_component|auto_generated|altsyncram1|*|clk0 }]

# Audio clocks (don't work)
#create_generated_clock -name AUDIO_CLK -source [get_ports clk_74a] \
#							  -divide_by 6.04248046875 [get_pins {ic|sound_i2s|audio_mclk*}]

#create_generated_clock -name AUDIO_CLK -source [get_ports clk_74a] \
#							  -divide_by 24.169921875 [get_pins {ic|sound_i2s|aud_mclk_divider[1]*}]

derive_clock_uncertainty

set_clock_groups -asynchronous -group [get_clocks { GSU_CACHE_CLK CX4_MEM_CLK }] 

set_max_delay 23 -from [get_registers { ic|icb|* \
													 ic|data_loader|* \
													 ic|snes|main|* \
													 ic|snes|rom_mask[*] \
													 ic|snes|rom_parser|parsed_rom_type[*] }] \
					  -to   [get_registers { ic|snes|sdram|a[*] \
													 ic|snes|sdram|ram_req* \
													 ic|snes|sdram|we* \
													 ic|snes|sdram|state[*] \
													 ic|snes|sdram|old_* \
													 ic|snes|sdram|busy* \
													 ic|snes|sdram|SDRAM_nCAS \
													 ic|snes|sdram|SDRAM_A[*] \
													 ic|snes|sdram|SDRAM_BA[*] }] 

set_max_delay 23 -from [get_registers { ic|snes|sdram|* }] \
					  -to   [get_registers { ic|snes|main|* \
													 ic|snes|bsram|* \
													 ic|snes|wram|* \
													 ic|snes|vram*|* }]

set_false_path -to [get_registers { ic|snes|sdram|ds ic|snes|sdram|data[*]}]
