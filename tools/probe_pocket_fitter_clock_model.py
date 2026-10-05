#!/usr/bin/env python3
"""Run a bounded fitter SDC-context test; never run placement to completion.

Use an isolated map-only project whose final SDC_FILE is the companion probe
SDC. The probe blocks in SDC after writing a validated-edge marker. This parent
then terminates only the child process group it owns. No production QSF includes
the probe. A timeout or absent marker is a failure, not a successful fit.
"""
import argparse, hashlib, json, os, pathlib, re, signal, subprocess, time
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--quartus-fit', required=True)
    p.add_argument('--project', required=True, type=pathlib.Path)
    p.add_argument('--project-name', default='snes_pocket', help='Isolated project revision, including the PLL unit fixture')
    p.add_argument('--output', required=True, type=pathlib.Path)
    a=p.parse_args(); project=a.project.resolve(); out=a.output.resolve()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',a.project_name): p.error('Invalid project name')
    qsf=project/(a.project_name+'.qsf'); probe=ROOT/'tools/probe_pocket_fitter_clock_model.sdc'
    assignments=re.findall(r'^set_global_assignment -name SDC_FILE (.+)$',qsf.read_text(),re.M)
    if not assignments or (project/assignments[-1].strip('"')).resolve()!=probe:
        raise RuntimeError('Final SDC_FILE must be the companion test probe')
    status=subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True)
    if status.strip(): raise RuntimeError('Commit validation code before launching the probe')
    if out.exists(): raise RuntimeError('Refusing to replace existing evidence')
    out.mkdir(parents=True); marker=out/'sdc-context-pass.marker'
    command=[str(pathlib.Path(a.quartus_fit).resolve()),'--read_settings_files=on',
             '--write_settings_files=off',a.project_name]
    record={'command':command,'project':str(project),
            'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
            'qsf_sha256':hashlib.sha256(qsf.read_bytes()).hexdigest(),
            'probe_sha256':hashlib.sha256(probe.read_bytes()).hexdigest(),
            'full_fit':False}
    with (out/'fitter.log').open('w') as log:
        proc=subprocess.Popen(command,cwd=project,stdout=log,stderr=subprocess.STDOUT,
                              env={**os.environ,'POCKET_FITTER_PROBE_MARKER':str(marker)},
                              start_new_session=True)
        deadline=time.monotonic()+120
        try:
            while proc.poll() is None and not marker.exists() and time.monotonic()<deadline:
                time.sleep(.2)
            record['marker']=marker.read_text() if marker.exists() else None
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid,signal.SIGTERM)
                try: proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid,signal.SIGKILL);proc.wait()
            record['process_exit_code']=proc.returncode
    log=(out/'fitter.log').read_text()
    record['core_placement_or_packing_started']=bool(re.search(r'Starting register packing|Fitter placement preparation operations beginning',log))
    record['result']='PASS' if record['marker'] and record['marker'].startswith('PASS ') and not record['core_placement_or_packing_started'] and 'Error (' not in log else 'FAIL'
    (out/'summary.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record,indent=2))
    if record['result']!='PASS': raise SystemExit(1)
if __name__=='__main__':main()
