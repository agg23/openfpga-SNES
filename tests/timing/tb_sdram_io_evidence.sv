`timescale 1ns/1ps
// @ tokens are replaced only in a build-directory copy by the trace generator.
// There is no external SDRAM electrical model: DQ is constant, and all printed
// datasheet windows are annotations. They do not measure a board signal.
module altddio_out #(
 parameter extend_oe_disable="OFF", intended_device_family="Cyclone V",
 invert_output="OFF", lpm_hint="UNUSED", lpm_type="altddio_out",
 oe_reg="UNREGISTERED", power_up_high="OFF", width=1
)(input [width-1:0] datain_h,datain_l,input outclock,aclr,aset,oe,outclocken,sclr,sset,
 output [width-1:0] dataout);
 assign dataout=outclock?datain_h:datain_l;
endmodule
module tb;
localparam realtime T=@PERIOD_NS@;
localparam integer REQUESTS=@REQUEST_COUNT@;
reg clk=0,sysclk=0; integer phase=0,cyc=-1;
initial forever begin
 #(T/2);clk=~clk;
 if(clk)begin
  if(phase==0)sysclk=1;
  if(phase==2)sysclk=0;
  phase=(phase+1)%4;
 end
end
reg [23:0] addr=0;reg rd=0;
wire [15:0] dq,q;wire [12:0] a;wire [1:0] ba;
wire ml,mh,cs,we,ras,cas,sclk,cke;
assign dq=16'h5678;
sdram #(.POCKET_SYS_CAPTURE(1)) dut(
 .clk(clk),.sys_clk(sysclk),.initialized(),.init(1'b0),
 .addr0(addr),.din0(16'b0),.dout0(q),.wr0(1'b0),.rd0(rd),.word0(1'b1),
 .addr1(24'b0),.din1(16'b0),.dout1(),.wr1(1'b0),.rd1(1'b0),.rfs1(1'b0),.word1(1'b0),
 .sni_addr(25'b0),.sni_din(16'b0),.sni_dout(),.sni_wr_req(1'b0),.sni_rd_req(1'b0),.sni_word(1'b0),.sni_ready(),
 .SDRAM_DQ(dq),.SDRAM_A(a),.SDRAM_DQML(ml),.SDRAM_DQMH(mh),.SDRAM_BA(ba),
 .SDRAM_nCS(cs),.SDRAM_nWE(we),.SDRAM_nRAS(ras),.SDRAM_nCAS(cas),.SDRAM_CLK(sclk),.SDRAM_CKE(cke));
integer ar_runtime=0,ar_init=0,mrs=0,emrs=0,pre_init=0,captures=0,read_commands=0;
integer origin,read_edge=-1,extedge=0;bit tracing=0;real launch_time;
always @(posedge clk)begin
 cyc++;
 if(tracing&&dut.data_read)begin
  captures++;
  if((cyc-origin)%8!=6)$fatal(1,"DQ capture did not occur at M6 modulo 8");
  if(($realtime-launch_time)<2.49*T || ($realtime-launch_time)>2.51*T)
   $fatal(1,"READ-to-capture not 2.5 cycles");
  if(captures==1)$display("CAPTURE relM=%0d delta_READ=%0.3f delta_LAUNCH=%0.3f ideal_valid_end=%0.3f capture_late_beyond_guaranteed_end=%0.3f",cyc-origin,$realtime-launch_time,$realtime-(launch_time+T),launch_time+2*T+2.5,$realtime-(launch_time+2*T+2.5));
 end
end
always @(posedge sclk)begin
 if({ras,cas,we}==3'b001)begin if(dut.initialized)ar_runtime++;else ar_init++;end
 if({ras,cas,we}==3'b000)begin if(ba==0)mrs++;else if(ba==2)emrs++;end
 if({ras,cas,we}==3'b010&&!dut.initialized)pre_init++;
 if(!dut.initialized&&{ras,cas,we}!=3'b111)
  $display("INIT_CMD t=%0.3f cmd=%b ba=%b a=%h mode=%b init_state=%0d reset=%0d",$realtime,{ras,cas,we},ba,a,dut.mode,dut.init_state,dut.reset);
 if(tracing)begin
  if(cyc-origin<8)$display("EXTERNAL_RISE relM=%0d+0.5 t=%0.3f CMD=%b A=%h",cyc-origin,$realtime,{ras,cas,we},a);
  if({ras,cas,we}==3'b101)begin launch_time=$realtime;read_edge=extedge;read_commands++;end
  if(cyc-origin<8)begin
   if(extedge==read_edge+1&&read_edge>=0)$display("DQ_LAUNCH_R1 t=%0.3f latest_valid=%0.3f",$realtime,$realtime+6.0);
   if(extedge==read_edge+2&&read_edge>=0)$display("DQ_R2 t=%0.3f earliest_invalid=%0.3f",$realtime,$realtime+2.5);
  end
  extedge++;
 end
end
initial begin
 repeat(520)begin @(posedge clk);#0.001;end
 while(cyc%4!=0)begin @(posedge clk);#0.001;end
 if(!dut.initialized)$fatal(1,"initialization incomplete");
 origin=cyc;tracing=1;addr=24'h200;rd=1;
 $display("REQUEST M0 t=%0.3f period=%0.3f",$realtime,T);
 for(integer req=0;req<REQUESTS;req++)begin
  repeat(4)begin @(posedge clk);#0.001;end
  rd=0;
  repeat(4)begin @(posedge clk);#0.001;end
  if(req+1<REQUESTS)begin addr=addr+2;rd=1;end
 end
 $display("SUMMARY init_AR=%0d init_PRE=%0d MRS=%0d EMRS=%0d runtime_AR=%0d unique_reads=%0d read_commands=%0d captures=%0d",ar_init,pre_init,mrs,emrs,ar_runtime,REQUESTS,read_commands,captures);
 if(ar_runtime!=0||emrs!=0||ar_init!=1||pre_init!=1||mrs!=1)
  $fatal(1,"historical initialization/refresh count changed");
 if(captures!=REQUESTS||read_commands!=REQUESTS)$fatal(1,"request coverage incomplete");
 $display("PASS pinned controller capture-edge and initialization/refresh observations");
 $display("LIMIT mode starts at simulator zero; constant DQ, no retention/SI/PVT/board signoff");
 $finish;
end
initial begin #100000000; $fatal(1,"watchdog");end
endmodule
