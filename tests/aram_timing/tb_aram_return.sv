// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module aram_side #(parameter STAGED=0)(
 input sys_clk,mem_clk,rst_n,enable,pal,freq,
 input[8:0]ss_addr,input[7:0]ss_di,input smp_ss_wr,dsp_ss_wr,dsp_ss_sel,
 output[15:0]ram_a,output[7:0]ram_d,output ram_ce_n,ram_oe_n,ram_we_n,
 output[15:0]smp_a,output[7:0]smp_d,output smp_we,ce,en_f,en_r,
 output[15:0]audio_l,audio_r,output snd_rdy,output[7:0]smp_ss_do,dsp_ss_do,
 output[7:0]raw_q,read_q,output busy,read_avail,output[15:0]sample_tag);
 wire[7:0]smp_di,cpu_do;wire s0,lrck,bck,sdat;
 SMP smp(.CLK(sys_clk),.RST_N(rst_n),.CE(ce),.EN_R(en_r),.EN_F(en_f),
 .SYSCLKF_CE(1'b0),.DI(smp_di),.PA(2'b0),.PARD_N(1'b1),.PAWR_N(1'b1),
 .CPU_DI(8'b0),.CS(1'b0),.CS_N(1'b1),.IO_ADDR(17'b0),.IO_DAT(16'b0),.IO_WR(1'b0),
 .SS_ADDR(ss_addr[7:0]),.SS_WR(smp_ss_wr),.SS_DI(ss_di),.SS_DO(smp_ss_do),
 .A(smp_a),.DO(smp_d),.WE(smp_we),.CPU_DO(cpu_do),.SPC_S0(s0));
 if(STAGED)begin:core
 DSP dsp(.CLK(sys_clk),.RST_N(rst_n),.ENABLE(enable),.PAL(pal),.FREQ(freq),
 .SMP_A(smp_a),.SMP_DO(smp_d),.SMP_WE(smp_we),.RAM_Q(STAGED&&mutation==1 ? (ram_a[0]?word_q[7:0]:word_q[15:8]) : STAGED&&mutation==2 ? old_q[4] : raw_q),
 .IO_ADDR(17'b0),.IO_DAT(16'b0),.IO_WR(1'b0),.SS_ADDR(ss_addr),
 .SS_REGS_SEL(dsp_ss_sel),.SS_WR(dsp_ss_wr),.SS_DI(ss_di),.SS_DO(dsp_ss_do),
 .SMP_EN_F(en_f),.SMP_EN_R(en_r),.SMP_DI(smp_di),.SMP_CE(ce),
 .RAM_A(ram_a),.RAM_D(ram_d),.RAM_CE_N(ram_ce_n),.RAM_OE_N(ram_oe_n),.RAM_WE_N(ram_we_n),
 .LRCK(lrck),.BCK(bck),.SDAT(sdat),.AUDIO_L(audio_l),.AUDIO_R(audio_r),.SND_RDY(snd_rdy));
 end else begin:core
 DSP_ref dsp(.CLK(sys_clk),.RST_N(rst_n),.ENABLE(enable),.PAL(pal),.FREQ(freq),
 .SMP_A(smp_a),.SMP_DO(smp_d),.SMP_WE(smp_we),.RAM_Q(STAGED&&mutation==1 ? (ram_a[0]?word_q[7:0]:word_q[15:8]) : STAGED&&mutation==2 ? old_q[4] : raw_q),
 .IO_ADDR(17'b0),.IO_DAT(16'b0),.IO_WR(1'b0),.SS_ADDR(ss_addr),
 .SS_REGS_SEL(dsp_ss_sel),.SS_WR(dsp_ss_wr),.SS_DI(ss_di),.SS_DO(dsp_ss_do),
 .SMP_EN_F(en_f),.SMP_EN_R(en_r),.SMP_DI(smp_di),.SMP_CE(ce),
 .RAM_A(ram_a),.RAM_D(ram_d),.RAM_CE_N(ram_ce_n),.RAM_OE_N(ram_oe_n),.RAM_WE_N(ram_we_n),
 .LRCK(lrck),.BCK(bck),.SDAT(sdat),.AUDIO_L(audio_l),.AUDIO_R(audio_r),.SND_RDY(snd_rdy));
 end
 wire[15:0]word_q;integer mutation=0;reg[7:0]old_q[0:4];
 always @(posedge sys_clk)begin old_q[0]<=raw_q;for(integer d=1;d<5;d++)old_q[d]<=old_q[d-1];end
 reg[14:0]accepted_tag=0,returned_tag=0;reg[15:0]staged_tag=0;
 assign sample_tag=STAGED?staged_tag:{returned_tag,ram_a[0]};
 always @(negedge sys_clk)staged_tag<={returned_tag,ram_a[0]};
 always @(posedge mem_clk)begin
 if(aram.state==aram.STATE_NONE&&!ram_ce_n&&!ram_oe_n&&ram_we_n)accepted_tag<=ram_a[15:1];
 if(aram.state==aram.STATE_READ_DATA_RECEIVED)returned_tag<=accepted_tag;end
 initial if(!$value$plusargs("mutation=%d",mutation))mutation=0;
 assign raw_q=ram_a[0]?word_q[15:8]:word_q[7:0];
 assign read_q=core.dsp.ram_di;
 wire[5:0]ca;tri[15:0]dq;wire cclk,adv,cre,ce0,ce1,oe,we,ub,lb;
 psram #(.CLOCK_SPEED(85.9)) aram(.clk(mem_clk),.bank_sel(1'b0),.addr({7'b0,ram_a[15:1]}),
 .write_en(!ram_ce_n&&!ram_we_n),.read_en(!ram_ce_n&&!ram_oe_n),
 .data_in(ram_a[0]?{ram_d,8'h0}:{8'h0,ram_d}),.write_high_byte(ram_a[0]),.write_low_byte(!ram_a[0]),
 .data_out(word_q),.busy(busy),.read_avail(read_avail),.cram_a(ca),.cram_dq(dq),.cram_wait(1'b0),
 .cram_clk(cclk),.cram_adv_n(adv),.cram_cre(cre),.cram_ce0_n(ce0),.cram_ce1_n(ce1),.cram_oe_n(oe),.cram_we_n(we),.cram_ub_n(ub),.cram_lb_n(lb));
 reg[7:0]bytes[0:65535];reg[14:0]latched_addr=0;integer writes=0,reads=0;
 initial begin
  for(integer i=0;i<65536;i++)bytes[i]=8'((i*73)^(i>>3)^8'ha6);
  $readmemh("program.hex",bytes,512,767);
  for(integer i=0;i<32;i++)begin bytes[16'h1000+i*4]=0;bytes[16'h1001+i*4]=8'h20;bytes[16'h1002+i*4]=0;bytes[16'h1003+i*4]=8'h20;end
  // Repeating valid BRR block (END+LOOP) and asymmetric signed data.
  bytes[16'h2000]=8'h83;for(integer i=1;i<9;i++)bytes[16'h2000+i]=8'(i*29);
 end
 always @(negedge mem_clk)if(!adv&&!ce0)latched_addr=dq[14:0];
 assign dq=(!ce0&&!oe&&we)?{bytes[{latched_addr,1'b1}],bytes[{latched_addr,1'b0}]}:16'hzzzz;
 always @(posedge mem_clk)if(aram.state==aram.STATE_WRITE_DATA_END)begin
  if(!lb)bytes[{latched_addr,1'b0}]=dq[7:0];
  if(!ub)bytes[{latched_addr,1'b1}]=dq[15:8];writes++;
 end
 always @(negedge oe)reads++;
endmodule

module tb_aram_return;
 reg sys_clk=0,mem_clk=0,rst_n=0,enable=0,pal=0,freq=0;
 integer ipal=0,ifreq=0,phase=0,mutation=0;real half_sys=23.280;real half_mem=5.820;
 initial begin
  void'($value$plusargs("pal=%d",ipal));void'($value$plusargs("freq=%d",ifreq));void'($value$plusargs("phase=%d",phase));void'($value$plusargs("mutation=%d",mutation));
  pal=1'(ipal);freq=1'(ifreq);half_sys=ipal?500000000.0/21281370:500000000.0/21477270;half_mem=half_sys/4.0;
 end
 initial forever begin #(half_sys)sys_clk=~sys_clk;end
 initial forever begin #(half_mem)mem_clk=~mem_clk;end
 reg[8:0]ss_addr=0;reg[7:0]ss_di=0;reg smp_ss_wr=0,dsp_ss_wr=0,dsp_ss_sel=0;
 wire[15:0]ram_a[2],smp_a[2],audio_l[2],audio_r[2],sample_tag[2];wire[7:0]ram_d[2],smp_d[2],smp_ss_do[2],dsp_ss_do[2],raw_q[2],read_q[2];
 wire[1:0]ram_ce_n,ram_oe_n,ram_we_n,smp_we,ce,en_f,en_r,snd_rdy,busy,read_avail;
 for(genvar j=0;j<2;j++)begin:g
  aram_side #(.STAGED(j)) u(.sys_clk(sys_clk),.mem_clk(mem_clk),.rst_n(rst_n),.enable(enable),.pal(pal),.freq(freq),
  .ss_addr(ss_addr),.ss_di(ss_di),.smp_ss_wr(smp_ss_wr),.dsp_ss_wr(dsp_ss_wr),.dsp_ss_sel(dsp_ss_sel),
  .ram_a(ram_a[j]),.ram_d(ram_d[j]),.ram_ce_n(ram_ce_n[j]),.ram_oe_n(ram_oe_n[j]),.ram_we_n(ram_we_n[j]),
  .smp_a(smp_a[j]),.smp_d(smp_d[j]),.smp_we(smp_we[j]),.ce(ce[j]),.en_f(en_f[j]),.en_r(en_r[j]),
  .audio_l(audio_l[j]),.audio_r(audio_r[j]),.snd_rdy(snd_rdy[j]),.smp_ss_do(smp_ss_do[j]),.dsp_ss_do(dsp_ss_do[j]),
  .raw_q(raw_q[j]),.read_q(read_q[j]),.busy(busy[j]),.read_avail(read_avail[j]),.sample_tag(sample_tag[j]));
 end
 integer checks=0,smp_reads=0,dsp_reads=0,low_reads=0,high_reads=0,frames=0,nonzero_frames=0,opcodes=0,pauses=0,resets=0;
 bit[31:0]seen_request_state=0;
 always @(ram_a[0],ram_ce_n[0],ram_oe_n[0],ram_we_n[0])if(checking)seen_request_state[g[0].u.aram.state]=1;
 bit[255:0]seen_op=0;bit[127:0]seen_slot=0;bit checking=0;
 always @(posedge sys_clk)begin
  if(checking&&rst_n)begin
   if({ce[0],en_f[0],en_r[0],ram_a[0],ram_d[0],ram_ce_n[0],ram_oe_n[0],ram_we_n[0],smp_a[0],smp_d[0],smp_we[0]} !==
      {ce[1],en_f[1],en_r[1],ram_a[1],ram_d[1],ram_ce_n[1],ram_oe_n[1],ram_we_n[1],smp_a[1],smp_d[1],smp_we[1]})$fatal(1,"BUS_MISMATCH cycle=%d pc=%h",checks,g[0].u.smp.cpucore.pc);
   if(enable&&ce[0]&&!ram_ce_n[0]&&!ram_oe_n[0])begin
    if(sample_tag[0]!==ram_a[0]||sample_tag[1]!==ram_a[0])$fatal(1,"SAMPLE_TAG_MISMATCH current=%h raw_tag=%h staged_tag=%h",ram_a[0],sample_tag[0],sample_tag[1]);
    if(read_q[1]!==raw_q[0])$fatal(1,"ARAM_CONSUME_MISMATCH pc=%h a=%h raw=%h staged=%h slot=%d:%d",g[0].u.smp.cpucore.pc,ram_a[0],raw_q[0],read_q[1],g[0].u.core.dsp.step_cnt,g[0].u.core.dsp.substep_cnt);
    if(raw_q[0]!==g[0].u.bytes[ram_a[0]])$fatal(1,"REFERENCE_STALE a=%h q=%h expected=%h",ram_a[0],raw_q[0],g[0].u.bytes[ram_a[0]]);
    if(en_f[0])smp_reads++;else dsp_reads++;
    if(ram_a[0][0])high_reads++;else low_reads++;
    seen_slot[{g[0].u.core.dsp.step_cnt,g[0].u.core.dsp.substep_cnt}]=1;
   end
   if(enable&&ce[0]&&en_f[0]&&g[0].u.smp.cpucore.state==0)begin
    seen_op[g[0].u.smp.spc700_d_in]=1;opcodes++;
   end
   #0.1;
   if({audio_l[0],audio_r[0],snd_rdy[0],smp_ss_do[0]}!=={audio_l[1],audio_r[1],snd_rdy[1],smp_ss_do[1]} || (!mutation && dsp_ss_do[0]!==dsp_ss_do[1]))$fatal(1,"OUTPUT_MISMATCH cycle=%d audio=%h/%h vs %h/%h ready=%b ss=%h/%h vs %h/%h ssaddr=%h",checks,audio_l[0],audio_r[0],audio_l[1],audio_r[1],snd_rdy,smp_ss_do[0],dsp_ss_do[0],smp_ss_do[1],dsp_ss_do[1],ss_addr);
   if({g[0].u.smp.cpucore.pc,g[0].u.smp.cpucore.a,g[0].u.smp.cpucore.x,g[0].u.smp.cpucore.y,g[0].u.smp.cpucore.psw,g[0].u.smp.cpucore.sp,g[0].u.smp.cpucore.t,g[0].u.smp.cpucore.state,g[0].u.smp.cpucore.ir,g[0].u.smp.cpucore.jumptaken} !==
      {g[1].u.smp.cpucore.pc,g[1].u.smp.cpucore.a,g[1].u.smp.cpucore.x,g[1].u.smp.cpucore.y,g[1].u.smp.cpucore.psw,g[1].u.smp.cpucore.sp,g[1].u.smp.cpucore.t,g[1].u.smp.cpucore.state,g[1].u.smp.cpucore.ir,g[1].u.smp.cpucore.jumptaken})$fatal(1,"REGISTER_MISMATCH cycle=%d",checks);
   checks++;if(snd_rdy[0])begin frames++;if(audio_l[0]!=0||audio_r[0]!=0)nonzero_frames++;end
  end
 end
 task tick;@(negedge sys_clk);endtask
 task sswrite(input bit dsp,input[8:0]addr,input[7:0]value);
  tick;ss_addr=addr;ss_di=value;smp_ss_wr=!dsp;dsp_ss_wr=dsp;dsp_ss_sel=dsp;tick;smp_ss_wr=0;dsp_ss_wr=0;repeat(3)tick;dsp_ss_sel=0;
 endtask
 task init_state;
  enable=0;checking=0;rst_n=0;repeat(13+phase)@(negedge mem_clk);rst_n=1;repeat(3)tick;
  for(integer a=0;a<30;a++)sswrite(0,9'(a),0);
  sswrite(0,9'h16,8'h02);sswrite(0,9'h1b,8'hef);
  for(integer a=0;a<128;a++)sswrite(1,9'(a),0);
  sswrite(1,9'h00,8'h7f);sswrite(1,9'h01,8'h7f);sswrite(1,9'h02,0);sswrite(1,9'h03,8'h10);
  sswrite(1,9'h07,8'h7f);sswrite(1,9'h0c,8'h7f);sswrite(1,9'h1c,8'h7f);
  sswrite(1,9'h5d,8'h10);sswrite(1,9'h6d,8'h30);sswrite(1,9'h7d,1);
  sswrite(1,9'h6c,8'h1f);sswrite(1,9'h3d,1);sswrite(1,9'h81,1);sswrite(1,9'h80,0);
  tick;enable=1;checking=1;resets++;
 endtask
 initial begin
  init_state;
  for(integer epoch=0;epoch<2;epoch++)begin
   for(integer k=0;k<128;k++)begin
    // Freeze every actual DSP slot, with varying pause lengths and CPU state.
    wait(g[0].u.core.dsp.step_cnt==k/4&&g[0].u.core.dsp.substep_cnt==k%4);tick;enable=0;repeat(3+(k%13))tick;enable=1;pauses++;
    repeat(700)begin tick;ss_addr=ss_addr+1;end
   end
   if(epoch==0)init_state;
  end
  repeat(30000)tick;
  if(smp_reads<1000||dsp_reads<1000||low_reads<1000||high_reads<1000||opcodes<1000||$countones(seen_op)<20||frames<100||nonzero_frames<10)$fatal(1,"COVERAGE reads=%d/%d lanes=%d/%d instructions=%d unique=%d frames=%d nonzero=%d",smp_reads,dsp_reads,low_reads,high_reads,opcodes,$countones(seen_op),frames,nonzero_frames);
  for(integer a=0;a<65536;a++)if(g[0].u.bytes[a]!==g[1].u.bytes[a])$fatal(1,"FINAL_MEMORY_MISMATCH %h",a);
  $display("PASS ARAM_RETURN pal=%0d freq=%0d phase=%0d checks=%0d smp_reads=%0d dsp_reads=%0d low=%0d high=%0d instructions=%0d unique=%0d slots=%0d frames=%0d nonzero=%0d writes=%0d pauses=%0d resets=%0d residual_states=%08h",ipal,ifreq,phase,checks,smp_reads,dsp_reads,low_reads,high_reads,opcodes,$countones(seen_op),$countones(seen_slot),frames,nonzero_frames,g[0].u.writes,pauses,resets,seen_request_state);$finish;
 end
 initial begin #500000000;$fatal(1,"TIMEOUT");end
endmodule
