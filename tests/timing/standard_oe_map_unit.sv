// Unit mapping fixture around the ACTUAL engine. No algorithm or reset edits.
module standard_oe_map_unit(
 input wire clk,reset_n,pll_locked,req_valid,req_write,rsp_ready,
 input wire [31:0] req_addr,input wire [15:0] req_wdata,input wire [1:0] req_wstrb,
 output wire req_ready,rsp_valid,rsp_error,init_done,output wire [15:0] rsp_rdata,
 output wire [12:0] dram_a,output wire [1:0] dram_ba,dram_dqm,
 output wire dram_cke,dram_ras_n,dram_cas_n,dram_we_n,inout wire [15:0] dram_dq);
 wire [15:0] dq_out;wire dq_oe;
 assign dram_dq=dq_oe ? dq_out : 16'hzzzz;
 sdram_single_request engine(.clk_mem(clk),.reset_n(reset_n),.pll_locked(pll_locked),
   .req_valid(req_valid),.req_ready(req_ready),.req_write(req_write),.req_addr(req_addr),
   .req_wdata(req_wdata),.req_wstrb(req_wstrb),.rsp_valid(rsp_valid),.rsp_ready(rsp_ready),
   .rsp_rdata(rsp_rdata),.rsp_error(rsp_error),.init_done(init_done),.dram_cke(dram_cke),
   .dram_cs_n(),.dram_ras_n(dram_ras_n),.dram_cas_n(dram_cas_n),.dram_we_n(dram_we_n),
   .dram_addr(dram_a),.dram_ba(dram_ba),.dram_dqm(dram_dqm),.dq_in(dram_dq),.dq_out(dq_out),.dq_oe(dq_oe));
endmodule
