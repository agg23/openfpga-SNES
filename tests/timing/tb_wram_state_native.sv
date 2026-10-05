`timescale 1ns/1ps
module tb_wram_state_native;
 parameter real T=11.640;parameter integer CYCLES=40000;
 reg clk=0;always #(T/2)clk=~clk;
 reg [1:0] bank_sel=0,write_en=0,write_high_byte=0,write_low_byte=0,read_en=0,cram_wait=0;
 reg [43:0] addr=0;reg [31:0] data_in=0;
 wire [31:0] dq[0:2],data_out[0:2];wire [11:0] ca[0:2];
 wire [1:0] rav[0:2],busy[0:2],ck[0:2],adv[0:2],cre[0:2],ce0[0:2],ce1[0:2],oe[0:2],we[0:2],ub[0:2],lb[0:2];
 `define CONNECT(i) .clk(clk),.bank_sel(bank_sel),.write_en(write_en),.write_high_byte(write_high_byte),.write_low_byte(write_low_byte),.read_en(read_en),.addr(addr),.data_in(data_in),.cram_wait(cram_wait),.cram_dq(dq[i]),.read_avail(rav[i]),.busy(busy[i]),.cram_clk(ck[i]),.cram_adv_n(adv[i]),.cram_cre(cre[i]),.cram_ce0_n(ce0[i]),.cram_ce1_n(ce1[i]),.cram_oe_n(oe[i]),.cram_we_n(we[i]),.cram_ub_n(ub[i]),.cram_lb_n(lb[i]),.data_out(data_out[i]),.cram_a(ca[i])
 native_baseline b(`CONNECT(0));native_candidate c(`CONNECT(1));psram_state_map_unit rtl(`CONNECT(2));
 `undef CONNECT
 genvar g,k;generate for(g=0;g<3;g=g+1)begin:memory
  for(k=0;k<2;k=k+1)begin:bank
   state_pin_memory mem(.a(ca[g][6*k+:6]),.dq(dq[g][16*k+:16]),.adv(adv[g][k]),.ce0(ce0[g][k]),.ce1(ce1[g][k]),.oe(oe[g][k]),.we(we[g][k]),.ub(ub[g][k]),.lb(lb[g][k]));
  end
 end endgenerate
 // NATIVE_Q_WIRES is injected from the exact exported FF Q-port names.
 // NATIVE_Q_WIRES
 integer cycles=0,samples=0,pin_events=0,wram_reads=0,aram_reads=0,quiesce_changes=0;
 reg [31:0] seen_wram=0,seen_aram=0;reg [31:0] rng=32'h51ae2011;reg [1:0] seen_read=0;
 function automatic [31:0] step(input [31:0] x);begin x=x^(x<<13);x=x^(x>>17);x=x^(x<<5);step=x;end endfunction
 task compare_pins;integer m,j;begin
  for(m=1;m<3;m=m+1)begin
   if({rav[0],busy[0],ck[0],adv[0],cre[0],ce0[0],ce1[0],oe[0],we[0],ub[0],lb[0],dq[0]} !==
      {rav[m],busy[m],ck[m],adv[m],cre[m],ce0[m],ce1[m],oe[m],we[m],ub[m],lb[m],dq[m]})
    $fatal(1,"NATIVE PIN EDGE MISMATCH model=%0d cycle=%0d base controls=%h dq=%h other controls=%h dq=%h",m,cycles,{rav[0],busy[0],ck[0],adv[0],cre[0],ce0[0],ce1[0],oe[0],we[0],ub[0],lb[0]},dq[0],{rav[m],busy[m],ck[m],adv[m],cre[m],ce0[m],ce1[m],oe[m],we[m],ub[m],lb[m]},dq[m]);
   for(j=0;j<2;j=j+1)begin
    if((!ce0[0][j]||!ce1[0][j])&&ca[0][6*j+:6]!==ca[m][6*j+:6])$fatal(1,"ADDRESS PIN MISMATCH");
    if(seen_read[j]&&data_out[0][16*j+:16]!==data_out[m][16*j+:16])$fatal(1,"READ VALUE MISMATCH");
   end
  end
 end endtask
 always @(posedge clk)begin
  cycles<=cycles+1;
  #0.01;
  if(cycles>2)begin
   compare_pins();samples=samples+1;
   if(qb!==qc)$fatal(1,"NATIVE REGISTER MISMATCH cycle=%0d",cycles);
   if(rtl.ic.snes.wram.state<32)seen_wram[rtl.ic.snes.wram.state]=1;
   if(rtl.ic.snes.aram.state<32)seen_aram[rtl.ic.snes.aram.state]=1;
   if(rav[0][0])begin wram_reads=wram_reads+1;seen_read[0]=1;end
   if(rav[0][1])begin aram_reads=aram_reads+1;seen_read[1]=1;end
  end
 end
 always @(negedge clk)begin
  if(cycles>2)begin compare_pins();samples=samples+1;end
  rng=step(rng);addr={rng[21:0],rng[31:10]};rng=step(rng);data_in=rng;bank_sel=rng[1:0];write_high_byte=rng[3:2];write_low_byte=rng[5:4];cram_wait=rng[7:6];
  // Long held read/write streams, simultaneous requests, input changes while
  // busy, and quiesce boundaries at every physical controller phase.
  case((cycles/127)%5)
   0:begin write_en=2'b00;read_en=2'b11;end
   1:begin write_en=2'b11;read_en=2'b11;end
   2:begin write_en=rng[9:8];read_en=rng[11:10];end
   3:begin write_en=2'b01;read_en=2'b10;end
   4:begin write_en=0;read_en=0;quiesce_changes=quiesce_changes+1;end
  endcase
 end
 always @(adv[0] or adv[1] or adv[2] or we[0] or we[1] or we[2] or oe[0] or oe[1] or oe[2] or ce0[0] or ce0[1] or ce0[2])begin
  #0.01;if(cycles>2)begin compare_pins();pin_events=pin_events+1;end
 end
 initial begin
  wait(cycles==CYCLES);@(negedge clk);#0.02;
  if((seen_wram&32'h0ff001ff)!==32'h0ff001ff||(seen_aram&32'h0ff001ff)!==32'h0ff001ff)$fatal(1,"MISSING STATE COVERAGE %h %h",seen_wram,seen_aram);
  if(wram_reads<100||aram_reads<100||quiesce_changes<100)$fatal(1,"MISSING TRAFFIC COVERAGE");
  $display("PASS native PSRAM sequential/pin equivalence cycles=%0d half_edges=%0d pin_events=%0d wram_reads=%0d aram_reads=%0d quiesce=%0d states=%h/%h",cycles,samples,pin_events,wram_reads,aram_reads,quiesce_changes,seen_wram,seen_aram);$finish;
 end
endmodule
module state_pin_memory(input [5:0] a,inout [15:0] dq,input adv,ce0,ce1,oe,we,ub,lb);
 wire ce=ce0&&ce1;reg [21:0] address=0;reg bank=0;reg read_valid=0;realtime write_start=0,last_data_change=0;
 // Ignore zero-time power-up delta transitions from the vendor I/O atoms.
 always @(negedge adv)if($realtime>0)begin read_valid<=0;read_valid<=#70 1;end
 always @(posedge adv)if(!ce)begin address<={a,dq};bank<=!ce1;end
 wire [15:0] payload=address[15:0]^(address[21:6]*16'h113d)^{15'b0,bank}^16'ha763;
 assign dq=!ce&&!oe&&we&&read_valid?payload:16'hzzzz;
 always @(negedge we)write_start=$realtime;
 always @(dq or ub or lb)if(!ce&&!we&&adv)last_data_change=$realtime;
 always @(posedge we)if(write_start>0)begin
  if($realtime-write_start<45)$fatal(1,"WRITE PULSE WIDTH");
  if($realtime-last_data_change<20)$fatal(1,"WRITE DATA SETUP");
 end
endmodule
