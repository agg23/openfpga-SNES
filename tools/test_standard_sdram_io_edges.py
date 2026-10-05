#!/usr/bin/env python3
"""Native post-map clock-relation test; performs no fit and no board signoff."""
import argparse,csv,json,pathlib,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--quartus-bin',required=True,type=pathlib.Path)
p.add_argument('--out',required=True,type=pathlib.Path);a=p.parse_args()
q=a.quartus_bin.resolve();out=a.out.resolve();out.mkdir(parents=True,exist_ok=False)
project=out/'unit';project.mkdir();reports=out/'reports';reports.mkdir()
(project/'io_unit.qpf').write_text('QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "io_unit"\n')
(project/'io_unit.qsf').write_text(f'''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY standard_io_window_unit
set_global_assignment -name SYSTEMVERILOG_FILE "{ROOT/'tests/timing/standard_io_window_unit.sv'}"
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_instance_assignment -name VIRTUAL_PIN ON -to *
''')
(project/'map.tcl').write_text('load_package flow\nproject_open io_unit\nexecute_module -tool map\nproject_close\n')
checks=[]
def run(name,cmd,cwd=project):
 r=subprocess.run(list(map(str,cmd)),cwd=cwd,text=True,capture_output=True,timeout=300)
 (out/(name+'.log')).write_text(r.stdout+r.stderr)
 if r.returncode or 'Error (' in r.stdout+r.stderr:raise RuntimeError(name+' failed; inspect '+str(out/(name+'.log')))
 if '332088' in r.stdout+r.stderr:raise RuntimeError('source clock latency lost')
run('map-only',[q/'quartus_sh','-t',project/'map.tcl'])
for period in (9.312,9.392):
 for mode in ('ordinary','cl3_window','restored_hold'):
  run(f'edge-{period}-{mode}',[q/'quartus_sta','-t',ROOT/'tests/timing/check_standard_io_window_edges.tcl',project,reports,period,mode])
  rows=list(csv.DictReader((reports/f'relations-{period}-{mode}.tsv').open(),delimiter='\t'))
  pairs={(row['label'],row['analysis']):float(row['relationship']) for row in rows}
  expected_read_setup=period*(.5 if mode=='ordinary' else 1.5)
  expected_read_hold=period*(.5 if mode=='cl3_window' else -.5)
  wanted={('read','setup'):expected_read_setup,('read','hold'):expected_read_hold,
          ('write','setup'):period*.5,('write','hold'):-period*.5,
          ('internal','setup'):period,('internal','hold'):0.0}
  for key,value in wanted.items():
   if abs(pairs[key]-value)>.0011:raise AssertionError(f'{period}/{mode} {key}: {pairs[key]} != {value}')
  checks.append(dict(period_ns=period,mode=mode,relationships={f'{k[0]}_{k[1]}':v for k,v in pairs.items()},passed=True))
  print('PASS',period,mode,pairs)
(out/'summary.json').write_text(json.dumps({'checks':checks,'scope':'Native post-map relationship proof only; synthetic zero PCB flight; no fit, routed budget, or hardware claim'},indent=2)+'\n')
