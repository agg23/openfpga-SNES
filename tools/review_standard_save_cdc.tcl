# Read-only new Save/reset/FIFO/mailbox audit under the production SDC.
# No false paths, synchronizer assignments, delays or clocks are added here.
package require ::quartus::project
package require ::quartus::sta
package require ::quartus::sdc_ext
if {[llength $quartus(args)] != 2} {error "Expected PROJECT_DIR NEW_OUTPUT_DIR"}
lassign $quartus(args) project_dir output_dir
set inv [open [file join $output_dir inventory.tsv] w]
puts $inv "group\tname\tlocation\tclock_input\tasync_input\tfanouts"
set counts [open [file join $output_dir counts.tsv] w]
puts $counts "group\tcount"
set paths_table [open [file join $output_dir paths.tsv] w]
puts $paths_table "corner\tgroup\tanalysis\trank\tslack\tfrom\tto\tfrom_clock\tto_clock\trelationship\tdata_delay"
proc node_name {n} {
 if {$n eq ""} {return ""}
 if {[catch {get_node_info -name $n} name]} {return $n}
 return $name
}
proc edge_sources {r kind} {
 set names {}
 foreach e [get_register_info -${kind}_edges $r] {lappend names [node_name [get_edge_info -src $e]]}
 return [join $names { ; }]
}
proc registers {label pattern} {
 global inv counts
 set regs [get_registers -nowarn $pattern]
 puts $counts "$label\t[get_collection_size $regs]";flush $counts
 foreach_in_collection r $regs {
  set outs {}
  foreach_in_collection o [get_fanouts [get_registers [node_name $r]]] {lappend outs [node_name $o]}
  puts $inv [join [list $label [node_name $r] [get_node_info -location $r] \
    [edge_sources $r clock] [edge_sources $r asynch] [join $outs { ; }]] "\t"]
 }
 flush $inv
 return $regs
}
proc paths {corner label kind args} {
 global output_dir paths_table counts
 set opts [list -$kind -npaths 32 -nworst 1 -detail full_path {*}$args]
 set found [get_timing_paths {*}$opts]
 puts $counts "$corner/$label/$kind\t[get_collection_size $found]";flush $counts
 set rank 0
 foreach_in_collection p $found {
  incr rank
  set clocks {}
  foreach field {from_clock to_clock} {
   set c [get_path_info -$field $p]
   if {$c eq ""} {lappend clocks ""} else {lappend clocks [get_clock_info -name $c]}
  }
  puts $paths_table [join [list $corner $label $kind $rank [get_path_info -slack $p] \
    [node_name [get_path_info -from $p]] [node_name [get_path_info -to $p]] {*}$clocks \
    [get_path_info -clock_relationship $p] [get_path_info -data_delay $p]] "\t"]
 }
 flush $paths_table
 if {$rank} {report_timing {*}$opts -file [file join $output_dir $corner-$label-$kind.rpt]}
}
set opened 0;set netlist 0
set code [catch {
 project_open [file join $project_dir snes_pocket.qpf];set opened 1
 create_timing_netlist -model slow;set netlist 1
 read_sdc;update_timing_netlist
 set groups {}
 foreach {label pattern} {
  fence_ack {*rom_download_queue*|read_ack_sync*}
  fence_source {*|read_fence_issued* *|read_fence_saw_clear* *|queue_save_read_request* *rom_download_queue*|read_pending* *rom_download_queue*|read_ready* *rom_download_queue*|read_request_toggle* *rom_download_queue*|source_armed*}
  fence_destination {*rom_download_queue*|holding_fence* *rom_download_queue*|read_ack_toggle*}
  queue_reset {*rom_download_queue*|source_reset_sync* *rom_download_queue*|sink_reset_sync*}
  queue_fault {*rom_download_queue*|fault_sync*}
  host_reset {*host_reset_guard*|hold_sync*}
  reader_release {*data_unloader*|source_release* *data_unloader*|memory_release*}
  mailbox_sync {*sdram_transaction_cdc*|request_sync* *sdram_transaction_cdc*|response_sync* *sdram_transaction_cdc*|init_sync*}
  mailbox_release {*sdram_transaction_cdc*|sys_reset_sync* *sdram_transaction_cdc*|mem_reset_sync*}
 } {
  set regs [registers $label $pattern]
  if {[get_collection_size $regs]} {lappend groups [list $label $regs]}
 }
 set fifo_groups {}
 foreach {label pattern} {
  ordered_fifo {*rom_download_queue*|*transport_fifo|*}
  reader_address_fifo {*data_unloader*|*fifo_address_req|*}
  reader_response_fifo {*data_unloader*|*fifo_data_response|*}
 } {
  set regs [registers $label $pattern]
  if {[get_collection_size $regs]} {lappend fifo_groups [list $label $regs]}
 }
 set req_from [registers mailbox_request_sources {*sdram_transaction_cdc*|request_addr_hold* *sdram_transaction_cdc*|request_data_hold* *sdram_transaction_cdc*|request_write_hold* *sdram_transaction_cdc*|request_strb_hold*}]
 set req_to [registers mailbox_request_destinations {*sdram_transaction_cdc*|mem_addr* *sdram_transaction_cdc*|mem_data* *sdram_transaction_cdc*|mem_write* *sdram_transaction_cdc*|mem_strb*}]
 set rsp_from [registers mailbox_response_sources {*sdram_transaction_cdc*|response_data_hold* *sdram_transaction_cdc*|response_error_hold*}]
 set rsp_to [registers mailbox_response_destinations {*sdram_transaction_cdc*|rsp_rdata* *sdram_transaction_cdc*|rsp_error*}]
 foreach regs [list $req_from $req_to $rsp_from $rsp_to] {
  if {[get_collection_size $regs]==0} {error "Missing actual source-held mailbox endpoint group"}
 }
 set stage_pairs {};set pair_index 0
 set pair_file [open [file join $output_dir stage-pairs.tsv] w]
 puts $pair_file "label\tfrom\tto"
 foreach pair $groups {
  lassign $pair group regs
  foreach_in_collection r $regs {
   set name [node_name $r]
   if {[regexp {^(.*)\[([0-9]+)\]$} $name all stem index]} {
    set next_name [format {%s[%d]} $stem [expr {$index+1}]]
    set next [get_registers -nowarn $next_name]
    if {[get_collection_size $next]} {
     set label $group-stage[incr pair_index]
     lappend stage_pairs [list $label [get_registers $name] $next]
     puts $pair_file "$label\t$name\t$next_name"
    }
   }
  }
 }
 close $pair_file
 report_clocks -file [file join $output_dir clocks.rpt]
 report_ucp -file [file join $output_dir unconstrained-full.rpt]
 report_sdc -file [file join $output_dir sdc-active.rpt]
 report_sdc -ignored -file [file join $output_dir sdc-ignored.rpt]
 foreach kind {setup hold recovery removal} {
  report_clock_transfers -$kind -file [file join $output_dir clock-transfers-$kind.rpt]
 }
 # These are exception coverage reports, never positive timing-slack claims.
 foreach pair [concat $groups $fifo_groups] {
  lassign $pair label regs
  # Cyclone V/21.1 legacy reporter does not support -report_clock_groups;
  # retain clock-group cuts independently in sdc-active + clock-transfers.
  report_exceptions -setup -to $regs -npaths 4 -detail full_path \
    -file [file join $output_dir exceptions-to-$label.rpt]
 }
 foreach {corner model temp} {slow85 slow 85 slow0 slow 0 fast85 fast 85 fast0 fast 0} {
  set_operating_conditions -model $model -voltage 1100 -temperature $temp
  update_timing_netlist
  report_metastability -nchains 2048 -file [file join $output_dir $corner-metastability.rpt]
  foreach pair $groups {
   lassign $pair label regs
   foreach kind {setup hold} {paths $corner $label $kind -to $regs}
   # Downstream reset recovery/removal matters separately from expected
   # asynchronous assertion at the first release-stage FF.
   if {$label in {queue_reset host_reset reader_release mailbox_release}} {
    foreach kind {recovery removal} {paths $corner from-$label $kind -from $regs}
   }
  }
  foreach kind {setup hold} {
   paths $corner mailbox-request-payload $kind -from $req_from -to $req_to
   paths $corner mailbox-response-payload $kind -from $rsp_from -to $rsp_to
  }
  foreach pair $stage_pairs {
   lassign $pair label from to
   foreach kind {setup hold} {paths $corner $label $kind -from $from -to $to}
  }
 }
} message options]
close $inv;close $counts;close $paths_table
if {$netlist} {delete_timing_netlist}
if {$opened} {project_close -dont_export_assignments}
if {$code} {return -options $options $message}
puts SAVE_CDC_EXTRACTED_REQUIRES_REVIEW
