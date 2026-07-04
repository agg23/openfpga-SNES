// This module is responsible for exposing MSU registers to the SNES for it to control

module MSU
(
	input             CLK,
	input             RST_N,
	input             ENABLE,

	input             RD_N,
	input             WR_N,
	input             SYSCLKF_CE,

	input      [23:0] ADDR,
	input       [7:0] DIN,
	output reg  [7:0] DOUT,
	output            MSU_SEL,

	output reg [15:0] track_num,
	output            track_request,
	input             track_mounting,

	// Audio player control
	output reg  [7:0] volume,
	input             status_track_missing,
	output reg        status_audio_repeat,
	output reg        status_audio_playing,
	input             audio_stop,
	output reg        audio_resume,
	input      [21:0] audio_sector,
	output reg [21:0] resume_sector,

	// Data track read
	output reg [31:0] data_addr,
	input       [7:0] data,
	input             data_ack,
	output reg        data_seek,
	output reg        data_req
);


// Read 'registers'
// MSU_STATUS - $2000
// Status bits
localparam [2:0] status_revision = 3'b010;
wire [7:0] MSU_STATUS = {
	status_data_busy,
	status_audio_busy,
	status_audio_repeat,
	status_audio_playing,
	status_track_missing,
	status_revision
};

// Write register buffers excl MSB
reg [23:0] MSU_SEEK;   // $2000 - $2003
reg [ 7:0] MSU_TRACK;  // $2004 - $2005

// banks 00-3F and 80-BF, address 2000-2007
assign MSU_SEL = ENABLE && !ADDR[22] && (ADDR[15:4] == 'h200) && !ADDR[3];

wire       status_audio_busy = track_request;
reg [15:0] resume_track_num;
reg        resume_valid;

reg status_data_busy;
reg data_ack_old;
reg track_mounting_old;

reg  data_rd_old;
wire data_rd = MSU_SEL && !RD_N && ADDR[2:0] == 1 && !status_data_busy;

always @(posedge CLK) begin
	if (~RST_N) begin
		data_addr <= 0;
		track_num <= 0;
		track_request <= 0;
		volume <= 0;
		status_audio_playing <= 0;
		audio_resume <= 0;
		status_audio_repeat <= 0;
		status_data_busy <= 0;
		track_mounting_old <= 0;
		data_ack_old <= 0;
		data_rd_old <= 0;
		resume_valid <= 0;
		data_req <= 0;
		data_seek <= 0;
	end
	else begin

		// Set/reset pulsed signals
		data_req <= 0;
		audio_resume <= 0;
		if (audio_stop) status_audio_playing <= 0;

		// Rising edge of data busy
		data_ack_old <= data_ack;
		if (!data_ack_old && data_ack) begin
			status_data_busy <= 0;
			data_seek <= 0;
		end

		// Falling edge of track mounting
		track_mounting_old <= track_mounting;
		if (track_mounting_old && !track_mounting) track_request <= 0;

		// Register writes
		if (MSU_SEL & SYSCLKF_CE & ~WR_N) begin
			case (ADDR[2:0])
				0: MSU_SEEK[7:0]   <= DIN;
				1: MSU_SEEK[15:8]  <= DIN;
				2: MSU_SEEK[23:16] <= DIN;
				3: begin 
					data_addr <= {DIN, MSU_SEEK};
					data_seek <= 1;
					status_data_busy <= 1;
				end
				4: MSU_TRACK <= DIN;
				5: begin
					track_num <= {DIN, MSU_TRACK};
					track_request <= 1;
					if (resume_valid && resume_track_num == {DIN, MSU_TRACK}) begin
						audio_resume <= 1;
						resume_valid <= 0;
					end
				end
				6: volume <= DIN;
				7: begin
					status_audio_repeat <= DIN[1];
					status_audio_playing <= DIN[0];
					if (DIN[2] && !DIN[0]) begin
						resume_track_num <= track_num;
						resume_sector <= audio_sector;
						resume_valid <= 1;
					end
				end
			endcase
		end

		// Advance data pointer after read
		data_rd_old <= data_rd;
		if (data_rd_old & ~data_rd) begin
			data_addr <= data_addr + 1;
			data_req <= 1'b1;
		end

		case (ADDR[2:0])
			0: DOUT <= MSU_STATUS;
			1: DOUT <= data;
			2: DOUT <= "S";
			3: DOUT <= "-";
			4: DOUT <= "M";
			5: DOUT <= "S";
			6: DOUT <= "U";
			7: DOUT <= "1";
		endcase
	end
end

endmodule
