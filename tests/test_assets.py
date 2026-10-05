"""Original asset format and generated 65816 instruction regression tests.

The narrow CPU/bus harness executes the emitted instructions and checks I/O
ordering. It is NOT a cycle-accurate SNES, SPC, FPGA, audio, or hardware test.
Run from repository root: python3 -m unittest discover -s tests -p test_assets.py
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("msu1_testrom", ROOT / "tools/msu1_testrom.py")
assets = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(assets)


class TestAssetFormats(unittest.TestCase):
    def test_lorom_header_vectors_checksum_and_reproducibility(self):
        rom, symbols = assets.build_rom()
        self.assertEqual((rom, symbols), assets.build_rom())
        self.assertEqual(len(rom), 32768)
        self.assertEqual(rom[0x7FC0:0x7FD5], b"POCKET MSU1 SELF TEST")
        self.assertEqual(rom[0x7FD5:0x7FDC], bytes((0x20, 0, 5, 0, 1, 0, 0)))
        complement, checksum = struct.unpack_from("<HH", rom, 0x7FDC)
        self.assertEqual(checksum ^ complement, 0xFFFF)
        self.assertEqual(sum(rom) & 0xFFFF, checksum)
        self.assertEqual(struct.unpack_from("<H", rom, 0x7FFC)[0], symbols["reset"])
        for vector in (0x7FE4, 0x7FE6, 0x7FE8, 0x7FEA, 0x7FEE, 0x7FF4,
                       0x7FF8, 0x7FFA, 0x7FFE):
            self.assertEqual(struct.unpack_from("<H", rom, vector)[0], symbols["interrupt"])
        self.assertEqual(rom[symbols["interrupt"] - 0x8000], 0x40)  # RTI
        self.assertLess(symbols["tilemap"] + 2048, 0xFFC0)

    def test_assembler_rejects_broken_branches(self):
        a = assets.Assembler()
        a.branch(0x80, "far")
        a.data.extend(bytes(129))
        a.label("far")
        with self.assertRaisesRegex(ValueError, "out of range"):
            a.resolve()
        with self.assertRaisesRegex(ValueError, "duplicate"):
            a.label("far")

    def test_font_and_screen_are_original_self_contained_tiles(self):
        font, tilemap = assets.make_font(), assets.make_tilemap()
        self.assertEqual(len(font), 2048)
        self.assertEqual(len(tilemap), 2048)
        self.assertEqual(set(font[1::2]), {0})
        self.assertEqual(set(tilemap[1::2]), {0})
        for line in assets.SCREEN_LINES.values():
            self.assertLessEqual(len(line), 28)
            self.assertTrue(all(character in assets.FONT for character in line))

    def test_predictable_data_and_sector_boundary(self):
        data = assets.make_data()
        self.assertEqual(len(data), assets.DATA_SIZE)
        for index in (0, 1, 15, 16, 255, 256, 511, 512, 4095, 8191):
            self.assertEqual(data[index], (0x5A + 37 * index) & 255)
        self.assertEqual(data[15], 0x85)
        self.assertEqual(data[31], 0xD5)
        with self.assertRaises(ValueError):
            assets.make_data(-1)

    def test_pcm_header_loop_frames_length_and_stereo(self):
        for track in (1, 2):
            pcm = assets.make_pcm(track)
            self.assertEqual(pcm[:4], b"MSU1")
            loop = struct.unpack_from("<I", pcm, 4)[0]
            self.assertEqual(loop, 22050)
            self.assertEqual(len(pcm), 8 + 88200 * 4)
            self.assertLess(8 + loop * 4, len(pcm))
            samples = list(struct.iter_unpack("<hh", pcm[8:]))
            self.assertTrue(any(left != right for left, right in samples))
            self.assertTrue(any(left > 0 for left, _ in samples))
            self.assertTrue(any(left < 0 for left, _ in samples))
            self.assertLessEqual(max(abs(v) for pair in samples for v in pair), 4096)
            self.assertEqual(samples[loop], (-4096, -4096))
            self.assertEqual(pcm, assets.make_pcm(track))
        self.assertNotEqual(assets.make_pcm(1), assets.make_pcm(2))

    def test_pcm_invalid_inputs(self):
        for arguments in ((3, 10, 0), (1, 0, 0), (1, 10, 10), (1, 10, -1)):
            with self.assertRaises(ValueError):
                assets.make_pcm(*arguments)

    def test_file_layout_manifest_and_determinism(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            manifest = assets.write_assets(output)
            for name, details in manifest["files"].items():
                content = (output / name).read_bytes()
                self.assertEqual(details["size"], len(content))
                self.assertEqual(details["sha256"], hashlib.sha256(content).hexdigest())
            saved = {p.name: p.read_bytes() for p in output.iterdir()}
            self.assertEqual(manifest, assets.write_assets(output))
            self.assertEqual(saved, {p.name: p.read_bytes() for p in output.iterdir()})
            self.assertFalse((output / "MSU Test-3.pcm").exists())
            self.assertEqual(json.loads((output / "MSU Test.manifest.json").read_text()), manifest)
            self.assertFalse(manifest["hardware_tested"])
            for invalid in ("", "..", "../escape", "a/b", "a\\b", "a\x00b"):
                with self.assertRaises(ValueError):
                    assets.write_assets(output, invalid)


class DiagnosticBus:
    """Byte-addressed mocked SNES/MSU I/O, with explicit controllable busy flags."""
    def __init__(self, rom, present=True, spc_present=True):
        self.rom = rom
        self.ram = bytearray(32768)
        self.vram = bytearray(65536)
        self.vram_address = 0
        self.present = present
        self.data = bytearray(assets.make_data())
        self.data_seek = 0
        self.data_pointer = 0
        self.data_reads = 0
        self.data_busy = False
        self.audio_busy = False
        self.audio_playing = False
        self.audio_repeat = False
        self.audio_missing = False
        self.track = 0
        self.volume = 0
        self.msu_writes = []
        self.spc_present = spc_present
        self.spc_ports = [0xAA, 0xBB, 0, 0]
        self.spc_upload = bytearray()
        self.spc_started = False

    def read(self, address):
        address &= 65535
        if address >= 0x8000:
            return self.rom[address - 0x8000]
        if 0x2000 <= address <= 0x2007:
            if not self.present:
                return 0xFF
            if address == 0x2000:
                return (2 | (self.audio_missing << 3) | (self.audio_playing << 4)
                        | (self.audio_repeat << 5) | (self.audio_busy << 6)
                        | (self.data_busy << 7))
            if address == 0x2001:
                if self.data_busy:
                    raise AssertionError("read while data busy")
                self.data_reads += 1
                value = self.data[self.data_pointer] if self.data_pointer < len(self.data) else 0
                self.data_pointer += 1
                return value
            return b"S-MSU1"[address - 0x2002]
        if 0x2140 <= address <= 0x2143:
            return self.spc_ports[address - 0x2140] if self.spc_present else 0
        return self.ram[address]

    def write(self, address, value):
        address &= 65535
        value &= 255
        if address >= 0x8000:
            raise AssertionError("write into ROM")
        self.ram[address] = value
        if 0x2000 <= address <= 0x2007:
            self.msu_writes.append((address, value))
            if address < 0x2004:
                shift = (address - 0x2000) * 8
                self.data_seek = (self.data_seek & ~(255 << shift)) | (value << shift)
                if address == 0x2003:
                    self.data_pointer = self.data_seek
            elif address == 0x2004:
                self.track = (self.track & 0xFF00) | value
            elif address == 0x2005:
                self.track = (self.track & 255) | (value << 8)
                self.audio_missing = self.track not in (1, 2)
                self.audio_playing = self.audio_repeat = False
            elif address == 0x2006:
                self.volume = value
            elif address == 0x2007:
                if self.audio_busy:
                    raise AssertionError("control write while audio busy")
                if not self.audio_missing:
                    self.audio_playing = bool(value & 1)
                    self.audio_repeat = bool(value & 2)
        elif address == 0x2116:
            self.vram_address = (self.vram_address & 0xFF00) | value
        elif address == 0x2117:
            self.vram_address = ((self.vram_address & 255) | (value << 8)) & 0x7FFF
        elif address == 0x2118:
            self.vram[self.vram_address * 2] = value
        elif address == 0x2119:
            self.vram[self.vram_address * 2 + 1] = value
            self.vram_address = (self.vram_address + 1) & 0x7FFF
        elif 0x2140 <= address <= 0x2143:
            if address == 0x2140:
                if value == 0xCC:
                    self.spc_started = True
                elif self.spc_started and value == len(self.spc_upload):
                    self.spc_upload.append(self.spc_ports[1])
                else:
                    self.spc_started = False
            self.spc_ports[address - 0x2140] = value


class DiagnosticCPU:
    """Only the documented instruction subset emitted by msu1_testrom.py.

    Memory, widths, status flags and hardware stack are modeled; instruction
    timing, decimal mode, interrupts and unrelated opcodes are not. Unsupported
    instructions fail instead of being silently treated as NOPs.
    """
    def __init__(self, bus):
        self.bus = bus
        self.pc = bus.read(0xFFFC) | (bus.read(0xFFFD) << 8)
        self.a = self.x = self.dp = 0
        self.sp = 0x1FF
        self.m8 = self.x8 = True
        self.c = self.z = self.n = False

    def fetch(self):
        value = self.bus.read(self.pc)
        self.pc = (self.pc + 1) & 65535
        return value

    def word(self):
        return self.fetch() | (self.fetch() << 8)

    def push(self, value, wide=False):
        if wide:
            self.push(value >> 8)
        self.bus.write(self.sp, value)
        self.sp = (self.sp - 1) & 65535

    def pop(self, wide=False):
        self.sp = (self.sp + 1) & 65535
        value = self.bus.read(self.sp)
        return value | (self.pop() << 8) if wide else value

    def flags(self, value, wide=False):
        self.z = value == 0
        self.n = bool(value & (0x8000 if wide else 0x80))

    def set_a(self, value):
        mask = 255 if self.m8 else 65535
        self.a = ((self.a & 0xFF00) if self.m8 else 0) | (value & mask)
        self.flags(value & mask, not self.m8)

    def step(self):
        instruction_at = self.pc
        opcode = self.fetch()
        mask = 255 if self.m8 else 65535
        av = self.a & mask
        if opcode in (0x78, 0xD8, 0xFB):
            return  # SEI, CLD, XCE have no relevant effect beyond widths below
        if opcode == 0x18: self.c = False
        elif opcode == 0x38: self.c = True
        elif opcode in (0xC2, 0xE2):
            bits = self.fetch()
            if bits & 0x20: self.m8 = opcode == 0xE2
            if bits & 0x10: self.x8 = opcode == 0xE2
        elif opcode == 0xA9: self.set_a(self.fetch() if self.m8 else self.word())
        elif opcode == 0xA2:
            self.x = self.fetch() if self.x8 else self.word()
            self.flags(self.x, not self.x8)
        elif opcode == 0x9A: self.sp = self.x
        elif opcode == 0x5B: self.dp = self.a
        elif opcode == 0x48: self.push(self.a, not self.m8)
        elif opcode == 0xAB: self.pop()  # DB is explicitly zero in this ROM
        elif opcode == 0xDA: self.push(self.x, not self.x8)
        elif opcode == 0xFA:
            self.x = self.pop(not self.x8); self.flags(self.x, not self.x8)
        elif opcode in (0x8D, 0x9C):
            self.bus.write(self.word(), av if opcode == 0x8D else 0)
        elif opcode in (0x85, 0x64):
            self.bus.write(self.dp + self.fetch(), av if opcode == 0x85 else 0)
        elif opcode in (0xAD, 0xA5, 0xBD):
            address = self.dp + self.fetch() if opcode == 0xA5 else self.word()
            if opcode == 0xBD: address = (address + self.x) & 65535
            value = self.bus.read(address)
            if not self.m8: value |= self.bus.read(address + 1) << 8
            self.set_a(value)
        elif opcode in (0xCA, 0xE8):
            self.x = (self.x + (-1 if opcode == 0xCA else 1)) & (255 if self.x8 else 65535)
            self.flags(self.x, not self.x8)
        elif opcode in (0x1A, 0x3A): self.set_a(av + (1 if opcode == 0x1A else -1))
        elif opcode == 0xC6:
            address = self.dp + self.fetch()
            value = (self.bus.read(address) - 1) & mask
            self.bus.write(address, value); self.flags(value, not self.m8)
        elif opcode in (0xC9, 0xC5, 0xE0):
            if opcode == 0xC5: value = self.bus.read(self.dp + self.fetch())
            elif opcode == 0xE0: value = self.fetch() if self.x8 else self.word()
            else: value = self.fetch() if self.m8 else self.word()
            lhs, wide = (self.x, not self.x8) if opcode == 0xE0 else (av, not self.m8)
            self.c = lhs >= value
            self.flags((lhs - value) & (65535 if wide else 255), wide)
        elif opcode in (0x29, 0x2D, 0x49, 0x09, 0x05):
            if opcode == 0x2D: value = self.bus.read(self.word())
            elif opcode == 0x05: value = self.bus.read(self.dp + self.fetch())
            else: value = self.fetch()
            if opcode in (0x29, 0x2D): self.set_a(av & value)
            elif opcode == 0x49: self.set_a(av ^ value)
            else: self.set_a(av | value)
        elif opcode in (0x69, 0xE9):
            value = self.fetch()
            result = av + value + self.c if opcode == 0x69 else av - value - (not self.c)
            self.c = result > mask if opcode == 0x69 else result >= 0
            self.set_a(result)
        elif opcode == 0x4A:
            self.c = bool(av & 1); self.set_a(av >> 1)
        elif opcode == 0xAA:
            self.x = self.a & (255 if self.x8 else 65535)
            self.flags(self.x, not self.x8)
        elif opcode == 0x20:
            target = self.word(); self.push((self.pc - 1) & 65535, True); self.pc = target
        elif opcode == 0x60: self.pc = (self.pop(True) + 1) & 65535
        elif opcode == 0x4C: self.pc = self.word()
        elif opcode in (0x80, 0xF0, 0xD0, 0x30, 0x10, 0x90, 0xB0):
            offset = self.fetch()
            take = {0x80: True, 0xF0: self.z, 0xD0: not self.z, 0x30: self.n,
                    0x10: not self.n, 0x90: not self.c, 0xB0: self.c}[opcode]
            if take: self.pc = (self.pc + (offset if offset < 128 else offset - 256)) & 65535
        else:
            raise AssertionError(f"unsupported opcode ${opcode:02X} at ${instruction_at:04X}")

    def run_until(self, address, budget=1000000):
        for _ in range(budget):
            if self.pc == address: return
            self.step()
        raise AssertionError(f"instruction budget exceeded at ${self.pc:04X}")

    def call(self, address):
        stop = 0x7000
        self.push(stop - 1, True)
        self.pc = address
        self.run_until(stop)


class TestDiagnosticExecution(unittest.TestCase):
    def boot(self, present=True, spc_present=True):
        rom, self.symbols = assets.build_rom()
        self.bus = DiagnosticBus(rom, present, spc_present)
        self.cpu = DiagnosticCPU(self.bus)
        self.cpu.run_until(self.symbols["main"])

    def value(self, name):
        return self.bus.ram[assets.STATE[name]]

    def call(self, name):
        self.cpu.call(self.symbols[name])

    def press(self, low=0, high=0):
        self.bus.ram[0x4218] = low
        self.bus.ram[0x4219] = high
        self.call("read_controller")
        self.call("handle_buttons")
        self.call("service_msu")
        self.bus.ram[0x4218] = self.bus.ram[0x4219] = 0
        self.call("read_controller")

    def test_boot_data_and_visible_hex_fields(self):
        self.boot()
        self.assertEqual(self.value("detected"), 1)
        self.assertEqual(self.value("spc_ready"), 1)
        self.assertEqual(self.bus.spc_upload, bytes((0x8F, 0x5C, 0xF2, 0x8F, 0xFF, 0xF3,
                                                    0x8F, 0x6C, 0xF2, 0x8F, 0x20, 0xF3, 0x2F, 0xFE)))
        self.assertEqual(self.bus.vram[:2048], assets.make_font())
        self.assertEqual(self.bus.vram[0x2000:0x2800], assets.make_tilemap())
        self.assertEqual(self.bus.ram[0x2100], 15)
        self.assertEqual(self.bus.track, 1)
        self.assertEqual(self.bus.volume, 0x80)
        self.call("service_msu")
        self.assertEqual(self.bus.data_reads, 16)
        self.assertEqual(self.value("data_byte"), 0x85)
        self.assertEqual(self.value("data_check"), 1)
        self.call("render_status")
        def field(row):
            offset = (0x1000 + row * 32 + 13) * 2
            return bytes(self.bus.vram[offset:offset + 4:2])
        self.assertEqual(field(4), b"01")
        self.assertEqual(field(5), b"02")
        self.assertEqual(field(7), b"85")
        self.assertEqual(field(10), b"80")
        self.assertEqual(field(12), b"01")

    def test_missing_msu_boot_does_not_touch_msu_registers(self):
        self.boot(present=False)
        self.assertEqual(self.value("detected"), 0)
        self.assertEqual(self.bus.msu_writes, [])
        self.assertEqual(self.bus.ram[0x2100], 15)

    def test_spc_timeout_still_reaches_diagnostic(self):
        self.boot(spc_present=False)
        self.assertEqual(self.value("spc_ready"), 0)
        self.assertEqual(self.value("detected"), 1)

    def test_play_stop_repeat_and_eof_play_again(self):
        self.boot()
        self.press(low=0x80)  # A
        self.assertTrue(self.bus.audio_playing)
        self.press(high=0x40)  # Y
        self.assertTrue(self.bus.audio_repeat)
        self.assertTrue(self.bus.audio_playing)
        self.press(high=0x80)  # B
        self.assertFalse(self.bus.audio_playing)
        self.assertTrue(self.bus.audio_repeat)
        self.press(low=0x80)
        self.assertTrue(self.bus.audio_playing)
        self.press(low=0x80)
        self.assertFalse(self.bus.audio_playing)
        self.press(low=0x80)
        self.bus.audio_playing = False  # Simulated non-repeating EOF
        self.press(high=0x40)  # Changing repeat after EOF must not restart audio
        self.assertFalse(self.bus.audio_playing)
        self.press(low=0x80)
        self.assertTrue(self.bus.audio_playing)

    def test_tracks_missing_track_and_recovery(self):
        self.boot()
        self.press(high=1)
        self.assertEqual(self.bus.track, 2)
        self.press(high=1)
        self.assertEqual(self.bus.track, 3)
        self.assertTrue(self.bus.audio_missing)
        self.press(low=0x80)
        self.assertFalse(self.bus.audio_playing)
        self.assertTrue(self.value("status") & 8)
        self.press(high=1)
        self.assertEqual(self.bus.track, 1)
        self.assertFalse(self.bus.audio_missing)
        self.press(high=2)
        self.assertEqual(self.bus.track, 3)

    def test_volume_saturates_and_button_edges_do_not_repeat(self):
        self.boot()
        for _ in range(20): self.press(high=8)
        self.assertEqual(self.bus.volume, 255)
        for _ in range(20): self.press(high=4)
        self.assertEqual(self.bus.volume, 0)
        self.bus.ram[0x4219] = 8
        for _ in range(3):
            self.call("read_controller"); self.call("handle_buttons")
        self.assertEqual(self.bus.volume, 16)

    def test_data_busy_audio_busy_and_seek_commit_order(self):
        self.boot()
        self.bus.data_busy = self.bus.audio_busy = True
        self.call("service_msu")
        self.assertEqual(self.bus.data_reads, 0)
        self.assertEqual(self.value("remaining"), 16)
        self.assertEqual(self.value("pending_control"), 1)
        self.assertEqual(self.value("status") & 0xC0, 0xC0)
        self.bus.data_busy = self.bus.audio_busy = False
        self.call("service_msu")
        self.assertEqual(self.value("data_check"), 1)
        self.assertEqual(self.value("pending_control"), 0)
        self.press(low=0x40)
        self.assertEqual(self.value("data_byte"), 0xD5)
        self.assertEqual(self.value("data_check"), 1)
        self.press(high=0x10)
        self.assertEqual(self.value("data_byte"), 0x85)
        seeks = [(address, value) for address, value in self.bus.msu_writes if address < 0x2004]
        self.assertEqual(seeks[-4:], [(0x2000, 0), (0x2001, 0), (0x2002, 0), (0x2003, 0)])

    def test_data_corruption_latches_failure_and_reseek_recovers(self):
        self.boot()
        self.bus.data[3] ^= 1
        self.call("service_msu")
        self.assertEqual(self.value("data_check"), 2)
        self.bus.data[3] ^= 1
        self.press(high=0x10)
        self.assertEqual(self.value("data_check"), 1)


if __name__ == "__main__":
    unittest.main()
