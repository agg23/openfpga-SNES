# Read-only, post-fit, all-corner timing review. No SDC mutations or exceptions.
package require ::quartus::project
package require ::quartus::sta
if {[llength $quartus(args)] != 3} {error "Expected PROJECT_DIR OUTPUT_DIR ntsc|pal"}
lassign $quartus(args) project_dir output_dir region
set project_dir [file normalize $project_dir]
set output_dir [file normalize $output_dir]
if {$region ni {ntsc pal}} {error "Invalid region"}
set overview [open [file join $output_dir review.tsv] w]
proc record {args} {global overview; puts $overview [join $args "\t"];flush $overview;puts "REVIEW [join $args { | }]"}
proc node_name {node} {if {$node eq ""} {return ""};return [get_node_info -name $node]}
proc clock_name {path direction} {
 set clk [get_path_info -${direction}_clock $path]
 if {$clk eq ""} {return ""}
 return "[get_clock_info -name $clk]:inverted=[get_path_info -${direction}_clock_is_inverted $path]"
}
proc inventory {label pattern} {
 set result [get_registers -nowarn $pattern]
 record collection $label [get_collection_size $result] $pattern
 global output_dir
 set f [open [file join $output_dir nodes-$label.tsv] w]
 puts $f "name\ttype\tlocation"
 foreach_in_collection n $result {
  puts $f "[get_node_info -name $n]\t[get_node_info -type $n]\t[get_node_info -location $n]"
 }
 close $f
 return $result
}
proc paths {corner label analysis count args} {
 global output_dir
 set opts [list -$analysis -npaths $count -nworst 1 {*}$args]
 set coll [get_timing_paths {*}$opts]
 record query $corner $label $analysis [get_collection_size $coll]
 set file [open [file join $output_dir $corner-$label-$analysis.tsv] w]
 puts $file "slack\tfrom\tto\tfrom_clock\tto_clock\trelationship\tskew\tdata_delay\tlogic_levels\tlaunch\tlatch\tsetup_start_multicycle\tsetup_end_multicycle\thold_start_multicycle\thold_end_multicycle"
 foreach_in_collection p $coll {
  set row [list [get_path_info -slack $p] [node_name [get_path_info -from $p]] [node_name [get_path_info -to $p]] [clock_name $p from] [clock_name $p to]]
  foreach attr {clock_relationship clock_skew data_delay num_logic_levels launch_time latch_time setup_start_multicycle setup_end_multicycle hold_start_multicycle hold_end_multicycle} {lappend row [get_path_info -$attr $p]}
  puts $file [join $row "\t"]
 }
 close $file
 if {[get_collection_size $coll]} {
  record report $corner $label $analysis [report_timing {*}$opts -detail full_path -file [file join $output_dir $corner-$label-$analysis.rpt]]
 }
}
set opened 0
set netlist 0
set code [catch {
 project_open [file join $project_dir snes_pocket.qpf]
 set opened 1
 set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
 create_timing_netlist -model slow
 set netlist 1
 read_sdc
 update_timing_netlist
 set msu [inventory msu {*g_msu.msu* *|MSU|* *|MSU:MSU|*}]
 set volume [inventory volume {*|MSU|volume* *|MSU:MSU|volume*}]
 set p65 [inventory p65 {*|CPU|P65C816|* *|SCPU:CPU|P65C816:*}]
 set dma [inventory dma {*|CPU|DMA* *|CPU|HDMA* *|CPU|A1T* *|CPU|A2A* *|SCPU:CPU|DMA* *|SCPU:CPU|HDMA* *|SCPU:CPU|A1T* *|SCPU:CPU|A2A*}]
 set wram [inventory wram-write {*|wram|latched_data_in* *|psram:wram|latched_data_in*}]
 set capture [inventory capture {*g_pocket_sys_capture*}]
 set lifecycle [inventory lifecycle {*g_sdram_lifecycle*}]
 set release [inventory release {*g_sdram_lifecycle*release_pipe*}]
 foreach name {sys_dq0 sys_fallback0 sys_use_dq sys_word0} {set part($name) [inventory $name [list *$name*]]}
 set instance [expr {$region eq "pal" ? "mf_pllbase_pal_inst" : "mf_pllbase_inst"}]
 foreach counter {0 1} {
  set name [format {ic|mp1|%s|altera_pll_i|general[%d].gpll~PLL_OUTPUT_COUNTER|divclk} $instance $counter]
  set clk($counter) [get_clocks -nowarn $name]
  record clock $counter $name [get_collection_size $clk($counter)]
  if {[get_collection_size $clk($counter)] != 1} {error "Missing regional clock $counter"}
 }
 foreach required {msu volume p65 wram capture lifecycle release} {if {[get_collection_size [set $required]] == 0} {error "Missing required collection $required"}}
 report_clocks -file [file join $output_dir clocks.rpt]
 report_clock_transfers -setup -file [file join $output_dir transfers-setup.rpt]
 report_clock_transfers -hold -file [file join $output_dir transfers-hold.rpt]
 report_ucp -summary -file [file join $output_dir unconstrained-summary.rpt]
 foreach {corner model temperature} {slow85 slow 85 slow0 slow 0 fast85 fast 85 fast0 fast 0} {
  set_operating_conditions -model $model -voltage 1100 -temperature $temperature
  update_timing_netlist
  record corner $corner $model $temperature
  report_clock_fmax_summary -file [file join $output_dir $corner-fmax.rpt]
  paths $corner global setup 100
  paths $corner negative-endpoints setup 1000 -less_than_slack 0
  paths $corner global hold 32
  paths $corner global recovery 16
  paths $corner global removal 16
  foreach analysis {setup hold} {
   paths $corner from-msu $analysis 16 -from $msu
   paths $corner to-msu $analysis 16 -to $msu
   paths $corner within-msu $analysis 16 -from $msu -to $msu
   paths $corner to-volume $analysis 16 -to $volume
   paths $corner from-volume $analysis 16 -from $volume
   paths $corner to-capture $analysis 32 -to $capture
   paths $corner from-capture $analysis 32 -from $capture
   foreach name {sys_dq0 sys_fallback0 sys_use_dq sys_word0} {
    if {[get_collection_size $part($name)]} {
     paths $corner to-$name $analysis 16 -to $part($name)
     paths $corner from-$name $analysis 16 -from $part($name)
    }
   }
   paths $corner p65-to-wram $analysis 16 -from $p65 -to $wram
   if {[get_collection_size $dma]} {paths $corner dma-to-wram $analysis 16 -from $dma -to $wram}
   paths $corner to-wram $analysis 16 -to $wram
   paths $corner from-lifecycle $analysis 16 -from $lifecycle
   paths $corner to-lifecycle $analysis 16 -to $lifecycle
   paths $corner mem-to-sys $analysis 16 -from_clock $clk(0) -to_clock $clk(1)
   paths $corner sys-to-mem $analysis 16 -from_clock $clk(1) -to_clock $clk(0)
  }
  foreach analysis {recovery removal} {
   paths $corner from-release $analysis 24 -from $release
   paths $corner lifecycle $analysis 24 -to $lifecycle
  }
 }
 record result PASS
} result options]
if {$netlist} {catch {delete_timing_netlist}}
if {$opened} {project_close -dont_export_assignments}
close $overview
if {$code} {return -options $options $result}
