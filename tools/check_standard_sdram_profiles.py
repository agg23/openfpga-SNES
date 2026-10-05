#!/usr/bin/env python3
"""Native Quartus assignment-only profile switching; compile entry points removed.

Runs fresh profiles plus every pairwise switch in isolated project directories.
Uses the production generate.tcl but intercepts execute_flow; no map/fit/STA.
"""
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
PROFILES=['ntsc','pal','ntsc_spc','none','none_pal','msu_ntsc','msu_pal',
          'msu_standard_ntsc','msu_standard_pal','standard_ntsc_spc']
FROM='core_top:ic|MAIN_SNES:snes|main:main|SNES:SNES|DO[2]~6'
TO='core_top:ic|MAIN_SNES:snes|main:main|MSU:MSU|resume_loop_index[22]~0'
VALUE='msu_resume_din2_local'

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--quartus-sh',type=Path,required=True)
    p.add_argument('--output',type=Path,default=Path('build/standard-profile-check'))
    a=p.parse_args();out=a.output.resolve();q=a.quartus_sh.resolve()
    if out.exists():p.error('Output already exists; refusing to replace evidence')
    out.mkdir(parents=True); checks=[]
    def check(condition,message):
        if not condition:raise AssertionError(message)
        checks.append(message)
    def prepare(name):
        d=out/name;d.mkdir()
        for file in ['generate.tcl','projects/snes_pocket.qpf','projects/snes_pocket.qsf',
                     'projects/snes_pocket.qip','projects/snes_pocket.sdc',
                     'projects/msu_resume_din2_duplicate.qsf']:
            destination=d/file;destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT/file,destination)
        # Source trees are read-only links; only each isolated projects/QSF is exported.
        for directory in ['platform','target','rtl']:
            (d/directory).symlink_to(ROOT/directory,target_is_directory=True)
        return d
    def run(d,profile,label,seed=None):
        log=out/(label+'.log');snap=out/(label+'.assignments.tcl')
        result=subprocess.run([str(q),'-t',str(ROOT/'tests/timing/generate_profile_case.tcl'),str(d),profile,str(snap),str(seed) if seed else ''],env=os.environ,capture_output=True,text=True,timeout=40)
        log.write_text(result.stdout+result.stderr)
        check(result.returncode==0,f'{label}: native API success')
        check('Warning (' not in log.read_text() and 'Error (' not in log.read_text(),f'{label}: no native warnings/errors')
        check('FAKE_FLOW_ONLY -compile; no compiler stage launched' in log.read_text(),f'{label}: compile intercepted')
        return set(snap.read_text().splitlines())
    fresh={}
    for profile in PROFILES:
        fresh[profile]=run(prepare('fresh-'+profile),profile,'fresh-'+profile)
    def param(snapshot,name):
        values=[row.split()[3] for row in snapshot if row.startswith('set_parameter -name '+name+' ')]
        check(len(values)==1,f'{name}: exactly one parameter')
        return values[0].strip("'")
    for profile,rows in fresh.items():
        standard=profile in ['msu_standard_ntsc','msu_standard_pal','standard_ntsc_spc']
        msu=profile.startswith('msu_')
        check(param(rows,'USE_STANDARD_SDRAM')==str(int(standard)),profile+': explicit standard flag')
        check(param(rows,'USE_MSU_POCKET')==str(int(msu)),profile+': explicit MSU top flag')
        check(param(rows,'USE_MSU')==str(int(msu)),profile+': explicit MSU core flag')
        duplicates=[row for row in rows if 'DUPLICATE_ATOM' in row]
        check(len(duplicates)==int(profile=='msu_ntsc'),profile+': only original NTSC duplicate enabled')
        ioe=[row for row in rows if 'STANDARD_SDRAM_IOE_CANDIDATE_V1' in row]
        check(len(ioe)==(70 if standard else 0),profile+': exact standard-only I/O packing count')
        state=[row for row in rows if 'STANDARD_WRAM_STATE_DATA_ONLY_V1' in row]
        check(len(state)==(8 if standard else 0),profile+': exact standard-only WRAM state count')
        palfit=profile=='msu_standard_pal'
        fitrows=[row for row in rows if 'STANDARD_PAL_FIT_SEED2_V1' in row]
        check(len(fitrows)==(2 if palfit else 0),profile+': exact PAL-only fitter experiment count')
        seedrows=[r for r in rows if r.startswith('set_global_assignment -name SEED ')]
        effortrows=[r for r in rows if r.startswith('set_global_assignment -name FITTER_EFFORT ')]
        check(len(seedrows)==1 and bool(re.search(r'-name SEED '+('2' if palfit else '1')+r'(?:\s|$)',seedrows[0])),profile+': exact fitter seed')
        check(len(effortrows)==1 and ('STANDARD FIT' if palfit else 'AUTO FIT') in effortrows[0],profile+': exact fitter effort')
        if standard:
            for bit in range(8):
                check(any('ic|snes|wram|state['+str(bit)+']' in row and '-name ALLOW_SYNCH_CTRL_USAGE OFF' in row for row in state),profile+': exact WRAM state bit '+str(bit))
            check(all('|aram|' not in row for row in state),profile+': ARAM untouched')

    for standard,old in [('msu_standard_ntsc','msu_ntsc'),('msu_standard_pal','msu_pal'),('standard_ntsc_spc','ntsc_spc')]:
        unchanged=lambda rows:{r for r in rows if 'USE_STANDARD_SDRAM' not in r and 'DUPLICATE_ATOM' not in r and 'STANDARD_SDRAM_IOE_CANDIDATE_V1' not in r and 'STANDARD_WRAM_STATE_DATA_ONLY_V1' not in r and not r.startswith('set_global_assignment -name SEED ') and not r.startswith('set_global_assignment -name FITTER_EFFORT ')}
        check(unchanged(fresh[standard])==unchanged(fresh[old]),standard+': all other effective assignments match '+old)
    for before in PROFILES:
        d=prepare('switch-from-'+before)
        for after in PROFILES:
            # Reset to known source before each destination, checking idempotence too.
            run(d,before,f'{before}-to-{after}-source')
            actual=run(d,after,f'{before}-to-{after}-destination')
            check(actual==fresh[after],f'{before} -> {after}: exact fresh effective assignment set')
    d=prepare('sentinels');run(d,'msu_ntsc','sentinels-source')
    seed=d/'seed.tcl'
    seed.write_text(f'''set_instance_assignment -name DUPLICATE_ATOM {VALUE} -from {{{FROM}}} -to unrelated_dest
set_instance_assignment -name DUPLICATE_ATOM {VALUE} -from unrelated_source -to {{{TO}}}
set_instance_assignment -name DUPLICATE_ATOM other_value -from {{{FROM}}} -to {{{TO}}}
''')
    rows=run(d,'msu_standard_ntsc','sentinels-standard',seed)
    duplicates={r for r in rows if 'DUPLICATE_ATOM' in r}
    check(len(duplicates)==3,'Exact cleanup preserves different source/destination/value sentinels')
    check(all(VALUE not in r or 'unrelated_' in r for r in duplicates),'Stale original exact DUPLICATE_ATOM is absent')
    for pattern in ['*.map.rpt','*.fit.rpt','*.sta.rpt','*.rbf','*.sof']:
        check(not list(out.rglob(pattern)),'No compiler output '+pattern)
    summary={'status':'PASS','compiled':False,'profile_count':len(PROFILES),'pairwise_switch_count':len(PROFILES)**2,'check_count':len(checks),'checks':checks}
    (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps({k:v for k,v in summary.items() if k!='checks'}))
if __name__=='__main__':main()
