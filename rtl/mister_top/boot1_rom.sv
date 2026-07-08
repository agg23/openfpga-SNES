// The savestate CPU program, baked into BRAM
module boot1_rom (
    input wire clk,

    input wire [11:0] addr,
    input wire word,
    output reg [15:0] q = 0
);
  wire [15:0] rom_q;
  reg addr0;

  spram #(
      .addr_width(11),
      .data_width(16),
      .mem_init_file("rtl/mister_top/boot1.mif")
  ) rom (
      .clock(clk),
      .address(addr[11:1]),
      .q(rom_q)
  );

  // The MIF stores little-endian words; a byte read on an odd address swaps
  // the lanes, matching the byte muxing in sdram.sv
  always @(posedge clk) begin
    addr0 <= addr[0];
    q <= (~word & addr0) ? {rom_q[7:0], rom_q[15:8]} : rom_q;
  end
endmodule
