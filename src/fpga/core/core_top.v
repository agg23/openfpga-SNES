//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//

`default_nettype none

module core_top (

    //
    // physical connections
    //

    ///////////////////////////////////////////////////
    // clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

    input wire clk_74a,  // mainclk1
    input wire clk_74b,  // mainclk1 

    ///////////////////////////////////////////////////
    // cartridge interface
    // switches between 3.3v and 5v mechanically
    // output enable for multibit translators controlled by pic32

    // GBA AD[15:8]
    inout  wire [7:0] cart_tran_bank2,
    output wire       cart_tran_bank2_dir,

    // GBA AD[7:0]
    inout  wire [7:0] cart_tran_bank3,
    output wire       cart_tran_bank3_dir,

    // GBA A[23:16]
    inout  wire [7:0] cart_tran_bank1,
    output wire       cart_tran_bank1_dir,

    // GBA [7] PHI#
    // GBA [6] WR#
    // GBA [5] RD#
    // GBA [4] CS1#/CS#
    //     [3:0] unwired
    inout  wire [7:4] cart_tran_bank0,
    output wire       cart_tran_bank0_dir,

    // GBA CS2#/RES#
    inout  wire cart_tran_pin30,
    output wire cart_tran_pin30_dir,
    // when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
    // the goal is that when unconfigured, the FPGA weak pullups won't interfere.
    // thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
    // and general IO drive this pin.
    output wire cart_pin30_pwroff_reset,

    // GBA IRQ/DRQ
    inout  wire cart_tran_pin31,
    output wire cart_tran_pin31_dir,

    // infrared
    input  wire port_ir_rx,
    output wire port_ir_tx,
    output wire port_ir_rx_disable,

    // GBA link port
    inout  wire port_tran_si,
    output wire port_tran_si_dir,
    inout  wire port_tran_so,
    output wire port_tran_so_dir,
    inout  wire port_tran_sck,
    output wire port_tran_sck_dir,
    inout  wire port_tran_sd,
    output wire port_tran_sd_dir,

    ///////////////////////////////////////////////////
    // cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

    output wire [21:16] cram0_a,
    inout  wire [ 15:0] cram0_dq,
    input  wire         cram0_wait,
    output wire         cram0_clk,
    output wire         cram0_adv_n,
    output wire         cram0_cre,
    output wire         cram0_ce0_n,
    output wire         cram0_ce1_n,
    output wire         cram0_oe_n,
    output wire         cram0_we_n,
    output wire         cram0_ub_n,
    output wire         cram0_lb_n,

    output wire [21:16] cram1_a,
    inout  wire [ 15:0] cram1_dq,
    input  wire         cram1_wait,
    output wire         cram1_clk,
    output wire         cram1_adv_n,
    output wire         cram1_cre,
    output wire         cram1_ce0_n,
    output wire         cram1_ce1_n,
    output wire         cram1_oe_n,
    output wire         cram1_we_n,
    output wire         cram1_ub_n,
    output wire         cram1_lb_n,

    ///////////////////////////////////////////////////
    // sdram, 512mbit 16bit

    output wire [12:0] dram_a,
    output wire [ 1:0] dram_ba,
    inout  wire [15:0] dram_dq,
    output wire [ 1:0] dram_dqm,
    output wire        dram_clk,
    output wire        dram_cke,
    output wire        dram_ras_n,
    output wire        dram_cas_n,
    output wire        dram_we_n,

    ///////////////////////////////////////////////////
    // sram, 1mbit 16bit

    output wire [16:0] sram_a,
    inout  wire [15:0] sram_dq,
    output wire        sram_oe_n,
    output wire        sram_we_n,
    output wire        sram_ub_n,
    output wire        sram_lb_n,

    ///////////////////////////////////////////////////
    // vblank driven by dock for sync in a certain mode

    input wire vblank,

    ///////////////////////////////////////////////////
    // i/o to 6515D breakout usb uart

    output wire dbg_tx,
    input  wire dbg_rx,

    ///////////////////////////////////////////////////
    // i/o pads near jtag connector user can solder to

    output wire user1,
    input  wire user2,

    ///////////////////////////////////////////////////
    // RFU internal i2c bus 

    inout  wire aux_sda,
    output wire aux_scl,

    ///////////////////////////////////////////////////
    // RFU, do not use
    output wire vpll_feed,


    //
    // logical connections
    //

    ///////////////////////////////////////////////////
    // video, audio output to scaler
    output wire [23:0] video_rgb,
    output wire        video_rgb_clock,
    output wire        video_rgb_clock_90,
    output wire        video_de,
    output wire        video_skip,
    output wire        video_vs,
    output wire        video_hs,

    output wire audio_mclk,
    input  wire audio_adc,
    output wire audio_dac,
    output wire audio_lrck,

    ///////////////////////////////////////////////////
    // bridge bus connection
    // synchronous to clk_74a
    output wire        bridge_endian_little,
    input  wire [31:0] bridge_addr,
    input  wire        bridge_rd,
    output reg  [31:0] bridge_rd_data,
    input  wire        bridge_wr,
    input  wire [31:0] bridge_wr_data,

    ///////////////////////////////////////////////////
    // controller data
    // 
    // key bitmap:
    //   [0]    dpad_up
    //   [1]    dpad_down
    //   [2]    dpad_left
    //   [3]    dpad_right
    //   [4]    face_a
    //   [5]    face_b
    //   [6]    face_x
    //   [7]    face_y
    //   [8]    trig_l1
    //   [9]    trig_r1
    //   [10]   trig_l2
    //   [11]   trig_r2
    //   [12]   trig_l3
    //   [13]   trig_r3
    //   [14]   face_select
    //   [15]   face_start
    // joy values - unsigned
    //   [ 7: 0] lstick_x
    //   [15: 8] lstick_y
    //   [23:16] rstick_x
    //   [31:24] rstick_y
    // trigger values - unsigned
    //   [ 7: 0] ltrig
    //   [15: 8] rtrig
    //
    input wire [15:0] cont1_key,
    input wire [15:0] cont2_key,
    input wire [15:0] cont3_key,
    input wire [15:0] cont4_key,
    input wire [31:0] cont1_joy,
    input wire [31:0] cont2_joy,
    input wire [31:0] cont3_joy,
    input wire [31:0] cont4_joy,
    input wire [15:0] cont1_trig,
    input wire [15:0] cont2_trig,
    input wire [15:0] cont3_trig,
    input wire [15:0] cont4_trig

);

  // not using the IR port, so turn off both the LED, and
  // disable the receive circuit to save power
  assign port_ir_tx              = 0;
  assign port_ir_rx_disable      = 1;

  // bridge endianness
  assign bridge_endian_little    = 0;

  // cart is unused, so set all level translators accordingly
  // directions are 0:IN, 1:OUT
  assign cart_tran_bank3         = 8'hzz;  // these pins are not used, make them inputs
  assign cart_tran_bank3_dir     = 1'b0;

  assign cart_tran_bank2         = 8'hzz;  // these pins are not used, make them inputs
  assign cart_tran_bank2_dir     = 1'b0;

  assign cart_tran_bank1         = 8'hzz;  // these pins are not used, make them inputs
  assign cart_tran_bank1_dir     = 1'b0;

  assign cart_tran_bank0         = {1'b0, TXDATA, 1'b0, 1'b0};  // LED and TXD hook up here
  assign cart_tran_bank0_dir     = 1'b1;

  assign cart_tran_pin30         = 1'bz;  // this pin is not used, make it an input
  assign cart_tran_pin30_dir     = 1'b0;
  assign cart_pin30_pwroff_reset = 1'b1;

  assign cart_tran_pin31         = 1'bz;  // this pin is an input
  assign cart_tran_pin31_dir     = 1'b0;  // input

  // UART
  wire TXDATA;  // your UART transmit data hooks up here
  wire RXDATA = cart_tran_pin31;  // your UART RX data shows up here

  // link port is input only
  assign port_tran_so      = 1'bz;
  assign port_tran_so_dir  = 1'b0;  // SO is output only
  assign port_tran_si      = 1'bz;
  assign port_tran_si_dir  = 1'b0;  // SI is input only
  assign port_tran_sck     = 1'bz;
  assign port_tran_sck_dir = 1'b0;  // clock direction can change
  assign port_tran_sd      = 1'bz;
  assign port_tran_sd_dir  = 1'b0;  // SD is input and not used

  // tie off the rest of the pins we are not using
  //   assign cram0_a                 = 'h0;
  //   assign cram0_dq                = {16{1'bZ}};
  //   assign cram0_clk               = 0;
  //   assign cram0_adv_n             = 1;
  //   assign cram0_cre               = 0;
  //   assign cram0_ce0_n             = 1;
  //   assign cram0_ce1_n             = 1;
  //   assign cram0_oe_n              = 1;
  //   assign cram0_we_n              = 1;
  //   assign cram0_ub_n              = 1;
  //   assign cram0_lb_n              = 1;

  //   assign cram1_a                 = 'h0;
  //   assign cram1_dq                = {16{1'bZ}};
  //   assign cram1_clk               = 0;
  //   assign cram1_adv_n             = 1;
  //   assign cram1_cre               = 0;
  //   assign cram1_ce0_n             = 1;
  //   assign cram1_ce1_n             = 1;
  //   assign cram1_oe_n              = 1;
  //   assign cram1_we_n              = 1;
  //   assign cram1_ub_n              = 1;
  //   assign cram1_lb_n              = 1;

  //   assign dram_a                  = 'h0;
  //   assign dram_ba                 = 'h0;
  //   assign dram_dq                 = {16{1'bZ}};
  //   assign dram_dqm                = 'h0;
  //   assign dram_clk                = 'h0;
  //   assign dram_cke                = 'h0;
  //   assign dram_ras_n              = 'h1;
  //   assign dram_cas_n              = 'h1;
  //   assign dram_we_n               = 'h1;

  assign sram_a            = 'h0;
  assign sram_dq           = {16{1'bZ}};
  assign sram_oe_n         = 1;
  assign sram_we_n         = 1;
  assign sram_ub_n         = 1;
  assign sram_lb_n         = 1;

  assign dbg_tx            = 1'bZ;
  assign user1             = 1'bZ;
  assign aux_scl           = 1'bZ;
  assign vpll_feed         = 1'bZ;


  // for bridge write data, we just broadcast it to all bus devices
  // for bridge read data, we have to mux it
  // add your own devices here
  always @(*) begin
    casex (bridge_addr)
      default: begin
        bridge_rd_data <= 0;
      end
      32'h10xxxxxx: begin
        // example
        bridge_rd_data <= 0;
      end
      32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
      end
    endcase

    if (bridge_addr[31:28] == 4'h2) begin
      bridge_rd_data <= sd_read_data;
    end
  end

  always @(posedge clk_74a) begin
    if (bridge_wr) begin
      casex (bridge_addr)
        32'h00000100: begin
          multitap_enabled <= bridge_wr_data[0];
        end
      endcase
    end
  end


  //
  // host/target command handler
  //
  wire reset_n;  // driven by host commands, can be used as core-wide reset
  wire [31:0] cmd_bridge_rd_data;

  // bridge host commands
  // synchronous to clk_74a
  wire status_boot_done = pll_core_locked;
  wire status_setup_done = pll_core_locked;  // rising edge triggers a target command
  wire status_running = reset_n;  // we are running as soon as reset_n goes high

  wire dataslot_requestread;
  wire [15:0] dataslot_requestread_id;
  wire dataslot_requestread_ack = 1;
  wire dataslot_requestread_ok = 1;

  wire dataslot_requestwrite;
  wire [15:0] dataslot_requestwrite_id;
  wire dataslot_requestwrite_ack = 1;
  wire dataslot_requestwrite_ok = 1;

  wire dataslot_allcomplete;

  wire savestate_supported = 0;
  wire [31:0] savestate_addr;
  wire [31:0] savestate_size;
  wire [31:0] savestate_maxloadsize;

  wire savestate_start;
  wire savestate_start_ack;
  wire savestate_start_busy;
  wire savestate_start_ok;
  wire savestate_start_err;

  wire savestate_load;
  wire savestate_load_ack;
  wire savestate_load_busy;
  wire savestate_load_ok;
  wire savestate_load_err;

  wire osnotify_inmenu;

  // bridge target commands
  // synchronous to clk_74a


  // bridge data slot access

  reg [9:0] datatable_addr;
  reg datatable_wren;
  reg [31:0] datatable_data;
  wire [31:0] datatable_q;

  core_bridge_cmd icb (

      .clk    (clk_74a),
      .reset_n(reset_n),

      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_rd           (bridge_rd),
      .bridge_rd_data      (cmd_bridge_rd_data),
      .bridge_wr           (bridge_wr),
      .bridge_wr_data      (bridge_wr_data),

      .status_boot_done (status_boot_done),
      .status_setup_done(status_setup_done),
      .status_running   (status_running),

      .dataslot_requestread    (dataslot_requestread),
      .dataslot_requestread_id (dataslot_requestread_id),
      .dataslot_requestread_ack(dataslot_requestread_ack),
      .dataslot_requestread_ok (dataslot_requestread_ok),

      .dataslot_requestwrite    (dataslot_requestwrite),
      .dataslot_requestwrite_id (dataslot_requestwrite_id),
      .dataslot_requestwrite_ack(dataslot_requestwrite_ack),
      .dataslot_requestwrite_ok (dataslot_requestwrite_ok),

      .dataslot_allcomplete(dataslot_allcomplete),

      .savestate_supported  (savestate_supported),
      .savestate_addr       (savestate_addr),
      .savestate_size       (savestate_size),
      .savestate_maxloadsize(savestate_maxloadsize),

      .savestate_start     (savestate_start),
      .savestate_start_ack (savestate_start_ack),
      .savestate_start_busy(savestate_start_busy),
      .savestate_start_ok  (savestate_start_ok),
      .savestate_start_err (savestate_start_err),

      .savestate_load     (savestate_load),
      .savestate_load_ack (savestate_load_ack),
      .savestate_load_busy(savestate_load_busy),
      .savestate_load_ok  (savestate_load_ok),
      .savestate_load_err (savestate_load_err),

      .osnotify_inmenu(osnotify_inmenu),

      .datatable_addr(datatable_addr),
      .datatable_wren(datatable_wren),
      .datatable_data(datatable_data),
      .datatable_q   (datatable_q),

  );

  reg ioctl_download = 0;
  wire ioctl_wr;
  wire [24:0] ioctl_addr;
  wire [15:0] ioctl_dout;

  reg save_download = 0;
  reg dataslot_allcomplete_prev;

  always @(posedge clk_74a) begin
    dataslot_allcomplete_prev <= dataslot_allcomplete;

    if (dataslot_requestwrite) ioctl_download <= 1;
    else if (dataslot_allcomplete) ioctl_download <= 0;

    if (dataslot_requestread || dataslot_requestwrite) save_download <= 1;
    else if (dataslot_allcomplete && ~dataslot_allcomplete_prev) save_download <= 0;
  end

  wire save_download_s;

  synch_3 save_s (
      save_download,
      save_download_s,
      clk_sys_21_48
  );

  data_loader #(
      .ADDRESS_MASK_UPPER_4(4'h1),
      .ADDRESS_SIZE(25),
      .WRITE_MEM_CLOCK_DELAY(7),
      .OUTPUT_WORD_SIZE(2)
  ) data_loader (
      .clk_74a(clk_74a),
      .clk_memory(clk_sys_21_48),

      .bridge_wr(bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr(bridge_addr),
      .bridge_wr_data(bridge_wr_data),

      .write_en  (ioctl_wr),
      .write_addr(ioctl_addr),
      .write_data(ioctl_dout)
  );

  data_loader #(
      .ADDRESS_MASK_UPPER_4(4'h2),
      .ADDRESS_SIZE(17),
      .WRITE_MEM_CLOCK_DELAY(7),
      .OUTPUT_WORD_SIZE(2)
  ) save_data_loader (
      .clk_74a(clk_74a),
      .clk_memory(clk_sys_21_48),

      .bridge_wr(bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr(bridge_addr),
      .bridge_wr_data(bridge_wr_data),

      .write_en  (sd_wr),
      .write_addr(sd_buff_addr_in),
      .write_data(sd_buff_dout)
  );

  wire [31:0] sd_read_data;

  wire sd_rd;
  wire sd_wr;

  wire [16:0] sd_buff_addr_in;
  wire [16:0] sd_buff_addr_out;

  // Lowest bit is for byte addressing
  wire [15:0] sd_buff_addr = sd_wr ? sd_buff_addr_in[16:1] : sd_buff_addr_out[16:1];

  wire [15:0] sd_buff_din;
  wire [15:0] sd_buff_dout;

  data_unloader #(
      .ADDRESS_MASK_UPPER_4(4'h2),
      .ADDRESS_SIZE(17),
      .READ_MEM_CLOCK_DELAY(7),
      .INPUT_WORD_SIZE(2)
  ) data_unloader (
      .clk_74a(clk_74a),
      .clk_memory(clk_sys_21_48),

      .bridge_rd(bridge_rd),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr(bridge_addr),
      .bridge_rd_data(sd_read_data),

      .read_en  (sd_rd),
      .read_addr(sd_buff_addr_out),
      .read_data(sd_buff_din)
  );

  reg [ 2:0] datatable_div = 0;
  reg [31:0] rom_file_size = 0;

  always @(posedge clk_74a or negedge pll_core_locked) begin
    if (~pll_core_locked) begin
      datatable_addr <= 0;
      datatable_data <= 0;
      datatable_wren <= 0;
    end else begin
      if (datatable_div > 4) begin
        // Write sram size half of the time
        datatable_wren <= 1;
        // sram_size is the size of the config value in the ROM. Convert to actual size
        datatable_data <= sram_size ? 32'd1024 << sram_size : 32'h0;
        // Data slot index 1, not id 1
        datatable_addr <= 1 * 2 + 1;
      end else begin
        datatable_wren <= 0;
        // Read ROM size rest of the time
        datatable_addr <= 1;

        if (datatable_div == 4) begin
          rom_file_size <= datatable_q;
        end
      end

      datatable_div <= datatable_div + 1;
    end
  end

  // UART

  reg write;
  reg write_mem;
  reg [7:0] data;
  reg [1:0] byte_index = 0;
  wire [23:0] DEBUG_PC;
  reg [23:0] prev_debug_pc;

  wire busy;

  wire [23:0] mem_out;

  parameter WORD_COUNT = 16384 * 2;

  spram_sz #(
      .addr_width(15),
      .data_width(24),
      .numwords  (WORD_COUNT)
  ) spram_sz (
      .clock(clk_mem_85_9),
      .address(pc_addr),
      .data(DEBUG_PC),
      .wren(write_mem),
      .q(mem_out)
  );

  // reg [15:0] rom[16383];
  reg [14:0] pc_addr = 0;
  reg finished = 0;
  reg finished_uart = 0;

  // 21.48 / 921600.0
  uart_tx #(24) uart_tx (
      .i_Clock(clk_sys_21_48),
      .i_Tx_DV(write),
      .i_Tx_Byte(data),
      .o_Tx_Active(busy),
      .o_Tx_Serial(TXDATA),
      //   .o_Tx_Done(ready),
  );


  reg read_delay = 0;
  reg [31:0] instruction_delay = 32'h2000;

  // Very simple and dumb (no state machine) way of capturing PC and bank and
  // shoveling it out over UART. Requires 921,600 baud rate
  always @(posedge clk_sys_21_48) begin
    write <= 0;
    write_mem <= 0;

    if (finished) begin
      if (~busy && ~write) begin
        if (pc_addr == WORD_COUNT - 1) begin
          finished_uart <= 1;
        end else if (read_delay) begin
          read_delay <= 0;
        end else if (byte_index == 2) begin
          // Need to write lower byte
          write <= 1;
          data <= mem_out[7:0];

          pc_addr <= pc_addr + 1;
          read_delay <= 1;
          byte_index <= 0;
        end else if (byte_index == 1) begin
          // Need to write middle byte
          write <= 1;
          data <= mem_out[15:8];

          byte_index <= 2;
        end else begin
          // New data
          write <= 1;
          data <= mem_out[23:16];
          byte_index <= 1;
        end
      end
    end else if (pc_addr == WORD_COUNT - 1) begin
      finished <= 1;
      pc_addr <= 0;
      read_delay <= 1;
    end else if (prev_debug_pc != DEBUG_PC) begin
      if (instruction_delay == 0) begin
        write_mem <= 1;

        pc_addr   <= pc_addr + 1;
      end else begin
        instruction_delay <= instruction_delay - 1;
      end

      prev_debug_pc <= DEBUG_PC;
    end
  end

  wire [15:0] audio_l;
  wire [15:0] audio_r;

  wire [ 3:0] sram_size;

  wire [15:0] cont1_key_s;
  wire [15:0] cont2_key_s;
  wire [15:0] cont3_key_s;
  wire [15:0] cont4_key_s;

  synch_3 #(
      .WIDTH(32)
  ) cont1_s (
      cont1_key,
      cont1_key_s,
      clk_sys_21_48
  );

  synch_3 #(
      .WIDTH(32)
  ) cont2_s (
      cont2_key,
      cont2_key_s,
      clk_sys_21_48
  );

  synch_3 #(
      .WIDTH(32)
  ) cont3_s (
      cont3_key,
      cont3_key_s,
      clk_sys_21_48
  );

  synch_3 #(
      .WIDTH(32)
  ) cont4_s (
      cont4_key,
      cont4_key_s,
      clk_sys_21_48
  );

  wire PAL;

  // Settings
  reg  multitap_enabled;

  MAIN_SNES snes (
      .clk_mem_85_9 (clk_mem_85_9),
      .clk_sys_21_48(clk_sys_21_48),

      .core_reset(~pll_core_locked),

      // Settings
      .multitap_enabled(multitap_enabled),

      // Input
      .p1_button_a(cont1_key_s[4]),
      .p1_button_b(cont1_key_s[5]),
      .p1_button_x(cont1_key_s[6]),
      .p1_button_y(cont1_key_s[7]),
      .p1_button_trig_l(cont1_key_s[8]),
      .p1_button_trig_r(cont1_key_s[9]),
      .p1_button_start(cont1_key_s[15]),
      .p1_button_select(cont1_key_s[14]),
      .p1_dpad_up(cont1_key_s[0]),
      .p1_dpad_down(cont1_key_s[1]),
      .p1_dpad_left(cont1_key_s[2]),
      .p1_dpad_right(cont1_key_s[3]),

      .p2_button_a(cont2_key_s[4]),
      .p2_button_b(cont2_key_s[5]),
      .p2_button_x(cont2_key_s[6]),
      .p2_button_y(cont2_key_s[7]),
      .p2_button_trig_l(cont2_key_s[8]),
      .p2_button_trig_r(cont2_key_s[9]),
      .p2_button_start(cont2_key_s[15]),
      .p2_button_select(cont2_key_s[14]),
      .p2_dpad_up(cont2_key_s[0]),
      .p2_dpad_down(cont2_key_s[1]),
      .p2_dpad_left(cont2_key_s[2]),
      .p2_dpad_right(cont2_key_s[3]),

      .p3_button_a(cont3_key_s[4]),
      .p3_button_b(cont3_key_s[5]),
      .p3_button_x(cont3_key_s[6]),
      .p3_button_y(cont3_key_s[7]),
      .p3_button_trig_l(cont3_key_s[8]),
      .p3_button_trig_r(cont3_key_s[9]),
      .p3_button_start(cont3_key_s[15]),
      .p3_button_select(cont3_key_s[14]),
      .p3_dpad_up(cont3_key_s[0]),
      .p3_dpad_down(cont3_key_s[1]),
      .p3_dpad_left(cont3_key_s[2]),
      .p3_dpad_right(cont3_key_s[3]),

      .p4_button_a(cont4_key_s[4]),
      .p4_button_b(cont4_key_s[5]),
      .p4_button_x(cont4_key_s[6]),
      .p4_button_y(cont4_key_s[7]),
      .p4_button_trig_l(cont4_key_s[8]),
      .p4_button_trig_r(cont4_key_s[9]),
      .p4_button_start(cont4_key_s[15]),
      .p4_button_select(cont4_key_s[14]),
      .p4_dpad_up(cont4_key_s[0]),
      .p4_dpad_down(cont4_key_s[1]),
      .p4_dpad_left(cont4_key_s[2]),
      .p4_dpad_right(cont4_key_s[3]),

      // ROM loading
      .rom_file_size(rom_file_size),
      .ioctl_download(ioctl_download),
      .ioctl_wr(ioctl_wr),
      .ioctl_addr(ioctl_addr),
      .ioctl_dout(ioctl_dout),

      // Save input/output
      .save_download(save_download_s),
      .sd_rd(sd_rd),
      .sd_wr(sd_wr),
      .sd_buff_addr(sd_buff_addr),
      .sd_buff_din(sd_buff_din),
      .sd_buff_dout(sd_buff_dout),

      .sram_size(sram_size),

      // SDRAM
      .dram_a(dram_a),
      .dram_ba(dram_ba),
      .dram_dq(dram_dq),
      .dram_dqm(dram_dqm),
      .dram_clk(dram_clk),
      .dram_cke(dram_cke),
      .dram_ras_n(dram_ras_n),
      .dram_cas_n(dram_cas_n),
      .dram_we_n(dram_we_n),

      // PSRAM
      .cram0_a(cram0_a),
      .cram0_dq(cram0_dq),
      .cram0_wait(cram0_wait),
      .cram0_clk(cram0_clk),
      .cram0_adv_n(cram0_adv_n),
      .cram0_cre(cram0_cre),
      .cram0_ce0_n(cram0_ce0_n),
      .cram0_ce1_n(cram0_ce1_n),
      .cram0_oe_n(cram0_oe_n),
      .cram0_we_n(cram0_we_n),
      .cram0_ub_n(cram0_ub_n),
      .cram0_lb_n(cram0_lb_n),

      .cram1_a(cram1_a),
      .cram1_dq(cram1_dq),
      .cram1_wait(cram1_wait),
      .cram1_clk(cram1_clk),
      .cram1_adv_n(cram1_adv_n),
      .cram1_cre(cram1_cre),
      .cram1_ce0_n(cram1_ce0_n),
      .cram1_ce1_n(cram1_ce1_n),
      .cram1_oe_n(cram1_oe_n),
      .cram1_we_n(cram1_we_n),
      .cram1_ub_n(cram1_ub_n),
      .cram1_lb_n(cram1_lb_n),

      // Video
      .hblank (h_blank),
      .vblank (v_blank),
      .hsync  (video_hs_snes),
      .vsync  (video_vs_snes),
      .video_r(video_rgb_snes[23:16]),
      .video_g(video_rgb_snes[15:8]),
      .video_b(video_rgb_snes[7:0]),

      .PAL(PAL),

      // Audio
      .audio_l(audio_l),
      .audio_r(audio_r),

      .DEBUG_PC(DEBUG_PC)
  );

  // Video

  wire h_blank;
  wire v_blank;
  wire video_hs_snes;
  wire video_vs_snes;
  wire [23:0] video_rgb_snes;

  reg video_de_reg;
  reg video_hs_reg;
  reg video_vs_reg;
  reg [23:0] video_rgb_reg;

  assign video_rgb_clock = clk_video_5_37;
  assign video_rgb_clock_90 = clk_video_5_37_90deg;
  assign video_de = video_de_reg;
  assign video_hs = video_hs_reg;
  assign video_vs = video_vs_reg;
  assign video_rgb = video_rgb_reg;

  reg hs_prev;
  reg [2:0] hs_delay;
  reg vs_prev;

  always @(posedge clk_video_5_37) begin
    video_hs_reg  <= 0;
    video_de_reg  <= 0;
    video_rgb_reg <= 24'h0;

    if (~(h_blank || v_blank)) begin
      video_de_reg  <= 1;

      video_rgb_reg <= video_rgb_snes;
    end

    // Set VSync to be high for a single cycle on the rising edge of the VSync coming out of the core
    video_hs_reg <= ~hs_prev && video_hs_snes;
    video_vs_reg <= ~vs_prev && video_vs_snes;
    hs_prev <= video_hs_snes;
    vs_prev <= video_vs_snes;
  end

  sound_i2s #(
      .CHANNEL_WIDTH(16),
      .SIGNED_INPUT (1)
  ) sound_i2s (
      .clk_74a  (clk_74a),
      .clk_audio(clk_sys_21_48),

      .audio_l(audio_l),
      .audio_r(audio_r),

      .audio_mclk(audio_mclk),
      .audio_lrck(audio_lrck),
      .audio_dac (audio_dac)
  );

  ///////////////////////////////////////////////

  wire clk_mem_85_9;
  wire clk_sys_21_48;
  wire clk_video_5_37;
  wire clk_video_5_37_90deg;

  wire pll_core_locked;

  mf_pllbase mp1 (
      .refclk(clk_74a),
      .rst   (0),

      .outclk_0(clk_mem_85_9),
      .outclk_1(clk_sys_21_48),
      .outclk_2(clk_video_5_37),
      .outclk_3(clk_video_5_37_90deg),

      .locked(pll_core_locked)
  );

endmodule
