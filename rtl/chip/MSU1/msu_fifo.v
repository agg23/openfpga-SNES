
module msu_fifo #(parameter WIDTH, DEPTH)
(
	input	             aclr,

	input	             wrclk,
	input	             wrreq,
	input	 [WIDTH-1:0] data,
	output             wrfull,
	output [DEPTH-1:0] wrusedw,

	input	             rdclk,
	input	             rdreq,
	output [WIDTH-1:0] q,
	output             rdempty,
	output [DEPTH-1:0] rdusedw
);

dcfifo dcfifo_component
(
	.aclr (aclr),
	.data (data),
	.rdclk (rdclk),
	.rdreq (rdreq),
	.wrclk (wrclk),
	.wrreq (wrreq),
	.q (q),
	.rdempty (rdempty),
	.wrfull (wrfull),
	.wrusedw (wrusedw),
	.eccstatus (),
	.rdfull (),
	.rdusedw (rdusedw),
	.wrempty ()
);
defparam
	dcfifo_component.intended_device_family = "Cyclone V",
	dcfifo_component.lpm_numwords = 2**DEPTH,
	dcfifo_component.lpm_showahead = "ON",
	dcfifo_component.lpm_type = "dcfifo",
	dcfifo_component.lpm_width = WIDTH,
	dcfifo_component.lpm_widthu = DEPTH,
	dcfifo_component.overflow_checking = "ON",
	dcfifo_component.rdsync_delaypipe = 4,
	dcfifo_component.read_aclr_synch = "OFF",
	dcfifo_component.underflow_checking = "ON",
	dcfifo_component.use_eab = "ON",
	dcfifo_component.write_aclr_synch = "OFF",
	dcfifo_component.wrsync_delaypipe = 4;

endmodule
