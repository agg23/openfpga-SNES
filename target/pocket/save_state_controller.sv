// APF Memories command sequencer for savestates.sv.

module save_state_controller #(
    // Bridge region (upper nibble) carrying the blob; matches core_top.sv
    parameter [3:0] SS_REGION = 4'h4,

    // ~10s/~6s/~12s at 21.48 MHz, overridable for sim. The trigger wait must
    // outlast a full game boot (request fires on the first NMI/IRQ vector fetch).
    parameter [27:0] TIMEOUT_TRIGGER = 28'd215_000_000,
    parameter [27:0] TIMEOUT_WALK = 28'd128_000_000,
    parameter [27:0] TIMEOUT_READBACK = 28'd256_000_000,
    // Fixed drain delay (clk_sys ticks), not an error timeout
    parameter [27:0] SAVE_DRAIN_CYCLES = 28'd2048
) (
    input wire clk_74a,
    input wire clk_sys_21_48,

    // APF bridge (clk_74a)
    input wire bridge_rd,
    input wire bridge_wr,
    input wire [31:0] bridge_addr,
    // Declared blob size in bytes; cart dependent, set by the loader
    input wire [31:0] ss_size,

    // APF savestate handshake (clk_74a)
    input  wire savestate_load,
    output wire savestate_load_ack_s,
    output wire savestate_load_busy_s,
    output wire savestate_load_ok_s,
    output wire savestate_load_err_s,

    input  wire savestate_start,
    output wire savestate_start_ack_s,
    output wire savestate_start_busy_s,
    output wire savestate_start_ok_s,
    output wire savestate_start_err_s,

    // Core (clk_sys)
    input wire ss_allow,     // save states usable right now (cart ready etc)
    input wire ss_busy,      // engine walk running
    input wire stage_lost,   // staging dropped data, the staged blob is torn (clk_mem)

    output reg ss_save = 0,
    output reg ss_load = 0,
    output wire ss_idle      // sequencer idle, clears the stage_lost latch
);

  // clock domain: clk_74a
  wire in_region = bridge_addr[31:28] == SS_REGION;

  // Retriggerable monostable spanning gaps in the firmware write stream
  // (2^21 at 74.25 MHz ~28 ms); marks that staging started, not that it ended
  reg [20:0] wr_quiet = 0;
  wire stage_active = wr_quiet != 0;

  // Latched when the firmware touches the last word of the blob; cleared
  // whenever the sequencer is idle
  reg last_read_seen = 0;
  reg last_write_seen = 0;
  wire seq_idle_74;

  // ss_size is static for the whole transfer, so no synchronizer is needed
  wire last_word = bridge_addr[27:0] >= ss_size[27:0] - 28'd4;

  always @(posedge clk_74a) begin
    if (bridge_wr && in_region) begin
      wr_quiet <= ~21'd0;
    end else if (wr_quiet != 0) begin
      wr_quiet <= wr_quiet - 1'd1;
    end

    if (seq_idle_74) begin
      last_read_seen  <= 0;
      last_write_seen <= 0;
    end else begin
      if (bridge_rd && in_region && last_word) begin
        last_read_seen <= 1;
      end
      if (bridge_wr && in_region && last_word) begin
        last_write_seen <= 1;
      end
    end
  end

  // clock domain: clk_sys_21_48
  wire start_s;
  wire load_s;
  wire stage_active_s;
  wire last_read_s;
  wire last_write_s;
  wire stage_lost_s;

  synch_3 #(
      .WIDTH(5)
  ) cmd_sync (
      {savestate_start, savestate_load, stage_active, last_read_seen, last_write_seen},
      {start_s, load_s, stage_active_s, last_read_s, last_write_s},
      clk_sys_21_48
  );

  synch_3 stage_lost_sync (
      stage_lost,
      stage_lost_s,
      clk_sys_21_48
  );

  reg start_ack = 0;
  reg start_busy = 0;
  reg start_ok = 0;
  reg start_err = 0;
  reg load_ack = 0;
  reg load_busy = 0;
  reg load_ok = 0;
  reg load_err = 0;

  localparam IDLE = 4'd0;
  localparam SAVE_WAIT_BUSY = 4'd1;
  localparam SAVE_WALK = 4'd2;
  localparam SAVE_READBACK = 4'd3;
  localparam PRELOAD_STAGE = 4'd4;
  localparam LOAD_WAIT_STAGE = 4'd5;
  localparam LOAD_WAIT_BUSY = 4'd6;
  localparam LOAD_WALK = 4'd7;
  localparam SAVE_DRAIN = 4'd9;

  reg [3:0] state = IDLE;
  reg prev_start = 0;
  reg prev_load = 0;
  reg prev_stage = 0;
  reg [27:0] timeout = 0;

  // ss_allow rises before the console reset tail fully releases; a trigger
  // fired into that tail is dropped, so wait for the window to settle first
  reg [6:0] allow_cnt = 0;
  wire allow_settled = allow_cnt[6];

  assign ss_idle = state == IDLE;

  synch_3 idle_sync (
      ss_idle,
      seq_idle_74,
      clk_74a
  );

  always @(posedge clk_sys_21_48) begin
    prev_start <= start_s;
    prev_load <= load_s;
    prev_stage <= stage_active_s;

    ss_save <= 0;
    ss_load <= 0;

    // Drop ack once the firmware releases the request
    if (~start_s) begin
      start_ack <= 0;
    end
    if (~load_s) begin
      load_ack <= 0;
    end

    timeout <= timeout + 1'd1;

    if (~ss_allow) begin
      allow_cnt <= 0;
    end else if (~allow_settled) begin
      allow_cnt <= allow_cnt + 1'd1;
    end

    case (state)
      IDLE: begin
        timeout <= 0;

        if (start_s & ~prev_start) begin
          start_ack <= 1;
          start_ok <= 0;
          start_err <= 0;

          // Need the settled window, else the engine drops the trigger
          if (ss_allow && allow_settled) begin
            start_busy <= 1;
            ss_save <= 1;
            state <= SAVE_WAIT_BUSY;
          end else begin
            start_err <= 1;
          end
        end else if (load_s & ~prev_load) begin
          load_ack <= 1;
          load_ok <= 0;
          load_err <= 0;

          if (ss_allow) begin
            load_busy <= 1;
            state <= LOAD_WAIT_STAGE;
          end else begin
            load_err <= 1;
          end
        end else if (stage_active_s & ~prev_stage) begin
          // Blob arriving ahead of the Load command; track it
          state <= PRELOAD_STAGE;
        end
      end

      SAVE_WAIT_BUSY: begin
        if (ss_busy) begin
          timeout <= 0;
          state <= SAVE_WALK;
        end else if (~ss_allow) begin
          // Console reset cleared the armed request; latch is free again
          start_busy <= 0;
          start_err <= 1;
          state <= IDLE;
        end else if (timeout == TIMEOUT_TRIGGER) begin
          // Engine never fetched a hijackable vector; report failure
          start_busy <= 0;
          start_err <= 1;
          state <= IDLE;
        end
      end

      SAVE_WALK: begin
        if (~ss_busy && ~ss_allow) begin
          // Reset killed the walk (ss_allow drops first), not a completion:
          // the blob is torn, do not offer it
          start_busy <= 0;
          start_err <= 1;
          state <= IDLE;
        end else if (~ss_busy) begin
          // Blob complete; the game resumes (helper RTI) and firmware reads it
          start_busy <= 0;
          start_ok <= 1;
          timeout <= 0;
          state <= SAVE_READBACK;
        end else if (timeout == TIMEOUT_WALK) begin
          start_busy <= 0;
          start_err <= 1;
          state <= IDLE;
        end
      end

      SAVE_READBACK: begin
        // Stay busy until the firmware reads the whole blob; timeout only
        // rescues a firmware that walked away mid-transfer
        if (last_read_s || timeout == TIMEOUT_READBACK) begin
          timeout <= 0;
          state <= SAVE_DRAIN;
        end
      end

      SAVE_DRAIN: begin
        // Let the last word finish through the unloader before going idle
        if (timeout == SAVE_DRAIN_CYCLES) begin
          state <= IDLE;
        end
      end

      PRELOAD_STAGE: begin
        // Staging is alive while writes arrive; only give up after a long
        // quiet period so an SD stall is not mistaken for an abandoned load
        if (stage_active_s) begin
          timeout <= 0;
        end

        if (load_s & ~prev_load) begin
          // No ss_allow test: on wake-from-sleep the Load can arrive while the
          // download tail still holds ss_allow low; LOAD_WAIT_STAGE waits it out
          load_ack <= 1;
          load_ok <= 0;
          load_err <= 0;

          load_busy <= 1;
          timeout <= 0;
          state <= LOAD_WAIT_STAGE;
        end else if (~stage_active_s && timeout >= TIMEOUT_WALK) begin
          // Data arrived but no Load command followed
          state <= IDLE;
        end
      end

      LOAD_WAIT_STAGE: begin
        if (last_write_s && stage_lost_s) begin
          // Staging overflowed; the blob is torn and would wedge the console
          load_busy <= 0;
          load_err <= 1;
          state <= IDLE;
        end else if (last_write_s && allow_settled) begin
          // Last word landed and any download drained; trigger the engine
          ss_load <= 1;
          timeout <= 0;
          state <= LOAD_WAIT_BUSY;
        end else if (timeout == TIMEOUT_READBACK) begin
          load_busy <= 0;
          load_err <= 1;
          state <= IDLE;
        end
      end

      LOAD_WAIT_BUSY: begin
        if (ss_busy) begin
          timeout <= 0;
          state <= LOAD_WALK;
        end else if (~ss_allow) begin
          // Console reset cleared the armed request
          load_busy <= 0;
          load_err <= 1;
          state <= IDLE;
        end else if (timeout == TIMEOUT_TRIGGER) begin
          // Engine refused the blob or never saw an interrupt
          load_busy <= 0;
          load_err <= 1;
          state <= IDLE;
        end
      end

      LOAD_WALK: begin
        if (~ss_busy && ~ss_allow) begin
          // As SAVE_WALK: a mid-walk reset is not a completion
          load_busy <= 0;
          load_err <= 1;
          state <= IDLE;
        end else if (~ss_busy) begin
          load_busy <= 0;
          load_ok <= 1;
          state <= IDLE;
        end else if (timeout == TIMEOUT_WALK) begin
          load_busy <= 0;
          load_err <= 1;
          state <= IDLE;
        end
      end

      default: state <= IDLE;
    endcase

    // Ack a request that lands mid-operation so core_bridge_cmd never hangs;
    // error unless the same op is already running (busy keeps firmware polling)
    if ((start_s & ~prev_start) && state != IDLE) begin
      start_ack <= 1;
      if (~start_busy) begin
        start_ok  <= 0;
        start_err <= 1;
      end
    end
    if ((load_s & ~prev_load) && state != IDLE && state != PRELOAD_STAGE) begin
      load_ack <= 1;
      if (~load_busy) begin
        load_ok  <= 0;
        load_err <= 1;
      end
    end
  end


  // Flags and ack cross to clk_74a on independent synchronizers and
  // core_bridge_cmd latches on the ack; delay the ack so flags land first
  reg [1:0] start_ack_dly = 0;
  reg [1:0] load_ack_dly = 0;

  always @(posedge clk_sys_21_48) begin
    start_ack_dly <= {start_ack_dly[0], start_ack};
    load_ack_dly  <= {load_ack_dly[0], load_ack};
  end

  synch_3 #(
      .WIDTH(8)
  ) status_sync (
      {start_ack_dly[1], start_busy, start_ok, start_err, load_ack_dly[1], load_busy, load_ok, load_err},
      {
        savestate_start_ack_s,
        savestate_start_busy_s,
        savestate_start_ok_s,
        savestate_start_err_s,
        savestate_load_ack_s,
        savestate_load_busy_s,
        savestate_load_ok_s,
        savestate_load_err_s
      },
      clk_74a
  );

endmodule
