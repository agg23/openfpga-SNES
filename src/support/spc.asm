constant ext_addr = 0x1800

check_spc:
ld r1,#0
ld r2,#ext_addr
getext r1,r2
ld r1,#spc_ext
test r1,r2
jp nz, not_spc

// Is SPC
ld r1,#0
core r1

log_string("Booting")
ld r1,#0x14 // Set address for write
ld r2,#1 // Downloading start
pmpw r1,r2 // Write spc_download = 1

ld r3,#rom_dataslot
loadf r3 // Load ROM

ld r2,#0 // Downloading end
pmpw r1,r2 // Write spc_download = 0

// Start core
ld r0,#host_init
host r0,r0

exit 0

not_spc:
ret

spc_ext:
db "SPC",0