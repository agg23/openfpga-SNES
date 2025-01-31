// This module is responsible for handling sectors, including loop point and partial end sector.
// Pausing/resuming also handled here

module msu_audio
(
	input             reset,

	input             clk,
	input      [31:0] clk_rate,

	input      [7:0]  ctl_volume,
	input             ctl_repeat,
	input             ctl_play,
	output reg        ctl_stop,

	input      [31:0] track_size,
	input             track_processing,

	input             audio_download,
	input             audio_data_wr,
	input      [15:0] audio_data,

	output reg        audio_req,
	output reg        audio_seek,
	output reg [21:0] audio_sector,
	input             audio_ack,
 
	output     [15:0] audio_l,	 
	output     [15:0] audio_r
);

localparam WAITING_FOR_PLAY_STATE = 0;
localparam WAITING_ACK_STATE      = 1;
localparam PLAYING_STATE          = 2;
localparam PLAYING_CHECKS_STATE   = 3;
localparam END_SECTOR_STATE       = 5;

always @(posedge clk) begin
	reg [31:0] loop_index = 0;
	reg  [7:0] state = WAITING_FOR_PLAY_STATE;
	reg        partial_sector_state = 0;
	reg        looping;

	ctl_stop <= 0;

	if (reset) begin
		state <= WAITING_FOR_PLAY_STATE;
		audio_sector <= 0;
		audio_seek <= 0;
		fifo_wren <= 0;
		audio_req <= 0;
	end
	else begin

		// Loop sector handling - also need to take into account the 8 bytes for file header (msu1 and loop index = 8 bytes)
		if (audio_sector == 0 && data_cnt == 1 && data_wr && audio_ack) loop_index <= data + 2;

		case (state)
			WAITING_FOR_PLAY_STATE:
				begin
					audio_sector <= 0;
					audio_seek <= 0;
					partial_sector_state <= 0;
					fifo_wren <= 0;
					looping <= 0;
					audio_req <= 0;
					if (~track_processing & ctl_play) begin
						audio_seek <= 1;
						state <= WAITING_ACK_STATE;
					end
				end

			WAITING_ACK_STATE:
				if (audio_ack) begin
					audio_req <= 0;
					audio_seek <= 0;
					state <= PLAYING_STATE;
				end

			PLAYING_STATE:
				if (partial_sector_state) begin
					// Handling the last sector here
					if (data_cnt >= track_size[9:2]) begin
						fifo_wren <= 0;
						state <= END_SECTOR_STATE;
					end
				end
				else begin
					// Keep collecting samples until we hit the buffer limit and while audio_ack is still high
					if (looping) begin
						// We may need to deal with some remainder samples after the loop sector boundary
						if (data_cnt < loop_index[7:0]) begin
							// Disable writing to the fifo, skipping to the correct sample in the loop sector
							fifo_wren <= 0;
						end
						else begin
							looping <= 0;
							fifo_wren <= 1;
						end
					end
					else begin
						fifo_wren <= (audio_sector || data_cnt[7:1]);
					end
					 
					if (!audio_ack && fifo_usedw < 768) begin
						// We've received a full sector
						// Only add new sectors if we haven't filled the buffer
						// 1024 dwords in the fifo - sector size of 256 dwords
						state <= PLAYING_CHECKS_STATE;
					end
				end

			PLAYING_CHECKS_STATE:
				// Check if we've reached end_sector yet
				if (audio_sector < track_size[31:10]-1'd1) begin
					// Nope, Fetch another sector, keeping track of where we are
					audio_sector <= audio_sector + 1'd1;
					audio_req <= 1;
					state <= WAITING_ACK_STATE;
				end
				else begin
					state <= END_SECTOR_STATE;
				end

			END_SECTOR_STATE:
				// Depending on the last sector and looping, we need to handle things differently
				if (!track_size[9:2] || partial_sector_state) begin
					partial_sector_state <= 0;
					// Handle a full last sector
					if (!ctl_repeat) begin
						// Stop, no loop
						ctl_stop <= 1;
						state <= WAITING_FOR_PLAY_STATE;
					end
					else begin
						// Loop, jump back to the loop sector
						audio_sector <= loop_index[29:8];
						audio_seek <= 1;
						state <= WAITING_ACK_STATE;
						looping <= 1;
					end
				end
				else begin
					// Handle partial end sector - The last sector of the PCM file does NOT end on an exact
					// Sector boundary. We need to keep reading until we reach the end sample.
					// Move to the partial sector
					partial_sector_state <= 1;
					audio_sector <= audio_sector + 1'd1;
					audio_req <= 1;
					state <= WAITING_ACK_STATE;
				end
		endcase
		
		if(track_processing) state <= WAITING_FOR_PLAY_STATE;
	end
end

reg        data_wr;
reg [31:0] data;
reg  [7:0] data_cnt;

always @(posedge clk) begin
	reg [8:0] cnt;

	data_wr <= 0;

	if(~audio_download) begin
		data_cnt <= 0;
		cnt <= 0;
	end
	else if(audio_data_wr)  begin
		cnt <= cnt + 1'd1;
		if(cnt[0]) begin
			data[31:16] <= audio_data;
			data_wr <= 1;
		end
		else begin
			data[15:0] <= audio_data;
			data_cnt <= cnt[8:1];
		end
	end
end

reg sample_ce;
CEGen sample_clock
(
	.CLK(clk),
	.RST_N(~reset),
	.IN_CLK(clk_rate),
	.OUT_CLK(44100),
	.CE(sample_ce)
);

wire        playing = ctl_play & ~track_processing & ~fifo_empty;
wire        fifo_full;
wire  [9:0] fifo_usedw;
wire        fifo_empty;
reg         fifo_wren;
wire [15:0] sample_l;
wire [15:0] sample_r;

msu_fifo #(32,10) audio_fifo
(
	.aclr(track_processing),

	.wrclk(clk),
	.wrreq(data_wr & ~fifo_full & fifo_wren),
	.data(data),
	.wrfull(fifo_full),
	.wrusedw(fifo_usedw),

	.rdclk(clk),
	.q({sample_r,sample_l}),
	.rdreq(sample_ce & playing),
	.rdempty(fifo_empty)
);

wire [23:0] vol_mix_l = $signed(sample_l) * ctl_volume;
wire [23:0] vol_mix_r = $signed(sample_r) * ctl_volume;
assign      audio_l = playing ? vol_mix_l[23:8] : 16'h0000;
assign      audio_r = playing ? vol_mix_r[23:8] : 16'h0000;

endmodule
