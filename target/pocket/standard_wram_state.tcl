# Standard-profile-only synthesis steering for exactly the eight WRAM PSRAM
# state flops. No RTL, RAM timing, clocks, exceptions, ARAM or I/O controls change.
# OFF keeps the identical state transition on D rather than inferred SCLR/SLOAD.
proc configure_standard_wram_state {enabled} {
 set tag STANDARD_WRAM_STATE_DATA_ONLY_V1
 set name ALLOW_SYNCH_CTRL_USAGE
 set targets {}
 for {set i 0} {$i < 8} {incr i} {lappend targets [format {ic|snes|wram|state[%d]} $i]}
 # Preflight all exact targets before mutating anything. Preserve independent
 # settings and fail closed if an owned setting has been edited unexpectedly.
 foreach_in_collection a [get_all_instance_assignments -name $name] {
  lassign $a section from to actual_name value entity actual_tag
  if {$to ni $targets || $from ne ""} {continue}
  if {$actual_tag eq $tag && ![string equal -nocase $value OFF]} {error "Unexpected edited WRAM state assignment: $to $value"}
  if {$enabled && $actual_tag ne $tag} {error "Existing unowned WRAM state assignment conflicts: $to"}
 }
 foreach_in_collection a [get_all_instance_assignments -name $name -tag $tag] {
  lassign $a section from to actual_name value entity actual_tag
  if {$to in $targets && $from eq "" && [string equal -nocase $value OFF]} {
   set_instance_assignment -name $name OFF -to $to -tag $tag -remove
  }
 }
 if {$enabled} {
  foreach target $targets {set_instance_assignment -name $name OFF -to $target -tag $tag}
 }
}
