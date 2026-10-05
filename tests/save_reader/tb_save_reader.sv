// SPDX-License-Identifier: MIT
// Actual data_unloader plus the source-derived Intel BRAM primitive wrapper.
`timescale 1ns/1ps
module tb_save_reader #(parameter SAFE=1, DELAY=2, WORD=2);
 reg src=0,sys=0,reset_n=0; integer pal=0,phase=0,little_arg=1,interval=75,reset_case=0;
 real halfsys=23.280,phase_ns=0,start_time,max_latency=0;
 initial begin
  if($value$plusargs("pal=%d",pal)); if($value$plusargs("phase=%d",phase));
  if($value$plusargs("little=%d",little_arg)); if($value$plusargs("interval=%d",interval));
  if($value$plusargs("reset_case=%d",reset_case));
  halfsys=pal?23.492:23.280;phase_ns=2.0*halfsys*phase/16.0;
  #(phase_ns); forever #(halfsys) sys=~sys;
 end
 always #6.734 src=~src;
 reg rd=0;reg[31:0]addr=0;wire[31:0]result;wire re;wire[16:0]ra;
 reg init_write=0;reg[16:0]init_addr=0;reg[7:0]init_data=0;wire[WORD*8-1:0]q;
 data_unloader #(.ADDRESS_MASK_UPPER_4(4'h2),.ADDRESS_SIZE(17),
 .READ_MEM_CLOCK_DELAY(DELAY),.INPUT_WORD_SIZE(WORD),.SAFE_RESPONSE_HANDSHAKE(SAFE)) reader(
 .clk_74a(src),.clk_memory(sys),.reset_n(reset_n),.bridge_rd(rd),.bridge_endian_little(little_arg[0]),
 .bridge_addr(addr),.bridge_rd_data(result),.read_en(re),.read_addr(ra),.read_data(q));
 dpram_dif #(17,8,17-(WORD==2),WORD*8,"") ram(.clock(sys),
 .address_a(init_addr),.data_a(init_data),.wren_a(init_write),.q_a(),
 .address_b(ra[16:(WORD==2)]),.data_b({WORD*8{1'b0}}),.wren_b(1'b0),.q_b(q));
 function[7:0]byte_at(input integer a);byte_at=((a*37)^(a>>3)^(a>>9)^8'h69)&255;endfunction
 function[31:0]expected(input integer a);
 reg[31:0]x;begin x={byte_at(a+3),byte_at(a+2),byte_at(a+1),byte_at(a)};
 expected=little_arg?x:{x[7:0],x[15:8],x[23:16],x[31:24]};end endfunction
 integer requests=0,responses=0,underflows=0;reg[31:0]wanted;reg measuring=0;reg post_reset=0;real latency;
 always @(posedge src)if(SAFE&&reset_n&&reader.source_reset_n)begin
  if(reader.data_read_req&&reader.data_empty)$fatal(1,"FIFO_UNDERFLOW");
  if(reader.address_write_req&&reader.fifo_address_req.wrfull)$fatal(1,"ADDRESS_OVERFLOW");
 end
 always @(negedge src)if(measuring && result===wanted)begin
  latency=$realtime-start_time;if(latency>max_latency)max_latency=latency;measuring=0;responses=responses+1;
 end
 task read_word(input integer a);begin
  // Next read strobe is the protocol deadline for the preceding request.
  if(measuring)$fatal(1,"NEXT_STROBE_DEADLINE previous=%h got=%h",wanted,result);
  addr=32'h20000000+a;rd=1;wanted=expected(a);start_time=$realtime;measuring=1;requests=requests+1;
  @(negedge src);rd=0;repeat(interval-1)@(negedge src);
  if(measuring||result!==wanted)begin
   if(post_reset)$fatal(1,"POST_RESET_READ_DATA wanted=%h got=%h",wanted,result);
   else $fatal(1,"READ_DATA_OR_DEADLINE wanted=%h got=%h interval=%0d",wanted,result,interval);
  end
 end endtask
 integer i,a;
 integer read_starts=0,starts_before=0;
 always @(posedge sys) if(reader.data_read_state==2) read_starts=read_starts+1;
 initial begin
  repeat(8)@(negedge src);reset_n=1;
  for(i=0;i<512;i=i+1)begin
   @(negedge sys);init_write=1;init_addr=(i<256)?i:131072-512+i;init_data=byte_at(init_addr);
  end
  @(negedge sys);init_write=0;
  repeat(20)@(negedge src);
  // Sequential and alternating low/high addresses, including final full word.
  for(i=0;i<48;i=i+1)begin
   a=(i%3==0)?131072-4*(1+i%32):4*(i%32);
   read_word(a);
  end
  if(reset_case)begin
   for(i=0;i<100;i=i+1)begin
    @(negedge src);addr=32'h20000000+4*(i%32);rd=1;
    @(negedge src);rd=0;repeat(i)@(negedge src);
    post_reset=1;reset_n=0;repeat(12)@(negedge src);reset_n=1;repeat(24)@(negedge src);
    if(result!==0)$fatal(1,"RESET_STALE_RESPONSE");
    read_word(131068-4*(i%32));
   end
  end
  if(reset_case)begin
   // A pre-reset strobe held high is not a new post-PLL transaction.
   @(negedge src);reset_n=0;rd=1;addr=32'h20000000;
   repeat(12)@(negedge src);reset_n=1;starts_before=read_starts;
   repeat(150)@(negedge src);
   if(read_starts!=starts_before||result!==0)$fatal(1,"HELD_READ_REPLAYED_AFTER_RESET");
   rd=0;repeat(12)@(negedge src);read_word(131064);
  end
  $display("PASS SAVE_READER pal=%0d phase=%0d little=%0d interval=%0d word=%0d delay=%0d requests=%0d responses=%0d max_response_ns=%0.3f",pal,phase,little_arg,interval,WORD,DELAY,requests,responses,max_latency);
  $finish;
 end
 initial begin #5000000;$fatal(1,"TIMEOUT");end
endmodule
