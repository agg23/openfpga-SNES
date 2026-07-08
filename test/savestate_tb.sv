// Testbench for savestate (with its embedded psram_blob) over a behavioral
// PSRAM model. Checks engine handshake budgets, blob/stage data integrity, the
// 8'hF0 header byte enables, the unloader sample budget (measures the blob read
// latency behind READ_MEM_CLOCK_DELAY), the stage FIFO, and read/write ordering.
//
// The blob lives on cram die 0 (bank_sel = 0 -> model mem0).

`timescale 1ns / 1ps

module synch_3 #(
    parameter WIDTH = 1
) (
    input wire [WIDTH-1:0] i,
    output reg [WIDTH-1:0] o,
    input wire clk,
    output wire rise,
    output wire fall
);
  reg [WIDTH-1:0] s1, s2;
  always @(posedge clk) begin
    s1 <= i;
    s2 <= s1;
    o  <= s2;
  end
  assign rise = 0;
  assign fall = 0;
endmodule

module savestate_tb #(
    // PSRAM timing knobs (see tb_psram_model): sweep T_ACCESS_NS to probe the
    // unloader sample budget, raise T_TRI_NS to stress bus turnaround
    parameter T_ACCESS_NS = 15,
    parameter T_TRI_NS = 3,
    parameter integer WAIT_CYCLES = 0
) ();
  reg clk_sys = 0;
  reg clk_mem = 0;

  always #23.28 clk_sys = ~clk_sys;  // 21.48 MHz
  always #5.82 clk_mem = ~clk_mem;  // 85.9 MHz

  // engine side
  reg [63:0] ss_ddr_do = 0;
  reg [21:3] ss_ddr_addr = 0;
  reg [7:0] ss_ddr_be = 8'hFF;
  reg ss_ddr_we = 0;
  reg ss_ddr_req = 0;
  wire [63:0] ss_ddr_di;
  wire ss_ddr_ack;

  reg ss_busy = 0;

  reg stage_wr = 0;
  reg [19:0] stage_addr = 0;
  reg [15:0] stage_data = 0;

  reg blob_rd = 0;
  reg [19:0] blob_addr = 0;
  wire [15:0] blob_q;
  wire stage_lost;

  wire [21:16] cram_a;
  wire [15:0] cram_dq;
  wire cram_clk, cram_adv_n, cram_cre, cram_ce0_n, cram_ce1_n;
  wire cram_oe_n, cram_we_n, cram_ub_n, cram_lb_n;
  wire cram_wait_w;

  savestate dut (
      .clk_sys(clk_sys),
      .clk_mem(clk_mem),
      .ss_ddr_do(ss_ddr_do),
      .ss_ddr_addr(ss_ddr_addr),
      .ss_ddr_be(ss_ddr_be),
      .ss_ddr_we(ss_ddr_we),
      .ss_ddr_req(ss_ddr_req),
      .ss_ddr_di(ss_ddr_di),
      .ss_ddr_ack(ss_ddr_ack),
      .ss_busy(ss_busy),
      .blocked(1'b0),
      .ctrl_idle(1'b1),
      .stage_lost(stage_lost),
      .stage_wr(stage_wr),
      .stage_addr(stage_addr),
      .stage_data(stage_data),
      .blob_rd(blob_rd),
      .blob_addr(blob_addr),
      .blob_q(blob_q),
      .cram_a(cram_a),
      .cram_dq(cram_dq),
      .cram_wait(cram_wait_w),
      .cram_clk(cram_clk),
      .cram_adv_n(cram_adv_n),
      .cram_cre(cram_cre),
      .cram_ce0_n(cram_ce0_n),
      .cram_ce1_n(cram_ce1_n),
      .cram_oe_n(cram_oe_n),
      .cram_we_n(cram_we_n),
      .cram_ub_n(cram_ub_n),
      .cram_lb_n(cram_lb_n)
  );

  // ---------------------------------------------------------------------
  // Behavioral async PSRAM, 2 dies (blob is on die 0 = mem0).
  // ---------------------------------------------------------------------
  wire [31:0] mon_errors;
  integer errors = 0;  // task-level check failures

  tb_psram_model #(
      .DEPTH_LOG2 (12),
      .T_ACCESS_NS(T_ACCESS_NS),
      .T_TRI_NS   (T_TRI_NS),
      .WAIT_CYCLES(WAIT_CYCLES)
  ) psram_model (
      .clk(clk_mem),
      .cram_a(cram_a),
      .cram_dq(cram_dq),
      .cram_wait(cram_wait_w),
      .cram_adv_n(cram_adv_n),
      .cram_ce0_n(cram_ce0_n),
      .cram_ce1_n(cram_ce1_n),
      .cram_oe_n(cram_oe_n),
      .cram_we_n(cram_we_n),
      .cram_ub_n(cram_ub_n),
      .cram_lb_n(cram_lb_n),
      .errors(mon_errors)
  );

  // ---------------------------------------------------------------------
  // Engine-accurate tasks (from save_state_mem_tb)
  // ---------------------------------------------------------------------
  task eng_write(input [16:0] qaddr, input [63:0] data);
    integer waits;
    begin
      @(posedge clk_sys);
      ss_ddr_addr <= {1'b0, 1'b0, qaddr};
      ss_ddr_do <= data;
      ss_ddr_we <= 1;
      ss_ddr_req <= ~ss_ddr_req;
      @(posedge clk_sys);
      ss_ddr_we <= 0;  // exactly one cycle, like savestates.sv
      @(posedge clk_sys);
      @(posedge clk_sys);
      ss_ddr_do <= 64'h00000000000000AA;  // next byte mangles the data port
      waits = 0;
      while (ss_ddr_req != ss_ddr_ack) begin
        @(posedge clk_sys);
        waits = waits + 1;
        if (waits > 64) begin
          $display("FAIL: write ack timeout qaddr=%0d", qaddr);
          errors = errors + 1;
          disable eng_write;
        end
      end
    end
  endtask

  task eng_read(input [16:0] qaddr, output [63:0] data, output integer lat);
    begin
      @(posedge clk_sys);
      ss_ddr_addr <= {1'b0, 1'b0, qaddr};
      ss_ddr_we <= 0;
      ss_ddr_req <= ~ss_ddr_req;
      lat = 0;
      @(posedge clk_sys);
      while (ss_ddr_req != ss_ddr_ack) begin
        @(posedge clk_sys);
        lat = lat + 1;
        if (lat > 1000) begin
          $display("FAIL: read ack timeout qaddr=%0d", qaddr);
          errors = errors + 1;
          disable eng_read;
        end
      end
      data = ss_ddr_di;
    end
  endtask

  function [63:0] pattern(input [16:0] q);
    pattern = {4{13'h0AB5, q[15:0]}} ^ 64'h0123456789ABCDEF;
  endfunction

  function [63:0] qw(input integer q);
    qw = {psram_model.mem0[q*4+3], psram_model.mem0[q*4+2], psram_model.mem0[q*4+1], psram_model.mem0[q*4]};
  endfunction

  integer i, lat, err_snap;
  reg [63:0] rd_data;
  integer worst_hit_lat, worst_blob_lat, k;

  initial begin
    $dumpfile("savestate_tb.vcd");
    $dumpvars(0, dut);

    for (i = 0; i < 2 ** 12; i = i + 1) begin
      psram_model.mem0[i] = i[15:0] ^ 16'hA55A;
      psram_model.mem1[i] = 16'h0000;
    end

    repeat (10) @(posedge clk_mem);

    // ------------------------------------------------------------------
    // SAVE: body qwords 1..63 at DMA pace, header last
    ss_busy = 1;
    for (i = 1; i < 64; i = i + 1) begin
      eng_write(i[16:0], pattern(i[16:0]));
      repeat (30) @(posedge clk_sys);  // DMA pace
    end
    eng_write(17'd0, 64'h00010200_00000001);  // WRITE_CNTSIZE
    ss_busy = 0;
    repeat (40) @(posedge clk_sys);

    err_snap = errors;
    for (i = 1; i < 64; i = i + 1) begin
      if (qw(i) != pattern(i[16:0])) begin
        $display("FAIL: save qword %0d = %h expected %h", i, qw(i), pattern(i[16:0]));
        errors = errors + 1;
      end
    end
    if (qw(0) != 64'h00010200_00000001) begin
      $display("FAIL: header qword = %h", qw(0));
      errors = errors + 1;
    end else if (errors == err_snap) $display("PASS: save, header last");

    // ------------------------------------------------------------------
    // Byte enables: 8'hF0 header rewrite preserves the count field
    ss_busy   = 1;
    ss_ddr_be = 8'hF0;
    eng_write(17'd0, 64'hDEADBEEF_A5A55A5A);
    ss_ddr_be = 8'hFF;
    ss_busy   = 0;
    repeat (40) @(posedge clk_sys);
    if ({psram_model.mem0[3], psram_model.mem0[2]} != 32'hDEADBEEF) begin
      $display("FAIL: BE write upper half = %h", {psram_model.mem0[3], psram_model.mem0[2]});
      errors = errors + 1;
    end else if ({psram_model.mem0[1], psram_model.mem0[0]} != 32'h00000001) begin
      $display("FAIL: BE write clobbered the count field: %h", {psram_model.mem0[1], psram_model.mem0[0]});
      errors = errors + 1;
    end else $display("PASS: byte enables skip the masked half words");

    // ------------------------------------------------------------------
    // READBACK (held read_en): measure the latency to blob_q behind READ_MEM_CLOCK_DELAY
    err_snap = errors;
    worst_blob_lat = 0;
    for (i = 0; i < 64; i = i + 1) begin
      @(posedge clk_mem);
      blob_addr <= i[19:0] * 2;
      blob_rd   <= 1;  // hold the level like READ_MEM_CLOCK_DELAY
      k = 0;
      repeat (48) @(posedge clk_mem) begin
        k = k + 1;
        if (blob_q !== psram_model.mem0[i] && k > worst_blob_lat) worst_blob_lat = k;
      end
      if (blob_q !== psram_model.mem0[i]) begin
        $display("FAIL: held read %0d = %h expected %h", i, blob_q, psram_model.mem0[i]);
        errors = errors + 1;
      end
      blob_rd <= 0;
      repeat (3) @(posedge clk_mem);
    end
    if (errors == err_snap)
      $display("PASS: unloader reads land (worst %0d clk_mem -> READ_MEM_CLOCK_DELAY margin)",
               worst_blob_lat);

    // ------------------------------------------------------------------
    // LOAD staging at loader pace (16 clk_mem/word): FIFO must not overflow
    err_snap = errors;
    for (i = 0; i < 640; i = i + 1) begin
      @(posedge clk_mem);
      stage_addr <= (i[19:0] & 20'hFFF) * 2;
      stage_data <= 16'hC000 | i[15:0];
      stage_wr   <= 1;
      @(posedge clk_mem);
      stage_wr <= 0;
      repeat (14) @(posedge clk_mem);
    end
    k = 0;
    while (dut.stage_wp != dut.stage_rp && k < 40000) begin
      @(posedge clk_mem);
      k = k + 1;
    end
    if (dut.stage_wp != dut.stage_rp) begin
      $display("FAIL: stage FIFO never drained");
      errors = errors + 1;
    end
    repeat (100) @(posedge clk_mem);
    for (i = 640 - 4096 >= 0 ? 640 - 4096 : 0; i < 640 && i < 4096; i = i + 1) begin
      if (psram_model.mem0[i] != (16'hC000 | i[15:0])) begin
        $display("FAIL: staged word %0d = %h", i, psram_model.mem0[i]);
        errors = errors + 1;
      end
    end
    if (stage_lost) begin
      $display("FAIL: stage FIFO overflowed at loader pace");
      errors = errors + 1;
    end
    if (errors == err_snap) $display("PASS: staging drains at loader pace");

    // ------------------------------------------------------------------
    // Ordering: an engine read must not overtake still-queued staged writes.
    // Burst 64 words so a backlog is guaranteed, qword 2 last, then read it.
    err_snap = errors;
    for (i = 0; i < 64; i = i + 1) begin
      @(posedge clk_mem);
      stage_addr <= (i < 60 ? (20'd100 + i[19:0]) : (20'd8 + (i[19:0] - 60))) * 2;
      stage_data <= 16'h7E00 | i[15:0];
      stage_wr   <= 1;
      @(posedge clk_mem);
      stage_wr <= 0;
    end
    eng_read(17'd2, rd_data, lat);
    if (rd_data != {16'h7E3F, 16'h7E3E, 16'h7E3D, 16'h7E3C}) begin
      $display("FAIL: engine read overtook staged writes: %h", rd_data);
      errors = errors + 1;
    end
    if (errors == err_snap) $display("PASS: engine read waits out the staged backlog");

    // ------------------------------------------------------------------
    // LOAD stream: header read, SSADDR re-read, DMA-paced stream; hits must
    // ack inside the no-wait budget
    ss_busy = 1;
    worst_hit_lat = 0;

    eng_read(17'd1, rd_data, lat);  // READ_HEAD
    if (rd_data != qw(1)) begin
      $display("FAIL: READ_HEAD data %h expected %h", rd_data, qw(1));
      errors = errors + 1;
    end

    eng_read(17'd1, rd_data, lat);  // engine re-reads qword 1 after SSADDR
    if (rd_data != qw(1)) begin
      $display("FAIL: addr-8 re-read data %h", rd_data);
      errors = errors + 1;
    end

    for (i = 2; i < 64; i = i + 1) begin
      repeat (56) @(posedge clk_sys);  // rest of the qword's DMA time
      eng_read(i[16:0], rd_data, lat);
      if (rd_data != qw(i)) begin
        $display("FAIL: stream qword %0d = %h expected %h", i, rd_data, qw(i));
        errors = errors + 1;
      end
      if (lat > worst_hit_lat) worst_hit_lat = lat;
    end
    if (worst_hit_lat > 8) begin
      $display("FAIL: stream hit latency %0d clk_sys (no-wait budget ~8)", worst_hit_lat);
      errors = errors + 1;
    end else $display("PASS: load stream, worst hit %0d clk_sys", worst_hit_lat);
    ss_busy = 0;
    repeat (200) @(posedge clk_mem);

    if (errors == 0 && mon_errors == 0) $display("PASS");
    else $display("FAIL: %0d task + %0d model errors", errors, mon_errors);
    $finish;
  end

  initial begin
    #12_000_000;
    $display("FAIL: timeout");
    $finish;
  end

endmodule
