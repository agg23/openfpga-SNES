/// Util Functions ///

// Seek function
// Input: location - r1
// Clobbers Z
macro seek() {
  seek r1
  jp z, seek_end

  // Failed to seek
  ld r14,#seek_err
  printf r14
  hex.l r1
  exit 1

  seek_end:
}

// Read function
// Input: length - r1
// Input: ouput memory address - r2
// Clobbers Z
macro read() {
  read r2,r1
  jp z, read_end

  // Failed to read
  ld r14,#read_err
  printf r14
  hex.l r1
  exit 1

  read_end:
}

macro align(size) {
  while (pc() % {size}) {
    db 0
  }
}

macro log_string(value) {
  if DEBUG {
    ld r15,#+
    printf r15
    jp ++

    +;
    db {value},0
    align(2)
    +;
  }
}

macro log_hex(value) {
  if DEBUG {
    ld r15,#{value}
    hex.l r15
  }
}

macro log_dec(value) {
  if DEBUG {
    ld r15,#{value}
    dec.l r15
  }
}

/// Messages ///

seek_err:
db "Seek fail 0x",0

read_err:
db "Read fail length 0x",0
