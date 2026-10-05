`timescale 1ns/1ps
module tb_clear_cpu;
 parameter PAL=0;
 localparam real T=PAL?1000.0/85.125480:1000.0/85.909080;
 reg clk=0,mclk=0,hard_reset_n=0,cpu_run=0,image_busy=0,save_busy=0,image_begin=0;
 integer clock_phase=0;
 initial begin #(T);forever begin
  mclk=1;if(clock_phase==0)clk=1;else if(clock_phase==2)clk=0;
  #(T/2);mclk=0;#(T/2);clock_phase=(clock_phase+1)%4;
 end end
 wire rst=cpu_run&&!image_busy&&!save_busy;
 integer cut=100,target=256,turbo=0,wait_cycles=0;reg seen=0,closed=0;
 wire [23:0] ca;wire [7:0] pa,cd,ci,cartdo;wire rd,wr,prd,pwr,ram,rom,fc,rc,rf,ri,wi,ret;wire [1:0] owner;
 reg [7:0] prog[0:65535];
 wire [16:0] wa;wire [7:0] wd,wq,wdi;wire ce,oe,we;
 WramMux bus_mux(.INT_CA(ca),.INT_PA(pa),.DI(prog[ca[15:0]]),.PPU_DO(8'hb6),.SMP_CPU_DO(8'hb6),.WRAM_DO(wq),.CPU_DO(cd),
 .INT_RAMSEL_N(ram),.INT_PARD_N(prd),.CPU_DI(ci),.WRAM_DI(wdi),.CART_DO(cartdo));
 SCPU cpu(.CLK(clk),.RST_N(rst),.ENABLE(1'b1),.BUS_WAIT(1'b0),.BUS_WRITE_WAIT(1'b0),
 .DI(ci),.HBLANK(1'b0),.VBLANK(1'b0),.IRQ_N(1'b1),.JOY1_DI(2'b11),.JOY2_DI(2'b11),.TURBO(turbo!=0),.SS_BUSY(1'b0),.DBG_CPU_EN(1'b1),
 .BUS_A_READ_INTENT(ri),.BUS_A_WRITE_INTENT(wi),.BUS_A_OWNER(owner),.BUS_A_RETIRE(ret),.CA(ca),.CPURD_N(rd),.CPUWR_N(wr),
 .PA(pa),.PARD_N(prd),.PAWR_N(pwr),.DO(cd),.RAMSEL_N(ram),.ROMSEL_N(rom),.SYSCLKF_CE(fc),.SYSCLKR_CE(rc),.REFRESH(rf));
 SWRAM swram(.CLK(clk),.SYSCLK_CE(fc),.RST_N(rst),.ENABLE(1'b1),.CA(ca),.CPURD_N(rd),.CPUWR_N(wr),.RAMSEL_N(ram),
 .PA(pa),.PARD_N(prd),.PAWR_N(pwr),.DI(wdi),.RAM_Q(wq),.DO(),.RAM_A(wa),.RAM_D(wd),.RAM_WE_N(we),.RAM_CE_N(ce),.RAM_OE_N(oe));
 wire wen=!ce&&!we,ren=!ce&&!oe;
 wire staged_write;wire [16:0] staged_addr;wire [7:0] staged_data;
 wram_write_stage c0(.clk_sys(clk),.write_en(wen),.address(wa),.data(wd),.memory_write(staged_write),.memory_address(staged_addr),.memory_data(staged_data));
 wire active,barrier_busy,psram_busy;wire [16:0] clear_addr;
 ram_clear_frontier frontier(.clk_sys(clk),.hard_reset_n(hard_reset_n),.image_begin(image_begin),.quiescent(image_busy&&!psram_busy),.save_byte_addr(17'b0),.active(active),.busy(barrier_busy),.clear_addr(clear_addr),.save_credit());
 wire [16:0] addr=active?clear_addr:staged_addr;
 wire [7:0] fill=clear_addr[0]?8'hff:8'h00;
 wire [15:0] data_in=active?{fill,fill}:addr[0]?{staged_data,8'b0}:{8'b0,staged_data};
 wire [15:0] data_out,dq;wire [5:0] a;wire adv,psce,psce2,psoe,pswe,ub,lb;
 psram #(.CLOCK_SPEED(85.9)) dut(.clk(mclk),.bank_sel(1'b0),.addr({6'b0,addr[16:1]}),
 .write_en(active||(staged_write&&!barrier_busy)),.data_in(data_in),.write_high_byte(addr[0]),.write_low_byte(!addr[0]),.read_en(!active&&!barrier_busy&&ren),.data_out(data_out),.busy(psram_busy),
 .cram_a(a),.cram_dq(dq),.cram_wait(1'b0),.cram_adv_n(adv),.cram_ce0_n(psce),.cram_ce1_n(psce2),.cram_oe_n(psoe),.cram_we_n(pswe),.cram_ub_n(ub),.cram_lb_n(lb));
 wram_read_stage c1(.clk_sys(clk),.memory_data(data_out),.byte_lane(addr[0]),.data(wq));
 psram_pin_memory mem(.a(a),.dq(dq),.adv(adv),.ce(psce),.oe(psoe),.we(pswe),.ub(ub),.lb(lb));
 realtime busy_time,clear_time,last_old_accept=-1,last_old_finish=-1,first_clear_finish=-1;
 reg packet_old=0;reg [16:0] packet_addr;reg [7:0] packet_data;
 integer last_f=0,post_reset_accepts=0,old_completed=0,clear_state=0;
 always @(posedge mclk)begin
  if(dut.state==0&&(active||(staged_write&&!barrier_busy)))begin
   packet_old=!active;packet_addr=addr;packet_data=addr[0]?data_in[15:8]:data_in[7:0];
   if(!active)begin last_old_accept=$realtime;if(closed)post_reset_accepts=post_reset_accepts+1;end
  end
  if(dut.state==8)begin
   if(packet_old)begin last_old_finish=$realtime;old_completed=old_completed+1;end
   else if(first_clear_finish<0)first_clear_finish=$realtime;
  end
 end
 always @(posedge active)begin clear_time=$realtime;clear_state=dut.state;if(psram_busy)$fatal(1,"ACTUAL CPU CLEAR BEFORE IDLE");end
 always @(posedge clk)begin
  image_begin<=0;
  if(rst&&wen&&wa==17'(target)&&!closed)begin
   if(!seen)begin seen<=1;wait_cycles<=0;end
   else wait_cycles<=wait_cycles+1;
   if((cut==100&&fc)||(cut!=100&&wait_cycles==cut))begin
    closed<=1;image_busy<=1;save_busy<=1;image_begin<=1;busy_time=$realtime;
    if(fc)last_f=1;
   end
  end
  if(active&&clear_addr==0&&frontier.divider==3)
   if(mem.mem[0][7:0]!==0)$fatal(1,"ACTUAL CPU ZERO DEADLINE cut=%0d target=%h",cut,target);
 end
 integer p,i;
 task emit(input [7:0] b);begin prog[p]=b;p=p+1;end endtask
 task store(input [15:0] ad,input [7:0] d);begin emit('ha9);emit(d);emit('h8d);emit(ad[7:0]);emit(ad[15:8]);end endtask
 initial begin
  if($value$plusargs("cut=%d",cut))begin end
  if($value$plusargs("target=%d",target))begin end
  if($value$plusargs("turbo=%d",turbo))begin end
  for(i=0;i<65536;i=i+1)prog[i]=8'hea;
  prog['hfffc]=0;prog['hfffd]='h80;p='h8000;emit('h78);emit('hd8);
  store('h0100,'h3c);store('h0101,'h97);store('h2181,0);store('h2182,'h11);store('h2183,0);store('h2180,'h76);store('h2180,'hba);emit('h80);emit('hfe);
  repeat(3)@(posedge clk);#0.01;hard_reset_n=1;repeat(5)@(posedge clk);#0.01;cpu_run=1;
  wait(active&&clear_addr==8);#(2*T);
  if(cut==100&&!last_f)$fatal(1,"MISSING LAST F");
  if(last_old_accept>busy_time+0.01*T)$fatal(1,"ACTUAL CPU OLD ADMISSION TOO LATE");
  if(old_completed==0)$fatal(1,"NO ACCEPTED OLD CPU WRITE");
  if(last_old_finish>=clear_time)$fatal(1,"OLD AFTER FIRST CLEAR");
  for(i=0;i<4;i=i+1)if(mem.mem[i]!==16'hff00)$fatal(1,"ACTUAL CPU CLEAR INTEGRITY");
  if(mem.mem['h80][7:0]!==8'h3c)$fatal(1,"DELAYED CPU WRITE CORRUPTED");
  if(target==257&&mem.mem['h80][15:8]!==8'h97)$fatal(1,"LAST ODD CPU WRITE CORRUPTED");
  if(target>=4352&&mem.mem['h880][7:0]!==8'h76)$fatal(1,"LAST WMDATA WRITE CORRUPTED");
  if(target==4353&&mem.mem['h880][15:8]!==8'hba)$fatal(1,"LAST ODD WMDATA WRITE CORRUPTED");
  $display("PASS CPU CLEAR PAL=%0d turbo=%0d cut=%0d target=%h last_F=%0d post_reset_accepts=%0d old_completed=%0d clear_state=%0d last_old_T=%0.3f first_finish_T=%0.3f",PAL,turbo,cut,target,last_f,post_reset_accepts,old_completed,clear_state,(last_old_finish-clear_time)/T,(first_clear_finish-clear_time)/T);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout cut=%0d target=%h",cut,target);end
endmodule
