# Read-only post-map CLOCK RELATION test. Synthetic board flight is exactly zero
# by fixture definition, never an estimate of the Pocket PCB or routed FPGA.
package require ::quartus::project
package require ::quartus::sta
lassign $quartus(args) project_dir output_dir period mode
project_open [file join $project_dir io_unit.qpf]
create_timing_netlist -post_map -model slow
create_clock -name MEM -period $period [get_ports clk]
create_generated_clock -name SDRAM_FWD -source [get_ports clk] -master_clock MEM \
    -invert -divide_by 1 [get_ports forwarded_clk]
set dq [get_ports {dq[*]}]
set cap [get_registers {*dq_sample[*]}]
if {[get_collection_size $dq]!=16 || [get_collection_size $cap]!=16} {error "wrong fixture endpoints"}
set_input_delay -clock SDRAM_FWD -max 5.5 $dq
set_input_delay -clock SDRAM_FWD -min 2.5 $dq
set_output_delay -clock SDRAM_FWD -max 2.0 [get_ports {write_data[*]}]
set_output_delay -clock SDRAM_FWD -min -1.0 [get_ports {write_data[*]}]
if {$mode ne "ordinary"} {set_multicycle_path -setup 2 -from $dq -to $cap}
if {$mode eq "restored_hold"} {set_multicycle_path -hold 1 -from $dq -to $cap}
update_timing_netlist
set f [open [file join $output_dir relations-$period-$mode.tsv] w]
puts $f "label\tanalysis\trelationship\tslack\tlaunch\tlatch\tfrom\tto"
foreach label {read write internal} {
 if {$label eq "read"} {set opts [list -from $dq -to $cap]}
 if {$label eq "write"} {set opts [list -to [get_ports {write_data[*]}]]}
 if {$label eq "internal"} {set opts [list -from $cap -to [get_registers {*read_data*}]]}
 foreach analysis {setup hold} {
  set paths [get_timing_paths -$analysis -detail full_path -npaths 1 {*}$opts]
  if {[get_collection_size $paths]!=1} {error "missing $label $analysis path"}
  foreach_in_collection p $paths {
   puts $f [join [list $label $analysis [get_path_info -clock_relationship $p] \
    [get_path_info -slack $p] [get_path_info -launch_time $p] [get_path_info -latch_time $p] \
    [get_node_info -name [get_path_info -from $p]] [get_node_info -name [get_path_info -to $p]]] "\t"]
  }
  report_timing -$analysis -detail full_path -npaths 1 {*}$opts \
    -file [file join $output_dir $period-$mode-$label-$analysis.rpt]
 }
}
close $f
report_path -from [get_ports clk] -to [get_ports forwarded_clk] -show_routing     -file [file join $output_dir $period-$mode-root-to-clock-pin.rpt]
report_clocks -file [file join $output_dir clocks-$period-$mode.rpt]
delete_timing_netlist
project_close -dont_export_assignments
