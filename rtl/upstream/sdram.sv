module sdram
(
	inout  reg [15:0] SDRAM_DQ,   // 16 bit bidirectional data bus
	output reg [12:0] SDRAM_A,    // 13 bit multiplexed address bus
	output reg        SDRAM_DQML, // byte mask
	output reg        SDRAM_DQMH, // byte mask
	output reg  [1:0] SDRAM_BA,   // two banks
	output            SDRAM_nCS,  // a single chip select
	output reg        SDRAM_nWE,  // write enable
	output reg        SDRAM_nRAS, // row address select
	output reg        SDRAM_nCAS, // columns address select
	output            SDRAM_CLK,
	output            SDRAM_CKE,

	// cpu/chipset interface
	input             init,			// init signal after FPGA config to initialize RAM
	input             clk,			// sdram is accessed at up to 128MHz

	input     [23: 0] addr0,
	input     [15: 0] din0,
	output    [15: 0] dout0,
	input             wr0,
	input             rd0,
	input             word0,
	
	input     [23: 0] addr1,
	input     [15: 0] din1,
	output    [15: 0] dout1,
	input             wr1,
	input             rd1,
	input             word1,

	output [1:0] dbg_ctrl_bank,
	output [1:0] dbg_ctrl_cmd,
	output [3:0] dbg_ctrl_we,
	output       dbg_ctrl_rfs,
	
	output       dbg_data_read,
	output       dbg_out_read,
	output [1:0] dbg_out_bank,
	
	output reg [15:0] dbg_sdram_d
);

	localparam RASCAS_DELAY   = 3'd1; // tRCD=20ns -> 2 cycles@85MHz
	localparam BURST          = 3'd0; // 0=1, 1=2, 2=4, 3=8, 7=full page
	localparam ACCESS_TYPE    = 1'd0; // 0=sequential, 1=interleaved
	localparam CAS_LATENCY    = 3'd2; // 2/3 allowed
	localparam OP_MODE        = 2'd0; // only 0 (standard operation) allowed
	localparam NO_WRITE_BURST = 1'd1; // 0=write burst enabled, 1=only single access write

	localparam bit [12:0] MODE = {3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST}; 
	
	localparam STATE_IDLE  = 3'd0;             // state to check the requests
	localparam STATE_START = STATE_IDLE+1'd1;  // state in which a new command is started
	localparam STATE_CONT  = STATE_START+RASCAS_DELAY;
	localparam STATE_READY = STATE_CONT+CAS_LATENCY+1'd1;
	localparam STATE_LAST  = STATE_READY;      // last state in cycle
	
	localparam MODE_NORMAL = 2'b00;
	localparam MODE_RESET  = 2'b01;
	localparam MODE_LDM    = 2'b10;
	localparam MODE_PRE    = 2'b11;

	// initialization 
	reg [2:0] init_state = '0;
	reg [1:0] mode;
	reg       init_done = 0;
	always @(posedge clk) begin
		reg [4:0] reset = 5'h1f;
		reg init_old = 0;
		
		if(mode != MODE_NORMAL || init_state != STATE_IDLE || reset) begin
			init_state <= init_state + 1'd1;
			if (init_state == STATE_LAST) init_state <= STATE_IDLE;
		end

		init_old <= init;
		if (init_old & ~init) begin
			reset <= 5'h1f; 
			init_done <= 0;
		end
		else if (init_state == STATE_LAST) begin
			if(reset != 0) begin
				reset <= reset - 5'd1;
				if (reset == 15) begin mode <= MODE_PRE; end
				else if(reset == 4) begin mode <= MODE_LDM; end
				else                mode <= MODE_RESET;
			end
			else begin
				mode <= MODE_NORMAL;
				init_done <= 1;
			end
		end
	end
	
	localparam CTRL_IDLE = 2'd0;
	localparam CTRL_RAS = 2'd1;
	localparam CTRL_CAS = 2'd2;
	
	typedef struct packed
	{
		bit [ 1:0] CMD;	//command
		bit [ 1:0] BANK;	//bank
		bit [22:0] ADDR;	//read/write address
		bit [15:0] DATA;	//write data
		bit        RD;		//read	
		bit        WE;		//write enable
		bit [ 1:0] BE;		//byte
		bit        RFS;	//refresh	
	} state_t;
	state_t state[5];
	reg [ 3: 0] st_num;
	
	reg [23: 0] addr[2];
	reg [15: 0] din[2];
	reg         word[2];
	reg         read[2],write[2],rfs;
	
	wire raw_req_test = (addr[0][23:1] != addr0[23:1]);
	
		reg old_rd0, old_rd1, old_wr0, old_wr1;
	always @(posedge clk) begin
		
		if (!init_done) begin
			st_num <= 4'd8;
			read <= '{2{0}};
			write <= '{2{0}};
			rfs <= 0;
		end else begin
			if (st_num < 4'd8) st_num <= st_num + 4'd1;
			
			if (st_num == 4'd3) begin
				read <= '{2{0}};
				rfs <= 0;
			end
			if (st_num == 4'd7) begin
				write <= '{2{0}};
			end
			
			{old_rd0,old_rd1} <= {rd0,rd1};
			{old_wr0,old_wr1} <= {wr0,wr1};
			if (wr0 && !old_wr0) begin
				addr[0] <= addr0;
				din[0] <= din0;
				word[0] <= word0;
				write[0] <= 1;
				st_num <= 5;
			end
			if (wr1 && !old_wr1) begin
				addr[1] <= addr1;
				din[1] <= din1;
				word[1] <= word1;
				write[1] <= 1;
				st_num <= 5;
			end
			
			if (rd0 && !old_rd0) begin
				addr[0] <= addr0;
				word[0] <= word0;
				read[0] <= raw_req_test;
				rfs <= ~raw_req_test;
				st_num <= 1;
			end
			if (rd1 && !old_rd1) begin
				addr[1] <= addr1;
				word[1] <= word1;
				read[1] <= 1;
				st_num <= 1;
			end
			
			if ((wr0 && !old_wr0) || (wr1 && !old_wr1) || (rd1 && !old_rd1) || read[1] || write[0] || write[1]) begin
				rfs <= 0;
			end
		end
		
	end
	
	always_comb begin
		state[0] <= '0;
		if (!init_done) begin
			state[0].CMD <= init_state == STATE_START ? CTRL_RAS : 
			                init_state == STATE_CONT  ? CTRL_CAS : 
								                             CTRL_IDLE;
			state[0].RFS <= 1;
		end else begin
			if (rd0 && !old_rd0 && raw_req_test) begin
				            state[0].CMD  <= CTRL_RAS;
								state[0].ADDR <= addr0[22:0];
								state[0].BANK <= {1'b0,addr0[23]};
			end else if (wr0 && !old_wr0 && !rd0 && !rd1) begin
				            state[0].CMD  <= CTRL_RAS;
								state[0].ADDR <= addr0[22:0];
								state[0].BANK <= {1'b0,addr0[23]};
			end else
			case (st_num[2:0])
//				3'd0: begin state[0].CMD  <= read[0]     ? CTRL_RAS : CTRL_IDLE;
//								state[0].ADDR <= addr[0][22:0];
//								state[0].BANK <= {1'b0,addr[0][23]}; end
								
				3'd1: begin state[0].CMD  <= read[1] || rfs     ? CTRL_RAS : CTRL_IDLE;
								state[0].ADDR <= addr[1][22:0];
								state[0].BANK <= {1'b1,addr[1][23]};
								state[0].RFS  <= rfs; end

				3'd2: begin state[0].CMD  <= read[0] && !rfs    ? CTRL_CAS : CTRL_IDLE;
								state[0].ADDR <= addr[0][22:0];
				            state[0].RD   <= read[0] & ~rfs;
								state[0].BANK <= {1'b0,addr[0][23]}; end

				3'd3: begin state[0].CMD  <= read[1]           ? CTRL_CAS : CTRL_IDLE;
								state[0].ADDR <= addr[1][22:0];
				            state[0].RD   <= read[1];
								state[0].BANK <= {1'b1,addr[1][23]}; end
								
				3'd4: begin state[0].CMD  <= write[0]           ? CTRL_RAS : CTRL_IDLE;
								state[0].ADDR <= addr[0][22:0];
								state[0].BANK <= {1'b0,addr[0][23]}; end
								
				3'd5: begin state[0].CMD  <= write[1]          ? CTRL_RAS : CTRL_IDLE;
								state[0].ADDR <= addr[1][22:0];
								state[0].BANK <= {1'b1,addr[1][23]}; end

				3'd6: begin state[0].CMD  <= write[0]                  ? CTRL_CAS : CTRL_IDLE;
								state[0].ADDR <= addr[0][22:0];
								state[0].DATA <= word[0] ? din[0] : {2{din[0][7:0]}};
								state[0].WE   <= write[0];
								state[0].BE   <= word[0] ? 2'b11 : {addr[0][0],~addr[0][0]};
								state[0].BANK <= {1'b0,addr[0][23]}; end

				3'd7: begin state[0].CMD  <= write[1]                  ? CTRL_CAS : CTRL_IDLE;
								state[0].ADDR <= addr[1][22:0];
								state[0].DATA <= word[1] ? din[1] : {2{din[1][7:0]}};
								state[0].WE   <= write[1];
								state[0].BE   <= word[1] ? 2'b11 : {addr[1][0],~addr[1][0]};
								state[0].BANK <= {1'b1,addr[1][23]}; end
				default:;
			endcase
		end
	end
	
	always @(posedge clk) begin
		state[1] <= state[0];
		state[2] <= state[1];
		state[3] <= state[2];
		state[4] <= state[3];
	end
	
	wire [ 1:0] ctrl_cmd   = state[0].CMD;
	wire [22:1] ctrl_addr  = state[0].ADDR[22:1];
	wire [15:0] ctrl_data  = state[0].DATA;
//	wire        ctrl_rd    = state[0].RD;
	wire        ctrl_we    = state[0].WE;
	wire [ 1:0] ctrl_be    = state[0].BE;
	wire [ 1:0] ctrl_bank  = state[0].BANK;
	wire        ctrl_rfs   = state[0].RFS;
	
	wire       data_read = state[3].RD;
	wire [1:0] data_bank  = state[3].BANK;
	wire       data_rfs  = state[3].RFS;
	wire       out_read  = state[4].RD;
//	wire       out_addr0  = state[4].ADDR[0];
	wire [1:0] out_bank  = state[4].BANK;
	
	reg [15:0] rbuf;
	reg [15:0] dout_buf[2];
	reg data_read0_new;
	always @(posedge clk) begin
		if (data_read) rbuf <= SDRAM_DQ;
		
		data_read0_new <= 0;
		if (data_read && !data_bank[1] && !data_rfs) data_read0_new <= 1;

		if (out_read) dout_buf[out_bank[1]] <= rbuf;
	end
	wire [15:0] dout_temp_0 = data_read0_new ? rbuf : dout_buf[0];
	assign dout0 = addr[0][0] && !word[0] ? {dout_temp_0[15:8],dout_temp_0[15:8]} : dout_temp_0;
	assign dout1 = addr[1][0] && !word[1] ? {dout_buf[1][15:8],dout_buf[1][15:8]} : dout_buf[1];
	

	localparam CMD_NOP             = 3'b111;
	localparam CMD_ACTIVE          = 3'b011;
	localparam CMD_READ            = 3'b101;
	localparam CMD_WRITE           = 3'b100;
	localparam CMD_BURST_TERMINATE = 3'b110;
	localparam CMD_PRECHARGE       = 3'b010;
	localparam CMD_AUTO_REFRESH    = 3'b001;
	localparam CMD_LOAD_MODE       = 3'b000;
	
	// SDRAM state machines
	wire [22:1] a = ctrl_addr;
	wire [15:0] d = ctrl_data;
	wire        we = ctrl_we;
	wire  [1:0] dqm = ~ctrl_be;
	always @(posedge clk) begin
		if (ctrl_cmd == CTRL_RAS || ctrl_cmd == CTRL_CAS) SDRAM_BA <= (mode == MODE_NORMAL) ? ctrl_bank : 2'b00;

		casex({init_done,ctrl_rfs,we,mode,ctrl_cmd})
			{3'bx0x, MODE_NORMAL, CTRL_RAS}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_nCS} <= {CMD_ACTIVE,1'b0};
			{3'bx1x, MODE_NORMAL, CTRL_RAS}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_nCS} <= {CMD_AUTO_REFRESH,1'b0};
			{3'b101, MODE_NORMAL, CTRL_CAS}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_nCS} <= {CMD_WRITE,1'b0};
			{3'b100, MODE_NORMAL, CTRL_CAS}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_nCS} <= {CMD_READ,1'b0};

			// init
			{3'bxxx,    MODE_LDM, CTRL_RAS}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_nCS} <= {CMD_LOAD_MODE, 1'b0};
			{3'bxxx,    MODE_PRE, CTRL_RAS}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_nCS} <= {CMD_PRECHARGE, 1'b0};

										   default: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_nCS} <= {CMD_NOP,1'b0};
		endcase
		
		SDRAM_DQ <= 'Z;
		casex({init_done,ctrl_rfs,we,mode,ctrl_cmd})
			{3'b101, MODE_NORMAL, CTRL_CAS}: begin SDRAM_DQ <= d; dbg_sdram_d <= d; end
										   default: ;
		endcase

		if (mode == MODE_NORMAL) begin
			casex ({we,ctrl_cmd})
				{1'bx,CTRL_RAS}: SDRAM_A <= a[13:1];
				{1'b0,CTRL_CAS}: SDRAM_A <= {2'b00,2'b10,a[22:14]};
				{1'b1,CTRL_CAS}: SDRAM_A <= {dqm  ,2'b10,a[22:14]};
			endcase;
		end
		else if (mode == MODE_LDM && ctrl_cmd == CTRL_RAS) SDRAM_A <= MODE;
		else if (mode == MODE_PRE && ctrl_cmd == CTRL_RAS) SDRAM_A <= 13'b0010000000000;
		else SDRAM_A <= '0;
	end
	
	assign SDRAM_CKE = 1;
	assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];
	
	
	
	assign dbg_ctrl_bank = ctrl_bank;
	assign dbg_ctrl_cmd = ctrl_cmd;
	assign dbg_ctrl_we = ctrl_we;
	assign dbg_ctrl_rfs = ctrl_rfs;
	assign dbg_data_read = data_read;
	assign dbg_out_read = out_read;
	assign dbg_out_bank = out_bank;

	altddio_out
	#(
		.extend_oe_disable("OFF"),
		.intended_device_family("Cyclone V"),
		.invert_output("OFF"),
		.lpm_hint("UNUSED"),
		.lpm_type("altddio_out"),
		.oe_reg("UNREGISTERED"),
		.power_up_high("OFF"),
		.width(1)
	)
	sdramclk_ddr
	(
		.datain_h(1'b0),
		.datain_l(1'b1),
		.outclock(clk),
		.dataout(SDRAM_CLK),
		.aclr(1'b0),
		.aset(1'b0),
		.oe(1'b1),
		.outclocken(1'b1),
		.sclr(1'b0),
		.sset(1'b0)
	);

endmodule
