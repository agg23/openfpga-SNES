module savestates
(
	input reset_n,
	input clk,

	input             save,
	input             save_sd,
	input             load,
	input       [1:0] slot,

	input       [3:0] ram_size,
	input       [7:0] rom_type,

	input             sysclkf_ce,
	input             sysclkr_ce,

	input             romsel_n,

	input      [15:0] rom_q,

	input      [23:0] ca,
	input             cpurd_n,
	input             cpuwr_n,

	input       [7:0] pa,
	input             pard_n,
	input             pawr_n,

	input       [7:0] di,
	output reg  [7:0] ss_do,

	output     [23:0] rom_addr,

	output     [19:0] ext_addr,

	input       [7:0] spc_di,

	input      [63:0] ddr_di,
	output reg [63:0] ddr_do,
	input             ddr_ack,
	output     [21:3] ddr_addr,
	output reg        ddr_we,
	output reg  [7:0] ddr_be,
	output reg        ddr_req,

	output            aram_sel,
	output            dsp_regs_sel,
	output            smp_regs_sel,

	input       [7:0] ppu_di,

	output            bsram_sel,
	input       [7:0] bsram_di,

	output            dspn_regs_sel,
	output            dspn_ram_sel,
	input       [7:0] dspn_di,

	output            gsu_regs_sel,
	input       [7:0] gsu_di,

	input             sa1_active,
	input      [23:0] sa1_a,
	input       [7:0] sa1_di,
	input             sa1_rd_n,
	input             sa1_wr_n,
	input             sa1_sa1_romsel,
	input             sa1_sns_romsel,

	output            ss_do_ovr,
	output            ss_rom_ovr,
	output reg        ss_busy
);

reg cpurd_n_old, cpuwr_n_old;
reg pawr_n_old, pard_n_old;
reg save_old, load_old;

always @(posedge clk or negedge reset_n) begin
	if (~reset_n) begin
		cpurd_n_old <= 1'b1;
		cpuwr_n_old <= 1'b1;
		pard_n_old <= 1'b1;
		pawr_n_old <= 1'b1;
		save_old <= 0;
		load_old <= 0;
	end else begin
		cpurd_n_old <= cpurd_n;
		cpuwr_n_old <= cpuwr_n;

		pawr_n_old <= pawr_n;
		pard_n_old <= pard_n;

		save_old <= save;
		load_old <= load;
	end
end

wire cpurd_ce   =  cpurd_n_old & ~cpurd_n;
wire cpurd_ce_n = ~cpurd_n_old &  cpurd_n;
wire cpuwr_ce   =  cpuwr_n_old & ~cpuwr_n;
wire cpuwr_ce_n = ~cpuwr_n_old &  cpuwr_n;

wire pard_ce   =  pard_n_old & ~pard_n;
wire pard_ce_n = ~pard_n_old &  pard_n;
wire pawr_ce   =  pawr_n_old & ~pawr_n;
wire pawr_ce_n = ~pawr_n_old &  pawr_n;

reg save_en;
reg load_en;
reg rd_rti;
reg save_end;

wire nmi_vect = ({ca[23:1],1'b0} == 24'h00FFEA);
wire nmi_vect_l = nmi_vect & ~ca[0];
wire nmi_vect_h = nmi_vect &  ca[0];

wire irq_vect = ({ca[23:1],1'b0} == 24'h00FFEE);
wire irq_vect_l = irq_vect & ~ca[0];
wire irq_vect_h = irq_vect &  ca[0];

wire ss_reg_sel = (ca[23:16] == 8'hC0);

reg [19:0] ss_data_addr;
reg [19:0] ss_data_size;
reg [19:0] ss_ddr_addr;
reg [1:0] ss_slot;
reg ss_data_addr_inc;
wire ss_data_sel = ss_reg_sel & (ca[15:0] == 16'h6000);
wire ss_addr_sel = ss_reg_sel & (ca[15:0] == 16'h6001);
wire ss_ext_addr_sel = ss_reg_sel & (ca[15:0] == 16'h6002);
wire ss_ramsize_sel = ss_reg_sel & (ca[15:0] == 16'h6003);
wire ss_romtype_sel = ss_reg_sel & (ca[15:0] == 16'h6004);
wire ss_end_sel = ss_reg_sel & (ca[15:0] == 16'h600E);
wire ss_status_sel = ss_reg_sel & (ca[15:0] == 16'h600F);

assign dspn_regs_sel = ss_reg_sel & (ca[15:8] == 8'h61);
assign gsu_regs_sel = ss_reg_sel & (ca[15:8] == 8'h62);

wire ppu_sel = (ca[23:16] == 8'hC1) & (ca[15:8] == 8'h21);

wire rti_sel = (ca[23:0] == 24'h008008);

reg [19:0] ss_ext_addr;
reg ss_ext_addr_inc;

wire spc_sel = (aram_sel | dsp_regs_sel | smp_regs_sel);
wire spc_read = spc_sel & ~pard_n;

wire bsram_read = bsram_sel & ~pard_n;

wire dspn_ram_read = dspn_ram_sel & ~pard_n;

reg [3:0] ddr_state;
reg [7:0] ddr_data;
reg load_ready;

wire ddr_busy = ddr_req != ddr_ack;

localparam DDR_IDLE = 4'd0, LOAD_DATA = 4'd1, WRITE_DATA = 4'd2,
			WRITE_CNTSIZE = 4'd3, READ_HEAD = 4'd4,	READ_HEAD_END = 4'd5,
			DDR_END = 4'd6;

reg [31:0] ss_count = 0;

// Detect if NMI is being used. Some games do not use NMI during game play.
reg [15:0] nmi_cycle_cnt, nmi_read_sr;
wire ss_use_nmi = |nmi_read_sr;
always @(posedge clk) begin
	if (~reset_n) begin
		nmi_cycle_cnt <= 0;
		nmi_read_sr   <= 0;
	end else if (sysclkf_ce) begin
		nmi_cycle_cnt <= nmi_cycle_cnt + 1'b1;
		if (&nmi_cycle_cnt | (~cpurd_n & nmi_vect_l)) begin
			nmi_read_sr <= { nmi_read_sr[14:0], nmi_vect_l };
			nmi_cycle_cnt <= 0;
		end
	end
end


always @(posedge clk) begin
	if (~reset_n) begin
		ss_busy <= 0;
		save_en <= 0;
		load_en <= 0;
		save_end <= 0;
		load_ready <= 0;
		rd_rti <= 0;
		ss_data_addr <= 0;
		ss_data_addr_inc <= 0;
		ss_ext_addr <= 0;
		ss_ext_addr_inc <= 0;
		ddr_state <= DDR_IDLE;
	end else begin
		if (~(load_en | save_en)) begin
			if (~save_old & save) begin
				save_en <= 1;
				ss_slot <= slot;
			end else if (~load_old & load) begin
				load_en <= 1;
				ss_slot <= slot;
				ddr_state <= READ_HEAD; // Check header in RAM
				load_ready <= 0;
			end
		end

		if (cpurd_ce) begin
			if (nmi_vect_l | (~ss_use_nmi & irq_vect_l)) begin // Prefer to use NMI
				if (~ss_busy & (save_en | (load_en & load_ready))) begin
					ss_busy <= 1; // Override NMI/IRQ vector
					if (save_en) begin
						ss_count <= ss_count + 1'b1;
					end
				end
			end

			if (ss_busy & rti_sel) begin
				rd_rti <= 1;
			end
		end

		if (cpurd_ce_n) begin
			if (rd_rti) begin
				ss_busy <= 0;
				rd_rti <= 0;
				load_en <= 0;
				save_en <= 0;
				save_end <= 0;
			end
		end

		if (cpuwr_ce & ss_busy) begin
			if (ss_addr_sel) begin // Reset save state address
				ss_data_addr <= 20'd8;
				if (load_en) begin
					// Request new data when address is reset
					ddr_state <= LOAD_DATA;
				end
			end

			if (ss_ext_addr_sel) begin
				ss_ext_addr <= 0;
			end

			if (ss_end_sel) begin // Saving finished
				save_end <= 1;
				ss_data_size <= ss_data_addr;
				// Write header to DDR so HPS can save it to SD card.
				if (ss_data_addr[2:0] != 3'd0) begin
					// Write remaining data first
					ddr_state <= WRITE_DATA;
				end else begin
					ddr_state <= WRITE_CNTSIZE;
				end
			end
		end

		if (cpuwr_ce | cpurd_ce) begin
			if (ss_data_sel & ss_busy) begin
				ss_data_addr_inc <= 1;
			end
		end

		if (cpuwr_ce_n | cpurd_ce_n) begin
			if (ss_data_addr_inc) begin
				ss_data_addr <= ss_data_addr + 1'b1;
				ss_data_addr_inc <= 0;
				if (cpurd_ce_n & (ss_data_addr[2:0] == 3'd7)) begin
					// Request next 8 bytes
					ddr_state <= LOAD_DATA;
				end
			end
		end

		if (pawr_ce | pard_ce) begin
			if (spc_sel | bsram_sel | dspn_ram_sel) begin
				ss_ext_addr_inc <= 1;
			end
		end

		if (pawr_ce_n | pard_ce_n) begin
			if (ss_ext_addr_inc) begin
				ss_ext_addr <= ss_ext_addr + 1'b1;
				ss_ext_addr_inc <= 0;
			end
		end

		if (~cpuwr_n & sysclkf_ce & ss_busy & ss_data_sel) begin // Data write
			if (ss_data_addr[2:0] == 3'd0) begin
				ddr_do[63:8] <= 0; // Clear for possible partial last write
			end

			ddr_do[ss_data_addr[2:0]*8 +:8] <= ddr_data;

			if (ss_data_addr[2:0] == 3'd7) begin // 8 bytes written
				ddr_state <= WRITE_DATA;
			end
		end

		ddr_we <= 0;
		ddr_be <= 8'hFF;

		if (ddr_req == ddr_ack) begin
			case(ddr_state)
				LOAD_DATA: begin
					ss_ddr_addr <= ss_data_addr;
					ddr_req <= ~ddr_req;
					ddr_state <= DDR_END;
				end
				WRITE_DATA: begin
					ss_ddr_addr <= ss_data_addr;
					ddr_req <= ~ddr_req;
					ddr_we <= 1;
					ddr_state <= save_end ? WRITE_CNTSIZE : DDR_END;
				end
				WRITE_CNTSIZE: begin
					ddr_do <= {14'd0, ss_data_size[19:2], ss_count[31:0]};
					ss_ddr_addr <= 20'd0;
					ddr_we <= 1;
					ddr_req <= ~ddr_req;
					if (~save_sd) begin
						ddr_be <= 8'hF0; // Skip count write
					end
					ddr_state <= DDR_END;
				end
				READ_HEAD: begin
					ss_ddr_addr <= 20'd8;
					ddr_req <= ~ddr_req;
					ddr_state <= READ_HEAD_END;
				end
				READ_HEAD_END: begin
					ddr_state <= DDR_END;
					if (ddr_di[31:0] == 32'h5345_4E53) begin // "SNES"
						load_ready <= 1; // State found
					end else begin
						load_en <= 0;
					end
				end

				DDR_END: begin
					ddr_state <= DDR_IDLE;
				end
			endcase

		end
	end
end

wire [15:0] nmi_vect_addr = save_en ? 16'h8000 : 16'h8004;

wire [7:0] ssr_do;
wire ssr_oe;
savestates_regs ss_regs
(
	.reset_n(reset_n),
	.clk(clk),

	.ss_busy(ss_busy),
	.save_en(save_en),

	.ss_reg_sel(ss_reg_sel),

	.sysclkf_ce(sysclkf_ce),
	.sysclkr_ce(sysclkr_ce),

	.romsel_n(romsel_n),

	.ca(ca),
	.cpurd_ce(cpurd_ce),
	.cpurd_ce_n(cpurd_ce_n),
	.cpuwr_ce(cpuwr_ce),

	.pa(pa),

	.pard_ce(pard_ce),
	.pawr_ce(pawr_ce),

	.di(di),
	.ssr_do(ssr_do),
	.ssr_oe(ssr_oe)
);

wire [ 7:0] map_ss_do;
wire        map_ss_oe;
wire [15:0] map_rom_addr;
wire        map_rom_ovr;
wire        map_active;

savestates_map ss_map
(
	.reset_n(reset_n),
	.clk(clk),

	.ss_busy(ss_busy),
	.save_en(save_en),

	.ss_reg_sel(ss_reg_sel),

	.sysclkf_ce(sysclkf_ce),
	.sysclkr_ce(sysclkr_ce),

	.ca(ca),
	.cpurd_n(cpurd_n),
	.cpuwr_n(cpuwr_n),
	.cpuwr_ce(cpuwr_ce),

	.pa(pa),
	.pard_n(pard_n),
	.pawr_n(pawr_n),

	.di(di),

	.sa1_active(sa1_active),

	.sa1_a(sa1_a),
	.sa1_rd_n(sa1_rd_n),
	.sa1_wr_n(sa1_wr_n),
	.sa1_di(sa1_di),
	.sa1_sa1_romsel(sa1_sa1_romsel),
	.sa1_sns_romsel(sa1_sns_romsel),

	.map_active(map_active),

	.rom_addr(map_rom_addr),
	.rom_ovr(map_rom_ovr),

	.ss_do(map_ss_do),
	.ss_oe(map_ss_oe)
);


wire ss_oe = ss_data_sel | ss_status_sel | nmi_vect | irq_vect |
			ss_ramsize_sel | ss_romtype_sel | ssr_oe | map_ss_oe |
			ppu_sel | dspn_regs_sel | gsu_regs_sel;

always @(posedge clk) begin
	ss_do <= 8'h00;
	if (ss_data_sel) ss_do <= ddr_di[ss_data_addr[2:0]*8 +:8];
	if (ss_status_sel) ss_do <= { 6'd0, ddr_busy, save_en };
	if (nmi_vect_l | irq_vect_l) ss_do <= nmi_vect_addr[7:0];
	if (nmi_vect_h | irq_vect_h) ss_do <= nmi_vect_addr[15:8];
	if (ss_ramsize_sel) ss_do <= { 4'd0, ram_size };
	if (ss_romtype_sel) ss_do <= rom_type;
	if (ssr_oe) ss_do <= ssr_do;
	if (map_ss_oe) ss_do <= map_ss_do;
	if (ppu_sel) ss_do <= ppu_di;
	if (dspn_regs_sel) ss_do <= dspn_di;
	if (gsu_regs_sel) ss_do <= gsu_di;
end

always @(*) begin
	// savestate.bin ROM
	rom_addr[23:16] = { 2'b11, 6'b11_1111 };
	rom_addr[15: 0] = { ca[16], ca[14:0] };
	if (map_rom_ovr) begin
		rom_addr[15:0] = map_rom_addr;
	end
end

// Data to DDRAM
always @(*) begin
	ddr_data = di;
	if (spc_read) ddr_data = spc_di;
	if (bsram_read) ddr_data = bsram_di;
	if (dspn_ram_read) ddr_data = dspn_di;
end

assign ss_do_ovr = ss_busy & ss_oe;
assign ss_rom_ovr = map_active ? map_rom_ovr : ss_busy;

assign aram_sel = ss_busy & (pa == 8'h84);
assign dsp_regs_sel = ss_busy & (pa == 8'h85);
assign smp_regs_sel = ss_busy & (pa == 8'h86);
assign bsram_sel = ss_busy & (pa == 8'h87);
assign dspn_ram_sel = ss_busy & (pa == 8'h88);
assign ext_addr = ss_ext_addr;

assign ddr_addr = { ss_slot[1:0], ss_ddr_addr[19:3] };

endmodule