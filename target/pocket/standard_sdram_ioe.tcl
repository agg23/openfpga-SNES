# Standard-profile-only placement candidate. No RTL, clocks, I/O voltage, drive,
# slew, board delays, or timing exceptions are changed by these assignments.
# Fitter success/actual packing and all read/write/OE setup AND hold must be
# checked on each new fitted image; ON is a request, never timing evidence.
proc configure_standard_sdram_ioe {enabled} {
 set tag STANDARD_SDRAM_IOE_CANDIDATE_V1
 set dq {};set command {}
 for {set i 0} {$i<16} {incr i} {lappend dq [format {dram_dq[%d]} $i]}
 for {set i 0} {$i<13} {incr i} {lappend command [format {dram_a[%d]} $i]}
 for {set i 0} {$i<2} {incr i} {lappend command [format {dram_ba[%d]} $i] [format {dram_dqm[%d]} $i]}
 lappend command dram_cke dram_ras_n dram_cas_n dram_we_n
 set oe_node {ic|snes|g_standard_sdram.cart_memory|engine|dq_oe}
 # Keep the one-cycle OE D function and asynchronous release_sync[1] clear.
 # Local synthesis steering prevents its state guard becoming an incompatible
 # synchronous-clear pin; this is not a global optimization disable.
 set choices [list [list FAST_INPUT_REGISTER ON $dq] [list FAST_OUTPUT_REGISTER ON [concat $dq $command]] [list FAST_OUTPUT_ENABLE_REGISTER ON $dq] [list ALLOW_SYNCH_CTRL_USAGE OFF [list $oe_node]]]
 # Preflight all exact targets before changing anything. A tag is metadata,
 # NOT a separate Quartus assignment identity; never overwrite someone else's
 # setting and assume a later tagged removal could restore it.
 foreach choice $choices {
  lassign $choice name desired pins
  foreach_in_collection a [get_all_instance_assignments -name $name] {
   lassign $a section from to actual_name value entity actual_tag
   if {$to ni $pins || $from ne ""} {continue}
   if {$actual_tag eq $tag && ![string equal -nocase $value $desired]} {error "Unexpected edited candidate assignment: $name $to $value"}
   if {$enabled && $actual_tag ne $tag} {error "Existing unowned I/O assignment conflicts with standard candidate: $name $to"}
  }
 }
 foreach choice $choices {
  lassign $choice name desired pins
  foreach_in_collection a [get_all_instance_assignments -name $name -tag $tag] {
   lassign $a section from to actual_name value entity actual_tag
   if {$to in $pins && $from eq "" && [string equal -nocase $value $desired]} {
    set_instance_assignment -name $name $desired -to $to -tag $tag -remove
   }
  }
  if {$enabled} {foreach pin $pins {set_instance_assignment -name $name $desired -to $pin -tag $tag}}
 }
}
