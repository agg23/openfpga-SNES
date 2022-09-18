set_global_assignment -entity "mf_pllcfg" -library "lib_mf_pllcfg" -name IP_TOOL_NAME "altera_pll_reconfig"
set_global_assignment -entity "mf_pllcfg" -library "lib_mf_pllcfg" -name IP_TOOL_VERSION "21.1"
set_global_assignment -entity "mf_pllcfg" -library "lib_mf_pllcfg" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_mf_pllcfg" -name SPD_FILE [file join $::quartus(sip_path) "mf_pllcfg.spd"]

set_global_assignment -library "lib_mf_pllcfg" -name MISC_FILE [file join $::quartus(sip_path) "mf_pllcfg_sim/mf_pllcfg.v"]
set_global_assignment -library "lib_mf_pllcfg" -name MISC_FILE [file join $::quartus(sip_path) "mf_pllcfg_sim/altera_pll_reconfig/altera_pll_reconfig_top.v"]
set_global_assignment -library "lib_mf_pllcfg" -name MISC_FILE [file join $::quartus(sip_path) "mf_pllcfg_sim/altera_pll_reconfig/altera_pll_reconfig_core.v"]
set_global_assignment -library "lib_mf_pllcfg" -name MISC_FILE [file join $::quartus(sip_path) "mf_pllcfg_sim/altera_pll_reconfig/altera_std_synchronizer.v"]
