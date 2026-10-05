module sdram_sys_guard_unit (
input wire mem_clk,sys_clk,reset_request,
input wire [23:0] addr,input wire [15:0] din,input wire wr,rd,word,
output wire [15:0] q,output wire reset_n,
inout wire [15:0] dq,output wire [12:0] a,output wire dqml,dqmh,
output wire [1:0] ba,output wire ncs,nwe,nras,ncas,sclk,cke
);
wire initialized;
pocket_sdram_lifecycle_guard lifecycle(.mem_clk(mem_clk),.sys_clk(sys_clk),
 .reset_request(reset_request),.sdram_initialized(initialized),.reset_n(reset_n),.memory_ready());
sdram #(.POCKET_SYS_CAPTURE(1)) controller(.clk(mem_clk),.sys_clk(sys_clk),.initialized(initialized),.init(1'b0),
 .addr0(addr),.din0(din),.dout0(q),.wr0(wr),.rd0(rd),.word0(word),
 .addr1(24'd0),.din1(16'd0),.dout1(),.wr1(1'b0),.rd1(1'b0),.rfs1(1'b0),.word1(1'b0),
 .sni_addr(25'd0),.sni_din(16'd0),.sni_dout(),.sni_wr_req(1'b0),.sni_rd_req(1'b0),.sni_word(1'b0),.sni_ready(),
 .SDRAM_DQ(dq),.SDRAM_A(a),.SDRAM_DQML(dqml),.SDRAM_DQMH(dqmh),.SDRAM_BA(ba),.SDRAM_nCS(ncs),
 .SDRAM_nWE(nwe),.SDRAM_nRAS(nras),.SDRAM_nCAS(ncas),.SDRAM_CLK(sclk),.SDRAM_CKE(cke));
endmodule
