// (C) 2001-2022 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files from any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel FPGA IP License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.


`timescale 1ps/1ps

module altera_pll_reconfig_mif_reader  
#(
    parameter   RECONFIG_ADDR_WIDTH     = 6,
    parameter   RECONFIG_DATA_WIDTH     = 32,

    parameter   MIF_ADDR_WIDTH          = 6,

    parameter   ROM_ADDR_WIDTH          = 9,    // 512 words x
    parameter   ROM_DATA_WIDTH          = 32,   // 32 bits per word = 20kB
    parameter	 ROM_NUM_WORDS           = 512, 	// Default 512 32-bit words = 1 M20K 

    parameter   DEVICE_FAMILY           = "Stratix V",
    parameter   ENABLE_MIF              = 0,    
    parameter   MIF_FILE_NAME           = ""
) (

    // Inputs
    input   wire    mif_clk,
    input   wire    mif_rst,

    // Reconfig Module interface for internal register mapping
    input   wire                            reconfig_busy,          // waitrequest
    input   wire [RECONFIG_DATA_WIDTH-1:0]   reconfig_read_data, 
    output  reg [RECONFIG_DATA_WIDTH-1:0]   reconfig_write_data, 
    output  reg [RECONFIG_ADDR_WIDTH-1:0]   reconfig_addr,
    output  reg                             reconfig_write,
    output  reg                             reconfig_read,

    // MIF Controller Interface
    input   wire [ROM_ADDR_WIDTH-1:0]       mif_base_addr,
    input   wire                            mif_start,
    output  wire                            mif_busy

);
        
// NOTE: Assumes settings opcodes/registers are continguous and OP_MODE is 0

// ROM Interface ctlr states
localparam  NUM_STATES              = 5;
localparam  STATE_REG_WIDTH         = 32;
localparam  MIF_IDLE                = 32'd0;
localparam  SET_INSTR_ADDR          = 32'd1;
localparam  FETCH_INSTR             = 32'd2;
localparam  WAIT_FOR_ROM_INSTR      = 32'd3;
localparam  STORE_INSTR             = 32'd4;
localparam  DECODE_ROM_INSTR        = 32'd5;
localparam  SET_DATA_ADDR           = 32'd6;
localparam  SET_DATA_ADDR_DLY       = 32'd34;
localparam  FETCH_DATA              = 32'd7;
localparam  WAIT_FOR_ROM_DATA       = 32'd8;
localparam  STORE_DATA              = 32'd9;
localparam  SET_INDEX               = 32'd35;
localparam  CHANGE_SETTINGS_REG     = 32'd10;
localparam  SET_MODE_REG_INFO       = 32'd11;
localparam  WAIT_MODE_REG           = 32'd12;
localparam  SAVE_MODE_REG           = 32'd13;
localparam  SET_WR_MODE             = 32'd14;
localparam  WAIT_WRITE_MODE         = 32'd15;
localparam  INIT_RECONFIG_PARAMS    = 32'd16;
localparam  CHECK_RECONFIG_SETTING  = 32'd17;
localparam  WRITE_RECONFIG_SETTING  = 32'd18;
localparam  DECREMENT_SETTING_NUM   = 32'd19;
localparam  CHECK_C_SETTINGS        = 32'd20;
localparam  WRITE_C_SETTINGS        = 32'd21;
localparam  DECREMENT_C_NUM         = 32'd22;
localparam  CHECK_DPS_SETTINGS      = 32'd23;
localparam  WRITE_DPS_SETTINGS      = 32'd24;
localparam  DECREMENT_DPS_NUM       = 32'd25;
localparam  START_RECONFIG_CHANGE   = 32'd26;
localparam  START_RECONFIG_DELAY    = 32'd27;
localparam  START_RECONFIG_DELAY2   = 32'd28;
localparam  WAIT_DONE_SIGNAL        = 32'd29;
localparam  SET_MODE_REG            = 32'd30;
localparam  WRITE_FINAL_MODE        = 32'd31;
localparam  WAIT_FINAL_MODE         = 32'd32;
localparam  MIF_STREAMING_DONE      = 32'd33;


// MIF Opcodes
// Addresses for settings from PLL Reconfig module
localparam OP_MODE           = 6'b000000;
localparam OP_STATUS         = 6'b000001;  // Read only
localparam OP_START          = 6'b000010;  
localparam OP_N              = 6'b000011;
localparam OP_M              = 6'b000100;
localparam OP_C_COUNTERS     = 6'b000101;
localparam OP_DPS            = 6'b000110;
localparam OP_DSM            = 6'b000111;
localparam OP_BWCTRL         = 6'b001000;
localparam OP_CP_CURRENT     = 6'b001001;

localparam OP_SOM            = 6'b111110;   
localparam OP_EOM            = 6'b111111;   

localparam INVAL_SETTING     = 6'b111100;

localparam MODE_WR            = 1'b0;
localparam MODE_POLL          = 1'b1;

// Total MIF changeable settings = 8
// + Total non-MIF changeable settings = 2 (status, start)
// + StartOfMif, EndOfMif, Invalid = 3
// = 13 total settings
localparam  NUM_SETTINGS        = 6'd13;
localparam	NUM_MIF_SETTINGS	  = 6'd10;    // Mode = 0.. CP_Current=9
localparam  LOG2NUM_SETTINGS    = 6;        // Consistent with Reconfig addr width        
localparam  NUM_C_COUNTERS      = 5'd18;
localparam  LOG2NUM_C_COUNTERS  = 3'd5;
localparam  NUM_DPS_COUNTERS    = 6'd32;   
localparam  LOG2NUM_DPS_COUNTERS = 3'd6;

// Reconfig Module parameters
localparam WAITREQUEST_MODE     = 1'b1;

// Control flow registers
reg [STATE_REG_WIDTH-1:0]       mif_curstate;
reg [STATE_REG_WIDTH-1:0]       mif_nextstate;
wire                            is_done;

// Internal data registers
reg [ROM_ADDR_WIDTH-1:0]        reg_mif_base_addr;
reg [LOG2NUM_SETTINGS-1:0]      reg_instr;
reg [RECONFIG_DATA_WIDTH-1:0]   reg_data;
reg [RECONFIG_DATA_WIDTH-1:0]   settings_reg [NUM_MIF_SETTINGS-1:0];
reg [RECONFIG_DATA_WIDTH-1:0]   c_settings_reg [NUM_C_COUNTERS-1:0];
reg [RECONFIG_DATA_WIDTH-1:0]   dps_settings_reg [NUM_DPS_COUNTERS-1:0];
reg [4:0]                       c_cntr_index;   // C cntr is data[22:18];
reg [4:0]                       dps_index;      // DPS is data[20:16];

reg [NUM_SETTINGS-1:0]          is_setting_changed; // 1 bit per setting 
reg [NUM_C_COUNTERS-1:0]        is_c_cntr_changed;
reg [NUM_DPS_COUNTERS-1:0]      is_dps_changed;

reg                             user_mode_setting;  // 0 for waitrequest mode, 1 for polling
reg                             mif_started;
reg                             saved_mode;         
reg                             mode_reg;           
reg [RECONFIG_ADDR_WIDTH-1:0]   setting_number;     
reg [LOG2NUM_C_COUNTERS-1:0]    c_cntr_number;       
reg [LOG2NUM_DPS_COUNTERS-1:0]  dps_number;    
reg                             c_done;
reg                             dps_done;
reg                             is_mode_changed;

// ROM Interface
wire [ROM_DATA_WIDTH-1:0]       rom_q;     
reg [ROM_ADDR_WIDTH-1:0]       rom_addr;

assign mif_busy = (is_done) ? 1'b0 : 1'b1;

// mif_started register
always @(posedge mif_clk)
begin
    if (mif_curstate == MIF_IDLE)
        mif_started <= 0;
    else if (reg_instr == OP_SOM && mif_curstate == DECODE_ROM_INSTR) 
        mif_started <= 1;
    else
        mif_started <= mif_started;
end

// is_done logic
assign is_done = (mif_curstate == MIF_IDLE && mif_nextstate == MIF_IDLE) ? 1'b1 : 1'b0;

// State register
always @(posedge mif_clk)
begin
    if (mif_rst)
        mif_curstate <= MIF_IDLE;
    else 
        mif_curstate <= mif_nextstate;
end

// Next state logic
always @(*)
begin
    case (mif_curstate)
        MIF_IDLE:
        begin
            if (mif_start)
                mif_nextstate = SET_INSTR_ADDR;
            else
                mif_nextstate = MIF_IDLE;
        end
        
        // Set address for instruction to be fetched from ROM
        SET_INSTR_ADDR: // SET_ROM_INFO
        begin
            mif_nextstate = FETCH_INSTR;
        end

        FETCH_INSTR:
        begin
            mif_nextstate = WAIT_FOR_ROM_INSTR; 
        end
        
        WAIT_FOR_ROM_INSTR: 
        begin
            mif_nextstate = STORE_INSTR;
        end
        
        STORE_INSTR:
        begin
            mif_nextstate = DECODE_ROM_INSTR;
        end

        DECODE_ROM_INSTR:
        begin
            if (reg_instr == OP_SOM)
                mif_nextstate = SET_INSTR_ADDR;
            else if (reg_instr == OP_EOM)
                mif_nextstate = SET_MODE_REG_INFO;  // Done reading MIF, send it to reconfig module
            else
                mif_nextstate = SET_DATA_ADDR;
        end

        SET_DATA_ADDR:
        begin
            mif_nextstate = SET_DATA_ADDR_DLY;
        end

        SET_DATA_ADDR_DLY:
        begin
            mif_nextstate = FETCH_DATA;
        end

        FETCH_DATA:
        begin
            mif_nextstate = WAIT_FOR_ROM_DATA; 
        end

        WAIT_FOR_ROM_DATA:
        begin
            mif_nextstate = STORE_DATA;
        end
        
        STORE_DATA:
        begin
            mif_nextstate = SET_INDEX;
        end
        
        SET_INDEX:
        begin
            mif_nextstate = CHANGE_SETTINGS_REG;
        end

        CHANGE_SETTINGS_REG:
        begin
            mif_nextstate = SET_INSTR_ADDR;    // Loop back to read rest of MIF file
        end

        // --- CHANGE RECONFIG REGISTERS --- //
        // GENERAL STEPS FOR MANAGING WITH RECONFIG MODULE:
        // 1) Save user's configured mode register,
        // 2) Change mode to waitrequest mode,
        // 3) Send all settings that have changed to
        // 4) Start reconfig
        // 5) Wait till PLL has locked again.
        // 6) Restore user's mode register
        SET_MODE_REG_INFO:        
        begin
            mif_nextstate = WAIT_MODE_REG;
        end
        
        WAIT_MODE_REG:
        begin
            mif_nextstate = SAVE_MODE_REG;
        end
        
        SAVE_MODE_REG:
        begin
            mif_nextstate = SET_WR_MODE;
        end

        SET_WR_MODE:
        begin
            mif_nextstate = WAIT_WRITE_MODE;
        end

        WAIT_WRITE_MODE:
        begin
            mif_nextstate = INIT_RECONFIG_PARAMS;
        end

        INIT_RECONFIG_PARAMS:
        begin
            mif_nextstate = CHECK_RECONFIG_SETTING;
        end

        // PARENT LOOP (writing to reconfig)
        CHECK_RECONFIG_SETTING: // Loop over changed settings until setting_num = 0 = MODE
        begin
            // Don't write the user's mode reg just yet
            // Stay in WR mode till we're done with reconfig IP
            // then restore the user's old mode/the new mode
            // they wrote in the MIF
            if (setting_number == 6'b0)
                mif_nextstate = START_RECONFIG_CHANGE;
            else 
            begin
                if(is_setting_changed[setting_number])
                    // C and DPS settings are different,
                    // since multiple can be reconfigured in
                    // one MIF. If they are changed, check them all.
                    // In their respective loops
                    if (setting_number == OP_C_COUNTERS)
                    begin
                        mif_nextstate = DECREMENT_C_NUM;
                    end
                    else if (setting_number == OP_DPS)
                    begin
                        mif_nextstate = DECREMENT_DPS_NUM;
                    end
                    else
                    begin
                        mif_nextstate = WRITE_RECONFIG_SETTING;
                    end
                else
                    mif_nextstate = DECREMENT_SETTING_NUM;  
            end
        end

        // C LOOP
        // We need to check the 0th setting always (unlike the parent loop) so decrement first.
        DECREMENT_C_NUM:
        begin
            if (c_done)
            begin
                // Done checking and writing C counters
                // check next setting in parent loop
                mif_nextstate = DECREMENT_SETTING_NUM;
            end
            else
                mif_nextstate = CHECK_C_SETTINGS;
        end
        
        CHECK_C_SETTINGS:
        begin
            if (is_c_cntr_changed[c_cntr_number])
                mif_nextstate = WRITE_C_SETTINGS;
            else
                mif_nextstate = DECREMENT_C_NUM;
        end

        WRITE_C_SETTINGS:
        begin
            mif_nextstate = DECREMENT_C_NUM;
        end
        //End C Loop

        // DPS LOOP
        // Same as C loop, decrement first.
        DECREMENT_DPS_NUM:
        begin
            if (dps_done)
            begin
                // Done checking and writing DPS counters
                // check next setting in parent loop
                mif_nextstate = DECREMENT_SETTING_NUM;
            end
            else
                mif_nextstate = CHECK_DPS_SETTINGS;   // Check next DPS setting
        end

        CHECK_DPS_SETTINGS:
        begin
            if(is_dps_changed[dps_number])
                mif_nextstate = WRITE_DPS_SETTINGS;
            else
                mif_nextstate = DECREMENT_DPS_NUM;
        end

        WRITE_DPS_SETTINGS:
        begin
            mif_nextstate = DECREMENT_DPS_NUM;
        end
        //End DPS Loop


        WRITE_RECONFIG_SETTING:
        begin
            mif_nextstate = DECREMENT_SETTING_NUM;
        end

        DECREMENT_SETTING_NUM:  
        begin
            mif_nextstate = CHECK_RECONFIG_SETTING; // Loop back
        end

        // --- DONE CHANGING SETTINGS, START RECONFIG --- //
        
        START_RECONFIG_CHANGE:
        begin
            mif_nextstate = START_RECONFIG_DELAY;
        end
        
		  START_RECONFIG_DELAY:
		  begin
            mif_nextstate = START_RECONFIG_DELAY2;
        end
		  
		  START_RECONFIG_DELAY2:	// register at top level before we mux into reconfig
		  begin
            mif_nextstate = WAIT_DONE_SIGNAL;
        end
		  
        WAIT_DONE_SIGNAL:
        begin
            if (reconfig_busy)
                mif_nextstate = WAIT_DONE_SIGNAL;
            else
                mif_nextstate = SET_MODE_REG;
        end

        SET_MODE_REG:
        begin
            mif_nextstate = WRITE_FINAL_MODE;
        end
        
        WRITE_FINAL_MODE:
        begin
            mif_nextstate = WAIT_FINAL_MODE;
        end

        WAIT_FINAL_MODE:
        begin
            mif_nextstate = MIF_STREAMING_DONE;
			end
			
        MIF_STREAMING_DONE:
        begin
            mif_nextstate = MIF_IDLE;
        end
 
        default:
        begin
            mif_nextstate = MIF_IDLE;
        end 
	endcase
end

// Data flow
reg [LOG2NUM_SETTINGS-1:0]	i;
reg [LOG2NUM_C_COUNTERS-1:0]	j;
reg [LOG2NUM_DPS_COUNTERS-1:0]	k;
always @(posedge mif_clk)
begin
    if (mif_rst)
    begin
        reg_mif_base_addr   <= 0;
        is_setting_changed  <= 0;
        is_c_cntr_changed   <= 0;
        is_dps_changed      <= 0;
        rom_addr            <= 0;
        reg_instr           <= 0;
        reg_data            <= 0;
        for (i = 0; i < NUM_MIF_SETTINGS; i = i + 1'b1)
        begin
		    settings_reg [i] <= 0;
        end
        for (j = 0; j < NUM_C_COUNTERS; j = j + 1'b1)
        begin
            c_settings_reg [j] <= 0;
        end
        for (k = 0; k < NUM_DPS_COUNTERS; k = k + 1'b1)
        begin
            dps_settings_reg [k] <= 0;
        end
        setting_number      <= 0;
        c_cntr_number       <= 0;
        dps_number          <= 0;
        c_done              <= 0;
        dps_done            <= 0;
        c_cntr_index        <= 0;
        dps_index           <= 0;
        reconfig_write_data <= 0;
        reconfig_addr       <= 0;
        reconfig_write      <= 0;
        reconfig_read       <= 0; 
    end
    else
    begin
        case (mif_curstate)
            MIF_IDLE:               
            begin
                reg_mif_base_addr <= mif_base_addr;
                is_setting_changed <= 0;
                is_c_cntr_changed   <= 0;
                is_dps_changed      <= 0;
    			    rom_addr            <= 0;
                reg_instr           <= 0;
				reg_data            <= 0;
				for (i = 0; i < NUM_MIF_SETTINGS; i = i + 1'b1)
				begin
				    settings_reg [i] <= 0;
			 	end
                for (j = 0; j < NUM_C_COUNTERS; j = j + 1'b1)
                begin
                    c_settings_reg [j] <= 0;
                end
                for (k = 0; k < NUM_DPS_COUNTERS; k = k + 1'b1)
                begin
                    dps_settings_reg [k] <= 0;
                end
                setting_number <= 0;
                c_cntr_number <= 0;
                dps_number <= 0;
                c_done              <= 0;
                dps_done            <= 0;
                c_cntr_index        <= 0;
                dps_index           <= 0;
                reconfig_write_data <= 0;
                reconfig_addr       <= 0;
                reconfig_write      <= 0;
                reconfig_read       <= 0;
            end
            
            // ----- ROM FLOW ----- //
            SET_INSTR_ADDR:         rom_addr <= (mif_started) ? rom_addr + 9'd1 : reg_mif_base_addr; // ROM_ADDR_WIDTH = 9
            FETCH_INSTR:            ;
            WAIT_FOR_ROM_INSTR:		;
            STORE_INSTR:            reg_instr <= rom_q [LOG2NUM_SETTINGS-1:0];    // Only the last 6 bits are instr bits, rest is reserved
            DECODE_ROM_INSTR:       ;
            SET_DATA_ADDR:          rom_addr <= rom_addr + 9'd1; // ROM_ADDR_WIDTH = 9
            SET_DATA_ADDR_DLY:      ;
            FETCH_DATA:             ;
            WAIT_FOR_ROM_DATA:		;
            STORE_DATA:             reg_data <= rom_q;      // Data is 32 bits
    
            SET_INDEX:
            begin
                c_cntr_index    <= reg_data[22:18];
                dps_index       <= reg_data[20:16];
            end

    
            CHANGE_SETTINGS_REG:    
            begin
                if (reg_instr == OP_C_COUNTERS)
                begin
                    c_settings_reg [c_cntr_index] <= reg_data;   //22:18 is c cnt number
                    is_c_cntr_changed [c_cntr_index] <= 1'b1;
                end
                else if (reg_instr == OP_DPS)
                begin
                    dps_settings_reg [dps_index] <= reg_data;   //20:16 is DPS number
                    is_dps_changed [dps_index] <= 1'b1;
                end
                else
                begin
                    c_settings_reg [c_cntr_index] <= c_settings_reg [c_cntr_index];
                    is_c_cntr_changed [c_cntr_index] <= is_c_cntr_changed[c_cntr_index];
                    dps_settings_reg [dps_index] <= dps_settings_reg [dps_index];
                    is_dps_changed [dps_index] <= is_dps_changed [dps_index];
                end

                settings_reg [reg_instr] <= reg_data;
                is_setting_changed [reg_instr] <= 1'b1;
            end
            

            // ---------- RECONFIG FLOW ---------- //
            
            // Reading/writing mode takes only one cycle
            // (we don't know what mode its in initally)
            SET_MODE_REG_INFO:
            begin
                reconfig_addr <= OP_MODE;   
                reconfig_read <= 1'b1;
                reconfig_write <= 1'b0;
                reconfig_write_data <= 0;
            end

            WAIT_MODE_REG:      reconfig_read <= 1'b0; 
            SAVE_MODE_REG:      saved_mode <= reconfig_read_data[0];
            SET_WR_MODE:
            begin
                reconfig_addr <= OP_MODE;
                reconfig_write <= 1'b1;
                reconfig_write_data[0] <= MODE_WR;         // Want WaitRequest Mode while MIF reader changes Reconfig regs
            end
            WAIT_WRITE_MODE:    reconfig_write <= 1'b0;

           // Done saving the mode reg, start writing the reconfig regs
			  // Start with the highest setting and work our way down
            INIT_RECONFIG_PARAMS:
            begin
                setting_number  <= NUM_MIF_SETTINGS - 6'd1;
                c_cntr_number   <= NUM_C_COUNTERS;
                dps_number      <= NUM_DPS_COUNTERS;
            end
				
            CHECK_RECONFIG_SETTING:     ;
			
            // C LOOP
            DECREMENT_C_NUM:
            begin
                c_cntr_number   <= c_cntr_number - 5'd1;
                reconfig_write  <= 1'b0;
            end

            CHECK_C_SETTINGS:       
            begin
                if (c_cntr_number == 5'b0)
                    c_done <= 1'b1;
                else
                    c_done <= c_done;
            end
                        
            WRITE_C_SETTINGS:
            begin
                reconfig_addr <= OP_C_COUNTERS;
                reconfig_write_data <= c_settings_reg[c_cntr_number];
                reconfig_read <= 1'b0;
                reconfig_write <= 1'b1;
            end
            //End C Loop
            
            // DPS LOOP
            DECREMENT_DPS_NUM:
            begin
                dps_number   <= dps_number - 5'd1;
                reconfig_write  <= 1'b0;
            end

            CHECK_DPS_SETTINGS:
            begin
                if (dps_number == 5'b0)
                    dps_done <= 1'b1;
                else
                    dps_done <= dps_done;
            end
            
            WRITE_DPS_SETTINGS:
            begin
                reconfig_addr <= OP_DPS;
                reconfig_write_data <= dps_settings_reg[dps_number];
                reconfig_read <= 1'b0;
                reconfig_write <= 1'b1;
            end
            //End DPS Loop

            WRITE_RECONFIG_SETTING:
            begin
                reconfig_addr <= setting_number;        // setting_number = OP_CODE
                reconfig_write_data <= settings_reg[setting_number];
                reconfig_read <= 1'b0;
                reconfig_write <= 1'b1;
            end
            
            DECREMENT_SETTING_NUM:
            begin
                reconfig_write <= 1'b0;
                setting_number <= setting_number - 6'd1;     // Decrement for looping back
            end
 
            // --- Wrote all the changed settings to the Reconfig IP except MODE
            // --- Start the Reconfig process (write to start reg) and wait for
            // --- waitrequest signal to deassert
            
            START_RECONFIG_CHANGE:
            begin
                reconfig_addr <= OP_START;
                reconfig_write_data <= 1;
                reconfig_read <= 1'b0;
                reconfig_write <= 1'b1;
            end
				
				START_RECONFIG_DELAY:
				begin
					 reconfig_write <= 1'b0;
				end
								
            WAIT_DONE_SIGNAL:				;
            
            // --- Restore saved MODE reg ONLY if mode hasn't been changed by MIF
            SET_MODE_REG:
                mode_reg <= (is_setting_changed[OP_MODE]) ? settings_reg [OP_MODE][0] : saved_mode;
            
            WRITE_FINAL_MODE:
            begin
                reconfig_addr <= OP_MODE;
                reconfig_write_data[0] <= mode_reg;
                reconfig_read <= 1'b0;
                reconfig_write <= 1'b1;
            end

            WAIT_FINAL_MODE:
            begin
                reconfig_write <= 1'b0;
            end

            MIF_STREAMING_DONE:     ;

			   default :            	;

        endcase
    end
end

// RAM block 
	altsyncram	altsyncram_component (
				.address_a (rom_addr),
				.clock0 (mif_clk),
				.q_a (rom_q),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.address_b (1'b1),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_a ({32{1'b1}}),
				.data_b (1'b1),
				.eccstatus (),
				.q_b (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_a (1'b0),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_a = "NONE",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.init_file = MIF_FILE_NAME,
		altsyncram_component.intended_device_family = "Stratix V",
		altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = ROM_NUM_WORDS,
		altsyncram_component.operation_mode = "ROM",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_reg_a = "CLOCK0",
		altsyncram_component.widthad_a = ROM_ADDR_WIDTH,
		altsyncram_component.width_a = ROM_DATA_WIDTH,
		altsyncram_component.width_byteena_a = 1;
		
endmodule  // mif_reader

