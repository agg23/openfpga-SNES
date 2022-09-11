module main (
	input             RESET_N,

	input             MCLK,
	input             ACLK,

	input       [7:0] ROM_TYPE,
	input      [23:0] ROM_MASK,
	input      [23:0] RAM_MASK,

	output reg [23:0] ROM_ADDR,
	output reg [15:0] ROM_D,
	input      [15:0] ROM_Q,
	output reg        ROM_CE_N,
	output reg        ROM_OE_N,
	output reg        ROM_WE_N,
	output reg        ROM_WORD,

	output reg [19:0] BSRAM_ADDR,
	output reg  [7:0] BSRAM_D,
	input       [7:0] BSRAM_Q,
	output reg        BSRAM_CE_N,
	output reg        BSRAM_OE_N,
	output reg        BSRAM_WE_N,

	output     [16:0] WRAM_ADDR,
	output      [7:0] WRAM_D,
	input       [7:0] WRAM_Q,
	output            WRAM_CE_N,
	output            WRAM_OE_N,
	output            WRAM_WE_N,

	output     [15:0] VRAM1_ADDR,
	input       [7:0] VRAM1_DI,
	output      [7:0] VRAM1_DO,
	output            VRAM1_WE_N,
	output     [15:0] VRAM2_ADDR,
	input       [7:0] VRAM2_DI,
	output      [7:0] VRAM2_DO,
	output            VRAM2_WE_N,
	output            VRAM_OE_N,

	output     [15:0] ARAM_ADDR,
	output      [7:0] ARAM_D,
	input       [7:0] ARAM_Q,
	output            ARAM_CE_N,
	output            ARAM_OE_N,
	output            ARAM_WE_N,

	output            GSU_ACTIVE,
	input             GSU_TURBO,

	input             BLEND,
	input             PAL,
	output            HIGH_RES,
	output            FIELD,
	output            INTERLACE,
	output            DOTCLK,
	output      [7:0] R,
	output      [7:0] G,
	output      [7:0] B,
	output            HBLANKn,
	output            VBLANKn,
	output            HSYNC,
	output            VSYNC,

	input       [1:0] JOY1_DI,
	input       [1:0] JOY2_DI,
	output            JOY_STRB,
	output            JOY1_CLK,
	output            JOY2_CLK,
	output            JOY1_P6,
	output            JOY2_P6,
	input             JOY2_P6_in,

	input      [64:0] EXT_RTC,

	input             GG_EN,
	input     [128:0] GG_CODE,
	input             GG_RESET,
	output            GG_AVAILABLE,

	input             SPC_MODE,

	input      [16:0] IO_ADDR,
	input      [15:0] IO_DAT,
	input             IO_WR,

	input       [4:0] DBG_BG_EN,
	input             DBG_CPU_EN,

	input             TURBO,
	output            TURBO_ALLOW,

	output     [15:0] MSU_TRACK_NUM,
	output            MSU_TRACK_REQUEST,
	input             MSU_TRACK_MOUNTING,
	input             MSU_TRACK_MISSING,
	output      [7:0] MSU_VOLUME,
	input             MSU_AUDIO_STOP,
	output            MSU_AUDIO_REPEAT,
	output            MSU_AUDIO_PLAYING,
	output     [31:0] MSU_DATA_ADDR,
	input       [7:0] MSU_DATA,
	input             MSU_DATA_ACK,
	output            MSU_DATA_SEEK,
	output            MSU_DATA_REQ,
	input             MSU_ENABLE,

	output     [15:0] AUDIO_L,
	output     [15:0] AUDIO_R
);

parameter USE_DLH = 1'b1;
parameter USE_CX4 = 1'b1;
parameter USE_SDD1 = 1'b1;
parameter USE_GSU = 1'b1;
parameter USE_SA1 = 1'b1;
parameter USE_DSPn = 1'b1;
parameter USE_SPC7110 = 1'b1;
parameter USE_BSX = 1'b1;
parameter USE_MSU = 1'b1;

wire [23:0] CA;
wire        CPURD_N;
wire        CPUWR_N;
reg   [7:0] DI;
wire  [7:0] DO;
wire        RAMSEL_N;
wire        ROMSEL_N;
reg         IRQ_N;
wire  [7:0] PA;
wire        PARD_N;
wire        PAWR_N;
wire        SYSCLKF_CE;
wire        SYSCLKR_CE;
wire        REFRESH;

wire  [5:0] MAP_ACTIVE;

SNES SNES
(
	.mclk(MCLK),
	.dspclk(ACLK),

	.rst_n(RESET_N),
	.enable(1),

	.ca(CA),
	.cpurd_n(CPURD_N),
	.cpuwr_n(CPUWR_N),

	.pa(PA),
	.pard_n(PARD_N),
	.pawr_n(PAWR_N),
	.di(DI),
	.do(DO),

	.ramsel_n(RAMSEL_N),
	.romsel_n(ROMSEL_N),

	.sysclkf_ce(SYSCLKF_CE),
	.sysclkr_ce(SYSCLKR_CE),

	.refresh(REFRESH),

	.irq_n(IRQ_N),

	.wsram_addr(WRAM_ADDR),
	.wsram_d(WRAM_D),
	.wsram_q(WRAM_Q),
	.wsram_ce_n(WRAM_CE_N),
	.wsram_oe_n(WRAM_OE_N),
	.wsram_we_n(WRAM_WE_N),

	.vram_addra(VRAM1_ADDR),
	.vram_addrb(VRAM2_ADDR),
	.vram_dai(VRAM1_DI),
	.vram_dbi(VRAM2_DI),
	.vram_dao(VRAM1_DO),
	.vram_dbo(VRAM2_DO),
	.vram_rd_n(VRAM_OE_N),
	.vram_wra_n(VRAM1_WE_N),
	.vram_wrb_n(VRAM2_WE_N),

	.aram_addr(ARAM_ADDR),
	.aram_d(ARAM_D),
	.aram_q(ARAM_Q),
	.aram_ce_n(ARAM_CE_N),
	.aram_oe_n(ARAM_OE_N),
	.aram_we_n(ARAM_WE_N),

	.joy1_di(JOY1_DI),
	.joy2_di(JOY2_DI),
	.joy_strb(JOY_STRB),
	.joy1_clk(JOY1_CLK),
	.joy2_clk(JOY2_CLK),
	.joy1_p6(JOY1_P6),
	.joy2_p6(JOY2_P6),
	.joy2_p6_in(JOY2_P6_in),

	.blend(BLEND),
	.pal(PAL),
	.high_res(HIGH_RES),
	.field_out(FIELD),
	.interlace(INTERLACE),
	.dotclk(DOTCLK),

	.rgb_out({B,G,R}),
	.hde(HBLANKn),
	.vde(VBLANKn),
	.hsync(HSYNC),
	.vsync(VSYNC),

	.gg_en(GG_EN),
	.gg_code(GG_CODE),
	.gg_reset(GG_RESET),
	.gg_available(GG_AVAILABLE),
	
	.spc_mode(SPC_MODE),
	
	.io_addr(IO_ADDR),
	.io_dat(IO_DAT),
	.io_wr(IO_WR),
	
	.DBG_BG_EN(DBG_BG_EN),
	.DBG_CPU_EN(DBG_CPU_EN),
	
	.turbo(TURBO),

	.audio_l(AUDIO_L),
	.audio_r(AUDIO_R)
);

wire  [7:0] MSU_DO;
wire        MSU_SEL;

generate
if (USE_MSU == 1'b1) begin
MSU MSU
(
	.CLK(MCLK),
	.RST_N(RESET_N),
	.ENABLE(MSU_ENABLE),

	.RD_N(CPURD_N),
	.WR_N(CPUWR_N),
	.SYSCLKF_CE(SYSCLKF_CE),

	.ADDR(CA),
	.DIN(DO),
	.DOUT(MSU_DO),
	.MSU_SEL(MSU_SEL),

	.data_addr(MSU_DATA_ADDR),
	.data(MSU_DATA),
	.data_ack(MSU_DATA_ACK),
	.data_seek(MSU_DATA_SEEK),
	.data_req(MSU_DATA_REQ),

	.track_num(MSU_TRACK_NUM),
	.track_request(MSU_TRACK_REQUEST),
	.track_mounting(MSU_TRACK_MOUNTING),

	.status_track_missing(MSU_TRACK_MISSING),
	.status_audio_repeat(MSU_AUDIO_REPEAT),
	.status_audio_playing(MSU_AUDIO_PLAYING),
	.audio_stop(MSU_AUDIO_STOP),

	.volume(MSU_VOLUME)
);
end else begin
	assign MSU_DO  = 0;
	assign MSU_SEL = 0;
	assign MSU_TRACK_NUM = 0;
	assign MSU_TRACK_REQUEST = 0;
	assign MSU_VOLUME = 0;
	assign MSU_AUDIO_REPEAT = 0;
	assign MSU_AUDIO_PLAYING = 0;
end
endgenerate

wire  [7:0] DLH_DO;
wire        DLH_IRQ_N;
wire [23:0] DLH_ROM_ADDR;
wire        DLH_ROM_CE_N;
wire        DLH_ROM_OE_N;
wire        DLH_ROM_WORD;
wire [19:0] DLH_BSRAM_ADDR;
wire  [7:0] DLH_BSRAM_D;
wire        DLH_BSRAM_CE_N;
wire        DLH_BSRAM_OE_N;
wire        DLH_BSRAM_WE_N;

generate
if (USE_DLH == 1'b1) begin

DSP_LHRomMap #(.USE_DSPn(USE_DSPn)) DSP_LHRomMap
(
	.mclk(MCLK),
	.rst_n(RESET_N),

	.ca(CA),
	.di(DO),
	.do(DLH_DO),
	.cpurd_n(CPURD_N),
	.cpuwr_n(CPUWR_N),
	
	.pa(PA),
	.pard_n(PARD_N),
	.pawr_n(PAWR_N),

	.romsel_n(ROMSEL_N),
	.ramsel_n(RAMSEL_N),

	.sysclkf_ce(SYSCLKF_CE),
	.sysclkr_ce(SYSCLKR_CE),
	.refresh(REFRESH),

	.irq_n(DLH_IRQ_N),

	.rom_addr(DLH_ROM_ADDR),
	.rom_q(ROM_Q),
	.rom_ce_n(DLH_ROM_CE_N),
	.rom_oe_n(DLH_ROM_OE_N),
	.rom_word(DLH_ROM_WORD),

	.bsram_addr(DLH_BSRAM_ADDR),
	.bsram_d(DLH_BSRAM_D),
	.bsram_q(BSRAM_Q),
	.bsram_ce_n(DLH_BSRAM_CE_N),
	.bsram_oe_n(DLH_BSRAM_OE_N),
	.bsram_we_n(DLH_BSRAM_WE_N),

	.map_ctrl(ROM_TYPE),
	.rom_mask(ROM_MASK),
	.bsram_mask(RAM_MASK),

	.ext_rtc(EXT_RTC)
);
end else begin
	assign DLH_DO = 0;
	assign DLH_IRQ_N = 1;
	assign DLH_ROM_ADDR = 0;
	assign DLH_ROM_CE_N = 1;
	assign DLH_ROM_OE_N = 1;
	assign DLH_BSRAM_ADDR = 0;
	assign DLH_BSRAM_D = 0;
	assign DLH_BSRAM_CE_N = 1;
	assign DLH_BSRAM_OE_N = 1;
	assign DLH_BSRAM_WE_N = 1;
	assign DLH_ROM_WORD = 0;
end
endgenerate

wire [7:0]  CX4_DO;
wire        CX4_IRQ_N;
wire [22:0] CX4_ROM_ADDR;
wire        CX4_ROM_CE_N;
wire        CX4_ROM_OE_N;
wire        CX4_ROM_WORD;
wire [19:0] CX4_BSRAM_ADDR;
wire [7:0]  CX4_BSRAM_D;
wire        CX4_BSRAM_CE_N;
wire        CX4_BSRAM_OE_N;
wire        CX4_BSRAM_WE_N;

generate
if (USE_CX4 == 1'b1) begin

CX4Map CX4Map
(
	.mclk(MCLK),
	.rst_n(RESET_N),

	.ca(CA),
	.di(DO),
	.do(CX4_DO),
	.cpurd_n(CPURD_N),
	.cpuwr_n(CPUWR_N),

	.pa(PA),
	.pard_n(PARD_N),
	.pawr_n(PAWR_N),

	.romsel_n(ROMSEL_N),
	.ramsel_n(RAMSEL_N),

	.sysclkf_ce(SYSCLKF_CE),
	.sysclkr_ce(SYSCLKR_CE),
	.refresh(REFRESH),

	.irq_n(CX4_IRQ_N),

	.rom_addr(CX4_ROM_ADDR),
	.rom_q(ROM_Q),
	.rom_ce_n(CX4_ROM_CE_N),
	.rom_oe_n(CX4_ROM_OE_N),
	.rom_word(CX4_ROM_WORD),

	.bsram_addr(CX4_BSRAM_ADDR),
	.bsram_d(CX4_BSRAM_D),
	.bsram_q(BSRAM_Q),
	.bsram_ce_n(CX4_BSRAM_CE_N),
	.bsram_oe_n(CX4_BSRAM_OE_N),
	.bsram_we_n(CX4_BSRAM_WE_N),

	.map_active(MAP_ACTIVE[0]),
	.map_ctrl(ROM_TYPE),
	.rom_mask(ROM_MASK),
	.bsram_mask(RAM_MASK)
);
end else
assign MAP_ACTIVE[0] = 0;
endgenerate

wire [7:0]  SDD_DO;
wire        SDD_IRQ_N;
wire [22:0] SDD_ROM_ADDR;
wire        SDD_ROM_CE_N;
wire        SDD_ROM_OE_N;
wire        SDD_ROM_WORD;
wire [19:0] SDD_BSRAM_ADDR;
wire [7:0]  SDD_BSRAM_D;
wire        SDD_BSRAM_CE_N;
wire        SDD_BSRAM_OE_N;
wire        SDD_BSRAM_WE_N;

generate
if (USE_SDD1 == 1'b1) begin

SDD1Map SDD1Map
(
	.mclk(MCLK),
	.rst_n(RESET_N),

	.ca(CA),
	.di(DO),
	.do(SDD_DO),
	.cpurd_n(CPURD_N),
	.cpuwr_n(CPUWR_N),

	.pa(PA),
	.pard_n(PARD_N),
	.pawr_n(PAWR_N),

	.romsel_n(ROMSEL_N),
	.ramsel_n(RAMSEL_N),

	.sysclkf_ce(SYSCLKF_CE),
	.sysclkr_ce(SYSCLKR_CE),
	.refresh(REFRESH),

	.irq_n(SDD_IRQ_N),

	.rom_addr(SDD_ROM_ADDR),
	.rom_q(ROM_Q),
	.rom_ce_n(SDD_ROM_CE_N),
	.rom_oe_n(SDD_ROM_OE_N),
	.rom_word(SDD_ROM_WORD),

	.bsram_addr(SDD_BSRAM_ADDR),
	.bsram_d(SDD_BSRAM_D),
	.bsram_q(BSRAM_Q),
	.bsram_ce_n(SDD_BSRAM_CE_N),
	.bsram_oe_n(SDD_BSRAM_OE_N),
	.bsram_we_n(SDD_BSRAM_WE_N),

	.map_active(MAP_ACTIVE[1]),
	.map_ctrl(ROM_TYPE),
	.rom_mask(ROM_MASK),
	.bsram_mask(RAM_MASK)
);
end else
assign MAP_ACTIVE[1] = 0;
endgenerate

wire [7:0]  GSU_DO;
wire        GSU_IRQ_N;
wire [22:0] GSU_ROM_ADDR;
wire        GSU_ROM_CE_N;
wire        GSU_ROM_OE_N;
wire        GSU_ROM_WORD;
wire [19:0] GSU_BSRAM_ADDR;
wire [7:0]  GSU_BSRAM_D;
wire        GSU_BSRAM_CE_N;
wire        GSU_BSRAM_OE_N;
wire        GSU_BSRAM_WE_N;

generate
if (USE_GSU == 1'b1) begin

GSUMap GSUMap
(
	.mclk(MCLK),
	.rst_n(RESET_N),

	.ca(CA),
	.di(DO),
	.do(GSU_DO),
	.cpurd_n(CPURD_N),
	.cpuwr_n(CPUWR_N),

	.pa(PA),
	.pard_n(PARD_N),
	.pawr_n(PAWR_N),

	.romsel_n(ROMSEL_N),
	.ramsel_n(RAMSEL_N),

	.sysclkf_ce(SYSCLKF_CE),
	.sysclkr_ce(SYSCLKR_CE),
	.refresh(REFRESH),

	.irq_n(GSU_IRQ_N),

	.rom_addr(GSU_ROM_ADDR),
	.rom_q(ROM_Q),
	.rom_ce_n(GSU_ROM_CE_N),
	.rom_oe_n(GSU_ROM_OE_N),
	.rom_word(GSU_ROM_WORD),

	.bsram_addr(GSU_BSRAM_ADDR),
	.bsram_d(GSU_BSRAM_D),
	.bsram_q(BSRAM_Q),
	.bsram_ce_n(GSU_BSRAM_CE_N),
	.bsram_oe_n(GSU_BSRAM_OE_N),
	.bsram_we_n(GSU_BSRAM_WE_N),

	.map_active(MAP_ACTIVE[2]),
	.map_ctrl(ROM_TYPE),
	.rom_mask(ROM_MASK),
	.bsram_mask(RAM_MASK),

	.turbo(GSU_TURBO)
);
end else
assign MAP_ACTIVE[2] = 0;
endgenerate

assign GSU_ACTIVE = MAP_ACTIVE[2];

wire [7:0]  SA1_DO;
wire        SA1_IRQ_N;
wire [22:0] SA1_ROM_ADDR;
wire        SA1_ROM_CE_N;
wire        SA1_ROM_OE_N;
wire        SA1_ROM_WORD;
wire [19:0] SA1_BSRAM_ADDR;
wire [7:0]  SA1_BSRAM_D;
wire        SA1_BSRAM_CE_N;
wire        SA1_BSRAM_OE_N;
wire        SA1_BSRAM_WE_N;

generate
if (USE_SA1 == 1'b1) begin

SA1Map SA1Map
(
	.mclk(MCLK),
	.rst_n(RESET_N),

	.ca(CA),
	.di(DO),
	.do(SA1_DO),
	.cpurd_n(CPURD_N),
	.cpuwr_n(CPUWR_N),

	.pa(PA),
	.pard_n(PARD_N),
	.pawr_n(PAWR_N),

	.romsel_n(ROMSEL_N),
	.ramsel_n(RAMSEL_N),

	.sysclkf_ce(SYSCLKF_CE),
	.sysclkr_ce(SYSCLKR_CE),
	.refresh(REFRESH),

	.pal(PAL),

	.irq_n(SA1_IRQ_N),

	.rom_addr(SA1_ROM_ADDR),
	.rom_q(ROM_Q),
	.rom_ce_n(SA1_ROM_CE_N),
	.rom_oe_n(SA1_ROM_OE_N),
	.rom_word(SA1_ROM_WORD),

	.bsram_addr(SA1_BSRAM_ADDR),
	.bsram_d(SA1_BSRAM_D),
	.bsram_q(BSRAM_Q),
	.bsram_ce_n(SA1_BSRAM_CE_N),
	.bsram_oe_n(SA1_BSRAM_OE_N),
	.bsram_we_n(SA1_BSRAM_WE_N),

	.map_active(MAP_ACTIVE[3]),
	.map_ctrl(ROM_TYPE),
	.rom_mask(ROM_MASK),
	.bsram_mask(RAM_MASK)
);
end else
assign MAP_ACTIVE[3] = 0;
endgenerate

wire [7:0]  SPC7110_DO;
wire        SPC7110_IRQ_N;
wire [22:0] SPC7110_ROM_ADDR;
wire        SPC7110_ROM_CE_N;
wire        SPC7110_ROM_OE_N;
wire        SPC7110_ROM_WORD;
wire [19:0] SPC7110_BSRAM_ADDR;
wire [7:0]  SPC7110_BSRAM_D;
wire        SPC7110_BSRAM_CE_N;
wire        SPC7110_BSRAM_OE_N;
wire        SPC7110_BSRAM_WE_N;

generate
if (USE_SPC7110 == 1'b1) begin
SPC7110Map SPC7110Map
(
	.mclk(MCLK),
	.rst_n(RESET_N),

	.ca(CA),
	.di(DO),
	.do(SPC7110_DO),
	.cpurd_n(CPURD_N),
	.cpuwr_n(CPUWR_N),

	.pa(PA),
	.pard_n(PARD_N),
	.pawr_n(PAWR_N),

	.romsel_n(ROMSEL_N),
	.ramsel_n(RAMSEL_N),

	.sysclkf_ce(SYSCLKF_CE),
	.sysclkr_ce(SYSCLKR_CE),
	.refresh(REFRESH),

	.irq_n(SPC7110_IRQ_N),

	.rom_addr(SPC7110_ROM_ADDR),
	.rom_q(ROM_Q),
	.rom_ce_n(SPC7110_ROM_CE_N),
	.rom_oe_n(SPC7110_ROM_OE_N),
	.rom_word(SPC7110_ROM_WORD),

	.bsram_addr(SPC7110_BSRAM_ADDR),
	.bsram_d(SPC7110_BSRAM_D),
	.bsram_q(BSRAM_Q),
	.bsram_ce_n(SPC7110_BSRAM_CE_N),
	.bsram_oe_n(SPC7110_BSRAM_OE_N),
	.bsram_we_n(SPC7110_BSRAM_WE_N),

	.map_active(MAP_ACTIVE[4]),
	.map_ctrl(ROM_TYPE),
	.rom_mask(ROM_MASK),
	.bsram_mask(RAM_MASK),
	
	.ext_rtc(EXT_RTC)
);
end else
assign MAP_ACTIVE[4] = 0;
endgenerate

wire [7:0]  BSX_DO;
wire        BSX_IRQ_N;
wire [22:0] BSX_ROM_ADDR;
wire [7:0]  BSX_ROM_D;
wire        BSX_ROM_CE_N;
wire        BSX_ROM_OE_N;
wire        BSX_ROM_WE_N;
wire        BSX_ROM_WORD;
wire [19:0] BSX_BSRAM_ADDR;
wire [7:0]  BSX_BSRAM_D;
wire        BSX_BSRAM_CE_N;
wire        BSX_BSRAM_OE_N;
wire        BSX_BSRAM_WE_N;

generate
if (USE_BSX == 1'b1) begin
BSXMap BSXMap
(
	.mclk(MCLK),
	.rst_n(RESET_N),

	.ca(CA),
	.di(DO),
	.do(BSX_DO),
	.cpurd_n(CPURD_N),
	.cpuwr_n(CPUWR_N),

	.pa(PA),
	.pard_n(PARD_N),
	.pawr_n(PAWR_N),

	.romsel_n(ROMSEL_N),
	.ramsel_n(RAMSEL_N),

	.sysclkf_ce(SYSCLKF_CE),
	.sysclkr_ce(SYSCLKR_CE),
	.refresh(REFRESH),

	.irq_n(BSX_IRQ_N),

	.rom_addr(BSX_ROM_ADDR),
	.rom_d(BSX_ROM_D),
	.rom_q(ROM_Q),
	.rom_ce_n(BSX_ROM_CE_N),
	.rom_oe_n(BSX_ROM_OE_N),
	.rom_we_n(BSX_ROM_WE_N),
	.rom_word(BSX_ROM_WORD),

	.bsram_addr(BSX_BSRAM_ADDR),
	.bsram_d(BSX_BSRAM_D),
	.bsram_q(BSRAM_Q),
	.bsram_ce_n(BSX_BSRAM_CE_N),
	.bsram_oe_n(BSX_BSRAM_OE_N),
	.bsram_we_n(BSX_BSRAM_WE_N),

	.map_active(MAP_ACTIVE[5]),
	.map_ctrl(ROM_TYPE),
	.rom_mask(ROM_MASK),
	.bsram_mask(RAM_MASK),

	
	.ext_rtc(EXT_RTC)
);
end else
assign MAP_ACTIVE[5] = 0;
endgenerate

assign TURBO_ALLOW = ~(MAP_ACTIVE[3] | MAP_ACTIVE[1]);

always @(*) begin
	case (MAP_ACTIVE)
	'b000001:
		begin
			DI         = CX4_DO;
			IRQ_N      = CX4_IRQ_N;
			ROM_ADDR   = {1'b0,CX4_ROM_ADDR};
			ROM_D      = 7'h00;
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

	'b000010:
		begin
			DI         = SDD_DO;
			IRQ_N      = SDD_IRQ_N;
			ROM_ADDR   = {1'b0,SDD_ROM_ADDR};
			ROM_D      = 7'h00;
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

	'b000100:
		begin
			DI         = GSU_DO;
			IRQ_N      = GSU_IRQ_N;
			ROM_ADDR   = {1'b0,GSU_ROM_ADDR};
			ROM_D      = 7'h00;
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

	'b001000:
		begin
			DI         = SA1_DO;
			IRQ_N      = SA1_IRQ_N;
			ROM_ADDR   = {1'b0,SA1_ROM_ADDR};
			ROM_D      = 7'h00;
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

	'b010000:
		begin
			DI         = SPC7110_DO;
			IRQ_N      = SPC7110_IRQ_N;
			ROM_ADDR   = {1'b0,SPC7110_ROM_ADDR};
			ROM_D      = 7'h00;
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

	'b100000:
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
end

endmodule
