package require ::quartus::project
set root [file normalize [lindex $quartus(args) 0]]
set out [file normalize [lindex $quartus(args) 1]]
file mkdir $out
project_new [file join $out unit] -overwrite
set_global_assignment -name FAMILY {Cyclone V}
set_global_assignment -name DEVICE 5CEBA4F23C8
source [file join $root target pocket standard_pal_fit.tcl]
set checks 0
proc check {condition name} {
 global checks
 if {![uplevel 1 [list expr $condition]]} {error "FAIL $name"}
 incr checks
}
proc settings {} {
 set result {}
 foreach name {SEED FITTER_EFFORT NUM_PARALLEL_PROCESSORS} {
  foreach_in_collection a [get_all_global_assignments -name $name] {lappend result $a}
 }
 return [lsort $result]
}
proc baseline {} {
 foreach name {SEED FITTER_EFFORT} {
  foreach_in_collection a [get_all_global_assignments -name $name] {
   lassign $a section actual_name value entity tag
   if {$tag eq ""} {set_global_assignment -name $name $value -remove} else {set_global_assignment -name $name $value -tag $tag -remove}
  }
 }
 set_global_assignment -name SEED 1
 set_global_assignment -name FITTER_EFFORT {AUTO FIT}
}
proc rejects {enabled label} {
 set before [settings]
 set code [catch {configure_standard_pal_fit $enabled} result]
 check {$code == 1} "$label rejected"
 check {[settings] eq $before} "$label preserves assignments"
 puts "PASS NEGATIVE $label: $result"
}
baseline
set_global_assignment -name NUM_PARALLEL_PROCESSORS 3
set original [settings]
for {set i 0} {$i < 100} {incr i} {
 configure_standard_pal_fit 1
 check {[get_global_assignment -name SEED] eq "2"} "seed2 $i"
 check {[get_global_assignment -name FITTER_EFFORT] eq "STANDARD FIT"} "standard effort $i"
 configure_standard_pal_fit 1
 check {[get_collection_size [get_all_global_assignments -name SEED]] == 1} "idempotent seed $i"
 configure_standard_pal_fit 0
 check {[settings] eq $original} "exact restore $i"
}
set_global_assignment -name SEED 7
rejects 1 custom_seed
configure_standard_pal_fit 0
check {[get_global_assignment -name SEED] eq "7"} "unowned custom seed retained inactive"
baseline
set_global_assignment -name FITTER_EFFORT {FAST FIT}
rejects 1 custom_effort
baseline
set_global_assignment -name SEED 1 -tag USER_SETTING
rejects 1 unowned_same_value_tag
baseline
configure_standard_pal_fit 1
set_global_assignment -name SEED 7 -tag STANDARD_PAL_FIT_SEED2_V1
rejects 0 edited_owned_seed
rejects 1 edited_owned_seed_active
baseline
set_global_assignment -name SEED 2 -tag STANDARD_PAL_FIT_SEED2_V1
rejects 0 partial_owned_inactive
rejects 1 partial_owned_active
baseline
set_global_assignment -name SEED 1 -remove
rejects 1 missing_baseline_seed
baseline
check {[settings] eq $original} "final baseline"
export_assignments
project_close
puts "PASS PAL FIT ASSIGNMENTS checks=$checks"
