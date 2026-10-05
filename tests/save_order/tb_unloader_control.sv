// SPDX-License-Identifier: MIT
// Original, unchanged loader/unloader and actual Intel RAM/FIFOs. No ROM queue.
`timescale 1ns/1ps
module tb_unloader_control;
 reg src=0,sys=0;always #6.734 src=~src;always #23.280 sys=~sys;
 reg wr=0,rd=0;reg[31:0]addr=0,data=0;wire en,re;wire[16:0]wa,ra;wire[15:0]wd,qb;wire[31:0]result;
 data_loader #(.ADDRESS_MASK_UPPER_4(4'h2),.ADDRESS_SIZE(17),.WRITE_MEM_CLOCK_DELAY(7),.OUTPUT_WORD_SIZE(2)) loader(
 .clk_74a(src),.clk_memory(sys),.bridge_wr(wr),.bridge_endian_little(1'b1),.bridge_addr(addr),.bridge_wr_data(data),.write_en(en),.write_addr(wa),.write_data(wd));
 data_unloader #(.ADDRESS_MASK_UPPER_4(4'h2),.ADDRESS_SIZE(17),.READ_MEM_CLOCK_DELAY(7),.INPUT_WORD_SIZE(2)) reader(
 .clk_74a(src),.clk_memory(sys),.bridge_rd(rd),.bridge_endian_little(1'b1),.bridge_addr(addr),.bridge_rd_data(result),.read_en(re),.read_addr(ra),.read_data(qb));
 dpram_dif #(17,8,16,16) ram(.clock(sys),.address_a(17'd0),.data_a(8'd0),.wren_a(1'b0),.q_a(),.address_b(en?wa[16:1]:ra[16:1]),.data_b(wd),.wren_b(en),.q_b(qb));
 integer nw=0,nr=0;
 always @(posedge sys)begin
 if(en)begin nw=nw+1;$display("CONTROL_WRITE addr=%h data=%h ns=%0.3f",wa,wd,$realtime);end
 if(reader.data_read_state==9)begin nr=nr+1;$display("CONTROL_READ_SAMPLE addr=%h data=%h ns=%0.3f",ra,qb,$realtime);end
 end
 initial begin
 repeat(40)@(negedge src);addr=32'h20000000;data=32'h44332211;wr=1;@(negedge src);wr=0;
 repeat(200)@(negedge sys);
 if(nw!=2||{ram.altsyncram_component.m_default.altsyncram_inst.mem_data[3],ram.altsyncram_component.m_default.altsyncram_inst.mem_data[2],ram.altsyncram_component.m_default.altsyncram_inst.mem_data[1],ram.altsyncram_component.m_default.altsyncram_inst.mem_data[0]}!==32'h44332211)$fatal(1,"CONTROL_RESTORE_FAILED");
 @(negedge src);rd=1;@(negedge src);rd=0;repeat(300)@(negedge src);
 $display("CONTROL_RESULT no_pending_restore=1 sampled_halfwords=%0d got=%h wanted=44332211",nr,result);
 if(nr!=2)$fatal(1,"CONTROL_READ_MISSING");
 if(result!==32'h44332211)$fatal(1,"EXPECTED_PREEXISTING_UNLOADER_DATA_FAILURE");
 $display("PASS ORIGINAL_UNLOADER_CONTROL");$finish;
 end
endmodule
