# In-memory conditional STA only. The project's production SDC is unmodified.
package require ::quartus::project
package require ::quartus::sta
lassign $quartus(args) project_dir output_dir assumptions_file
project_open [file join $project_dir snes_pocket.qpf]
create_timing_netlist -model slow
read_sdc;update_timing_netlist
# Preserve an original-constraint view of the distinct 4x-memory bottleneck.
set memory_clock [get_clocks -nowarn {*mf_pllbase*_sdram_inst*general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
if {[get_collection_size $memory_clock]!=1} {error "Missing unique C0 memory clock"}
report_timing -setup -to_clock $memory_clock -npaths 10 -detail full_path     -file [file join $output_dir slow85-original-to-c0-worst10-setup.rpt]
source $assumptions_file
source [file join [file dirname [info script]] standard_sdram_io_assumptions.tcl]
apply_standard_sdram_io_assumptions $io_assumptions
set mf [open [file join $output_dir conditional-model.tsv] w]
foreach_in_collection c [get_clocks [dict get $io_assumptions root_clock]] {
 puts $mf "period_ns\t[get_clock_info -period $c]"
}
puts $mf "status\tCONDITIONAL_ASSUMPTIONS_NOT_BOARD_SIGNOFF"
close $mf
set dq [get_ports {dram_dq[*]}];set cap [get_registers {*|dq_sample*}]
set command [get_ports {dram_a[*] dram_ba[*] dram_dqm[*] dram_cke dram_ras_n dram_cas_n dram_we_n}]
set data_out [get_registers {*g_standard_sdram*|dq_out*}]
set oe [get_registers {*g_standard_sdram*|dq_oe*}]
set f [open [file join $output_dir conditional-slacks.tsv] w]
puts $f "corner\tgroup\tanalysis\tslack\trelationship\tfrom\tto\tdata_delay\tclock_skew"
foreach {corner model temperature} {slow85 slow 85 slow0 slow 0 fast85 fast 85 fast0 fast 0} {
 set_operating_conditions -model $model -voltage 1100 -temperature $temperature
 update_timing_netlist
 foreach group {read command write write_data output_enable} {
  if {$group eq "read"} {set opts [list -from $dq -to $cap]}
  if {$group eq "command"} {set opts [list -to $command]}
  if {$group eq "write"} {set opts [list -to $dq]}
  if {$group eq "write_data"} {set opts [list -from $data_out -to $dq]}
  if {$group eq "output_enable"} {set opts [list -from $oe -to $dq]}
  foreach analysis {setup hold} {
   set paths [get_timing_paths -$analysis -detail full_path -npaths 64 -nworst 2 {*}$opts]
   if {[get_collection_size $paths]==0} {error "Conditional $group $analysis path missing"}
   foreach_in_collection p $paths {
    puts $f [join [list $corner $group $analysis [get_path_info -slack $p] \
       [get_path_info -clock_relationship $p] [get_node_info -name [get_path_info -from $p]] \
       [get_node_info -name [get_path_info -to $p]] [get_path_info -data_delay $p] [get_path_info -clock_skew $p]] "\t"]
   }
   flush $f
   report_timing -$analysis -detail full_path -npaths 32 -nworst 2 {*}$opts \
       -file [file join $output_dir $corner-$group-$analysis.rpt]
  }
 }
}
report_clocks -file [file join $output_dir conditional-clocks.rpt]
close $f
delete_timing_netlist
project_close -dont_export_assignments
puts "CONDITIONAL_SCENARIO_COMPLETE_NOT_BOARD_SIGNOFF"
