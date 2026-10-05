`timescale 1ns/1ps
module tb_sdram_download_throughput;
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
 integer cycle=0,last_cycle=0,first_cycle=0,last_accept_cycle=0,gap_min=100000,gap_max=0,count=0;
 always @(posedge sys) begin
  cycle=cycle+1;
  if(dv && dr) begin
   if(count==0) first_cycle=cycle;
   else begin
    if(cycle-last_cycle<gap_min)gap_min=cycle-last_cycle;
    if(cycle-last_cycle>gap_max)gap_max=cycle-last_cycle;
   end
   last_cycle=cycle;last_accept_cycle=cycle;count=count+1;
  end
 end
 integer i;
 initial begin
  #112;reset_n=1;locked=1;
  @(negedge sys);active=1;idle=0;
  for(i=0;i<4096;i=i+1) host_word(i*2,i);
  @(negedge sys);active=0;idle=1;
  wait(run);@(negedge sys);
  if(writes!=4096 || fault) $fatal(1,"write loss in continuous download");
  $display("PASS DOWNLOAD THROUGHPUT words=%0d sys_intervals=%0d min_gap=%0d max_gap=%0d avg_gap=%0f NTSC_words_s=%0f PAL_words_s=%0f",count,last_accept_cycle-first_cycle,gap_min,gap_max,1.0*(last_accept_cycle-first_cycle)/(count-1),21477270.0*(count-1)/(last_accept_cycle-first_cycle),21281370.0*(count-1)/(last_accept_cycle-first_cycle));
  $finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
