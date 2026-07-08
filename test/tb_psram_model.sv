// Behavioral async PSRAM model for the psram testbenches, 2 dies. Address
// latched while adv_n low with a CE active; writes commit on CE rise; reads
// drive DQ T_ACCESS after oe_n falls and release it T_TRI after the read.
//
// psram.sv is purely time-based (fixed read sample point, ignores cram_wait),
// so the model exposes what a zero-delay model hides:
//   - T_ACCESS_NS: OE-fall to data-valid. Sweep up to find how slow the part
//     can be before the fixed sample point latches stale/Z data.
//   - T_TRI_NS: OE-deassert to DQ high-Z (die-to-die turnaround). Raise it to
//     prove the single-controller topology never double-drives DQ.
// cram_wait is driven WAIT_CYCLES per access but ignored by psram.sv.

`timescale 1ns / 1ps

module tb_psram_model #(
    parameter integer DEPTH_LOG2  = 10,  // words per die = 2**DEPTH_LOG2
    parameter         T_ACCESS_NS = 15,  // oe_n fall -> read data valid
    parameter         T_TRI_NS    = 3,   // read end -> DQ high-Z (bus turnaround)
    parameter integer WAIT_CYCLES = 0    // clk cycles cram_wait held per access
) (
    input  wire         clk,
    input  wire [21:16] cram_a,
    inout  wire  [15:0] cram_dq,
    output reg          cram_wait,
    input  wire         cram_adv_n,
    input  wire         cram_ce0_n,
    input  wire         cram_ce1_n,
    input  wire         cram_oe_n,
    input  wire         cram_we_n,
    input  wire         cram_ub_n,
    input  wire         cram_lb_n,
    output reg  [31:0]  errors = 0
);

  reg [15:0] mem0[0:2**DEPTH_LOG2-1];
  reg [15:0] mem1[0:2**DEPTH_LOG2-1];

  reg [21:0] lat_addr;
  reg lat_die;
  reg op_we;
  reg [15:0] wr_data;
  reg wr_ub, wr_lb;

  wire ce_any = ~cram_ce0_n | ~cram_ce1_n;
  reg ce_any_q = 0;

  reg [15:0] dq_drive = 16'hzzzz;
  reg dq_oe = 0;
  assign cram_dq = dq_oe ? dq_drive : 16'hzzzz;

  wire read_active = ce_any & ~cram_oe_n & cram_we_n;

  // Protocol monitors
  always @(posedge clk) begin
    if (~cram_ce0_n && ~cram_ce1_n) begin
      errors = errors + 1;
      $display("FAIL: both CE low at %t", $time);
    end
    // Model driving while the controller also drives address/data on DQ
    if (dq_oe && cram_dq !== dq_drive) begin
      errors = errors + 1;
      $display("FAIL: DQ contention at %t", $time);
    end
  end

  // Address latch (sampled on clk like the controller drives it)
  always @(posedge clk) begin
    ce_any_q <= ce_any;

    if (ce_any && ~cram_adv_n) begin
      lat_addr <= {cram_a, cram_dq[15:0]};
      lat_die  <= ~cram_ce1_n;
      op_we    <= ~cram_we_n;
    end

    if (ce_any && ~cram_we_n && cram_adv_n && cram_dq !== 16'hzzzz) begin
      wr_data <= cram_dq;
      wr_ub   <= ~cram_ub_n;
      wr_lb   <= ~cram_lb_n;
    end

    // Commit on CE rise
    if (ce_any_q && ~ce_any && op_we) begin
      if (lat_die) begin
        if (wr_ub) mem1[lat_addr[DEPTH_LOG2-1:0]][15:8] <= wr_data[15:8];
        if (wr_lb) mem1[lat_addr[DEPTH_LOG2-1:0]][7:0]  <= wr_data[7:0];
      end else begin
        if (wr_ub) mem0[lat_addr[DEPTH_LOG2-1:0]][15:8] <= wr_data[15:8];
        if (wr_lb) mem0[lat_addr[DEPTH_LOG2-1:0]][7:0]  <= wr_data[7:0];
      end
    end
  end

  // Read path: drive after T_ACCESS, release after T_TRI
  always @(*) begin
    if (read_active) begin
      dq_oe    <= #T_ACCESS_NS 1'b1;
      dq_drive <= #T_ACCESS_NS (lat_die ? mem1[lat_addr[DEPTH_LOG2-1:0]]
                                        : mem0[lat_addr[DEPTH_LOG2-1:0]]);
    end else begin
      dq_oe    <= #T_TRI_NS 1'b0;
      dq_drive <= #T_TRI_NS 16'hzzzz;
    end
  end

  // cram_wait: assert on access latch, hold WAIT_CYCLES, drop. Observational
  // only (psram.sv ignores it); WAIT_CYCLES == 0 is the old tie-off.
  integer wait_cnt = 0;
  initial cram_wait = 0;
  always @(posedge clk) begin
    if (ce_any && ~cram_adv_n && WAIT_CYCLES != 0) begin
      cram_wait <= 1;
      wait_cnt  <= WAIT_CYCLES;
    end else if (wait_cnt != 0) begin
      wait_cnt <= wait_cnt - 1;
      if (wait_cnt == 1) cram_wait <= 0;
    end
  end

endmodule
