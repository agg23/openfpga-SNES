#!/usr/bin/env python3
"""Original standalone LoROM battery-SRAM smoke test and read-only save checker.

SPDX-License-Identifier: GPL-3.0-or-later
No external assembler, game, music, MSU assets or third-party ROM is used.
This tool is deliberately independent of tools/msu1_testrom.py and its manifest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

ROM_SIZE = 32768
SRAM_SIZE = 2048
BASENAME = "Pocket Standard Save Test"
MAGIC = b"POCKET-SRAM-v1!!"
COUNTER_OFFSET = len(MAGIC)
COMPLEMENT_OFFSET = COUNTER_OFFSET + 1
FORMAT = "pocket-standard-save-test-v1"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def save_image(counter: int) -> bytes:
    """Address-dependent original pattern, with version magic and count pair."""
    if not 0 <= counter <= 255:
        raise ValueError("counter must be an unsigned 8-bit value")
    data = bytearray(((i * 73) ^ (i >> 8) ^ 0xA7) & 255 for i in range(SRAM_SIZE))
    data[:len(MAGIC)] = MAGIC
    data[COUNTER_OFFSET] = counter
    data[COMPLEMENT_OFFSET] = counter ^ 255
    return bytes(data)


class Emitter:
    """Tiny explicit-width 65816 emitter with bounded branch fixups."""
    def __init__(self):
        self.code = bytearray()
        self.labels: dict[str, int] = {}
        self.fixups: list[tuple[int, str, str]] = []

    def label(self, name: str) -> None:
        if name in self.labels:
            raise ValueError(f"duplicate label: {name}")
        self.labels[name] = 0x8000 + len(self.code)

    def emit(self, *data: int) -> None:
        self.code.extend(data)

    def imm16(self, opcode: int, value: int) -> None:
        self.emit(opcode, value & 255, value >> 8)

    def absolute(self, opcode: int, target: int | str) -> None:
        self.emit(opcode)
        if isinstance(target, str):
            self.fixups.append((len(self.code), "absolute", target))
            self.emit(0, 0)
        else:
            self.emit(target & 255, target >> 8)

    def long(self, opcode: int, target: int) -> None:
        self.emit(opcode, target & 255, (target >> 8) & 255, target >> 16)

    def branch(self, opcode: int, target: str) -> None:
        self.emit(opcode)
        self.fixups.append((len(self.code), "relative", target))
        self.emit(0)

    def resolve(self) -> bytes:
        data = bytearray(self.code)
        for offset, kind, name in self.fixups:
            target = self.labels[name]
            if kind == "absolute":
                struct.pack_into("<H", data, offset, target)
            else:
                displacement = target - (0x8000 + offset + 1)
                if not -128 <= displacement <= 127:
                    raise ValueError(f"branch out of range: {name}")
                data[offset] = displacement & 255
        return bytes(data)


def build_rom() -> tuple[bytes, dict[str, int]]:
    """Native A8/X16/DB0 program. All SRAM accesses use $70:0000-$70:07FF.

    Only an entirely erased FF image is initialized. A nonblank image is fully
    compared before either count byte is written. Damage never triggers repair.
    The saved counter is modulo 256; 255 -> 0 is intentional.
    """
    a = Emitter()
    def write(address: int, value: int) -> None:
        a.emit(0xA9, value)                    # LDA #imm8
        a.absolute(0x8D, address)             # STA abs
    def jump(name: str) -> None:
        a.absolute(0x4C, name)
    def color(name: str, value: int) -> None:
        a.label(name)
        a.absolute(0x9C, 0x2121)              # palette index 0
        write(0x2122, value & 255)
        write(0x2122, value >> 8)
        write(0x2100, 0x0F)                   # unblank only after result
        jump("idle")

    a.label("reset")
    a.emit(0x78, 0xD8, 0x18, 0xFB)            # SEI CLD CLC XCE
    a.emit(0xC2, 0x30)                        # 16-bit A/X/Y
    a.imm16(0xA2, 0x1FFF); a.emit(0x9A)      # known WRAM stack
    a.imm16(0xA9, 0); a.emit(0x5B)            # DP = 0, hidden B = 0
    a.emit(0xE2, 0x20, 0x48, 0xAB)            # A8; PHA PLB => DB = 0
    for register in (0x4200, 0x420B, 0x420C):
        a.absolute(0x9C, register)            # no IRQ/NMI/autojoy/DMA/HDMA
    write(0x2100, 0x80)                       # force blank
    for register in range(0x2101, 0x2134):
        a.absolute(0x9C, register)            # no layers/color math/windows

    a.imm16(0xA2, 0)
    a.label("blank_scan")
    a.long(0xBF, 0x700000)                    # LDA long,X
    a.emit(0xC9, 0xFF)                        # CMP #$FF
    a.branch(0xD0, "validate")
    a.emit(0xE8); a.imm16(0xE0, SRAM_SIZE)    # INX; CPX #$0800
    a.branch(0xD0, "blank_scan")

    a.imm16(0xA2, 0)
    a.label("initialize")
    a.absolute(0xBD, "template")             # LDA template,X
    a.long(0x9F, 0x700000)                    # STA long,X
    a.emit(0xE8); a.imm16(0xE0, SRAM_SIZE)
    a.branch(0xD0, "initialize")
    jump("cold_blue")

    a.label("validate")
    a.imm16(0xA2, 0)
    a.label("compare")
    a.imm16(0xE0, COUNTER_OFFSET)
    a.branch(0xF0, "skip_counter_pair")
    a.long(0xBF, 0x700000)
    a.absolute(0xDD, "template")             # CMP template,X
    a.branch(0xD0, "corrupt_red")
    a.emit(0xE8); a.imm16(0xE0, SRAM_SIZE)
    a.branch(0xD0, "compare")
    jump("validate_counter")
    a.label("skip_counter_pair")
    a.emit(0xE8, 0xE8)                        # skip count and its complement
    jump("compare")
    a.label("validate_counter")
    a.long(0xAF, 0x700000 + COUNTER_OFFSET)
    a.emit(0x49, 0xFF)                        # EOR #$FF
    a.long(0xCF, 0x700000 + COMPLEMENT_OFFSET)
    a.branch(0xD0, "corrupt_red")
    a.emit(0x49, 0xFF, 0x18, 0x69, 0x01)      # undo EOR; CLC; ADC #1
    a.long(0x8F, 0x700000 + COUNTER_OFFSET)
    a.emit(0x49, 0xFF)
    a.long(0x8F, 0x700000 + COMPLEMENT_OFFSET)
    jump("restored_green")

    color("corrupt_red", 0x001F)
    color("cold_blue", 0x7C00)
    color("restored_green", 0x03E0)
    a.label("idle"); jump("idle")
    a.label("interrupt"); a.emit(0x40)        # RTI, interrupts kept disabled
    a.label("template"); a.code.extend(save_image(1))
    code = a.resolve()
    if len(code) > 0x7FC0:
        raise ValueError("program overlaps LoROM header")
    rom = bytearray([0xEA] * ROM_SIZE)
    rom[:len(code)] = code
    rom[0x7FC0:0x7FD5] = b"POCKET STANDARD SAVE ".ljust(21, b" ")
    # Slow LoROM; ROM+RAM+battery; 32KiB ROM; 2KiB SRAM; NTSC; no maker; v1.
    rom[0x7FD5:0x7FDC] = bytes((0x20, 0x02, 0x05, 0x01, 0x01, 0x00, 0x00))
    # Clear reserved/vector words, then install documented native/emulation vectors.
    rom[0x7FE0:0x8000] = bytes(32)
    for offset in (0x7FE4, 0x7FE6, 0x7FE8, 0x7FEA, 0x7FEE,
                   0x7FF4, 0x7FF8, 0x7FFA, 0x7FFE):
        struct.pack_into("<H", rom, offset, a.labels["interrupt"])
    struct.pack_into("<H", rom, 0x7FFC, a.labels["reset"])
    rom[0x7FDC:0x7FE0] = bytes((0xFF, 0xFF, 0x00, 0x00))
    checksum = sum(rom) & 0xFFFF
    struct.pack_into("<HH", rom, 0x7FDC, checksum ^ 0xFFFF, checksum)
    validate_rom(bytes(rom))
    return bytes(rom), a.labels


def validate_rom(rom: bytes) -> dict:
    if len(rom) != ROM_SIZE:
        raise ValueError(f"ROM must be exactly {ROM_SIZE} bytes")
    if rom[0x7FD5:0x7FD9] != bytes((0x20, 0x02, 0x05, 0x01)):
        raise ValueError("expected slow LoROM / battery SRAM / 32KiB / 2KiB header")
    complement, checksum = struct.unpack_from("<HH", rom, 0x7FDC)
    if complement ^ checksum != 0xFFFF or sum(rom) & 0xFFFF != checksum:
        raise ValueError("invalid SNES checksum/complement")
    if struct.unpack_from("<H", rom, 0x7FFC)[0] != 0x8000:
        raise ValueError("unexpected reset vector")
    return {"bytes": len(rom), "sha256": sha256(rom), "checksum": f"{checksum:04x}",
            "mapper": "slow LoROM (0x20)", "cartridge_type": "ROM+RAM+battery (0x02)",
            "rom_size_header": 5, "sram_size_header": 1, "sram_bytes": SRAM_SIZE}


def check_save(data: bytes, expected_counter: int | None = None,
               expected_sha256: str | None = None) -> dict:
    if len(data) != SRAM_SIZE:
        raise ValueError(f"save must be exactly {SRAM_SIZE} raw bytes; got {len(data)} (no padding/header accepted)")
    if data[:len(MAGIC)] != MAGIC:
        raise ValueError("save magic/version mismatch (blank or another game's save is not accepted)")
    counter = data[COUNTER_OFFSET]
    if data[COMPLEMENT_OFFSET] != counter ^ 255:
        raise ValueError("counter complement mismatch")
    expected = save_image(counter)
    for offset, (actual, wanted) in enumerate(zip(data, expected)):
        if actual != wanted:
            raise ValueError(f"pattern mismatch at 0x{offset:04X}: got 0x{actual:02X}, expected 0x{wanted:02X}")
    if expected_counter is not None and counter != expected_counter:
        raise ValueError(f"counter mismatch: got {counter}, expected {expected_counter}")
    digest = sha256(data)
    if expected_sha256 is not None and digest != expected_sha256.lower():
        raise ValueError(f"SHA-256 mismatch: got {digest}, expected {expected_sha256.lower()}")
    return {"format": FORMAT, "bytes": len(data), "magic_hex": MAGIC.hex(), "counter": counter,
            "counter_complement": data[COMPLEMENT_OFFSET], "pattern_verified": True,
            "sha256": digest, "hardware_verified": False,
            "scope": "read-only supplied bytes; provenance/device not attested"}


def write_assets(output: Path) -> dict:
    # Fresh-directory-only, so this cannot replace a game or a save by accident.
    output.mkdir(parents=True, exist_ok=False)
    rom, symbols = build_rom()
    rom_info = validate_rom(rom)
    manifest = {"format": FORMAT, "basename": BASENAME, "original_assets_only": True,
                "hardware_verified": False, "state": "original_test_asset_unverified_on_hardware",
                "rom": {"filename": BASENAME + ".sfc", **rom_info}, "symbols": symbols,
                "save": {"bytes": SRAM_SIZE, "magic_hex": MAGIC.hex(),
                         "counter_offset": COUNTER_OFFSET, "complement_offset": COMPLEMENT_OFFSET,
                         "pattern": "((offset * 73) XOR (offset >> 8) XOR 0xA7) AND 0xFF, except magic/count pair",
                         "expected_sha256_after_first_boot": sha256(save_image(1)),
                         "expected_sha256_after_second_boot": sha256(save_image(2))},
                "generator_sha256": sha256(Path(__file__).read_bytes()),
                "warning": "Blank/spare SD and new test basename only. Do not use real saves or old b63 builds. Core renaming does not isolate common saves."}
    (output / (BASENAME + ".sfc")).write_bytes(rom)
    (output / "save-test-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def counter_argument(text: str) -> int:
    value = int(text, 0)
    if not 0 <= value <= 255:
        raise argparse.ArgumentTypeError("counter must be 0..255")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    generate = sub.add_parser("generate", help="make original ROM and separate manifest in a NEW directory")
    generate.add_argument("--out", type=Path, required=True)
    check = sub.add_parser("check-save", help="read-only verification of an exported raw .sav/.srm")
    check.add_argument("save", type=Path)
    check.add_argument("--expect-counter", type=counter_argument)
    check.add_argument("--expect-sha256")
    verify = sub.add_parser("check-rom", help="check header/checksum and exact original generated ROM")
    verify.add_argument("rom", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "generate":
            result = write_assets(args.out)
        elif args.command == "check-save":
            if args.save.suffix.lower() not in (".sav", ".srm"):
                raise ValueError("expected a raw .sav or .srm export; file is never modified")
            result = check_save(args.save.read_bytes(), args.expect_counter, args.expect_sha256)
        else:
            data = args.rom.read_bytes()
            result = validate_rom(data)
            if data != build_rom()[0]:
                raise ValueError("ROM does not match this original generator exactly")
        print(json.dumps(result, indent=2))
        return 0
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
