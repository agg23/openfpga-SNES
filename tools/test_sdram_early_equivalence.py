#!/usr/bin/env python3
"""Compare the real modified controller against unchanged ad9fed4e RTL.
No Quartus build, SDC changes, or external SDRAM timing sign-off is performed.
"""
import argparse,pathlib,shutil,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
def normalize_dq(source):
 """Verilator cannot lower nonblocking assignments to an inout reg.
 Use an equivalent registered output plus registered output-enable in test
 copies only. The complete controller state/read logic is left unchanged.
 """
 replacements={
  'inout  reg [15:0] SDRAM_DQ':'inout wire [15:0] SDRAM_DQ',
  '\tlocalparam RASCAS_DELAY':'\treg [15:0] test_dq_out;\n\treg test_dq_oe;\n\tassign SDRAM_DQ = test_dq_oe ? test_dq_out : 16\'hzzzz;\n\n\tlocalparam RASCAS_DELAY',
  "SDRAM_DQ <= 'Z;":"test_dq_oe <= 0;",
  'begin SDRAM_DQ <= d; end':'begin test_dq_out <= d; test_dq_oe <= 1; end',
  "\talways @(posedge clk) begin\n\t\treg [4:0] reset = 5'h1f;\n\t\treg init_old = 0;":
  "\treg [4:0] reset = 5'h1f;\n\treg init_old = 0;\n\talways @(posedge clk) begin",
 }
 for old,new in replacements.items():
  assert source.count(old)==1,(old,source.count(old))
  source=source.replace(old,new)
 return source
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',default='build/sdram-early-equivalence')
 modes=p.add_mutually_exclusive_group()
 modes.add_argument('--negative-control',action='store_true',help='require the miter to reject a test-copy-only early-data corruption')
 modes.add_argument('--startup-phase-counterexample',action='store_true',help='require the unconditional phase2 assertion to fail for a held startup request')
 modes.add_argument('--async-host-gate-counterexample',action='store_true',help='require the phase2 assertion to fail for a host-gated read after warmup')
 a=p.parse_args()
 out=(ROOT/a.output).resolve();out.mkdir(parents=True,exist_ok=True)
 if not shutil.which('verilator'):p.error('verilator is required')
 original=subprocess.check_output(['git','show','ad9fed4e:rtl/upstream/sdram.sv'],cwd=ROOT,text=True)
 assert original.startswith('module sdram\n')
 ref=out/'sdram_reference.sv';ref.write_text(normalize_dq(original.replace('module sdram\n','module sdram_reference\n',1)))
 candidate_source=(ROOT/'rtl/upstream/sdram.sv').read_text()
 if a.negative_control:
  needle='dout_buf[0] <= SDRAM_DQ;'
  assert candidate_source.count(needle)==1
  candidate_source=candidate_source.replace(needle,"dout_buf[0] <= 16'h0000;")
 candidate=out/'sdram_candidate.sv';candidate.write_text(normalize_dq(candidate_source))
 test_source=(ROOT/'tests/timing/tb_sdram_early_equivalence.sv').read_text()
 if a.startup_phase_counterexample:
  for old,new in [('reg [23:0] addr0=0,addr1=0;','reg [23:0] addr0=2,addr1=0;'),
                  ('reg wr0=0,rd0=0,word0=0','reg wr0=0,rd0=1,word0=0'),
                  ('bit phase_check=0;','bit phase_check=1;')]:
   assert test_source.count(old)==1,old
   test_source=test_source.replace(old,new)
 if a.async_host_gate_counterexample:
  old='  phase_check=1;\n  for(integer i=0;i<1024;i++)begin'
  new='''  phase_check=1;
  // rd0 rising here models cart_download falling while client_read/RFSH=1.
  // The controller is warm, so this is not the startup-only counterexample.
  while(cycle%4!=1)tick();
  rd0=1;addr0=2;
  repeat(12)tick();
  $fatal(1,"host-gate phase counterexample was not detected");
  for(integer i=0;i<1024;i++)begin'''
  assert test_source.count(old)==1
  test_source=test_source.replace(old,new)
 test=out/'tb_sdram_generated.sv';test.write_text(test_source)
 command=['verilator','--binary','--timing','--assert','-j','1','-Wno-fatal','--top-module','tb_sdram_early_equivalence','--Mdir',str(out/'obj'),str(test),str(candidate),str(ref)]
 build=subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (out/'compile.log').write_text(build.stdout)
 if build.returncode: print(build.stdout);return build.returncode
 run=subprocess.run([str(out/'obj/Vtb_sdram_early_equivalence')],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (out/'simulation.log').write_text(run.stdout);print(run.stdout,end='')
 if a.negative_control:
  caught=run.returncode!=0 and 'equivalence mismatch' in run.stdout
  print('PASS negative control rejected early-data corruption' if caught else 'FAIL negative control was not caught')
  return 0 if caught else 1
 if a.startup_phase_counterexample:
  caught=run.returncode!=0 and 'unexpected port0 capture phase cycle=197' in run.stdout
  print('PASS startup counterexample: held read returns at phase1, cycle197' if caught else 'FAIL startup counterexample was not reproduced')
  return 0 if caught else 1
 if a.async_host_gate_counterexample:
  caught=run.returncode!=0 and 'unexpected port0 capture phase cycle=527' in run.stdout
  print('PASS warm host-gate counterexample: read returns at phase3, cycle527' if caught else 'FAIL host-gate counterexample was not reproduced')
  return 0 if caught else 1
 return run.returncode
if __name__=='__main__':sys.exit(main())
