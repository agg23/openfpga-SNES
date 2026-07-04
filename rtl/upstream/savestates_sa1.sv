module savestates_sa1
(
	input             reset_n,
	input             clk,

	input             active,

	input             ss_busy,
	input             save_en,

	input             ss_reg_sel,

	input      [23:0] ca,
	input             cpurd_n,
	input             cpuwr_n,

	input       [7:0] di,

	input      [23:0] sa1_a,
	input             sa1_rd_n,
	input             sa1_wr_n,
	input       [7:0] sa1_di,

	input             sa1_romsel,
	input             sns_romsel,

	output     [15:0] rom_addr,
	output            rom_ovr,

	output reg  [7:0] ss_do,
	output reg        ss_oe

);
wire reset = ~reset_n | ~active;

wire sns_2200_23ff = (ca[15:9] == 7'b0010_001);
wire sns_reg_sel = ~ca[22] & sns_2200_23ff; // $00-$3F/$80-$BF:$2200-$23FF

wire sa1_2200_23ff = (sa1_a[15:9] == 7'b0010_001);
wire sa1_reg_sel = ~sa1_a[22] & sa1_2200_23ff; // $00-$3F/$80-$BF:$2200-$23FF

wire ss_sa1reg_sel = active & ss_reg_sel & sns_2200_23ff; // $C0:$2200-$23FF

wire nmi_vect = ({sa1_a[23:1],1'b0} == 24'h00FFEA);
wire nmi_vect_l = nmi_vect & ~sa1_a[0];

wire reset_vect = ({sa1_a[23:1],1'b0} == 24'h00FFFC);
wire reset_vect_l = reset_vect & ~sa1_a[0];

wire rti_sel = (sa1_a[23:0] == 24'h008008);

reg rd_rti;
reg sa1_ss_busy;

reg sa1_rd_n_old;
always @(posedge clk) begin
	if (reset) begin
		sa1_rd_n_old <= 1'b1;
	end else begin
		sa1_rd_n_old <= sa1_rd_n;
	end
end

always @(posedge clk) begin
	if (reset) begin
		sa1_ss_busy <= 0;
		rd_rti <= 0;
	end else begin
		if (sa1_rd_n_old & ~sa1_rd_n) begin
			if (ss_busy & ~sa1_ss_busy) begin
				if (nmi_vect_l | reset_vect_l) begin
					sa1_ss_busy <= 1;
				end
			end

			if (sa1_ss_busy & rti_sel) begin
				rd_rti <= 1;
			end
		end

		if (~sa1_rd_n_old & sa1_rd_n) begin
			if (rd_rti) begin
				sa1_ss_busy <= 0;
				rd_rti <= 0;
			end
		end

		if (sa1_ss_busy & ~ss_busy) begin
			sa1_ss_busy <= 0;
		end
	end
end

reg [15:0] reg_cnv, reg_crv;
reg sa1_nmi_en, sa1_reset;
always @(posedge clk) begin
	if (reset) begin
		reg_cnv <= 16'd0;
		reg_crv <= 16'd0;
		sa1_nmi_en <= 0;
		sa1_reset <= 1;
	end else begin
		// SNES CPU
		if (~cpuwr_n & ~(ss_busy & save_en)) begin
			if (sns_reg_sel & ~ca[8]) begin // $22xx
				case(ca[7:0])
					8'h00: sa1_reset     <= di[5];
					8'h03: reg_crv[ 7:0] <= di;
					8'h04: reg_crv[15:8] <= di;
					8'h05: reg_cnv[ 7:0] <= di;
					8'h06: reg_cnv[15:8] <= di;
					default: ;
				endcase
			end
		end

		if (~cpuwr_n & ss_sa1reg_sel) begin
			if (~ca[8]) begin // $C0:22xx
				case(ca[7:0])
					8'h00: sa1_reset <= di[5];
					default: ;
				endcase
			end
		end

		// SA-1
		if (~sa1_wr_n & ~(sa1_ss_busy & save_en)) begin
			if (sa1_reg_sel & ~sa1_a[8]) begin // $22xx
				case(sa1_a[7:0])
					8'h0A: sa1_nmi_en <= sa1_di[4];
					default: ;
				endcase
			end
		end

	end

end

always @(posedge clk) begin
	ss_oe <= ss_sa1reg_sel;
	ss_do <= 8'h00;
	if (active) begin
		if (~ca[8]) begin
			case(ca[7:0])
				8'h00: ss_do <= { 2'd0, sa1_reset, 5'd0 };
				8'h03: ss_do <= reg_crv[ 7:0];
				8'h04: ss_do <= reg_crv[15:8];
				8'h05: ss_do <= reg_cnv[ 7:0];
				8'h06: ss_do <= reg_cnv[15:8];
				8'h0A: ss_do <= { 3'd0, sa1_nmi_en, 4'd0 };
				default: ;
			endcase
		end
	end
end

assign rom_addr =	~active ? 16'd0 :
					sa1_romsel ? { sa1_a[16], sa1_a[14:0] } :
								{ ca[16], ca[14:0] };

assign rom_ovr = active & ((ss_busy & sns_romsel) | (sa1_ss_busy & sa1_romsel));

endmodule
