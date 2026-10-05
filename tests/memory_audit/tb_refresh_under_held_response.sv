`timescale 1ns/1ps
// Independent pin-level refresh deadline check. This intentionally does not
// model read-data timing; DQ is constant. It tests real engine arbitration and
// refresh while its only response is blocked, at both actual regional clocks.
module tb_refresh_under_held_response #(
 parameter integer PHYSICAL_CLK_HZ=107386350
);
 localparam realtime HALF=5.0e8/PHYSICAL_CLK_HZ;
 reg clk=0;always #(HALF) clk=~clk;
 reg rst=0,locked=0,valid=1,rr=0;
 reg [31:0] address=0;
 reg wr=0;
 wire ready,rv,error,initialized,cke,cs,ras,cas,we,oe;
 wire [15:0] q,d;
 wire [12:0] a;
 wire [1:0] bank,dqm;
 sdram_single_request dut(.clk_mem(clk),.reset_n(rst),.pll_locked(locked),
  .req_valid(valid),.req_ready(ready),.req_write(wr),.req_addr(address),.req_wdata(16'hdeca),.req_wstrb(2'b11),
  .rsp_valid(rv),.rsp_ready(rr),.rsp_rdata(q),.rsp_error(error),.init_done(initialized),
  .dram_cke(cke),.dram_cs_n(cs),.dram_ras_n(ras),.dram_cas_n(cas),.dram_we_n(we),
  .dram_addr(a),.dram_ba(bank),.dram_dqm(dqm),.dq_in(16'h1234),.dq_out(d),.dq_oe(oe));
 integer cycle=0,accepted=0,returned=0,ars=0,refresh_while_held=0,held=0;
 integer outstanding=0;
 reg expected_write=0;
 reg was_held=0;
 reg [16:0] held_payload;
 realtime last_ar=-1,max_gap=0,gap;
 reg [3:0] open_banks=0;
 always @(posedge clk) begin
  cycle=cycle+1;
  if(rst&&locked) begin
   if(was_held && (!rv || {error,q}!==held_payload)) $fatal(1,"held response changed");
   was_held=rv&&!rr;held_payload={error,q};
   if(was_held)held=held+1;
   if(rv&&rr)begin
    if(error || q!==(expected_write ? 16'h0000 : 16'h1234))$fatal(1,"response damaged by refresh");
    returned=returned+1;outstanding=outstanding-1;
   end
   if(valid&&ready)begin
    accepted=accepted+1;outstanding=outstanding+1;expected_write=wr;
    // Exercise aligned row/bank geometry while response metadata is held.
    address<=(address+32'h800)&32'h03fffffe;
    wr<=!wr;
    if(accepted==512) valid<=0;
   end
   if(outstanding<0||outstanding>1)$fatal(1,"physical single-outstanding broken");
  end
 end
 always @(negedge clk) begin
  // Long 1,900-cycle blocked intervals span multiple refresh deadlines.
  rr=(cycle%2000)<100;
  if(cke&&!cs)begin
   if(!ras&&cas&&we)begin
    if(open_banks[bank])$fatal(1,"ACT before PRE");open_banks[bank]=1;
   end
   if(!ras&&cas&&!we)begin
    if(a[10])open_banks=0;else open_banks[bank]=0;
   end
   if(!ras&&!cas&&we)begin
    if(open_banks)$fatal(1,"refresh with active bank");
    if(last_ar>=0)begin gap=$realtime-last_ar;if(gap>max_gap)max_gap=gap;end
    last_ar=$realtime;ars=ars+1;
    if(rv&&!rr)refresh_while_held=refresh_while_held+1;
   end
  end
  if(initialized&&last_ar>=0&&$realtime-last_ar>7812.5)$fatal(1,"refresh deadline exceeded");
  if(returned==512)begin
   if(ars<5||refresh_while_held<5)$fatal(1,"insufficient refresh/backpressure coverage");
   $display("PASS independent refresh audit hz=%0d accepted=%0d returned=%0d AR=%0d held_AR=%0d max_gap_ns=%0.3f held_cycles=%0d",PHYSICAL_CLK_HZ,accepted,returned,ars,refresh_while_held,max_gap,held);
   $finish;
  end
 end
 initial begin #112;rst=1;locked=1;#10000000;$fatal(1,"audit timeout");end
endmodule
