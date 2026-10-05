# Read-only, original-SDC endpoint audit. No conditional I/O overlay.
package require ::quartus::project
package require ::quartus::sta
lassign $quartus(args) project_dir output_dir
project_open [file join $project_dir snes_pocket.qpf]
create_timing_netlist -model slow
read_sdc;update_timing_netlist
set f [open [file join $output_dir cart-paths.tsv] w]
puts $f "corner\tgroup\tslack\tfrom\tto\tfrom_clock\tto_clock\trelationship\tdata_delay"
foreach {corner model temperature} {slow85 slow 85 slow0 slow 0 fast85 fast 85 fast0 fast 0} {
 set_operating_conditions -model $model -voltage 1100 -temperature $temperature
 update_timing_netlist
 foreach {label pattern} {request_metadata *request_meta_hold* request_data *request_data_hold* cached_metadata *cache_rsp_meta*} {
  set regs [get_registers -nowarn $pattern]
  if {[get_collection_size $regs]==0} {error "Missing requested endpoint group $label"}
  set paths [get_timing_paths -setup -to $regs -npaths 10 -nworst 1 -detail full_path]
  if {[get_collection_size $paths]==0} {error "No original setup path to $label"}
  foreach_in_collection p $paths {
   puts $f [join [list $corner $label [get_path_info -slack $p] \
      [get_node_info -name [get_path_info -from $p]] [get_node_info -name [get_path_info -to $p]] \
      [get_clock_info -name [get_path_info -from_clock $p]] [get_clock_info -name [get_path_info -to_clock $p]] \
      [get_path_info -clock_relationship $p] [get_path_info -data_delay $p]] "\t"]
  }
  flush $f
  report_timing -setup -to $regs -npaths 10 -nworst 1 -detail full_path \
      -file [file join $output_dir $corner-$label-worst10.rpt]
 }
}
close $f
delete_timing_netlist;project_close -dont_export_assignments
puts ORIGINAL_CART_ENDPOINTS_COMPLETE
