#!/usr/bin/env python3
"""Build an original SNES/MSU-1 diagnostic without external assembler or assets.

All machine code, 5x7 glyphs, data and tones in this file are original project
material, licensed under the repository's GPL-3.0 license. No Nintendo code,
commercial game, patch, soundtrack, or proprietary SDK is required.

CPU source is the commented build_rom() emitter below. The deliberately small
assembler resolves labels and rejects out-of-range branches and ROM overflow.
Run: python3 tools/msu1_testrom.py --out build/msu1-test
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

ROM_SIZE = 32768
SAMPLE_RATE = 44100
DEFAULT_FRAMES = SAMPLE_RATE * 2
DEFAULT_LOOP_FRAME = SAMPLE_RATE // 2
DATA_SIZE = 8192
DATA_SEED = 0x5A
DATA_STEP = 37

# These are hand-drawn monochrome glyphs, not extracted from a commercial font.
FONT = {
    " ": "00000/00000/00000/00000/00000/00000/00000",
    "0": "01110/10001/10011/10101/11001/10001/01110",
    "1": "00100/01100/00100/00100/00100/00100/01110",
    "2": "01110/10001/00001/00010/00100/01000/11111",
    "3": "11110/00001/00001/01110/00001/00001/11110",
    "4": "00010/00110/01010/10010/11111/00010/00010",
    "5": "11111/10000/10000/11110/00001/00001/11110",
    "6": "01110/10000/10000/11110/10001/10001/01110",
    "7": "11111/00001/00010/00100/01000/01000/01000",
    "8": "01110/10001/10001/01110/10001/10001/01110",
    "9": "01110/10001/10001/01111/00001/00001/01110",
    "A": "01110/10001/10001/11111/10001/10001/10001",
    "B": "11110/10001/10001/11110/10001/10001/11110",
    "C": "01111/10000/10000/10000/10000/10000/01111",
    "D": "11110/10001/10001/10001/10001/10001/11110",
    "E": "11111/10000/10000/11110/10000/10000/11111",
    "F": "11111/10000/10000/11110/10000/10000/10000",
    "G": "01111/10000/10000/10111/10001/10001/01111",
    "H": "10001/10001/10001/11111/10001/10001/10001",
    "I": "01110/00100/00100/00100/00100/00100/01110",
    "J": "00001/00001/00001/00001/10001/10001/01110",
    "K": "10001/10010/10100/11000/10100/10010/10001",
    "L": "10000/10000/10000/10000/10000/10000/11111",
    "M": "10001/11011/10101/10101/10001/10001/10001",
    "N": "10001/11001/10101/10011/10001/10001/10001",
    "O": "01110/10001/10001/10001/10001/10001/01110",
    "P": "11110/10001/10001/11110/10000/10000/10000",
    "Q": "01110/10001/10001/10001/10101/10010/01101",
    "R": "11110/10001/10001/11110/10100/10010/10001",
    "S": "01111/10000/10000/01110/00001/00001/11110",
    "T": "11111/00100/00100/00100/00100/00100/00100",
    "U": "10001/10001/10001/10001/10001/10001/01110",
    "V": "10001/10001/10001/10001/10001/01010/00100",
    "W": "10001/10001/10001/10101/10101/11011/10001",
    "X": "10001/10001/01010/00100/01010/10001/10001",
    "Y": "10001/10001/01010/00100/00100/00100/00100",
    "Z": "11111/00001/00010/00100/01000/10000/11111",
    "/": "00001/00001/00010/00100/01000/10000/10000",
    "-": "00000/00000/00000/11111/00000/00000/00000",
    "=": "00000/00000/11111/00000/11111/00000/00000",
}

# Direct-page state. No SRAM is used. All values below are byte-sized.
STATE = {
    "detected": 0x00, "status": 0x01, "track": 0x02, "control": 0x03,
    "volume": 0x04, "data_byte": 0x05, "data_check": 0x06,
    "expected": 0x07, "remaining": 0x08, "pending_control": 0x09,
    "joy_prev_low": 0x0A, "joy_prev_high": 0x0B,
    "joy_edge_low": 0x0C, "joy_edge_high": 0x0D,
    "temporary": 0x0E, "spc_ready": 0x0F,
}

SCREEN_LINES = {
    2: "POCKET MSU1 SELF TEST",
    4: "DETECTED   00   01=YES",
    5: "STATUS     00",
    6: "TRACK      00",
    7: "DATA BYTE  00",
    8: "PLAYING    00",
    9: "REPEAT     00",
    10: "VOLUME     00",
    11: "MISSING    00",
    12: "DATA CHECK 00",
    13: "SPC READY  00",
    15: "00=WAIT 01=PASS 02=FAIL",
    17: "A PLAY/STOP    B STOP",
    18: "LEFT/RIGHT TRACK 1-3",
    19: "Y REPEAT   UP/DOWN VOLUME",
    20: "X READ 16   START RESEEK",
    22: "TRACK 3 MISSING ON PURPOSE",
    24: "ALL VALUES ARE HEX",
    25: "ORIGINAL CODE DATA AND AUDIO",
}


class Assembler:
    """Minimal, checked 65816 emitter. Its API does not infer CPU width."""

    def __init__(self, origin: int = 0x8000):
        self.origin = origin
        self.data = bytearray()
        self.labels: dict[str, int] = {}
        self.fixups: list[tuple[int, str, str]] = []

    def label(self, name: str) -> None:
        if name in self.labels:
            raise ValueError(f"duplicate label: {name}")
        self.labels[name] = self.origin + len(self.data)

    def emit(self, *values: int) -> None:
        self.data.extend(values)

    def imm8(self, opcode: int, value: int) -> None:
        self.emit(opcode, value)

    def imm16(self, opcode: int, value: int) -> None:
        self.emit(opcode, value & 255, value >> 8)

    def absolute(self, opcode: int, address: int | str) -> None:
        self.emit(opcode)
        if isinstance(address, str):
            self.fixups.append((len(self.data), "absolute", address))
            self.emit(0, 0)
        else:
            self.emit(address & 255, address >> 8)

    def branch(self, opcode: int, target: str) -> None:
        self.emit(opcode)
        self.fixups.append((len(self.data), "relative", target))
        self.emit(0)

    def resolve(self) -> bytes:
        data = bytearray(self.data)
        for offset, kind, target in self.fixups:
            address = self.labels[target]
            if kind == "absolute":
                struct.pack_into("<H", data, offset, address)
            else:
                distance = address - (self.origin + offset + 1)
                if not -128 <= distance <= 127:
                    raise ValueError(f"branch to {target} out of range: {distance}")
                data[offset] = distance & 255
        return bytes(data)


def make_font() -> bytes:
    """128 ASCII-indexed 8x8 tiles in SNES mode-0 2bpp format."""
    output = bytearray(128 * 16)
    for character, bitmap in FONT.items():
        for y, row in enumerate(bitmap.split("/")):
            output[ord(character) * 16 + y * 2] = int(row, 2) << 2
    return bytes(output)


def make_tilemap() -> bytes:
    output = bytearray(32 * 32 * 2)
    for row, line in SCREEN_LINES.items():
        if len(line) > 28:
            raise ValueError(f"line {row} exceeds 28 columns")
        for column, character in enumerate(line, start=2):
            if character not in FONT:
                raise ValueError(f"missing glyph: {character}")
            output[(row * 32 + column) * 2] = ord(character)
    return bytes(output)


def build_rom() -> tuple[bytes, dict[str, int]]:
    """Assemble native-mode 65816 program; return 32 KiB LoROM and symbols.

    Mainline is M=1 (8-bit accumulator), X=0 (16-bit indices), DB=DP=0.
    Accumulator B remains zero after initialization, making TAX safe for the
    byte-to-hex table lookup. NMI/IRQ are disabled; PPU updates happen only in
    polled VBlank. MSU busy waits are serviced across frames, never blocking
    controller/video indefinitely. SPC IPL waits have explicit timeouts.
    """
    a = Assembler()
    def lda(value: int) -> None: a.imm8(0xA9, value)
    def sta(address: int) -> None: a.absolute(0x8D, address)
    def stz(address: int) -> None: a.absolute(0x9C, address)
    def load(name: str) -> None: a.imm8(0xA5, STATE[name])
    def save(name: str) -> None: a.imm8(0x85, STATE[name])
    def zero(name: str) -> None: a.imm8(0x64, STATE[name])
    def jsr(label: str) -> None: a.absolute(0x20, label)
    def jmp(label: str) -> None: a.absolute(0x4C, label)
    def write(address: int, value: int) -> None: lda(value); sta(address)
    def vram(address: int) -> None:
        write(0x2116, address & 255); write(0x2117, address >> 8)
    def check_button(bank: str, mask: int, skip: str) -> None:
        load("joy_edge_" + bank); a.imm8(0x29, mask); a.branch(0xF0, skip)

    a.label("reset")
    a.emit(0x78, 0xD8, 0x18, 0xFB)             # SEI CLD CLC XCE: native mode
    a.imm8(0xC2, 0x30)                         # REP #$30: A/X/Y 16-bit
    a.imm16(0xA2, 0x1FFF); a.emit(0x9A)       # LDX #$1FFF / TXS
    a.imm16(0xA9, 0); a.emit(0x5B)             # LDA #0 / TCD, including B=0
    a.imm8(0xE2, 0x20); a.emit(0x48, 0xAB)    # SEP #$20 / PHA PLB: DB=0
    for register in (0x4200, 0x420B, 0x420C): stz(register)
    write(0x2100, 0x80)                        # Forced blank during setup
    for register in range(0x2101, 0x2134): stz(register)
    for state in STATE: zero(state)

    # Silence the original sound channels and clear SPC DSP mute. Some MSU
    # emulators intentionally honor the DSP mute flag for their mixed output.
    jsr("initialize_spc")

    write(0x2115, 0x80)                        # VRAM increment after high byte
    vram(0)
    a.imm16(0xA2, 0x8000)
    a.label("clear_vram")
    stz(0x2118); stz(0x2119); a.emit(0xCA)     # DEX
    a.branch(0xD0, "clear_vram")

    def copy_vram(label: str, source: str, word_address: int, size: int) -> None:
        vram(word_address); a.imm16(0xA2, 0)
        a.label(label)
        a.absolute(0xBD, source); sta(0x2118); a.emit(0xE8)
        a.absolute(0xBD, source); sta(0x2119); a.emit(0xE8)
        a.imm16(0xE0, size); a.branch(0xD0, label)
    copy_vram("copy_font", "font", 0x0000, 2048)
    copy_vram("copy_map", "tilemap", 0x1000, 2048)
    stz(0x2121)                                # Palette 0: navy, white
    for color_byte in (0x82, 0x1C, 0xFF, 0x7F, 0, 0, 0, 0):
        write(0x2122, color_byte)
    write(0x2107, 0x10)                        # BG1 map at VRAM word $1000
    stz(0x210D); stz(0x210D)
    write(0x210E, 0xFF); write(0x210E, 0xFF)   # Vertical scroll -1
    write(0x212C, 1)                           # BG1 on main screen
    write(0x4200, 1)                           # Auto-joypad; no NMI/IRQ
    lda(1); save("track")
    lda(0x80); save("volume")

    # Require all six signature bytes. A missing MSU must remain bootable and
    # must never receive writes to its apparent I/O range.
    for i, character in enumerate(b"S-MSU1"):
        a.absolute(0xAD, 0x2002 + i); a.imm8(0xC9, character)
        a.branch(0xD0, "detection_done")
    lda(1); save("detected")
    load("volume"); sta(0x2006)
    jsr("select_track"); jsr("seek_data")
    a.label("detection_done")
    write(0x2100, 0x0F)
    a.label("main")
    jsr("wait_frame")
    jsr("render_status")                       # Only VRAM writes in VBlank
    jsr("read_controller")
    load("detected"); a.branch(0xF0, "main_done")
    jsr("handle_buttons")
    jsr("service_msu")
    a.label("main_done"); jmp("main")

    a.label("wait_frame")
    a.label("wait_active")
    a.absolute(0xAD, 0x4212); a.branch(0x30, "wait_active")
    a.label("wait_vblank")
    a.absolute(0xAD, 0x4212); a.branch(0x10, "wait_vblank")
    # Auto-joypad starts just after VBlank begins. Give it time to assert its
    # busy flag, then wait for completion before reading $4218/$4219.
    a.imm16(0xA2, 32)
    a.label("joy_start_delay"); a.emit(0xCA); a.branch(0xD0, "joy_start_delay")
    a.label("wait_joy")
    a.absolute(0xAD, 0x4212); a.imm8(0x29, 1); a.branch(0xD0, "wait_joy")
    a.emit(0x60)

    a.label("read_controller")
    for name, register in (("low", 0x4218), ("high", 0x4219)):
        load("joy_prev_" + name); a.imm8(0x49, 0xFF)  # new & ~old
        a.absolute(0x2D, register); save("joy_edge_" + name)
        a.absolute(0xAD, register); save("joy_prev_" + name)
    a.emit(0x60)

    a.label("handle_buttons")
    check_button("high", 0x01, "no_right")     # RIGHT: next track, 1..3
    load("track"); a.emit(0x1A); a.imm8(0xC9, 4)
    a.branch(0xD0, "right_valid"); lda(1)
    a.label("right_valid"); save("track"); jsr("select_track")
    a.label("no_right")
    check_button("high", 0x02, "no_left")
    load("track"); a.emit(0x3A); a.branch(0xD0, "left_valid"); lda(3)
    a.label("left_valid"); save("track"); jsr("select_track")
    a.label("no_left")
    check_button("low", 0x80, "no_a")          # A toggles actual playing
    a.absolute(0xAD, 0x2000); a.imm8(0x29, 0x10)
    a.branch(0xF0, "a_start")
    load("control"); a.imm8(0x29, 2); a.branch(0x80, "a_store")
    a.label("a_start"); load("control"); a.imm8(0x09, 1)
    a.label("a_store"); save("control"); lda(1); save("pending_control")
    a.label("no_a")
    check_button("high", 0x80, "no_b")         # B always stops
    load("control"); a.imm8(0x29, 2); save("control")
    lda(1); save("pending_control")
    a.label("no_b")
    check_button("high", 0x40, "no_y")         # Y toggles repeat
    load("control"); a.imm8(0x49, 2); a.imm8(0x29, 2); save("temporary")
    a.absolute(0xAD, 0x2000)
    for _ in range(4): a.emit(0x4A)
    a.imm8(0x29, 1); a.imm8(0x05, STATE["temporary"]); save("control")
    lda(1); save("pending_control")
    a.label("no_y")
    check_button("high", 0x08, "no_up")        # UP: saturating +$10
    load("volume"); a.emit(0x18); a.imm8(0x69, 0x10)
    a.branch(0x90, "up_valid"); lda(0xFF)
    a.label("up_valid"); save("volume"); sta(0x2006)
    a.label("no_up")
    check_button("high", 0x04, "no_down")      # DOWN: saturating -$10
    load("volume"); a.emit(0x38); a.imm8(0xE9, 0x10)
    a.branch(0xB0, "down_valid"); lda(0)
    a.label("down_valid"); save("volume"); sta(0x2006)
    a.label("no_down")
    check_button("low", 0x40, "no_x")          # X: next 16 bytes, no seek
    load("remaining"); a.branch(0xD0, "no_x")
    lda(16); save("remaining"); zero("data_check")
    a.label("no_x")
    check_button("high", 0x10, "no_start")     # START: restart from offset 0
    jsr("seek_data")
    a.label("no_start"); a.emit(0x60)

    a.label("select_track")
    load("track"); sta(0x2004); stz(0x2005)    # High byte commits selection
    load("control"); a.imm8(0x29, 2); save("control")
    lda(1); save("pending_control"); a.emit(0x60)

    a.label("seek_data")
    for address in range(0x2000, 0x2004): stz(address)
    lda(DATA_SEED); save("expected")
    lda(16); save("remaining"); zero("data_check"); a.emit(0x60)

    a.label("service_msu")
    a.absolute(0xAD, 0x2000); save("status")
    a.imm8(0x29, 0x40); a.branch(0xD0, "audio_busy")
    load("pending_control"); a.branch(0xF0, "audio_busy")
    load("control"); sta(0x2007); zero("pending_control")
    a.label("audio_busy")
    a.label("read_data_loop")
    load("remaining"); a.branch(0xF0, "service_done")
    a.absolute(0xAD, 0x2000); a.imm8(0x29, 0x80)
    a.branch(0xD0, "service_done")
    a.absolute(0xAD, 0x2001); save("data_byte")
    a.imm8(0xC5, STATE["expected"]); a.branch(0xF0, "data_matches")
    lda(2); save("data_check")
    a.label("data_matches")
    load("expected"); a.emit(0x18); a.imm8(0x69, DATA_STEP); save("expected")
    a.imm8(0xC6, STATE["remaining"]); a.branch(0xD0, "read_data_loop")
    load("data_check"); a.imm8(0xC9, 2); a.branch(0xF0, "service_done")
    lda(1); save("data_check")
    a.label("service_done")
    a.absolute(0xAD, 0x2000); save("status"); a.emit(0x60)

    a.label("render_status")
    # Each output is two hexadecimal digits at text-column 11, screen-column 13.
    fields = [(4, "detected", 0), (5, "status", 0), (6, "track", 0),
              (7, "data_byte", 0), (8, "status", 4), (9, "status", 5),
              (10, "volume", 0), (11, "status", 3),
              (12, "data_check", 0), (13, "spc_ready", 0)]
    for row, field, shift in fields:
        vram(0x1000 + row * 32 + 13); load(field)
        if shift:
            for _ in range(shift): a.emit(0x4A)  # LSR A
            a.imm8(0x29, 1)
        jsr("print_hex")
    a.emit(0x60)
    a.label("print_hex")
    a.emit(0xDA); save("temporary")             # PHX, retain original byte
    for _ in range(4): a.emit(0x4A)
    a.emit(0xAA); a.absolute(0xBD, "hex_digits"); sta(0x2118); stz(0x2119)
    load("temporary"); a.imm8(0x29, 15); a.emit(0xAA)
    a.absolute(0xBD, "hex_digits"); sta(0x2118); stz(0x2119)
    a.emit(0xFA, 0x60)                          # PLX RTS

    a.label("initialize_spc")
    # Original SPC700 code at $0200: KOFF=$FF, FLG=$20, then BRA forever.
    # FLG $20 disables echo writes while clearing reset and mute. IPL is the
    # console's own boot ROM; no IPL bytes are copied into this cartridge.
    spc_program = bytes((0x8F, 0x5C, 0xF2, 0x8F, 0xFF, 0xF3,
                         0x8F, 0x6C, 0xF2, 0x8F, 0x20, 0xF3, 0x2F, 0xFE))
    def spc_wait(value: int, label: str, address: int = 0x2140) -> None:
        a.imm16(0xA2, 0xFFFF); a.label(label)
        a.absolute(0xAD, address); a.imm8(0xC9, value)
        a.branch(0xF0, label + "_ok")
        a.emit(0xCA); a.branch(0xD0, label)
        a.emit(0x60)                           # Timeout: return; SPC READY=0
        a.label(label + "_ok")
    spc_wait(0xAA, "spc_wait_aa")
    spc_wait(0xBB, "spc_wait_bb", 0x2141)
    stz(0x2142); write(0x2143, 2)
    write(0x2141, 1); write(0x2140, 0xCC)
    spc_wait(0xCC, "spc_wait_cc")
    for index, byte in enumerate(spc_program):
        write(0x2141, byte); write(0x2140, index)
        spc_wait(index, f"spc_byte_{index}")
    stz(0x2141); stz(0x2142); write(0x2143, 2)
    write(0x2140, len(spc_program) + 1)         # Last counter + 2: execute
    spc_wait(len(spc_program) + 1, "spc_execute")
    lda(1); save("spc_ready"); a.emit(0x60)
    a.label("interrupt"); a.emit(0x40)         # RTI: defensive unused vectors
    a.label("hex_digits"); a.data.extend(b"0123456789ABCDEF")
    a.label("font"); a.data.extend(make_font())
    a.label("tilemap"); a.data.extend(make_tilemap())
    payload = a.resolve()
    if len(payload) > 0x7FC0:
        raise ValueError("program overlaps SNES header")
    rom = bytearray(b"\xFF" * ROM_SIZE)
    rom[:len(payload)] = payload
    rom[0x7FC0:0x7FD5] = b"POCKET MSU1 SELF TEST"
    rom[0x7FD5:0x7FDC] = bytes((0x20, 0, 5, 0, 1, 0, 0))
    struct.pack_into("<HH", rom, 0x7FDC, 0xFFFF, 0)
    for offset in range(0x7FE0, 0x8000, 2):
        struct.pack_into("<H", rom, offset, a.labels["interrupt"])
    struct.pack_into("<H", rom, 0x7FFC, a.labels["reset"])
    checksum = sum(rom) & 0xFFFF
    struct.pack_into("<HH", rom, 0x7FDC, checksum ^ 0xFFFF, checksum)
    assert len(rom) == ROM_SIZE and (sum(rom) & 0xFFFF) == checksum
    return bytes(rom), a.labels


def make_data(size: int = DATA_SIZE) -> bytes:
    """File byte i is (0x5A + 37*i) modulo 256; no .msu header is required."""
    if size < 0:
        raise ValueError("data size must be nonnegative")
    return bytes((DATA_SEED + i * DATA_STEP) & 255 for i in range(size))


def make_pcm(track: int, frames: int = DEFAULT_FRAMES,
             loop_frame: int = DEFAULT_LOOP_FRAME) -> bytes:
    """MSU1 header + signed 16-bit little-endian stereo, 44.1 kHz.

    Loop offset is a STEREO FRAME count after the 8-byte header, never a byte
    offset. Integer-only triangle synthesis produces byte-identical files.
    The intro uses half the loop's frequencies, making loop behavior audible.
    """
    if track not in (1, 2):
        raise ValueError("only original synthetic tracks 1 and 2 are defined")
    if frames <= 0 or not 0 <= loop_frame < frames:
        raise ValueError("loop frame must be within the audio payload")
    frequencies = {1: (440, 660), 2: (330, 550)}[track]
    result = bytearray(b"MSU1" + struct.pack("<I", loop_frame))
    def sample(frame: int, frequency: int) -> int:
        phase = (frame * frequency) % SAMPLE_RATE
        ramp = phase if phase <= SAMPLE_RATE // 2 else SAMPLE_RATE - phase
        return ramp * (4 * 4096) // SAMPLE_RATE - 4096
    for frame in range(frames):
        intro = frame < loop_frame
        position = frame if intro else frame - loop_frame
        left, right = (f // 2 if intro else f for f in frequencies)
        result.extend(struct.pack("<hh", sample(position, left), sample(position, right)))
    return bytes(result)


def write_assets(output: Path, basename: str = "MSU Test") -> dict:
    if not basename or basename in (".", "..") or re.search(r"[/\\\x00-\x1f]", basename):
        raise ValueError("basename must be a single nonempty filename stem")
    output.mkdir(parents=True, exist_ok=True)
    rom, symbols = build_rom()
    assets = {f"{basename}.sfc": rom, f"{basename}.msu": make_data(),
              f"{basename}-1.pcm": make_pcm(1), f"{basename}-2.pcm": make_pcm(2)}
    manifest = {"format": "pocket-msu1-self-test-v1", "basename": basename,
                "sample_rate": SAMPLE_RATE, "channels": 2, "sample_bits": 16,
                "frames_per_track": DEFAULT_FRAMES, "loop_frame": DEFAULT_LOOP_FRAME,
                "data_formula": "(0x5A + 37 * offset) & 0xFF",
                "intentionally_missing_track": 3, "hardware_tested": False,
                "files": {}}
    for filename, content in assets.items():
        (output / filename).write_bytes(content)
        manifest["files"][filename] = {"size": len(content),
                                       "sha256": hashlib.sha256(content).hexdigest()}
    (output / f"{basename}.manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (output / f"{basename}.symbols.json").write_text(
        json.dumps(symbols, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("build/msu1-test"))
    parser.add_argument("--basename", default="MSU Test")
    args = parser.parse_args()
    try:
        manifest = write_assets(args.out, args.basename)
    except ValueError as error:
        parser.error(str(error))
    for filename, info in manifest["files"].items():
        print(f"{args.out / filename}: {info['size']} bytes, sha256 {info['sha256']}")
    print("Generated original diagnostic assets. Hardware execution is NOT TESTED.")


if __name__ == "__main__":
    main()
