#!/usr/bin/env python3
"""Check DMA selector invariants on real SCPU regression traces.

This is finite settled-edge simulation, not sequential induction or an 85 MHz
PSRAM sampling/glitch proof. It never edits the actual RTL.
"""
import argparse
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PARTS = ['P65816_pkg', 'AddrGen', 'BCDAdder', 'AddSubBCD', 'ALU', 'MCode', 'P65C816']
CASES = [('tb_scpu_msu_wait', []),
         ('tb_scpu_msu_wait', ['-gHB_OFFSET=144', '-gREQUIRE_REFRESH_ENTRY=true']),
         ('tb_scpu_hdma_wait', []), ('tb_scpu_cpu_wait_hdma_init', []),
         ('tb_scpu_hdma_init_fetch_wait', [])]
MONITOR = '''
-- Test-only monitor, inserted in a temporary copy of the real SCPU.
dma_guard_monitor : process(CLK)
 variable saw_cpu, saw_dma, saw_hdma : boolean := false;
begin
 if falling_edge(CLK) and RST_N='1' then
  assert not(CPU_RD='1' and CPU_WR='1') report "GUARD CPU strobes overlap" severity failure;
  assert DMA_TRANSFER/='1' or DMA_RUN='1' report "GUARD DMA_TRANSFER without DMA_RUN" severity failure;
  assert HDMA_BUS_ACTIVE/='1' or HDMA_RUN='1' report "GUARD HDMA_BUS_ACTIVE without HDMA_RUN" severity failure;
  assert DMA_OWNER=(DMA_RUN or HDMA_RUN) report "GUARD ownership mismatch" severity failure;
  if DMA_OWNER='1' then
   assert DMA_CA=CA and DMA_RAMSEL_N=RAMSEL_N and DMA_ROMSEL_N=ROMSEL_N
    report "GUARD DMA address view mismatch" severity failure;
  end if;
  if CPU_WR='1' and not saw_cpu then report "COVER CPU_WRITE"; saw_cpu:=true; end if;
  if DMA_TRANSFER='1' and not saw_dma then report "COVER DMA_TRANSFER"; saw_dma:=true; end if;
  if HDMA_BUS_ACTIVE='1' and not saw_hdma then report "COVER HDMA_BUS_ACTIVE"; saw_hdma:=true; end if;
 end if;
end process;
'''

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output', default='build/dlh-dma-guards')
    args=parser.parse_args()
    out=(ROOT/args.output).resolve();out.mkdir(parents=True,exist_ok=True)
    if not shutil.which('ghdl'):parser.error('GHDL is required')
    with tempfile.TemporaryDirectory(prefix='dlh-dma-guards-') as directory:
        work=pathlib.Path(directory)
        flags=['--std=08','-fsynopsys','--workdir='+str(work)]
        source=(ROOT/'rtl/upstream/CPU.vhd').read_text()
        at=source.lower().rfind('end rtl;')
        if at<0:raise AssertionError('Actual SCPU architecture terminator not found')
        instrumented=work/'CPU_monitored.vhd'
        instrumented.write_text(source[:at]+MONITOR+source[at:])
        def run(label, action, *extra):
            command=['ghdl',action,*flags,*map(str,extra)]
            result=subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT,timeout=90)
            (out/(label+'.log')).write_text(result.stdout)
            if result.returncode:raise RuntimeError(label+' failed:\n'+result.stdout)
            return result.stdout
        run('analyze','-a',*[ROOT/'rtl/upstream/65C816'/(p+'.vhd') for p in PARTS],instrumented)
        coverage=set()
        for index,(bench,generics) in enumerate(CASES):
            label=str(index)+'-'+bench
            run(label+'-analyze','-a',ROOT/'tests/msu1'/(bench+'.vhd'))
            run(label+'-elaborate','-e',bench)
            log=run(label,'-r',bench,*generics,'--assert-level=error','--ieee-asserts=disable')
            if 'PASS' not in log:raise AssertionError('Missing testbench success: '+label)
            for name in ['CPU_WRITE','DMA_TRANSFER','HDMA_BUS_ACTIVE']:
                if 'COVER '+name in log:coverage.add(name)
            print('PASS '+label,flush=True)
        if coverage!={'CPU_WRITE','DMA_TRANSFER','HDMA_BUS_ACTIVE'}:
            raise AssertionError('Missing guard coverage: '+str(coverage))
        print('PASS actual SCPU guards on five CPU/DMA/HDMA/refresh/init traces; finite settled-edge simulation only')
if __name__=='__main__':main()
