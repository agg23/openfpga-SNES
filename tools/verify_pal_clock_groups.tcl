# Read-only post-fit SDC experiment. Never compile, save report databases, or
# export project assignments. Output files must go to a NEW empty directory.
# Usage: quartus_sta -t tools/verify_pal_clock_groups.tcl \
#   PROJECT_DIR CORE_SDC OUTPUT_DIR ntsc|pal baseline|candidate
package require ::quartus::project
package require ::quartus::sta

if {[llength $quartus(args)] != 5} {
    error "Expected PROJECT_DIR CORE_SDC OUTPUT_DIR ntsc|pal baseline|candidate"
}
lassign $quartus(args) project_dir core_sdc output_dir region mode
foreach var {project_dir core_sdc output_dir} {
    set $var [file normalize [set $var]]
}
if {$region ni {ntsc pal} || $mode ni {baseline candidate}} {
    error "Invalid region or mode"
}
if {[file exists $output_dir]} { error "Output directory must not exist: $output_dir" }
file mkdir $output_dir
set repo_dir [file dirname $project_dir]
set evidence [open [file join $output_dir verification.tsv] w]
proc record {args} {
    global evidence
    puts $evidence [join $args "\t"]
    flush $evidence
    puts "VERIFY: [join $args { | }]"
}
proc expect {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error "ASSERTION FAILED: $message" }
}

# Parse the actual SDC's set_clock_groups argument list without changing it.
# These stubs are only for reading group membership; Quartus reads the complete
# same file with real SDC commands below, including every legacy exception.
interp create group_parser
interp eval group_parser {
    set captured {}
    proc set_clock_groups {args} { global captured; lappend captured $args }
    proc derive_clock_uncertainty {} {}
    proc get_clocks {args} { return $args }
    proc set_multicycle_path {args} {}
    proc set_false_path {args} {}
}
interp eval group_parser [list source $core_sdc]
set captured [interp eval group_parser {set captured}]
interp delete group_parser
expect {[llength $captured] == 1} "Expected one clock-group command"
set group_args [lindex $captured 0]
expect {[lindex $group_args 0] eq "-asynchronous"} "Preserve asynchronous grouping"
set groups {}
for {set i 1} {$i < [llength $group_args]} {incr i 2} {
    expect {[lindex $group_args $i] eq "-group"} "Unexpected clock-group option"
    lappend groups [lindex $group_args [expr {$i+1}]]
}
expect {[llength $groups] == 7} "Expected seven groups"
expect {[llength [lindex $groups 3]] == 2} "System/memory must remain in one group"
foreach {index name} {0 bridge_spiclk 1 clk_74a 2 clk_74b} {
    expect {[string trim [lindex $groups $index]] eq $name} "Preserve input clock group"
}

record run $region $mode $project_dir $core_sdc
set opened 0
set netlist 0
set code [catch {
    project_open [file join $project_dir snes_pocket.qpf]
    set opened 1
    # In-memory only; the project close below explicitly suppresses export.
    set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
    record processors [get_global_assignment -name NUM_PARALLEL_PROCESSORS]
    create_timing_netlist -model slow
    set netlist 1
    set_operating_conditions -model slow -voltage 1100 -temperature 85
    record corner slow 1100 85
    # Explicit list avoids the QIP's original core_constraints.sdc. Include
    # HDL-embedded synchronizer exceptions just as the normal read_sdc does.
    foreach sdc [list [file join $project_dir snes_pocket.sdc] \
        [file join $repo_dir platform pocket apf_constraints.sdc] $core_sdc] {
        record read_sdc $sdc
        read_sdc $sdc
    }
    read_sdc -hdl
    update_timing_netlist

    set instance [expr {$region eq "pal" ? "mf_pllbase_pal_inst" : "mf_pllbase_inst"}]
    set targeted_unmatched 0
    set counter 0
    foreach group_index {3 4 5} {
        foreach filter [lindex $groups $group_index] {
            set matches [get_clocks -nowarn $filter]
            set names {}
            foreach_in_collection clk $matches { lappend names [get_clock_info -name $clk] }
            set expected [format {ic|mp1|%s|altera_pll_i|general[%d].gpll~PLL_OUTPUT_COUNTER|divclk} $instance $counter]
            set count [llength $names]
            record pll_filter $counter $group_index $filter $count {*}$names
            if {$count == 0} { incr targeted_unmatched }
            if {$mode eq "candidate" || $region eq "ntsc"} {
                expect {$count == 1 && [lindex $names 0] eq $expected} "Filter must match exactly expected clock $expected"
            } else {
                expect {$count == 0} "Original NTSC-only filter should miss PAL clock"
            }
            set clocks($counter) [get_clocks -nowarn $expected]
            expect {[get_collection_size $clocks($counter)] == 1} "Expected real counter clock absent"
            incr counter
        }
    }
    expect {$counter == 4} "Expected exactly four PLL group filters"
    record targeted_unmatched $targeted_unmatched
    foreach filter [lindex $groups 6] {
        set matches [get_clocks -nowarn $filter]
        record inactive_audio_filter $filter [get_collection_size $matches]
    }
    # Full tool-generated tables preserve cut flags and physical transfer counts.
    report_clocks -file [file join $output_dir clocks.log]
    report_clock_transfers -setup -file [file join $output_dir transfers-setup.log]
    report_clock_transfers -hold -file [file join $output_dir transfers-hold.log]
    # Prove these are real analyzed paths, not merely membership in a Tcl list.
    foreach analysis {setup hold} {
        foreach {from to} {0 1 1 0} {
            set paths [get_timing_paths -$analysis -npaths 1 -from_clock $clocks($from) -to_clock $clocks($to)]
            set count [get_collection_size $paths]
            expect {$count == 1} "Memory/system crossing unexpectedly unconstrained or cut"
            foreach_in_collection path $paths {
                record constrained_path $analysis $from $to [get_path_info -slack $path] \
                    [get_node_info -name [get_path_info -from $path]] \
                    [get_node_info -name [get_path_info -to $path]]
            }
        }
    }
    record result PASS
} result options]
if {$netlist} { catch {delete_timing_netlist} }
if {$opened} { project_close -dont_export_assignments }
close $evidence
if {$code} { return -options $options $result }
