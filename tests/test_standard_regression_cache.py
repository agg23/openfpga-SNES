"""Orchestrator-only unit tests, using mocked jobs; these are NOT RTL evidence."""
import contextlib,importlib.util,io,json,pathlib,subprocess,sys,tempfile,types,unittest
from unittest import mock
SCRIPT=pathlib.Path(__file__).resolve().parents[1]/'tools/run_standard_memory_regression.py'
class GeneratedCacheTests(unittest.TestCase):
 def exercise(self,enabled,fail_first=False):
  spec=importlib.util.spec_from_file_location('qualification_cache_unit',SCRIPT);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  with tempfile.TemporaryDirectory()as td:
   r=pathlib.Path(td);(r/'build').mkdir();old=r/'build/preexisting.gch';old.write_bytes(b'keep old cache')
   vendor=r/'vendor';vendor.mkdir();(vendor/'altera_mf.v').write_text('// mocked unit fixture only\n')
   out=r/'evidence';new=r/'build/generated.gch';exe=r/'build/generated.vvp';calls=[]
   def job(*args,**kwargs):
    self.assertEqual(kwargs['env']['TMPDIR'],str(out/'temporary'));self.assertTrue((out/'temporary').is_dir())
    calls.append(args);new.write_bytes(b'new rebuildable cache');exe.write_bytes(b'keep executable');return types.SimpleNamespace(returncode=int(fail_first and len(calls)==1))
   def git(cmd,**kwargs):return 'mock-commit\n'if'rev-parse'in cmd else ''
   argv=['qualification','--only','memory','--output',str(out),'--vendor-sim-dir',str(vendor)]+(['--discard-generated-pch']if enabled else [])
   with mock.patch.object(m,'ROOT',r),mock.patch.object(m,'digest_sources',return_value={'fixture':'stable'}),mock.patch.object(m.shutil,'which',return_value='/mock/tool'),mock.patch.object(m.subprocess,'run',side_effect=job),mock.patch.object(m.subprocess,'check_output',side_effect=git),mock.patch.object(sys,'argv',argv),contextlib.redirect_stdout(io.StringIO()):
    result=m.main()
   s=json.loads((out/'summary.json').read_text());self.assertTrue(old.exists());self.assertTrue(exe.exists());self.assertEqual(result,int(fail_first))
   if enabled and not fail_first:
    self.assertFalse(new.exists());self.assertEqual(len(s['generated_cache_cleanup']),9)
    self.assertTrue(all(x['sha256']and x['bytes']==21 for x in s['generated_cache_cleanup']))
   else:self.assertTrue(new.exists());self.assertEqual(s['generated_cache_cleanup'],[])
 def test_new_headers_only(self):self.exercise(True)
 def test_disabled_preserves_headers(self):self.exercise(False)
 def test_failure_disables_further_cleanup(self):self.exercise(True,True)
if __name__=='__main__':unittest.main()
