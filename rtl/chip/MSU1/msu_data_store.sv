//
// msu_data_store.v
// Copyright (c) 2022 Alexey Melnikov
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
//

module msu_data_store
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
	
	input         clk_sys,
	input  [31:0] base_addr,

	input         rd_next,
	input         rd_seek,
	output reg    rd_seek_done,
	input  [31:0] rd_addr,
	output  [7:0] rd_dout
);

assign DDRAM_BURSTCNT = ram_burst;
assign DDRAM_BE       = 8'hFF;
assign DDRAM_ADDR     = ram_address;
assign DDRAM_RD       = ram_read;
assign DDRAM_DIN      = 0;
assign DDRAM_WE       = 0;

wire [28:0] ph_addr      = base_addr[31:3] + rd_addr[31:3];
wire [28:0] ph_addr_curr = ph_addr + ((ph_addr >= 'h4400000) ? 29'h100000 : 29'h0);
wire [28:0] ph_addr_next = ph_addr + ((ph_addr >= 'h43FFFFF) ? 29'h100001 : 29'h1);

assign rd_dout = ram_q[{rd_addr[2:0], 3'b000} +:8];

reg  [7:0] ram_burst;
reg [63:0] ram_q, next_q;
reg [63:0] ram_data;
reg [28:0] ram_address, cache_addr;
reg        ram_read = 0;

reg  [1:0] state  = 0;

always @(posedge DDRAM_CLK) begin
	reg old_seek;
	reg old_rd;

	if(~rd_seek) old_seek <= 0;

	if(!DDRAM_BUSY) begin

		ram_read <= 0;
		old_rd   <= rd_next;

		case(state)
			0: if(~old_seek & rd_seek) begin
					old_seek    <= 1;
					rd_seek_done<= 0;
					ram_address <= ph_addr_curr;
					cache_addr  <= ph_addr_next; // seek to 'h21FFFFF8 will return wrong second dword
					ram_read 	<= 1;
					ram_burst   <= 2;
					state       <= 1;
				end
				else if(~old_rd & rd_next) begin
					if(cache_addr == ph_addr_curr) begin
						ram_q       <= next_q;
						ram_address <= ph_addr_next;
						cache_addr  <= ph_addr_next;
						ram_read    <= 1;
						ram_burst   <= 1;
						state       <= 2;
					end
				end

			1: if(DDRAM_DOUT_READY) begin
					ram_q <= DDRAM_DOUT;
					state <= 2;
				end

			2: if(DDRAM_DOUT_READY) begin
					next_q <= DDRAM_DOUT;
					state  <= 0;
					rd_seek_done <= 1;
				end
		endcase
	end
end

endmodule
