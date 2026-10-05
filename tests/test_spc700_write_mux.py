"""Exhaustive table proof and actual-VHDL equivalence for SPC700 write mux.

Run: python3 -m unittest discover -s tests -p test_spc700_write_mux.py -v
GHDL is optional only for discovery: a missing simulator is reported as NOT RUN.
The reference RTL comes from pinned, unchanged upstream commit ad9fed4e.
"""
import collections
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
PARTS = ROOT / 'rtl/upstream/SPC700'
REFERENCE = 'ad9fed4e'


def git_reference(filename):
    return subprocess.check_output(
        ['git', 'show', f'{REFERENCE}:rtl/upstream/SPC700/{filename}'],
        cwd=ROOT, text=True)


def table_rows(text):
    table = text.split('constant  M_TAB:', 1)[1].split('type ALUCtrl_t', 1)[0]
    rows = []
    for line in table.splitlines():
        values = re.findall(r'"([01X]+)"', line.split('--')[0])
        if len(values) == 8:
            rows.append(tuple(values))
    return rows


def assignment(text, signal):
    return re.search(r'\b' + signal + r'\s*<=.*?;', text, re.S).group(0)


class MicrocodeProof(unittest.TestCase):
    def test_all_rows_and_write_sources(self):
        rows = table_rows((PARTS / 'MCode.vhd').read_text())
        self.assertEqual(len(rows), 4096)
        self.assertEqual(rows, table_rows(git_reference('MCode.vhd')))
        # MI can only load a table row or the reset row. Even the literal-X
        # rows are retained; no formerly unspecified row is made concrete.
        defined = [v for v in rows if not any('X' in field for field in v)]
        undefined = [v for v in rows if any('X' in field for field in v)]
        self.assertEqual(len(defined), 1199)
        self.assertEqual(len(undefined), 2897)
        for v in undefined:
            self.assertTrue(all(set(field) == {'X'} for field in v))
        writes = collections.Counter()
        for i, v in enumerate(rows):
            bus, out = v[5], v[7]
            if out in ('000', 'XXX'):
                continue  # Both old/new D_OUT select their x"FF" default.
            self.assertIn(out, ('001', '011', '100', '101'), f'row {i}: new write source')
            if out == '001':
                self.assertIn(bus[:3], ('000', '001', '010', '011'), f'row {i}: live SB source')
                writes[{'000': 'A', '001': 'X', '010': 'Y', '011': 'T'}[bus[:3]]] += 1
            else:
                writes[{'011': 'PSW', '100': 'PCL', '101': 'PCH'}[out]] += 1
        self.assertEqual(writes, {'T': 60, 'A': 11, 'X': 4, 'Y': 5, 'PSW': 2, 'PCL': 19, 'PCH': 19})
        print('PASS 4096 rows: 1199 defined, 2897 unchanged all-X; 120 register-only writes')

    def test_no_live_input_or_alu_in_write_mux(self):
        rtl = (PARTS / 'SPC700.vhd').read_text()
        write_sb = assignment(rtl, 'WRITE_SB')
        output = assignment(rtl, 'D_OUT')
        self.assertNotRegex(write_sb + output, r'\b(D_IN|AluR|MulDivR|SB)\b')
        self.assertIn('WRITE_SB', output)
        # Read/ALU operand paths must not change as a side effect.
        self.assertEqual(assignment(rtl, 'SB'), assignment(git_reference('SPC700.vhd'), 'SB'))


class VhdlEquivalence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ghdl = shutil.which('ghdl')
        if not cls.ghdl:
            raise unittest.SkipTest('GHDL unavailable: actual VHDL mux equivalence/compile NOT RUN')
        cls.temp = tempfile.TemporaryDirectory(prefix='spc700-write-mux-')
        cls.work = pathlib.Path(cls.temp.name)
        cls.flags = ['--std=08', '-fsynopsys', '--workdir=' + str(cls.work)]
        cls.run_ghdl('-a', str(PARTS / 'SPC700_pkg.vhd'))

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    @classmethod
    def run_ghdl(cls, action, *args):
        result = subprocess.run([cls.ghdl, action, *cls.flags, *args], cwd=ROOT,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=120)
        if result.returncode:
            raise AssertionError(result.stdout)
        return result.stdout

    def test_full_spc700_analyzes_and_elaborates(self):
        for name in ('AddrGen', 'AddSub', 'BCDAdj', 'ALU', 'MCode', 'MulDiv', 'SPC700'):
            self.run_ghdl('-a', str(PARTS / (name + '.vhd')))
        self.run_ghdl('-e', 'SPC700')
        print('PASS full actual SPC700 VHDL analysis/elaboration')

    def test_actual_mux_all_rows(self):
        rtl = (PARTS / 'SPC700.vhd').read_text()
        reference = git_reference('SPC700.vhd')
        rows = table_rows((PARTS / 'MCode.vhd').read_text())
        controls = ',\n'.join('"' + v[5] + v[7] + '"' for v in rows)
        # Compile the actual assignments, not a reimplementation of the mux.
        old_output = assignment(reference, 'D_OUT').replace('D_OUT', 'd_reference', 1)
        new_output = assignment(rtl, 'D_OUT').replace('D_OUT', 'd_candidate', 1)
        bench = '''library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.SPC700_pkg.all;
entity tb_spc700_write_mux is end;
architecture test of tb_spc700_write_mux is
 signal MC: MCode_r;
 signal A,X,Y,T,PSW,SP,D_IN,AluR,SB,WRITE_SB: std_logic_vector(7 downto 0);
 signal PC,MulDivR: std_logic_vector(15 downto 0);
 signal d_reference,d_candidate: std_logic_vector(7 downto 0);
 type controls_t is array(0 to 4095) of std_logic_vector(8 downto 0);
 constant controls: controls_t := (
''' + controls + ''');
 constant nine: std_logic_vector(0 to 8) := "UX01ZWLH-";
begin
''' + assignment(reference, 'SB') + '\n' + assignment(rtl, 'WRITE_SB') + '\n' + old_output + '\n' + new_output + '''
 process
  variable b: unsigned(7 downto 0);
  variable cases: natural := 0;
 begin
  for row in controls'range loop
   MC.BUS_CTRL <= controls(row)(8 downto 3);
   MC.OUT_BUS <= controls(row)(2 downto 0);
   for value in 0 to 264 loop
    if value < 256 then
     b := to_unsigned(value,8);
     A <= std_logic_vector(b); X <= std_logic_vector(not b);
     Y <= std_logic_vector(rotate_left(b,1)); T <= std_logic_vector(rotate_left(b,2));
     PSW <= std_logic_vector(rotate_left(b,3)); SP <= std_logic_vector(b xor x"53");
     PC <= std_logic_vector(b & not b); MulDivR <= std_logic_vector(not b & b);
     D_IN <= std_logic_vector(b xor x"69"); AluR <= std_logic_vector(b xor x"A7");
    else
     A <= (others=>nine(value-256)); X <= (others=>nine(value-256));
     Y <= (others=>nine(value-256)); T <= (others=>nine(value-256));
     PSW <= (others=>nine(value-256)); SP <= (others=>nine(value-256));
     PC <= (others=>nine(value-256)); MulDivR <= (others=>nine(value-256));
     D_IN <= (others=>nine(value-256)); AluR <= (others=>nine(value-256));
    end if;
    wait for 1 ns;
    assert d_candidate=d_reference
     report "Mux mismatch row=" & integer'image(row) & " value=" & integer'image(value)
     severity failure;
    if controls(row)="XXXXXXXXX" then
     assert d_candidate=x"FF" report "Changed undefined X-row output" severity failure;
    end if;
    cases := cases + 1;
   end loop;
  end loop;
  report "PASS actual mux equivalence: " & integer'image(cases) & " cases, including all X rows";
  stop;
 end process;
end;
'''
        source = self.work / 'tb_spc700_write_mux.vhd'
        source.write_text(bench)
        self.run_ghdl('-a', str(source))
        self.run_ghdl('-e', 'tb_spc700_write_mux')
        output = self.run_ghdl('-r', 'tb_spc700_write_mux', '--assert-level=error')
        self.assertIn('PASS actual mux equivalence: 1085440 cases', output)
        print(output.strip())


if __name__ == '__main__':
    unittest.main()
