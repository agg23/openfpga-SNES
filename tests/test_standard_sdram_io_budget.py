import importlib.util
from pathlib import Path
import unittest
S=importlib.util.spec_from_file_location('budget',Path(__file__).resolve().parents[1]/'tools/standard_sdram_io_budget.py')
M=importlib.util.module_from_spec(S);S.loader.exec_module(M)
class ExternalBudgetTests(unittest.TestCase):
    def test_published_symbolic_windows(self):
        for region,lower,upper in [('ntsc',2.156085247,8.468255742),('pal',2.198945604,8.596836811)]:
            x=M.calculate(region)
            self.assertAlmostEqual(x['read_R_min_required_before_ff_hold_and_uncertainty_ns'],lower,places=8)
            self.assertAlmostEqual(x['read_R_max_allowed_before_ff_setup_and_uncertainty_ns'],upper,places=8)
            self.assertNotIn('conditional_evaluations',x)
            self.assertEqual(x['status'],'NOT_BOARD_SIGNOFF')
    def fixture(self):
        return {'evidence':'Synthetic arithmetic fixture only, never board evidence',
                'setup_uncertainty_ns':.1,'hold_uncertainty_ns':.2,
                'read':{'R_min_ns':3,'R_max_ns':4,'capture_ff_setup_ns':.3,'capture_ff_hold_ns':.4},
                'command':{'W_min_ns':-2,'W_max_ns':2},'write':{'W_min_ns':-1,'W_max_ns':1}}
    def test_conditional_arithmetic_includes_uncertainty_ff_requirements(self):
        x=M.calculate('ntsc',routed=self.fixture());r=x['conditional_evaluations']['read']
        self.assertAlmostEqual(r['conditional_setup_slack_ns'],8.468255742-4-.3-.1,places=8)
        self.assertAlmostEqual(r['conditional_hold_slack_ns'],3-2.156085247-.4-.2,places=8)
        self.assertIn('NOT_BOARD_SIGNOFF',x['status'])
    def test_bad_incomplete_inverted_or_nonfinite_budget_rejected(self):
        cases=[]
        x=self.fixture();x['evidence']='';cases.append(x)
        x=self.fixture();del x['read']['R_min_ns'];cases.append(x)
        x=self.fixture();x['read']['R_min_ns']=5;cases.append(x)
        x=self.fixture();x['setup_uncertainty_ns']=-.1;cases.append(x)
        x=self.fixture();x['write']['W_max_ns']=float('nan');cases.append(x)
        x=self.fixture();x['write']['W_min_ns']=4;cases.append(x)
        for x in cases:
            with self.assertRaises(ValueError):M.calculate('ntsc',routed=x)
    def test_device_changes_are_explicit(self):
        x=M.calculate('ntsc',{'cl3_period_min_ns':10})
        self.assertFalse(x['cl3_period_requirement_met'])
        with self.assertRaises(ValueError):M.calculate('ntsc',{'unknown':1})
if __name__=='__main__':unittest.main()
