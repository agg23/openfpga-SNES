"""Exercise the build wrapper's exact final-manifest parser without fitting."""
import hashlib,json,pathlib,re,subprocess,sys,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
CODE=re.search(r'''python3 - "\$run_dir/build.json" "\$status" <<'PY'\n(.*?)\nPY''',(ROOT/'tools/build_msu1.sh').read_text(),re.S)[1]
class FitterReceipt(unittest.TestCase):
 def run_case(self,report,status):
  with tempfile.TemporaryDirectory() as td:
   d=pathlib.Path(td);m=d/'build.json';m.write_text('{}')
   if report is not None:(d/'snes_pocket.fit.rpt').write_text(report)
   p=subprocess.run([sys.executable,'-c',CODE,str(m),str(status)],capture_output=True,text=True)
   self.assertEqual(p.returncode,0,p.stderr);return json.loads(m.read_text())
 def test_actual_settings_and_full_report_hash(self):
  text='; Fitter Initial Placement Seed ; 2 ; 1 ;\n; Fitter Effort ; Standard Fit ; Auto Fit ;\n; Optimize Hold Timing ; All Paths ; All Paths ;\n; Optimize Multi-Corner Timing ; On ; On ;\n'
  r=self.run_case(text,0);self.assertEqual(r['actual_fitter_settings'],{'Fitter Initial Placement Seed':'2','Fitter Effort':'Standard Fit','Optimize Hold Timing':'All Paths','Optimize Multi-Corner Timing':'On'})
  self.assertEqual(r['fitter_settings_report'],{'file':'snes_pocket.fit.rpt','bytes':len(text.encode()),'sha256':hashlib.sha256(text.encode()).hexdigest()})
 def test_missing_report_does_not_invent_settings(self):
  r=self.run_case(None,3);self.assertEqual(r['compile_exit_code'],3);self.assertNotIn('actual_fitter_settings',r)
 def test_actual_value_is_not_default_value(self):
  r=self.run_case('; Fitter Initial Placement Seed ; 7 ; 1 ;\n; Fitter Effort ; Fast Fit ; Auto Fit ;\n',0)
  self.assertEqual(r['actual_fitter_settings'],{'Fitter Initial Placement Seed':'7','Fitter Effort':'Fast Fit'})
if __name__=='__main__':unittest.main()
