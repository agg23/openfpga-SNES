#!/usr/bin/env python3
"""Isolated 5x/CL3 pipeline probe; inherited init/refresh deliberately not fixed.
Generated copies only. Roundtrip is a test parameter, not a PCB measurement.
"""
from pathlib import Path
import sys,subprocess,os,argparse
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--region',choices=['ntsc','pal'],default='ntsc');p.add_argument('--cache',action='store_true');p.add_argument('--roundtrip',type=float,default=3.0);p.add_argument('--output',default='build/sdram5x-probe');args=p.parse_args()
o=r/args.output;o.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(r/'tools'))
from test_sdram_early_equivalence import normalize_dq
s=(r/'rtl/upstream/sdram.sv').read_text()
s=s.replace("CAS_LATENCY    = 3'd2", "CAS_LATENCY    = 3'd3")
s=s.replace('state_t state[5];','state_t state[6];')
s=s.replace('state[4] <= state[3];','state[4] <= state[3];\n\t\tstate[5] <= state[4];')
for name in ['data_read','data_bank','data_rfs','data_sni']:
 import re
 s,n=re.subn(r'(wire[^\n]*\b'+name+r'\s*=\s*)state\[3\]',r'\g<1>state[4]',s);assert n==1,(name,n)
for name in ['out_read','out_bank','out_sni']:
 s,n=re.subn(r'(wire[^\n]*\b'+name+r'\s*=\s*)state\[4\]',r'\g<1>state[5]',s);assert n==1,(name,n)
st=s.index('\t\treg [15:0] sys_dq0, sys_fallback0;');en=s.index('\n\tend else begin: g_legacy_capture',st)
s=s[:st]+'''\t\treg [15:0] sys_q;
\t\treg sys_word0;
\t\talways @(negedge sys_clk) begin
\t\t\tsys_q <= dout_buf[0];
\t\t\tsys_word0 <= word[0];
\t\tend
\t\tassign dout_temp_0=sys_q;
\t\tassign output_word0=sys_word0;'''+s[en:]
(o/'sdram5x.sv').write_text(normalize_dq(s))
stub=(r/'tests/timing/tb_sdram_sys_negedge_guard.sv').read_text().split('module tb;')[0]
tb=r'''
module tb;
 parameter realtime T=9.31217072;
 reg clk=0,sysclk=0;integer halfphase=0,cycle=-1;
 initial forever begin #(T/2);clk=~clk;if(halfphase==0)sysclk=1;if(halfphase==5)sysclk=0;halfphase=(halfphase+1)%10;end
 reg [23:0] addr=0;reg rd=0;wire[15:0]dq,q;reg[15:0]dq_drive=16'hdead,expected=16'h5678,readword;
 wire[12:0]a;wire[1:0]ba;wire ml,mh,cs,we,ras,cas,sclk,cke;
 assign dq=dq_drive;
 sdram #(.POCKET_SYS_CAPTURE(1)) dut(.clk(clk),.sys_clk(sysclk),.initialized(),.init(1'b0),.addr0(addr),.din0(16'b0),.dout0(q),.wr0(1'b0),.rd0(rd),.word0(1'b1),
 .addr1(24'b0),.din1(16'b0),.dout1(),.wr1(1'b0),.rd1(1'b0),.rfs1(1'b0),.word1(1'b0),
 .sni_addr(25'b0),.sni_din(16'b0),.sni_dout(),.sni_wr_req(1'b0),.sni_rd_req(1'b0),.sni_word(1'b0),.sni_ready(),
 .SDRAM_DQ(dq),.SDRAM_A(a),.SDRAM_DQML(ml),.SDRAM_DQMH(mh),.SDRAM_BA(ba),.SDRAM_nCS(cs),.SDRAM_nWE(we),.SDRAM_nRAS(ras),.SDRAM_nCAS(cas),.SDRAM_CLK(sclk),.SDRAM_CKE(cke));
 integer origin,reads=0,act=0,refresh=0,bad_rfc=0,init_refresh_count;bit checking=0,tracing=0;
 real first_command=-1,last_refresh=-1,last_active=-1;
 always @(posedge clk)begin
  cycle++;
  if(tracing&&dut.data_read)begin
   $display("CAPTURE M%0d time=%0.3f",cycle-origin,$realtime);
   if((cycle-origin)%10!=7)$fatal(1,"capture is not phase2 of 5:1/M7");
  end
 end
 always @(negedge sysclk)if(tracing)$display("SYS_NEG M%0.1f time=%0.3f data=%h",($realtime-(origin+0.5)*T)/T,$realtime,dut.dout_buf[0]);
 always @(posedge sclk)begin
  if(!checking&&{ras,cas,we}!=3'b111)$display("INIT CMD=%b t=%0.3f mode=%0d state=%0d count=%0d",{ras,cas,we},$realtime,dut.mode,dut.init_state,dut.reset);
  if({ras,cas,we}!=3'b111&&first_command<0)first_command=$realtime;
  if({ras,cas,we}==3'b001)begin
   refresh++;
   if(last_refresh>=0&&$realtime-last_refresh<80.0)bad_rfc++;
   last_refresh=$realtime;
  end
  if(checking&&{ras,cas,we}==3'b011)begin
   act++;
   if(last_active>=0&&$realtime-last_active<66.0)$fatal(1,"same-bank ACT/AP cycle too short");
   last_active=$realtime;
  end
  if(checking&&{ras,cas,we}==3'b101)begin
   reads++;
   if($realtime-last_active<18.0)$fatal(1,"tRCD violation");
   if(tracing)$display("READ external M%0.1f time=%0.3f",($realtime-(origin+0.5)*T)/T,$realtime);
   // Deliberately idealized guaranteed-valid window with symbolic FPGA/PCB
   // roundtrip R=3ns. No analog/JEDEC full model is claimed.
   readword=expected;
   fork
    begin #(2*T+5.5+3.0);dq_drive=readword;end
    begin #(3*T+2.5+3.0);dq_drive=16'hdead;end
   join_none
  end
 end
 task tick;begin @(posedge clk);#0.001;end endtask
 initial begin
  repeat(520)tick();while(cycle%5!=0)tick();
  if(!dut.initialized)$fatal(1,"initialization incomplete");
  $display("SPEC DIAGNOSTIC first non-NOP command=%0.3fns (required200000ns); init refresh gaps below80ns=%0d",first_command,bad_rfc);
  init_refresh_count=refresh;checking=1;origin=cycle;tracing=1;
  for(integer n=0;n<1024;n++)begin
   addr=addr+2;expected=16'h1200+n;rd=1;
   repeat(5)tick();rd=0;
   repeat(5)tick();
   if(q!==expected)$fatal(1,"M10 consumption mismatch n=%0d q=%h expected=%h",n,q,expected);
   if(n==2)tracing=0;
  end
  $display("PASS 5x CL3 normal earliest throughput reads=%0d ACT=%0d runtime_AR=%0d",reads,act,refresh-init_refresh_count);
  $display("LIMIT: inherited initialization/refresh are NOT repaired; R=3ns is illustrative, not board evidence");
  $finish;
 end
endmodule
'''
freq=107.386350 if args.region=='ntsc' else 106.406850
tb=tb.replace('parameter realtime T=9.31217072;',f'parameter realtime T={1000/freq:.12f};')
tb=tb.replace('R=3ns',f'R={args.roundtrip:g}ns')
tb=tb.replace('2*T+5.5+3.0',f'2*T+5.5+{args.roundtrip}').replace('3*T+2.5+3.0',f'3*T+2.5+{args.roundtrip}')
if args.cache:
 tb=tb.replace('reg rd=0;wire[15:0]dq,q;','reg rd=0,wordmode=1;wire[15:0]dq,q;').replace(".word0(1'b1)",'.word0(wordmode)')
 tb=tb.replace('integer origin,reads=0,act=0,refresh=0,bad_rfc=0,init_refresh_count;','integer origin,reads=0,act=0,refresh=0,bad_rfc=0,init_refresh_count;reg[15:0]expected_q;')
 tb=tb.replace("   addr=addr+2;expected=16'h1200+n;rd=1;","   addr=24'h1000+2*(n/4)+(n%2);wordmode=(n/2)%2;expected=16'h1200+(n/4);rd=1;\n   expected_q=(!wordmode&&addr[0])?{2{expected[15:8]}}:expected;")
 tb=tb.replace('if(q!==expected)$fatal(1,"M10 consumption mismatch n=%0d q=%h expected=%h",n,q,expected);','if(q!==expected_q)$fatal(1,"M10 consumption mismatch n=%0d q=%h expected=%h",n,q,expected_q);')
(o/'tb.sv').write_text(stub+tb)
env=os.environ.copy()
cmd=[os.environ.get('VERILATOR','verilator'),'--binary','--timing','--assert','-j','1','-Wno-fatal','--top-module','tb','--Mdir',str(o/'obj'),str(o/'tb.sv'),str(o/'sdram5x.sv')]
p=subprocess.run(cmd,env=env,capture_output=True,text=True);(o/'compile.log').write_text(p.stdout+p.stderr)
if p.returncode:print((p.stdout+p.stderr)[-3000:]);raise SystemExit(p.returncode)
p=subprocess.run([str(o/'obj/Vtb')],capture_output=True,text=True);(o/'simulation.log').write_text(p.stdout+p.stderr);print(p.stdout+p.stderr);raise SystemExit(p.returncode)
