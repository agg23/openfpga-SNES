// MIT License

// Copyright (c) 2022 Adam Gastineau

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
////////////////////////////////////////////////////////////////////////////////

function integer rtoi(input integer x);
  return x;
endfunction

`define CEIL(x) ((rtoi(x) > x) ? rtoi(x) : rtoi(x) + 1)
`define MAX(x, y) ((x > y) ? x : y)

module psram #(
    parameter CLOCK_SPEED = 133.12,  // Clock speed in megahertz

    // -- Shared async --
    parameter MIN_ADV_N_PULSE = 5, // Minimum time (ns) for adv_n to be held low to latch address (t_vp)
    parameter MIN_ADDRESS_SETUP_BEFORE_ADV_HIGH = 5, // Minimum time (ns) for address to be asserted before adv_n goes high again (t_avs)
    parameter MIN_ADDRESS_HOLD_AFTER_ADV_HIGH = 2, // Minimum time (ns) for address to be held after adv_n goes high (t_avh)
    parameter MIN_CE_BEFORE_ADV_HIGH = 7, // Minimum time (ns) for bank to be enabled (ce#_n low) before adv_n goes high (t_cvs)

    // -- Writes --
    parameter MIN_DATA_SETUP_BEFORE_WE_HIGH = 20, // Minimum time (ns) for data to write to be set up before we_n goes high (t_dw)
    parameter MIN_DATA_AFTER_ADDR_UNLATCHED = 8, // Minimum time (ns) until data should be asserted after addr unlatch. This isn't in the spec, so I'm guessing
    parameter MIN_WRITE_PULSE = 45, // Minimum time (ns) for we_n to be held low to latch data (t_wp)
    parameter MIN_WRITE_TIME_FROM_ADV = 70, // Minimum time (ns) for write to complete after adv_n goes low (after setup) (t_aw)

    // -- Reads --
    parameter MIN_OE_AFTER_ADDR_UNLATCHED = 3, // Minimum time (ns) until oe_n goes low after addr unlatch. This isn't in the spec, so I'm guessing
    // parameter MAX_OE_TO_VALID_DATA = 20, // Maximum time (ns) for valid data to appear after oe_n goes low
    parameter MAX_ACCESS_TIME_FROM_ADV = 70 // Maximum time (ns) for valid data to appear after adv_n goes low
) (
    input wire clk,

    input wire bank_sel,
    input wire [21:0] addr,

    input wire write_en,
    input wire [15:0] data_in,
    input wire write_high_byte,
    input wire write_low_byte,

    input wire read_en,
    output reg read_avail,
    output reg [15:0] data_out,

    output reg busy,

    // PSRAM signals
    output reg [21:16] cram_a,
    inout wire [15:0] cram_dq,
    input wire cram_wait,
    output reg cram_clk = 0,
    output reg cram_adv_n = 1,
    output reg cram_cre = 0,
    output reg cram_ce0_n = 1,
    output reg cram_ce1_n = 1,
    output reg cram_oe_n = 1,
    output reg cram_we_n = 1,
    output reg cram_ub_n = 1,
    output reg cram_lb_n = 1
);

  localparam PERIOD = 1000.0 / CLOCK_SPEED;  // In nanoseconds

  // -- Shared cycle counts --
  localparam ADV_PULSE_CYCLE_COUNT =
  `CEIL(MIN_ADV_N_PULSE / PERIOD);
  // 2 ns added for setup times. This will vary based on the fitter and hardware, but hopefully is correct
  localparam ADDRESS_SETUP_BEFORE_ADV_CYCLE_COUNT =
  `CEIL((MIN_ADDRESS_SETUP_BEFORE_ADV_HIGH + 2) / PERIOD);

  localparam CE_BEFORE_ADV_CYCLE_COUNT =
  `CEIL((MIN_CE_BEFORE_ADV_HIGH) / PERIOD);

  localparam ADV_CYCLE_COUNT =
  `MAX(`MAX(ADV_PULSE_CYCLE_COUNT, ADDRESS_SETUP_BEFORE_ADV_CYCLE_COUNT),
       CE_BEFORE_ADV_CYCLE_COUNT);
  localparam ADDR_HOLD_AFTER_ADV_CYCLE_COUNT =
  `CEIL(MIN_ADDRESS_HOLD_AFTER_ADV_HIGH / PERIOD);

  // -- Write cycle counts
  localparam DATA_SETUP_BEFORE_WE_ENDS_CYCLE_COUNT =
  `CEIL(MIN_DATA_SETUP_BEFORE_WE_HIGH / PERIOD);

  localparam DATA_AFTER_ADDR_UNLATCH_CYCLE_COUNT =
  `CEIL(MIN_DATA_AFTER_ADDR_UNLATCHED / PERIOD);

  localparam WRITE_PULSE_CYCLE_COUNT =
  `CEIL(MIN_WRITE_PULSE / PERIOD);

  localparam TOTAL_WRITE_CYCLE_COUNT =
  `CEIL(`MAX(MIN_WRITE_TIME_FROM_ADV, MIN_WRITE_PULSE) / PERIOD);

  // -- Read cycle counts --
  localparam OE_AFTER_ADDR_UNLATCH_CYCLE_COUNT =
  `CEIL(MIN_OE_AFTER_ADDR_UNLATCHED / PERIOD);

  localparam TOTAL_READ_CYCLE_COUNT =
  `CEIL(MAX_ACCESS_TIME_FROM_ADV / PERIOD);

  localparam STATE_NONE = 0;

  // -- Write states --

  localparam WRITE_INITIAL_COUNT = 1;

  // On STATE_NONE, write_en triggers:
  //
  // Actions:
  // - Hold adv_n low for MIN_ADV_N_PULSE.
  // - Begin holding ce#_n low, which will continue until write is completed
  // - Begin holding byte enables (lb_n and ub_n) low, which will continue until write is completed
  // - Begin holding we_n low, which will continue until write is completed

  // Actions:
  // - Unlatch adv_n
  //
  // Requirements:
  // - adv_n must be held low for MIN_ADV_N_PULSE (ADV_PULSE_CYCLE_COUNT)
  // - Addr must be held for MIN_ADDRESS_SETUP_BEFORE_ADV_HIGH (ADDRESS_SETUP_BEFORE_ADV_CYCLE_COUNT) before pulse ends
  // These requirements are combined in ADV_CYCLE_COUNT
  //
  // 1 is subtracted here as STATE_NONE will transition to WRITE_INITIAL_COUNT, which may be this state (if ADV_CYCLE_COUNT == 1)
  localparam STATE_WRITE_ADV_END = WRITE_INITIAL_COUNT - 1 + ADV_CYCLE_COUNT;

  // Actions:
  // - Unlatch addr in preparation for writing data on dq
  //
  // Requirements:
  // - Addr must be held for MIN_ADDRESS_HOLD_AFTER_ADV_HIGH after adv_n pulse ends in the previous state
  localparam STATE_WRITE_ADDR_LATCH_END = STATE_WRITE_ADV_END + ADDR_HOLD_AFTER_ADV_CYCLE_COUNT;

  // Actions:
  // - Set data to write on dq
  //
  // Requirements:
  // - Must happen some time period after addr is unlatched. Using MIN_DATA_AFTER_ADDR_UNLATCHED
  //     (DATA_AFTER_ADDR_UNLATCH_CYCLE_COUNT) but this isn't in the spec
  localparam STATE_WRITE_DATA_START = STATE_WRITE_ADDR_LATCH_END + DATA_AFTER_ADDR_UNLATCH_CYCLE_COUNT;

  // Actions:
  // - Clean up all latched signals
  //
  // Requirements:
  // - Occurs MIN_WRITE_TIME_FROM_ADV (TOTAL_WRITE_CYCLE_COUNT) after beginning of read
  localparam STATE_WRITE_DATA_END = WRITE_INITIAL_COUNT + TOTAL_WRITE_CYCLE_COUNT;

  // -- Read states --

  // The initial cycle count/FSM id for the beginning of a read
  localparam READ_INITIAL_COUNT = 20;

  // On STATE_NONE, read_en triggers:
  //
  // Actions:
  // - Hold adv_n low for MIN_ADV_N_PULSE.
  // - Begin holding ce#_n low, which will continue until read is completed
  // - Begin holding byte enables (lb_n and ub_n) low, which will continue until read is completed

  // Actions:
  // - Unlatch adv_n
  //
  // Requirements:
  // - adv_n must be held low for MIN_ADV_N_PULSE (ADV_PULSE_CYCLE_COUNT)
  // - Addr must be held for MIN_ADDRESS_SETUP_BEFORE_ADV_HIGH (ADDRESS_SETUP_BEFORE_ADV_CYCLE_COUNT) before pulse ends
  // These requirements are combined in ADV_CYCLE_COUNT
  //
  // 1 is subtracted here as STATE_NONE will transition to READ_INITIAL_COUNT, which may be this state (if ADV_CYCLE_COUNT == 1)
  localparam STATE_READ_ADV_END = READ_INITIAL_COUNT - 1 + ADV_CYCLE_COUNT;

  // Actions:
  // - Unlatch addr in preparation for data on dq
  //
  // Requirements:
  // - Addr must be held for MIN_ADDRESS_HOLD_AFTER_ADV_HIGH after adv_n pulse ends in the previous state
  localparam STATE_READ_ADDR_LATCH_END = STATE_READ_ADV_END + ADDR_HOLD_AFTER_ADV_CYCLE_COUNT;

  // Actions:
  // - Hold oe_n low in preparation for data on dq
  //
  // Requirements:
  // - Must happen some time period after addr is unlatched. Using MIN_OE_AFTER_ADDR_UNLATCHED
  //     (OE_AFTER_ADDR_UNLATCH_CYCLE_COUNT) but this isn't in the spec
  localparam STATE_READ_DATA_ENABLE = STATE_READ_ADDR_LATCH_END + OE_AFTER_ADDR_UNLATCH_CYCLE_COUNT;

  // Actions:
  // - Receive data and write to data_out
  // - Clean up all latched signals
  //
  // Requirements:
  // - Occurs MAX_ACCESS_TIME_FROM_ADV (TOTAL_READ_CYCLE_COUNT) after beginning of read
  localparam STATE_READ_DATA_RECEIVED = READ_INITIAL_COUNT + TOTAL_READ_CYCLE_COUNT;

  initial begin
    $info("Instantiated PSRAM with the following settings:");
    $info("  Clock speed: %f MHz with period %f ns", CLOCK_SPEED, PERIOD);
    $info("  Writes:");
    $info("    STATE_WRITE_ADV_END: %d", STATE_WRITE_ADV_END);
    $info("    STATE_WRITE_ADDR_LATCH_END: %d", STATE_WRITE_ADDR_LATCH_END);
    $info("    STATE_WRITE_DATA_START: %d", STATE_WRITE_DATA_START);
    $info("    STATE_WRITE_DATA_END: %d", STATE_WRITE_DATA_END);
    $info("");
    $info("  Total write time: %d cycles", TOTAL_WRITE_CYCLE_COUNT);
    $info("  Reads:");
    $info("    STATE_READ_ADV_END: %d", STATE_READ_ADV_END);
    $info("    STATE_READ_ADDR_LATCH_END: %d", STATE_READ_ADDR_LATCH_END);
    $info("    STATE_READ_DATA_ENABLE: %d", STATE_READ_DATA_ENABLE);
    $info("    STATE_READ_DATA_RECEIVED: %d", STATE_READ_DATA_RECEIVED);
    $info("");
    $info("  Total read time: %d cycles", TOTAL_READ_CYCLE_COUNT);
  end

  reg [7:0] state = STATE_NONE;

  // If 1, route cram_data reg to cram_dq
  reg data_out_en = 0;
  reg [15:0] cram_data;

  reg [15:0] latched_data_in;

  assign cram_dq = data_out_en ? cram_data : 16'hZZ;

  always @(posedge clk) begin
    if (state != STATE_NONE) begin
      // If we are not at STATE_NONE, increment state
      state <= state + 1;
    end

    if (state == STATE_NONE) begin
      // We are only busy when not in STATE_NONE
      busy <= 0;
    end else begin
      busy <= 1;
    end

    case (state)
      STATE_NONE: begin
        read_avail <= 0;

        cram_clk   <= 0;
        cram_adv_n <= 1;
        cram_cre   <= 0;
        cram_ce0_n <= 1;
        cram_ce1_n <= 1;
        cram_oe_n  <= 1;
        cram_we_n  <= 1;
        cram_ub_n  <= 1;
        cram_lb_n  <= 1;

        if (write_en) begin
          // Enter write_init
          state <= WRITE_INITIAL_COUNT;

          if (bank_sel) cram_ce1_n <= 0;
          else cram_ce0_n <= 0;

          // Set address and output on dq
          cram_a <= addr[21:16];
          cram_data <= addr[15:0];
          data_out_en <= 1;
          // Store data in for future use
          latched_data_in <= data_in;

          // Enable write
          cram_we_n <= 0;

          // Enable address latching
          cram_adv_n <= 0;

          if (write_high_byte) cram_ub_n <= 0;
          if (write_low_byte) cram_lb_n <= 0;

          // Set busy now instead of waiting for the state change
          busy <= 1;
        end else if (read_en) begin
          state <= READ_INITIAL_COUNT;

          // Activate chip
          if (bank_sel) cram_ce1_n <= 0;
          else cram_ce0_n <= 0;

          // Set address and output on dq
          cram_a <= addr[21:16];
          cram_data <= addr[15:0];
          data_out_en <= 1;

          // Enable address latching
          cram_adv_n <= 0;
          cram_ub_n <= 0;
          cram_lb_n <= 0;

          // Set busy now instead of waiting for the state change
          busy <= 1;
        end
      end

      // Writes
      STATE_WRITE_ADV_END: begin
        // Continue holding address after setting adv high
        cram_adv_n <= 1;
      end
      STATE_WRITE_ADDR_LATCH_END: begin
        // No longer sending address data on cram_dq
        data_out_en <= 0;
      end
      STATE_WRITE_DATA_START: begin
        // Provide data to write
        data_out_en <= 1;
        cram_data   <= latched_data_in;
      end
      STATE_WRITE_DATA_END: begin
        state <= STATE_NONE;

        data_out_en <= 0;

        // Unlatch write enable and banks
        cram_we_n <= 1;

        cram_ce0_n <= 1;
        cram_ce1_n <= 1;

        cram_ub_n <= 1;
        cram_lb_n <= 1;

        // Clear busy now, so we don't have to wait for the state change
        busy <= 0;
      end

      // Reads
      STATE_READ_ADV_END: begin
        // Continue holding address after setting adv high
        cram_adv_n <= 1;
      end
      STATE_READ_ADDR_LATCH_END: begin
        // No longer sending address data on cram_dq
        data_out_en <= 0;
      end
      STATE_READ_DATA_ENABLE: begin
        // Data should arrive shortly, enable output
        cram_oe_n <= 0;
      end
      STATE_READ_DATA_RECEIVED: begin
        state <= STATE_NONE;

        // Actually read data
        read_avail <= 1;
        data_out <= cram_dq;

        // We're done reading, clean up
        cram_ce0_n <= 1;
        cram_ce1_n <= 1;

        cram_ub_n <= 1;
        cram_lb_n <= 1;

        cram_oe_n <= 1;

        // Clear busy now, so we don't have to wait for the state change
        busy <= 0;
      end
    endcase
  end

endmodule
