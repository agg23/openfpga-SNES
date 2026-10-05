# TEST ONLY. Add LAST in an isolated validation QSF, never in a real build.
# Must be launched by probe_pocket_fitter_clock_model.py.
# Block at SDC loading until that owning process terminates this test fitter.
if {$::quartus(nameofexecutable) ne "quartus_fit"} {
    error "Fitter clock-model probe was loaded by the wrong executable"
}
set probe_mem [get_clocks -nowarn {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[0].*|divclk}]
set probe_sys [get_clocks -nowarn {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[1].*|divclk}]
if {[get_collection_size $probe_mem] != 1 || [get_collection_size $probe_sys] != 1} {
    error "Fitter clock-model probe: missing pair"
}
set probe_medges [get_clock_info -edges $probe_mem]
set probe_sedges [get_clock_info -edges $probe_sys]
foreach probe_edges [list $probe_medges $probe_sedges] {
    if {[llength $probe_edges] != 3 || [lindex $probe_edges 0] != 1 ||
        [lindex $probe_edges 2] != 2*[lindex $probe_edges 1]-1} {
        error "Fitter clock-model probe: explicit counter edges absent"
    }
}
if {[lindex $probe_sedges 1]-1 != 4*([lindex $probe_medges 1]-1)} {
    error "Fitter clock-model probe: changed ratio"
}
puts "POCKET_FITTER_SDC_PASS mem_edges=$probe_medges sys_edges=$probe_sedges"
set probe_sdram [get_clocks -nowarn {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[4].*|divclk}]
set probe_dedges {}
if {[string match {*mf_pllbase*sdram_inst|*} [get_clock_info -name $probe_mem]]} {
    if {[get_collection_size $probe_sdram] != 1} {error "Fitter clock-model probe: missing standard SDRAM counter"}
    set probe_dedges [get_clock_info -edges $probe_sdram]
    if {[llength $probe_dedges] != 3 || [lindex $probe_dedges 0] != 1 ||
        [lindex $probe_dedges 2] != 2*[lindex $probe_dedges 1]-1 ||
        [lindex $probe_sedges 1]-1 != 5*([lindex $probe_dedges 1]-1) ||
        [get_clock_info -master_clock $probe_sdram] ne [get_clock_info -master_clock $probe_sys]} {
        error "Fitter clock-model probe: standard SDRAM edge ratio/master changed"
    }
    puts "POCKET_FITTER_SDRAM_SDC_PASS sdram_edges=$probe_dedges"
} elseif {[get_collection_size $probe_sdram] != 0} {
    error "Fitter clock-model probe: unexpected fifth counter"
}
puts "POCKET_FITTER_SDC_INTENTIONAL_EXIT: no core placement/routing requested"
if {![info exists ::env(POCKET_FITTER_PROBE_MARKER)]} {
    error "Use the bounded Python fitter-probe launcher"
}
set probe_file [open $::env(POCKET_FITTER_PROBE_MARKER) {WRONLY CREAT EXCL}]
puts $probe_file "PASS mem_edges=$probe_medges sys_edges=$probe_sedges sdram_edges=$probe_dedges"
close $probe_file
# qexit only exits the embedded SDC interpreter; it does NOT stop the fitter.
# Do not return to the fitter. The owning launcher observes the closed marker
# and terminates only its own process group, before core placement can begin.
while {1} {after 1000}
