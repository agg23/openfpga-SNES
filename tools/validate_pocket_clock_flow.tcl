# Run on an isolated project copy. No compile, fit, atom API or project export.
package require ::quartus::project
package require ::quartus::sta
if {[llength $quartus(args)] != 3} {error "Expected PROJECT_DIR NEW_OUTPUT_DIR post_map|post_fit"}
lassign $quartus(args) project_dir output_dir stage
if {$stage ni {post_map post_fit}} {error "Unknown timing-netlist stage"}
if {[file exists $output_dir]} {error "Refusing to replace existing evidence"}
file mkdir $output_dir
set opened 0; set netlist 0
proc capture_clock_flow_reports {output_dir stage} {
    set f [open [file join $output_dir clocks.tsv] w]
    foreach_in_collection clock [get_clocks *] {
        foreach attr {type name period waveform master_clock master_clock_pin multiply_by divide_by phase offset duty_cycle edges edge_shifts is_inverted} {
            puts $f "[get_clock_info -name $clock]\t$attr\t[get_clock_info -$attr $clock]"
        }
    }
    close $f
    report_clocks -file [file join $output_dir common_vco_edges-clocks.rpt]
    report_clock_transfers -setup -file [file join $output_dir common_vco_edges-transfers-setup.rpt]
    report_clock_transfers -hold -file [file join $output_dir common_vco_edges-transfers-hold.rpt]
    set captures [get_registers {*g_pocket_sys_capture*}]
    if {[get_collection_size $captures] == 0} {error "Expected a1e3059 sys-capture registers absent"}
    foreach {corner model temp} {slow85 slow 85 slow0 slow 0 fast85 fast 85 fast0 fast 0} {
        if {$stage eq "post_map" && $corner ne "slow85"} {continue}
        set_operating_conditions -model $model -voltage 1100 -temperature $temp
        update_timing_netlist
        report_sdc -file [file join $output_dir common_vco_edges-$corner-sdc.rpt]
        foreach analysis {setup hold} {
            foreach {kind scope} [list global {} capture [list -to $captures]] {
                report_timing -$analysis -npaths 20 -nworst 1 {*}$scope -detail full_path \
                    -file [file join $output_dir common_vco_edges-$corner-$kind-$analysis.rpt]
            }
        }
    }
}
set code [catch {
    project_open [file join $project_dir snes_pocket.qpf]; set opened 1
    set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
    if {$stage eq "post_map"} {create_timing_netlist -post_map} else {create_timing_netlist}
    set netlist 1
    # The ordinary project/QIP order, including apf_constraints + core_constraints.
    read_sdc
    update_timing_netlist
    capture_clock_flow_reports $output_dir $stage
    puts "POCKET_CLOCK_FLOW_PASS stage=$stage"
} result options]
if {$netlist} {catch {delete_timing_netlist}}
if {$opened} {project_close -dont_export_assignments}
if {$code} {return -options $options $result}
