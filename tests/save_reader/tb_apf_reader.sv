// SPDX-License-Identifier: MIT
// Real APF serial bridge + data_unloader + source-derived Intel Save BRAM.
`timescale 1ns/1ps
module tb_apf_reader #(parameter DELAY=2);
 reg src=0,sys=0,reset_n=0;
 integer pal=0,phase=0,ss_high_cycles=6;real halfsys=23.280,phase_ns=0;
 always #(500.0/74.25) src=~src;
 initial begin
  if($value$plusargs("pal=%d",pal));if($value$plusargs("phase=%d",phase));
  if($value$plusargs("ss_high_cycles=%d",ss_high_cycles));
  halfsys=pal?(500.0/21.281370):(500.0/21.477270);phase_ns=2.0*halfsys*phase/16.0;
  #(phase_ns);forever #(halfsys)sys=~sys;
 end
 reg ss=0,host_drive=0,host_clk=0,host_mosi=0,host_miso=0;
 tri spiclk,mosi,miso;
 assign spiclk=host_drive?host_clk:1'bz;
 assign mosi=host_drive?host_mosi:1'bz;
 assign miso=host_drive?host_miso:1'bz;
 wire[31:0]addr,result;wire rd,re;wire[16:0]ra;wire[15:0]q;
 // Production core_top drives endian_little=0. Use the original APF module.
 io_bridge_peripheral apf(.clk(src),.reset_n(reset_n),.endian_little(1'b0),
 .pmp_addr(addr),.pmp_addr_valid(),.pmp_rd(rd),.pmp_rd_data(result),
 .pmp_wr(),.pmp_wr_data(),.phy_spimosi(mosi),.phy_spimiso(miso),.phy_spiclk(spiclk),.phy_spiss(ss));
 data_unloader #(.ADDRESS_MASK_UPPER_4(4'h2),.ADDRESS_SIZE(17),
 .READ_MEM_CLOCK_DELAY(DELAY),.INPUT_WORD_SIZE(2),.SAFE_RESPONSE_HANDSHAKE(1)) reader(
 .clk_74a(src),.clk_memory(sys),.reset_n(reset_n),.bridge_rd(rd),.bridge_endian_little(1'b0),
 .bridge_addr(addr),.bridge_rd_data(result),.read_en(re),.read_addr(ra),.read_data(q));
 reg iw=0;reg[16:0]ia=0;reg[7:0]id=0;
 dpram_dif #(17,8,16,16,"") ram(.clock(sys),.address_a(ia),.data_a(id),.wren_a(iw),.q_a(),
 .address_b(ra[16:1]),.data_b(16'b0),.wren_b(1'b0),.q_b(q));
 function[7:0]byte_at(input integer a);byte_at=((a*37)^(a>>3)^(a>>9)^8'h69)&255;endfunction
 function[31:0]expected(input integer a);expected={byte_at(a),byte_at(a+1),byte_at(a+2),byte_at(a+3)};endfunction
 integer cycle=0,last_accept=0,last_latch=0,requests=0,checks=0,min_interval=100000,max_interval=0,min_budget=100000;
 reg pending=0;reg[31:0]host_expected_addr=0;reg[31:0]wanted=0;reg check_buffer=0;reg[31:0]sampled=0;
 always @(posedge src) begin
  cycle=cycle+1;
  if(reset_n && reader.source_reset_n)begin
   if(reader.data_read_req&&reader.data_empty)$fatal(1,"RESPONSE_FIFO_UNDERFLOW");
   if(reader.address_write_req&&reader.fifo_address_req.wrfull)$fatal(1,"ADDRESS_FIFO_OVERFLOW");
  end
  // This is the actual APF latch edge, not a guessed read-strobe deadline.
  if(apf.state==apf.ST_READ_0 && apf.read_cnt==3)begin
   last_latch=cycle;
   if(pending)begin
    if(result!==wanted)$fatal(1,"APF_LATCH_DEADLINE wanted=%h got=%h age=%0d",wanted,result,cycle-last_accept);
    if(cycle-last_accept<min_budget)min_budget=cycle-last_accept;
    checks=checks+1;sampled=wanted;check_buffer=1;
   end
  end
  if(rd)begin
   if(addr!==host_expected_addr)$fatal(1,"APF_ADDRESS_DECODE wanted=%h got=%h",host_expected_addr,addr);
   if(cycle-last_latch!=2)$fatal(1,"APF_LATCH_STROBE_OFFSET changed=%0d",cycle-last_latch);
   if(requests>0)begin
    if(cycle-last_accept<min_interval)min_interval=cycle-last_accept;
    if(cycle-last_accept>max_interval)max_interval=cycle-last_accept;
   end
   if(addr[31:28]==4'h2)begin wanted=expected(addr[16:0]);pending=1;end
   else pending=0;
   last_accept=cycle;requests=requests+1;
  end
 end
 always @(negedge src)if(check_buffer)begin
  if(apf.spis_word_tx!==sampled)$fatal(1,"APF_BUFFER_DATA wanted=%h got=%h",sampled,apf.spis_word_tx);
  check_buffer=0;
 end
 task read_packet(input[31:0]a);
 integer k;begin
  host_expected_addr=a;
  @(negedge src);ss=1;host_drive=0;
  repeat(ss_high_cycles)@(negedge src);
  ss=0;host_drive=1;host_clk=0;
  // Four address bytes, two bits per SPI edge, one clk74 per half-bit.
  for(k=15;k>=0;k=k-1)begin
   host_mosi=a[2*k+1];host_miso=a[2*k];
   @(negedge src);host_clk=1;
   @(negedge src);host_clk=0;
  end
  host_drive=0;
  wait(rd===1'b1);wait(apf.spis_done===1'b1);
 end endtask
 integer i,a;
 initial begin
  #1;ss=1;
  repeat(8)@(negedge src);reset_n=1;
  for(i=0;i<512;i=i+1)begin
   @(negedge sys);iw=1;ia=(i<256)?i:131072-512+i;id=byte_at(ia);
  end
  @(negedge sys);iw=0;
  repeat(20)@(negedge src);
  for(i=0;i<49;i=i+1)begin
   a=(i%3==0)?131072-4*(1+i%32):4*(i%32);
   // A final unrelated read drains the last Save word without adding Save work.
   read_packet(i==48?32'h10000000:32'h20000000+a);
  end
  @(negedge src);ss=1;repeat(8)@(negedge src);
  if(checks!=48||requests!=49)$fatal(1,"APF_READ_COUNTS checks=%0d requests=%0d",checks,requests);
  $display("PASS APF_READER pal=%0d phase=%0d little=0 ss_high_cycles=%0d checks=%0d requests=%0d min_strobe_cycles=%0d max_strobe_cycles=%0d min_latch_budget_cycles=%0d",pal,phase,ss_high_cycles,checks,requests,min_interval,max_interval,min_budget);
  $finish;
 end
 initial begin #5000000;$fatal(1,"TIMEOUT");end
endmodule
