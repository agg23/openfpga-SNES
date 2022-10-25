architecture chip32.vm
output "loader.bin", create

constant DEBUG = 1

// we will put data into here that we're working on.  It's the last 1K of the 8K chip32 memory
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
ld.b r1,(lorom_output) // Get LoROM score
ld.b r2,(hirom_output) // Get HiROM score
ld.b r3,(exhirom_output) // Get ExHiROM score

cmp r1,r2 // r1 - r2
jp c, check_hirom_score // Jp if hirom >= lorom
cmp r1,r3 // Else lorom >= hirom, so r1 - r3
jp c, check_hirom_score // jp if exhirom >= lorom

// LoROM has the highest core
log_string("Choosing LoROM")
exit 1

check_hirom_score:
cmp r2,r3
jp c, score_exhi // jp if exhirom >= hirom

log_string("Choosing HiROM")
exit 1

score_exhi:
log_string("Choosing ExHiROM")
exit 1

error_handler:
ld r14,#test_err_msg

print:
printf r14
exit 1

test_err_msg:
db "Error",0
align(2)
