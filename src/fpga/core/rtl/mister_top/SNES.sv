module MAIN_SNES (
    input wire clk_mem_85_9,
    input wire clk_sys_21_48,

    input wire core_reset,

    input [64:0] rtc,

    // Settings
    input wire multitap_enabled,
    input wire lightgun_enabled,
    input wire lightgun_type,
    input wire [7:0] lightgun_dpad_aim_speed,

    // Inputs
    input wire p1_button_a,
    input wire p1_button_b,
    input wire p1_button_x,
    input wire p1_button_y,
    input wire p1_button_trig_l,
    input wire p1_button_trig_r,
    input wire p1_button_start,
    input wire p1_button_select,
    input wire p1_dpad_up,
    input wire p1_dpad_down,
    input wire p1_dpad_left,
    input wire p1_dpad_right,

    input wire [7:0] p1_lstick_x,
    input wire [7:0] p1_lstick_y,

    input wire p2_button_a,
    input wire p2_button_b,
    input wire p2_button_x,
    input wire p2_button_y,
    input wire p2_button_trig_l,
    input wire p2_button_trig_r,
    input wire p2_button_start,
    input wire p2_button_select,
    input wire p2_dpad_up,
    input wire p2_dpad_down,
    input wire p2_dpad_left,
    input wire p2_dpad_right,

    input wire p3_button_a,
    input wire p3_button_b,
    input wire p3_button_x,
    input wire p3_button_y,
    input wire p3_button_trig_l,
    input wire p3_button_trig_r,
    input wire p3_button_start,
    input wire p3_button_select,
    input wire p3_dpad_up,
    input wire p3_dpad_down,
    input wire p3_dpad_left,
    input wire p3_dpad_right,

    input wire p4_button_a,
    input wire p4_button_b,
    input wire p4_button_x,
    input wire p4_button_y,
    input wire p4_button_trig_l,
    input wire p4_button_trig_r,
    input wire p4_button_start,
    input wire p4_button_select,
    input wire p4_dpad_up,
    input wire p4_dpad_down,
    input wire p4_dpad_left,
    input wire p4_dpad_right,

    // ROM loading
    input wire ioctl_download,
    input wire ioctl_wr,
    input wire [24:0] ioctl_addr,
    input wire [15:0] ioctl_dout,

    input wire [7:0] rom_type,
    input wire [3:0] rom_size,
    input wire [3:0] ram_size,
    input wire PAL,

    // Saves
    input wire save_download,
    input wire sd_rd,
    input wire sd_wr,
    input wire [16:0] sd_buff_addr,
    output wire [15:0] sd_buff_din,
    input wire [15:0] sd_buff_dout,

    output reg [3:0] sram_size,

    // SDRAM
    output wire [12:0] dram_a,
    output wire [ 1:0] dram_ba,
    inout  wire [15:0] dram_dq,
    output wire [ 1:0] dram_dqm,
    output wire        dram_clk,
    output wire        dram_cke,
    output wire        dram_ras_n,
    output wire        dram_cas_n,
    output wire        dram_we_n,

    // PSRAM
    output wire [21:16] cram0_a,
    inout wire [15:0] cram0_dq,
    input wire cram0_wait,
    output wire cram0_clk,
    output wire cram0_adv_n,
    output wire cram0_cre,
    output wire cram0_ce0_n,
    output wire cram0_ce1_n,
    output wire cram0_oe_n,
    output wire cram0_we_n,
    output wire cram0_ub_n,
    output wire cram0_lb_n,

    output wire [21:16] cram1_a,
    inout wire [15:0] cram1_dq,
    input wire cram1_wait,
    output wire cram1_clk,
    output wire cram1_adv_n,
    output wire cram1_cre,
    output wire cram1_ce0_n,
    output wire cram1_ce1_n,
    output wire cram1_oe_n,
    output wire cram1_we_n,
    output wire cram1_ub_n,
    output wire cram1_lb_n,

    // Video
    output wire vblank,
    output wire hblank,
    output wire vsync,
    output wire hsync,

    output wire [7:0] video_r,
    output wire [7:0] video_g,
    output wire [7:0] video_b,

    // Audio
    output wire [15:0] audio_l,
    output wire [15:0] audio_r
);
  parameter USE_CX4 = 1'b0;
  parameter USE_SDD1 = 1'b0;
  parameter USE_GSU = 1'b0;
  parameter USE_SA1 = 1'b0;
  parameter USE_DSPn = 1'b0;
  parameter USE_SPC7110 = 1'b0;
  parameter USE_BSX = 1'b0;
  parameter USE_MSU = 1'b0;

  initial begin
    $info("Selected chips");
    $info("CX4 %d", USE_CX4);
    $info("SDD1 %d", USE_SDD1);
    $info("GSU %d", USE_GSU);
    $info("SA1 %d", USE_SA1);
    $info("DSPn %d", USE_DSPn);
    $info("SPC7110 %d", USE_SPC7110);
    $info("BSX %d", USE_BSX);
    $info("MSU %d", USE_MSU);
  end

  // Hardcoded wires
  wire [63:0] status = 0;
  wire [5:0] ioctl_index = 0;  // TODO
  wire GUN_BTN = status[27];
  wire [1:0] GUN_MODE = lightgun_enabled ? 2'd1 : 0;
  wire GSU_TURBO = status[18];
  wire BLEND = ~status[16];
  wire [1:0] mouse_mode = status[6:5];
  wire joy_swap = status[7] | piano;

  wire [6:0] USER_IN = 0;
  wire [6:0] USER_OUT;

  reg [128:0] gg_code = 0;
  wire gg_available;

  wire OSD_STATUS = 0;

  wire piano = 0;
  wire piano_joypad_do = 0;

  // Renamed wires
  wire clk_sys = clk_sys_21_48;
  wire clk_mem = clk_mem_85_9;

  wire code_index = &ioctl_index;
  wire code_download = ioctl_download & code_index;
  wire cart_download = ioctl_download & ioctl_index[5:0] == 0;
  // wire spc_download = ioctl_download & ioctl_index[5:0] == 6'h01;
  wire spc_download = 0;

  reg new_vmode;
  always @(posedge clk_sys) begin
    reg old_pal;
    int to;

    if (~reset) begin
      old_pal <= PAL;
      if (old_pal != PAL) to <= 2000000;
    end

    if (to) begin
      to <= to - 1;
      if (to == 1) new_vmode <= ~new_vmode;
    end
  end

  //////////////////////////  ROM DETECT  /////////////////////////////////

  reg [23:0] rom_mask, ram_mask;
  // Replaced by rom_parser
  // always @(posedge clk_sys) begin
  // 	reg [3:0] rom_size;
  // 	reg [3:0] ram_size;
  // 	reg       rom_region = 0;

  // 	if (cart_download) begin
  // 		if(ioctl_wr) begin
  // 			if (ioctl_addr == 0) begin
  // 				rom_size <= 4'hC;
  // 				ram_size <= 4'h0;
  // 				if(!LHRom_type && ioctl_dout[7:0]) {ram_size,rom_size} <= ioctl_dout[7:0];

  // 				case(LHRom_type)
  // 					1: rom_type <= 0;
  // 					2: rom_type <= 0;
  // 					3: rom_type <= 1;
  // 					4: rom_type <= 2;
  // 					default: rom_type <= ioctl_dout[15:8];
  // 				endcase
  // 			end

  // 			if (ioctl_addr == 2) begin
  // 				rom_region <= ioctl_dout[8];
  // 			end

  // 			if(LHRom_type == 2) begin
  // 				if(ioctl_addr == ('h7FD6+'h200)) rom_size <= ioctl_dout[11:8];
  // 				if(ioctl_addr == ('h7FD8+'h200)) ram_size <= ioctl_dout[3:0];
  // 			end
  // 			else if(LHRom_type == 3) begin
  // 				if(ioctl_addr == ('hFFD6+'h200)) rom_size <= ioctl_dout[11:8];
  // 				if(ioctl_addr == ('hFFD8+'h200)) ram_size <= ioctl_dout[3:0];
  // 			end
  // 			else if(LHRom_type == 4) begin
  // 				if(ioctl_addr == ('h40FFD6+'h200)) rom_size <= ioctl_dout[11:8];
  // 				if(ioctl_addr == ('h40FFD8+'h200)) ram_size <= ioctl_dout[3:0];
  // 			end

  // 			rom_mask <= (24'd1024 << rom_size) - 1'd1;
  // 			ram_mask <= ram_size ? (24'd1024 << ram_size) - 1'd1 : 24'd0;

  // 			sram_size <= ram_size;
  // 		end
  // 	end
  // 	else begin
  // 		PAL <= (!status[15:14]) ? rom_region : status[15];
  // 	end
  // end

  reg prev_cart_download;
  reg [2:0] parser_delay = 7;

  always @(posedge clk_sys) begin
    prev_cart_download <= cart_download;
    if (prev_cart_download && ~cart_download) begin
      parser_delay <= 6;
    end

    if (parser_delay != 7 && parser_delay != 0) begin
      parser_delay <= parser_delay - 1;
    end

    if (parser_delay == 1) begin
      // Set up masks before core starts
      rom_mask  <= (24'd1024 << rom_size) - 1'd1;
      ram_mask  <= ram_size ? (24'd1024 << ram_size) - 1'd1 : 24'd0;

      sram_size <= ram_size;
    end
  end

  reg spc_mode = 0;
  always @(posedge clk_sys) begin
    if (ioctl_wr) begin
      spc_mode <= spc_download;
    end
  end

  ////////////////////////////  SYSTEM  ///////////////////////////////////

  wire GSU_ACTIVE;
  wire turbo_allow;

  reg [15:0] main_audio_l;
  reg [15:0] main_audio_r;

  wire vblank_n;
  wire hblank_n;
  wire dotclk;

  assign vblank = ~vblank_n;
  assign hblank = ~hblank_n;

  wire [7:0] R;
  wire [7:0] G;
  wire [7:0] B;

  main #(
      .USE_CX4(USE_CX4),
      .USE_SDD1(USE_SDD1),
      .USE_GSU(USE_GSU),
      .USE_SA1(USE_SA1),
      .USE_DSPn(USE_DSPn),
      .USE_SPC7110(USE_SPC7110),
      .USE_BSX(USE_BSX),
      .USE_MSU(USE_MSU)
  ) main (
      .RESET_N(RESET_N),

      .MCLK(clk_sys),  // 21.47727 / 21.28137
      .ACLK(clk_sys),

      .GSU_ACTIVE(GSU_ACTIVE),
      .GSU_TURBO (GSU_TURBO),

      .ROM_TYPE(rom_type),
      .ROM_MASK(rom_mask),
      .RAM_MASK(ram_mask),
      .PAL(PAL),
      .BLEND(BLEND),

      .ROM_ADDR(ROM_ADDR),
      .ROM_D(ROM_D),
      .ROM_Q(ROM_Q),
      .ROM_OE_N(ROM_OE_N),
      .ROM_WE_N(ROM_WE_N),
      .ROM_WORD(ROM_WORD),

      .BSRAM_ADDR(BSRAM_ADDR),
      .BSRAM_D(BSRAM_D),
      .BSRAM_Q(BSRAM_Q),
      .BSRAM_CE_N(BSRAM_CE_N),
      .BSRAM_OE_N(BSRAM_OE_N),
      .BSRAM_WE_N(BSRAM_WE_N),

      .WRAM_ADDR(WRAM_ADDR),
      .WRAM_D(WRAM_D),
      .WRAM_Q(WRAM_Q),
      .WRAM_CE_N(WRAM_CE_N),
      .WRAM_OE_N(WRAM_OE_N),
      .WRAM_WE_N(WRAM_WE_N),

      .VRAM1_ADDR(VRAM1_ADDR),
      .VRAM1_DI  (VRAM1_Q),
      .VRAM1_DO  (VRAM1_D),
      .VRAM1_WE_N(VRAM1_WE_N),

      .VRAM2_ADDR(VRAM2_ADDR),
      .VRAM2_DI  (VRAM2_Q),
      .VRAM2_DO  (VRAM2_D),
      .VRAM2_WE_N(VRAM2_WE_N),

      .ARAM_ADDR(ARAM_ADDR),
      .ARAM_D(ARAM_D),
      .ARAM_Q(ARAM_Q),
      .ARAM_CE_N(ARAM_CE_N),
      .ARAM_OE_N(ARAM_OE_N),
      .ARAM_WE_N(ARAM_WE_N),

      .R(R),
      .G(G),
      .B(B),

      // .FIELD(FIELD), // TODO
      // .INTERLACE(INTERLACE),
      // .HIGH_RES(HIGH_RES),
      .DOTCLK(dotclk),

      .HBLANKn(hblank_n),
      .VBLANKn(vblank_n),
      .HSYNC  (hsync),
      .VSYNC  (vsync),

      .JOY1_DI(JOY1_DI),
      .JOY2_DI(GUN_MODE ? LG_DO : JOY2_DI),
      .JOY_STRB(JOY_STRB),
      .JOY1_CLK(JOY1_CLK),
      .JOY2_CLK(JOY2_CLK),
      .JOY1_P6(JOY1_P6),
      .JOY2_P6(JOY2_P6),
      .JOY2_P6_in(JOY2_P6_DI),

      .EXT_RTC(rtc),

      .GG_EN(status[24]),
      .GG_CODE(gg_code),
      .GG_RESET((code_download && ioctl_wr && !ioctl_addr) || cart_download),
      .GG_AVAILABLE(gg_available),

      .SPC_MODE(spc_mode),

      .IO_ADDR(ioctl_addr[16:0]),
      .IO_DAT (ioctl_dout),
      .IO_WR  (spc_download & ioctl_wr),

      .TURBO(status[4] & turbo_allow),
      .TURBO_ALLOW(turbo_allow),

`ifdef DEBUG_BUILD
      .DBG_BG_EN (DBG_BG_EN),
      .DBG_CPU_EN(DBG_CPU_EN),
`else
      .DBG_BG_EN (5'b11111),
      .DBG_CPU_EN(1'b1),
`endif

      // MSU register handling
      // .MSU_TRACK_NUM(msu_track_num),
      // .MSU_TRACK_REQUEST(msu_track_request),
      // .MSU_TRACK_MOUNTING(msu_track_mounting),
      // .MSU_TRACK_MISSING(msu_track_missing),
      // .MSU_VOLUME(msu_volume),
      // .MSU_AUDIO_REPEAT(msu_audio_repeat),
      // .MSU_AUDIO_STOP(msu_audio_stop),
      // .MSU_AUDIO_PLAYING(msu_audio_playing),
      // .MSU_DATA_ADDR(msu_data_addr),
      // .MSU_DATA(msu_data),
      // .MSU_DATA_ACK(msu_data_ack),
      // .MSU_DATA_SEEK(msu_data_seek),
      // .MSU_DATA_REQ(msu_data_req),
      .MSU_ENABLE(0),  // TODO

      .AUDIO_L(audio_l),
      .AUDIO_R(audio_r)
  );

  wire reset = core_reset | cart_download | spc_download | bk_loading | clearing_ram | msu_data_download | parser_delay != 0;

  reg RESET_N = 0;
  reg RFSH = 0;
  always @(posedge clk_sys) begin
    reg [1:0] div;

    div  <= div + 1'd1;
    RFSH <= !div;

    if (div == 2) RESET_N <= ~reset;
  end

  always @(posedge clk_sys) begin
    video_r <= (LG_TARGET && lightgun_enabled) ? {8{LG_TARGET[0]}} : R;
    video_g <= (LG_TARGET && lightgun_enabled) ? {8{LG_TARGET[1]}} : G;
    video_b <= (LG_TARGET && lightgun_enabled) ? {8{LG_TARGET[2]}} : B;
  end

  ////////////////////////////  MEMORY  ///////////////////////////////////

  reg [16:0] mem_fill_addr;
  // Slowed down for PSRAM
  reg [1:0] clear_div = 0;
  reg clearing_ram = 0;
  always @(posedge clk_sys) begin
    if (~old_downloading & cart_download) clearing_ram <= 1'b1;

    if (&mem_fill_addr) clearing_ram <= 0;

    clear_div <= clear_div + 1;

    if (clearing_ram) begin
      if (clear_div == 0) begin
        mem_fill_addr <= mem_fill_addr + 1'b1;
      end
    end else mem_fill_addr <= 0;
  end

  reg [7:0] wram_fill_data;
  always @* begin
    case (status[22:21])
      0: wram_fill_data = (mem_fill_addr[8] ^ mem_fill_addr[2]) ? 8'h66 : 8'h99;
      1: wram_fill_data = (mem_fill_addr[9] ^ mem_fill_addr[0]) ? 8'hFF : 8'h00;
      2: wram_fill_data = 8'h55;
      3: wram_fill_data = 8'hFF;
    endcase
  end

  reg [7:0] aram_fill_data;
  always @* begin
    case (status[45:44])
      0: aram_fill_data = (mem_fill_addr[8] ^ mem_fill_addr[2]) ? 8'h66 : 8'h99;
      1: aram_fill_data = (mem_fill_addr[9] ^ mem_fill_addr[0]) ? 8'hFF : 8'h00;
      2: aram_fill_data = 8'h55;
      3: aram_fill_data = 8'hFF;
    endcase
  end

  wire [23:0] ROM_ADDR;
  wire ROM_OE_N;
  wire ROM_WE_N;
  wire ROM_WORD;
  wire [15:0] ROM_D;
  wire [15:0] ROM_Q;

  sdram sdram (
      .init(0),  //~clock_locked),
      .clk(clk_mem),

      .addr(cart_download ? ioctl_addr : ROM_ADDR),
      .din (cart_download ? ioctl_dout : ROM_D),
      .dout(ROM_Q),
      .rd  (~cart_download & (RESET_N ? ~ROM_OE_N : RFSH)),
      .wr  (cart_download ? ioctl_wr : ~ROM_WE_N),
      .word(cart_download | ROM_WORD),
      .busy(),

      // Actual SDRAM interface
      .SDRAM_DQ(dram_dq),
      .SDRAM_A(dram_a),
      .SDRAM_DQML(dram_dqm[0]),
      .SDRAM_DQMH(dram_dqm[1]),
      .SDRAM_BA(dram_ba),
      .SDRAM_nWE(dram_we_n),
      .SDRAM_nRAS(dram_ras_n),
      .SDRAM_nCAS(dram_cas_n),
      .SDRAM_CLK(dram_clk),
      .SDRAM_CKE(dram_cke)
  );

  wire [16:0] WRAM_ADDR;
  wire        WRAM_CE_N;
  wire        WRAM_OE_N;
  wire        WRAM_WE_N;
  wire [7:0] WRAM_Q, WRAM_D;

  wire [16:0] psram_wram_addr = clearing_ram ? mem_fill_addr[16:0] : WRAM_ADDR;
  wire [15:0] wram_data_in = clearing_ram ? {wram_fill_data, wram_fill_data} : // TODO: This isn't correct
  // Data either goes in high or low byte
  psram_wram_addr[0] ? {WRAM_D, 8'h0} : {8'h0, WRAM_D};
  wire [15:0] wram_data_out;

  assign WRAM_Q = psram_wram_addr[0] ? wram_data_out[15:8] : wram_data_out[7:0];

  psram #(
      .CLOCK_SPEED(85.9)
  ) wram (
      .clk(clk_mem_85_9),

      .bank_sel(0),
      // Remove bottom most bit, since this is a 8bit address and the RAM wants a 16bit address
      .addr(psram_wram_addr[16:1]),

      .write_en(clearing_ram ? 1'b1 : ~WRAM_CE_N & ~WRAM_WE_N),
      .data_in(wram_data_in),
      .write_high_byte(psram_wram_addr[0]),
      .write_low_byte(~psram_wram_addr[0]),

      .read_en (clearing_ram ? 1'b0 : ~WRAM_CE_N & ~WRAM_OE_N),
      .data_out(wram_data_out),

      // Actual PSRAM interface
      .cram_a(cram0_a),
      .cram_dq(cram0_dq),
      .cram_wait(cram0_wait),
      .cram_clk(cram0_clk),
      .cram_adv_n(cram0_adv_n),
      .cram_cre(cram0_cre),
      .cram_ce0_n(cram0_ce0_n),
      .cram_ce1_n(cram0_ce1_n),
      .cram_oe_n(cram0_oe_n),
      .cram_we_n(cram0_we_n),
      .cram_ub_n(cram0_ub_n),
      .cram_lb_n(cram0_lb_n)
  );

  wire [15:0] VRAM1_ADDR;
  wire        VRAM1_WE_N;
  wire [7:0] VRAM1_D, VRAM1_Q;
  dpram #(15) vram1 (
      .clock(clk_sys),
      .address_a(VRAM1_ADDR[14:0]),
      .data_a(VRAM1_D),
      .wren_a(~VRAM1_WE_N),
      .q_a(VRAM1_Q),

      // clear the RAM on loading
      .address_b(mem_fill_addr[14:0]),
      .wren_b(clearing_ram)
  );

  wire [15:0] VRAM2_ADDR;
  wire        VRAM2_WE_N;
  wire [7:0] VRAM2_D, VRAM2_Q;
  dpram #(15) vram2 (
      .clock(clk_sys),
      .address_a(VRAM2_ADDR[14:0]),
      .data_a(VRAM2_D),
      .wren_a(~VRAM2_WE_N),
      .q_a(VRAM2_Q),

      // clear the RAM on loading
      .address_b(mem_fill_addr[14:0]),
      .wren_b(clearing_ram)
  );

  wire [15:0] ARAM_ADDR;
  wire        ARAM_CE_N;
  wire        ARAM_OE_N;
  wire        ARAM_WE_N;
  wire [7:0] ARAM_Q, ARAM_D;

  wire [15:0] aram_16_out;

  assign ARAM_Q = psram_aram_addr[0] ? aram_16_out[15:8] : aram_16_out[7:0];

  wire [15:0] psram_aram_addr = clearing_ram ? mem_fill_addr[15:0] : ARAM_ADDR;

  wire [ 7:0] aram_data = clearing_ram ? aram_fill_data : ARAM_D;
  wire [15:0] aram_16_data = psram_aram_addr[0] ? {aram_data, 8'h0} : {8'h0, aram_data};

  psram #(
      .CLOCK_SPEED(85.9)
  ) aram (
      .clk(clk_mem_85_9),

      .bank_sel(0),
      // Remove bottom most bit, since this is a 8bit address and the RAM wants a 16bit address
      .addr(psram_aram_addr[15:1]),

      .write_en(clearing_ram ? 1'b1 : ~ARAM_CE_N & ~ARAM_WE_N),
      .data_in(aram_16_data),
      .write_high_byte(psram_aram_addr[0]),
      .write_low_byte(~psram_aram_addr[0]),

      .read_en (~ARAM_CE_N & ~ARAM_OE_N),
      .data_out(aram_16_out),

      // Actual PSRAM interface
      .cram_a(cram1_a),
      .cram_dq(cram1_dq),
      .cram_wait(cram1_wait),
      .cram_clk(cram1_clk),
      .cram_adv_n(cram1_adv_n),
      .cram_cre(cram1_cre),
      .cram_ce0_n(cram1_ce0_n),
      .cram_ce1_n(cram1_ce1_n),
      .cram_oe_n(cram1_oe_n),
      .cram_we_n(cram1_we_n),
      .cram_ub_n(cram1_ub_n),
      .cram_lb_n(cram1_lb_n)
  );

  localparam BSRAM_BITS = 17;  // 1Mbits
  wire [19:0] BSRAM_ADDR;
  wire        BSRAM_CE_N;
  wire        BSRAM_OE_N;
  wire        BSRAM_WE_N;
  wire [7:0] BSRAM_Q, BSRAM_D;
  dpram_dif #(BSRAM_BITS, 8, BSRAM_BITS - 1, 16) bsram (
      .clock(clk_sys),

      //Thrash the BSRAM upon ROM loading
      .address_a(clearing_ram ? mem_fill_addr[BSRAM_BITS-1:0] : BSRAM_ADDR[BSRAM_BITS-1:0]),
      .data_a(clearing_ram ? 8'hFF : BSRAM_D),
      .wren_a(clearing_ram ? 1'b1 : ~BSRAM_CE_N & ~BSRAM_WE_N),
      .q_a(BSRAM_Q),

      // .address_b({sd_lba[BSRAM_BITS-10:0],sd_buff_addr}),
      .address_b(sd_buff_addr),
      .data_b(sd_buff_dout),
      .wren_b(sd_wr),
      // .wren_b(sd_buff_wr & sd_ack),
      .q_b(sd_buff_din)
  );

  ////////////////////////////  I/O PORTS  ////////////////////////////////

  // assign {UART_RTS, UART_DTR} = 1;
  // wire [15:0] uart_data;
  // wire piano_joypad_do;
  // wire piano = status[43];
  // miraclepiano miracle(
  // 	.clk(clk_sys),
  // 	.reset(reset || !piano),
  // 	.strobe(JOY_STRB),
  // 	.joypad_o(piano_joypad_do),
  // 	.joypad_clock(JOY1_CLK),
  // 	.data_o(uart_data),
  // 	.txd(UART_TXD),
  // 	.rxd(UART_RXD)
  // );
  // Trigger r = 9,
  // Trigger l = 8
  // x = 6
  // a = 4
  // right = 0
  // left = 1
  // down = 2
  // up = 3
  // start = 11
  // select = 10
  // y = 7
  // b = 5
  wire [11:0] joy0 = {
    p1_button_start,
    p1_button_select,
    p1_button_trig_r,
    p1_button_trig_l,
    p1_button_y,
    p1_button_x,
    p1_button_b,
    p1_button_a,
    p1_dpad_up,
    p1_dpad_down,
    p1_dpad_left,
    p1_dpad_right
  };

  wire [11:0] joy1 = {
    p2_button_start,
    p2_button_select,
    p2_button_trig_r,
    p2_button_trig_l,
    p2_button_y,
    p2_button_x,
    p2_button_b,
    p2_button_a,
    p2_dpad_up,
    p2_dpad_down,
    p2_dpad_left,
    p2_dpad_right
  };

  wire [11:0] joy2 = {
    p3_button_start,
    p3_button_select,
    p3_button_trig_r,
    p3_button_trig_l,
    p3_button_y,
    p3_button_x,
    p3_button_b,
    p3_button_a,
    p3_dpad_up,
    p3_dpad_down,
    p3_dpad_left,
    p3_dpad_right
  };

  wire [11:0] joy3 = {
    p4_button_start,
    p4_button_select,
    p4_button_trig_r,
    p4_button_trig_l,
    p4_button_y,
    p4_button_x,
    p4_button_b,
    p4_button_a,
    p4_dpad_up,
    p4_dpad_down,
    p4_dpad_left,
    p4_dpad_right
  };

  wire [1:0] JOY1_DO = piano ? {1'b1, piano_joypad_do} : JOY1_DO_t;

  wire JOY_STRB;

  wire [1:0] JOY1_DO_t;
  wire JOY1_CLK;
  wire JOY1_P6;
  ioport port1 (
      .CLK(clk_sys),

      .PORT_LATCH(JOY_STRB),
      .PORT_CLK(JOY1_CLK),
      .PORT_P6(JOY1_P6),
      .PORT_DO(JOY1_DO_t),

      .JOYSTICK1(joy_swap ? joy1 : joy0),

      // .MOUSE(ps2_mouse),
      // .MOUSE_EN(mouse_mode[0])
  );

  wire [1:0] JOY2_DO;
  wire       JOY2_CLK;
  wire       JOY2_P6;
  ioport port2 (
      .CLK(clk_sys),

      .MULTITAP(multitap_enabled),

      .PORT_LATCH(JOY_STRB),
      .PORT_CLK(JOY2_CLK),
      .PORT_P6(JOY2_P6),
      .PORT_DO(JOY2_DO),

      .JOYSTICK1((joy_swap ^ raw_serial) ? joy0 : joy1),
      .JOYSTICK2(joy2),
      .JOYSTICK3(joy3),
      // .JOYSTICK4(joy4),

      // .MOUSE(ps2_mouse),
      // .MOUSE_EN(mouse_mode[1])
  );

  wire LG_P6_out;
  wire [1:0] LG_DO;
  wire [2:0] LG_TARGET;

  lightgun lightgun (
      .CLK  (clk_sys),
      .RESET(reset),

      .JOY_X(p1_lstick_x),
      .JOY_Y(p1_lstick_y),

      .F(p1_button_a),
      .C(p1_button_b),
      .T(p1_button_x),
      .P(p1_button_y),

      .UP(p1_dpad_up),
      .DOWN(p1_dpad_down),
      .LEFT(p1_dpad_left),
      .RIGHT(p1_dpad_right),
      .DPAD_AIM_SPEED(lightgun_dpad_aim_speed),

      .HDE(hblank_n),
      .VDE(vblank_n),
      .CLKPIX(dotclk),

      .TARGET(LG_TARGET),
      .SIZE(0),
      .GUN_TYPE(lightgun_type),

      .PORT_LATCH(JOY_STRB),
      .PORT_CLK(JOY2_CLK),
      .PORT_P6(LG_P6_out),
      .PORT_DO(LG_DO)
  );

  // 1 [oooo|ooo) 7 - 1:+5V  2:Clk  3:Strobe   4:D0  5:D1  6: I/O  7:Gnd

  // Indexes:
  // IDXDIR   Function    USBPIN
  // 0  OUT   Strobe      D+
  // 1  OUT   Clk (P1)    D-
  // 2  IN    D1          TX-
  // 3  OUT   CLK (P2)    GND_d
  // 4  BI    I/O         RX+
  // 5  IN    P1D0        RX-
  // 6  IN    P2D0        TX+

  wire raw_serial = status[8];
  reg                          snac_p2 = 0;

  assign USER_OUT[2] = 1'b1;
  assign USER_OUT[5] = 1'b1;
  assign USER_OUT[6] = 1'b1;

  wire [1:0] datajoy0_DI = snac_p2 ? {1'b1, USER_IN[6]} : JOY1_DO;
  wire [1:0] datajoy1_DI = snac_p2 ? {USER_IN[2], USER_IN[6]} : JOY2_DO;

  // JOYX_DO[0] is P4, JOYX_DO[1] is P5
  wire [1:0] JOY1_DI;
  wire [1:0] JOY2_DI;
  wire JOY2_P6_DI;

  always @(posedge clk_sys) begin
    if (raw_serial) begin
      if (~USER_IN[6]) snac_p2 <= 1;
    end else begin
      snac_p2 <= 0;
    end
  end

  always_comb begin
    if (raw_serial) begin
      USER_OUT[0] = JOY_STRB;
      USER_OUT[1] = joy_swap ? ~JOY2_CLK : ~JOY1_CLK;
      USER_OUT[3] = joy_swap ? ~JOY1_CLK : ~JOY2_CLK;
      USER_OUT[4] = joy_swap ? JOY2_P6 : snac_p2 ? JOY2_P6 : JOY1_P6;
      JOY1_DI = joy_swap ? datajoy0_DI : snac_p2 ? {1'b1, USER_IN[5]} : {USER_IN[2], USER_IN[5]};
      JOY2_DI = joy_swap ? {USER_IN[2], USER_IN[5]} : datajoy1_DI;
      JOY2_P6_DI = joy_swap ? USER_IN[4] : snac_p2 ? USER_IN[4] : (LG_P6_out | !GUN_MODE);
    end else begin
      USER_OUT[0] = 1'b1;
      USER_OUT[1] = 1'b1;
      USER_OUT[3] = 1'b1;
      USER_OUT[4] = 1'b1;
      JOY1_DI = JOY1_DO;
      JOY2_DI = JOY2_DO;
      JOY2_P6_DI = (LG_P6_out | !GUN_MODE);
    end
  end

  /////////////////////////  STATE SAVE/LOAD  /////////////////////////////

  // wire bk_save_write = ~BSRAM_CE_N & ~BSRAM_WE_N;
  // reg bk_pending;

  // always @(posedge clk_sys) begin
  // 	if (bk_ena && ~OSD_STATUS && bk_save_write)
  // 		bk_pending <= 1'b1;
  // 	else if (bk_state | ~bk_ena)
  // 		bk_pending <= 1'b0;
  // end

  reg bk_ena = 0;
  reg old_downloading = 0;
  always @(posedge clk_sys) begin
    old_downloading <= cart_download;
    if (~old_downloading & cart_download) bk_ena <= 0;

    //Save file always mounted in the end of downloading state.
    // if(cart_download && img_mounted && !img_readonly) bk_ena <= |ram_mask; // TODO
  end

  // wire bk_load    = status[12];
  // wire bk_save    = status[13] | (bk_pending & OSD_STATUS && status[23]);
  reg bk_loading = 0;
  reg bk_state = 0;

  // always @(posedge clk_sys) begin
  // 	reg old_load = 0, old_save = 0, old_ack;

  // 	old_load <= bk_load & bk_ena;
  // 	old_save <= bk_save & bk_ena;
  // 	old_ack  <= sd_ack;

  // 	if(~old_ack & sd_ack) {sd_rd, sd_wr} <= 0;

  // 	if(!bk_state) begin
  // 		if((~old_load & bk_load) | (~old_save & bk_save)) begin
  // 			bk_state <= 1;
  // 			bk_loading <= bk_load;
  // 			sd_lba <= 0;
  // 			sd_rd <=  bk_load;
  // 			sd_wr <= ~bk_load;
  // 		end
  // 		if(old_downloading & ~cart_download & |img_size & bk_ena) begin
  // 			bk_state <= 1;
  // 			bk_loading <= 1;
  // 			sd_lba <= 0;
  // 			sd_rd <= 1;
  // 			sd_wr <= 0;
  // 		end
  // 	end else begin
  // 		if(old_ack & ~sd_ack) begin
  // 			if(sd_lba >= ram_mask[23:9]) begin
  // 				bk_loading <= 0;
  // 				bk_state <= 0;
  // 			end else begin
  // 				sd_lba <= sd_lba + 1'd1;
  // 				sd_rd  <=  bk_loading;
  // 				sd_wr  <= ~bk_loading;
  // 			end
  // 		end
  // 	end
  // end

  ///////////////////////////  MSU1  ///////////////////////////////////

  // wire msu_enable;
  // wire msu_audio_download = ioctl_download & ioctl_index[5:0] == 6'h02;
  // wire msu_data_download  = ioctl_download & ioctl_index[5:0] == 6'h03;
  wire msu_data_download = 0;

  // // EXT bus is used to communicate with the HPS for MSU functionality
  // wire [35:0] EXT_BUS;
  // hps_ext hps_ext
  // (
  // 	.reset(reset),
  // 	.clk_sys(clk_sys),
  // 	.EXT_BUS(EXT_BUS),

  // 	.msu_enable(msu_enable),

  // 	.msu_track_mounting(msu_track_mounting),
  // 	.msu_track_missing(msu_track_missing),
  // 	.msu_track_num(msu_track_num),
  // 	.msu_track_request(msu_track_request),

  // 	.msu_audio_size(msu_audio_size),
  // 	.msu_audio_ack(msu_audio_ack),
  // 	.msu_audio_req(msu_audio_req),
  // 	.msu_audio_seek(msu_audio_seek),
  // 	.msu_audio_sector(msu_audio_sector),
  // 	.msu_audio_download(msu_audio_download),

  // 	.msu_data_base(msu_data_base)
  // );

  // wire        msu_track_mounting;
  // wire        msu_track_missing;
  // wire [15:0] msu_track_num;
  // wire        msu_track_request;
  // wire [31:0] msu_audio_size;

  // wire  [7:0] msu_volume;
  // wire        msu_audio_repeat;
  // wire        msu_audio_playing;
  // wire        msu_audio_stop;

  // wire        msu_audio_ack;
  // wire        msu_audio_req;
  // wire        msu_audio_seek;
  // wire [21:0] msu_audio_sector;

  // wire [15:0] msu_l;
  // wire [15:0] msu_r;

  // msu_audio msu_audio
  // (
  // 	.reset(reset),

  // 	.clk(clk_sys),
  // 	.clk_rate(PAL ? 21281370 : 21477270),

  // 	.ctl_volume(msu_volume),
  // 	.ctl_stop(msu_audio_stop),
  // 	.ctl_play(msu_audio_playing),
  // 	.ctl_repeat(msu_audio_repeat),

  // 	.track_size(msu_audio_size),
  // 	.track_processing(msu_track_missing | msu_track_mounting | msu_track_request),

  // 	.audio_download(msu_audio_download),
  // 	.audio_data(ioctl_dout),
  // 	.audio_data_wr(ioctl_wr),

  // 	.audio_ack(msu_audio_ack),
  // 	.audio_sector(msu_audio_sector),
  // 	.audio_req(msu_audio_req),
  // 	.audio_seek(msu_audio_seek),

  // 	.audio_l(msu_l),
  // 	.audio_r(msu_r)
  // );

  // reg [15:0] audio_l, audio_r;

  // always @(posedge clk_sys) begin
  // 	reg [16:0] mix_l, mix_r;

  // 	mix_l = $signed({main_audio_l[15], main_audio_l}) + $signed({msu_l[15], msu_l});
  // 	mix_r = $signed({main_audio_r[15], main_audio_r}) + $signed({msu_r[15], msu_r});

  // 	audio_l <= (^mix_l[16:15]) ? {mix_l[16], {15{mix_l[15]}}} : mix_l[15:0];
  // 	audio_r <= (^mix_r[16:15]) ? {mix_r[16], {15{mix_r[15]}}} : mix_r[15:0];
  // end

  // wire [31:0] msu_data_addr;
  // wire  [7:0] msu_data;
  // wire        msu_data_ack;
  // wire        msu_data_seek;
  // wire        msu_data_req;
  // wire [31:0] msu_data_base;

  // assign DDRAM_CLK = clk_mem;

  // msu_data_store msu_data_store
  // (
  // 	.*,
  // 	.rd_next(msu_data_req),
  // 	.rd_seek(msu_data_seek),
  // 	.rd_seek_done(msu_data_ack),
  // 	.rd_addr(msu_data_addr),
  // 	.rd_dout(msu_data),
  // 	.base_addr(msu_data_base)
  // );

endmodule
