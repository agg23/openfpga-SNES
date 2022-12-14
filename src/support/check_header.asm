constant base_address = 0x1900
constant output_address = 0x1904

constant rambuf = 0x1b00 // Starts at 0xZZZBD in ROM
constant header_start_mem = rambuf + 0x3 // Offset to 0xZZZC0

// Address into header/ROM
constant gsu_ramz_addr = rambuf // FBC

constant mapping_mode_addr = header_start_mem + 0x15 // FD5
constant rom_type_addr = header_start_mem + 0x16 // FD6
constant rom_size_addr = header_start_mem + 0x17 // FD7
constant sram_size_addr = header_start_mem + 0x18 // FD8
constant region_addr = header_start_mem + 0x19 // FD9
constant dev_id_addr = header_start_mem + 0x1A // FDA
constant version_number_addr = header_start_mem + 0x1B // FDB
constant checksum_complement_addr = header_start_mem + 0x1C // FDC/D
constant checksum_addr = header_start_mem + 0x1E // FDE/F

// Registers:
// r10: PAL       (stored 3)
// r11: ramsz     (stored 2)
// r12: chip_type (stored 1)
// r13: score     (stored 0)

// Function
// Input: r3 - SMC header status
// Clobbers r1, r2, r3, r10, r11, r12, r13
macro check_header(variable base_address_input, variable output_address_input) {
  ld r1,#base_address_input
  ld r2,#output_address_input

  ld.w r3,(header_offset_addr) // Get header offset
  add r1,r3 // Add offset to base address

  ld.w (base_address),r1 // Store base_address into RAM
  ld.w (output_address),r2 // Store output_address into RAM

  log_string("Starting header at:")
  hex.l r1
  hex.l r3
  call load_header_values_into_mem

  log_string("Loaded header data")

  // Score is stored in r13
  ld r13,#0
  call validate_checksum
  validate_mapping_mode(base_address_input)
  call validate_simple_values
  call choose_ramsz
  call choose_chip_type
  call choose_region

  log_string("Storing header data at:")
  ld.w r1,(output_address)
  hex.w r1

  ld.b (r1),r13 // score
  add r1,#1
  ld.b (r1),r12 // chip_type
  add r1,#1
  ld.b (r1),r11 // ramsz
  add r1,#1
  ld.b (r1),r10 // PAL

  log_string("Finished header. Score:")
  hex.b r13
}

validate_checksum:
  // if (checksum != 0 && checksum_compliment != 0 && checksum + checksum_compliment == 'hFFFF)
  log_string("Checking checksum")
  ld.w r1,(checksum_addr) // Load checksum
  jp z, finish_checksum // If checksum 0, skip

  ld.w r2,(checksum_complement_addr) // Load checksum complement
  jp z, finish_checksum // If complement 0, skip

  add r1,r2 // Add checksum and complement
  cmp r1,#0xFFFF // Compare against 0xFFFF
  jp nz, finish_checksum // If not equal, skip

  // Increment score
  add r13,#4
  log_string("Score checksum +4")

  finish_checksum:
  log_string("Finished checksum")
  ret

macro validate_mapping_mode(variable address) {
  log_string("Checking mapping mode")
  ld.w r1,(mapping_mode_addr)
  and r1,#0xEF // Mask off FastROM set bit

  if (address == 0x7FBD) {
    cmp r1,#0x20 // Compare against mapper 0x20 (LoROM)
    jp nz, noscore{#}
    cmp r1,#0x22 // Compare against mapper 0x22 (SDD1)
    jp nz, noscore{#}
  } else if (address == 0xFFBD) {
    cmp r1,#0x21 // Compare against mapper 0x21 (HiROM)
    jp nz, noscore{#}
  } else if (address == 0x40FFBD) {
    cmp r1,#0x25 // Compare against mapper 0x25 (ExHiROM)
    jp nz, noscore{#}
  }

  add r13,#2 // Add 2 to score
  log_string("Score mapper +2")

  noscore{#}:
  log_string("Finished mapping mode")
}

macro check_simple_value_inequality(variable address, variable less_than, define name) {
  // Check address < less_than
  ld.b r1,(address)
  cmp r1,#less_than // r1 - less_than
  jp nc, end_inequality{#} // If carry set, address < less_than

  add r15,#1
  log_string("Score {name} +1")

  end_inequality{#}:
}

macro check_value_equality(variable address, variable compare) {
  ld.b r1,(address)
  cmp r1,#compare
}

validate_simple_values:
  log_string("Checking simple values")

  // Check dev id is 0x33
  ld.b r1,(dev_id_addr)
  cmp r1,#0x33 // If dev id is 0x33

  jp nz, rom_type
  add r13,#2
  log_string("Score dev_id +2")

  rom_type:
  check_simple_value_inequality(rom_type_addr, 8, rom_type)
  check_simple_value_inequality(rom_size_addr, 16, rom_size)
  check_simple_value_inequality(sram_size_addr, 8, ram_size)
  check_simple_value_inequality(region_addr, 14, region)

  log_string("Finished simple values")
  ret

choose_ramsz:
  log_string("Checking RAMSZ")
  ld.b r11,(sram_size_addr) // ramsz is stored in r11

  ld r1,#8
  cmp r11,r1 // r11 - 8
  jp nc, zero_sram // If r11 >= 8
  jp end_choose_ramsz

  zero_sram:
  ld r11,#0

  end_choose_ramsz:
  log_string("Finished RAMSZ")
  ret

choose_chip_type:
  log_string("Checking chip type")
  ld r12,#0 // chip_type is stored in r12

  // if (mapping_mode == 'h20 && rom_type == 'h03) begin
  log_string("Checking DSP1")
  check_value_equality(mapping_mode_addr, 0x20)
  jp nz, dsp1b
  check_value_equality(rom_type_addr, 0x03)
  jp nz, dsp1b
  // Mapping 0x20, rom_type 0x3 => DSP1
  or r12,#0x84
  jp separate_ifs

  dsp1b: // if (mapping_mode == 'h21 && rom_type == 'h03) begin
  log_string("Checking DSP1B")
  check_value_equality(mapping_mode_addr, 0x21)
  jp nz, dsp1b_2
  check_value_equality(rom_type_addr, 0x03)
  jp nz, dsp1b_2
  // Mapping 0x21, rom_type 0x3 => DSP1B
  or r12,#0x80
  jp separate_ifs

  dsp1b_2: // if (mapping_mode == 'h30 && rom_type == 'h05 && dev_id != 'hB2) begin
  check_value_equality(mapping_mode_addr, 0x30)
  jp nz, dsp1b_3
  check_value_equality(rom_type_addr, 0x05)
  jp nz, dsp1b_3
  check_value_equality(dev_id_addr, 0xB2)
  jp z, dsp1b_3
  // Mapping 0x30, rom_type 0x5, dev_id != 0xB2 => DSP1B
  or r12,#0x80
  jp separate_ifs

  dsp1b_3: // if (mapping_mode == 'h31 && (rom_type == 'h03 || rom_type == 'h05)) begin
  check_value_equality(mapping_mode_addr, 0x31)
  jp nz, dsp2
  check_value_equality(rom_type_addr, 0x03)
  jp z, set_dsp1b_3
  check_value_equality(rom_type_addr, 0x05)
  jp nz, dsp2

  set_dsp1b_3:
  // Mapping 0x31, rom_type 0x3 || 0x5 => DSP1B
  or r12,#0x80
  jp separate_ifs

  dsp2: // if (mapping_mode == 'h20 && rom_type == 'h05) begin
  log_string("Checking DSP2")
  check_value_equality(mapping_mode_addr, 0x20)
  jp nz, dsp3
  check_value_equality(rom_type_addr, 0x05)
  jp nz, dsp3
  // Mapping 0x20, rom_type 0x5 => DSP2
  or r12,#0x90
  jp separate_ifs

  dsp3: // if (mapping_mode == 'h30 && rom_type == 'h05 && dev_id == 'hB2) begin
  log_string("Checking DSP3")
  check_value_equality(mapping_mode_addr, 0x30)
  jp nz, dsp4
  check_value_equality(rom_type_addr, 0x05)
  jp nz, dsp4
  check_value_equality(dev_id_addr, 0xB2)
  jp nz, dsp4
  // Mapping 0x30, rom_type 0x5, dev_id 0xB2 => DSP3
  or r12,#0xA0
  jp separate_ifs

  dsp4: // if (mapping_mode == 'h30 && rom_type == 'h03) begin
  log_string("Checking DSP4")
  check_value_equality(mapping_mode_addr, 0x30)
  jp nz, st010
  check_value_equality(rom_type_addr, 0x03)
  jp nz, st010
  // Mapping 0x30, rom_type 0x3 => DSP4
  or r12,#0xB0
  jp separate_ifs

  st010: // if (mapping_mode == 'h30 && rom_type == 'hF6) begin
  log_string("Checking ST010")
  check_value_equality(mapping_mode_addr, 0x30)
  jp nz, obc1
  check_value_equality(rom_type_addr, 0xF6)
  jp nz, obc1
  // Mapping 0x30, rom_type 0xF6 => ST010
  or r12,#0x88
  ld r11,#1

  // if (rom_size < 10)
  check_value_equality(rom_size_addr, 10)
  jp nc, separate_ifs
  // If rom_size < 10 => ST011
  or r12,#0x20
  jp separate_ifs

  obc1: // if (mapping_mode == 'h30 && rom_type == 'h25) begin
  log_string("Checking OBC1")
  check_value_equality(mapping_mode_addr, 0x30)
  jp nz, separate_ifs
  check_value_equality(rom_type_addr, 0x25)
  jp nz, separate_ifs
  // Mapping 0x30, rom_type 0x25 => OBC1
  or r12,#0xC0

  separate_ifs: // These ifs are standalone (not else if)
  // if (mapping_mode == 'h3A && (rom_type == 'hF5 || rom_type == 'hF9)) begin
  log_string("Checking SPC7110")
  check_value_equality(mapping_mode_addr, 0x3A)
  jp nz, srtc
  check_value_equality(rom_type_addr, 0xF5)
  jp z, set_spc7110
  check_value_equality(rom_type_addr, 0xF9)
  jp nz, srtc
  // Mapping 0x3A, rom_type 0xF5 || 0xF9 => SPC7110

  // Is F9
  or r12,#0x08 // With RTC

  set_spc7110:
  or r12,#0xD0 // SPC7110

  srtc: // if (mapping_mode == 'h35 && rom_type == 'h55) begin
  log_string("Checking S-RTC")
  check_value_equality(mapping_mode_addr, 0x35)
  jp nz, cx4
  check_value_equality(rom_type_addr, 0x55)
  jp nz, cx4
  // Mapping 0x35, rom_type 0x55 => S-RTC (+ExHigh)

  or r12,#0x8

  cx4: // if (mapping_mode == 'h20 && rom_type == 'hF3) begin
  log_string("Checking CX4")
  check_value_equality(mapping_mode_addr, 0x20)
  jp nz, sdd1
  check_value_equality(rom_type_addr, 0xF3)
  jp nz, sdd1
  // Mapping 0x20, rom_type 0xF3 => CX4

  or r12,#0x40

  sdd1: // if (mapping_mode == 'h32 && (rom_type == 'h43 || rom_type == 'h45) && rom_size < 14) begin
  log_string("Checking SDD1")
  check_value_equality(mapping_mode_addr, 0x32)
  jp nz, sa1
  check_value_equality(romsz_addr, 14) // Only mark SDD1 if romsz < 14
  jp nc, sa1
  check_value_equality(rom_type_addr, 0x43)
  jp z, set_sdd1
  check_value_equality(rom_type_addr, 0x45)
  jp nz, sa1
  // Mapping 0x32, rom_type 0x43 || 0x45, rom_size < 14 => SDD1

  set_sdd1:
  or r12,#0x50

  sa1: // if (mapping_mode == 'h23 && (rom_type == 'h32 || rom_type == 'h34 || rom_type == 'h35)) begin
  log_string("Checking SA1")
  check_value_equality(mapping_mode_addr, 0x23)
  jp nz, gsu
  check_value_equality(rom_type_addr, 0x32)
  jp z, set_sa1
  check_value_equality(rom_type_addr, 0x34)
  jp z, set_sa1
  check_value_equality(rom_type_addr, 0x35)
  jp nz, gsu
  // Mapping 0x23, rom_type 0x32 || 0x34 || 0x35 => SA1

  set_sa1:
  or r12,#0x60

  gsu: // if (mapping_mode == 'h20 && (rom_type == 'h13 || rom_type == 'h14 || rom_type == 'h15 || rom_type == 'h1A)) begin
  log_string("Checking GSU")
  check_value_equality(mapping_mode_addr, 0x20)
  jp nz, finished_chip
  check_value_equality(rom_type_addr, 0x13)
  jp z, set_gsu
  check_value_equality(rom_type_addr, 0x14)
  jp z, set_gsu
  check_value_equality(rom_type_addr, 0x15)
  jp z, set_gsu
  check_value_equality(rom_type_addr, 0x1A)
  jp nz, finished_chip
  // Mapping 0x20, rom_type 0x13 || 0x14 || 0x15 || 0x1A => GSU

  set_gsu:
  or r12,#0x70

  ld.b r11,(gsu_ramz_addr) // Load GSU ramsz
  cmp r11,#0xFF // If ramsz == 0xFF
  jp nz, check_6
  ld r11,#5 // Starfox

  check_6:
  ld r1,#6
  cmp r1,r11 // Cmp 6 - r11
  jp nc, finished_chip
  ld r11,#6 // Max out at 6

  finished_chip:
  log_string("Finished chip type, ramsz:")
  hex.b r12
  hex.b r11

  ret

choose_region:
  log_string("Checking region")
  ld r10,#0
  // if ((region >= 'h02 && region <= 'h0C) || region == 'h11) begin
  check_value_equality(region_addr, 0x2)
  jp c, region_11 // If region < 2, jump to region_11

  ld r2,#0xC
  cmp r2,r1
  jp c, region_11 // If region > 0xC, jump to region_11
  jp set_pal // It's PAL

  region_11:
  cmp r1,#0x11 // If region == 0x11
  jp nz, end_region

  set_pal:
  ld r10,#1

  end_region:
  log_string("Finished region:")
  hex.b r10
  ret

// Load all header values from file into memory
load_header_values_into_mem:
  seek()
  ld r1,#0x44 // Load 0x44 bytes
  ld r2,#rambuf // Read into read_space memory
  read()
  ret

// Fetch a header byte value into register
//macro fetch_header_byte(variable address) {
//  ld.b r1,(address)
//}
