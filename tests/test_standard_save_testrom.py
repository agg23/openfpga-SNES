"""Pure-Python original save ROM/checker regression; no emulator substitution."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('standard_save_testrom', ROOT/'tools/standard_save_testrom.py')
t = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(t)


class StandardSaveRomTests(unittest.TestCase):
    def test_original_rom_header_checksum_and_vectors(self):
        rom, symbols = t.build_rom()
        self.assertEqual(len(rom), 32768)
        self.assertEqual(rom[0x7FD5:0x7FDB], bytes((0x20,2,5,1,1,0)))
        self.assertEqual(rom[0x7FFC:0x7FFE], b'\x00\x80')
        self.assertEqual(t.validate_rom(rom)['sram_bytes'],2048)
        self.assertEqual(len(t.MAGIC),16)
        template=symbols['template']-0x8000
        self.assertEqual(rom[template:template+2048], t.save_image(1))
        self.assertEqual(t.build_rom(), t.build_rom())

    def test_all_counter_values_and_full_image_sha(self):
        for counter in range(256):
            data=t.save_image(counter)
            info=t.check_save(data, counter, t.sha256(data))
            self.assertEqual(info['counter'],counter)
            self.assertEqual(data[16:18], bytes((counter,counter^255)))
            self.assertEqual(len(data),2048)
        # Deliberate fixed known-answer hashes, not calculated in this test.
        self.assertEqual(t.sha256(t.save_image(1)), '94aa75cd2153de17921b871ed22077fe6e13f7334f40eb6190a25d5bb129d9d3')
        self.assertEqual(t.sha256(t.save_image(2)), '073f5a2e3d47ef13360f6e4d41a1bb6960ba5a08c64bb90bde0f6f501c744633')

    def test_every_byte_corruption_is_rejected(self):
        for index in range(2048):
            data=bytearray(t.save_image(2));data[index]^=0x01
            with self.subTest(offset=index), self.assertRaises(ValueError):t.check_save(data)

    def test_all_bit_flips_of_magic_counter_and_last_byte_rejected(self):
        for index in (*range(18),255,256,2047):
            for bit in range(8):
                data=bytearray(t.save_image(2));data[index]^=1<<bit
                with self.subTest(offset=index,bit=bit), self.assertRaises(ValueError):t.check_save(data)

    def test_address_dependent_pattern_rejects_page_alias(self):
        data=bytearray(t.save_image(2));data[256:512]=data[512:768]
        with self.assertRaisesRegex(ValueError,'0x0100'):t.check_save(data)

    def test_blank_zero_truncated_padded_headered_wrong_count_hash(self):
        good=t.save_image(2)
        for data in (bytes([255])*2048, bytes(2048), good[:-1],good+b'\0',bytes(512)+good):
            with self.assertRaises(ValueError):t.check_save(data)
        with self.assertRaisesRegex(ValueError,'counter mismatch'):t.check_save(good,1)
        with self.assertRaisesRegex(ValueError,'SHA-256 mismatch'):t.check_save(good,2,'0'*64)
        with self.assertRaises(ValueError):t.save_image(-1)
        with self.assertRaises(ValueError):t.save_image(256)

    def test_rom_validator_rejects_bad_sizes_header_and_checksum(self):
        rom=t.build_rom()[0]
        for bad in (rom[:-1],bytes(512)+rom):
            with self.assertRaises(ValueError):t.validate_rom(bad)
        for index in (0,0x7FD5,0x7FD6,0x7FD7,0x7FD8,0x7FDC,0x7FDE,0x7FFC):
            data=bytearray(rom);data[index]^=1
            with self.subTest(offset=index),self.assertRaises(ValueError):t.validate_rom(data)

    def test_fresh_output_manifest_and_refusal_to_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)/'new-assets'
            manifest=t.write_assets(folder)
            self.assertEqual({p.name for p in folder.iterdir()}, {'Pocket Standard Save Test.sfc','save-test-manifest.json'})
            self.assertEqual(json.loads((folder/'save-test-manifest.json').read_text()),manifest)
            self.assertEqual(manifest['rom']['sha256'],t.sha256((folder/'Pocket Standard Save Test.sfc').read_bytes()))
            self.assertFalse(manifest['hardware_verified'])
            with self.assertRaises(FileExistsError):t.write_assets(folder)
            self.assertEqual(json.loads((folder/'save-test-manifest.json').read_text()),manifest)

    def test_assembler_rejects_duplicate_labels_out_of_range(self):
        a=t.Emitter();a.label('start')
        with self.assertRaises(ValueError):a.label('start')
        a.branch(0xD0,'far');a.code.extend(bytes(129));a.label('far')
        with self.assertRaises(ValueError):a.resolve()

    def test_cli_read_only_and_errors_nonzero(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'test.srm';path.write_bytes(t.save_image(2))
            before=path.read_bytes()
            def run(*args):
                return subprocess.run([sys.executable,str(ROOT/'tools/standard_save_testrom.py'),*map(str,args)],capture_output=True,text=True)
            good=run('check-save',path,'--expect-counter','2','--expect-sha256',t.sha256(before))
            self.assertEqual(good.returncode,0,good.stderr)
            self.assertTrue(json.loads(good.stdout)['pattern_verified'])
            for args in (('check-save',path,'--expect-counter','1'),('check-save',path,'--expect-sha256','0'*64),
                         ('check-save',path,'--expect-counter','256'),('check-save',Path(temp)/'absent.sav')):
                self.assertNotEqual(run(*args).returncode,0)
            path.write_bytes(before[:-1]);self.assertNotEqual(run('check-save',path).returncode,0)
            path.write_bytes(before);self.assertEqual(path.read_bytes(),before)
            self.assertNotEqual(run('generate','--out',Path(temp)).returncode,0)
            rom_path=Path(temp)/'rom.sfc';rom_path.write_bytes(t.build_rom()[0])
            self.assertEqual(run('check-rom',rom_path).returncode,0)
            # Header/checksum-valid non-original bytes must still be refused.
            altered=bytearray(rom_path.read_bytes());altered[0x4000]^=1
            altered[0x7FDC:0x7FE0]=b'\xFF\xFF\0\0'
            checksum=sum(altered)&65535
            import struct
            struct.pack_into('<HH',altered,0x7FDC,checksum^65535,checksum)
            rom_path.write_bytes(altered)
            self.assertNotEqual(run('check-rom',rom_path).returncode,0)

if __name__=='__main__':unittest.main()
