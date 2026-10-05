`timescale 1ns/1ps
module tb_clear_continuation;
 parameter PAL=0;
 localparam real T=PAL?1000.0/85.125480:1000.0/85.909080;
 reg clk=0,mclk=0,hard_reset_n=0,image_begin=0,image_busy=0,save_busy=0;
 integer clock_phase=0;
 initial begin #(T);forever begin
  mclk=1;if(clock_phase==0)clk=1;else if(clock_phase==2)clk=0;
  #(T/2);mclk=0;#(T/2);clock_phase=(clock_phase+1)%4;
 end end
 integer phase=0,kind=1,old_addr=0,fillmode=1,host_delay=0,full=0,akind=0,alead=0,restart=0;reg aram_launch=0;integer closed_cycles=0;reg launch=0;
 // standard_run_ready drops combinationally with image/save busy. This closes
 // CPU reset/admission even if the old four-sys RESET_N divider has not fired.
 wire cpu_reset_n=!(image_busy||save_busy);
 wire old_write=launch&&kind==1&&cpu_reset_n;
 wire old_read=launch&&kind==2&&cpu_reset_n;
 wire [16:0] raw_addr=cpu_reset_n?17'(old_addr):17'h1badd;
 wire [7:0] raw_data=cpu_reset_n?8'h3c:8'he7;
 wire staged_write;wire [16:0] staged_addr;wire [7:0] staged_data;
 wram_write_stage c0(.clk_sys(clk),.write_en(old_write),.address(raw_addr),.data(raw_data),
 .memory_write(staged_write),.memory_address(staged_addr),.memory_data(staged_data));
 wire active,barrier_busy,psram_busy,aram_busy;wire [16:0] clear_addr;wire credit;
 wire host_quiescent=image_busy&&closed_cycles>=host_delay;
 always @(posedge clk)if(image_busy)closed_cycles<=closed_cycles+1;
 ram_clear_frontier frontier(.clk_sys(clk),.hard_reset_n(hard_reset_n),.image_begin(image_begin),.quiescent(host_quiescent&&!psram_busy&&!aram_busy),
 .save_byte_addr(17'b0),.active(active),.busy(barrier_busy),.clear_addr(clear_addr),.save_credit(credit));
 function automatic [7:0] fill(input [16:0] a);
  case(fillmode)
   0:fill=(a[8]^a[2])?8'h66:8'h99;
   1:fill=(a[9]^a[0])?8'hff:8'h00;
   2:fill=8'h55;
   3:fill=8'hff;
  endcase
 endfunction
 wire [16:0] addr=active?clear_addr:staged_addr;
 wire write_en=active||(staged_write&&!barrier_busy);
 wire [15:0] data_in=active?{fill(clear_addr),fill(clear_addr)}:addr[0]?{staged_data,8'b0}:{8'b0,staged_data};
 wire [15:0] data_out,dq;wire [5:0] a;wire adv,ce,ce2,oe,we,ub,lb;
 psram #(.CLOCK_SPEED(85.9)) dut(.clk(mclk),.bank_sel(1'b0),.addr({6'b0,addr[16:1]}),
 .write_en(write_en),.data_in(data_in),.write_high_byte(addr[0]),.write_low_byte(!addr[0]),.read_en(!active&&!barrier_busy&&old_read),.data_out(data_out),.busy(psram_busy),
 .cram_a(a),.cram_dq(dq),.cram_wait(1'b0),.cram_adv_n(adv),.cram_ce0_n(ce),.cram_ce1_n(ce2),.cram_oe_n(oe),.cram_we_n(we),.cram_ub_n(ub),.cram_lb_n(lb));
 wire [7:0] q;
 wram_read_stage c1(.clk_sys(clk),.memory_data(data_out),.byte_lane(addr[0]),.data(q));
 psram_pin_memory mem(.a(a),.dq(dq),.adv(adv),.ce(ce),.oe(oe),.we(we),.ub(ub),.lb(lb));
 wire [15:0] aa=active?clear_addr[15:0]:16'h0200;
 wire arwrite=active||(aram_launch&&akind==1&&cpu_reset_n&&!barrier_busy);
 wire arread=!active&&aram_launch&&akind==2&&cpu_reset_n&&!barrier_busy;
 wire [7:0] arbyte=active?fill(clear_addr):8'ha7;
 wire [15:0] ardata=aa[0]?{arbyte,8'b0}:{8'b0,arbyte};
 wire [15:0] ardq;wire [5:0] ara;wire aradv,arce,arce2,aroe,arwe,arub,arlb;
 psram #(.CLOCK_SPEED(85.9)) aram(.clk(mclk),.bank_sel(1'b0),.addr({7'b0,aa[15:1]}),
 .write_en(arwrite),.data_in(ardata),.write_high_byte(aa[0]),.write_low_byte(!aa[0]),.read_en(arread),.busy(aram_busy),
 .cram_a(ara),.cram_dq(ardq),.cram_wait(1'b0),.cram_adv_n(aradv),.cram_ce0_n(arce),.cram_ce1_n(arce2),.cram_oe_n(aroe),.cram_we_n(arwe),.cram_ub_n(arub),.cram_lb_n(arlb));
 psram_pin_memory amem(.a(ara),.dq(ardq),.adv(aradv),.ce(arce),.oe(aroe),.we(arwe),.ub(arub),.lb(arlb));
 integer arbegin_state=-1,arclear_state=-1;
 realtime arlast_old_accept=-1,arlast_old_finish=-1;reg arpacket_old=0;
 always @(posedge mclk)begin
  if(aram.state==0&&arwrite)begin arpacket_old=!active;arpacket_generation=generation;if(!active)arlast_old_accept=$realtime;end
  if(aram.state==8&&(arpacket_old||arpacket_generation<generation))arlast_old_finish=$realtime;
 end
 realtime begin_time=0,clear_time=0,last_old_accept=-1,last_old_finish=-1,first_clear_accept=-1,first_clear_finish=-1;
 integer begin_state=-1,clear_state=-1,late_old_accepts=0,old_finishes=0,clear_sys=0,blocked_stage=0;
 realtime clear_end_time=0,physical_tail=0,busy_end_time=0;
 integer generation=0,packet_generation=0,arpacket_generation=0;
 always @(posedge image_begin)generation=generation+1;
 reg packet_old=0;reg [16:0] packet_addr;integer word_zero_late=0;
 always @(posedge mclk)begin
  if(image_busy&&barrier_busy&&staged_write)blocked_stage=blocked_stage+1;
  if(dut.state==0&&write_en)begin
   packet_old=!active;packet_generation=generation;packet_addr=addr;
   if(!active)begin last_old_accept=$realtime;if(image_busy)late_old_accepts=late_old_accepts+1;end
   else if(first_clear_accept<0)begin first_clear_accept=$realtime;if(addr!==0)$fatal(1,"FIRST CLEAR ADDRESS %h",addr);end
  end
  if(dut.state==8)begin
   if(packet_old||packet_generation<generation)begin last_old_finish=$realtime;old_finishes=old_finishes+1;end
   else if(first_clear_finish<0)begin first_clear_finish=$realtime;if(packet_addr!==0)$fatal(1,"FIRST CLEAR COMPLETION ADDRESS");end
  end
 end
 // Observe settled registered phases. BEGIN's deassertion and clearing's
 // cancellation can produce a zero-delta combinational active event, which is
 // not an accepted request at a real memory/system clock edge.
 reg sampled_active=0,sampled_busy=0;integer starts=0;
 always @(posedge clk)begin
  #0.001;
  if(active&&!sampled_active)begin
   starts=starts+1;clear_sys=0;first_clear_accept=-1;first_clear_finish=-1;word_zero_late=0;
   clear_time=$realtime-0.001;clear_state=dut.state;arclear_state=aram.state;
   if(psram_busy||aram_busy)$fatal(1,"CLEAR START BEFORE IDLE");
   if(!host_quiescent)$fatal(1,"CLEAR START WITHOUT HOST QUIESCENT");
  end
  if(!active&&sampled_active&&!image_begin)clear_end_time=$realtime-0.001;
  if(!barrier_busy&&sampled_busy&&clear_end_time>0)begin
   busy_end_time=$realtime-0.001;
   if(psram_busy||aram_busy)$fatal(1,"CLEAR BARRIER RELEASED BEFORE PHYSICAL TAIL");
  end
  sampled_active=active;sampled_busy=barrier_busy;
 end
 always @(posedge clk)begin
  if(active&&clear_addr==0)begin
   clear_sys=clear_sys+1;
   if(frontier.divider==3)begin
    if(mem.mem[0][7:0]!==fill(0))$fatal(1,"ZERO BYTE DEADLINE kind=%0d phase=%0d state=%0d mem=%h clear_sys=%0d",kind,phase,clear_state,mem.mem[0],clear_sys);
    if(clear_sys!=4)$fatal(1,"ZERO RESIDENCE %0d",clear_sys);
   end
  end
  if(active&&clear_addr==1&&frontier.divider==3)
   if(mem.mem[0]!=={fill(1),fill(0)})word_zero_late=1;
 end
 initial begin
  if($value$plusargs("phase=%d",phase))begin end
  if($value$plusargs("kind=%d",kind))begin end
  if($value$plusargs("old_addr=%d",old_addr))begin end
  if($value$plusargs("fillmode=%d",fillmode))begin end
  if($value$plusargs("host_delay=%d",host_delay))begin end
  if($value$plusargs("full=%d",full))begin end
  if($value$plusargs("akind=%d",akind))begin end
  if($value$plusargs("alead=%d",alead))begin end
  if($value$plusargs("restart=%d",restart))begin end
  repeat(3)@(posedge clk);#0.01;hard_reset_n=1;repeat(5)@(posedge clk);
  aram_launch<=1;repeat(alead)@(posedge clk);
  launch<=1;
  repeat(phase+1)@(posedge clk);
  begin_time=$realtime;begin_state=dut.state;arbegin_state=aram.state;
  // Queue registers BEGIN and busy here; frontier observes BEGIN next sys edge.
  image_busy<=1;save_busy<=1;image_begin<=1;
  @(posedge clk);image_begin<=0;
  if(restart!=0)begin
   wait(active&&clear_addr==3);repeat(restart-1)@(posedge clk);
   @(posedge clk);image_begin<=1;begin_time=$realtime;begin_state=dut.state;arbegin_state=aram.state;
   @(posedge clk);image_begin<=0;
  end
  if(full!=0)begin wait(starts==(restart!=0?2:1));wait(clear_end_time>clear_time);wait(!psram_busy&&!aram_busy);physical_tail=$realtime-clear_end_time;wait(!barrier_busy);#(2*T);end
  else begin wait(starts==(restart!=0?2:1)&&active&&clear_addr==8);#(2*T);end
  if(clear_time-begin_time<7.99*T)$fatal(1,"BEGIN/PENDING PIPELINE");
  if(arlast_old_accept>begin_time+0.01*T)$fatal(1,"ARAM OLD ADMISSION TOO LATE");
  if(arlast_old_finish>=clear_time&&arlast_old_finish>=0)$fatal(1,"ARAM OLD WRITE AFTER CLEAR");
  if(last_old_accept>begin_time+0.01*T)$fatal(1,"OLD ADMISSION TOO LATE");
  if(last_old_finish>=clear_time&&old_finishes>0)$fatal(1,"OLD WRITE AFTER CLEAR");
  for(integer i=0;i<(full!=0?131072:8);i=i+1)
   if((i[0]?mem.mem[i>>1][15:8]:mem.mem[i>>1][7:0])!==fill(17'(i)))$fatal(1,"CLEAR INTEGRITY byte=%0d",i);
  if(full!=0)for(integer i=0;i<65536;i=i+1)
   if((i[0]?amem.mem[i>>1][15:8]:amem.mem[i>>1][7:0])!==fill(17'(i)))$fatal(1,"ARAM CLEAR INTEGRITY byte=%0d",i);
  if(full==0&&old_finishes>0&&old_addr>=16)
   if((old_addr[0]?mem.mem[old_addr>>1][15:8]:mem.mem[old_addr>>1][7:0])!==8'h3c)$fatal(1,"OLD PACKET CORRUPTED");
  $display("PASS CLEAR PAL=%0d kind=%0d phase=%0d old_addr=%0d fill=%0d begin_state=%0d clear_state=%0d late_old_accepts=%0d old_finishes=%0d first_accept_T=%0.3f first_finish_T=%0.3f last_old_T=%0.3f word_zero_late=%0d blocked_stage=%0d host_delay=%0d full=%0d physical_tail_T=%0.3f akind=%0d alead=%0d arbegin_state=%0d arclear_state=%0d clear_start_T=%0.3f busy_tail_T=%0.3f",PAL,kind,phase,old_addr,fillmode,begin_state,clear_state,late_old_accepts,old_finishes,(first_clear_accept-clear_time)/T,(first_clear_finish-clear_time)/T,(last_old_finish-clear_time)/T,word_zero_late,blocked_stage,host_delay,full,physical_tail/T,akind,alead,arbegin_state,arclear_state,(clear_time-begin_time)/T,(full!=0?(busy_end_time-clear_end_time)/T:0.0));$finish;
 end
 initial begin if(dut.STATE_WRITE_DATA_END!=8||dut.STATE_READ_DATA_RECEIVED!=27)$fatal(1,"PSRAM BOUND CHANGED");end
 initial begin #50000000;$fatal(1,"timeout");end
endmodule
