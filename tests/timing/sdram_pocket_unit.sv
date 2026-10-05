module sdram_unit(input clk,init,input [23:0] addr,input [15:0] din,input wr,rd,word,
output [15:0] q,inout [15:0] dq,output [12:0] a,output dqml,dqmh,output [1:0] ba,
output ncs,nwe,nras,ncas,sclk,cke);
sdram controller(.clk(clk),.init(init),.addr0(addr),.din0(din),.dout0(q),.wr0(wr),.rd0(rd),.word0(word),
.addr1(24'd0),.din1(16'd0),.dout1(),.wr1(1'b0),.rd1(1'b0),.rfs1(1'b0),.word1(1'b0),
.sni_addr(25'd0),.sni_din(16'd0),.sni_dout(),.sni_wr_req(1'b0),.sni_rd_req(1'b0),.sni_word(1'b0),.sni_ready(),
.SDRAM_DQ(dq),.SDRAM_A(a),.SDRAM_DQML(dqml),.SDRAM_DQMH(dqmh),.SDRAM_BA(ba),.SDRAM_nCS(ncs),.SDRAM_nWE(nwe),.SDRAM_nRAS(nras),.SDRAM_nCAS(ncas),.SDRAM_CLK(sclk),.SDRAM_CKE(cke));
endmodule
