#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase*_inst|altera_pll_i|*[0].*|divclk \
          ic|mp1|mf_pllbase*_inst|altera_pll_i|*[1].*|divclk } \
 -group { ic|mp1|mf_pllbase*_inst|altera_pll_i|*[2].*|divclk } \
 -group { ic|mp1|mf_pllbase*_inst|altera_pll_i|*[3].*|divclk } \
 -group { ic|audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

derive_clock_uncertainty

set sys_ce_clk [get_clocks {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[1].*|divclk}]
set_multicycle_path -from "ic|snes|sdram|*" -to $sys_ce_clk -start -setup 2
set_multicycle_path -from "ic|snes|sdram|*" -to $sys_ce_clk -start -hold 1
set_multicycle_path -from $sys_ce_clk -to "ic|snes|sdram|*" -setup 2
set_multicycle_path -from $sys_ce_clk -to "ic|snes|sdram|*" -hold 2

set_multicycle_path -from "ic|snes|wram|*" -to $sys_ce_clk -start -setup 2
set_multicycle_path -from "ic|snes|wram|*" -to $sys_ce_clk -start -hold 1
set_multicycle_path -from $sys_ce_clk -to "ic|snes|wram|*" -setup 2
set_multicycle_path -from $sys_ce_clk -to "ic|snes|wram|*" -hold 2

set_multicycle_path -from "ic|snes|aram|*" -to $sys_ce_clk -start -setup 2
set_multicycle_path -from "ic|snes|aram|*" -to $sys_ce_clk -start -hold 1
set_multicycle_path -from $sys_ce_clk -to "ic|snes|aram|*" -setup 2
set_multicycle_path -from $sys_ce_clk -to "ic|snes|aram|*" -hold 2

set boot1_regs [get_registers {*|boot1_rom:*|*}]
set_multicycle_path -from $boot1_regs -to $sys_ce_clk -start -setup 2
set_multicycle_path -from $boot1_regs -to $sys_ce_clk -start -hold 1
set_multicycle_path -from $sys_ce_clk -to $boot1_regs -setup 2
set_multicycle_path -from $sys_ce_clk -to $boot1_regs -hold 2

set aram_q_regs [get_registers {*|sram_ctrl:aram|sram:*|q[*]}]
set aram_wd_regs [get_registers {*|sram_ctrl:aram|sram:*|current_write_data[*]}]
set_multicycle_path -from $aram_q_regs -to $aram_wd_regs -setup 2
set_multicycle_path -from $aram_q_regs -to $aram_wd_regs -hold 1

set ss_clk_mem_85_9 [get_clocks {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[0].*|divclk}]
set ss_clk_sys_21_48 [get_clocks {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[1].*|divclk}]
set ss_cmd_regs [get_registers {*|savestate:*|cmd_qaddr[*] \
                                *|savestate:*|cmd_data[*] \
                                *|savestate:*|cmd_we}]
set ss_rsp_regs [get_registers {*|savestate:*|rsp_data[*]}]
set_multicycle_path -from $ss_cmd_regs -to $ss_clk_mem_85_9 -setup 2
set_multicycle_path -from $ss_cmd_regs -to $ss_clk_mem_85_9 -hold 2
set_multicycle_path -from $ss_rsp_regs -to $ss_clk_sys_21_48 -start -setup 2
set_multicycle_path -from $ss_rsp_regs -to $ss_clk_sys_21_48 -start -hold 2
