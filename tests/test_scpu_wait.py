"""Actual upstream SCPU regressions, with no behavioral replacement CPU.

Requires GHDL in PATH (GHDL_PREFIX/LD_LIBRARY_PATH may be set by the caller).
The equivalence reference is read from the pinned Git revision at test time,
renamed, and compiled only in a temporary test work directory.
"""
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASELINE = 'ad9fed4e'
CPU_PARTS = ['P65816_pkg', 'AddrGen', 'BCDAdder', 'AddSubBCD', 'ALU', 'MCode', 'P65C816']
BENCHES = ['tb_scpu_msu_wait', 'tb_scpu_hdma_wait', 'tb_scpu_cpu_wait_hdma_init', 'tb_scpu_hdma_init_fetch_wait']


class ScpuWaitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ghdl = shutil.which('ghdl')
        if not cls.ghdl:
            raise unittest.SkipTest('GHDL unavailable: actual SCPU CPU/DMA/HDMA and baseline equivalence simulations NOT RUN')
        cls.temp = tempfile.TemporaryDirectory(prefix='msu1-scpu-')
        cls.work = pathlib.Path(cls.temp.name)
        cls.flags = ['--std=08', '-fsynopsys', '--workdir=' + str(cls.work)]
        cls.run_ghdl('-a', *[str(ROOT / 'rtl/upstream/65C816' / (p + '.vhd')) for p in CPU_PARTS],
                     str(ROOT / 'rtl/upstream/CPU.vhd'))
        ref = subprocess.check_output(['git', 'show', BASELINE + ':rtl/upstream/CPU.vhd'], cwd=ROOT, text=True)
        # VHDL's std_logic has nine values. Quartus tolerates this upstream
        # incomplete case, GHDL requires the nonbinary branch explicitly.
        start = ref.index('case HVIRQ_EN is')
        end = ref.index('end case;', start)
        ref = ref[:end] + "when others => IRQ_TIME := '0';\n\t\t\t" + ref[end:]
        ref = re.sub(r'\bSCPU\b', 'SCPU_REF', ref)
        reference = cls.work / 'CPU_reference.vhd'
        reference.write_text(ref)
        cls.run_ghdl('-a', str(reference))

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    @classmethod
    def run_ghdl(cls, action, *args):
        result = subprocess.run([cls.ghdl, action, *cls.flags, *args], cwd=ROOT,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        if result.returncode:
            raise AssertionError(result.stdout)
        return result.stdout

    def simulate(self, name, source, *generics):
        self.run_ghdl('-a', str(source))
        self.run_ghdl('-e', name)
        result = self.run_ghdl('-r', name, *generics, '--assert-level=error', '--ieee-asserts=disable')
        self.assertIn('PASS', result)
        print(result.strip(), flush=True)

    def test_cpu_dma_interrupt_wait(self):
        self.simulate(BENCHES[0], ROOT / 'tests/msu1' / (BENCHES[0] + '.vhd'))

    def test_refresh_aligned_nmi_wait(self):
        self.simulate(BENCHES[0], ROOT / 'tests/msu1' / (BENCHES[0] + '.vhd'),
                      '-gHB_OFFSET=144', '-gREQUIRE_REFRESH_ENTRY=true')

    def test_hdma_frame_boundary_wait(self):
        self.simulate(BENCHES[1], ROOT / 'tests/msu1' / (BENCHES[1] + '.vhd'))

    def test_cpu_wait_delays_hdma_frame_init(self):
        self.simulate(BENCHES[2], ROOT / 'tests/msu1' / (BENCHES[2] + '.vhd'))

    def test_first_wait_inside_hdma_init(self):
        self.simulate(BENCHES[3], ROOT / 'tests/msu1' / (BENCHES[3] + '.vhd'))

    def test_no_wait_cycle_equivalence(self):
        # Exercise both the CPU/DMA/interrupt program and the HDMA program.
        # Both real SCPU instances receive the same memory, blanking and reset.
        # Every externally-visible A/B bus signal and phase is compared.
        for original in BENCHES[:2]:
            with self.subTest(program=original):
                text = (ROOT / 'tests/msu1' / (original + '.vhd')).read_text()
                name = original + '_equivalence'
                text = text.replace(original, name)
                text = text.replace('BUS_WAIT=>bwait', "BUS_WAIT=>'0'")
                text = re.sub(r'assert\s+.*?severity failure;', '', text, flags=re.S)
                text = text.replace('stop;', '')
                text = re.sub(r'report "PASS.*?";', '', text)
                a = text.index(' dut:entity work.SCPU')
                b = text.index("DBG_CPU_EN=>'1');", a) + len("DBG_CPU_EN=>'1');")
                instance = text[a:b].replace('dut:entity work.SCPU', 'reference:entity work.SCPU_REF')
                instance = instance.replace("BUS_WAIT=>'0',", '')
                names = 'ca|pa|dout|rd|wr|prd|pwr|fc|rc|rf'
                instance = re.sub(r'=>\s*(' + names + r')\b', lambda m: '=>' + m[1] + '_ref', instance)
                pos = text.index('\nbegin\n')
                text = text[:pos] + '''
 signal ca_ref:std_logic_vector(23 downto 0);
 signal pa_ref,dout_ref:std_logic_vector(7 downto 0);
 signal rd_ref,wr_ref,prd_ref,pwr_ref,fc_ref,rc_ref,rf_ref:std_logic;
''' + text[pos:]
                pos = text.index('\nbegin\n') + len('\nbegin\n')
                text = text[:pos] + instance + '''
 compare:process(clk) begin if falling_edge(clk) and rst='1' then
 assert ca=ca_ref and pa=pa_ref and dout=dout_ref and rd=rd_ref and wr=wr_ref and
        prd=prd_ref and pwr=pwr_ref and fc=fc_ref and rc=rc_ref and rf=rf_ref
 report "BUS_WAIT=0 differs from pinned upstream SCPU" severity failure;
 if cycles=40000 then report "PASS 40000-cycle pristine SCPU equivalence";stop;end if;
 end if;end process;
''' + text[pos:]
                source = self.work / (name + '.vhd')
                source.write_text(text)
                self.simulate(name, source)


if __name__ == '__main__':
    unittest.main()
