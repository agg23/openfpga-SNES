"""Fail-closed I/O-assumption validation; no Quartus/fit invocation."""
import json
import pathlib
import shutil
import subprocess
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[1]
FIXTURE=ROOT/'docs/evidence/standard-sdram-io/fc8dff4/synthetic-zero-board-ntsc.json'

def word(s):
    return '"'+str(s).replace('\\','\\\\').replace('$','\\$').replace('[','\\[').replace('"','\\"').replace('\n','\\n')+'"'

class IoPolicyTests(unittest.TestCase):
    def run_policy(self,a):
        if not shutil.which('tclsh'):self.skipTest('tclsh unavailable')
        helper=ROOT/'tools/standard_sdram_io_assumptions.tcl'
        script='source '+word(helper)+'\n'
        script+='proc get_clocks {args} {error API_REACHED_AFTER_VALIDATION}\n'
        script+='set a [dict create '+' '.join(word(k)+' '+word(v) for k,v in a.items())+']\n'
        script+='catch {apply_standard_sdram_io_assumptions $a} result\nputs $result\n'
        r=subprocess.run(['tclsh'],input=script,capture_output=True,text=True,timeout=10)
        self.assertEqual(r.returncode,0,r.stderr)
        return r.stdout.strip()
    def fixture(self):return json.loads(FIXTURE.read_text())
    def test_complete_explicit_fixture_reaches_native_preflight(self):
        self.assertEqual(self.run_policy(self.fixture()),'API_REACHED_AFTER_VALIDATION')
    def test_missing_board_value_never_defaults_to_zero(self):
        a=self.fixture();del a['pcb_read_max']
        self.assertIn('Missing explicit I/O assumption: pcb_read_max',self.run_policy(a))
    def test_missing_provenance(self):
        a=self.fixture();a['evidence']=''
        self.assertIn('provenance is mandatory',self.run_policy(a))
    def test_unknown_key(self):
        a=self.fixture();a['pretend_signoff']=1
        self.assertIn('Unknown I/O assumption',self.run_policy(a))
    def test_bad_numbers(self):
        for value in (-1,'NaN','Inf','-Inf','guess'):
            with self.subTest(value=value):
                a=self.fixture();a['pcb_clock_min']=value
                self.assertIn('Non-finite/negative',self.run_policy(a))
    def test_reversed_board_bounds(self):
        a=self.fixture();a['pcb_write_min']=2;a['pcb_write_max']=1
        self.assertIn('minimum exceeds maximum',self.run_policy(a))
