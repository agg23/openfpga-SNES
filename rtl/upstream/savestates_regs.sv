module savestates_regs
(
	input reset_n,
	input clk,

	input ss_busy,
	input save_en,

	input ss_reg_sel,

	input sysclkf_ce,
	input sysclkr_ce,

	input romsel_n,

	input [23:0] ca,
	input cpurd_ce,
	input cpurd_ce_n,
	input cpuwr_ce,

	input [7:0] pa,
	input pard_ce,
	input pawr_ce,

	input [7:0] di,
	output reg [7:0] ssr_do,
	output reg ssr_oe
);

wire mmio_sel = (ca[15:10] == 6'b010000);
wire io_sel = ~ca[22] & mmio_sel; // $00-$3F/$80-$BF:$4000-$43FF
wire ss_io_sel = ss_reg_sel & mmio_sel; // $C0:$4000-$43FF

wire ss_inidisp_sel = ss_reg_sel & (ca[15:0] == 16'h2100);

wire wram_sel = (ca[15:8] == 8'h21) & (ca[7:2] == 6'b100000);

wire ss_temp0_sel = ss_reg_sel & (ca[15:0] == 16'h21F0);
wire ss_temp1_sel = ss_reg_sel & (ca[15:0] == 16'h21F1);
wire ss_temp2_sel = ss_reg_sel & (ca[15:0] == 16'h21F2);

wire ss_temp_sel = (ss_temp0_sel | ss_temp1_sel | ss_temp2_sel);

reg [16:0] wmadd;
reg        nmitimen_j;
reg  [1:0] nmitimen_hv;
reg        nmitimen_n;
reg [ 7:0] wrmpya;
reg [ 7:0] wrmpyb;
reg [15:0] wrdiv;
reg [ 7:0] wrdivb;
reg        wrdivb_last;
reg [ 8:0] htime;
reg [ 8:0] vtime;
reg [ 7:0] hdmaen;
reg        memsel;

reg [ 7:0] dma0[0:6];

reg        ppu_inidisp_fb;
reg [ 3:0] ppu_inidisp_br;

reg [ 7:0] temp_reg[0:2];

always @(posedge clk or negedge reset_n) begin
	 if (~reset_n) begin
		dma0[0] <= 8'hFF;
		dma0[1] <= 8'hFF;
		dma0[2] <= 8'hFF;
		dma0[3] <= 8'hFF;
		dma0[4] <= 8'hFF;
		dma0[5] <= 8'hFF;
		dma0[6] <= 8'hFF;
		wmadd <= 0;
		nmitimen_j <= 0;
		nmitimen_hv <= 0;
		nmitimen_n <= 0;
		wrmpya <= 0;
		wrmpyb <= 0;
		wrdiv <= 0;
		wrdivb <= 8'h01;
		wrdivb_last <= 0;
		htime <= 9'h1FF;
		vtime <= 9'h1FF;
		hdmaen <= 0;
		memsel <= 0;
	 end else begin

		if (cpuwr_ce) begin
			if (ss_busy & ss_io_sel & (ca[9:8] == 2'd3)) begin
				case(ca[7:0])
					// Temp storage for DMA registers during save state
					8'h00: dma0[0] <= di;
					8'h01: dma0[1] <= di;
					8'h02: dma0[2] <= di;
					8'h03: dma0[3] <= di;
					8'h04: dma0[4] <= di;
					8'h05: dma0[5] <= di;
					8'h06: dma0[6] <= di;
					default: ;
				endcase
			end

			// For only writing to the shadow register
			if (ss_busy) begin
				if (ss_inidisp_sel) begin
					ppu_inidisp_fb <= di[7];
					ppu_inidisp_br <= di[3:0];
				end

				if (ss_temp0_sel) begin
					temp_reg[0] <= di;
				end
				if (ss_temp1_sel) begin
					temp_reg[1] <= di;
				end
				if (ss_temp2_sel) begin
					temp_reg[2] <= di;
				end

				if (ss_io_sel) begin
					if (ca[9:8] == 2'd2) begin
						case(ca[7:0])
							8'h00: begin
								nmitimen_j  <= di[0];
								nmitimen_hv <= di[5:4];
								nmitimen_n  <= di[7];
							end
							8'h03: wrmpyb <= di;
							8'h06: wrdivb <= di;
							8'h0C: hdmaen <= di;
							default: ;
						endcase
					end
				end
			end
		end

		if (cpuwr_ce & ~(ss_busy & save_en)) begin
			if (io_sel & (ca[9:8] == 2'd2)) begin
				case(ca[7:0])
					8'h00: begin
						nmitimen_j  <= di[0];
						nmitimen_hv <= di[5:4];
						nmitimen_n  <= di[7];
					end
					8'h02: wrmpya <= di;
					8'h03: begin
						wrmpyb <= di;
						wrdivb_last <= 0;
					end
					8'h04: wrdiv[7:0]  <= di;
					8'h05: wrdiv[15:8] <= di;
					8'h06: begin
						wrdivb <= di;
						wrdivb_last <= 1;
					end
					8'h07: htime[7:0] <= di;
					8'h08: htime[8]   <= di[0];
					8'h09: vtime[7:0] <= di;
					8'h0A: vtime[8]   <= di[0];
					8'h0C: hdmaen     <= di;
					8'h0D: memsel     <= di[0];
					default: ;
				endcase
			end
		end

		if (pawr_ce & ~(ss_busy & save_en)) begin
			if (pa[7:2] == 6'b100000) begin // $80-$83
				case(pa[1:0])
					2'd1: wmadd[ 7: 0] <= di;
					2'd2: wmadd[15: 8] <= di;
					2'd3: wmadd[   16] <= di[0];
					default: ;
				endcase
			end
		end

		if (~ss_busy) begin
			if (pard_ce | pawr_ce) begin
				if (pa[7:0] == 8'h80) begin
					wmadd <= wmadd + 1'b1;
				end
			end
		end

	 end
end

always @(posedge clk) begin
	ssr_oe <= ss_reg_sel & (mmio_sel | ss_inidisp_sel | wram_sel | ss_temp_sel);
	ssr_do <= 8'h00;
	case(ca[7:0])
		8'h00: ssr_do <= dma0[0];
		8'h01: ssr_do <= dma0[1];
		8'h02: ssr_do <= dma0[2];
		8'h03: ssr_do <= dma0[3];
		8'h04: ssr_do <= dma0[4];
		8'h05: ssr_do <= dma0[5];
		8'h06: ssr_do <= dma0[6];
		default: ;
	endcase

	if (mmio_sel & (ca[9:8] == 2'd2)) begin
		case(ca[7:0])
			8'h00: begin
				ssr_do[0]   <= nmitimen_j;
				ssr_do[5:4] <= nmitimen_hv;
				ssr_do[7]   <= nmitimen_n;
			end
			8'h02: ssr_do <= wrmpya;
			8'h03: ssr_do <= wrmpyb;
			8'h04: ssr_do <= wrdiv[ 7:0];
			8'h05: ssr_do <= wrdiv[15:8];
			8'h06: ssr_do <= wrdivb;
			8'h07: ssr_do <= htime[7:0];
			8'h08: ssr_do[0] <= htime[8];
			8'h09: ssr_do <= vtime[7:0];
			8'h0A: ssr_do[0] <= vtime[8];
			8'h0C: ssr_do <= hdmaen;
			8'h0D: ssr_do[0] <= memsel;
			8'h0F: ssr_do[0] <= wrdivb_last;
			default: ;
		endcase
	end

	if (ss_inidisp_sel) begin
		ssr_do[7]   <= ppu_inidisp_fb;
		ssr_do[3:0] <= ppu_inidisp_br;
	end

	if (ss_temp0_sel) begin
		ssr_do <= temp_reg[0];
	end
	if (ss_temp1_sel) begin
		ssr_do <= temp_reg[1];
	end
	if (ss_temp2_sel) begin
		ssr_do <= temp_reg[2];
	end

	if (wram_sel) begin
		case(ca[1:0])
			2'd1: ssr_do <= wmadd[ 7: 0];
			2'd2: ssr_do <= wmadd[15: 8];
			2'd3: ssr_do <= wmadd[   16];
			default: ;
		endcase
	end
end


endmodule
