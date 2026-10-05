#!/usr/bin/env python3
"""Opt-in conditional STA on an existing fit, with explicit assumption provenance.

Does not enable the candidate in production, run fit, or claim board signoff.
All PCB flight and extra-margin numbers are mandatory; none have defaults.
"""
import argparse,collections,csv,fcntl,hashlib,json,pathlib,re,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--project',type=pathlib.Path,required=True)
p.add_argument('--quartus-sta',type=pathlib.Path,required=True);p.add_argument('--out',type=pathlib.Path,required=True)
p.add_argument('--fit-report',type=pathlib.Path,required=True);p.add_argument('--assumptions',type=pathlib.Path,required=True)
p.add_argument('--compare',type=pathlib.Path,help='Prior summary using the same timing/board assumptions')
a=p.parse_args();project=a.project.resolve();out=a.out.resolve();fit=a.fit_report.resolve();root=project.parent
if not fit.is_file() or not re.search(r'Fitter Status\s*;\s*Successful',fit.read_text(errors='replace')):p.error('Completed successful fitted report required')
assumptions=json.loads(a.assumptions.read_text())
required={'evidence','root_clock','expected_source','pcb_clock_min','pcb_clock_max','pcb_read_min','pcb_read_max','pcb_command_min','pcb_command_max','pcb_write_min','pcb_write_max','tac_max','toh_min','tis','tih','extra_setup_margin','extra_hold_margin'}
if set(assumptions)!=required:p.error('Every explicit board/device/margin field is required; no defaults')
if not isinstance(assumptions['evidence'],str) or not assumptions['evidence'].strip():p.error('Assumption provenance required')
rtl=(root/'rtl/memory_ready/sdram_single_request.sv').read_text()
if not re.search(r'READ_CAPTURE\s*=\s*4',rtl) or "13'h230" not in rtl or 'read_data <= dq_sample' not in rtl:
 p.error('CL3/BL1/READ+4 pipeline contract changed; revalidate the edge model')
out.mkdir(parents=True,exist_ok=False)
def tcl_word(s):return '"'+str(s).replace('\\','\\\\').replace('$','\\$').replace('[','\\[').replace('"','\\"').replace('\n','\\n')+'"'
(out/'assumptions.json').write_text(json.dumps(assumptions,indent=2)+'\n')
(out/'assumptions.tcl').write_text('set io_assumptions [dict create '+' '.join(tcl_word(k)+' '+tcl_word(v) for k,v in assumptions.items())+']\n')
protected=[project/'snes_pocket.qsf',project/'snes_pocket.sdc',root/'target/pocket/core_constraints.sdc',root/'target/pocket/pocket_clock_model.sdc',root/'rtl/memory_ready/sdram_single_request.sv',root/'rtl/mister_top/SNES.sv',fit,*fit.parent.glob('*.sta.rpt')]
def digest():return {str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in protected}
with (project/'output_files/.msu1-build.lock').open('r') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 before=digest()
 cmd=[a.quartus_sta.resolve(),'-t',ROOT/'tools/check_standard_sdram_io_scenario.tcl',project,out,out/'assumptions.tcl']
 r=subprocess.run(list(map(str,cmd)),cwd=out,text=True,capture_output=True,timeout=900)
 log=r.stdout+r.stderr;(out/'query.log').write_text(log)
 after=digest()
 if r.returncode or 'CONDITIONAL_SCENARIO_COMPLETE_NOT_BOARD_SIGNOFF' not in log or '332088' in log or '332199' in log or before!=after:
  raise RuntimeError('Conditional extraction incomplete or original design/report changed; inspect query.log')
 model=dict(line.split('\t',1) for line in (out/'conditional-model.tsv').read_text().splitlines())
 period=float(model['period_ns']);rows=list(csv.DictReader((out/'conditional-slacks.tsv').open(),delimiter='\t'))
 groups=collections.defaultdict(list)
 for row in rows:groups[row['corner'],row['group'],row['analysis']].append(row)
 worst={}
 for corner in ('slow85','slow0','fast85','fast0'):
  for group in ('read','command','write','write_data','output_enable'):
   for analysis in ('setup','hold'):
    selected=groups[corner,group,analysis]
    if not selected:raise RuntimeError('Missing corner/group/analysis')
    expected=period*((1.5 if analysis=='setup' else .5) if group=='read' else (.5 if analysis=='setup' else -.5))
    if any(abs(float(row['relationship'])-expected)>.0011 for row in selected):raise RuntimeError('Wrong edge relationship')
    worst['/'.join((corner,group,analysis))]=min(selected,key=lambda row:float(row['slack']))
 summary={'status':'CONDITIONAL_STA_NOT_BOARD_SIGNOFF','source_revision':subprocess.check_output(['git','-C',root,'rev-parse','HEAD'],text=True).strip(),'period_ns':period,'assumptions':assumptions,'protected_unchanged':True,'protected_sha256':before,'worst':worst}
 if a.compare:
  old=json.loads(a.compare.read_text());ignore={'evidence','root_clock','expected_source'}
  if {k:v for k,v in old['assumptions'].items() if k not in ignore}!={k:v for k,v in assumptions.items() if k not in ignore} or old['period_ns']!=period:raise RuntimeError('Baseline used different timing/board assumptions')
  summary['baseline']=str(a.compare.resolve());summary['slack_delta_ns']={key:float(row['slack'])-float(old['worst'][key]['slack']) for key,row in worst.items()}
 (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
 for key,row in worst.items():print(key,row['slack'],row['from'],'->',row['to'])
 print('Complete conditional extraction; production QSF/SDC/RTL/reports unchanged; NOT BOARD SIGNOFF')
