//
// ddram.v
// Copyright (c) 2017,2019 Sorgelig
//
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. 
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// ------------------------------------------
//

// 16-bit version

module ddram
(
	input         DDRAM_CLK,

	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	input         cache_rst,

	input  [31:1] wraddr,
	input  [15:0] din,
	input         we_req,
	output reg    we_ack,

	input  [31:3] rdaddr,
	output [63:0] dout,
	input  [63:0] rom_din,
	input   [7:0] rom_be,
	input         rom_we,
	input         rom_req,
	output reg    rom_ack,

	input  [31:3] rdaddr2,
	output [63:0] dout2,
	input         rd_req2,
	output reg    rd_ack2
);

assign DDRAM_BURSTCNT = ram_burst;
assign DDRAM_BE       = ram_be | {8{ram_read}};
assign DDRAM_ADDR     = ram_address;
assign DDRAM_RD       = ram_read;
assign DDRAM_DIN      = ram_data;
assign DDRAM_WE       = ram_write;

//assign dout  =  ram_q[{rdaddr[2:1],  4'b0000} +:16];
//assign dout2 = ram_q2[{rdaddr2[2:1], 4'b0000} +:16]; 
assign dout = ram_q;
assign dout2 = ram_q2;

reg  [7:0] ram_burst;
reg [63:0] ram_q, next_q, ram_q2, next_q2;
reg [63:0] ram_data;
reg [31:3] ram_address, cache_addr, cache_addr2;
reg        ram_read = 0;
reg        ram_write = 0;
reg  [7:0] ram_be = 0;

reg [1:0]  state  = 0;
reg        ch = 0;

reg [1:0]  cache_valid;

always @(posedge DDRAM_CLK) begin
	if (cache_rst) begin
		cache_valid <= 2'b00;
	end

	if(!DDRAM_BUSY) begin
		ram_write <= 0;
		ram_read  <= 0;

		case(state)
			0: if(we_ack != we_req) begin
					ram_be      <= 8'd3<<{wraddr[2:1],1'b0};
					ram_data		<= {4{din}};
					ram_address <= wraddr[31:3];
					ram_write 	<= 1;
					ram_burst   <= 1;
					ch          <= 1;
					state       <= 1;
				end
				else if(rom_req != rom_ack) begin
					if(rom_we) begin
						ram_be      <= rom_be;
						ram_data	<= rom_din;
						ram_address <= rdaddr[31:3];
						ram_write 	<= 1;
						ram_burst   <= 1;
						ch          <= 0;
						state       <= 1;
					end
					else if(cache_valid[0] & (cache_addr == rdaddr[31:3])) rom_ack <= rom_req;
					else if(cache_valid[0] & ((cache_addr+1'd1) == rdaddr[31:3])) begin
						rom_ack     <= rom_req;
						ram_q       <= next_q;
						cache_addr  <= rdaddr[31:3];
						ram_address <= rdaddr[31:3]+1'd1;
						ram_read    <= 1;
						ram_burst   <= 1;
						ch 			<= 0; 
						state       <= 3;
					end
					else begin
						ram_address <= rdaddr[31:3];
						cache_addr  <= rdaddr[31:3];
						ram_read    <= 1;
						ram_burst   <= 2;
						ch 			<= 0; 
						state       <= 2;
					end 
				end
				else if(rd_req2 != rd_ack2) begin
					if(cache_valid[1] & (cache_addr2 == rdaddr2[31:3])) rd_ack2 <= rd_req2;
					else if(cache_valid[1] & ((cache_addr2+1'd1) == rdaddr2[31:3])) begin
						rd_ack2     <= rd_req2;
						ram_q2      <= next_q2;
						cache_addr2 <= rdaddr2[31:3];
						ram_address <= rdaddr2[31:3]+1'd1;
						ram_read    <= 1;
						ram_burst   <= 1;
						ch 			<= 1;
						state       <= 3;
					end
					else begin
						ram_address <= rdaddr2[31:3];
						cache_addr2 <= rdaddr2[31:3];
						ram_read    <= 1;
						ram_burst   <= 2;
						ch 			<= 1;
						state       <= 2;
					end 
				end 

			1: begin
					cache_valid <= 2'b00;
					if(ch) we_ack <= we_req;
					else rom_ack <= rom_req;
					state <= 0;
				end

			2: if(DDRAM_DOUT_READY) begin
					if (~ch) begin
						ram_q  <= DDRAM_DOUT;
						rom_ack <= rom_req;
					end
					else begin
						ram_q2  <= DDRAM_DOUT;
						rd_ack2 <= rd_req2;
					end 
					state <= 3;
				end

			3: if(DDRAM_DOUT_READY) begin
					if (~ch) begin
						next_q <= DDRAM_DOUT;
						cache_valid[0] <= 1'b1;
					end
					else begin
						next_q2 <= DDRAM_DOUT;
						cache_valid[1] <= 1'b1;
					end
					state <= 0;
				end
		endcase
	end
end

endmodule
