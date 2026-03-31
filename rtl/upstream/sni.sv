/* UART driver for Super Nintendo Interface connectivity */

module sni(
	input wire			clk,
	input wire			reset,
	input wire			vblank,

	output wire[24:0]	sdram_addr,
	output wire[7:0]	sdram_data,
	input wire[7:0]		sdram_q,
	output wire			sdram_rd_req,
	output wire			sdram_wr_req,
	input wire			sdram_ready,

	input wire [63:0]	joypad,

	output wire[19:0]	bsram_addr,
	input  wire[7:0]	bsram_q,
	output wire			bsram_wr,
	output wire[7:0]	bsram_data,
	input  wire			bsram_ready,

	output wire			rbf,
	input wire			txint,
	input wire			rxint,
	output reg			tdata_i,
	output wire [15:0]	tdata_m,
	input wire [15:0]	rdata_m
	);

	reg [8:0] inbuffer_raddr;
	reg [8:0] last_inbuffer_raddr;
	reg [8:0] inbuffer_waddr;
	wire [7:0] inbuffer_rdata;
	wire [7:0] inbuffer_wdata;

	// receive buffer is full if head = tail - 1
	assign rbf = (inbuffer_waddr == inbuffer_raddr - 1);

	// State machine for UART interface
	enum bit[3:0] {
		// command-parsing states
		STATE_CMD		= 4'h0,
		STATE_ADDR		= 4'h1,		// 1, 2, 3
		STATE_LEN		= 4'h4,		// 4,
		STATE_PING		= 4'h5,		// 5

		// command-responding states
		STATE_TRANSFER	= 4'h8,		// 8, 9
		STATE_WAITNMI	= 4'hA,		// A
		STATE_VERSION   = 4'hB		// B
	} State;
	reg[3:0] state;

	localparam[7:0] PROTOCOL_VERSION = 8'b0;

	reg last_vblank;
	reg[23:0] addr;
	wire rom_sel	= addr[23:21] != 3'h7;
	wire wram_sel	= (addr[23:16] == 8'hF5 || addr[23:16] == 8'hF6);
	wire sdram_sel	= rom_sel | wram_sel;
	wire joypad_sel = (addr[23:4] == 20'hF9071 && addr[3] == 1'b1);
	wire bsram_sel	= (addr[23:20] == 4'hE);
	wire[16:0] wram_addr = {~addr[16], addr[15:0]};

	reg rd_req, wr_req;
	assign sdram_rd_req = rd_req;
	assign sdram_wr_req = wr_req;

	assign sdram_addr = wram_sel ? {1'b1, 7'h0, wram_addr} : {1'b0,addr};
	assign sdram_data = inbuffer_rdata;
	assign bsram_addr = addr[19:0];
	assign bsram_data = inbuffer_rdata;
	reg last_bsram_ready;
	reg bsram_wr_;
	assign bsram_wr = bsram_wr_;

	reg[7:0] len;

	enum bit[7:0] {
		CMD_PING	= 8'h00,
		CMD_READ	= 8'h1,
		CMD_WRITE	= 8'h2,
		CMD_WAITNMI = 8'h3,
		CMD_VERSION = 8'h4
	} Cmd;
	reg wNr;

	// UART RX buffer
	dpram #(9) inbuffer
	(
		.clock(clk),
		.address_a(inbuffer_waddr),
		.data_a(inbuffer_wdata),
		.wren_a(1'b1),

		.address_b(inbuffer_raddr),
		.q_b(inbuffer_rdata),
		.wren_b(1'b0)
	);

	assign inbuffer_wdata = rdata_m[7:0];

	reg[7:0] tdata;
	assign tdata_m = {8'h01, tdata};

	reg last_txint;
	reg last_rxint;
	reg tinprogress;

	reg sdram_busy;

	always @(posedge clk) begin
		last_txint <= txint;
		last_rxint <= rxint;
		last_vblank <= vblank;
		last_inbuffer_raddr <= inbuffer_raddr;
		last_bsram_ready <= bsram_ready;

		{rd_req, wr_req} <= 2'b0;
		tdata_i <= 1'b0;
		bsram_wr_ <= 1'b0;

		if (reset) begin
			addr <= 24'b0;
			len <= 8'b0;
			inbuffer_raddr <= 9'h000;
			inbuffer_waddr <= 9'h000;
			tinprogress <= 1'b0;
			sdram_busy <= 1'b0;
			state <= STATE_CMD;
		end else begin
			if (!rxint && last_rxint) begin
				// We've received data, update the write address for the next byte
				inbuffer_waddr <= inbuffer_waddr + 1'b1;
			end

			if (tinprogress) begin
				// If we're currently transmitting, don't do anything until the transmission finishes.
				if (!txint && last_txint) tinprogress <= 1'b0;
			end else if (last_inbuffer_raddr != inbuffer_raddr) begin
				// Wait for  DPRAM read result to be available next cycle.
			end else if (state[3] == 0) begin
				// If we're in a command-parsing state, and we have a data byte available...
				if (inbuffer_raddr != inbuffer_waddr) begin
					// Automatically advance to the next state unless the specific state overrides this behavior.
					state <= state + 1'b1;
					// Advance the read buffer index.
					inbuffer_raddr <= inbuffer_raddr + 1'b1;
					case (state)
						STATE_CMD: begin
							case (inbuffer_rdata)
								CMD_PING: begin
									// Respond with a length of 1, then read the next data byte
									tdata_i <= 1'b1;
									tinprogress <= 1'b1;
									tdata <= 1'b1;
									state <= STATE_PING;
								end
								CMD_VERSION: begin
									// Respond with a length of 1, then the
									// protocol version
									tdata_i <= 1'b1;
									tinprogress <= 1'b1;
									tdata <= 1'b1;
									state <= STATE_VERSION;
								end
								CMD_READ:  wNr <= 0; // go to STATE_ADDR
								CMD_WRITE: wNr <= 1; // go to STATE_ADDR
								CMD_WAITNMI: state <= STATE_WAITNMI;

								// Invalid command, ignore
								default: state <= STATE_CMD;
							endcase
						end
						STATE_ADDR+0: addr[7:0]   <= inbuffer_rdata;
						STATE_ADDR+1: addr[15:8]  <= inbuffer_rdata;
						STATE_ADDR+2: addr[23:16] <= inbuffer_rdata;
						STATE_LEN+0: begin
							len <= inbuffer_rdata;
							tdata_i <= 1'b1;
							tinprogress <= 1'b1;
							state <= STATE_TRANSFER;
							sdram_busy <= 1'b0;
							if (wNr) begin
								// write, response length is 0
								tdata <= 8'b0;
							end else begin
								// read, response length is the requested length
								tdata <= inbuffer_rdata;
							end
						end
						STATE_PING: begin
							// Echo the data byte we received.
							tdata_i <= 1'b1;
							tinprogress <= 1'b1;
							tdata <= inbuffer_rdata;
							state <= STATE_CMD;
						end
					endcase
				end
			end else if ((state == STATE_TRANSFER || state == STATE_TRANSFER+1) && !(rd_req || wr_req)) begin
				// If length is 0, we're done
				if (len == 24'b0) state <= STATE_CMD;
				else if (wNr) begin
					// Write
					if (inbuffer_raddr != inbuffer_waddr) begin
						// If we have data available, write it to memory.
						if (sdram_sel && !sdram_busy) begin
							wr_req <= 1'b1;
							sdram_busy <= 1'b1;
						end
						if (bsram_sel) begin
							bsram_wr_ <= 1'b1;
						end
						if ((!sdram_sel || (sdram_busy && sdram_ready)) && 
							(!bsram_sel || (bsram_wr_ && bsram_ready))) begin
							addr <= addr + 24'b1;
							len <= len - 1'b1;
							sdram_busy <= 1'b0;
							inbuffer_raddr <= inbuffer_raddr + 1'b1;
							bsram_wr_ <= 1'b0;
						end
					end
				end else begin
					// Read
					if ((!sdram_sel || (sdram_busy && sdram_ready)) && (!bsram_sel || last_bsram_ready)) begin
						if (sdram_sel) tdata <= sdram_q;
						else if (bsram_sel) tdata <= bsram_q;
						else if (joypad_sel) tdata <= joypad[addr[2:0]*8 +: 8];
						else tdata <= 8'b0;
						tinprogress <= 1'b1;
						tdata_i <= 1'b1;

						// Use blocking assignments so that the if statement below can issue another SDRAM read
						// request immediately, allowing read requests to be pipelined with UART transmissionss.
						addr = addr + 24'b1;
						len = len - 1'b1;
						sdram_busy = 1'b0;
					end
					if (sdram_sel && !sdram_busy && len != 24'h0) begin
						rd_req <= 1'b1;
						sdram_busy <= 1'b1;
					end
				end
			end else if (state == STATE_WAITNMI) begin
				if (vblank && ~last_vblank) begin
					// Response length = 0
					tinprogress <= 1'b1;
					tdata_i <= 1'b1;
					tdata <= 8'b0;
					state <= STATE_CMD;
				end
			end else if (state == STATE_VERSION) begin
				// Respond with the protocol version
				tinprogress <= 1'b1;
				tdata_i <= 1'b1;
				tdata <= PROTOCOL_VERSION;
				state <= STATE_CMD;
			end
		end
	end
endmodule
