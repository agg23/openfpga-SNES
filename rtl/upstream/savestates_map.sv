module savestates_map
(
	input             reset_n,
	input             clk,

	input             ss_busy,
	input             save_en,

	input             ss_reg_sel,

	input             sysclkf_ce,
	input             sysclkr_ce,

	input      [23:0] ca,
	input             cpurd_n,
	input             cpuwr_n,
	input             cpuwr_ce,

	input       [7:0] pa,
	input             pard_n,
	input             pawr_n,

	input       [7:0] di,

	input             sa1_active,

	input      [23:0] sa1_a,
	input             sa1_rd_n,
	input             sa1_wr_n,
	input       [7:0] sa1_di,
	input             sa1_sa1_romsel,
	input             sa1_sns_romsel,

	output            map_active,

	output     [15:0] rom_addr,
	output            rom_ovr,

	output      [7:0] ss_do,
	output            ss_oe

);

wire  [7:0] sa1_ss_do;
wire        sa1_ss_oe;
wire [15:0] sa1_rom_addr;
wire        sa1_rom_ovr;

savestates_sa1 ss_map_sa1
(
	.reset_n(reset_n),
	.clk(clk),

	.active(sa1_active),

	.ss_busy(ss_busy),
	.save_en(save_en),

	.ss_reg_sel(ss_reg_sel),

	.ca(ca),
	.cpurd_n(cpurd_n),
	.cpuwr_n(cpuwr_n),

	.di(di),

	.sa1_a(sa1_a),
	.sa1_rd_n(sa1_rd_n),
	.sa1_wr_n(sa1_wr_n),
	.sa1_di(sa1_di),

	.sa1_romsel(sa1_sa1_romsel),
	.sns_romsel(sa1_sns_romsel),

	.rom_addr(sa1_rom_addr),
	.rom_ovr(sa1_rom_ovr),

	.ss_do(sa1_ss_do),
	.ss_oe(sa1_ss_oe)
);

assign ss_do = (sa1_ss_do);
assign ss_oe = (sa1_ss_oe);

assign rom_addr = (sa1_rom_addr);
assign rom_ovr = (sa1_rom_ovr);
assign map_active = (sa1_active);


endmodule