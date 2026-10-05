# Keep related PLL counter edges on the same 1 ps TimeQuest grid.
# Loaded after derive_pll_clocks and before clock groups/uncertainty.
# Derive every divisor from Quartus's current PLL model, never a board frequency.
# Original zero-phase, 50%-duty, 4:1 pair; the standard-refresh variants also
# require their dedicated 5:1 SDRAM/sys counter to use the same physical VCO.
# Hardware/odd-divider validation: docs/MSU1-clock-model-flow.md.
proc pocket_align_counter_edges {} {
    set memory [get_clocks -nowarn {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[0].*|divclk}]
    set system [get_clocks -nowarn {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[1].*|divclk}]
    set sdram [get_clocks -nowarn {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[4].*|divclk}]
    # Timing-driven synthesis sees behavioral outclk_wire clocks, before the
    # physical VCO/counter netlist exists. Do not invent a source pin/route in
    # that context or disable TDS by rejecting its documented native model.
    # Keep Quartus's native synthesis clocks; only mapped STA is authoritative
    # for exact related edges. The parent groups both native naming schemes.
    if {[info exists ::quartus(nameofexecutable)] &&
        $::quartus(nameofexecutable) eq "quartus_map" &&
        [get_collection_size $memory] == 0 &&
        [get_collection_size $system] == 0 &&
        [get_collection_size $sdram] == 0} {
        set first [get_clocks -nowarn {ic|mp1|mf_pllbase*_inst|altera_pll_i|outclk_wire[0]}]
        if {[get_collection_size $first] != 1} {
            error "Pocket clock model: missing behavioral synthesis PLL clock"
        }
        set standard [string match {*mf_pllbase*sdram_inst|*} [get_clock_info -name $first]]
        set count [expr {$standard ? 5 : 4}]
        set all [get_clocks -nowarn {ic|mp1|mf_pllbase*_inst|altera_pll_i|outclk_wire*}]
        if {[get_collection_size $all] != $count} {
            error "Pocket clock model: wrong behavioral synthesis clock count"
        }
        set first_name [get_clock_info -name $first]
        set prefix [string range $first_name 0 [expr {[string last | $first_name]-1}]]
        for {set index 0} {$index < $count} {incr index} {
            set clock [get_clocks -nowarn [format {%s|outclk_wire[%s]} $prefix $index]]
            if {[get_collection_size $clock] != 1} {
                error "Pocket clock model: missing behavioral synthesis output"
            }
            set phase [get_clock_info -phase $clock]
            if {[get_clock_info -type $clock] ne "generated" ||
                [get_clock_info -master_clock $clock] ne "clk_74a" ||
                [get_clock_info -master_clock_pin $clock] ne [format {%s|general[%s].gpll~PLL_OUTPUT_COUNTER|refclk} $prefix $index] ||
                [get_clock_info -duty_cycle $clock] != 50 ||
                [get_clock_info -offset $clock] != 0 ||
                [get_clock_info -is_inverted $clock] ||
                ($index != 3 && $phase != 0) ||
                ($index == 3 && ($phase < 89 || $phase > 91)) ||
                [get_clock_info -period $clock] <= 0 ||
                [llength [get_clock_info -edges $clock]] != 0 ||
                [llength [get_clock_info -edge_shifts $clock]] != 0} {
                error "Pocket clock model: unsupported behavioral synthesis clock"
            }
            puts "POCKET_PREMAP_NATIVE_CLOCK name=[get_clock_info -name $clock] period=[get_clock_info -period $clock]"
        }
        return
    }
    if {[get_collection_size $memory] != 1 || [get_collection_size $system] != 1} {
        error "Pocket clock model: expected one memory/system PLL clock pair"
    }
    set master [get_clock_info -master_clock $memory]
    set mdiv [get_clock_info -divide_by $memory]
    set sdiv [get_clock_info -divide_by $system]
    if {![string is integer -strict $mdiv] || ![string is integer -strict $sdiv] || $mdiv <= 0 || $sdiv != 4*$mdiv} {
        error "Pocket clock model: unsupported memory/system counter ratio"
    }
    set counters [list $memory $system]
    set divisors [list $mdiv $sdiv]
    set standard [string match {*mf_pllbase*sdram_inst|*} [get_clock_info -name $memory]]
    if {$standard} {
        if {[get_collection_size $sdram] != 1} {
            error "Pocket clock model: expected one standard SDRAM counter"
        }
        set ddiv [get_clock_info -divide_by $sdram]
        if {![string is integer -strict $ddiv] || $ddiv <= 0 || $sdiv != 5*$ddiv} {
            error "Pocket clock model: unsupported SDRAM/system counter ratio"
        }
        lappend counters $sdram
        lappend divisors $ddiv
    } elseif {[get_collection_size $sdram] != 0} {
        error "Pocket clock model: unexpected fifth counter in legacy PLL"
    }
    # Validate every related clock completely before replacing any one.
    set definitions {}
    foreach clock $counters divisor $divisors {
        if {[get_clock_info -type $clock] ne "generated" ||
            [get_clock_info -master_clock $clock] ne $master ||
            [get_clock_info -phase $clock] != 0 ||
            [get_clock_info -offset $clock] != 0 ||
            [get_clock_info -duty_cycle $clock] != 50 ||
            [get_clock_info -multiply_by $clock] != 1 ||
            [get_clock_info -is_inverted $clock] ||
            [llength [get_clock_info -edges $clock]] != 0 ||
            [llength [get_clock_info -edge_shifts $clock]] != 0} {
            error "Pocket clock model: unsupported derived PLL phase/duty/master"
        }
        set name [get_clock_info -name $clock]
        set pll [string range $name 0 [expr {[string first "|altera_pll_i|" $name]+13}]]
        if {![string equal -length [string length $pll] $pll $master]} {
            error "Pocket clock model: counter and master are not in the same PLL"
        }
        set targets [get_clock_info -targets $clock]
        if {[get_collection_size $targets] != 1} {
            error "Pocket clock model: expected one output counter target"
        }
        if {[get_node_info -name $targets] ne $name ||
            [get_clock_info -master_clock_pin $clock] ne "[string range $name 0 end-6]vco0ph\[0\]"} {
            error "Pocket clock model: unsupported output counter/source pin identity"
        }
        lappend definitions [list $name $targets $divisor]
    }
    # Use the physical common VCO output, not a sibling counter output.
    # A sibling is not on the real clock route and would lose source latency.
    set vco [get_clocks -nowarn $master]
    set source [get_pins -nowarn $master]
    if {![string match {*FRACTIONAL_PLL|vcoph\[0\]} $master] ||
        [get_collection_size $vco] != 1 || [get_collection_size $source] != 1} {
        error "Pocket clock model: expected one physical common VCO source"
    }
    if {[get_clock_info -duty_cycle $vco] != 50 ||
        [get_clock_info -phase $vco] != 0 ||
        [get_clock_info -offset $vco] != 0 ||
        [get_clock_info -is_inverted $vco]} {
        error "Pocket clock model: unsupported common VCO waveform"
    }
    foreach definition $definitions {
        lassign $definition name targets divisor
        # 50% output duty, including odd C via the PLL's even-duty odd mode.
        set edges [list 1 [expr {$divisor+1}] [expr {2*$divisor+1}]]
        puts "POCKET_COUNTER_EDGES name=$name source=$master divisor=$divisor edges=$edges"
        create_generated_clock -name $name -source $source -master_clock $master -edges $edges $targets
    }
}
pocket_align_counter_edges
rename pocket_align_counter_edges {}
