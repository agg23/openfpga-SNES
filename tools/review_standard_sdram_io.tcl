# Read-only extraction from an ALREADY FITTED standard-SDRAM project.
# No clocks, delays, exceptions, assignments, or fitted atoms are changed here.
package require ::quartus::project
package require ::quartus::sta
if {[llength $quartus(args)] != 2} {error "Expected PROJECT_DIR NEW_OUTPUT_DIR"}
lassign $quartus(args) project_dir output_dir
set project_dir [file normalize $project_dir]
set output_dir [file normalize $output_dir]
set overview [open [file join $output_dir overview.tsv] w]
proc record {args} {global overview;puts $overview [join $args "\t"];flush $overview;puts "SDRAM_IO [join $args { | }]"}
proc node_name {node} {
 if {$node eq ""} {return ""}
 # Routing-only points can contain primitive labels instead of node IDs.
 if {[regexp {^[A-Z][A-Z0-9_]+$} $node]} {return "ROUTING_LABEL:$node"}
 if {[catch {get_node_info -name $node} name]} {return "RAW_NODE:$node"}
 return $name
}
proc safe {command} {if {[catch {uplevel 1 $command} value]} {return "UNAVAILABLE:[string map [list \n { } \r { } \t { }] $value]"};return $value}
proc inventory {label collection} {
 global output_dir
 set f [open [file join $output_dir inventory-$label.tsv] w]
 puts $f "name\ttype\tlocation\tcell\tprimitive"
 foreach_in_collection n $collection {
  set c [safe [list get_node_info -cell $n]]
  puts $f [join [list [node_name $n] [get_node_info -type $n] [get_node_info -location $n] \
    [safe [list get_cell_info -name $c]] [safe [list get_cell_info -wysiwyg_type $c]]] "\t"]
 }
 close $f;record inventory $label [get_collection_size $collection]
 return $collection
}
proc points {f path category} {
 foreach_in_collection pt [get_path_info -${category}_points $path] {
  set edge [get_point_info -edge $pt];set src "";set dst ""
  if {$edge ne ""} {set src [node_name [get_edge_info -src $edge]];set dst [node_name [get_edge_info -dst $edge]]}
  puts $f [join [list $category [get_point_info -type $pt] [get_point_info -rise_fall $pt] \
    [get_point_info -total_delay $pt] [get_point_info -incremental_delay $pt] \
    [node_name [get_point_info -node $pt]] [get_point_info -location $pt] $src $dst] "\t"]
 }
}
proc paths {corner label kind args} {
 global output_dir
 if {$kind in {setup hold recovery removal}} {
  set opts [list -$kind -detail full_path -show_routing -npaths 64 -nworst 2 {*}$args]
  set found [get_timing_paths {*}$opts]
 } else {
  set opts [list -show_routing -npaths 128 -nworst 4 {*}$args]
  if {$kind eq "min"} {lappend opts -min_path}
  set found [get_path {*}$opts]
 }
 record paths $corner $label $kind [get_collection_size $found]
 set f [open [file join $output_dir $corner-$label-$kind.tsv] w]
 puts $f "path\tfrom\tto\tarrival_time\tdata_delay\tsetup_or_hold_slack_only\tlaunch\tlatch\tclock_relationship\tclock_skew"
 set index 0
 foreach_in_collection p $found {
  incr index
  set row [list $index [node_name [get_path_info -from $p]] [node_name [get_path_info -to $p]]]
  foreach field {arrival_time data_delay} {lappend row [get_path_info -$field $p]}
  foreach field {slack launch_time latch_time clock_relationship clock_skew} {
   if {$kind in {min max}} {lappend row NOT_APPLICABLE_COMBINATIONAL_FRAGMENT} else {lappend row [get_path_info -$field $p]}
  }
  puts $f [join $row "\t"]
  set pf [open [file join $output_dir $corner-$label-$kind-path-$index.tsv] w]
  puts $pf "segment\ttype\trise_fall\ttotal\tincrement\tnode\tlocation\tedge_src\tedge_dst"
  points $pf $p arrival
  if {$kind ni {min max}} {points $pf $p required}
  close $pf
 }
 close $f
 if {[get_collection_size $found]} {
  set file [file join $output_dir $corner-$label-$kind.rpt]
  if {$kind in {min max}} {report_path {*}$opts -file $file} else {report_timing {*}$opts -file $file}
 }
}
proc micro_registers {corner label regs} {
 global output_dir
 set f [open [file join $output_dir $corner-$label-micro.tsv] w]
 puts $f "register\tdelay_type\ttsu\tth\ttco\ttch\ttcl\ttmin"
 set ef [open [file join $output_dir $corner-$label-clock-edges.tsv] w]
 puts $ef "register\tclock_edge_source\tclock_edge_destination\tmin_rr\tmax_rr\tmin_fr\tmax_fr\tmin_rf\tmax_rf\tmin_ff\tmax_ff"
 foreach_in_collection r $regs {
  foreach type {native_default} {
   set row [list [node_name $r] $type]
   foreach param {tsu th tco tch tcl tmin} {lappend row [safe [list get_register_info -$param $r]]}
   puts $f [join $row "\t"]
  }
  foreach edge [get_register_info -clock_edges $r] {
   set row [list [node_name $r] [node_name [get_edge_info -src $edge]] [node_name [get_edge_info -dst $edge]]]
   foreach rf {rr fr rf ff} {foreach bound {min max} {lappend row [safe [list get_edge_info -delay -$bound -$rf $edge]]}}
   puts $ef [join $row "\t"]
  }
 }
 close $f;close $ef
}
set opened 0;set netlist 0
set code [catch {
 project_open [file join $project_dir snes_pocket.qpf];set opened 1
 create_timing_netlist -model slow;set netlist 1
 read_sdc;update_timing_netlist
 set dq [inventory dq-ports [get_ports -nowarn {dram_dq[*]}]]
 set fwd [inventory forwarded-clock-port [get_ports -nowarn dram_clk]]
 set cmd [inventory command-ports [get_ports -nowarn {dram_a[*] dram_ba[*] dram_dqm[*] dram_cke dram_ras_n dram_cas_n dram_we_n}]]
 set cap [inventory dq-sample [get_registers -nowarn {*|dq_sample*}]]
 set rd [inventory read-data [get_registers -nowarn {*g_standard_sdram*|read_data*}]]
 set out [inventory output-regs [get_registers -nowarn {*g_standard_sdram*|dram_addr* *g_standard_sdram*|dram_ba* *g_standard_sdram*|dram_dqm* *g_standard_sdram*|dram_cke* *g_standard_sdram*|dram_ras_n* *g_standard_sdram*|dram_cas_n* *g_standard_sdram*|dram_we_n* *g_standard_sdram*|dq_out*}]]
 set oe [inventory output-enable [get_registers -nowarn {*g_standard_sdram*|dq_oe*}]]
 set ddio [inventory forwarded-clock-regs [get_registers -nowarn {*sdramclk_ddr*}]]
 if {[get_collection_size $dq]!=16 || [get_collection_size $cap]!=16 || [get_collection_size $fwd]!=1 || [get_collection_size $cmd]!=21 || [get_collection_size $rd]!=16} {error "Unexpected physical SDRAM port/capture inventory; do not substitute legacy nodes"}
 if {[get_collection_size $out]==0 || [get_collection_size $oe]==0} {error "Missing real output/OE registers"}
 if {[get_collection_size $ddio]==0} {record note DDIO_REGISTERS_ABSENT_REQUIRE_NATIVE_CLOCK_PATH_REVIEW}
 set c0 [get_clocks -nowarn {*mf_pllbase*_sdram_inst*general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
 set c1 [get_clocks -nowarn {*mf_pllbase*_sdram_inst*general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]
 if {[get_collection_size $c0]!=1 || [get_collection_size $c1]!=1} {error "Missing original C0/C1 clocks"}
 set c4 [get_clocks -nowarn {*mf_pllbase*_sdram_inst*general[4].gpll~PLL_OUTPUT_COUNTER|divclk}]
 if {[get_collection_size $c4]!=1} {error "Missing unique standard C4 clock"}
 foreach_in_collection c $c4 {
  record clock [get_clock_info -name $c] [get_clock_info -period $c] [get_clock_info -waveform $c] [get_clock_info -master_clock_pin $c]
  set root [get_clock_info -targets $c]
  inventory c4-clock-target $root
 }
 report_clocks -file [file join $output_dir clocks.rpt]
 report_clock_transfers -setup -file [file join $output_dir transfers-setup.rpt]
 report_clock_transfers -hold -file [file join $output_dir transfers-hold.rpt]
 report_ucp -summary -file [file join $output_dir unconstrained.rpt]
 foreach {corner model temp} {slow85 slow 85 slow0 slow 0 fast85 fast 85 fast0 fast 0} {
  set_operating_conditions -model $model -voltage 1100 -temperature $temp
  update_timing_netlist;record corner $corner $model $temp
  # Prioritize the internal timing root cause for the integration worker.
  foreach pair [list [list c0-memory $c0] [list c1-system $c1]] {
   lassign $pair domain clock
   paths $corner to-$domain setup -to_clock $clock
   report_timing -setup -to_clock $clock -npaths 20 -detail full_path -file [file join $output_dir $corner-to-$domain-worst20-setup.rpt]
  }
  paths $corner global setup
  report_timing -setup -npaths 20 -detail full_path -file [file join $output_dir $corner-worst20-setup.rpt]
  report_datasheet -expand_bus -file [file join $output_dir $corner-datasheet.rpt]
  report_min_pulse_width -nworst 32 -detail full_path -file [file join $output_dir $corner-pulse-width.rpt]
  foreach pair [list [list capture $cap] [list output $out] [list oe $oe] [list ddio $ddio]] {
   lassign $pair label registers;micro_registers $corner $label $registers
  }
  foreach kind {max min} {
   # These fragments explicitly lack a timing requirement and are NOT slacks.
   paths $corner pin-to-dq-sample $kind -from $dq -to $cap
   paths $corner output-register-to-pin $kind -from $out -to [get_ports -nowarn {dram_*}]
   paths $corner output-enable-to-pin $kind -from $oe -to $dq
   paths $corner ddio-register-to-clock-pin $kind -from $ddio -to $fwd
   # An empty root-to-port result is recorded, never replaced by Q-to-pin.
   paths $corner c4-root-to-forwarded-rise $kind -from $root -rise_to $fwd
   paths $corner c4-root-to-forwarded-fall $kind -from $root -fall_to $fwd
   paths $corner c4-root-to-all-output-pins $kind -from $root -to [get_ports -nowarn {dram_*}]
   # Clock edges end at the vendor register timing reference (including its
   # model cell arc). Keep both src/dst names and never call this just wire delay.
   paths $corner c4-root-to-capture-timing-reference $kind -from $root -to $cap
  }
  foreach analysis {setup hold} {
   # Full paths preserve launch/capture clocks, CQ, uncertainty and FF terms.
   paths $corner sample-to-read-data $analysis -from $cap -to $rd
   paths $corner to-output-registers $analysis -to $out
   paths $corner to-output-enable $analysis -to $oe
   paths $corner within-sdram-clock $analysis -from_clock $c4 -to_clock $c4
   if {$analysis eq "hold"} {paths $corner global $analysis}
  }
 }
 record result EXTRACTED_NOT_BOARD_SIGNOFF
} result options]
if {$netlist} {catch {delete_timing_netlist}}
if {$opened} {project_close -dont_export_assignments}
close $overview
if {$code} {return -options $options $result}
