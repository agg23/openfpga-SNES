module ioport
(
	input        CLK,

	input        MULTITAP,

	input        PORT_LATCH,
	input        PORT_CLK,
	input        PORT_P6,
	output [1:0] PORT_DO,
	output [15:0] JOYSTICK1_RUMBLE,  // 15:8 - 'large' rumble motor magnitude, 7:0 'small' rumble motor magnitude
	input	[11:0] JOYSTICK1,
	input	[11:0] JOYSTICK2,
	input	[11:0] JOYSTICK3,
	input	[11:0] JOYSTICK4,

	input [7:0]  JOY_X,
	input [7:0]  JOY_Y,

	input [7:0]  DPAD_AIM_SPEED,

	input        MOUSE_EN
);

assign PORT_DO = {(JOY_LATCH1[15] & ~PORT_LATCH) | ~MULTITAP, MOUSE_EN ? MS_LATCH[31] : JOY_LATCH0[15]};

wire [11:0] JOYSTICK[4] = '{JOYSTICK1,JOYSTICK2,JOYSTICK3,JOYSTICK4};

wire JOYn = ~PORT_P6 & MULTITAP;

wire [15:0] JOY0 = {JOYSTICK[{JOYn,1'b0}][5],  JOYSTICK[{JOYn,1'b0}][7],
                    JOYSTICK[{JOYn,1'b0}][10], JOYSTICK[{JOYn,1'b0}][11],
                    JOYSTICK[{JOYn,1'b0}][3],  JOYSTICK[{JOYn,1'b0}][2],
                    JOYSTICK[{JOYn,1'b0}][1],  JOYSTICK[{JOYn,1'b0}][0],
                    JOYSTICK[{JOYn,1'b0}][4],  JOYSTICK[{JOYn,1'b0}][6],
                    JOYSTICK[{JOYn,1'b0}][8],  JOYSTICK[{JOYn,1'b0}][9], 4'b0000};

wire [15:0] JOY1 = {JOYSTICK[{JOYn,1'b1}][5],  JOYSTICK[{JOYn,1'b1}][7],
                    JOYSTICK[{JOYn,1'b1}][10], JOYSTICK[{JOYn,1'b1}][11],
                    JOYSTICK[{JOYn,1'b1}][3],  JOYSTICK[{JOYn,1'b1}][2],
                    JOYSTICK[{JOYn,1'b1}][1],  JOYSTICK[{JOYn,1'b1}][0],
                    JOYSTICK[{JOYn,1'b1}][4],  JOYSTICK[{JOYn,1'b1}][6],
                    JOYSTICK[{JOYn,1'b1}][8],  JOYSTICK[{JOYn,1'b1}][9], 4'b0000};

reg [15:0] JOY_LATCH0;
always @(posedge CLK) begin
	reg old_clk, old_n;
	old_clk <= PORT_CLK;
	old_n <= JOYn;
	if(PORT_LATCH | (~old_n & JOYn)) JOY_LATCH0 <= ~JOY0;
	else if (~old_clk & PORT_CLK) JOY_LATCH0 <= JOY_LATCH0 << 1;
end

reg [15:0] JOY_LATCH1;
always @(posedge CLK) begin
	reg old_clk, old_n;
	old_clk <= PORT_CLK;
	old_n <= JOYn;
	if(PORT_LATCH | (~old_n & JOYn)) JOY_LATCH1 <= ~JOY1;
	else if (~old_clk & PORT_CLK) JOY_LATCH1 <= JOY_LATCH1 << 1;
end

// Rumble Support
// only Port 1 (JOYn==0) ever drives rumble
wire doing_port1 = ~MULTITAP || (MULTITAP && (JOYn == 1'b0));

// shift‑in window to spot 0x72
localparam [7:0] RUMBLE_SENTRY = 8'h72;
reg  [15:0] shift16;
reg  [15:0] current_rumble;
reg         prev_clk, prev_latch;

always @(posedge CLK) begin
  // sample the raw lines
  prev_clk   <= PORT_CLK;
  prev_latch <= PORT_LATCH;

  // on P/S Out falling edge: new frame → clear everything
  if (prev_latch & ~PORT_LATCH) begin
    shift16        <= 16'h0000;
    current_rumble <= 16'h0000;
  end

  // during frame (PORT_LATCH low), only for Port 1, shift in each PORT_CLK rising
  if (~prev_clk & PORT_CLK && ~PORT_LATCH && doing_port1) begin
    shift16 <= { shift16[14:0], PORT_P6 };
  end

  // whenever the top‑byte matches 0x72, latch the low nibble intensities
  if (shift16[15:8] == RUMBLE_SENTRY && doing_port1) begin
    // expand 4‑bit to 8‑bit by duplicating nibble
    current_rumble[15:8] <= { shift16[7:4], shift16[7:4] };   // large motor
    current_rumble[ 7:0] <= { shift16[3:0], shift16[3:0] };   // small motor
  end
end

// drive out the two‑byte rumble word
assign JOYSTICK1_RUMBLE = current_rumble;

// Mouse
wire dpad_mouse_sdy = JOYSTICK1[3];
wire dpad_mouse_sdx = JOYSTICK1[1];
wire [6:0] dpad_mouse_dy = JOYSTICK1[3] | JOYSTICK1[2] ? DPAD_AIM_SPEED[6:0] : 7'd0;
wire [6:0] dpad_mouse_dx = JOYSTICK1[0] | JOYSTICK1[1] ? DPAD_AIM_SPEED[6:0] : 7'd0;
wire joy_mouse_sdy = ~JOY_Y[7];
wire joy_mouse_sdx = ~JOY_X[7];
wire [6:0] joy_mouse_dy = joy_mouse_sdy ? (8'd128-JOY_Y) >> 4 : (JOY_Y[6:0]) >> 4;
wire [6:0] joy_mouse_dx = joy_mouse_sdx ? (8'd128-JOY_X) >> 4 : (JOY_X[6:0]) >> 4;
wire mouse_left = JOYSTICK1[5];
wire mouse_right = JOYSTICK1[4];

reg joystick_detected = 0;

reg  [1:0] speed = 0;
reg [31:0] MS_LATCH;
always @(posedge CLK) begin
	reg old_clk, old_latch;
	reg sdx,sdy;

	old_clk <= PORT_CLK;
	old_latch <= PORT_LATCH;

	if (JOY_Y || JOY_X)
		joystick_detected <= 1'b1;

	if(old_latch & ~PORT_LATCH) begin
		if(joystick_detected && (joy_mouse_dy + joy_mouse_dx > 0)) begin
			MS_LATCH <= ~{8'h00, mouse_left, mouse_right, speed, 4'b0001, joy_mouse_sdy, joy_mouse_dy, joy_mouse_sdx, joy_mouse_dx};
		end else begin
			MS_LATCH <= ~{8'h00, mouse_left, mouse_right, speed, 4'b0001, dpad_mouse_sdy, dpad_mouse_dy, dpad_mouse_sdx, dpad_mouse_dx};
		end
	end

	if(~old_clk & PORT_CLK) begin
		if(PORT_LATCH) begin
			speed <= speed + 1'd1;
			if(speed == 2) speed <= 0;
		end
		else MS_LATCH <= MS_LATCH << 1;
	end
end

endmodule