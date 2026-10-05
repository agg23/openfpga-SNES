package require ::quartus::project
package require ::quartus::sta
if {[llength $quartus(args)] != 5} {error "Expected PROJECT_DIR OUTPUT_DIR REGION FITTED_MEM_DIV FITTED_SYS_DIV"}
lassign $quartus(args) project_dir output_dir region fitted_mdiv fitted_sdiv
set instance [expr {$region eq "pal" ? "mf_pllbase_pal_inst" : "mf_pllbase_inst"}]
set f [open [file join $output_dir clocks-raw.tsv] w]
proc record {args} {global f; puts $f [join $args "\t"];flush $f;puts [join $args { | }]}
proc dump {label} {
 foreach_in_collection c [get_clocks *] {
  set name [get_clock_info -name $c]
  foreach attr {type period waveform divide_by multiply_by master_clock master_clock_pin duty_cycle phase offset edges edge_shifts is_inverted nreg_pos nreg_neg} {
   if {[catch {get_clock_info -$attr $c} value]} {set value "ERROR:$value"}
   record $label $name $attr $value
   if {$attr eq "period" && [string is double -strict $value]} {record $label $name period_17g [format %.17g $value]}
  }
 }
}
proc reports {label} {
 global output_dir
 report_clocks -file [file join $output_dir $label-clocks.rpt]
 report_clocks -tree -file [file join $output_dir $label-clock-tree.rpt]
 report_clock_transfers -setup -file [file join $output_dir $label-transfers-setup.rpt]
 report_clock_transfers -hold -file [file join $output_dir $label-transfers-hold.rpt]
 set captures [get_registers {*g_pocket_sys_capture*}]
 if {[get_collection_size $captures] == 0} {error "Expected capture registers absent"}
 foreach {corner model temp} {slow85 slow 85 slow0 slow 0 fast85 fast 85 fast0 fast 0} {
  set_operating_conditions -model $model -voltage 1100 -temperature $temp
  update_timing_netlist
  report_sdc -file [file join $output_dir $label-$corner-sdc.rpt]
  foreach analysis {setup hold} {
   foreach {kind scope} [list global {} capture [list -to $captures]] {
    record $label $corner $kind $analysis [report_timing -$analysis -npaths 20 -nworst 1 {*}$scope -detail full_path -file [file join $output_dir $label-$corner-$kind-$analysis.rpt]]
   }
  }
 }
}
set opened 0;set netlist 0
set code [catch {
 project_open [file join $project_dir snes_pocket.qpf];set opened 1
 set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
 create_timing_netlist -model slow;set netlist 1
 read_sdc;update_timing_netlist
 dump original
 reports original
 set mem [format {ic|mp1|%s|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk} $instance]
 set sys [format {ic|mp1|%s|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk} $instance]
 set mempin [get_pins $mem];set syspin [get_pins $sys]
 record PIN_COUNTS [get_collection_size $mempin] [get_collection_size $syspin]
 set vco [format {ic|mp1|%s|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|vcoph[0]} $instance]
 set vcopin [get_pins $vco]
 record VCO_PIN_COUNT [get_collection_size $vcopin]
 set memclock [get_clocks $mem]
 set sysclock [get_clocks $sys]
 set mdiv [get_clock_info -divide_by $memclock]
 set sdiv [get_clock_info -divide_by $sysclock]
 if {$mdiv != $fitted_mdiv || $sdiv != $fitted_sdiv} {error "Timing-clock counters disagree with fitted PLL report"}
 if {$sdiv != 4*$mdiv} {error "Not the proven 4:1 counter relationship"}
 foreach c [list $memclock $sysclock] {
  if {[get_clock_info -master_clock $c] ne $vco || [get_clock_info -phase $c] != 0 || [get_clock_info -duty_cycle $c] != 50 || [get_clock_info -multiply_by $c] != 1} {error "Unsupported original PLL clock model"}
 }
 set medges [list 1 [expr {$mdiv+1}] [expr {2*$mdiv+1}]]
 set sedges [list 1 [expr {$sdiv+1}] [expr {2*$sdiv+1}]]
 record proven_counter_edges $mdiv $sdiv $medges $sedges
 set candidate [file normalize [file join [file dirname [info script]] .. target pocket experiments exact_counter_edges.sdc]]
 file copy $candidate [file join $output_dir exact_counter_edges.sdc]
 source $candidate
 update_timing_netlist
 dump common_vco_edges
 reports common_vco_edges
 record result PASS
} result options]
if {$netlist} {catch {delete_timing_netlist}}
if {$opened} {project_close -dont_export_assignments}
close $f
if {$code} {return -options $options $result}
