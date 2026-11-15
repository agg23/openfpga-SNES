# Run with quartus_sh -t generate.tcl

# Load Quartus II Tcl Project package
package require ::quartus::project

# Required for compilation
package require ::quartus::flow

if { $argc != 1 } {
  puts "Exactly 1 argument required"
  exit
}

# Convert the vendored boot1.rom into the MIF boot1_rom.sv loads
proc generate_boot1_mif { rom_path mif_path } {
  set depth 2048

  if { ![file exists $rom_path] } {
    puts "Error: $rom_path not found; cannot generate $mif_path"
    exit 1
  }

  set in [open $rom_path rb]
  set data [read $in]
  close $in

  if { [string length $data] > [expr {2 * $depth}] } {
    puts "Error: $rom_path is larger than [expr {2 * $depth}] bytes"
    exit 1
  }

  binary scan $data cu* bytes
  while { [llength $bytes] < [expr {2 * $depth}] } {
    lappend bytes 0
  }

  set out [open $mif_path w]
  puts $out "-- Generated from $rom_path"
  puts $out ""
  puts $out "WIDTH=16;"
  puts $out "DEPTH=$depth;"
  puts $out ""
  puts $out "ADDRESS_RADIX=HEX;"
  puts $out "DATA_RADIX=HEX;"
  puts $out ""
  puts $out "CONTENT BEGIN"
  for {set i 0} {$i < $depth} {incr i} {
    set lo [lindex $bytes [expr {2 * $i}]]
    set hi [lindex $bytes [expr {2 * $i + 1}]]
    puts $out [format "\t%03X : %04X;" $i [expr {($hi << 8) | $lo}]]
  }
  puts $out "END;"
  close $out
}

generate_boot1_mif "rtl/upstream/releases/boot1.rom" "rtl/mister_top/boot1.mif"

project_open projects/snes_pocket.qpf

if { [lindex $argv 0] == "ntsc" } {
  puts "NTSC"
  set_parameter -name PAL_PLL -entity core_top '0
  set_parameter -name USE_SS -entity core_top '1

  set_parameter -name USE_CX4 -entity MAIN_SNES '0
  set_parameter -name USE_SDD1 -entity MAIN_SNES '0
  set_parameter -name USE_GSU -entity MAIN_SNES '1
  set_parameter -name USE_SA1 -entity MAIN_SNES '0
  set_parameter -name USE_DSPn -entity MAIN_SNES '1
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '0
  set_parameter -name USE_BSX -entity MAIN_SNES '0
  set_parameter -name USE_MSU -entity MAIN_SNES '0
  set_parameter -name USE_SUFAMI -entity MAIN_SNES '0
  set_parameter -name USE_SS -entity MAIN_SNES '1
} elseif { [lindex $argv 0] == "ntsc_sa1cx4" } {
  puts "NTSC SA1 CX4"
  set_parameter -name PAL_PLL -entity core_top '0
  set_parameter -name USE_SS -entity core_top '1

  set_parameter -name USE_CX4 -entity MAIN_SNES '1
  set_parameter -name USE_SDD1 -entity MAIN_SNES '0
  set_parameter -name USE_GSU -entity MAIN_SNES '0
  set_parameter -name USE_SA1 -entity MAIN_SNES '1
  set_parameter -name USE_DSPn -entity MAIN_SNES '0
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '0
  set_parameter -name USE_BSX -entity MAIN_SNES '0
  set_parameter -name USE_MSU -entity MAIN_SNES '0
  set_parameter -name USE_SUFAMI -entity MAIN_SNES '0
  set_parameter -name USE_SS -entity MAIN_SNES '1
} elseif { [lindex $argv 0] == "pal" } {
  puts "PAL"
  set_parameter -name USE_SS -entity core_top '1
  set_parameter -name PAL_PLL -entity core_top '1

  set_parameter -name USE_CX4 -entity MAIN_SNES '0
  set_parameter -name USE_SDD1 -entity MAIN_SNES '0
  set_parameter -name USE_GSU -entity MAIN_SNES '1
  set_parameter -name USE_SA1 -entity MAIN_SNES '0
  set_parameter -name USE_DSPn -entity MAIN_SNES '1
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '0
  set_parameter -name USE_BSX -entity MAIN_SNES '0
  set_parameter -name USE_MSU -entity MAIN_SNES '0
  set_parameter -name USE_SUFAMI -entity MAIN_SNES '0
  set_parameter -name USE_SS -entity MAIN_SNES '1
} elseif { [lindex $argv 0] == "pal_sa1cx4" } {
  puts "PAL SA1 CX4"
  set_parameter -name USE_SS -entity core_top '1
  set_parameter -name PAL_PLL -entity core_top '1

  set_parameter -name USE_CX4 -entity MAIN_SNES '1
  set_parameter -name USE_SDD1 -entity MAIN_SNES '0
  set_parameter -name USE_GSU -entity MAIN_SNES '0
  set_parameter -name USE_SA1 -entity MAIN_SNES '1
  set_parameter -name USE_DSPn -entity MAIN_SNES '0
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '0
  set_parameter -name USE_BSX -entity MAIN_SNES '0
  set_parameter -name USE_MSU -entity MAIN_SNES '0
  set_parameter -name USE_SUFAMI -entity MAIN_SNES '0
  set_parameter -name USE_SS -entity MAIN_SNES '1
} elseif { [lindex $argv 0] == "ntsc_spc" } {
  puts "NTSC SPC"
  set_parameter -name USE_SS -entity core_top '0
  set_parameter -name PAL_PLL -entity core_top '0

  set_parameter -name USE_CX4 -entity MAIN_SNES '0
  set_parameter -name USE_SDD1 -entity MAIN_SNES '1
  set_parameter -name USE_GSU -entity MAIN_SNES '0
  set_parameter -name USE_SA1 -entity MAIN_SNES '0
  set_parameter -name USE_DSPn -entity MAIN_SNES '0
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '1
  set_parameter -name USE_BSX -entity MAIN_SNES '1
  set_parameter -name USE_MSU -entity MAIN_SNES '0
  set_parameter -name USE_SUFAMI -entity MAIN_SNES '0
  set_parameter -name USE_SS -entity MAIN_SNES '0
} elseif { [lindex $argv 0] == "none" } {
  puts "NONE"
  set_parameter -name USE_SS -entity core_top '0
  set_parameter -name PAL_PLL -entity core_top '0

  set_parameter -name USE_CX4 -entity MAIN_SNES '0
  set_parameter -name USE_SDD1 -entity MAIN_SNES '0
  set_parameter -name USE_GSU -entity MAIN_SNES '0
  set_parameter -name USE_SA1 -entity MAIN_SNES '0
  set_parameter -name USE_DSPn -entity MAIN_SNES '0
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '0
  set_parameter -name USE_BSX -entity MAIN_SNES '0
  set_parameter -name USE_MSU -entity MAIN_SNES '0
  set_parameter -name USE_SUFAMI -entity MAIN_SNES '0
  set_parameter -name USE_SS -entity MAIN_SNES '0
} elseif { [lindex $argv 0] == "none_pal" } {
  puts "NONE PAL"
  set_parameter -name USE_SS -entity core_top '0
  set_parameter -name PAL_PLL -entity core_top '1

  set_parameter -name USE_CX4 -entity MAIN_SNES '0
  set_parameter -name USE_SDD1 -entity MAIN_SNES '0
  set_parameter -name USE_GSU -entity MAIN_SNES '0
  set_parameter -name USE_SA1 -entity MAIN_SNES '0
  set_parameter -name USE_DSPn -entity MAIN_SNES '0
  set_parameter -name USE_SPC7110 -entity MAIN_SNES '0
  set_parameter -name USE_BSX -entity MAIN_SNES '0
  set_parameter -name USE_MSU -entity MAIN_SNES '0
  set_parameter -name USE_SUFAMI -entity MAIN_SNES '0
  set_parameter -name USE_SS -entity MAIN_SNES '0
} else {
  puts "Unknown bitstream type [lindex $argv 0]"
  project_close
  exit
}

execute_flow -compile

project_close