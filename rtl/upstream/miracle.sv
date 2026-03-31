/* Miracle Piano for MiSTER NES by GreyRogue. */

// Uses 512 byte ring buffers for receive and transmit
// Doesn't handle CTS/DTS, etc.
// Period is set by localparam (21.477MHz/31250Hz)

module miraclepiano (
  input  wire           clk,     //(Use 21.477 MHz clk for most things)
  input  wire           reset,
  input  wire           strobe,
  input  wire           joypad_clock,
  output wire           joypad_o, //untested
  input wire            txint,
  input wire            rxint,
  output reg            tdata_i,
  output wire [15:0]    tdata_m,
  input wire [15:0]     rdata_m
);

localparam [1:0] J_MODE=2'd0, J_READ=2'd1, J_WRITE=2'd2;

// r = from midi, t = to midi

reg rw;
reg [8:0] raddrr;
reg [8:0] raddrw;
wire [7:0] rdatar;
wire [7:0] rdataw;
wire rdata_empty = (raddrr == raddrw);
//wire rdata_full = (raddrr == (raddrw + 1'b1)); // Do something with this?

reg tinprogress;
reg tw;
reg [8:0] taddrr;
reg [8:0] taddrw;
wire [7:0] tdatar;
reg [7:0] tdataw;
wire tdata_empty = (taddrr == taddrw);
//wire tdata_full = (taddrr == (taddrw + 1'b1)); // Do something with this?

reg [15:0] joypad_bits;
assign joypad_o = ~joypad_bits[0];
// data_o clocking/shifting handled by nes.v
wire [ 15:0]   data_o;
assign data_o = ~{7'h00, rdatar[0], rdatar[1], rdatar[2], rdatar[3], rdatar[4], rdatar[5], rdatar[6], rdatar[7], rdata_empty};
assign tdata_m = {8'h01, tdatar};
assign rdataw = rdata_m[7:0];

reg last_txint;
reg last_rxint;
reg last_strobe;
reg last_joypad_clock;
reg [11:0] strobe_count;
reg [2:0] clock_count;
reg [1:0] mode;

always @ (posedge clk) begin
	last_txint <= txint;
	last_rxint <= rxint;
	last_strobe <= strobe;
	last_joypad_clock <= joypad_clock;
	rw <= 1'b0;
	tw <= 1'b0;
	tdata_i <= 1'b0;
	
	if (reset) begin
		raddrr <= 9'h000;
		raddrw <= 9'h000;
		taddrr <= 9'h000;
		taddrw <= 9'h000;
		strobe_count <= 0;
		tinprogress <= 0;
		mode <= J_READ;
	end else begin
		if (!tdata_empty && !tinprogress) begin
			tinprogress <= 1'b1;
			tdata_i <= 1'b1;
		end
		if (~txint && last_txint) begin
			taddrr <= taddrr + 1'b1;
			tinprogress <= 1'b0;
		end
		if (~rxint && last_rxint) begin
			rw <= 1'b1;
		end
		if (rw == 1'b1) begin
			raddrw <= raddrw + 1'b1;
		end
		if (tw == 1'b1) begin
			taddrw <= taddrw + 1'b1;
		end
		if (~last_strobe && strobe && (mode == J_READ)) begin
			strobe_count <= 8'h00;
			mode <= J_MODE;
		end
		if (last_strobe && strobe) begin
			strobe_count <= strobe_count + 1'b1;
		end
		if (((~strobe && last_strobe) || (strobe_count >= 12'd528)) && (mode == J_MODE)) begin
			// Assuming 21.477 MHz clk
			// Strobe Count 66 NES cycles = Write = 792
			// Strobe Count 12 NES cycles = Read  = 144
			// Strobe Count   SNES cycles = Write = 528
			// Strobe Count   SNES cycles = Read  = 102
			if (strobe_count >= 12'd256) begin  // Should be either 792 or 144 for NES
				clock_count <= 3'h0;
				mode <= J_WRITE;
			end else begin
				if (!rdata_empty)
					raddrr <= raddrr + 1'b1;
				mode <= J_READ;
			end
		end
		if (joypad_clock && !last_joypad_clock && (mode == J_WRITE)) begin
			if (clock_count < 3'h7) begin
				clock_count <= clock_count + 1'b1;
				tdataw <= {tdataw[6:0], strobe};
			end else begin //if (clock_count == 7) begin
				tw <= 1'b1;
				mode <= J_READ;
			end
		end
		if (strobe) begin
			joypad_bits <= data_o;
		end else if (!joypad_clock && last_joypad_clock) begin
			joypad_bits <= {1'b0, joypad_bits[15:1]};
		end
	end
end

dpram #(9)	inbuffer
(
	.clock(clk),
	.address_a(raddrw),
	.wren_a(rw),
	.data_a(rdataw),
	.q_a(),

	.address_b(raddrr),
	.q_b(rdatar),
	.wren_b(1'b0)
);

dpram #(9)	outbuffer
(
	.clock(clk),
	.address_a(taddrw),
	.wren_a(tw),
	.data_a({tdataw[6:0], strobe}),
	.q_a(),

	.address_b(taddrr),
	.q_b(tdatar),
	.wren_b(1'b0)
);

endmodule

