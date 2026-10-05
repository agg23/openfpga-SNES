# Read-only fitted primitive evidence; never mutate atoms or export assignments.
package require ::quartus::project
package require ::quartus::atoms
if {[llength $quartus(args)] != 1} {error "Expected PROJECT_DIR"}
project_open [file join [lindex $quartus(args) 0] snes_pocket.qpf]
read_atom_netlist -type cmp
foreach_in_collection n [get_atom_nodes -matching *PLL_OUTPUT_COUNTER*] {
 puts "ATOM [get_atom_node_info -node $n -key NAME] [get_atom_node_info -node $n -key TYPE] [get_atom_node_info -node $n -key LOCATION]"
 foreach key [get_legal_info_keys -node $n -type ALL] {
  if {[regexp -nocase {cnt|count|duty|phase|prst|div|cascade} $key]} {
   if {[catch {get_atom_node_info -node $n -key $key} val]} {puts "KEY_ERROR $key $val"} else {puts "VALUE $key $val"}
  }
 }
}
project_close -dont_export_assignments
