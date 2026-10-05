# Native Quartus assignment APIs; compiler entry points are deliberately removed.
package require ::quartus::project
package require ::quartus::flow
set test_args $::quartus(args)
if {[llength $test_args] != 4} {error "usage: run-case.tcl RUN_ROOT PROFILE SNAPSHOT SEED_TCL_OR_EMPTY"}
set ::run_root [file normalize [lindex $test_args 0]]
set ::snapshot_path [file normalize [lindex $test_args 2]]
set profile [lindex $test_args 1]
set ::flow_calls 0
# Delete native compile entry points rather than retain callable renamed copies.
foreach command {execute_flow execute_module qexec exec} {
    if {[llength [info commands ::$command]]} {rename ::$command {}}
}
proc ::execute_module {args} {error "FORBIDDEN compiler module invocation: $args"}
proc ::qexec {args} {error "FORBIDDEN external Quartus command: $args"}
proc ::exec {args} {error "FORBIDDEN external process: $args"}
proc ::execute_flow {args} {
    if {$args ne "-compile"} {error "unexpected execute_flow request: $args"}
    incr ::flow_calls
    puts "FAKE_FLOW_ONLY $args; no compiler stage launched"
    # The real execute_flow exports settings before launching any compiler.
    export_assignments
    set rows {}
    foreach entity {{} core_top MAIN_SNES} {
        foreach type {global instance parameter} {
            set query [list get_all_assignments -type $type -name *]
            if {$entity ne {}} {lappend query -entity $entity}
            foreach_in_collection id [eval $query] {
                lappend rows [string map [list $::run_root <RUN_ROOT>] [get_assignment_info $id -get_tcl_command]]
            }
        }
    }
    set out [open $::snapshot_path w]
    foreach row [lsort -unique $rows] {puts $out $row}
    close $out
    puts "SNAPSHOT [llength [lsort -unique $rows]] effective assignments -> $::snapshot_path"
}
if {[info exists ::env(MSU1_OUTPUT_DIR)]} {unset ::env(MSU1_OUTPUT_DIR)}
cd $::run_root
set seed [lindex $test_args 3]
if {$seed ne {}} {
    project_open projects/snes_pocket.qpf
    source $seed
    project_close
    cd $::run_root
}
set argv [list $profile]
set argc 1
source [file join $::run_root generate.tcl]
if {$::flow_calls != 1} {error "expected exactly one intercepted flow, got $::flow_calls"}
puts "PASS native configuration generation: $profile"
