architecture chip32.vm
output "loader.bin", create

// we will put data into here that we're working on.  It's the last 1K of the 8K chip32 memory
constant rambuf = 0x1b00

constant dataslot = 0

// Host init command
constant host_init = 0x4002

// Error vector (0x0)
jp error_handler

// Init vector (0x2)
// Choose core
ld r0,#0
core r0

ld r1,#dataslot // populate data slot
open r1,r2
close
and r2,#0x200 // and with 0x200, which implies SMC header
jp z,dont_adjust_for_header // Don't adjust for header if anding was 0

adjust_for_header:
ld r1,#dataslot
ld r2,#0x200 // SMC header offset
adjfo r1,r2

dont_adjust_for_header:
ld r1,#0 // Set address for write
ld r2,#1 // Downloading start
pmpw r1,r2 // Write ioctl_download = 1

ld r1,#dataslot
ld r14,#load_err_msg
loadf r1 // Load ROM
jp nz,print

ld r1,#0 // Set address for write
ld r2,#0 // Downloading end
pmpw r1,r2 // Write ioctl_download = 0

// Start core
ld r0,#host_init
host r0,r0

exit 0

// Error handling
error_handler:
ld r14,#test_err_msg

print:
printf r14
exit 1

test_err_msg:
db "Error",0

load_err_msg:
db "Could not load ROM",0