# Run with quartus_sh -t generate.tcl

# Load Quartus II Tcl Project package
package require ::quartus::project

# Required for compilation
package require ::quartus::flow

if { $argc != 1 } {
  puts "Exactly 1 argument required"
  exit
}

project_open src/fpga/ap_core.qpf

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

execute_flow -compile

project_close