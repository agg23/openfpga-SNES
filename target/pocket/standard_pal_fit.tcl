# One controlled, versioned PAL placement experiment. The logical design,
# clocks, hold optimization and timing exceptions are untouched.
# Only the reviewed baseline seed=1/Auto Fit can be temporarily replaced.
proc configure_standard_pal_fit {enabled} {
 set tag STANDARD_PAL_FIT_SEED2_V1
 set choices [list [list SEED 1 2] [list FITTER_EFFORT {AUTO FIT} {STANDARD FIT}]]
 set owned 0
 foreach choice $choices {
  lassign $choice name baseline desired
  set count 0
  foreach_in_collection a [get_all_global_assignments -name $name] {
   incr count
   lassign $a section actual_name value entity actual_tag
   if {$actual_tag eq $tag} {
    incr owned
    if {![string equal -nocase $value $desired] || $section ne "" || $entity ne ""} {error "Edited PAL experiment assignment: $name $value"}
   } elseif {$enabled && ($actual_tag ne "" || ![string equal -nocase $value $baseline] || $section ne "" || $entity ne "")} {
    error "Unowned fitter setting conflicts with PAL experiment: $name $value"
   }
  }
  if {$enabled && $count != 1} {error "PAL experiment requires one baseline assignment for $name"}
 }
 if {$owned != 0 && $owned != 2} {error "Incomplete owned PAL fitter settings"}
 if {$enabled} {
  foreach choice $choices {
   lassign $choice name baseline desired
   set_global_assignment -name $name $desired -tag $tag
  }
 } elseif {$owned == 2} {
  foreach choice $choices {
   lassign $choice name baseline desired
   set_global_assignment -name $name $desired -tag $tag -remove
   set_global_assignment -name $name $baseline
  }
 }
}
