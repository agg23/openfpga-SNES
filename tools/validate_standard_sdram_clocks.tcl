# Map-only unit check. Clock creation/grouping uses the real project SDC includes.
package require ::quartus::project
package require ::quartus::sta
if {[llength $quartus(args)] != 2} {error "Expected NEW_UNIT_PROJECT_DIR STANDARD_BOOLEAN"}
lassign $quartus(args) unit_dir standard
proc pocket_unit_dump_clocks {filename} {
    set f [open $filename w]
    foreach_in_collection clock [get_clocks *] {
        foreach attr {type period waveform master_clock master_clock_pin divide_by multiply_by phase offset duty_cycle edges edge_shifts is_inverted} {
            puts $f "[get_clock_info -name $clock]\t$attr\t[get_clock_info -$attr $clock]"
        }
    }
    close $f
}
set opened 0; set netlist 0
set code [catch {
    project_open [file join $unit_dir pll_clock_unit.qpf]; set opened 1
    create_timing_netlist -post_map; set netlist 1
    read_sdc
    update_timing_netlist
    pocket_unit_dump_clocks aligned.tsv
    report_clocks -file aligned-clocks.rpt
    report_sdc -file aligned-sdc.rpt
    foreach analysis {setup hold} {
        report_clock_transfers -$analysis -file aligned-transfers-$analysis.rpt
    }
    set related {0 1}
    if {$standard} {lappend related 4}
    foreach from $related {
        foreach to $related {
            if {$from == $to} {continue}
            set fc [get_clocks -nowarn [format {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[%s].*|divclk} $from]]
            set tc [get_clocks -nowarn [format {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[%s].*|divclk} $to]]
            foreach analysis {setup hold} {
                set paths [get_timing_paths -$analysis -from_clock $fc -to_clock $tc -npaths 1]
                if {[get_collection_size $paths] == 0} {error "Related transfer was cut: $from -> $to $analysis"}
                puts "RELATED_TRANSFER_TIMED from=$from to=$to analysis=$analysis"
            }
        }
    }
    puts "STANDARD_CLOCK_UNIT_PASS standard=$standard"
} result options]
if {$netlist} {catch {delete_timing_netlist}}
if {$opened} {project_close -dont_export_assignments}
if {$code} {return -options $options $result}
