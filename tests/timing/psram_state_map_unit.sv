// Actual dual PSRAM map fixture, retaining the production WRAM/ARAM hierarchy.
module psram_state_map_unit(input wire clk,input wire [1:0] bank_sel,write_en,write_high_byte,write_low_byte,read_en,
 input wire [43:0] addr,input wire [31:0] data_in,inout wire [31:0] cram_dq,
 input wire [1:0] cram_wait,output wire [1:0] read_avail,busy,cram_clk,cram_adv_n,cram_cre,cram_ce0_n,cram_ce1_n,cram_oe_n,cram_we_n,cram_ub_n,cram_lb_n,
 output wire [31:0] data_out,output wire [11:0] cram_a);
state_map_core ic(.clk(clk),.bank_sel(bank_sel),.write_en(write_en),.write_high_byte(write_high_byte),.write_low_byte(write_low_byte),.read_en(read_en),.addr(addr),.data_in(data_in),.cram_dq(cram_dq),.cram_wait(cram_wait),.read_avail(read_avail),.busy(busy),.cram_clk(cram_clk),.cram_adv_n(cram_adv_n),.cram_cre(cram_cre),.cram_ce0_n(cram_ce0_n),.cram_ce1_n(cram_ce1_n),.cram_oe_n(cram_oe_n),.cram_we_n(cram_we_n),.cram_ub_n(cram_ub_n),.cram_lb_n(cram_lb_n),.data_out(data_out),.cram_a(cram_a));
endmodule
module state_map_core(input wire clk,input wire [1:0] bank_sel,write_en,write_high_byte,write_low_byte,read_en,
 input wire [43:0] addr,input wire [31:0] data_in,inout wire [31:0] cram_dq,
 input wire [1:0] cram_wait,output wire [1:0] read_avail,busy,cram_clk,cram_adv_n,cram_cre,cram_ce0_n,cram_ce1_n,cram_oe_n,cram_we_n,cram_ub_n,cram_lb_n,
 output wire [31:0] data_out,output wire [11:0] cram_a);
state_map_snes snes(.clk(clk),.bank_sel(bank_sel),.write_en(write_en),.write_high_byte(write_high_byte),.write_low_byte(write_low_byte),.read_en(read_en),.addr(addr),.data_in(data_in),.cram_dq(cram_dq),.cram_wait(cram_wait),.read_avail(read_avail),.busy(busy),.cram_clk(cram_clk),.cram_adv_n(cram_adv_n),.cram_cre(cram_cre),.cram_ce0_n(cram_ce0_n),.cram_ce1_n(cram_ce1_n),.cram_oe_n(cram_oe_n),.cram_we_n(cram_we_n),.cram_ub_n(cram_ub_n),.cram_lb_n(cram_lb_n),.data_out(data_out),.cram_a(cram_a));
endmodule
module state_map_snes(input wire clk,input wire [1:0] bank_sel,write_en,write_high_byte,write_low_byte,read_en,
 input wire [43:0] addr,input wire [31:0] data_in,inout wire [31:0] cram_dq,
 input wire [1:0] cram_wait,output wire [1:0] read_avail,busy,cram_clk,cram_adv_n,cram_cre,cram_ce0_n,cram_ce1_n,cram_oe_n,cram_we_n,cram_ub_n,cram_lb_n,
 output wire [31:0] data_out,output wire [11:0] cram_a);
psram #(.CLOCK_SPEED(85.9)) wram(.clk(clk),.bank_sel(bank_sel[0]),.write_en(write_en[0]),.write_high_byte(write_high_byte[0]),.write_low_byte(write_low_byte[0]),.read_en(read_en[0]),.addr(addr[21:0]),.data_in(data_in[15:0]),.cram_dq(cram_dq[15:0]),.cram_wait(cram_wait[0]),.read_avail(read_avail[0]),.busy(busy[0]),.cram_clk(cram_clk[0]),.cram_adv_n(cram_adv_n[0]),.cram_cre(cram_cre[0]),.cram_ce0_n(cram_ce0_n[0]),.cram_ce1_n(cram_ce1_n[0]),.cram_oe_n(cram_oe_n[0]),.cram_we_n(cram_we_n[0]),.cram_ub_n(cram_ub_n[0]),.cram_lb_n(cram_lb_n[0]),.data_out(data_out[15:0]),.cram_a(cram_a[5:0]));
psram #(.CLOCK_SPEED(85.9)) aram(.clk(clk),.bank_sel(bank_sel[1]),.write_en(write_en[1]),.write_high_byte(write_high_byte[1]),.write_low_byte(write_low_byte[1]),.read_en(read_en[1]),.addr(addr[43:22]),.data_in(data_in[31:16]),.cram_dq(cram_dq[31:16]),.cram_wait(cram_wait[1]),.read_avail(read_avail[1]),.busy(busy[1]),.cram_clk(cram_clk[1]),.cram_adv_n(cram_adv_n[1]),.cram_cre(cram_cre[1]),.cram_ce0_n(cram_ce0_n[1]),.cram_ce1_n(cram_ce1_n[1]),.cram_oe_n(cram_oe_n[1]),.cram_we_n(cram_we_n[1]),.cram_ub_n(cram_ub_n[1]),.cram_lb_n(cram_lb_n[1]),.data_out(data_out[31:16]),.cram_a(cram_a[11:6]));
endmodule
