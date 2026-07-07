// Wraps sram engine in the psram-style level interface ARAM expects
module sram_ctrl #(
    parameter MIN_OP_CYCLE_TIME_NANO_SEC = 55
) (
    input wire clk,

    input wire [14:0] addr,

    input wire write_en,
    input wire [15:0] data_in,
    input wire write_high_byte,
    input wire write_low_byte,

    input wire read_en,
    output wire [15:0] data_out,

    // Async SRAM interface
    output wire [16:0] sram_a,
    inout wire [15:0] sram_dq,
    output wire sram_oe_n,
    output wire sram_we_n,
    output wire sram_ub_n,
    output wire sram_lb_n
);

  wire ready;

  sram #(
      .CLOCK_SPEED_MHZ(85.9),
      .MIN_OP_CYCLE_TIME_NANO_SEC(MIN_OP_CYCLE_TIME_NANO_SEC)
  ) sram (
      .clk(clk),
      .reset(1'b0),

      // Writes drive their byte lanes; reads always fetch the full word
      .mask(write_en ? {write_high_byte, write_low_byte} : 2'b11),
      .wr(ready & write_en),
      .rd(ready & ~write_en & read_en),

      .addr({2'b0, addr}),
      .data(data_in),
      .q(data_out),
      .ready(ready),

      .sram_a(sram_a),
      .sram_dq(sram_dq),
      .sram_oe_n(sram_oe_n),
      .sram_we_n(sram_we_n),
      .sram_ub_n(sram_ub_n),
      .sram_lb_n(sram_lb_n)
  );

endmodule
