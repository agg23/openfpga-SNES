architecture chip32.vm
output "loader.bin", create

constant DEBUG = 1

constant dataslot = 0

// Host init command
constant host_init = 0x4002

// Addresses
constant rom_file_size = 0x1000

constant lorom_header_seek = 0x007FBD
constant hirom_header_seek = 0x00FFBD
constant exhirom_header_seek = 0x40FFBD

constant lorom_output = 0x1A00
constant hirom_output = 0x1A10
constant exhirom_output = 0x1A20

constant romsz_addr = 0x1900

// Error vector (0x0)
jp error_handler

// Init vector (0x2)
jp start

/// Includes ///
include "util.asm"
align(2)

include "check_header.asm"
align(2)

start:
ld r1,#dataslot // populate data slot
open r1,r2

ld.l (rom_file_size),r2

check_header(lorom_header_seek, lorom_output)

// Check headers at 0xFFBD
ld.l r2,(rom_file_size)
cmp r2,#0xFFFF
jp c, finished_checking_headers // If ROM is smaller than 0xFFFF
check_header(hirom_header_seek, hirom_output)

// Check headers at 0x40FFBD
ld.l r2,(rom_file_size)
ld r3,#0x40
asl r3,#16 // Shift left 16 times
or r3,#0xFFFF // We now have 0x40FFFF in r3
cmp r2,r3
jp c, finished_checking_headers // If ROM is smaller than 0x40FFFF

check_header(exhirom_header_seek, exhirom_output)

// All headers checked, compare scores
finished_checking_headers:
close // Close file since we won't be seeking anymore
// Calculate romsz
ld r1,#15
ld r2,#0x1000000 // Max ROM size
ld.l r3,(rom_file_size) // ROM file size

rom_size_loop:
cmp r2,r3
jp c, finished_rom_size // If size > r2
asl r3,#1 // Else shift size left 1
sub r1,#1 // Subtract 1 from rom size
jp rom_size_loop

finished_rom_size:
log_string("Calculated ROM size:")
hex.b r1

ld.b (romsz_addr),r1

ld.b r1,(lorom_output) // Get LoROM score
ld.b r2,(hirom_output) // Get HiROM score
ld.b r3,(exhirom_output) // Get ExHiROM score

cmp r1,r2 // r1 - r2
jp c, check_hirom_score // Jp if hirom >= lorom
cmp r1,r3 // Else lorom >= hirom, so r1 - r3
jp c, check_hirom_score // jp if exhirom >= lorom

// LoROM has the highest core
log_string("Choosing LoROM")
ld.b r1,(lorom_output + 1) // Get LoROM chip type
ld.b r2,(lorom_output + 2) // Get RAMSZ
ld.b r3,(lorom_output + 3) // Get PAL
jp set_core

check_hirom_score:
cmp r2,r3
jp c, score_exhi // jp if exhirom >= hirom

log_string("Choosing HiROM")
ld.b r1,(hirom_output + 1) // Get HiROM chip type
or r1,#1 // OR 1 to chip_type to mark HiROM
ld.b r2,(hirom_output + 2) // Get RAMSZ
ld.b r3,(hirom_output + 3) // Get PAL

jp set_core

score_exhi:
log_string("Choosing ExHiROM")
ld.b r1,(exhirom_output + 1) // Get ExHiROM chip type
or r1,#2 // OR 2 to chip_type to mark ExHiROM
ld.b r2,(exhirom_output + 2) // Get RAMSZ
ld.b r3,(exhirom_output + 3) // Get PAL

// Set core
set_core:
log_string("Setting core")
and r1,#0xF0 // Get only the high nibble

ld r8,#0
core r8 // Default to the main core

cmp r1,#0xD0 // Check if SPC7110
jp nz, bit_sdd1
log_string("Using SPC7110")
jp expansion_core // It's SPC7110

bit_sdd1:
cmp r1,#0x50 // Check if SDD1
jp nz, bit_bsx
log_string("Using SDD1")
jp expansion_core // It's SDD1

bit_bsx:
cmp r1,#0x30 // Check if BSX
jp nz, send_chip
log_string("Using BSX")
// It's BSX

expansion_core:
ld r8,#1
core r8 // Boot SPC7110/SDD1/BSX core

send_chip:
log_string("Sending chip type")
ld r8,#8
pmpw r8,r1

log_string("Sending ROM size")
ld.b r7,(romsz_addr)
ld r8,#4 // Load address of ROM size
pmpw r8,r7 // Send ROM size to FPGA

log_string("Sending RAMSZ")
ld r8,#0xC
pmpw r8,r2

log_string("Sending PAL")
ld r8,#0x10
pmpw r8,r3

log_string("Booting")
ld r1,#0 // Set address for write
ld r2,#1 // Downloading start
pmpw r1,r2 // Write ioctl_download = 1

ld r1,#dataslot
loadf r1 // Load ROM

ld r1,#0 // Set address for write
ld r2,#0 // Downloading end
pmpw r1,r2 // Write ioctl_download = 0

// Start core
ld r0,#host_init
host r0,r0

exit 0

error_handler:
ld r14,#test_err_msg

print:
printf r14
exit 1

test_err_msg:
db "Error",0
align(2)
