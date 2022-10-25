architecture chip32.vm
output "loader.bin", create

constant DEBUG = 1

// we will put data into here that we're working on.  It's the last 1K of the 8K chip32 memory
constant dataslot = 0

// Host init command
constant host_init = 0x4002

// Addresses
constant small_header = 0x007FBD

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

check_header(small_header)

error_handler:
ld r14,#test_err_msg

print:
printf r14
exit 1

test_err_msg:
db "Error",0
align(2)
