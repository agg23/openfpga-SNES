#!/usr/bin/env python3
"""Run real self-checking RTL regressions and optional generic implementation checks.
Never invokes a service, downloads software, or claims a Quartus fit.
"""
import argparse, datetime, json, os, pathlib, shutil, subprocess, sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',default='build/msu1-validation');args=ap.parse_args()
    out=(ROOT/args.output).resolve();out.mkdir(parents=True,exist_ok=True)
    records=[]
    missing_optional=[name for name in ("ghdl","verilator","yosys") if not shutil.which(name)]
    def run(name,command,required=True):
        command=list(map(str,command));p=subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        (out/(name+'.log')).write_text(p.stdout)
        records.append({'name':name,'command':command,'exit_code':p.returncode,'required':required})
        print(('PASS ' if p.returncode==0 else 'FAIL ')+name,flush=True)
        return p.returncode==0
    for tool in ['iverilog','vvp']:
        if not shutil.which(tool):ap.error(tool+' required; install Icarus Verilog first')
    run('iverilog-version',['iverilog','-V'])
    cases=[('tb_msu_registers',['tests/tb_msu_registers.sv','rtl/upstream/chip/MSU1/MSU.sv']),
           ('tb_msu_seek_race',['tests/msu1/tb_msu_seek_race.sv','rtl/upstream/chip/MSU1/MSU.sv','rtl/msu1/msu_data_cache.sv']),
           ('tb_msu_bus_backpressure',['tests/msu1/tb_msu_bus_backpressure.sv','rtl/upstream/chip/MSU1/MSU.sv','rtl/msu1/msu_data_cache.sv']),
           ('tb_msu_data_cache',['tests/tb_msu_data_cache.sv','rtl/msu1/msu_data_cache.sv']),
           ('tb_msu_partial_word',['tests/msu1/tb_msu_partial_word.sv','rtl/msu1/msu_block_cdc.sv']),
           ('tb_msu_transport',['tests/msu1/tb_msu_transport.sv','rtl/msu1/msu_block_cdc.sv','rtl/msu1/msu_data_cache.sv']),
           ('tb_msu_host_masks',['tests/msu1/tb_msu_host_masks.sv','rtl/msu1/msu_pocket_host.sv']),
           ('tb_msu_host_metadata',['tests/msu1/tb_msu_host_metadata.sv','rtl/msu1/msu_pocket_host.sv']),
           ('tb_msu_pocket_host',['tests/msu1/tb_msu_pocket_host.sv','rtl/msu1/msu_pocket_host.sv']),
           ('tb_msu_pocket_integration',[str(p.relative_to(ROOT)) for p in sorted((ROOT/'rtl/msu1').glob('*.sv'))]+['target/pocket/core_bridge_cmd.v','platform/pocket/common.v','tests/msu1/tb_msu_pocket_integration.sv']),
           ('tb_audit_bootstrap',[str(p.relative_to(ROOT)) for p in sorted((ROOT/'rtl/msu1').glob('*.sv'))]+['target/pocket/core_bridge_cmd.v','platform/pocket/common.v','tests/msu1/tb_audit_bootstrap.sv'])]
    cases += [('tb_audit_init_guard',['tests/msu1/tb_audit_init_guard.sv','rtl/msu1/msu_init_guard.sv']),
              ('tb_audit_mount_queue',['tests/msu1/tb_audit_mount_queue.sv','rtl/msu1/msu_mount_cdc.sv']),
              ('tb_audit_reinit_mount',[str(p.relative_to(ROOT)) for p in sorted((ROOT/'rtl/msu1').glob('*.sv'))]+['target/pocket/core_bridge_cmd.v','platform/pocket/common.v','tests/msu1/tb_audit_reinit_mount.sv'])]
    cases += [('tb_audit_soft_reset',[str(p.relative_to(ROOT)) for p in sorted((ROOT/'rtl/msu1').glob('*.sv'))]+['target/pocket/core_bridge_cmd.v','platform/pocket/common.v','tests/msu1/tb_audit_soft_reset.sv'])]
    for name,files in cases:
        binary=out/(name+'.vvp')
        if run(name+'-compile',['iverilog','-g2012','-s',name,'-o',binary,*files]):run(name,['vvp',binary])
    run('python-tests',[sys.executable,'-m','unittest','discover','-s','tests','-p','test_*.py','-v'])
    sv=[str(p.relative_to(ROOT)) for p in sorted((ROOT/'rtl/msu1').glob('*.sv'))]
    if shutil.which('verilator'):
        run('verilator-msu',['verilator','--lint-only','-Wall','-Wno-PINCONNECTEMPTY','-Wno-UNUSEDSIGNAL','--top-module','msu_pocket',*sv])
        run('sdram-equivalence',[sys.executable,'tools/test_sdram_early_equivalence.py','--output',str(out/'sdram-equivalence')])
        run('sdram-negative-control',[sys.executable,'tools/test_sdram_early_equivalence.py','--negative-control','--output',str(out/'sdram-negative-control')])
    if shutil.which('yosys'):
        run('yosys-phase-equivalence',['yosys','-Q','-T','-p','read_verilog -sv tests/msu1/formal_msu_phase.sv; prep -top phase_equiv; sat -verify -prove equivalent 1 -show-inputs'])
        run('yosys-mask-equivalence',['yosys','-Q','-T','-p','read_verilog -sv tests/msu1/formal_msu_masks.sv; prep -top mask_equiv; sat -verify -prove equivalent 1 -show-inputs'])
        run('yosys-msu',['yosys','-Q','-T','-p',f'read_verilog -sv {" ".join(sv)}; hierarchy -check -top msu_pocket; proc; opt; memory_collect; check -assert; stat; write_json {out}/generic-netlist.json'])
    success=all(r['exit_code']==0 for r in records if r['required'])
    summary={'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'dirty':bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True)),
        'passed':success,'checks':records,'not_run':['Quartus synthesis/fitter','TimeQuest timing','complete mixed VHDL/Verilog SNES simulation','Pocket hardware','commercial games']+[name+' checks (tool absent)' for name in missing_optional],
        'limits':'Behavioral APF host and mf_datatable RAM model used only in testbench; existing core_bridge_cmd is real RTL. Generic Yosys checks are not Intel resources or timing.'}
    (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    return 0 if success else 1
if __name__=='__main__':sys.exit(main())
