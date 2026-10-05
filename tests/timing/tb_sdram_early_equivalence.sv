`timescale 1ns/1ps
// The controllers are real RTL. Only the vendor DDR clock output primitive is
// modeled; this checks cycle/edge behavior, not board-level SDRAM electrical timing.
module altddio_out #(
 parameter extend_oe_disable="OFF", intended_device_family="Cyclone V",
 invert_output="OFF", lpm_hint="UNUSED", lpm_type="altddio_out",
 oe_reg="UNREGISTERED", power_up_high="OFF", width=1
)(input [width-1:0] datain_h,datain_l,input outclock,aclr,aset,oe,outclocken,sclr,sset,
 output [width-1:0] dataout);
 assign dataout=outclock?datain_h:datain_l;
endmodule

module tb_sdram_early_equivalence;
 reg clk=0; always #5 clk=~clk;
 reg init=0;
 reg [23:0] addr0=0,addr1=0;
 reg [15:0] din0=0,din1=0;
 reg wr0=0,rd0=0,word0=0,wr1=0,rd1=0,rfs1=0,word1=0;
 reg [24:0] sni_addr=0;
 reg [15:0] sni_din=0;
 reg sni_wr_req=0,sni_rd_req=0,sni_word=0;
 reg [15:0] memory_word=16'hbeef;
 wire [15:0] dq_ref,dq_new,dout0_ref,dout0_new,dout1_ref,dout1_new,sni_ref,sni_new;
 wire [12:0] a_ref,a_new;
 wire [1:0] ba_ref,ba_new;
 wire dqml_ref,dqml_new,dqmh_ref,dqmh_new,ncs_ref,ncs_new,nwe_ref,nwe_new,nras_ref,nras_new,ncas_ref,ncas_new,ck_ref,ck_new,cke_ref,cke_new,ready_ref,ready_new;
 assign dq_ref=(!nwe_ref&&!ncas_ref)?16'hzzzz:memory_word;
 assign dq_new=(!nwe_new&&!ncas_new)?16'hzzzz:memory_word;
 sdram_reference reference(.SDRAM_DQ(dq_ref),.SDRAM_A(a_ref),.SDRAM_DQML(dqml_ref),.SDRAM_DQMH(dqmh_ref),.SDRAM_BA(ba_ref),.SDRAM_nCS(ncs_ref),.SDRAM_nWE(nwe_ref),.SDRAM_nRAS(nras_ref),.SDRAM_nCAS(ncas_ref),.SDRAM_CLK(ck_ref),.SDRAM_CKE(cke_ref),.init(init),.clk(clk),.addr0(addr0),.din0(din0),.dout0(dout0_ref),.wr0(wr0),.rd0(rd0),.word0(word0),.addr1(addr1),.din1(din1),.dout1(dout1_ref),.wr1(wr1),.rd1(rd1),.rfs1(rfs1),.word1(word1),.sni_addr(sni_addr),.sni_din(sni_din),.sni_dout(sni_ref),.sni_wr_req(sni_wr_req),.sni_rd_req(sni_rd_req),.sni_word(sni_word),.sni_ready(ready_ref));
 sdram candidate(.SDRAM_DQ(dq_new),.SDRAM_A(a_new),.SDRAM_DQML(dqml_new),.SDRAM_DQMH(dqmh_new),.SDRAM_BA(ba_new),.SDRAM_nCS(ncs_new),.SDRAM_nWE(nwe_new),.SDRAM_nRAS(nras_new),.SDRAM_nCAS(ncas_new),.SDRAM_CLK(ck_new),.SDRAM_CKE(cke_new),.init(init),.clk(clk),.addr0(addr0),.din0(din0),.dout0(dout0_new),.wr0(wr0),.rd0(rd0),.word0(word0),.addr1(addr1),.din1(din1),.dout1(dout1_new),.wr1(wr1),.rd1(rd1),.rfs1(rfs1),.word1(word1),.sni_addr(sni_addr),.sni_din(sni_din),.sni_dout(sni_new),.sni_wr_req(sni_wr_req),.sni_rd_req(sni_rd_req),.sni_word(sni_word),.sni_ready(ready_new));
 integer cycle=-1,checks=0,early_count=0,hit_count=0,refresh_count=0,preempt_count=0,sni_count=0;
 integer phase_counts[4]='{0,0,0,0};
 bit phase_check=0;
 reg [31:0] rng=32'h13579bdf;
 task randomize_word;
  begin rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};memory_word=rng[15:0];end
 endtask
 task compare;
  begin
   checks++;
   if ({dout0_ref,dout1_ref,sni_ref,a_ref,ba_ref,dqml_ref,dqmh_ref,ncs_ref,nwe_ref,nras_ref,ncas_ref,ck_ref,cke_ref,ready_ref} !==
       {dout0_new,dout1_new,sni_new,a_new,ba_new,dqml_new,dqmh_new,ncs_new,nwe_new,nras_new,ncas_new,ck_new,cke_new,ready_new})
    $fatal(1,"equivalence mismatch cycle=%0d phase=%0d dout0=%h/%h dout1=%h/%h",cycle,cycle%4,dout0_ref,dout0_new,dout1_ref,dout1_new);
  end
 endtask
 task tick;
  bit early;
  begin
   @(posedge clk);cycle++;
   early=reference.data_read && !reference.data_bank[1] && !reference.data_rfs && !reference.data_sni;
   if(reference.data_read&&reference.data_rfs)$fatal(1,"RD/RFS exclusivity violated");
   if(early) begin
    early_count++;
    if(phase_check) begin
     phase_counts[cycle%4]++;
     if(cycle%4!=2)$fatal(1,"unexpected port0 capture phase cycle=%0d",cycle);
     if(early_count<12)$display("TRACE early result cycle=%0d phase=%0d data=%h; late copy/select fall follows at phase3",cycle,cycle%4,memory_word);
    end
   end
   if(reference.init_done && rd0 && !reference.old_rd0 && !reference.raw_req_test)hit_count++;
   if(reference.ctrl_rfs && reference.ctrl_cmd==1)refresh_count++;
   if((wr0&&!reference.old_wr0&&reference.sni_read_ch1)||
      (wr1&&!reference.old_wr1&&reference.sni_read_ch0)||
      (rd0&&!reference.old_rd0&&reference.raw_req_test&&reference.sni_write_ch1))preempt_count++;
   if(reference.out_read&&reference.out_sni)sni_count++;
   #1;compare();
  end
 endtask
 task settle;
  begin #1;compare();end
 endtask
 initial begin
  repeat(520)tick();
  if(!reference.init_done)$fatal(1,"controller did not initialize");
  // Normal target traffic: all read pulses launched just after sys edges,
  // which coincide with memory phase 0. Only channel0 is active.
  phase_check=1;
  for(integer i=0;i<1024;i++)begin
   tick();
   if(cycle%4==0)begin
    rd0=0;wr0=0;
    case((cycle/4)%8)
     0:begin addr0=addr0+2;rd0=1;word0=0;end
     2:begin rd0=1;end // Same-word hit; no new SDRAM data capture.
     4:begin addr0=addr0+3;rd0=1;word0=1;end
     6:begin addr0=addr0+2;wr0=1;din0=rng[15:0];end
     default:;
    endcase
   end
   randomize_word();settle();
  end
  rd0=0;wr0=0;repeat(20)tick();phase_check=0;
  // Reinitialize, then exercise refresh and held/burst-like request trains.
  // SDRAM BURST remains the original single-word mode; these are bus trains.
  init=1;repeat(8)tick();init=0;repeat(520)tick();
  for(integer i=0;i<512;i++)begin
   tick();
   rd0=(i%8)<4;rfs1=(i%16)<8;
   if(i%16==0)addr0=addr0+2;
   randomize_word();settle();
  end
  rd0=0;rfs1=0;repeat(20)tick();
  // Generic controller stress, including unused-in-Pocket port1 and SNI.
  // Deliberately vary request phase; no phase relaxation is assumed here.
  for(integer i=0;i<65536;i++)begin
   tick();randomize_word();
   if((rng[3:0]==0)||i%19==0)begin
    addr0={rng[23:1],rng[30]};addr1={rng[27:5],rng[29]};
    din0=rng[15:0];din1=~rng[15:0];word0=rng[4];word1=rng[5];
   end
   rd0=rng[0];wr0=rng[1]&&!rd0;rd1=rng[2];wr1=rng[3]&&!rd1;rfs1=rng[6];
   sni_addr={rng[7],rng[31:8]};sni_din=rng[15:0];sni_word=rng[8];
   sni_rd_req=rng[9];sni_wr_req=rng[10]&&!sni_rd_req;
   settle();
  end
  if(early_count==0||hit_count==0||refresh_count==0||preempt_count==0||sni_count==0||phase_counts[2]==0)
   $fatal(1,"missing coverage early=%0d hit=%0d refresh=%0d preempt=%0d sni=%0d",early_count,hit_count,refresh_count,preempt_count,sni_count);
  $display("PASS SDRAM early-result miter: cycles=%0d comparisons=%0d early=%0d hits=%0d refresh=%0d preempt=%0d SNI=%0d",cycle+1,checks,early_count,hit_count,refresh_count,preempt_count,sni_count);
  $display("PASS system-aligned capture phases: phase0=%0d phase1=%0d phase2=%0d phase3=%0d",phase_counts[0],phase_counts[1],phase_counts[2],phase_counts[3]);
  $finish;
 end
endmodule
