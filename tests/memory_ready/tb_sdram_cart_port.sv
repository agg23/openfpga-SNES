`timescale 1ns/1ps
module tb_sdram_cart_port;
 reg sys=0,mem=0;always #25 sys=~sys;always #5 mem=~mem;
 reg reset_n=0,locked=0,soft_req=0,active=0,idle=1,dv=0;
 reg [24:0] da=0;reg [15:0] dd=0;
 wire dr,flush;reg flush_ack=1;
 wire [7:0] epoch;wire run,fault;
 reg valid=0,write=0,rr=0;
 reg [23:0] a=0;reg [15:0] d=0;reg [1:0] be=3;
 reg [4:0] own=0;reg [7:0] tag=0,ep=0;
 wire ready,rv,re;wire [15:0] q;wire [4:0] ro;wire [7:0] rt,rp;
 wire cke,cs,ras,cas,we,oe;wire [12:0] ma;wire [1:0] ba,dqm;wire [15:0] md;
 sdram_cart_port dut(.clk_sys(sys),.clk_sdram(mem),.hard_reset_n(reset_n),.pll_locked(locked),
  .soft_reset(soft_req),.download_active(active),.download_complete(idle),.download_fault(1'b0),.download_valid(dv),
  .download_ready(dr),.download_addr(da),.download_data(dd),.client_flush(flush),
  .client_flush_ack(flush_ack),.client_fault(1'b0),.epoch(epoch),.run_ready(run),.fault(fault),
  .req_valid(valid),.req_ready(ready),.req_addr(a),.req_channel(1'b0),.req_write(write),.req_drain(1'b0),
  .req_wdata(d),.req_wstrb(be),.req_owner(own),.req_tag(tag),.req_epoch(ep),
  .rsp_valid(rv),.rsp_ready(rr),.rsp_data(q),.rsp_error(re),.rsp_owner(ro),.rsp_tag(rt),.rsp_epoch(rp),
  .dram_cke(cke),.dram_cs_n(cs),.dram_ras_n(ras),.dram_cas_n(cas),.dram_we_n(we),
  .dram_addr(ma),.dram_ba(ba),.dram_dqm(dqm),.dq_in(16'hcafe),.dq_out(md),.dq_oe(oe));
 integer writes=0,requests=0;
 always @(negedge mem) if(cke && !cs && ras && !cas && !we) writes<=writes+1;
 always @(posedge sys) if(valid && ready) requests<=requests+1;
 task host_word(input [24:0] address,input [15:0] data);
  begin @(negedge sys);dv=1;da=address;dd=data;
   do @(posedge sys); while(!dr);
   @(negedge sys);dv=0;end
 endtask
 task core_read(input [23:0] address,input [7:0] id);
  begin @(negedge sys);valid=1;a=address;tag=id;ep=epoch;own=4;
   do @(posedge sys);while(!ready);
   @(negedge sys);valid=0;end
 endtask
 initial begin
  #112;reset_n=1;locked=1;
  @(negedge sys);active=1;idle=0;
  host_word(25'h0,16'h1234);
  // Host stream can end before its last pending FIFO word reaches this boundary.
  @(negedge sys);active=0;
  repeat(20) @(negedge sys);
  if(run || !flush) $fatal(1,"released CPU before producer empty");
  host_word(25'h2,16'h5678);
  @(negedge sys);idle=1;
  wait(run);@(negedge sys);
  if(writes!=2 || fault || epoch==0) $fatal(1,"download drain/epoch failed");
  core_read(24'h800001,8'h23);
  wait(rv);@(negedge sys);
  if(q!==16'hcafe || re || ro!==4 || rt!==8'h23 || rp!==epoch)
   $fatal(1,"core response identity wrong");
  soft_req=1;flush_ack=0;
  repeat(5) @(negedge sys);soft_req=0;
  if(run) $fatal(1,"soft_req-reset reopened before old response drained");
  rr=1;@(negedge sys);rr=0;flush_ack=1;
  wait(run);
  // Remount waits until existing accepted core response drains, then admits host.
  core_read(24'h000400,8'h24);
  @(negedge sys);active=1;idle=0;flush_ack=0;
  repeat(4) @(negedge sys);
  if(dr) $fatal(1,"new mount admitted write before old owner flush");
  wait(rv);@(negedge sys);rr=1;@(negedge sys);rr=0;flush_ack=1;
  host_word(25'h800000,16'habcd);
  @(negedge sys);active=0;idle=1;
  wait(run);@(negedge sys);
  if(writes!=3 || requests!=2 || fault) $fatal(1,"mount drain count failure");
  $display("PASS cart port: actual engine init, final FIFO word, write drain, owner echo, soft_req reset, remount barrier");
  $finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
