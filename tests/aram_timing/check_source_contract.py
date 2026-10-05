#!/usr/bin/env python3
"""Guard the narrow production assumptions behind the ARAM phase proof."""
import pathlib,re,subprocess
R=pathlib.Path(__file__).resolve().parents[2]
def text(p):return (R/p).read_text()
def compact(s):return re.sub(r'\s+','',s)
dsp=text('rtl/upstream/DSP.vhd');snes=text('rtl/upstream/SNES.vhd');main=text('rtl/upstream/main.v');top=text('rtl/mister_top/SNES.sv')
for src in [dsp,snes]:assert re.search(r'ARAM_RETURN_STAGE\s*:\s*boolean\s*:=\s*false',src,re.I)
assert 'genericmap(ARAM_RETURN_STAGE=>ARAM_RETURN_STAGE)' in compact(snes)
assert '.ARAM_RETURN_STAGE(USE_STANDARD_SDRAM?"TRUE":"FALSE")' in compact(main)
assert re.search(r'ARAM_STAGED:\s*if ARAM_RETURN_STAGE generate.*?if falling_edge\(CLK\) then\s*RAM_DI <= RAM_Q;.*?end generate;',dsp,re.S)
assert re.search(r'ARAM_LEGACY:\s*if not ARAM_RETURN_STAGE generate\s*RAM_DI <= RAM_Q;\s*end generate;',dsp,re.S)
assert "SS_DO<=SS_REGS_DOwhenSS_REGS_SEL='1'elseRAM_Q;" in compact(dsp)
assert '.ACLK(clk_sys)' in compact(top) and '.dspclk(ACLK)' in compact(main)
assert snes.count('CLK\t\t\t=> DSPCLK')==2
assert '.clk(clk_mem_85_9)' in compact(top[top.index(') aram ('):])
# Current Pocket disables all address-register restore paths structurally.
assert 'wirespc_download=0;' in compact(top)
assert '.IO_WR(spc_download&ioctl_wr)' in compact(top)
assert "parameterUSE_SS=1'b0;" in compact(top)
core=text('target/pocket/core_top.sv')
main_parameters=re.search(r'MAIN_SNES\s*#\((.*?)\) snes',core,re.S)[1]
assert '.USE_SS' not in main_parameters
assert 'assignSS_DSP_REGS_SEL=0;' in compact(main) and 'assignSS_SMP_SEL=0;' in compact(main)
assert 'SS_WR=>SS_SMP_SELandSS_WR' in compact(snes)
assert 'SS_REGS_WR<=SS_WRandSS_REGS_SEL;' in compact(dsp)
assert "CEGEN_RST_N<=RST_NandENABLE;" in compact(dsp)
assert '.RESET_N(USE_STANDARD_SDRAM?(RESET_N&&standard_run_ready&&!reset):RESET_N)' in compact(top)
assert 'ram_clear_busy' in re.search(r'wire reset =(.*?);',top,re.S)[1]
# The scalar result already includes current byte selection before entering DSP.
assert 'assignARAM_Q=psram_aram_addr[0]?aram_16_out[15:8]:aram_16_out[7:0];' in compact(top)
# Do not allow accidental changes to the transaction engine, divider or CPU.
paths=['target/pocket/psram.sv','rtl/upstream/CEGen.vhd','rtl/upstream/DSP_PKG.vhd','rtl/upstream/SMP.vhd']
paths += [str(p.relative_to(R)) for p in (R/'rtl/upstream/SPC700').glob('*.vhd')]
for p in paths:
 assert (R/p).read_bytes()==subprocess.check_output(['git','show','982f103:'+p],cwd=R),p
print('PASS opt-in profile wiring, default legacy, raw save-state bypass, same clocks, unchanged real SPC700/SMP/PSRAM/CEGen')
