module main #(
	parameter reg USE_STANDARD_SDRAM = 1'b0,
	parameter reg USE_CX4 = 1'b0,
	parameter reg USE_SDD1 = 1'b0,
	parameter reg USE_GSU = 1'b0,
	parameter reg USE_SA1 = 1'b0,
	parameter reg USE_DSPn = 1'b0,
	parameter reg USE_SPC7110 = 1'b0,
	parameter reg USE_BSX = 1'b0,
	parameter reg USE_MSU = 1'b0,
	parameter reg USE_SS = 1'b0,
	parameter reg USE_SUFAMI = 1'b0
) (
	input             RESET_N,
    // Owner-tagged system-clock memory fabric (unused by legacy profiles).
    input             MEM_HARD_RESET_N,
    input             MEM_FLUSH,
    input      [7:0]  MEM_EPOCH,
    output            MEM_FLUSH_ACK,
    output            MEM_FAULT,
    output            MEM_REQ_VALID,
    input             MEM_REQ_READY,
    output     [23:0] MEM_REQ_ADDR,
    output            MEM_REQ_WRITE,
    output            MEM_REQ_DRAIN,
    output     [15:0] MEM_REQ_WDATA,
    output     [1:0]  MEM_REQ_WSTRB,
    output     [4:0]  MEM_REQ_OWNER,
    output     [7:0]  MEM_REQ_TAG,
    output     [7:0]  MEM_REQ_EPOCH,
    input             MEM_RSP_VALID,
    output            MEM_RSP_READY,
    input      [15:0] MEM_RSP_DATA,
    input             MEM_RSP_ERROR,
    input             MEM_RSP_WRITE,
    input      [4:0]  MEM_RSP_OWNER,
    input      [7:0]  MEM_RSP_TAG,
    input      [7:0]  MEM_RSP_EPOCH,

	input             MCLK,
	input             ACLK,

	input       [7:0] ROM_TYPE,
	input      [23:0] ROM_MASK,
	input      [23:0] RAM_MASK,
	input      [ 3:0] RAM_SIZE,
	
	output            SYSCLKR_CE,
	output            SYSCLKF_CE,
	output            REFRESH,

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

	output reg [15:0] ARAM_ADDR,
	output reg  [7:0] ARAM_D,
	input       [7:0] ARAM_Q,
	output reg        ARAM_CE_N,
	output reg        ARAM_OE_N,
	output reg        ARAM_WE_N,

	output            GSU_ACTIVE,
	input             GSU_TURBO,
	input             GSU_FASTROM,
	input             SUFAMI_SWAP,
	input       [7:0] CC_DIP,

	input             BLEND,
	input             PAL,
	output            HIGH_RES,
	output            V224_MODE,
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
	output            HVCNT_ATZERO,

	input       [1:0] JOY1_DI,
	input       [1:0] JOY2_DI,
	output            JOY_STRB,
	output            JOY1_CLK,
	output            JOY2_CLK,
	output            JOY1_P6,
	output            JOY2_P6,
	input             JOY2_P6_in,
	output reg [63:0] SNI_JOY,

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
	
	input             DSP_FREQ,

	output     [15:0] MSU_TRACK_NUM,
	output            MSU_TRACK_REQUEST,
	output            MSU_TRACK_UPDATE,
	input             MSU_TRACK_MOUNTING,
	input             MSU_TRACK_MISSING,
	output      [7:0] MSU_VOLUME,
	input             MSU_AUDIO_STOP,
	output            MSU_AUDIO_REPEAT,
	output            MSU_AUDIO_RESUME,
	output            MSU_AUDIO_PLAYING,
	input      [21:0] MSU_AUDIO_SECTOR,
	output     [21:0] MSU_RESUME_SECTOR,
	input      [31:0] MSU_AUDIO_LOOP_INDEX,
	output     [31:0] MSU_RESUME_LOOP_INDEX,
	output     [31:0] MSU_DATA_ADDR,
	input       [7:0] MSU_DATA,
	input             MSU_DATA_ACK,
	input             MSU_DATA_BUSY,
	output            MSU_DATA_SEEK,
	output            MSU_DATA_REQ,
	input             MSU_ENABLE,

	input             SS_SAVE,
	input             SS_TOSD,
	input             SS_LOAD,
	input       [1:0] SS_SLOT,
	output            SS_AVAIL,

	input      [63:0] SS_DDR_DI,
	input             SS_DDR_ACK,
	output     [63:0] SS_DDR_DO,
	output     [21:3] SS_DDR_ADDR,
	output            SS_DDR_WE,
	output      [7:0] SS_DDR_BE,
	output            SS_DDR_REQ,

	output     [15:0] AUDIO_L,
	output     [15:0] AUDIO_R
);

parameter USE_DLH = 1'b1;

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
//wire        SYSCLKF_CE;
//wire        SYSCLKR_CE;
//wire        REFRESH;

wire  [15:0] SNES_ARAM_ADDR;
wire   [7:0] SNES_ARAM_D;
wire         SNES_ARAM_CE_N;
wire         SNES_ARAM_OE_N;
wire         SNES_ARAM_WE_N;

wire  [6:0] MAP_ACTIVE;
wire BUS_A_READ_INTENT, BUS_A_WRITE_INTENT, BUS_A_RETIRE;
wire [1:0] BUS_A_OWNER;
wire [7:0] BUS_A_WRITE_DATA;
wire CART_READ_WAIT, CART_WRITE_WAIT;
wire [23:0] DLH_LOOKAHEAD_ADDR, SUFAMI_LOOKAHEAD_ADDR;
wire DLH_LOOKAHEAD_SEL, SUFAMI_LOOKAHEAD_SEL;
wire [15:0] PASSIVE_ROM_DATA;

// Index0 passive default/Sufami,1 CX4,2 SDD1,3 GSU,4 SA1,5 SPC7110,6 BSX.
wire [6:0] MC_VALID, MC_READY, MC_RSP_VALID, MC_RSP_READY;
wire [6:0] MC_FLUSH_ACK, MC_FAULT, MC_SNES_WAIT;
wire [23:0] MC_ADDR [0:6];
wire [1:0] MC_OWNER [0:6];
wire [1:0] MC_SNES_OWNER [0:6];
wire [7:0] MC_TAG [0:6];
wire [7:0] MC_EPOCH [0:6];
wire [6:0] MC_WRITE;
wire [15:0] MC_WDATA [0:6];
wire [1:0] MC_WSTRB [0:6];
wire BSX_SNES_WRITE_WAIT, BSX_REQ_DRAIN;
wire bsx_drain_offer = MC_VALID[6] && BSX_REQ_DRAIN && MC_WRITE[6] && MC_OWNER[6]==2;
wire client_flush = MEM_FLUSH || !RESET_N;
reg [2:0] mem_rsp_source;
reg [1:0] mem_rsp_local_owner;
reg [4:0] mem_rsp_global_owner;
wire [2:0] mem_source = bsx_drain_offer ? 3'd6 : MAP_ACTIVE[0] ? 3'd1 : MAP_ACTIVE[1] ? 3'd2 :
                        MAP_ACTIVE[2] ? 3'd3 : MAP_ACTIVE[3] ? 3'd4 :
                        MAP_ACTIVE[4] ? 3'd5 : MAP_ACTIVE[5] ? 3'd6 : 3'd0;
reg [4:0] mem_global_owner;
always @* begin
    if(MC_OWNER[mem_source]==0) mem_global_owner={3'b0,MC_SNES_OWNER[mem_source]};
    else case(mem_source)
      3'd1: mem_global_owner=5'd9+MC_OWNER[mem_source];
      3'd2: mem_global_owner=5'd14;
      3'd3: mem_global_owner=5'd6+MC_OWNER[mem_source];
      3'd4: mem_global_owner=5'd3+MC_OWNER[mem_source];
      3'd5: mem_global_owner=5'd13;
      3'd6: mem_global_owner=5'd15;
      default: mem_global_owner={3'b0,MC_SNES_OWNER[mem_source]};
    endcase
end
assign MEM_REQ_VALID = USE_STANDARD_SDRAM && (!client_flush || bsx_drain_offer) && MC_VALID[mem_source];
assign MEM_REQ_ADDR = MC_ADDR[mem_source];
assign MEM_REQ_OWNER = mem_global_owner;
assign MEM_REQ_TAG = MC_TAG[mem_source];
assign MEM_REQ_EPOCH = MC_EPOCH[mem_source];
assign MEM_REQ_WRITE = MC_WRITE[mem_source];
assign MEM_REQ_DRAIN = mem_source==6 && bsx_drain_offer;
assign MEM_REQ_WDATA = MC_WDATA[mem_source];
assign MEM_REQ_WSTRB = MC_WSTRB[mem_source];
assign MEM_RSP_READY = USE_STANDARD_SDRAM && MC_RSP_READY[mem_rsp_source];
assign MEM_FLUSH_ACK = !USE_STANDARD_SDRAM || (&MC_FLUSH_ACK);
assign MEM_FAULT = USE_STANDARD_SDRAM && (|MC_FAULT);
assign CART_READ_WAIT = USE_STANDARD_SDRAM && MC_SNES_WAIT[mem_source];
assign CART_WRITE_WAIT = USE_STANDARD_SDRAM && MAP_ACTIVE[5] && BSX_SNES_WRITE_WAIT;
wire mem_rsp_identity_error = MEM_RSP_OWNER != mem_rsp_global_owner;
always @(posedge MCLK or negedge MEM_HARD_RESET_N) begin
    if(!MEM_HARD_RESET_N) begin
        mem_rsp_source<=0;mem_rsp_local_owner<=0;mem_rsp_global_owner<=0;
    end else if(MEM_REQ_VALID && MEM_REQ_READY) begin
        mem_rsp_source<=mem_source;
        mem_rsp_local_owner<=MC_OWNER[mem_source];
        mem_rsp_global_owner<=mem_global_owner;
    end
end
genvar mi;
generate for(mi=0;mi<7;mi=mi+1) begin: memory_client_routing
    assign MC_READY[mi]=USE_STANDARD_SDRAM && (!client_flush || (mi==6 && bsx_drain_offer)) && mem_source==mi && MEM_REQ_READY;
    // Delivery follows captured source, never later MAP_ACTIVE. Includes reset/flush.
    assign MC_RSP_VALID[mi]=USE_STANDARD_SDRAM && MEM_RSP_VALID && mem_rsp_source==mi;
    if(mi!=6) begin: read_only
        assign MC_WRITE[mi]=1'b0;
        assign MC_WDATA[mi]=16'b0;
        assign MC_WSTRB[mi]=2'b0;
    end
end endgenerate

generate if(USE_STANDARD_SDRAM) begin: passive_memory_ready
    wire passive_selected = MAP_ACTIVE[6] ? SUFAMI_LOOKAHEAD_SEL :
                            (MAP_ACTIVE==0 && DLH_LOOKAHEAD_SEL);
    wire [23:0] passive_address = MAP_ACTIVE[6] ? SUFAMI_LOOKAHEAD_ADDR : DLH_LOOKAHEAD_ADDR;
    snes_rom_client passive_client(
        .clk(MCLK),.hard_reset_n(MEM_HARD_RESET_N),.flush(client_flush),.epoch(MEM_EPOCH),
        .read_intent(BUS_A_READ_INTENT),.owner(BUS_A_OWNER),.selected(passive_selected),
        .address(passive_address),.retire(BUS_A_RETIRE),.bus_wait(MC_SNES_WAIT[0]),
        .result_data(PASSIVE_ROM_DATA),.flush_ack(MC_FLUSH_ACK[0]),.fault(MC_FAULT[0]),
        .req_valid(MC_VALID[0]),.req_ready(MC_READY[0]),.req_addr(MC_ADDR[0]),
        .req_owner(MC_SNES_OWNER[0]),.req_tag(MC_TAG[0]),.req_epoch(MC_EPOCH[0]),
        .rsp_valid(MC_RSP_VALID[0]),.rsp_ready(MC_RSP_READY[0]),.rsp_data(MEM_RSP_DATA),
        .rsp_owner(MEM_RSP_OWNER[1:0]),.rsp_tag(MEM_RSP_TAG),.rsp_epoch(MEM_RSP_EPOCH),
        .rsp_error(MEM_RSP_ERROR || mem_rsp_identity_error));
    assign MC_OWNER[0]=0;
end else begin: passive_memory_legacy
    assign MC_VALID[0]=0;assign MC_ADDR[0]=0;assign MC_OWNER[0]=0;
    assign MC_SNES_OWNER[0]=0;assign MC_TAG[0]=0;assign MC_EPOCH[0]=0;
    assign MC_RSP_READY[0]=0;assign MC_FLUSH_ACK[0]=1;assign MC_FAULT[0]=0;
    assign MC_SNES_WAIT[0]=0;assign PASSIVE_ROM_DATA=ROM_Q;
end endgenerate

SNES #(
    .WRAM_PREDECODE(USE_STANDARD_SDRAM ? "TRUE" : "FALSE"),
    .ARAM_RETURN_STAGE(USE_STANDARD_SDRAM ? "TRUE" : "FALSE")
) SNES
(
	.mclk(MCLK),
	.dspclk(ACLK),

	.rst_n(RESET_N),
	.enable(1),
	.bus_wait(MSU_BUS_WAIT | CART_READ_WAIT),
    .bus_write_wait(CART_WRITE_WAIT),
    .bus_a_read_intent(BUS_A_READ_INTENT),
    .bus_a_write_intent(BUS_A_WRITE_INTENT),
    .bus_a_owner(BUS_A_OWNER),
    .bus_a_write_data(BUS_A_WRITE_DATA),
    .bus_a_retire(BUS_A_RETIRE),

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

	.aram_addr(SNES_ARAM_ADDR),
	.aram_d(SNES_ARAM_D),
	.aram_q(ARAM_Q),
	.aram_ce_n(SNES_ARAM_CE_N),
	.aram_oe_n(SNES_ARAM_OE_N),
	.aram_we_n(SNES_ARAM_WE_N),

	.joy1_di(JOY1_DI),
	.joy2_di(JOY2_DI),
	.joy_strb(JOY_STRB),
	.joy1_clk(JOY1_CLK),
	.joy2_clk(JOY2_CLK),
	.joy1_p6(JOY1_P6),
	.joy2_p6(JOY2_P6),
	.joy2_p6_in(JOY2_P6_in),
	.sni_joy(SNI_JOY),

	.blend(BLEND),
	.pal(PAL),
	.high_res(HIGH_RES),
	.field_out(FIELD),
	.interlace(INTERLACE),
	.v224_mode(V224_MODE),
	.dotclk(DOTCLK),

	.rgb_out({B,G,R}),
	.hde(HBLANKn),
	.vde(VBLANKn),
	.hsync(HSYNC),
	.vsync(VSYNC),
	.hvcnt_atzero(HVCNT_ATZERO),

	.gg_en(GG_EN),
	.gg_code(GG_CODE),
	.gg_reset(GG_RESET),
	.gg_available(GG_AVAILABLE),
	
	.spc_mode(SPC_MODE),
	
	.io_addr(IO_ADDR),
	.io_dat(IO_DAT),
	.io_wr(IO_WR),

	.ss_addr(SS_EXT_ADDR[8:0]),
	.ss_regs_sel(SS_DSP_REGS_SEL),
	.ss_smp_sel(SS_SMP_SEL),
	.ss_busy(SS_BUSY),
	.ss_wr(~PAWR_N),
	.ss_di(SS_DO),
	.ss_spc_do(SS_SPC_DI),
	.ss_ppu_do(SS_PPU_DI),

	.DBG_BG_EN(DBG_BG_EN),
	.DBG_CPU_EN(DBG_CPU_EN),
	
	.turbo(TURBO),
	
	.dsp_freq(DSP_FREQ),

	.audio_l(AUDIO_L),
	.audio_r(AUDIO_R)
);



wire  [7:0] MSU_DO;
wire        MSU_SEL;
// Address-qualified readiness, not CPURD-qualified: SCPU must be able to
// suppress a DMA destination write before asserting the source-read strobe.
reg msu_busy_delay;
always @(posedge MCLK) begin
  if(!RESET_N) msu_busy_delay <= 1'b1;
  else msu_busy_delay <= MSU_DATA_BUSY;
end
wire MSU_BUS_WAIT = USE_MSU && MSU_ENABLE && !CA[22] &&
                   CA[15:0] == 16'h2001 && (MSU_DATA_BUSY || msu_busy_delay);

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
	.data_busy_external(MSU_DATA_BUSY),
	.data_seek(MSU_DATA_SEEK),
	.data_req(MSU_DATA_REQ),

	.track_num(MSU_TRACK_NUM),
	.track_request(MSU_TRACK_REQUEST),
	.track_update(MSU_TRACK_UPDATE),
	.track_mounting(MSU_TRACK_MOUNTING),

	.status_track_missing(MSU_TRACK_MISSING),
	.status_audio_repeat(MSU_AUDIO_REPEAT),
	.audio_resume(MSU_AUDIO_RESUME),
	.status_audio_playing(MSU_AUDIO_PLAYING),
	.audio_stop(MSU_AUDIO_STOP),
	.audio_sector(MSU_AUDIO_SECTOR),
	.resume_sector(MSU_RESUME_SECTOR),
	.audio_loop_index(MSU_AUDIO_LOOP_INDEX),
	.resume_loop_index(MSU_RESUME_LOOP_INDEX),

	.volume(MSU_VOLUME)
);
end else begin
	assign MSU_DO  = 0;
	assign MSU_SEL = 0;
	assign MSU_TRACK_NUM = 0;
	assign MSU_TRACK_REQUEST = 0;
	assign MSU_TRACK_UPDATE = 0;
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
    .rom_lookahead_addr(DLH_LOOKAHEAD_ADDR),
    .rom_lookahead_sel(DLH_LOOKAHEAD_SEL),
	.rom_q(USE_STANDARD_SDRAM ? PASSIVE_ROM_DATA : ROM_Q),
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

	.ext_rtc(EXT_RTC),
	
	.cc_dip(CC_DIP),

	.ss_busy(SS_BUSY),
	.ss_ram_a(SS_EXT_ADDR[11:0]),
	.ss_dspn_regs_sel(SS_DSPN_REGS_SEL),
	.ss_dspn_ram_sel(SS_DSPN_RAM_SEL),
	.ss_di(SS_DO),
	.ss_do(SS_DSPN_DI)
);
end else begin
	assign DLH_DO = 0;
	assign DLH_IRQ_N = 1;
	assign DLH_ROM_ADDR = 0;
        assign DLH_LOOKAHEAD_ADDR=0;assign DLH_LOOKAHEAD_SEL=0;
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
assign MC_ADDR[1][23]=0;
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

CX4Map #(.ROM_HANDSHAKE(USE_STANDARD_SDRAM ? "TRUE" : "FALSE")) CX4Map
(
	.mclk(MCLK),
    .rom_hard_reset_n(MEM_HARD_RESET_N),.rom_epoch(MEM_EPOCH),.rom_flush(client_flush),.rom_flush_ack(MC_FLUSH_ACK[1]),
    .rom_fault(MC_FAULT[1]),
    .rom_snes_read_intent(BUS_A_READ_INTENT),.rom_snes_owner(BUS_A_OWNER),
    .rom_snes_retire(BUS_A_RETIRE),
    .rom_snes_wait(MC_SNES_WAIT[1]),
    .rom_req_valid(MC_VALID[1]),.rom_req_ready(MC_READY[1]),
    .rom_req_addr(MC_ADDR[1][22:0]),.rom_req_owner(MC_OWNER[1]),
    .rom_req_snes_owner(MC_SNES_OWNER[1]),
    .rom_req_tag(MC_TAG[1]),.rom_req_epoch(MC_EPOCH[1]),
    .rom_rsp_valid(MC_RSP_VALID[1]),.rom_rsp_ready(MC_RSP_READY[1]),
    .rom_rsp_data(MEM_RSP_DATA),.rom_rsp_owner(mem_rsp_local_owner),
    .rom_rsp_tag(MEM_RSP_TAG),.rom_rsp_epoch(MEM_RSP_EPOCH),
    .rom_rsp_error(MEM_RSP_ERROR || mem_rsp_identity_error),
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
	.bsram_mask(RAM_MASK),

	.ss_busy   (SS_BUSY),
	.ss_wr     (SS_BUSY & SS_CX4_SEL & ~CPUWR_N),
	.ss_do     (SS_CX4_DO_REG),

	.ss_cache_a  (SS_EXT_ADDR[9:0]),
	.ss_cache_sel(SS_CX4_CACHE_SEL),
	.ss_cache_di (SS_DO),
	.ss_cache_do (SS_CX4_DO_CACHE),

	.ss_idle     (SS_CX4_IDLE)
);
end else begin
assign MAP_ACTIVE[0] = 0;
assign MC_VALID[1]=0;assign MC_ADDR[1][22:0]=0;assign MC_OWNER[1]=0;
assign MC_SNES_OWNER[1]=0;assign MC_TAG[1]=0;assign MC_EPOCH[1]=0;
assign MC_RSP_READY[1]=0;assign MC_FLUSH_ACK[1]=1;assign MC_FAULT[1]=0;
assign MC_SNES_WAIT[1]=0;
// Stub CX4Map SS readback wires when CX4 is compiled out so the
// SS_CX4_DI mux does not read undriven nets in the USE_CX4==0 config.
assign SS_CX4_DO_REG = 8'h00;
assign SS_CX4_DO_CACHE = 8'h00;
assign SS_CX4_IDLE = 1'b1;   // not a CX4 cart -> never holds the snapshot
end
endgenerate

wire [7:0]  SDD_DO;
wire        SDD_IRQ_N;
assign MC_ADDR[2][23]=0;
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

SDD1Map #(.ROM_HANDSHAKE(USE_STANDARD_SDRAM ? "TRUE" : "FALSE")) SDD1Map
(
	.mclk(MCLK),
    .rom_hard_reset_n(MEM_HARD_RESET_N),.rom_epoch(MEM_EPOCH),.rom_flush(client_flush),.rom_flush_ack(MC_FLUSH_ACK[2]),
    .rom_fault(MC_FAULT[2]),
    .rom_snes_read_intent(BUS_A_READ_INTENT),.rom_snes_owner(BUS_A_OWNER),
    .rom_snes_retire(BUS_A_RETIRE),
    .rom_snes_wait(MC_SNES_WAIT[2]),
    .rom_req_valid(MC_VALID[2]),.rom_req_ready(MC_READY[2]),
    .rom_req_addr(MC_ADDR[2][22:0]),.rom_req_owner(MC_OWNER[2]),
    .rom_req_snes_owner(MC_SNES_OWNER[2]),
    .rom_req_tag(MC_TAG[2]),.rom_req_epoch(MC_EPOCH[2]),
    .rom_rsp_valid(MC_RSP_VALID[2]),.rom_rsp_ready(MC_RSP_READY[2]),
    .rom_rsp_data(MEM_RSP_DATA),.rom_rsp_owner(mem_rsp_local_owner),
    .rom_rsp_tag(MEM_RSP_TAG),.rom_rsp_epoch(MEM_RSP_EPOCH),
    .rom_rsp_error(MEM_RSP_ERROR || mem_rsp_identity_error),
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
end else begin
assign MAP_ACTIVE[1] = 0;
assign MC_VALID[2]=0;assign MC_ADDR[2][22:0]=0;assign MC_OWNER[2]=0;
assign MC_SNES_OWNER[2]=0;assign MC_TAG[2]=0;assign MC_EPOCH[2]=0;
assign MC_RSP_READY[2]=0;assign MC_FLUSH_ACK[2]=1;assign MC_FAULT[2]=0;
assign MC_SNES_WAIT[2]=0;
end
endgenerate

wire [7:0]  GSU_DO;
wire        GSU_IRQ_N;
assign MC_ADDR[3][23]=0;
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

GSUMap #(.ROM_HANDSHAKE(USE_STANDARD_SDRAM ? "TRUE" : "FALSE")) GSUMap
(
	.mclk(MCLK),
    .rom_hard_reset_n(MEM_HARD_RESET_N),.rom_epoch(MEM_EPOCH),.rom_flush(client_flush),.rom_flush_ack(MC_FLUSH_ACK[3]),
    .rom_fault(MC_FAULT[3]),
    .rom_snes_read_intent(BUS_A_READ_INTENT),.rom_snes_owner(BUS_A_OWNER),
    .rom_snes_retire(BUS_A_RETIRE),
    .rom_snes_wait(MC_SNES_WAIT[3]),
    .rom_req_valid(MC_VALID[3]),.rom_req_ready(MC_READY[3]),
    .rom_req_addr(MC_ADDR[3][22:0]),.rom_req_owner(MC_OWNER[3]),
    .rom_req_snes_owner(MC_SNES_OWNER[3]),
    .rom_req_tag(MC_TAG[3]),.rom_req_epoch(MC_EPOCH[3]),
    .rom_rsp_valid(MC_RSP_VALID[3]),.rom_rsp_ready(MC_RSP_READY[3]),
    .rom_rsp_data(MEM_RSP_DATA),.rom_rsp_owner(mem_rsp_local_owner),
    .rom_rsp_tag(MEM_RSP_TAG),.rom_rsp_epoch(MEM_RSP_EPOCH),
    .rom_rsp_error(MEM_RSP_ERROR || mem_rsp_identity_error),
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

	.turbo(GSU_TURBO),
	.fastrom(GSU_FASTROM),

	.ss_busy(SS_BUSY),
	.ss_wr(SS_BUSY & SS_GSU_SEL & ~CPUWR_N),
	.ss_do(SS_GSU_DI)
);
end else begin
assign MAP_ACTIVE[2] = 0;
assign MC_VALID[3]=0;assign MC_ADDR[3][22:0]=0;assign MC_OWNER[3]=0;
assign MC_SNES_OWNER[3]=0;assign MC_TAG[3]=0;assign MC_EPOCH[3]=0;
assign MC_RSP_READY[3]=0;assign MC_FLUSH_ACK[3]=1;assign MC_FAULT[3]=0;
assign MC_SNES_WAIT[3]=0;
end
endgenerate

assign GSU_ACTIVE = MAP_ACTIVE[2];

wire [7:0]  SA1_DO;
wire        SA1_IRQ_N;
assign MC_ADDR[4][23]=0;
wire [22:0] SA1_ROM_ADDR;
wire        SA1_ROM_CE_N;
wire        SA1_ROM_OE_N;
wire        SA1_ROM_WORD;
wire [19:0] SA1_BSRAM_ADDR;
wire [7:0]  SA1_BSRAM_D;
wire        SA1_BSRAM_CE_N;
wire        SA1_BSRAM_OE_N;
wire        SA1_BSRAM_WE_N;

wire [23:0] SA1_P65_A;
wire  [7:0] SA1_P65_DO;
wire        SA1_P65_RD_N;
wire        SA1_P65_WR_N;

wire        SS_SA1_ROMSEL;
wire        SS_SNS_ROMSEL;

generate
if (USE_SA1 == 1'b1) begin

SA1Map #(.ROM_HANDSHAKE(USE_STANDARD_SDRAM ? "TRUE" : "FALSE")) SA1Map
(
	.mclk(MCLK),
    .rom_hard_reset_n(MEM_HARD_RESET_N),.rom_epoch(MEM_EPOCH),.rom_flush(client_flush),.rom_flush_ack(MC_FLUSH_ACK[4]),
    .rom_fault(MC_FAULT[4]),
    .rom_snes_read_intent(BUS_A_READ_INTENT),.rom_snes_owner(BUS_A_OWNER),
    .rom_snes_retire(BUS_A_RETIRE),
    .rom_snes_wait(MC_SNES_WAIT[4]),
    .rom_req_valid(MC_VALID[4]),.rom_req_ready(MC_READY[4]),
    .rom_req_addr(MC_ADDR[4][22:0]),.rom_req_owner(MC_OWNER[4]),
    .rom_req_snes_owner(MC_SNES_OWNER[4]),
    .rom_req_tag(MC_TAG[4]),.rom_req_epoch(MC_EPOCH[4]),
    .rom_rsp_valid(MC_RSP_VALID[4]),.rom_rsp_ready(MC_RSP_READY[4]),
    .rom_rsp_data(MEM_RSP_DATA),.rom_rsp_owner(mem_rsp_local_owner),
    .rom_rsp_tag(MEM_RSP_TAG),.rom_rsp_epoch(MEM_RSP_EPOCH),
    .rom_rsp_error(MEM_RSP_ERROR || mem_rsp_identity_error),
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
	.bsram_mask(RAM_MASK),

	.sa1_p65_a(SA1_P65_A),
	.sa1_p65_do(SA1_P65_DO),
	.sa1_p65_rd_n(SA1_P65_RD_N),
	.sa1_p65_wr_n(SA1_P65_WR_N),

	.ss_busy(SS_BUSY),

	.ss_sa1_romsel(SS_SA1_ROMSEL),
	.ss_sns_romsel(SS_SNS_ROMSEL)
);
end else begin
assign MAP_ACTIVE[3] = 0;
assign MC_VALID[4]=0;assign MC_ADDR[4][22:0]=0;assign MC_OWNER[4]=0;
assign MC_SNES_OWNER[4]=0;assign MC_TAG[4]=0;assign MC_EPOCH[4]=0;
assign MC_RSP_READY[4]=0;assign MC_FLUSH_ACK[4]=1;assign MC_FAULT[4]=0;
assign MC_SNES_WAIT[4]=0;
end
endgenerate

wire [7:0]  SPC7110_DO;
wire        SPC7110_IRQ_N;
assign MC_ADDR[5][23]=0;
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
SPC7110Map #(.ROM_HANDSHAKE(USE_STANDARD_SDRAM ? "TRUE" : "FALSE")) SPC7110Map
(
	.mclk(MCLK),
    .rom_hard_reset_n(MEM_HARD_RESET_N),.rom_epoch(MEM_EPOCH),.rom_flush(client_flush),.rom_flush_ack(MC_FLUSH_ACK[5]),
    .rom_fault(MC_FAULT[5]),
    .rom_snes_read_intent(BUS_A_READ_INTENT),.rom_snes_owner(BUS_A_OWNER),
    .rom_snes_retire(BUS_A_RETIRE),
    .rom_snes_wait(MC_SNES_WAIT[5]),
    .rom_req_valid(MC_VALID[5]),.rom_req_ready(MC_READY[5]),
    .rom_req_addr(MC_ADDR[5][22:0]),.rom_req_owner(MC_OWNER[5]),
    .rom_req_snes_owner(MC_SNES_OWNER[5]),
    .rom_req_tag(MC_TAG[5]),.rom_req_epoch(MC_EPOCH[5]),
    .rom_rsp_valid(MC_RSP_VALID[5]),.rom_rsp_ready(MC_RSP_READY[5]),
    .rom_rsp_data(MEM_RSP_DATA),.rom_rsp_owner(mem_rsp_local_owner),
    .rom_rsp_tag(MEM_RSP_TAG),.rom_rsp_epoch(MEM_RSP_EPOCH),
    .rom_rsp_error(MEM_RSP_ERROR || mem_rsp_identity_error),
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
end else begin
assign MAP_ACTIVE[4] = 0;
assign MC_VALID[5]=0;assign MC_ADDR[5][22:0]=0;assign MC_OWNER[5]=0;
assign MC_SNES_OWNER[5]=0;assign MC_TAG[5]=0;assign MC_EPOCH[5]=0;
assign MC_RSP_READY[5]=0;assign MC_FLUSH_ACK[5]=1;assign MC_FAULT[5]=0;
assign MC_SNES_WAIT[5]=0;
end
endgenerate

wire [7:0]  BSX_DO;
wire        BSX_IRQ_N;
assign MC_ADDR[6][23]=0;
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
BSXMap #(.ROM_TRANSACTIONAL(USE_STANDARD_SDRAM ? "TRUE" : "FALSE")) BSXMap
(
	.mclk(MCLK),
    .rom_hard_reset_n(MEM_HARD_RESET_N),.rom_epoch(MEM_EPOCH),.rom_flush(client_flush),.rom_flush_ack(MC_FLUSH_ACK[6]),
    .rom_fault(MC_FAULT[6]),
    .rom_snes_read_intent(BUS_A_READ_INTENT),.rom_snes_owner(BUS_A_OWNER),
    .rom_snes_retire(BUS_A_RETIRE),
    .rom_snes_wait(MC_SNES_WAIT[6]),
    .rom_req_valid(MC_VALID[6]),.rom_req_ready(MC_READY[6]),
    .rom_req_addr(MC_ADDR[6][22:0]),.rom_req_owner(MC_OWNER[6]),
    .rom_req_snes_owner(MC_SNES_OWNER[6]),
    .rom_req_tag(MC_TAG[6]),.rom_req_epoch(MC_EPOCH[6]),
    .rom_rsp_valid(MC_RSP_VALID[6]),.rom_rsp_ready(MC_RSP_READY[6]),
    .rom_rsp_data(MEM_RSP_DATA),.rom_rsp_owner(mem_rsp_local_owner),
    .rom_rsp_tag(MEM_RSP_TAG),.rom_rsp_epoch(MEM_RSP_EPOCH),
    .rom_rsp_error(MEM_RSP_ERROR || mem_rsp_identity_error),
    .rom_snes_write_intent(BUS_A_WRITE_INTENT),.rom_snes_write_data(BUS_A_WRITE_DATA),.rom_snes_write_wait(BSX_SNES_WRITE_WAIT),
    .rom_rsp_write(MEM_RSP_WRITE),.rom_req_drain(BSX_REQ_DRAIN),
    .rom_req_write(MC_WRITE[6]),.rom_req_wdata(MC_WDATA[6]),.rom_req_wstrb(MC_WSTRB[6]),
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
end else begin
assign MAP_ACTIVE[5] = 0;
assign MC_VALID[6]=0;assign MC_ADDR[6][22:0]=0;assign MC_OWNER[6]=0;
assign MC_SNES_OWNER[6]=0;assign MC_TAG[6]=0;assign MC_EPOCH[6]=0;
assign MC_RSP_READY[6]=0;assign MC_FLUSH_ACK[6]=1;assign MC_FAULT[6]=0;
assign MC_SNES_WAIT[6]=0;
assign MC_WRITE[6]=0;assign MC_WDATA[6]=0;assign MC_WSTRB[6]=0;assign BSX_SNES_WRITE_WAIT=0;assign BSX_REQ_DRAIN=0;
end
endgenerate

wire [7:0]  SUFAMI_DO;
wire        SUFAMI_IRQ_N;
wire [22:0] SUFAMI_ROM_ADDR;
wire        SUFAMI_ROM_CE_N;
wire        SUFAMI_ROM_OE_N;
wire        SUFAMI_ROM_WORD;
wire [19:0] SUFAMI_BSRAM_ADDR;
wire [7:0]  SUFAMI_BSRAM_D;
wire        SUFAMI_BSRAM_CE_N;
wire        SUFAMI_BSRAM_OE_N;
wire        SUFAMI_BSRAM_WE_N;

generate
if (USE_SUFAMI == 1'b1) begin
SufamiMap SufamiMap
(
	.mclk(MCLK),
	.rst_n(RESET_N),

	.ca(CA),
	.di(DO),
	.do(SUFAMI_DO),
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

	.irq_n(SUFAMI_IRQ_N),

	.rom_addr(SUFAMI_ROM_ADDR),
    .rom_lookahead_addr(SUFAMI_LOOKAHEAD_ADDR),
    .rom_lookahead_sel(SUFAMI_LOOKAHEAD_SEL),
	.rom_q(USE_STANDARD_SDRAM ? PASSIVE_ROM_DATA : ROM_Q),
	.rom_ce_n(SUFAMI_ROM_CE_N),
	.rom_oe_n(SUFAMI_ROM_OE_N),
	.rom_word(SUFAMI_ROM_WORD),

	.bsram_addr(SUFAMI_BSRAM_ADDR),
	.bsram_d(SUFAMI_BSRAM_D),
	.bsram_q(BSRAM_Q),
	.bsram_ce_n(SUFAMI_BSRAM_CE_N),
	.bsram_oe_n(SUFAMI_BSRAM_OE_N),
	.bsram_we_n(SUFAMI_BSRAM_WE_N),

	.map_active(MAP_ACTIVE[6]),
	.map_ctrl(ROM_TYPE),
	.rom_mask(ROM_MASK),
	.bsram_mask(RAM_MASK),

	.ext_rtc(EXT_RTC),
	
	.cart_swap(SUFAMI_SWAP)
);
end else begin
assign MAP_ACTIVE[6] = 0;
assign SUFAMI_LOOKAHEAD_ADDR=0;assign SUFAMI_LOOKAHEAD_SEL=0;
end
endgenerate

wire        SS_BUSY;
wire  [7:0] SS_DO;
wire [23:0] SS_ROM_ADDR;

wire [19:0] SS_EXT_ADDR;
wire  [7:0] SS_SPC_DI;
wire  [7:0] SS_PPU_DI;
wire  [7:0] SS_DSPN_DI;
wire  [7:0] SS_GSU_DI;
wire        SS_DO_OVR;
wire        SS_ROM_OVR;
wire        SS_ARAM_SEL, SS_DSP_REGS_SEL, SS_SMP_SEL;
wire        SS_BSRAM_SEL;
wire        SS_DSPN_REGS_SEL, SS_DSPN_RAM_SEL;
wire        SS_GSU_SEL;

wire  [7:0] SS_CX4_DO_REG;
wire  [7:0] SS_CX4_DO_CACHE;
wire  [7:0] SS_CX4_DI;
wire        SS_CX4_SEL;
wire        SS_CX4_CACHE_SEL;
wire        SS_CX4_IDLE;
assign SS_CX4_DI = SS_CX4_CACHE_SEL ? SS_CX4_DO_CACHE : SS_CX4_DO_REG;
// Hold the snapshot until the CX4 is idle (only when a CX4 cart is active).
wire        CX4_SS_OK = ~MAP_ACTIVE[0] | SS_CX4_IDLE;


generate
if (USE_SS == 1'b1) begin
savestates ss
(
	.reset_n(RESET_N),
	.clk(MCLK),

	.save(SS_SAVE),
	.save_sd(SS_TOSD),
	.load(SS_LOAD),
	.slot(SS_SLOT),

	.ram_size(RAM_SIZE),
	.rom_type(ROM_TYPE),

	.sysclkf_ce(SYSCLKF_CE),
	.sysclkr_ce(SYSCLKR_CE),

	.romsel_n(ROMSEL_N),
	.rom_q(ROM_Q),

	.ca(CA),
	.cpurd_n(CPURD_N),
	.cpuwr_n(CPUWR_N),

	.pa(PA),
	.pard_n(PARD_N),
	.pawr_n(PAWR_N),

	.di(DO),
	.ss_do(SS_DO),

	.rom_addr(SS_ROM_ADDR),

	.ddr_di(SS_DDR_DI),
	.ddr_ack(SS_DDR_ACK),
	.ddr_do(SS_DDR_DO),
	.ddr_addr(SS_DDR_ADDR),
	.ddr_we(SS_DDR_WE),
	.ddr_be(SS_DDR_BE),
	.ddr_req(SS_DDR_REQ),

	.ext_addr(SS_EXT_ADDR),

	.spc_di(SS_SPC_DI),
	.aram_sel(SS_ARAM_SEL),
	.dsp_regs_sel(SS_DSP_REGS_SEL),
	.smp_regs_sel(SS_SMP_SEL),

	.ppu_di(SS_PPU_DI),

	.bsram_sel(SS_BSRAM_SEL),
	.bsram_di(BSRAM_Q),

	.dspn_regs_sel(SS_DSPN_REGS_SEL),
	.dspn_ram_sel(SS_DSPN_RAM_SEL),
	.dspn_di(SS_DSPN_DI),

	.gsu_regs_sel(SS_GSU_SEL),
	.gsu_di(SS_GSU_DI),

	.cx4_regs_sel(SS_CX4_SEL),
	.cx4_di(SS_CX4_DI),
	.cx4_cache_sel(SS_CX4_CACHE_SEL),
	.cx4_ss_ok(CX4_SS_OK),

	.sa1_active(MAP_ACTIVE[3]),
	.sa1_a(SA1_P65_A),
	.sa1_di(SA1_P65_DO),
	.sa1_rd_n(SA1_P65_RD_N),
	.sa1_wr_n(SA1_P65_WR_N),
	.sa1_sa1_romsel(SS_SA1_ROMSEL),
	.sa1_sns_romsel(SS_SNS_ROMSEL),

	.ss_do_ovr(SS_DO_OVR),
	.ss_rom_ovr(SS_ROM_OVR),
	.ss_busy(SS_BUSY)
);
end else begin
	assign SS_DO = 0;
	assign SS_ROM_ADDR = 0;
	assign SS_EXT_ADDR = 0;
	assign SS_DDR_DO = 0;
	assign SS_DDR_ADDR = 0;
	assign SS_DDR_WE = 0;
	assign SS_DDR_BE = 0;
	assign SS_DDR_REQ = 0;
	assign SS_ARAM_SEL = 0;
	assign SS_DSP_REGS_SEL = 0;
	assign SS_SMP_SEL = 0;
	assign SS_BSRAM_SEL = 0;
	assign SS_DSPN_REGS_SEL = 0;
	assign SS_DSPN_RAM_SEL = 0;
	assign SS_GSU_SEL = 0;
	assign SS_CX4_SEL = 0;
	assign SS_CX4_CACHE_SEL = 0;
	assign SS_DO_OVR = 0;
	assign SS_ROM_OVR = 0;
	assign SS_BUSY = 0;
end
endgenerate

assign SS_AVAIL = ~|{ROM_TYPE[7:4]} | MAP_ACTIVE[3] | (ROM_TYPE[7:6] == 2'b10) | MAP_ACTIVE[2] | MAP_ACTIVE[0]; // Basic carts + SA1 + DSPn + GSU + CX4

assign TURBO_ALLOW = ~(MAP_ACTIVE[3] | MAP_ACTIVE[1] | SS_BUSY);

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
