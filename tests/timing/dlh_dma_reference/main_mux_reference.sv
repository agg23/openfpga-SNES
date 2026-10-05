module MainMuxReference (
 input [19:0] BSX_BSRAM_ADDR,
 input BSX_BSRAM_CE_N,
 input [7:0] BSX_BSRAM_D,
 input BSX_BSRAM_OE_N,
 input BSX_BSRAM_WE_N,
 input [7:0] BSX_DO,
 input BSX_IRQ_N,
 input [22:0] BSX_ROM_ADDR,
 input BSX_ROM_CE_N,
 input [7:0] BSX_ROM_D,
 input BSX_ROM_OE_N,
 input BSX_ROM_WE_N,
 input BSX_ROM_WORD,
 input [19:0] CX4_BSRAM_ADDR,
 input CX4_BSRAM_CE_N,
 input [7:0] CX4_BSRAM_D,
 input CX4_BSRAM_OE_N,
 input CX4_BSRAM_WE_N,
 input [7:0] CX4_DO,
 input CX4_IRQ_N,
 input [22:0] CX4_ROM_ADDR,
 input CX4_ROM_CE_N,
 input CX4_ROM_OE_N,
 input CX4_ROM_WORD,
 input [19:0] DLH_BSRAM_ADDR,
 input DLH_BSRAM_CE_N,
 input [7:0] DLH_BSRAM_D,
 input DLH_BSRAM_OE_N,
 input DLH_BSRAM_WE_N,
 input [7:0] DLH_DO,
 input DLH_IRQ_N,
 input [23:0] DLH_ROM_ADDR,
 input DLH_ROM_CE_N,
 input DLH_ROM_OE_N,
 input DLH_ROM_WORD,
 input [19:0] GSU_BSRAM_ADDR,
 input GSU_BSRAM_CE_N,
 input [7:0] GSU_BSRAM_D,
 input GSU_BSRAM_OE_N,
 input GSU_BSRAM_WE_N,
 input [7:0] GSU_DO,
 input GSU_IRQ_N,
 input [22:0] GSU_ROM_ADDR,
 input GSU_ROM_CE_N,
 input GSU_ROM_OE_N,
 input GSU_ROM_WORD,
 input [6:0] MAP_ACTIVE,
 input [7:0] MSU_DO,
 input MSU_SEL,
 input PARD_N,
 input PAWR_N,
 input [19:0] SA1_BSRAM_ADDR,
 input SA1_BSRAM_CE_N,
 input [7:0] SA1_BSRAM_D,
 input SA1_BSRAM_OE_N,
 input SA1_BSRAM_WE_N,
 input [7:0] SA1_DO,
 input SA1_IRQ_N,
 input [22:0] SA1_ROM_ADDR,
 input SA1_ROM_CE_N,
 input SA1_ROM_OE_N,
 input SA1_ROM_WORD,
 input [19:0] SDD_BSRAM_ADDR,
 input SDD_BSRAM_CE_N,
 input [7:0] SDD_BSRAM_D,
 input SDD_BSRAM_OE_N,
 input SDD_BSRAM_WE_N,
 input [7:0] SDD_DO,
 input SDD_IRQ_N,
 input [22:0] SDD_ROM_ADDR,
 input SDD_ROM_CE_N,
 input SDD_ROM_OE_N,
 input SDD_ROM_WORD,
 input [15:0] SNES_ARAM_ADDR,
 input SNES_ARAM_CE_N,
 input [7:0] SNES_ARAM_D,
 input SNES_ARAM_OE_N,
 input SNES_ARAM_WE_N,
 input [19:0] SPC7110_BSRAM_ADDR,
 input SPC7110_BSRAM_CE_N,
 input [7:0] SPC7110_BSRAM_D,
 input SPC7110_BSRAM_OE_N,
 input SPC7110_BSRAM_WE_N,
 input [7:0] SPC7110_DO,
 input SPC7110_IRQ_N,
 input [22:0] SPC7110_ROM_ADDR,
 input SPC7110_ROM_CE_N,
 input SPC7110_ROM_OE_N,
 input SPC7110_ROM_WORD,
 input SS_ARAM_SEL,
 input SS_BSRAM_SEL,
 input [7:0] SS_DO,
 input SS_DO_OVR,
 input [19:0] SS_EXT_ADDR,
 input [23:0] SS_ROM_ADDR,
 input SS_ROM_OVR,
 input [19:0] SUFAMI_BSRAM_ADDR,
 input SUFAMI_BSRAM_CE_N,
 input [7:0] SUFAMI_BSRAM_D,
 input SUFAMI_BSRAM_OE_N,
 input SUFAMI_BSRAM_WE_N,
 input [7:0] SUFAMI_DO,
 input SUFAMI_IRQ_N,
 input [22:0] SUFAMI_ROM_ADDR,
 input SUFAMI_ROM_CE_N,
 input SUFAMI_ROM_OE_N,
 input SUFAMI_ROM_WORD,
 output reg [15:0] ARAM_ADDR,
 output reg ARAM_CE_N,
 output reg [7:0] ARAM_D,
 output reg ARAM_OE_N,
 output reg ARAM_WE_N,
 output reg [19:0] BSRAM_ADDR,
 output reg BSRAM_CE_N,
 output reg [7:0] BSRAM_D,
 output reg BSRAM_OE_N,
 output reg BSRAM_WE_N,
 output reg [7:0] DI,
 output reg IRQ_N,
 output reg [23:0] ROM_ADDR,
 output reg ROM_CE_N,
 output reg [15:0] ROM_D,
 output reg ROM_OE_N,
 output reg ROM_WE_N,
 output reg ROM_WORD
);
always @(*) begin
	case (MAP_ACTIVE)
	'b0000001:
		begin
			DI         = CX4_DO;
			IRQ_N      = CX4_IRQ_N;
			ROM_ADDR   = {1'b0,CX4_ROM_ADDR};
			ROM_D      = 8'h00;
			ROM_CE_N   = CX4_ROM_CE_N;
			ROM_OE_N   = CX4_ROM_OE_N;
			ROM_WE_N   = 1;
			BSRAM_ADDR = CX4_BSRAM_ADDR;
			BSRAM_D    = CX4_BSRAM_D;
			BSRAM_CE_N = CX4_BSRAM_CE_N;
			BSRAM_OE_N = CX4_BSRAM_OE_N;
			BSRAM_WE_N = CX4_BSRAM_WE_N;
			ROM_WORD   = CX4_ROM_WORD;
		end

	'b0000010:
		begin
			DI         = SDD_DO;
			IRQ_N      = SDD_IRQ_N;
			ROM_ADDR   = {1'b0,SDD_ROM_ADDR};
			ROM_D      = 8'h00;
			ROM_CE_N   = SDD_ROM_CE_N;
			ROM_OE_N   = SDD_ROM_OE_N;
			ROM_WE_N   = 1;
			BSRAM_ADDR = SDD_BSRAM_ADDR;
			BSRAM_D    = SDD_BSRAM_D;
			BSRAM_CE_N = SDD_BSRAM_CE_N;
			BSRAM_OE_N = SDD_BSRAM_OE_N;
			BSRAM_WE_N = SDD_BSRAM_WE_N;
			ROM_WORD   = SDD_ROM_WORD;
		end

	'b0000100:
		begin
			DI         = GSU_DO;
			IRQ_N      = GSU_IRQ_N;
			ROM_ADDR   = {1'b0,GSU_ROM_ADDR};
			ROM_D      = 8'h00;
			ROM_CE_N   = GSU_ROM_CE_N;
			ROM_OE_N   = GSU_ROM_OE_N;
			ROM_WE_N   = 1;
			BSRAM_ADDR = GSU_BSRAM_ADDR;
			BSRAM_D    = GSU_BSRAM_D;
			BSRAM_CE_N = GSU_BSRAM_CE_N;
			BSRAM_OE_N = GSU_BSRAM_OE_N;
			BSRAM_WE_N = GSU_BSRAM_WE_N;
			ROM_WORD   = GSU_ROM_WORD;
		end

	'b0001000:
		begin
			DI         = SA1_DO;
			IRQ_N      = SA1_IRQ_N;
			ROM_ADDR   = {1'b0,SA1_ROM_ADDR};
			ROM_D      = 8'h00;
			ROM_CE_N   = SA1_ROM_CE_N;
			ROM_OE_N   = SA1_ROM_OE_N;
			ROM_WE_N   = 1;
			BSRAM_ADDR = SA1_BSRAM_ADDR;
			BSRAM_D    = SA1_BSRAM_D;
			BSRAM_CE_N = SA1_BSRAM_CE_N;
			BSRAM_OE_N = SA1_BSRAM_OE_N;
			BSRAM_WE_N = SA1_BSRAM_WE_N;
			ROM_WORD   = SA1_ROM_WORD;
		end

	'b0010000:
		begin
			DI         = SPC7110_DO;
			IRQ_N      = SPC7110_IRQ_N;
			ROM_ADDR   = {1'b0,SPC7110_ROM_ADDR};
			ROM_D      = 8'h00;
			ROM_CE_N   = SPC7110_ROM_CE_N;
			ROM_OE_N   = SPC7110_ROM_OE_N;
			ROM_WE_N   = 1;
			BSRAM_ADDR = SPC7110_BSRAM_ADDR;
			BSRAM_D    = SPC7110_BSRAM_D;
			BSRAM_CE_N = SPC7110_BSRAM_CE_N;
			BSRAM_OE_N = SPC7110_BSRAM_OE_N;
			BSRAM_WE_N = SPC7110_BSRAM_WE_N;
			ROM_WORD   = SPC7110_ROM_WORD;
		end

	'b0100000:
		begin
			DI         = BSX_DO;
			IRQ_N      = BSX_IRQ_N;
			ROM_ADDR   = {1'b0,BSX_ROM_ADDR};
			ROM_D      = BSX_ROM_D;
			ROM_CE_N   = BSX_ROM_CE_N;
			ROM_OE_N   = BSX_ROM_OE_N;
			ROM_WE_N   = BSX_ROM_WE_N;
			BSRAM_ADDR = BSX_BSRAM_ADDR;
			BSRAM_D    = BSX_BSRAM_D;
			BSRAM_CE_N = BSX_BSRAM_CE_N;
			BSRAM_OE_N = BSX_BSRAM_OE_N;
			BSRAM_WE_N = BSX_BSRAM_WE_N;
			ROM_WORD   = BSX_ROM_WORD;
		end

	'b1000000:
		begin
			DI         = SUFAMI_DO;
			IRQ_N      = SUFAMI_IRQ_N;
			ROM_ADDR   = {1'b0,SUFAMI_ROM_ADDR};
			ROM_D      = 8'h00;
			ROM_CE_N   = SUFAMI_ROM_CE_N;
			ROM_OE_N   = SUFAMI_ROM_OE_N;
			ROM_WE_N   = 1;
			BSRAM_ADDR = SUFAMI_BSRAM_ADDR;
			BSRAM_D    = SUFAMI_BSRAM_D;
			BSRAM_CE_N = SUFAMI_BSRAM_CE_N;
			BSRAM_OE_N = SUFAMI_BSRAM_OE_N;
			BSRAM_WE_N = SUFAMI_BSRAM_WE_N;
			ROM_WORD   = SUFAMI_ROM_WORD;
		end
		
	default:
		begin
			DI         = DLH_DO;
			IRQ_N      = DLH_IRQ_N;
			ROM_ADDR   = DLH_ROM_ADDR;
			ROM_D      = 7'h00;
			ROM_CE_N   = DLH_ROM_CE_N;
			ROM_OE_N   = DLH_ROM_OE_N;
			ROM_WE_N   = 1;
			BSRAM_ADDR = DLH_BSRAM_ADDR;
			BSRAM_D    = DLH_BSRAM_D;
			BSRAM_CE_N = DLH_BSRAM_CE_N;
			BSRAM_OE_N = DLH_BSRAM_OE_N;
			BSRAM_WE_N = DLH_BSRAM_WE_N;
			ROM_WORD   = DLH_ROM_WORD;
		end
	endcase
	
	if(MSU_SEL)   DI = MSU_DO;

	if (SS_ARAM_SEL) begin
		ARAM_ADDR = SS_EXT_ADDR[15:0];
		ARAM_D    = SS_DO;
		ARAM_CE_N = 0;
		ARAM_OE_N = PARD_N;
		ARAM_WE_N = PAWR_N;
	end else begin
		ARAM_ADDR = SNES_ARAM_ADDR;
		ARAM_D    = SNES_ARAM_D;
		ARAM_CE_N = SNES_ARAM_CE_N;
		ARAM_OE_N = SNES_ARAM_OE_N;
		ARAM_WE_N = SNES_ARAM_WE_N;
	end

	if (SS_BSRAM_SEL) begin
		BSRAM_ADDR = SS_EXT_ADDR[19:0];
		BSRAM_D    = SS_DO;
		BSRAM_CE_N = 0;
		BSRAM_OE_N = PARD_N;
		BSRAM_WE_N = PAWR_N;
	end

	if (SS_DO_OVR) begin
		DI         = SS_DO;
	end

	if (SS_ROM_OVR) begin
		ROM_ADDR   = SS_ROM_ADDR;
	end
end
endmodule
