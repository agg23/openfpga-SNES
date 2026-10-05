`timescale 1ns/1ps
module tb_wram_cpu;
 parameter PAL=0, TURBO=0, MODE=0, HAS_HDMA=1;
 integer inject=0,hsource=0,read_pause_ticks=53;reg reverse_test=0;reg turbo_cfg=TURBO;
 initial begin if($value$plusargs("inject=%d",inject))begin end if($test$plusargs("turbo"))turbo_cfg=1;end
 localparam real T=PAL ? 1000.0/85.125480 : 1000.0/85.909080;
 reg clk=0,mclk=0,rst=0,en=1,hb=0,vb=0;
 reg clearing=1;reg [16:0] fill_addr=0;reg [1:0] clear_div=0;
 wire [7:0] fill_data=(fill_addr[8]^fill_addr[2])?8'h66:8'h99;
 always @(posedge clk)begin clear_div<=clear_div+1;if(clearing&&clear_div==0)fill_addr<=fill_addr+1;end
 // Exact 4:1, aligned rising edges. All edge observers use pre-NBA values.
 integer clock_phase=0;
 initial begin #(T);forever begin
  mclk=1;if(clock_phase==0)clk=1;else if(clock_phase==2)clk=0;
  #(T/2);mclk=0;#(T/2);clock_phase=(clock_phase+1)%4;
 end end
 wire pa_wmdata; wire [23:0] ca; wire [7:0] pa,cd,ci;wire rd,wr,prd,pwr,ram,rom,fc,rc,rf,ri,wi,ret;wire [1:0] owner;
 reg [7:0] prog[0:65535];
 wire [16:0] wa;wire [7:0] wd,wq;wire ce,oe,we;
 wire [7:0] msud;wire msusel,msureq;wire [31:0] msuaddr;
 wire [7:0] msudata=8'h43+(msuaddr[7:0]*8'h17);
 MSU msu(.CLK(clk),.RST_N(rst),.ENABLE(1'b1),.RD_N(rd),.WR_N(wr),.SYSCLKF_CE(fc),.ADDR(ca),.DIN(cd),.DOUT(msud),.MSU_SEL(msusel),
 .track_mounting(1'b0),.status_track_missing(1'b0),.audio_stop(1'b0),.audio_sector(22'b0),.audio_loop_index(32'b0),
 .data_addr(msuaddr),.data(msudata),.data_ack(1'b0),.data_busy_external(delayed_source && delay_bus),.data_req(msureq));
 reg [23:0] held_a=0;integer delay_count=0;
 wire delayed_source=ri && owner==1 && ram;
 wire delay_bus=(ca==24'h008000 && cycles<400) || (delayed_source && (held_a!=ca || delay_count<3+(ca[3:0])));
 always @(posedge clk) begin
  if(!delayed_source || ret)delay_count<=0;
  else if(held_a!=ca)begin held_a<=ca;delay_count<=0;end
  else if(delay_count<25)delay_count<=delay_count+1;
 end
 wire [7:0] mdi=msusel?msud:prog[ca[15:0]];
 wire [7:0] wdi,cart_do,candidate_cart_do;
 WramMux bus_mux(.INT_CA(ca),.INT_PA(pa),.DI(mdi),.PPU_DO(8'hb6),.SMP_CPU_DO(8'hb6),.WRAM_DO(wq),.CPU_DO(cd),
 .INT_RAMSEL_N(ram),.INT_PARD_N(prd),.CPU_DI(ci),.WRAM_DI(wdi),.CART_DO(cart_do));
 SCPU cpu(.CLK(clk),.RST_N(rst),.ENABLE(en),.BUS_WAIT(delay_bus),.BUS_WRITE_WAIT(1'b0),
 .DI(ci),.HBLANK(hb),.VBLANK(vb),.IRQ_N(1'b1),.JOY1_DI(2'b11),.JOY2_DI(2'b11),.TURBO(turbo_cfg),.SS_BUSY(1'b0),.DBG_CPU_EN(1'b1),
 .BUS_A_READ_INTENT(ri),.BUS_A_WRITE_INTENT(wi),.BUS_A_OWNER(owner),.BUS_A_RETIRE(ret),.CA(ca),.CPURD_N(rd),.CPUWR_N(wr),
 .PA(pa),.PA_WMDATA(pa_wmdata),.PARD_N(prd),.PAWR_N(pwr),.DO(cd),.RAMSEL_N(ram),.ROMSEL_N(rom),.SYSCLKF_CE(fc),.SYSCLKR_CE(rc),.REFRESH(rf));
 SWRAM swram(.CLK(clk),.SYSCLK_CE(fc),.RST_N(rst),.ENABLE(en),.CA(ca),.CPURD_N(rd),.CPUWR_N(wr),.RAMSEL_N(ram),
 .PA(pa),.PARD_N(prd),.PAWR_N(pwr),.DI(wdi),.RAM_Q(wq),.DO(),.RAM_A(wa),.RAM_D(wd),.RAM_WE_N(we),.RAM_CE_N(ce),.RAM_OE_N(oe));
 wire [16:0] pre_wa;wire [7:0] pre_wd;wire pre_ce,pre_oe,pre_we;
 SWRAM_PREDECODE predecoded_swram(.CLK(clk),.SYSCLK_CE(fc),.RST_N(rst),.ENABLE(en),.CA(ca),.CPURD_N(rd),.CPUWR_N(wr),.RAMSEL_N(ram),
 .PA(pa),.PA_WMDATA(pa_wmdata),.PARD_N(prd),.PAWR_N(pwr),.DI(wdi),.RAM_Q(wq),.DO(),.RAM_A(pre_wa),.RAM_D(pre_wd),.RAM_WE_N(pre_we),.RAM_CE_N(pre_ce),.RAM_OE_N(pre_oe));
 // Independent legacy/predecoded SWRAM instances retain pointer state. Compare
 // every memory-clock half-edge, not only CPU retirement or matching data bytes.
 always @(posedge mclk or negedge mclk) if(rst)begin
  if(pa_wmdata !== (pa==8'h80))$fatal(1,"PA PREDECODE MISMATCH pa=%h pred=%b",pa,pa_wmdata);
  if({pre_wa,pre_wd,pre_ce,pre_oe,pre_we} !== {wa,wd,ce,oe,we})
   $fatal(1,"SWRAM PREDECODE MISMATCH pa=%h addr=%h/%h controls=%b%b%b/%b%b%b",pa,wa,pre_wa,ce,oe,we,pre_ce,pre_oe,pre_we);
 end
 wire wen=!ce&&!we,ren=!clearing&&!ce&&!oe;
 wire pre_ren=!clearing&&!pre_ce&&!pre_oe;
 wire [16:0] old_a=clearing?fill_addr:wa;
 wire [15:0] old_d=clearing?{fill_data,fill_data}:wa[0]?{wd,8'h00}:{8'h00,wd};
 wire [16:0] staged_a;wire [7:0] staged_d;wire staged_w;
 wram_write_stage stage(.clk_sys(clk),.write_en(wen),.address(wa),.data(wd),.memory_write(staged_w),.memory_address(staged_a),.memory_data(staged_d));
 reg [15:0] sys_d;
 always @(posedge clk) sys_d<=wa[0]?{wd,8'h00}:{8'h00,wd};
 wire [16:0] qa=clearing?fill_addr:(MODE==2 && staged_w)?staged_a:wa;
 wire qw=clearing?1:MODE==2?staged_w:wen;
 wire [15:0] qd=clearing?{fill_data,fill_data}:MODE==1?sys_d:MODE==2?(qa[0]?{staged_d,8'h00}:{8'h00,staged_d}):(wa[0]?{wd,8'h00}:{8'h00,wd});
 wire [15:0] oldout,newout;wire [15:0] dq0,dq1;wire [5:0] a0,a1;
 wire adv0,adv1,ce0,ce1,ce02,ce12,oe0,oe1,we0,we1,ub0,ub1,lb0,lb1;
 psram #(.CLOCK_SPEED(85.9)) old(.clk(mclk),.bank_sel(1'b0),.addr({6'b0,old_a[16:1]}),.write_en(clearing||wen),
 .data_in(old_d),.write_high_byte(old_a[0]),.write_low_byte(!old_a[0]),.read_en(ren),.data_out(oldout),
 .cram_a(a0),.cram_dq(dq0),.cram_wait(1'b0),.cram_adv_n(adv0),.cram_ce0_n(ce0),.cram_ce1_n(ce02),.cram_oe_n(oe0),.cram_we_n(we0),.cram_ub_n(ub0),.cram_lb_n(lb0));
 psram #(.CLOCK_SPEED(85.9)) candidate(.clk(mclk),.bank_sel(1'b0),.addr({6'b0,qa[16:1]}),.write_en(qw),
 .data_in(qd),.write_high_byte(qa[0]),.write_low_byte(!qa[0]),.read_en(pre_ren),.data_out(newout),
 .cram_a(a1),.cram_dq(dq1),.cram_wait(1'b0),.cram_adv_n(adv1),.cram_ce0_n(ce1),.cram_ce1_n(ce12),.cram_oe_n(oe1),.cram_we_n(we1),.cram_ub_n(ub1),.cram_lb_n(lb1));
 psram_pin_memory mem0(.a(a0),.dq(dq0),.adv(adv0),.ce(ce0),.oe(oe0),.we(we0),.ub(ub0),.lb(lb0));
 psram_pin_memory mem1(.a(a1),.dq(dq1),.adv(adv1),.ce(ce1),.oe(oe1),.we(we1),.ub(ub1),.lb(lb1));
 assign wq=wa[0]?oldout[15:8]:oldout[7:0];
 wire [7:0] staged_q;
 wram_read_stage read_stage(.clk_sys(clk),.memory_data(newout),.byte_lane(qa[0]),.data(staged_q));
 wire [7:0] candidate_q=MODE==2?staged_q:(qa[0]?newout[15:8]:newout[7:0]);
 wire [7:0] candidate_ci,candidate_wdi;
 WramMux candidate_bus_mux(.INT_CA(ca),.INT_PA(pa),.DI(mdi),.PPU_DO(8'hb6),.SMP_CPU_DO(8'hb6),.WRAM_DO(candidate_q),.CPU_DO(cd),
 .INT_RAMSEL_N(ram),.INT_PARD_N(prd),.CPU_DI(candidate_ci),.WRAM_DI(candidate_wdi),.CART_DO(candidate_cart_do));
 initial begin
  wait(rst);
  if(inject==4)begin
   if($value$plusargs("read_pause_ticks=%d",read_pause_ticks))begin end
   wait(ren && ca==24'h002180);#(1.4*T);en=0;#(read_pause_ticks*T+0.3*T);en=1;
  end
  wait(wen && owner==1);
  if(inject==1)begin #(1.4*T);en=0;#(52*T+0.3*T);en=1;end
  if(inject==2)begin #(1.4*T);rst=0;#(80*T+0.3*T);rst=1;end
  if(inject==3)begin #(3.4*T);rst=0;#(80*T+0.3*T);rst=1;end
 end
 integer reverse_dma=0,reverse_hdma=0,read_even=0,read_odd=0,read_busy=0,read_repeat=0;
 // Address sidebands are observers, never inputs to the production stage.
 // They prevent identical bytes from hiding a stale-word/lane mismatch.
 reg [15:0] response_word,staged_word;
 realtime response_time,staged_response_time,min_return_age=1e9;
 always @(posedge mclk)if(candidate.state==27)begin response_word<=mem1.address[15:0];response_time<=$realtime;end
 always @(negedge clk)begin staged_word<=response_word;staged_response_time<=response_time;end
 reg [31:0] read_start_states=0;
 integer read_token=0,last_read_token=-1;
 always @(posedge clk)if(rst&&en&&rc)read_token<=read_token+1;
 always @(posedge clk)if(rst&&en&&rc)begin #0.001;if(ren)begin read_start_states[candidate.state]=1;if(candidate.state!=0)read_busy=read_busy+1;end end
 always @(posedge mclk)if(rst&&candidate.state==0&&ren&&!qw)begin
  if(last_read_token==read_token)read_repeat=read_repeat+1;
  last_read_token=read_token;
 end
 integer hdma_enable=-1;
 integer r_phases=0,f_phases=0;
 integer cycles=0, writes=0, dma=0, hdma=0,reads=0,refreshes=0,msu_reads=0;reg was_rf=0,done=0;
 always @(posedge clk) if(rst) begin
  cycles<=cycles+1;
  if(en&&rc)r_phases<=r_phases+1;
  if(en&&fc)f_phases<=f_phases+1;
  // Global return: include the external cartridge B-to-A write-data path, not
  // just the P65 input mux. Check every sys rising edge while B read is active,
  // including R/F and any intermediate cartridge register/offer observation.
  if(en&&!prd&&cart_do!==candidate_cart_do)
   $fatal(1,"CART B TO A PHASE MISMATCH ca=%h pa=%h R=%b F=%b old=%h new=%h",ca,pa,rc,fc,cart_do,candidate_cart_do);
  if(en&&fc&&!wr&&owner==1&&ca[23:8]==16'h0060)begin
   if(cart_do!==8'((reverse_dma*37+'h61)&255))$fatal(1,"reverse WRAM DMA source byte %0d got=%h",reverse_dma,cart_do);
   reverse_dma<=reverse_dma+1;
  end
  if(en&&fc&&!wr&&owner==2&&hsource>=3)begin
   if(cart_do!==8'(((reverse_hdma+1)*37+'h61)&255))$fatal(1,"reverse WRAM HDMA source byte %0d got=%h",reverse_hdma,cart_do);
   if(ca!==(hsource==3?24'ha001:24'h6040)+reverse_hdma)$fatal(1,"reverse HDMA target %h",ca);
   reverse_hdma<=reverse_hdma+1;hdma<=hdma+1;
  end

  if(en&&fc&&(owner!=0 || !rd)&&ci!==candidate_ci)
   $fatal(1,"SCPU INPUT MISMATCH ca=%h pa=%h old=%h new=%h",ca,pa,ci,candidate_ci);
  hb<=cycles%1364>=1096;
  if(fc&&!wr&&ca==24'h00420c&&cd==8'h08)hdma_enable<=cycles;
  if(hdma_enable>=0)begin
   if(cycles-hdma_enable<2000)vb<=1;
   else if(cycles%1364==0)vb<=0;
  end
  if(hdma==3)prog['h9ff0]<=1;
  if(rf&&!was_rf)refreshes<=refreshes+1;was_rf<=rf;
  if(fc&&!rd&&msusel&&ca[2:0]==1)msu_reads<=msu_reads+1;
  if(en&&fc && (!we&&!ce))begin
   if((wa[0]?mem1.mem[wa[16:1]][15:8]:mem1.mem[wa[16:1]][7:0])!==wd)
    $fatal(1,"WRITE RETIRE DEADLINE wa=%h expected=%h actual=%h",wa,wd,mem1.mem[wa[16:1]]);
   writes<=writes+1;if(owner==1)dma<=dma+1;end
  if(en&&fc&&!pwr&&pa==8'h80&&owner==2)begin hdma<=hdma+1;$display("HDMA byte ca=%h wd=%h wa=%h",ca,wd,wa);end
  if(en&&fc&&!ce&&!oe)begin reads<=reads+1;
   if(wa[0])read_odd<=read_odd+1;else read_even<=read_even+1;
   if(MODE==2)begin
    if(staged_word!==wa[16:1]||read_stage.read_lane!==wa[0])$fatal(1,"READ RETURN ADDRESS/LANE MISMATCH want=%h staged_word=%h lane=%b",wa,staged_word,read_stage.read_lane);
    if($realtime-staged_response_time<min_return_age)min_return_age=$realtime-staged_response_time;
   end
   if(oldout!==newout)$fatal(1,"READ VALUE MISMATCH ca=%h wa=%h old=%h new=%h cycle=%0d",ca,wa,oldout,newout,cycles);
  end
  if(fc&&!wr&&ca==24'h7e010f)begin
   if(cd!==8'h5a)$fatal(1,"bad CPU marker");done<=1;
  end
  if(cycles>30000)$fatal(1,"timeout ca=%h hdma=%0d enabled=%0d hds=%0d hrun=%b run=%b",ca,hdma,hdma_enable,cpu.hds,cpu.hdma_ch_run,cpu.hdma_run);
 end
 function automatic [7:0] stored(input integer a);
  stored=a[0]?mem0.mem[a>>1][15:8]:mem0.mem[a>>1][7:0];
 endfunction
 integer p,i;task emit(input [7:0] b);begin prog[p]=b;p=p+1;end endtask
 task store(input [15:0] a,input [7:0] d);begin emit('ha9);emit(d);emit('h8d);emit(a[7:0]);emit(a[15:8]);end endtask
 task dma_start(input [23:0] src,input [7:0] control,input [7:0] b,input [15:0] count);begin
  store('h4300,control);store('h4301,b);store('h4302,src[7:0]);store('h4303,src[15:8]);store('h4304,src[23:16]);store('h4305,count[7:0]);store('h4306,count[15:8]);store('h420b,1);
 end endtask
 task pointer(input [16:0] a);begin store('h2181,a[7:0]);store('h2182,a[15:8]);store('h2183,{7'b0,a[16]});end endtask
 initial begin
  if($value$plusargs("hdma_source=%d",hsource))begin end
  reverse_test=$test$plusargs("reverse");
  for(i=0;i<65536;i=i+1)prog[i]=8'hea;
  prog['hfffc]=0;prog['hfffd]='h80;p='h8000;emit('h78);emit('hd8);
  store('h0100,'ha5);emit('had);emit('h00);emit('h01);store('h0101,'h39);
  pointer('h1100);store('h2180,'h76);store('h2180,'hba);pointer('h1100);emit('had);emit('h80);emit('h21);emit('h8d);emit('h02);emit('h01);
  pointer('h1200);dma_start('h009000,0,'h80,32);
  pointer('h1300);dma_start('h002001,8,'h80,17);
  pointer('h1400);dma_start('h7e1200,0,'h80,7); // WRAM A→WRAM B is inhibited by SWRAM
  dma_start('h7e1500,'h80,'h40,11); // reverse B→A SMP fixture
  if(reverse_test)begin pointer('h1200);dma_start('h006000,'h80,'h80,7);end
  // Read back produced bytes through the actual physical WRAM controller.
  emit('ha2);emit(0);emit('hbd);emit(0);emit('h12);emit('h9d);emit(0);emit('h16);emit('he8);emit('he0);emit(32);emit('hd0);emit('hf5);
  if(HAS_HDMA)begin pointer(hsource>=3?'h1201:'h1700);store('h4330,hsource==0?0:hsource==3?'h80:hsource==4?'hc0:'h40);store('h4337,hsource==2?'h7e:0);store('h4331,'h80);store('h4332,0);store('h4333,'ha0);store('h4334,0);store('h420c,8);
  emit('had);emit('hf0);emit('h9f);emit('hf0);emit('hfb);store('h420c,0);end
  store('h010f,'h5a);emit('h80);emit('hfe);
  prog['h9ff0]=0;prog['ha000]='h83;prog['ha001]='h51;prog['ha002]='h72;prog['ha003]='h93;prog['ha004]=0;
  if(hsource==1)begin prog['ha001]=1;prog['ha002]='h20;prog['ha003]=0;end
  if(hsource==2)begin prog['ha001]=0;prog['ha002]='h12;prog['ha003]=0;end
  if(hsource==4)begin prog['ha001]='h40;prog['ha002]='h60;prog['ha003]=0;end
  for(i=0;i<32;i=i+1)prog['h9000+i]=(i*37+'h61)&255;
  repeat(64)@(posedge clk);#(T/10);clearing=0;repeat(4)@(posedge clk);#(T/10);rst=1;
  wait(done);repeat(100)@(posedge mclk);
  for(i=0;i<65536;i=i+1)if(mem0.mem[i]!==mem1.mem[i])$fatal(1,"MEMORY MISMATCH word=%h old=%h new=%h",i,mem0.mem[i],mem1.mem[i]);
  if(HAS_HDMA && (hdma!=3 || (hsource==0 && (mem0.mem['hb80]!==16'h7251 || mem0.mem['hb81][7:0]!==8'h93)) ||
     (hsource==1 && (mem0.mem['hb80]!==16'h53ca || mem0.mem['hb81][7:0]!==8'h2d)) ||
     (hsource==2 && (mem0.mem['hb80]!==16'heaea || mem0.mem['hb81]!==16'heaea))))$fatal(1,"HDMA destination count=%0d words=%h,%h",hdma,mem0.mem['hb80],mem0.mem['hb81]);
  if(reverse_test&&reverse_dma!=7)$fatal(1,"reverse DMA count %0d",reverse_dma);
  if(HAS_HDMA&&hsource>=3&&reverse_hdma!=3)$fatal(1,"reverse HDMA count %0d",reverse_hdma);
  if(read_even==0||read_odd==0||read_repeat==0)$fatal(1,"missing read coverage even=%0d odd=%0d repeat=%0d",read_even,read_odd,read_repeat);
  for(i=0;i<32;i=i+1)if(stored('h1200+i)!==8'((i*37+'h61)&255) || stored('h1600+i)!==8'((i*37+'h61)&255))$fatal(1,"independent ROM DMA/readback sequence %0d",i);
  for(i=0;i<17;i=i+1)if(stored('h1300+i)!==8'(8'h43+i*8'h17))$fatal(1,"independent MSU DMA sequence %0d",i);
  for(i=0;i<7;i=i+1)if(stored('h1400+i)!==8'hea)$fatal(1,"forbidden WRAM-to-WRAM DMA wrote data");
  for(i=0;i<11;i=i+1)if(stored('h1500+i)!==8'hb6)$fatal(1,"reverse SMP DMA source");
  if(stored('h1100)!==8'h76 || stored('h1101)!==8'hba || stored('h102)!==8'h76)$fatal(1,"CPU WMDATA read/write");
  $display("PIN tDW=%0.3f ns tWP=%0.3f ns",mem1.min_tdw,mem1.min_twp);
  $display("PASS CPU WRAM mode=%0d PAL=%0d turbo=%0d source=%0d cycles=%0d r_phases=%0d f_phases=%0d writes=%0d dma=%0d reads=%0d refresh=%0d msu_reads=%0d hdma=%0d physical_old=%0d physical_new=%0d reverse_dma=%0d reverse_hdma=%0d read_even=%0d read_odd=%0d read_busy=%0d read_repeat=%0d read_start_states=%h min_return_age=%0.3f",MODE,PAL,turbo_cfg,hsource,cycles,r_phases,f_phases,writes,dma,reads,refreshes,msu_reads,hdma,mem0.writes,mem1.writes,reverse_dma,reverse_hdma,read_even,read_odd,read_busy,read_repeat,read_start_states,min_return_age);$finish;
 end
endmodule
module psram_pin_memory(input [5:0] a,inout [15:0] dq,input adv,ce,oe,we,ub,lb);
 reg [15:0] mem[0:65535];reg [21:0] address=0;integer i,writes=0;reg [15:0] lastdata;reg lastub,lastlb;realtime start,lastchange;
 realtime min_tdw=1e9,min_twp=1e9;reg read_valid=0;
 always @(negedge adv)begin read_valid<=0;read_valid<=#70 1;end
 initial for(i=0;i<65536;i=i+1)mem[i]='heaea;
 always @(posedge adv) if(!ce)address={a,dq};
 assign dq=!ce&&!oe&&we&&read_valid ? mem[address[15:0]]:16'hzzzz;
 always @(dq or ub or lb)if(!ce&&!we&&adv)begin lastdata=dq;lastub=ub;lastlb=lb;lastchange=$realtime;end
 always @(negedge we)start=$realtime;
 always @(posedge we)if(start>0)begin
  if($realtime-start<45)$fatal(1,"tWP");
  if($realtime-lastchange<20)$fatal(1,"tDW got=%f",$realtime-lastchange);
  if($realtime-start<min_twp)min_twp=$realtime-start;
  if($realtime-lastchange<min_tdw)min_tdw=$realtime-lastchange;
  if(!lastlb)mem[address[15:0]][7:0]=lastdata[7:0];if(!lastub)mem[address[15:0]][15:8]=lastdata[15:8];writes=writes+1;
 end
endmodule
