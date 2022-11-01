set_global_assignment -entity "mf_pllbase_pal" -library "lib_mf_pllbase_pal" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "mf_pllbase_pal" -library "lib_mf_pllbase_pal" -name IP_TOOL_VERSION "21.1"
set_global_assignment -entity "mf_pllbase_pal" -library "lib_mf_pllbase_pal" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_mf_pllbase_pal" -name SPD_FILE [file join $::quartus(sip_path) "mf_pllbase_pal.spd"]

set_global_assignment -library "lib_mf_pllbase_pal" -name MISC_FILE [file join $::quartus(sip_path) "mf_pllbase_pal_sim/mf_pllbase_pal.vo"]
