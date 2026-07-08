// Testbench for save_state_controller: drives the APF handshake and bridge
// activity patterns and a fake engine, checks sequencing and status codes.

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

module tb_ss_ctrl;
  reg clk_74a = 0;
  reg clk_sys = 0;
  always #6.73 clk_74a = ~clk_74a;  // 74.25
  always #23.28 clk_sys = ~clk_sys;  // 21.48

  reg bridge_rd = 0, bridge_wr = 0;
  reg [31:0] bridge_addr = 0;

  reg savestate_load = 0, savestate_start = 0;
  wire l_ack, l_busy, l_ok, l_err;
  wire s_ack, s_busy, s_ok, s_err;

  reg ss_allow = 1;
  reg ss_busy = 0;
  reg stage_lost = 0;
  wire ss_save, ss_load, ss_idle;

  save_state_controller #(
      .TIMEOUT_TRIGGER(28'd200_000),
      .TIMEOUT_WALK(28'd800_000),
      .TIMEOUT_READBACK(28'd1_000_000)
  ) dut (
      .clk_74a(clk_74a),
      .clk_sys_21_48(clk_sys),
      .bridge_rd(bridge_rd),
      .bridge_wr(bridge_wr),
      .bridge_addr(bridge_addr),
      .ss_size(32'h1000),  // small for sim speed
      .savestate_load(savestate_load),
      .savestate_load_ack_s(l_ack),
      .savestate_load_busy_s(l_busy),
      .savestate_load_ok_s(l_ok),
      .savestate_load_err_s(l_err),
      .savestate_start(savestate_start),
      .savestate_start_ack_s(s_ack),
      .savestate_start_busy_s(s_busy),
      .savestate_start_ok_s(s_ok),
      .savestate_start_err_s(s_err),
      .ss_allow(ss_allow),
      .ss_busy(ss_busy),
      .stage_lost(stage_lost),
      .ss_save(ss_save),
      .ss_load(ss_load),
      .ss_idle(ss_idle)
  );

  integer errors = 0;

  // fake engine: on a pulse go busy after an NMI delay, stay busy a while.
  // Like the real engine, a pulse is swallowed while a request is armed or a
  // walk runs, and a console reset clears the latch.
  reg pend_walk = 0;
  integer nmi_delay = 300;
  integer nmi_cnt = 0, walk_cnt = 0;
  reg reject_load = 0;
  always @(posedge clk_sys) begin
    if (ss_save && !pend_walk && !ss_busy) begin
      pend_walk <= 1;
      nmi_cnt   <= nmi_delay;
    end
    if (ss_load && !reject_load && !pend_walk && !ss_busy) begin
      pend_walk <= 1;
      nmi_cnt   <= nmi_delay;
    end
    if (pend_walk) begin
      if (nmi_cnt > 0) nmi_cnt <= nmi_cnt - 1;
      else begin
        pend_walk <= 0;
        ss_busy   <= 1;
        walk_cnt  <= 2000;
      end
    end
    if (ss_busy) begin
      if (walk_cnt > 0) walk_cnt <= walk_cnt - 1;
      else ss_busy <= 0;
    end
    if (!ss_allow) begin
      pend_walk <= 0;
      ss_busy   <= 0;
    end
  end

  // Controller must never trigger while the latch is armed, else the engine
  // swallows it and the walk is misattributed
  always @(posedge clk_sys) begin
    if ((ss_save || ss_load) && (pend_walk || ss_busy)) begin
      $display("FAIL: trigger pulsed while engine latch armed");
      errors = errors + 1;
    end
  end

  task bridge_write_burst(input integer words);
    integer k;
    begin
      for (k = 0; k < words; k = k + 1) begin
        @(posedge clk_74a);
        bridge_addr <= 32'h40000000 + k * 4;
        bridge_wr   <= 1;
        @(posedge clk_74a);
        bridge_wr <= 0;
        repeat (70) @(posedge clk_74a);
      end
    end
  endtask

  task bridge_write_all;
    integer k;
    begin
      for (k = 0; k < 'h1000 / 4; k = k + 1) begin
        @(posedge clk_74a);
        bridge_addr <= 32'h40000000 + k * 4;
        bridge_wr   <= 1;
        @(posedge clk_74a);
        bridge_wr <= 0;
        repeat (10) @(posedge clk_74a);
      end
    end
  endtask

  task bridge_read_all;
    integer k;
    begin
      for (k = 0; k < 'h1000 / 4; k = k + 1) begin
        @(posedge clk_74a);
        bridge_addr <= 32'h40000000 + k * 4;
        bridge_rd   <= 1;
        @(posedge clk_74a);
        bridge_rd <= 0;
        repeat (30) @(posedge clk_74a);
      end
    end
  endtask

  integer guard;
  integer scen_errors;

  task wait_ok(input is_load, input integer max_us);
    begin
      guard = 0;
      while (guard < max_us * 149 && !(is_load ? (l_ok | l_err) : (s_ok | s_err))) begin
        @(posedge clk_74a);
        guard = guard + 1;
      end
      if (is_load ? l_err : s_err) begin
        $display("FAIL: got err instead of ok");
        errors = errors + 1;
      end else if (!(is_load ? l_ok : s_ok)) begin
        $display("FAIL: timeout waiting ok");
        errors = errors + 1;
      end
    end
  endtask

  // Full happy-path save: command, ok, readback. Waits out a stale err flag
  // from an earlier scenario first.
  task start_and_expect_ok;
    begin
      savestate_start <= 1;
      guard = 0;
      while (!s_ack && guard < 10000) begin
        @(posedge clk_74a);
        guard = guard + 1;
      end
      if (!s_ack) begin
        $display("FAIL: no start ack");
        errors = errors + 1;
      end
      savestate_start <= 0;
      guard = 0;
      while (s_err && guard < 1000) begin
        @(posedge clk_74a);
        guard = guard + 1;
      end
      wait_ok(0, 3000);
      bridge_read_all;
      guard = 0;
      while (!ss_idle && guard < 100000) begin
        @(posedge clk_74a);
        guard = guard + 1;
      end
      if (!ss_idle) begin
        $display("FAIL: not idle after readback");
        errors = errors + 1;
      end
    end
  endtask

  reg ss_load_fired = 0;
  always @(posedge clk_sys) begin
    if (ss_load) ss_load_fired <= 1;
  end

  initial begin
    // Let the allow window settle (allow_cnt[6], 64 clk_sys) as the real
    // firmware always does before its first command
    repeat (80) @(posedge clk_sys);

    // ---------------- SAVE flow ----------------
    savestate_start <= 1;
    // firmware holds the request until ack
    guard = 0;
    while (!s_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    if (!s_ack) begin
      $display("FAIL: no start ack");
      errors = errors + 1;
    end
    savestate_start <= 0;

    wait_ok(0, 3000);
    bridge_read_all;
    // reading the last word should return the sequencer to idle
    guard = 0;
    while (!ss_idle && guard < 100000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    if (!ss_idle) begin
      $display("FAIL: not idle after readback");
      errors = errors + 1;
    end else $display("PASS: save flow (ok + idle on last read)");

    repeat (1000) @(posedge clk_74a);

    // ---------------- LOAD flow, data first ----------------
    ss_load_fired = 0;
    bridge_write_burst(16);
    if (ss_idle) begin
      $display("FAIL: staging not tracked (still idle)");
      errors = errors + 1;
    end
    bridge_write_all;
    savestate_load <= 1;
    guard = 0;
    while (!l_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    if (!l_ack) begin
      $display("FAIL: no load ack");
      errors = errors + 1;
    end
    savestate_load <= 0;
    wait_ok(1, 60000);
    if (!ss_load_fired) begin
      $display("FAIL: ss_load never fired");
      errors = errors + 1;
    end else $display("PASS: load flow data-first");

    repeat (1000) @(posedge clk_74a);

    // ---------------- LOAD flow, command first ----------------
    ss_load_fired = 0;
    savestate_load <= 1;
    guard = 0;
    while (!l_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    savestate_load <= 0;
    bridge_write_all;
    wait_ok(1, 60000);
    if (!ss_load_fired) begin
      $display("FAIL: cmd-first: ss_load never fired");
      errors = errors + 1;
    end else $display("PASS: load flow command-first");

    repeat (1000) @(posedge clk_74a);

    // ---------------- LOAD with truncated stream ----------------
    // Firmware never reaches the last word: no ss_load, timeout error
    savestate_load <= 1;
    guard = 0;
    while (!l_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    savestate_load <= 0;
    bridge_write_burst(16);
    guard = 0;
    while (!(l_ok | l_err) && guard < 60000000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    if (!l_err) begin
      $display("FAIL: truncated stream did not produce err");
      errors = errors + 1;
    end else $display("PASS: truncated stream reports Loading failed");
    if (!ss_idle) begin
      $display("FAIL: not idle after truncated stream");
      errors = errors + 1;
    end

    repeat (1000) @(posedge clk_74a);

    // ---------------- LOAD with bad blob (engine never goes busy) --------
    reject_load = 1;
    bridge_write_all;
    savestate_load <= 1;
    guard = 0;
    while (!l_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    savestate_load <= 0;
    guard = 0;
    while (!(l_ok | l_err) && guard < 60000000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    if (!l_err) begin
      $display("FAIL: bad blob did not produce err");
      errors = errors + 1;
    end else $display("PASS: bad blob reports Loading failed");
    reject_load = 0;

    // The engine never armed on the rejected blob, so the next command works
    // with no reset between; command-first staging sidesteps the write monostable
    repeat (100) @(posedge clk_74a);
    savestate_load <= 1;
    guard = 0;
    while (!l_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    savestate_load <= 0;
    bridge_write_all;
    wait_ok(1, 60000);
    $display("PASS: load retry works right after the timeout error");

    // ---------------- LOAD with torn blob (staging lost data) ------------
    // Cart download overlapped staging: controller must error, not restore
    ss_load_fired = 0;
    stage_lost = 1;
    savestate_load <= 1;
    guard = 0;
    while (!l_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    savestate_load <= 0;
    bridge_write_all;
    guard = 0;
    while (!(l_ok | l_err) && guard < 60000000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    if (!l_err) begin
      $display("FAIL: torn blob did not produce err");
      errors = errors + 1;
    end else if (ss_load_fired) begin
      $display("FAIL: torn blob still triggered ss_load");
      errors = errors + 1;
    end else $display("PASS: torn blob reports Loading failed without restore");
    stage_lost = 0;

    // let the write-activity monostable expire so staging retriggers
    repeat (2_200_000) @(posedge clk_74a);

    // ---------------- LOAD deferred until allowed ----------------
    // Blob lands while a download still holds ss_allow low; ss_load must
    // wait for allow instead of racing the download on the SDRAM port
    ss_load_fired = 0;
    ss_allow = 0;
    bridge_write_all;
    savestate_load <= 1;
    guard = 0;
    while (!l_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    savestate_load <= 0;
    repeat (2000) @(posedge clk_74a);
    if (ss_load_fired) begin
      $display("FAIL: ss_load fired while not allowed");
      errors = errors + 1;
    end
    ss_allow = 1;
    wait_ok(1, 60000);
    if (!ss_load_fired) begin
      $display("FAIL: ss_load never fired after allow rose");
      errors = errors + 1;
    end else $display("PASS: load deferred until download released the port");

    repeat (1000) @(posedge clk_74a);

    // ---------------- LOAD with a slow boot (late first NMI) -------------
    // First hijackable NMI can be far out after wake; the trigger wait must
    // cover it, not abandon a load that will still complete
    nmi_delay = 150_000;  // 75% of TIMEOUT_TRIGGER
    savestate_load <= 1;
    guard = 0;
    while (!l_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    savestate_load <= 0;
    bridge_write_all;
    wait_ok(1, 60000);
    $display("PASS: slow boot load survives the trigger wait");
    nmi_delay = 300;

    repeat (1000) @(posedge clk_74a);

    // ---------------- ss_load held through the reset tail ----------------
    // ss_allow rises before the console leaves reset; the pulse must wait for
    // a continuously open window. Stage first with allow low, like a real wake.
    repeat (2_200_000) @(posedge clk_74a);  // let the staging monostable expire
    ss_load_fired = 0;
    ss_allow = 0;
    bridge_write_all;
    savestate_load <= 1;
    guard = 0;
    while (!l_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    savestate_load <= 0;
    repeat (100) @(posedge clk_sys);
    ss_allow = 1;
    repeat (30) @(posedge clk_sys);
    ss_allow = 0;
    repeat (4) @(posedge clk_sys);
    if (ss_load_fired) begin
      $display("FAIL: ss_load fired inside a short allow window");
      errors = errors + 1;
    end
    repeat (10) @(posedge clk_sys);
    ss_allow = 1;
    wait_ok(1, 60000);
    if (!ss_load_fired) begin
      $display("FAIL: ss_load never fired after allow settled");
      errors = errors + 1;
    end else $display("PASS: ss_load waits out the reset tail");

    repeat (1000) @(posedge clk_74a);

    // ---------------- trigger timeout reports failure ----------
    // No hijackable vector before TIMEOUT_TRIGGER, so the request cannot fire
    // and the controller reports err. The request stays armed in the engine
    // (nothing disarms it now), so a console reset clears it before the retry.
    nmi_delay = 260_000;  // beyond TIMEOUT_TRIGGER (200k)
    savestate_start <= 1;
    guard = 0;
    while (!s_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    savestate_start <= 0;
    guard = 0;
    while (!(s_ok | s_err) && guard < 60000000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    if (!s_err) begin
      $display("FAIL: trigger timeout did not err");
      errors = errors + 1;
    end
    ss_allow = 0;  // console reset clears the still-armed request
    repeat (20) @(posedge clk_sys);
    ss_allow = 1;
    repeat (80) @(posedge clk_sys);
    nmi_delay = 300;
    scen_errors = errors;
    start_and_expect_ok;
    if (errors == scen_errors) $display("PASS: trigger timeout errs, retry works after reset");

    repeat (1000) @(posedge clk_74a);

    // ---------------- reset during the trigger wait bails early ----------
    // Reset kills the armed request; controller must err well before
    // TIMEOUT_TRIGGER
    nmi_delay = 260_000;
    savestate_start <= 1;
    guard = 0;
    while (!s_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    savestate_start <= 0;
    repeat (10_000) @(posedge clk_sys);
    ss_allow = 0;
    guard = 0;
    while (!s_err && guard < 5000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    if (!s_err) begin
      $display("FAIL: reset during trigger wait did not err early");
      errors = errors + 1;
    end else $display("PASS: reset during trigger wait errs early");
    ss_allow = 1;
    repeat (80) @(posedge clk_sys);
    nmi_delay = 300;
    scen_errors = errors;
    start_and_expect_ok;
    if (errors == scen_errors) $display("PASS: save works after a reset-killed request");

    repeat (1000) @(posedge clk_74a);

    // ---------------- unsupported cart ----------------
    ss_allow = 0;
    savestate_start <= 1;
    guard = 0;
    while (!s_ack && guard < 10000) begin
      @(posedge clk_74a);
      guard = guard + 1;
    end
    savestate_start <= 0;
    repeat (100) @(posedge clk_74a);
    if (!s_err) begin
      $display("FAIL: unsupported cart did not err");
      errors = errors + 1;
    end else $display("PASS: unsupported cart errors immediately");

    if (errors == 0) $display("ALL TESTS PASSED");
    else $display("%0d ERRORS", errors);
    $finish;
  end
endmodule
