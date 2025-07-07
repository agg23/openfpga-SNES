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
	input         clk_sys,
	input  [31:0] base_addr,

	input         rd_next,
	input         rd_seek,
	output reg    rd_seek_done,
	input  [31:0] rd_addr,

	output [31:3] ram_addr,
	output reg    ram_req,
	input         ram_ack,
	input  [63:0] ram_din,

	output  [7:0] rd_dout
);

wire [28:0] ph_addr      = base_addr[31:3] + rd_addr[31:3];
wire [28:0] ph_addr_curr = ph_addr + ((ph_addr >= 'h4400000) ? 29'h100000 : 29'h0);
wire [28:0] ph_addr_next = ph_addr + ((ph_addr >= 'h43FFFFF) ? 29'h100001 : 29'h1);

assign rd_dout = ram_q[{rd_addr[2:0], 3'b000} +:8];

reg [63:0] ram_q, next_q;
reg [28:0] ram_address, cache_addr;

reg  [1:0] state  = 0;

assign ram_addr = ram_address;

always @(posedge clk_sys) begin
	reg old_seek;
	reg old_rd;

	if(~rd_seek) old_seek <= 0;

	if(ram_ack == ram_req) begin

		old_rd   <= rd_next;

		case(state)
			0: if(~old_seek & rd_seek) begin
					old_seek    <= 1;
					rd_seek_done<= 0;
					ram_address <= ph_addr_curr;
					cache_addr  <= ph_addr_next; // seek to 'h21FFFFF8 will return wrong second dword
					ram_req     <= ~ram_req;
					state       <= 1;
				end
				else if(~old_rd & rd_next) begin
					if(cache_addr == ph_addr_curr) begin
						ram_q       <= next_q;
						ram_address <= ph_addr_next;
						cache_addr  <= ph_addr_next;
						ram_req     <= ~ram_req;
						state       <= 2;
					end
				end

			1:  begin
					ram_q <= ram_din;
					// Read next address
					ram_req <= ~ram_req;
					ram_address <= cache_addr;
					state <= 2;
				end

			2:  begin
					next_q <= ram_din;
					state  <= 0;
					rd_seek_done <= 1;
				end
		endcase
	end
end

endmodule
