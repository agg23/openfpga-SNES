//
// hps_ext for Mega CD
//
// Copyright (c) 2020 Alexey Melnikov
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
///////////////////////////////////////////////////////////////////////

module hps_ext
(
	input             reset,
	input             clk_sys,
	inout      [35:0] EXT_BUS,

	output reg        msu_enable,

	input      [15:0] msu_track_num,
	input             msu_track_request,
	output reg        msu_track_mounting,
	output reg        msu_track_missing,
	
	output reg [31:0] msu_audio_size,
	output reg        msu_audio_ack,
	input             msu_audio_req,
	input             msu_audio_seek,
	input      [21:0] msu_audio_sector,
	input             msu_audio_download,

	output reg [31:0] msu_data_base
);

assign EXT_BUS[15:0] = io_dout;
wire [15:0] io_din = EXT_BUS[31:16];
assign EXT_BUS[32] = dout_en;
wire io_strobe = EXT_BUS[33];
wire io_enable = EXT_BUS[34];

localparam EXT_CMD_MIN = CD_GET;
localparam EXT_CMD_MAX = CD_SET;

localparam CD_GET = 'h34;
localparam CD_SET = 'h35;

reg [15:0] io_dout;
reg        dout_en = 0;
reg  [9:0] byte_cnt;

always@(posedge clk_sys) begin
	reg [15:0] cmd;
	reg  [7:0] cd_req = 0;

	cd_get <= 0;
	if(cd_put) cd_req <= cd_req + 1'd1;

	if(~io_enable) begin
		dout_en <= 0;
		io_dout <= 0;
		byte_cnt <= 0;
		if(cmd == 'h35) cd_get <= 1;
	end
	else if(io_strobe) begin

		io_dout <= 0;
		if(~&byte_cnt) byte_cnt <= byte_cnt + 1'd1;

		if(byte_cnt == 0) begin
			cmd <= io_din;
			dout_en <= (io_din >= EXT_CMD_MIN && io_din <= EXT_CMD_MAX);
			if(io_din == CD_GET) io_dout <= cd_req;
		end else begin
			case(cmd)
				CD_GET:
					if(!byte_cnt[9:3]) begin
						case(byte_cnt[2:0])
							1: io_dout <= cd_in[15:0];
							2: io_dout <= cd_in[31:16];
							3: io_dout <= cd_in[47:32];
						endcase
					end

				CD_SET:
					if(!byte_cnt[9:3]) begin
						case(byte_cnt[2:0])
							1: cd_out[15:0]  <= io_din;
							2: cd_out[31:16] <= io_din;
							3: cd_out[47:32] <= io_din;
						endcase
					end
			endcase
		end
	end
end

reg [47:0] cd_in;
reg [47:0] cd_out;
reg cd_put, cd_get;

always @(posedge clk_sys) begin
	reg reset_old = 0;
	reg msu_audio_req_old = 0;
	reg msu_audio_seek_old = 0;
	reg msu_track_request_old = 0;
	reg msu_audio_download_old = 0;

	cd_put <= 0;

	reset_old <= reset;
	if (reset) begin
		msu_track_missing  <= 0;
		msu_track_mounting <= 0;
		msu_audio_ack     <= 0;
		if (!reset_old) begin
			cd_in  <= 8'hFF;
			cd_put <= 1;
		end
	end

	msu_audio_download_old <= msu_audio_download;
	if (!msu_audio_download && msu_audio_download_old) begin
		msu_audio_ack <= 0;
	end
	if (msu_audio_download && !msu_audio_download_old) begin
		msu_audio_ack <= 1;
	end
	
	// Outgoing messaging
	// Sectors
	msu_audio_req_old <= msu_audio_req;
	if (!msu_track_request && !msu_audio_req_old && msu_audio_req) begin
		cd_in  <= 'h34;
		cd_put <= 1;
	end
	
	// Jump to a sector
	msu_audio_seek_old <= msu_audio_seek;
	if (!msu_track_request && !msu_audio_seek_old && msu_audio_seek) begin
		cd_in  <= { msu_audio_sector, 16'h36 };
		cd_put <= 1;
	end
	
	// Track requests
	msu_track_request_old <= msu_track_request;
	if (!msu_track_request_old && msu_track_request) begin
		cd_in  <= { msu_track_num, 16'h35 };
		cd_put <= 1;
		msu_track_missing <= 0;
		msu_track_mounting <= 1;
	end

	if (cd_get) begin
		case(cd_out[3:0])
			1: msu_enable <= cd_out[15];
			2: {msu_audio_size, msu_track_missing, msu_track_mounting, msu_audio_ack} <= {cd_out[47:16], !cd_out[47:16], 2'b00};
			3: msu_data_base <= cd_out[47:16];
		endcase
	end
end

endmodule
