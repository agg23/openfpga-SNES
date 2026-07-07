// Exercises sram_ctrl against AS6C2016-style tAA/tOH behavior.

`timescale 1ns / 1ps

// Behavioral async SRAM (AS6C2016-55 style).
module tb_sram_async #(
    parameter integer DEPTH_LOG2 = 12,
    parameter T_AA_NS = 55,  // address/OE -> valid read data
    parameter T_OH_NS = 4    // OE deassert -> DQ high-Z (bus turnaround)
) (
    input  wire        clk,
    input  wire [16:0] a,
    inout  wire [15:0] dq,
    input  wire        oe_n,
    input  wire        we_n,
    input  wire        ub_n,
    input  wire        lb_n,
    output reg  [31:0] errors = 0
);
  reg [15:0] mem[0:(1<<DEPTH_LOG2)-1];

  reg [15:0] dq_drive = 16'hzzzz;
  reg dq_oe = 0;
  assign dq = dq_oe ? dq_drive : 16'hzzzz;

  wire [DEPTH_LOG2-1:0] idx = a[DEPTH_LOG2-1:0];
  wire rd_active = ~oe_n & we_n;

  // Read path honours tAA, the timing the engine's fixed op latency must cover
  always @(*) begin
    if (rd_active) begin
      dq_oe    <= #T_AA_NS 1'b1;
      dq_drive <= #T_AA_NS mem[idx];
    end else begin
      dq_oe    <= #T_OH_NS 1'b0;
      dq_drive <= #T_OH_NS 16'hzzzz;
    end
  end

  // Byte-lane write commit: the engine holds we_n/byte enables and a stable
  // address+data for the op, so committing the driven byte each clk matches
  // the part's address/WE-controlled write
  always @(posedge clk) begin
    if (~we_n && oe_n) begin
      if (~ub_n) mem[idx][15:8] <= dq[15:8];
      if (~lb_n) mem[idx][7:0]  <= dq[7:0];
    end
    if (dq_oe && ~we_n) begin
      errors <= errors + 1;
      $display("FAIL: DQ contention (model + controller drive) at %t", $time);
    end
  end
endmodule

module sram_ctrl_tb #(
    parameter T_AA_NS = 55
) ();
  reg clk = 0;
  always #5.82 clk = ~clk;  // 85.9 MHz

  reg [14:0] c_addr = 0;
  reg c_wen = 0, c_ren = 0;
  reg [15:0] c_din = 0;
  reg c_wh = 1, c_wl = 1;
  wire [15:0] c_dout;

  wire [16:0] sram_a;
  wire [15:0] sram_dq;
  wire sram_oe_n, sram_we_n, sram_ub_n, sram_lb_n;
  wire [31:0] mon_errors;

  sram_ctrl dut (
      .clk(clk),
      .addr(c_addr),
      .write_en(c_wen),
      .data_in(c_din),
      .write_high_byte(c_wh),
      .write_low_byte(c_wl),
      .read_en(c_ren),
      .data_out(c_dout),
      .sram_a(sram_a),
      .sram_dq(sram_dq),
      .sram_oe_n(sram_oe_n),
      .sram_we_n(sram_we_n),
      .sram_ub_n(sram_ub_n),
      .sram_lb_n(sram_lb_n)
  );

  tb_sram_async #(
      .DEPTH_LOG2(12),
      .T_AA_NS(T_AA_NS)
  ) sram (
      .clk(clk),
      .a(sram_a),
      .dq(sram_dq),
      .oe_n(sram_oe_n),
      .we_n(sram_we_n),
      .ub_n(sram_ub_n),
      .lb_n(sram_lb_n),
      .errors(mon_errors)
  );

  integer errors = 0;

  task wr_word(input [14:0] addr, input [15:0] data, input hi, input lo);
    begin
      @(posedge clk);
      c_addr <= addr;
      c_din  <= data;
      c_wh   <= hi;
      c_wl   <= lo;
      c_wen  <= 1;
      repeat (10) @(posedge clk);  // > one op
      c_wen <= 0;
      @(posedge clk);
    end
  endtask

  task rd_word(input [14:0] addr, output [15:0] data);
    begin
      @(posedge clk);
      c_addr <= addr;
      c_ren  <= 1;
      repeat (12) @(posedge clk);  // > one op + settle
      data  = c_dout;
      c_ren <= 0;
      @(posedge clk);
    end
  endtask

  integer i;
  reg [15:0] got;

  initial begin
    $dumpfile("sram_ctrl_tb.vcd");
    $dumpvars(0, dut);

    for (i = 0; i < 4096; i = i + 1) sram.mem[i] = 16'h0000;

    repeat (10) @(posedge clk);

    // Full-word write/read
    for (i = 0; i < 32; i = i + 1) wr_word(i[14:0], 16'hBE00 | i[15:0], 1, 1);
    for (i = 0; i < 32; i = i + 1) begin
      rd_word(i[14:0], got);
      if (got !== (16'hBE00 | i[15:0])) begin
        $display("FAIL: word %0d = %h expected %h", i, got, 16'hBE00 | i[15:0]);
        errors = errors + 1;
      end
    end

    // Byte lanes: rewrite high byte only, then low byte only, at addr 5
    wr_word(15'd5, 16'hFFFF, 1, 1);
    wr_word(15'd5, 16'hAB00, 1, 0);  // high byte only
    rd_word(15'd5, got);
    if (got !== 16'hABFF) begin
      $display("FAIL: high-byte-only write = %h expected ABFF", got);
      errors = errors + 1;
    end
    wr_word(15'd5, 16'h00CD, 0, 1);  // low byte only
    rd_word(15'd5, got);
    if (got !== 16'hABCD) begin
      $display("FAIL: low-byte-only write = %h expected ABCD", got);
      errors = errors + 1;
    end

    // Clear sweep: held write_en with a stepping address (RAM-clear path)
    @(posedge clk);
    c_wh  <= 1;
    c_wl  <= 1;
    c_din <= 16'h9966;
    c_wen <= 1;
    for (i = 0; i < 64; i = i + 1) begin
      c_addr <= 15'd1000 + i[14:0];
      repeat (16) @(posedge clk);  // held per address like clear_div
    end
    c_wen <= 0;
    @(posedge clk);
    for (i = 0; i < 64; i = i + 1) begin
      if (sram.mem[1000+i] !== 16'h9966) begin
        $display("FAIL: clear sweep addr %0d = %h", 1000 + i, sram.mem[1000+i]);
        errors = errors + 1;
      end
    end

    // Re-establish words 0..15 (addr 5 was clobbered by the byte-lane test)
    for (i = 0; i < 16; i = i + 1) wr_word(i[14:0], 16'hBE00 | i[15:0], 1, 1);

    // Held-read freshness: keep read_en high, step the address, data_out must
    // track once it settles. The APU holds an ARAM address ~977 ns (>> one op),
    // so allow two back-to-back ops when the address changes mid-op.
    @(posedge clk);
    c_ren <= 1;
    for (i = 0; i < 16; i = i + 1) begin
      c_addr <= i[14:0];
      repeat (24) @(posedge clk);
      if (c_dout !== (16'hBE00 | i[15:0])) begin
        $display("FAIL: held-read addr %0d = %h expected %h", i, c_dout, 16'hBE00 | i[15:0]);
        errors = errors + 1;
      end
    end
    c_ren <= 0;

    repeat (20) @(posedge clk);
    if (errors == 0 && mon_errors == 0) $display("PASS");
    else $display("FAIL: %0d task + %0d model errors", errors, mon_errors);
    $finish;
  end

  initial begin
    #2_000_000;
    $display("FAIL: timeout");
    $finish;
  end

endmodule
