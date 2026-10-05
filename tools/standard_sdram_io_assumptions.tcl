# OPT-IN, CONDITIONAL constraint proposal. NOT sourced by any production QSF/SDC.
# The caller must provide every board/margin number and retain its provenance.
# No numeric PCB values or uncertainty defaults are supplied by this procedure.
proc apply_standard_sdram_io_assumptions {a} {
 set fields {evidence root_clock expected_source pcb_clock_min pcb_clock_max pcb_read_min pcb_read_max pcb_command_min pcb_command_max pcb_write_min pcb_write_max tac_max toh_min tis tih extra_setup_margin extra_hold_margin}
 foreach key $fields {if {![dict exists $a $key]} {error "Missing explicit I/O assumption: $key"}}
 foreach key [dict keys $a] {if {$key ni $fields} {error "Unknown I/O assumption: $key"}}
 if {[string trim [dict get $a evidence]] eq ""} {error "I/O budget provenance is mandatory"}
 foreach key [lrange $fields 3 end] {
  set value [dict get $a $key]
  if {![string is double -strict $value] || [regexp -nocase {nan|inf} $value] || $value<0} {error "Non-finite/negative I/O assumption: $key"}
 }
 foreach group {clock read command write} {
  if {[dict get $a pcb_${group}_min]>[dict get $a pcb_${group}_max]} {error "$group PCB minimum exceeds maximum"}
 }
 set root_clock [get_clocks -nowarn [dict get $a root_clock]]
 if {[get_collection_size $root_clock]!=1} {error "Require one existing physical C4 clock"}
 foreach_in_collection c $root_clock {set source [get_clock_info -targets $c];set root_name [get_clock_info -name $c]}
 if {[get_collection_size $source]!=1} {error "Ambiguous C4 physical source"}
 foreach_in_collection n $source {if {[get_node_info -name $n] ne [dict get $a expected_source]} {error "Physical source is not the reviewed C4 pin"}}
 set fwd [get_ports dram_clk];set dq [get_ports {dram_dq[*]}]
 set cap [get_registers {*|dq_sample*}]
 set command [get_ports {dram_a[*] dram_ba[*] dram_dqm[*] dram_cke dram_ras_n dram_cas_n dram_we_n}]
 if {[get_collection_size $fwd]!=1 || [get_collection_size $dq]!=16 || [get_collection_size $cap]!=16 || [get_collection_size $command]!=21} {error "Unsupported actual SDRAM endpoint inventory"}
 # This is a real C4 -> DDIO mux -> output-buffer path, not a fabricated route.
 if {[get_collection_size [get_path -fall_from $source -rise_to $fwd -npaths 1]]!=1} {error "Cannot verify the real inverted forwarded clock path"}
 if {[get_collection_size [get_clocks -nowarn SDRAM_FWD_CONDITIONAL]]!=0} {error "Conditional clock already exists"}
 create_generated_clock -name SDRAM_FWD_CONDITIONAL -source $source -master_clock $root_name \
    -invert -divide_by 1 $fwd
 set bcmin [dict get $a pcb_clock_min];set bcmax [dict get $a pcb_clock_max]
 set us [dict get $a extra_setup_margin];set uh [dict get $a extra_hold_margin]
 set_input_delay -clock SDRAM_FWD_CONDITIONAL -max [expr {$bcmax+[dict get $a pcb_read_max]+[dict get $a tac_max]+$us}] $dq
 set_input_delay -clock SDRAM_FWD_CONDITIONAL -min [expr {$bcmin+[dict get $a pcb_read_min]+[dict get $a toh_min]-$uh}] $dq
 # CL3/BL1 target word: setup E2 -> L4 = 1.5T, hold E3 -> L4 = 0.5T.
 # Do NOT add the usual hold=1 compensating exception: it would incorrectly
 # relax the required hold relationship by one whole cycle. Internal paths are
 # unchanged. Revalidate if capture cycle, burst length, CL, or topology changes.
 set_multicycle_path -setup -end 2 -from $dq -to $cap
 foreach group {command write} {
  if {$group eq "command"} {set ports $command} else {set ports $dq}
  set_output_delay -clock SDRAM_FWD_CONDITIONAL -max \
    [expr {[dict get $a pcb_${group}_max]-$bcmin+[dict get $a tis]+$us}] $ports
  set_output_delay -clock SDRAM_FWD_CONDITIONAL -min \
    [expr {[dict get $a pcb_${group}_min]-$bcmax-[dict get $a tih]-$uh}] $ports
 }
 derive_clock_uncertainty
 puts "CONDITIONAL_IO_ASSUMPTIONS [dict get $a evidence]"
 puts "CONDITIONAL_IO_NOT_BOARD_SIGNOFF $a"
}
