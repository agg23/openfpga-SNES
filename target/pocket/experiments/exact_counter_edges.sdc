# EXPERIMENTAL, NOT INCLUDED BY ANY QIP/PROJECT.
# Source only after derive_pll_clocks, for a fitted and separately verified
# zero-phase, 50%-duty common-VCO 4:1 Pocket memory/system counter pair.
# Odd memory counters require actual fitted ODD_DIV_EVEN_DUTY_EN=1 evidence.
# This changes only the timing-model edge representation at 1 ps resolution.
# It does not change PLL RTL, hardware frequency, I/O delays or timing exceptions.
proc pocket_exact_counter_edges {} {
 set memory [get_clocks -nowarn {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[0].*|divclk}]
 set system [get_clocks -nowarn {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[1].*|divclk}]
 if {[get_collection_size $memory] != 1 || [get_collection_size $system] != 1} {error "Expected exactly one Pocket memory/system clock pair"}
 set master [get_clock_info -master_clock $memory]
 set mdiv [get_clock_info -divide_by $memory]
 set sdiv [get_clock_info -divide_by $system]
 if {![string is integer -strict $mdiv] || ![string is integer -strict $sdiv] || $mdiv <= 0 || $sdiv != 4*$mdiv} {error "Unverified memory/system counter ratio"}
 foreach clock [list $memory $system] {
  if {[get_clock_info -master_clock $clock] ne $master || [get_clock_info -phase $clock] != 0 || [get_clock_info -duty_cycle $clock] != 50 || [get_clock_info -multiply_by $clock] != 1 || [get_clock_info -is_inverted $clock]} {error "Unsupported fitted clock phase/duty/master relationship"}
 }
 if {![string match *FRACTIONAL_PLL* $master]} {error "Expected real common fractional PLL VCO source"}
 set source [get_pins $master]
 if {[get_collection_size $source] != 1} {error "Expected one physical VCO source pin"}
 foreach clock [list $memory $system] divisor [list $mdiv $sdiv] {
  set name [get_clock_info -name $clock]
  set targets [get_clock_info -targets $clock]
  set edges [list 1 [expr {$divisor+1}] [expr {2*$divisor+1}]]
  puts "POCKET_EXACT_EDGES $name source=$master counter=$divisor edges=$edges"
  create_generated_clock -name $name -source $source -master_clock $master -edges $edges $targets
 }
}
pocket_exact_counter_edges
derive_clock_uncertainty
