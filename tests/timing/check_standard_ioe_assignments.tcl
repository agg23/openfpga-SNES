package require ::quartus::project
lassign $quartus(args) output_dir helper
file mkdir $output_dir
cd $output_dir
project_new io_assignment_unit -overwrite
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
source $helper
proc count_owned {} {
 set count 0
 foreach name {FAST_INPUT_REGISTER FAST_OUTPUT_REGISTER FAST_OUTPUT_ENABLE_REGISTER ALLOW_SYNCH_CTRL_USAGE} {
  foreach_in_collection a [get_all_instance_assignments -name $name -tag STANDARD_SDRAM_IOE_CANDIDATE_V1] {incr count}
 }
 return $count
}
set_instance_assignment -name FAST_INPUT_REGISTER ON -to unrelated_pin -tag independent_user
for {set i 0} {$i<100} {incr i} {
 configure_standard_sdram_ioe 1
 if {[count_owned]!=70} {error "standard packing missing pins"}
 configure_standard_sdram_ioe 1
 if {[count_owned]!=70} {error "not idempotent"}
 configure_standard_sdram_ioe 0
 if {[count_owned]!=0} {error "legacy retains standard assignments"}
}
if {[get_collection_size [get_all_instance_assignments -name FAST_INPUT_REGISTER -tag independent_user]]!=1} {error "unrelated setting removed"}
set_instance_assignment -name FAST_INPUT_REGISTER OFF -to {dram_dq[0]} -tag independent_user
if {![catch {configure_standard_sdram_ioe 1} message]} {error "conflicting user setting was overwritten"}
if {![string match {Existing unowned I/O assignment conflicts*} $message]} {error "unexpected conflict failure: $message"}
if {[count_owned]!=0} {error "failed preflight partially changed assignments"}
configure_standard_sdram_ioe 0
if {[get_collection_size [get_all_instance_assignments -name FAST_INPUT_REGISTER -tag independent_user]]!=2} {error "legacy altered independent settings"}
set_instance_assignment -name FAST_INPUT_REGISTER OFF -to {dram_dq[0]} -tag independent_user -remove
set_instance_assignment -name ALLOW_SYNCH_CTRL_USAGE ON -to {ic|snes|g_standard_sdram.cart_memory|engine|dq_oe} -tag independent_user
if {![catch {configure_standard_sdram_ioe 1} message]} {error "unowned OE synthesis control was overwritten"}
if {[count_owned]!=0} {error "OE conflict partially applied packing"}
configure_standard_sdram_ioe 0
if {[get_collection_size [get_all_instance_assignments -name ALLOW_SYNCH_CTRL_USAGE -tag independent_user]]!=1} {error "legacy cleared unowned OE control"}
puts "PASS 100 native standard/legacy IOE toggles, 69 exact pins + one local OE control, idempotence, unrelated preservation, conflict preflight; no map/fit"
project_close
