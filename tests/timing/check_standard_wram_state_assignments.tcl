package require ::quartus::project
lassign $quartus(args) output_dir helper
file mkdir $output_dir
cd $output_dir
project_new state_assignment_unit -overwrite
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
source $helper
proc count_owned {} {return [get_collection_size [get_all_instance_assignments -name ALLOW_SYNCH_CTRL_USAGE -tag STANDARD_WRAM_STATE_DATA_ONLY_V1]]}
set_instance_assignment -name ALLOW_SYNCH_CTRL_USAGE ON -to {ic|snes|aram|state[0]} -tag independent_user
set_instance_assignment -name ALLOW_SYNCH_CTRL_USAGE OFF -to {ic|snes|g_standard_sdram.cart_memory|engine|dq_oe} -tag independent_oe
for {set i 0} {$i<100} {incr i} {
 configure_standard_wram_state 1
 if {[count_owned]!=8} {error "standard WRAM state targets missing"}
 configure_standard_wram_state 1
 if {[count_owned]!=8} {error "not idempotent"}
 configure_standard_wram_state 0
 if {[count_owned]!=0} {error "legacy retains standard WRAM controls"}
}
foreach tag {independent_user independent_oe} {if {[get_collection_size [get_all_instance_assignments -name ALLOW_SYNCH_CTRL_USAGE -tag $tag]]!=1} {error "unrelated setting removed: $tag"}}
set_instance_assignment -name ALLOW_SYNCH_CTRL_USAGE ON -to {ic|snes|wram|state[3]} -tag independent_user
if {![catch {configure_standard_wram_state 1} message]} {error "unowned WRAM state control overwritten"}
if {![string match {Existing unowned WRAM state assignment conflicts*} $message]} {error "unexpected conflict failure: $message"}
if {[count_owned]!=0} {error "failed preflight partially changed assignments"}
configure_standard_wram_state 0
if {[get_collection_size [get_all_instance_assignments -name ALLOW_SYNCH_CTRL_USAGE -tag independent_user]]!=2} {error "legacy altered independent controls"}
set_instance_assignment -name ALLOW_SYNCH_CTRL_USAGE ON -to {ic|snes|wram|state[3]} -tag independent_user -remove
set_instance_assignment -name ALLOW_SYNCH_CTRL_USAGE ON -to {ic|snes|wram|state[0]} -tag STANDARD_WRAM_STATE_DATA_ONLY_V1
if {![catch {configure_standard_wram_state 1} message]} {error "edited owned control silently overwritten"}
if {![string match {Unexpected edited WRAM state assignment*} $message]} {error "unexpected owned conflict: $message"}
puts "PASS 100 native standard/legacy WRAM-state toggles; eight exact targets, idempotence, ARAM/OE preservation, both conflict preflights; no map/fit"
project_close
