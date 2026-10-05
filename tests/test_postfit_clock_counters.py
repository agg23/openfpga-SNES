import importlib.util, pathlib, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
S=importlib.util.spec_from_file_location('review',ROOT/'tools/review_msu1_postfit.py')
M=importlib.util.module_from_spec(S);S.loader.exec_module(M)
def fixture(mem=7,sys=28,odd='On',phase='0.000000 degrees'):
 lines=['; PLL Usage Summary ;']
 for i,c in [(0,mem),(1,sys)]:
  lines.append(f'; -- ic|mp1|general[{i}].gpll~PLL_OUTPUT_COUNTER ; ;')
  for k,v in [('C Counter',str(c)),('Duty Cycle','50.0000'),('Phase Shift',phase),('C Counter Odd Divider Even Duty Enable',odd if i==0 else 'Off'),('C Counter PH Mux PRST','0'),('C Counter PRST','1')]:
   lines.append(f'; -- {k} ; {v} ;')
 return '\n'.join(lines)
class CounterGuards(unittest.TestCase):
 def parse(self,text):
  with tempfile.TemporaryDirectory() as d:
   f=pathlib.Path(d)/'fit.rpt';f.write_text(text);return M.fitted_counters(f)
 def test_actual_ntsc_shape(self):self.assertEqual(self.parse(fixture())[1:],(7,28))
 def test_actual_pal_shape(self):self.assertEqual(self.parse(fixture(8,32,'Off'))[1:],(8,32))
 def test_reject_odd_duty_disabled(self):
  with self.assertRaisesRegex(RuntimeError,'even-duty'):self.parse(fixture(odd='Off'))
 def test_reject_wrong_ratio(self):
  with self.assertRaisesRegex(RuntimeError,'4:1'):self.parse(fixture(sys=30))
 def test_reject_phase(self):
  with self.assertRaisesRegex(RuntimeError,'phase'):self.parse(fixture(phase='1.000000 degrees'))
 def test_reject_missing_table(self):
  with self.assertRaisesRegex(RuntimeError,'usage table'):self.parse('unrelated')
if __name__=='__main__':unittest.main()
