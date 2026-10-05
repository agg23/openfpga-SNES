# Run with quartus_sh -t generate.tcl

# Load Quartus II Tcl Project package
package require ::quartus::project

# Required for compilation
package require ::quartus::flow

if { $argc != 1 } {
  puts "Exactly 1 argument required"
  exit 2
}

set generator_root [file dirname [file normalize [info script]]]
set requested_profile [lindex $argv 0]
if {$requested_profile ni {ntsc pal ntsc_spc none none_pal msu_ntsc msu_pal msu_standard_ntsc msu_standard_pal standard_ntsc_spc}} {
  puts "Unknown bitstream type $requested_profile"
  exit 2
}

project_open projects/snes_pocket.qpf
if {[info exists ::env(MSU1_OUTPUT_DIR)]} {
  set_global_assignment -name PROJECT_OUTPUT_DIRECTORY $::env(MSU1_OUTPUT_DIR)
}
set msu_profile [expr {$requested_profile in {msu_ntsc msu_pal msu_standard_ntsc msu_standard_pal}}]
set standard_sdram_profile [expr {$requested_profile in {msu_standard_ntsc msu_standard_pal standard_ntsc_spc}}]
if {$requested_profile in {msu_ntsc msu_standard_ntsc}} {set argv [list ntsc]}
if {$requested_profile in {msu_pal msu_standard_pal}} {set argv [list pal]}
if {$requested_profile eq "standard_ntsc_spc"} {set argv [list ntsc_spc]}
set_parameter -name USE_MSU_POCKET -entity core_top $msu_profile
set_parameter -name USE_STANDARD_SDRAM -entity core_top $standard_sdram_profile
# Apply only the dedicated standard-profile I/O packing candidate; remove its
# exact tagged settings when returning to any legacy profile.
source [file join $generator_root target pocket standard_sdram_ioe.tcl]
configure_standard_sdram_ioe $standard_sdram_profile
# The standard WRAM state transition remains identical; only its local mapped
# synchronous-control implementation is steered. Legacy removes these targets.
source [file join $generator_root target pocket standard_wram_state.tcl]
configure_standard_wram_state $standard_sdram_profile
# A single PAL-only placement experiment, with exact tagged baseline restoration.
source [file join $generator_root target pocket standard_pal_fit.tcl]
configure_standard_pal_fit [expr {$requested_profile eq "msu_standard_pal"}]

if { [lindex $argv 0] == "ntsc" } {
  puts "NTSC"
  set_parameter -name PAL_PLL -entity core_top '0

  set_parameter -name USE_CX4 -entity MAIN_SNES '1
  set_parameter -name USE_SDD1 -entity MAIN_SNES '0
  set_parameter -name USE_GSU -entity MAIN_SNES '1
  set_parameter -name USE_SA1 -entity MAIN_SNES '1
  set_parameter -name USE_DSPn -entity MAIN_SNES '1
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '0
  set_parameter -name USE_BSX -entity MAIN_SNES '0
  set_parameter -name USE_MSU -entity MAIN_SNES '0
} elseif { [lindex $argv 0] == "pal" } {
  puts "PAL"
  set_parameter -name PAL_PLL -entity core_top '1

  set_parameter -name USE_CX4 -entity MAIN_SNES '1
  set_parameter -name USE_SDD1 -entity MAIN_SNES '0
  set_parameter -name USE_GSU -entity MAIN_SNES '1
  set_parameter -name USE_SA1 -entity MAIN_SNES '1
  set_parameter -name USE_DSPn -entity MAIN_SNES '1
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '0
  set_parameter -name USE_BSX -entity MAIN_SNES '0
  set_parameter -name USE_MSU -entity MAIN_SNES '0
} elseif { [lindex $argv 0] == "ntsc_spc" } {
  puts "NTSC SPC"
  set_parameter -name PAL_PLL -entity core_top '0

  set_parameter -name USE_CX4 -entity MAIN_SNES '0
  set_parameter -name USE_SDD1 -entity MAIN_SNES '1
  set_parameter -name USE_GSU -entity MAIN_SNES '0
  set_parameter -name USE_SA1 -entity MAIN_SNES '0
  set_parameter -name USE_DSPn -entity MAIN_SNES '0
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '1
  set_parameter -name USE_BSX -entity MAIN_SNES '1
  set_parameter -name USE_MSU -entity MAIN_SNES '0
} elseif { [lindex $argv 0] == "none" } {
  puts "NONE"
  set_parameter -name PAL_PLL -entity core_top '0

  set_parameter -name USE_CX4 -entity MAIN_SNES '0
  set_parameter -name USE_SDD1 -entity MAIN_SNES '0
  set_parameter -name USE_GSU -entity MAIN_SNES '0
  set_parameter -name USE_SA1 -entity MAIN_SNES '0
  set_parameter -name USE_DSPn -entity MAIN_SNES '0
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '0
  set_parameter -name USE_BSX -entity MAIN_SNES '0
  set_parameter -name USE_MSU -entity MAIN_SNES '0
} elseif { [lindex $argv 0] == "none_pal" } {
  puts "NONE PAL"
  set_parameter -name PAL_PLL -entity core_top '1

  set_parameter -name USE_CX4 -entity MAIN_SNES '0
  set_parameter -name USE_SDD1 -entity MAIN_SNES '0
  set_parameter -name USE_GSU -entity MAIN_SNES '0
  set_parameter -name USE_SA1 -entity MAIN_SNES '0
  set_parameter -name USE_DSPn -entity MAIN_SNES '0
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '0
  set_parameter -name USE_BSX -entity MAIN_SNES '0
  set_parameter -name USE_MSU -entity MAIN_SNES '0
} else {
  puts "Unknown bitstream type [lindex $argv 0]"
  project_close
  exit
}

if {$msu_profile} {
  set_parameter -name USE_MSU -entity MAIN_SNES '1
  # The full SNES feature set leaves very little space. Permit legal LUT/FF
  # co-packing; do not disable coprocessors or relax timing constraints.
  set_global_assignment -name ALM_REGISTER_PACKING_EFFORT HIGH
  # MSU-only area experiment. Preserve all feature parameters and SDC clocks.
  set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE AREA"
  set_global_assignment -name OPTIMIZATION_TECHNIQUE AREA
  set_global_assignment -name MUX_RESTRUCTURE ON
  set_global_assignment -name AUTO_RESOURCE_SHARING ON
  set_global_assignment -name PHYSICAL_SYNTHESIS_COMBO_LOGIC OFF
  set_global_assignment -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION OFF
  set_global_assignment -name NUM_PARALLEL_PROCESSORS 2
} else {
  # Explicitly restore upstream behavior when switching profiles in this DB.
  set_global_assignment -name ALM_REGISTER_PACKING_EFFORT LOW
  set_global_assignment -name OPTIMIZATION_MODE "HIGH PERFORMANCE EFFORT"
  set_global_assignment -name OPTIMIZATION_TECHNIQUE SPEED
  set_global_assignment -name MUX_RESTRUCTURE OFF
  set_global_assignment -name AUTO_RESOURCE_SHARING OFF
  set_global_assignment -name PHYSICAL_SYNTHESIS_COMBO_LOGIC ON
  set_global_assignment -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON
  set_global_assignment -name NUM_PARALLEL_PROCESSORS 4
}
# Optional local resource bound. Defaults above stay unchanged for every profile.
if {[info exists ::env(MSU1_BUILD_JOBS)]} {
  set jobs $::env(MSU1_BUILD_JOBS)
  if {![string is integer -strict $jobs] || $jobs < 1 || $jobs > 64} {
    error "MSU1_BUILD_JOBS must be an integer from 1 to 64"
  }
  set_global_assignment -name NUM_PARALLEL_PROCESSORS $jobs
}
# Clear only this experiment's exact assignment when reusing a generated project.
# New standard-refresh profiles change logic binding and must not inherit it.
set_instance_assignment -name DUPLICATE_ATOM msu_resume_din2_local -remove \
    -from {core_top:ic|MAIN_SNES:snes|main:main|SNES:SNES|DO[2]~6} \
    -to {core_top:ic|MAIN_SNES:snes|main:main|MSU:MSU|resume_loop_index[22]~0}
# Controlled original MSU NTSC fanout experiment. Clone the observed combinational
# command-bit driver for its exact MSU resume-enable consumer. No new register,
# cycle or timing exception; the source and direct destination were atom-checked.
if {$requested_profile eq "msu_ntsc"} {
  source msu_resume_din2_duplicate.qsf
}
execute_flow -compile

project_close
