// SPDX-License-Identifier: MIT
// Cycle trace equivalence of parameter-default path to preserved b63 source.
`timescale 1ns/1ps
module tb_legacy_cycle #(parameter WORD=2,DELAY=7,EARLY_READ=0);
 reg src=0,sys=0;always #6.734 src=~src;always #23.492 sys=~sys;
 reg rd=EARLY_READ,little=0,reset_n=0;reg[31:0]addr=EARLY_READ?32'h20000000:0;wire[31:0]got,refgot;
 wire en,refen;wire[16:0]ra,refra;
 wire[WORD*8-1:0]rddata=ra^(ra>>7)^16'h5639;
 data_unloader #(.ADDRESS_MASK_UPPER_4(4'h2),.ADDRESS_SIZE(17),.READ_MEM_CLOCK_DELAY(DELAY),.INPUT_WORD_SIZE(WORD)) dut(
 .clk_74a(src),.clk_memory(sys),.reset_n(reset_n),.bridge_rd(rd),.bridge_endian_little(little),.bridge_addr(addr),.bridge_rd_data(got),.read_en(en),.read_addr(ra),.read_data(rddata));
 reference_data_unloader #(.ADDRESS_MASK_UPPER_4(4'h2),.ADDRESS_SIZE(17),.READ_MEM_CLOCK_DELAY(DELAY),.INPUT_WORD_SIZE(WORD)) refdut(
 .clk_74a(src),.clk_memory(sys),.bridge_rd(rd),.bridge_endian_little(little),.bridge_addr(addr),.bridge_rd_data(refgot),.read_en(refen),.read_addr(refra),.read_data(rddata));
 integer i,checks=0;
 always @(negedge src)begin
  checks=checks+1;
  if({got,en,ra}!=={refgot,refen,refra})$fatal(1,"LEGACY_CYCLE_MISMATCH");
 end
 initial begin
  for(i=0;i<30000;i=i+1)begin
   @(posedge src);#1;
   rd=(i%250==0);reset_n=(i%67)>6;
   if(i%250==0)begin little=~little;addr=32'h20000000+((i*13)&17'h1fffc);end
  end
  @(negedge src);#1;if(checks!=30000)$fatal(1,"LEGACY_CHECK_COUNT");$display("PASS LEGACY_CYCLE word=%0d delay=%0d clk74_checks=%0d",WORD,DELAY,checks);$finish;
 end
endmodule
