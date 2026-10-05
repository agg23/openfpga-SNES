#!/usr/bin/env python3
"""Run software-only qualification of the standard-refresh experimental branch.

Runs actual checked-in RTL/oracles, records exact source hashes and terminal
outcomes, and never substitutes a quick suite or FPGA fit for missing checks.
Native Quartus compilation and physical hardware are separate evidence.
"""
from __future__ import annotations
import argparse,contextlib,datetime,fcntl,gzip,hashlib,json,os,pathlib,shutil,subprocess,sys,time
ROOT=pathlib.Path(__file__).resolve().parents[1]
FAMILIES=['msu','memory','download','chips','bsx','sdd1','sdram','audit']

class QualificationBusyError(RuntimeError):
    pass

@contextlib.contextmanager
def qualification_lock(root):
    """Serialize aggregate runs sharing one checkout's build/cache directories."""
    lock_path=root/'build/.standard-memory-regression.lock'
    lock_path.parent.mkdir(parents=True,exist_ok=True)
    # Keep this file: unlinking a locked inode would allow a second live lock.
    with lock_path.open('a') as lock:
        try:
            fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise QualificationBusyError('NOT RUN: another standard-memory qualification is already running in this checkout; wait for it to finish') from error
        try:
            yield
        finally:
            fcntl.flock(lock.fileno(),fcntl.LOCK_UN)

def digest_sources():
    # Generated logs/VCD/JSON/executables can live under a test's results dir.
    # Hash only tracked source/fixture files, not qualification output artifacts.
    names=subprocess.check_output(['git','ls-files','rtl','target/pocket','platform/pocket','support','pkg','tests','tools'],cwd=ROOT,text=True).splitlines()
    suffixes={'.v','.sv','.vhd','.py','.sh','.tcl','.sdc','.qip','.qsf','.mif','.hex','.mem','.asm','.s','.inc','.json'}
    files=[ROOT/n for n in names if pathlib.Path(n).suffix.lower() in suffixes and
           'results' not in pathlib.Path(n).parts and pathlib.Path(n).name!='results.json']
    return {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=pathlib.Path,default=ROOT/'build/standard-memory-regression')
    ap.add_argument('--only',nargs='+',choices=FAMILIES,default=FAMILIES)
    ap.add_argument('--vendor-sim-dir',type=pathlib.Path,default=pathlib.Path(os.environ.get('QUARTUS_SIM_LIB',ROOT.parent/'toolchain/intelFPGA_lite/21.1/quartus/eda/sim_lib')))
    ap.add_argument('--discard-generated-pch',action='store_true',help='After each successful check, remove only newly created rebuildable .gch caches, recording hashes; preserve logs, executables and pre-existing files')
    args=ap.parse_args()
    try:
        with qualification_lock(ROOT):
            return run_qualification(args,ap)
    except QualificationBusyError as error:
        ap.error(str(error))
def run_qualification(args,ap):
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    def pch_files():
        return {p.resolve() for base in (ROOT/'build',out) if base.exists() for p in base.rglob('*.gch') if p.is_file()}
    preexisting_pch=pch_files()
    cache_cleanup_safe=True
    # Refuse silently replacing an earlier audit trail.
    if (out/'summary.json').exists():ap.error('output already has summary.json; use a fresh output directory')
    required=['iverilog','vvp','ghdl','verilator','yosys','g++','make','git']
    missing=[x for x in required if not shutil.which(x)]
    if missing:ap.error('NOT RUN: missing required tools: '+', '.join(missing))
    if not (args.vendor_sim_dir/'altera_mf.v').is_file():ap.error('NOT RUN: approved Quartus vendor models absent; pass --vendor-sim-dir')
    env=os.environ.copy();env['QUARTUS_SIM_LIB']=str(args.vendor_sim_dir.resolve())
    # Keep temporary compiler caches off RAM-backed /tmp on constrained hosts.
    temporary=out/'temporary';temporary.mkdir(exist_ok=True);env['TMPDIR']=str(temporary)
    env['SA1_TEST_ARTIFACTS']=str(out/'sa1')
    env['SDD1_BUILD_DIR']=str(out/'sdd1-work')
    before=digest_sources();records=[]
    start=datetime.datetime.now(datetime.timezone.utc).isoformat()
    summary={'started_utc':start,'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
             'git_status_before':subprocess.check_output(['git','status','--short'],cwd=ROOT,text=True).splitlines(),'selected_families':args.only,'source_sha256':before,'checks':records,'not_applicable':[],
             'discard_generated_pch':args.discard_generated_pch,'generated_cache_cleanup':[],
             'not_run':['native Quartus synthesis/fit/STA (separate build evidence)','whole-system commercial-game validation','Pocket hardware','PCB trace measurement'],
             'limits':'Component and directed integration regressions use documented RAM/APF/SDRAM simulation models. They are not proof of exhaustive game compatibility or physical timing closure.'}
    def save():
        (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    def run(name,cmd,timeout=1800,localenv=None):
        nonlocal cache_cleanup_safe
        begin=time.monotonic();path=out/(name+'.log');print('RUN '+name,flush=True)
        with path.open('w') as log:
            log.write('$ '+' '.join(map(str,cmd))+'\n');log.flush()
            try:
                r=subprocess.run(list(map(str,cmd)),cwd=ROOT,env=localenv or env,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
                code=r.returncode;error=None
            except subprocess.TimeoutExpired:
                code=None;error='timeout; not a pass'
        records.append({'name':name,'command':list(map(str,cmd)),'exit_code':code,'error':error,'passed':code==0,
                        'seconds':round(time.monotonic()-begin,3),'log':str(path.relative_to(out))})
        if code!=0:cache_cleanup_safe=False
        if cache_cleanup_safe and args.discard_generated_pch:
            # Only this successful subprocess's newly generated, rebuildable
            # compiler headers. Never run this cleanup after a timeout/failure.
            for p in sorted(pch_files()-preexisting_pch):
                row={'after_check':name,'path':str(p),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
                p.unlink();summary['generated_cache_cleanup'].append(row)
        print(('PASS ' if code==0 else 'FAIL ')+name,flush=True);save();return code==0
    py=sys.executable
    execution_finished=False
    try:
        if 'msu' in args.only:
            run('msu-full',[py,'tools/test_msu1.py','--output',out/'msu'])
            run('msu-negative',[py,'tools/test_msu1_negative.py','--output',out/'msu-negative'])
            # These are archived optimization experiments, not current core RTL.
            # Run only when their required implementation is actually present.
            if (ROOT/'rtl/upstream/chip/DSP/DSP_LHReadSelect.vhd').exists():
                run('dma-guards',[py,'tools/test_dlh_dma_guards.py','--output',out/'dma-guards'])
                run('dma-equivalence',[py,'tools/test_dlh_dma_equivalence.py','--output',out/'dma-equivalence','--verify-reference-git'])
            else:
                summary['not_applicable'].append('Archived DSP_LHReadSelect/DMA-view optimization tests: implementation absent from this branch; actual current SCPU/DMA tests still run')
        if 'memory' in args.only:
            run('memory-integration',[py,'tools/test_memory_ready_integration.py','--out',out/'memory'])
            run('wram-real-cpu-timing',[py,'tests/wram_timing/run.py','--out',out/'wram-timing'],timeout=2400)
            run('wram-read-predecode',[py,'tests/wram_timing/check_predecode.py','--out',out/'wram-predecode'])
            run('aram-source-contract',[py,'tests/aram_timing/check_source_contract.py'])
            run('aram-window',[py,'tests/aram_timing/prove_window.py','--output',out/'aram-window.json'])
            run('aram-real-apu',[py,'tests/aram_timing/run.py','--out',out/'aram'],timeout=3600)
            run('aram-vhdl-normalization',[py,'tests/aram_timing/check_vhdl_normalization.py','--out',out/'aram'],timeout=600)
            run('owner-liveness',[py,'tools/test_owner_liveness.py','--output',out/'owner-liveness'],timeout=1800)
            run('ram-clear-physical-drain',[py,'tests/wram_timing/check_clear_continuation.py','--source-ref',summary['commit'],'--out',out/'clear-continuation'],timeout=3600)
        if 'download' in args.only:
            run('download-chain',[py,'tools/test_rom_download_queue.py','--altera-mf',args.vendor_sim_dir/'altera_mf.v','--out',out/'download'])
            run('save-restore-contents',[py,'tests/save_order/run_unified.py','--integration-root',ROOT,'--queue-root',ROOT,'--vendor-sim-dir',args.vendor_sim_dir,'--pal','both','--case','all','--jobs','2','--out',out/'save-restore'],timeout=7200)
            run('save-reader',[py,'tests/save_reader/run.py','--vendor-sim-dir',args.vendor_sim_dir,'--output',out/'save-reader'],timeout=1800)
            run('save-reader-legacy',[py,'tests/save_reader/legacy.py','--vendor-sim-dir',args.vendor_sim_dir,'--output',out/'save-reader-legacy'])
            run('save-smoke-real-cpu',[py,'tests/save_smoke/run.py','--out',out/'save-smoke'],timeout=1800)
            run('save-reader-actual-apf',[py,'tests/save_reader/apf.py','--vendor-sim-dir',args.vendor_sim_dir,'--output',out/'save-reader-apf'])
        if 'chips' in args.only:
            # Full unittest discovery is included in msu-full; retain explicit SA1
            # qualification when the caller selects chip tests alone.
            if 'msu' not in args.only:run('sa1-actual',[py,'-m','unittest','discover','-s','tests','-p','test_sa1_memory_wait.py','-v'])
            run('gsu-cx4-actual',[py,'tools/test_gsu_cx4_waits.py'])
            for mutation in ['gsu-ready','cx4-cache-ready','cx4-finext-ready','cx4-dma-ready']:
                run('gsu-cx4-'+mutation,[py,'tools/test_gsu_cx4_waits.py','--mutation',mutation])
            run('spc7110-actual',[py,'tools/run_spc7110_wait_tests.py','--vendor-sim-dir',args.vendor_sim_dir,'--output',out/'spc7110.json'])
        if 'bsx' in args.only:
            run('bsx-mapper',[py,'tools/test_bsx_map_waits.py'])
            for mutation in ['posted-order','posted-drain','snes-ready','cpu-credit','dma-credit']:
                run('bsx-map-'+mutation,[py,'tools/test_bsx_map_waits.py','--mutation',mutation])
            run('bsx-bridge',[py,'tools/test_bsx_memory_bridge.py','--out',out/'bsx-bridge'])
            run('bsx-datapak',[py,'tools/test_bsx_datapak_waits.py'])
            for mutation in ['read-ready','erase-ready','program-and','busy-guard','final-byte']:
                run('bsx-datapak-'+mutation,[py,'tools/test_bsx_datapak_waits.py','--mutation',mutation])
        if 'sdd1' in args.only:
            default=out/'sdd1-default.vcd';zero=out/'sdd1-zero.vcd'
            run('sdd1-default',['bash','tests/sdd1_waits/run.sh','--vcd='+str(default)])
            if default.exists():run('sdd1-default-coverage',[py,'tests/sdd1_waits/coverage.py',default,'--output',out/'sdd1-default-coverage.json'])
            run('sdd1-remapped',['bash','tests/sdd1_waits/run.sh','-gADDRESS_MASK=2097151','-gBANK_C=7','-gBANK_D=2','-gMAX_DELAY=0'])
            for n in [1,3,255]:run('sdd1-size-'+str(n),['bash','tests/sdd1_waits/run.sh','-gCASES=17','-gOUTPUT_BYTES='+str(n)])
            run('sdd1-zero',['bash','tests/sdd1_waits/run.sh','-gCASES=1','-gSTREAM_KIND=1','--vcd='+str(zero)])
            if zero.exists():run('sdd1-zero-coverage',[py,'tests/sdd1_waits/coverage.py',zero,'--output',out/'sdd1-zero-coverage.json'])
            run('sdd1-coverage-union',[py,'tests/sdd1_waits/assert_coverage.py',out/'sdd1-default-coverage.json',out/'sdd1-zero-coverage.json'])
            run('sdd1-legacy',['bash','tests/sdd1_waits/legacy.sh'])
            run('sdd1-negative',[py,'tests/sdd1_waits/mutations.py'])
            # Preserve exact trace bytes while avoiding excessive uncompressed
            # intermediate storage. gzip is a standard portable file format.
            for p in [default,zero]:
                if p.exists():
                    with p.open('rb') as src,gzip.open(str(p)+'.gz','wb',compresslevel=6) as dst:shutil.copyfileobj(src,dst)
                    p.unlink()
        if 'sdram' in args.only:
            run('sdram-independent-model',[py,'tools/test_memory_ready_sdram.py','--jobs','1','--output',out/'sdram'],timeout=2400)
        if 'audit' in args.only:
            run('independent-lifecycle',[py,'tests/memory_audit/run.py','--vendor',args.vendor_sim_dir/'altera_mf.v','--output',out/'independent-lifecycle.json'])
            run('independent-scpu-bsx-credit',[py,'tests/memory_audit/credit_chain.py'])
            run('audio-memory-continuity',[py,'tests/audio_memory_audit/run.py','--vendor-sim-dir',args.vendor_sim_dir,'--output',out/'audio'],timeout=1800)
            for mutation in ['wait-reset','wait-clock']:
                run('audio-'+mutation,[py,'tests/audio_memory_audit/run.py','--only','continuity','--pal','0','--mutation',mutation,'--vendor-sim-dir',args.vendor_sim_dir,'--output',out/('audio-'+mutation)])
        execution_finished=True
    finally:
        summary['execution_finished']=execution_finished
        summary['git_status_after']=subprocess.check_output(['git','status','--short'],cwd=ROOT,text=True).splitlines()
        after=digest_sources();summary['source_stable']=before==after
        summary['changed_sources']=[p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)]
        summary['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        summary['passed']=execution_finished and bool(records) and all(r['passed'] for r in records) and summary['source_stable']
        summary['completed_families']=args.only if summary['passed'] else []
        save()
    print('PASS complete selected software qualification' if summary['passed'] else 'FAIL software qualification; inspect summary/logs',flush=True)
    return 0 if summary['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
