#!/usr/bin/env python3
"""Locked read-only audit of an already fitted source-identified SDRAM design.

Never runs map/fit, changes SDC, or overwrites the compiler's original reports.
"""
import argparse,datetime,fcntl,hashlib,json,pathlib,re,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--project',type=pathlib.Path,required=True)
p.add_argument('--quartus-sta',type=pathlib.Path,required=True);p.add_argument('--out',type=pathlib.Path,required=True)
p.add_argument('--fit-report',type=pathlib.Path,required=True)
a=p.parse_args();project=a.project.resolve();out=a.out.resolve();fit=a.fit_report.resolve()
if not (project/'snes_pocket.qpf').is_file():p.error('--project must be the directory containing snes_pocket.qpf')
if not fit.is_file() or not re.search(r'Fitter Status\s*;\s*Successful',fit.read_text(errors='replace')):
 p.error('Require a completed successful fit report; no post-map fallback is allowed')
out.mkdir(parents=True,exist_ok=False)
root=project.parent
protected=[project/'snes_pocket.qsf',project/'snes_pocket.sdc',fit,
 root/'target/pocket/core_constraints.sdc',root/'target/pocket/pocket_clock_model.sdc',
 root/'rtl/memory_ready/sdram_single_request.sv',root/'rtl/mister_top/SNES.sv']
protected += list(fit.parent.glob('*.sta.rpt'))
def digest():return {str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in protected}
lock_path=project/'output_files/.msu1-build.lock'
with lock_path.open('r') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 before=digest();revision=subprocess.check_output(['git','-C',root,'rev-parse','HEAD'],text=True).strip()
 command=[str(a.quartus_sta.resolve()),'-t',str(ROOT/'tools/review_standard_sdram_io.tcl'),str(project),str(out)]
 result=subprocess.run(command,cwd=out,text=True,capture_output=True,timeout=900)
 log=result.stdout+result.stderr;(out/'query.log').write_text(log)
 after=digest();unchanged=before==after
 status=(out/'overview.tsv').read_text() if (out/'overview.tsv').exists() else ''
 passed=result.returncode==0 and 'EXTRACTED_NOT_BOARD_SIGNOFF' in status and unchanged
 passed=passed and '332088' not in log and '332199' not in log
 receipt={'source_revision':revision,'command':command,'passed':passed,'protected_unchanged':unchanged,
  'protected_sha256':before,'captured_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
  'scope':'Existing fitted database, four-corner raw path extraction. No new fit, SDC mutations, or board signoff.'}
 (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 if not passed:raise SystemExit('Extraction incomplete or rejected; inspect '+str(out/'query.log'))
 print('PASS read-only extraction; original QSF/SDC/RTL/fit/STA reports unchanged; NOT BOARD SIGNOFF')
