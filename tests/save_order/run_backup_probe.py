#!/usr/bin/env python3
"""Command-level backup-after-restore ordering probe; current constant ACK witness."""
import argparse,hashlib,json,pathlib,re,subprocess,time
from run_unified import ROOT,HERE,make_boundary,need
p=argparse.ArgumentParser();p.add_argument('--integration-root',type=pathlib.Path,default=ROOT);p.add_argument('--queue-root',type=pathlib.Path,default=ROOT);p.add_argument('--out',type=pathlib.Path,default=HERE/'results-backup-admission');p.add_argument('--vendor-sim-dir',type=pathlib.Path,default=ROOT.parent/'toolchain/intelFPGA_lite/21.1/quartus/eda/sim_lib');a=p.parse_args()
i=a.integration_root.resolve();q=a.queue_root.resolve();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
top=(i/'target/pocket/core_top.sv').read_text();snes=(i/'rtl/mister_top/SNES.sv').read_text();bram=(i/'rtl/upstream/bram.vhd').read_text()
for f in ('wire dataslot_requestread_ack = 1;','wire dataslot_requestread_ok = 1;','wire dataslot_requestwrite_ack = 1;','wire dataslot_requestwrite_ok = 1;'):need(top,f,'This negative probe requires the original constant-ACK wiring')
b=(out/'boundary.sv');b.write_text(make_boundary(top,snes,bram))
t=(HERE/'tb_unified_save_contents.sv').read_text().replace('module tb_unified_save_contents;','module tb_backup_admission;')
start=t.index(' integer i,before_begins,before_saves;')
t=t[:start]+'''
 wire host_reset_n;wire[31:0]cmd_rdata;wire requestread;wire[15:0]requestread_id;
 core_bridge_cmd cb(.clk(src),.reset_n(host_reset_n),.bridge_endian_little(little),.bridge_addr(addr),.bridge_rd(bridge_rd),.bridge_rd_data(cmd_rdata),.bridge_wr(wr),.bridge_wr_data(data),
 .status_boot_done(locked),.status_setup_done(1'b0),.status_running(host_reset_n),.dataslot_requestread(requestread),.dataslot_requestread_id(requestread_id),
 .dataslot_requestread_ack(1'b1),.dataslot_requestread_ok(1'b1),.dataslot_requestwrite_ack(1'b1),.dataslot_requestwrite_ok(1'b1),
 .savestate_supported(1'b0),.savestate_addr(32'd0),.savestate_size(32'd0),.savestate_maxloadsize(32'd0),
 .savestate_start_ack(1'b0),.savestate_start_busy(1'b0),.savestate_start_ok(1'b0),.savestate_start_err(1'b0),
 .savestate_load_ack(1'b0),.savestate_load_busy(1'b0),.savestate_load_ok(1'b0),.savestate_load_err(1'b0),
 .target_dataslot_read(1'b0),.target_dataslot_write(1'b0),.target_dataslot_getfile(1'b0),.target_dataslot_openfile(1'b0),
 .target_dataslot_id(16'd0),.target_dataslot_slotoffset(32'd0),.target_dataslot_bridgeaddr(32'd0),.target_dataslot_length(32'd0),.target_buffer_param_struct(32'd0),.target_buffer_resp_struct(32'd0),
 .datatable_addr(10'd0),.datatable_wren(1'b0),.datatable_data(32'd0),.datatable_q());
 // Explicit existing FPGA FSM power-up zero, as in the repository APF tests.
 initial begin cb.hstate=0;cb.tstate=0;cb.host_cmd_start=0;end
 function automatic[31:0]swap(input[31:0]x);swap={x[7:0],x[15:8],x[23:16],x[31:24]};endfunction
 task command(input[15:0]c,input[15:0]slot);
 integer n;
 begin
 if(c==16'h0080||c==16'h0082)packet(32'hf8000020,swap({16'b0,slot}),150,1);
 if(c==16'h0082)packet(32'hf8000024,swap(32'd8192),150,1);
 packet(32'hf8000000,swap({16'h434d,c}),150,1);
 n=0;while(cb.host_0[31:16]!==16'h4f4b&&n<500)begin @(negedge src);n=n+1;end
 if(cb.host_0!==32'h4f4b0000)$fatal(1,"COMMAND_RESULT cmd=%h got=%h",c,cb.host_0);
 $display("HOST_COMMAND cmd=%h slot=%0d result=%h ns=%0.3f queued_save=%0d/%0d busy=%b",c,slot,cb.host_0,$realtime,asv,es,save_busy);$fflush();
 end endtask
 integer i,accepted_at_ready;realtime ready_time;
 initial begin
 clear_oracle();#112;reset_epoch(0);repeat(30)@(negedge src);
 command(16'h0082,0);begin_segment(17'h12345,75);packet(32'h10000000,32'h12345678,75,1);#1000000;
 for(i=0;i<128;i=i+1)packet(32'h10000004+i*4,32'habc00000+i,2,1);
 command(16'h008f,0);end_segment(75);
 begin_segment(17'h0eeee,75);command(16'h0082,10);packet(32'h20000000,32'h44332211,75,1);command(16'h008f,0);end_segment(75);
 command(16'h0011,0);command(16'h0010,0);
 command(16'h0080,10);ready_time=$realtime;accepted_at_ready=asv;
 if(requestread_id!==16'd10)$fatal(1,"WRONG_SLOT");
 use_reader=1;@(negedge src);addr=32'h20000000;bridge_rd=1;little=1;@(negedge src);bridge_rd=0;
 repeat(250)@(negedge src);
 $display("BACKUP_RESULT ready_ns=%0.3f read_ns=%0.3f accepted_at_ready=%0d expected_words=%0d got=%h wanted=44332211 queue_busy=%b",ready_time,$realtime,accepted_at_ready,es,bridge_rdata,save_busy);$fflush();
 if(accepted_at_ready<es&&bridge_rdata!==32'h44332211)$fatal(1,"EXPECTED_BACKUP_READY_BEFORE_RESTORE");
 $fatal(1,"COUNTEREXAMPLE_NOT_REPRODUCED");
 end
 initial begin #5000000;$fatal(1,"TIMEOUT");end
endmodule
'''
tb=out/'tb_backup_admission.sv';tb.write_text(t)
sources=[q/'rtl/memory_ready/rom_download_queue.sv',*[i/'rtl/memory_ready'/n for n in ('sdram_cart_port.sv','sdram_transaction_cdc.sv','sdram_single_request.sv')],i/'target/pocket/ram_clear_frontier.sv',i/'target/pocket/data_unloader.sv',i/'target/pocket/core_bridge_cmd.v',i/'platform/pocket/common.v',i/'platform/pocket/mf_datatable.v',b,tb,a.vendor_sim_dir.resolve()/'altera_mf.v']
hashes={str(x):hashlib.sha256(x.read_bytes()).hexdigest()for x in sources};exe=out/'probe.vvp';records=[]
cmd=['iverilog','-g2012','-s','tb_backup_admission','-o',str(exe),*map(str,sources)]
with (out/'compile.log').open('w')as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,text=True,timeout=90)
if r.returncode:raise SystemExit('COMPILE FAILED: '+str(out/'compile.log'))
with (out/'simulation.log').open('w')as log:r=subprocess.run(['vvp','-i',str(exe)],stdout=log,stderr=subprocess.STDOUT,text=True,timeout=120)
txt=(out/'simulation.log').read_text();print(txt)
ok=r.returncode!=0 and 'EXPECTED_BACKUP_READY_BEFORE_RESTORE' in txt
(out/'summary.json').write_text(json.dumps(dict(completed=True,expected_failure=True,passed=ok,observed='slot10 0080 ready while preceding Save bytes pending; actual unloader reads stale bytes'if ok else 'unexpected',source_hashes=hashes,limits=['Official Startup0082 / Shutdown0010 then0080 sequence; host commands serialized','Does not claim real firmware normally shuts down this quickly','Only current constant-ACK admission, not validation of a future fence','No unloader response delay or API change introduced']),indent=2)+'\n')
if not ok:raise SystemExit('Expected command-level ordering defect was not reproduced')
