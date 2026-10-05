# Original-SDC fitted paths only. Called through the locked Python wrapper.
package require ::quartus::project
package require ::quartus::sta
if {[llength $quartus(args)] != 2} {error "Expected PROJECT_DIR NEW_OUTPUT_DIR"}
lassign $quartus(args) project_dir output_dir
set table [open [file join $output_dir paths.tsv] w]
puts $table "corner\tgroup\trank\tslack\tfrom\tto\tfrom_clock\tto_clock\trelationship\tdata_delay"
set inventory [open [file join $output_dir inventory.tsv] w]
puts $inventory "group\tcount\tname"
proc paths {corner label args} {
 global table output_dir
 set opts [list -setup -npaths 20 -nworst 1 -detail full_path {*}$args]
 set found [get_timing_paths {*}$opts]
 set rank 0
 foreach_in_collection p $found {
  incr rank
  puts $table [join [list $corner $label $rank [get_path_info -slack $p] \
    [get_node_info -name [get_path_info -from $p]] [get_node_info -name [get_path_info -to $p]] \
    [get_clock_info -name [get_path_info -from_clock $p]] [get_clock_info -name [get_path_info -to_clock $p]] \
    [get_path_info -clock_relationship $p] [get_path_info -data_delay $p]] "\t"]
 }
 flush $table
 if {$rank} {report_timing {*}$opts -file [file join $output_dir $corner-$label-worst20.rpt]}
 puts "INTERNAL_PATHS $corner $label $rank";flush stdout
}
set opened 0;set netlist 0
set code [catch {
 project_open [file join $project_dir snes_pocket.qpf];set opened 1
 create_timing_netlist -model slow;set netlist 1
 read_sdc;update_timing_netlist
 set clocks {}
 # Prioritize C0 and C1 before enumerating the remaining clock domains.
 foreach n {0 1 2 3 4} {
  set pattern [format {*mf_pllbase*_sdram_inst*general[%d].gpll~PLL_OUTPUT_COUNTER|divclk} $n]
  set collection [get_clocks -nowarn $pattern]
  if {[get_collection_size $collection]!=1} {error "Missing unique standard PLL C$n"}
  foreach_in_collection c $collection {lappend clocks [list c$n $c];set seen($c) 1}
 }
 set index 0
 foreach_in_collection c [get_clocks *] {
  if {![info exists seen($c)]} {lappend clocks [list other[incr index] $c]}
 }
 foreach pair $clocks {lassign $pair label c;puts $inventory [join [list $label 1 [get_clock_info -name $c]] "\t"]}
 set groups {}
 foreach {label pattern} {
  spc {*SPC7110*} sdd {*SDD1*} bsx {*BSXMap*}
  request_metadata {*request_meta_hold*} request_data {*request_data_hold*} cached_metadata {*cache_rsp_meta*}
 } {
  set regs [get_registers -nowarn $pattern]
  set count [get_collection_size $regs]
  puts $inventory [join [list $label $count $pattern] "\t"]
  if {$count} {lappend groups [list $label $regs]}
 }
 flush $inventory
 report_clocks -file [file join $output_dir clocks.rpt]
 foreach {corner model temp} {slow85 slow 85 slow0 slow 0 fast85 fast 85 fast0 fast 0} {
  set_operating_conditions -model $model -voltage 1100 -temperature $temp
  update_timing_netlist
  foreach pair $clocks {lassign $pair label c;paths $corner to-$label -to_clock $c}
  foreach pair $groups {
   lassign $pair label regs
   paths $corner to-$label -to $regs
   if {$label in {spc sdd bsx}} {paths $corner from-$label -from $regs}
  }
 }
} message options]
close $table;close $inventory
if {$netlist} {delete_timing_netlist}
if {$opened} {project_close -dont_export_assignments}
if {$code} {return -options $options $message}
puts ORIGINAL_INTERNAL_PATHS_COMPLETE
