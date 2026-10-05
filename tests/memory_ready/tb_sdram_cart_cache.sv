`timescale 1ns/1ps
module tb_sdram_cart_cache;
 reg sys=0,mem=0;always #25 sys=~sys;always #5 mem=~mem;
 reg reset_n=0,locked=0,soft_req=0,active=0,idle=1,dv=0;
 reg [24:0] da=0;reg [15:0] dd=0;
 wire dr,flush;reg flush_ack=1;
 wire [7:0] epoch;wire run,fault;
 reg valid=0,write=0,rr=0;
 reg [23:0] a=0;reg [15:0] d=0;reg [1:0] be=3;
 reg [4:0] own=0;reg [7:0] tag=0,ep=0;
 wire ready,rv,re,rw;wire [15:0] q;wire [4:0] ro;wire [7:0] rt,rp;
 wire cke,cs,ras,cas,we,oe;wire [12:0] ma;wire [1:0] ba,dqm;wire [15:0] md;
 sdram_cart_port dut(.clk_sys(sys),.clk_sdram(mem),.hard_reset_n(reset_n),.pll_locked(locked),
  .soft_reset(soft_req),.download_active(active),.download_complete(idle),.download_fault(1'b0),.download_valid(dv),
  .download_ready(dr),.download_addr(da),.download_data(dd),.client_flush(flush),
  .client_flush_ack(flush_ack),.client_fault(1'b0),.epoch(epoch),.run_ready(run),.fault(fault),
  .req_valid(valid),.req_ready(ready),.req_addr(a),.req_channel(1'b0),.req_write(write),.req_drain(1'b0),
  .req_wdata(d),.req_wstrb(be),.req_owner(own),.req_tag(tag),.req_epoch(ep),
  .rsp_valid(rv),.rsp_ready(rr),.rsp_data(q),.rsp_error(re),.rsp_write(rw),.rsp_owner(ro),.rsp_tag(rt),.rsp_epoch(rp),
  .dram_cke(cke),.dram_cs_n(cs),.dram_ras_n(ras),.dram_cas_n(cas),.dram_we_n(we),
  .dram_addr(ma),.dram_ba(ba),.dram_dqm(dqm),.dq_in(16'hcafe),.dq_out(md),.dq_oe(oe));
 integer writes=0,requests=0,reads=0;
 always @(negedge mem) if(cke && !cs && ras && !cas) begin
  if(!we)writes<=writes+1;else reads<=reads+1;
 end
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
 task consume(input [7:0] expected_tag,input expected_write);
  begin wait(rv);@(negedge sys);
   if(re || rt!==expected_tag || rw!==expected_write || rp!==epoch) $fatal(1,"cache response identity/op wrong");
   rr=1;@(posedge sys);@(negedge sys);rr=0;end
 endtask
 initial begin
  #112;reset_n=1;locked=1;
  @(negedge sys);active=1;idle=0;
  host_word(25'h0,16'h1234);
  @(negedge sys);active=0;idle=1;
  wait(run);
  core_read(24'h001000,8'h01);consume(8'h01,0);
  if(reads!=1)$fatal(1,"first read did not miss");
  core_read(24'h001001,8'h02);consume(8'h02,0);
  if(reads!=1 || q!==16'hcafe)$fatal(1,"aligned-word cache miss or corruptdata");
  @(negedge sys);valid=1;a=24'h001000;tag=3;ep=epoch;own=15;write=1;d=16'haabb;be=3;
  do @(posedge sys);while(!ready);
  @(negedge sys);valid=0;write=0;
  consume(8'h03,1);
  core_read(24'h001000,8'h04);consume(8'h04,0);
  if(reads!=2 || writes!=2)$fatal(1,"accepted write failed to invalidate read cache");
  @(negedge sys);soft_req=1;repeat(3)@(negedge sys);soft_req=0;
  wait(run);
  core_read(24'h001000,8'h05);consume(8'h05,0);
  if(reads!=3)$fatal(1,"cache aliased old epoch");
  // Cached accepted response must survive flush and block a new mount's writes.
  core_read(24'h001001,8'h06);
  @(negedge sys);active=1;idle=0;flush_ack=0;
  #1;if(run || ready)$fatal(1,"new BEGIN did not close core admission immediately");
  repeat(4)@(negedge sys);
  if(dr || !rv)$fatal(1,"cached response erased or mount crossed old response");
  consume(8'h06,0);flush_ack=1;
  host_word(25'h0,16'h5678);
  @(negedge sys);active=0;idle=1;
  wait(run);
  core_read(24'h001000,8'h07);consume(8'h07,0);
  if(reads!=4 || writes!=3 || fault)$fatal(1,"mount cache invalidation failed");
  $display("PASS cart cache: raw aligned word, tagged hit, accepted write invalidation, epoch, held hit/remount drain");
  $finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
