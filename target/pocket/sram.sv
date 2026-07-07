// Async SRAM controller, copied from agg23's openfpga-litex.
// MIT License. Copyright (c) 2023 Adam Gastineau.

module sram #(
    parameter CLOCK_SPEED_MHZ = 74.25,  // Clock speed in megahertz
    parameter MIN_OP_CYCLE_TIME_NANO_SEC = 55
) (
    input wire clk,

    input wire reset,

    input wire [1:0] mask,
    input wire wr,
    input wire rd,

    input  wire [16:0] addr,
    input  wire [15:0] data,
    output reg  [15:0] q,

    output wire ready,

    // SRAM Interface
    output reg  [16:0] sram_a,
    inout  wire [15:0] sram_dq,
    output reg         sram_oe_n,
    output reg         sram_we_n,
    output reg         sram_ub_n,
    output reg         sram_lb_n
);
  function integer rtoi(input integer x);
    return x;
  endfunction

  `define CEIL(x) ((rtoi(x) > x) ? rtoi(x) : rtoi(x) + 1)

  localparam CLOCK_PERIOD_NANO_SEC = 1000.0 / CLOCK_SPEED_MHZ;  // In nanoseconds

  localparam CYCLES_PER_OP =
  `CEIL(MIN_OP_CYCLE_TIME_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

  reg use_write = 0;
  reg [15:0] current_write_data = 0;

  reg [3:0] wait_counter = 0;

  assign sram_dq = use_write ? current_write_data : 16'hZZZZ;

  localparam INIT_STATE = 0;
  localparam WAIT_STATE = 1;

  reg state = 0;

  assign ready = state == INIT_STATE;

  always @(posedge clk) begin
    if (reset) begin
      q <= 16'h0;

      sram_a <= 17'h0;
      sram_oe_n <= 1'b1;
      sram_we_n <= 1'b1;
      sram_ub_n <= 1'b1;
      sram_lb_n <= 1'b1;
    end else begin
      case (state)
        INIT_STATE: begin
          // Disable both bytes. Standby
          sram_ub_n <= 1'b1;
          sram_lb_n <= 1'b1;

          if (wr) begin
            state <= WAIT_STATE;
            wait_counter <= CYCLES_PER_OP;

            sram_a <= addr;
            current_write_data <= data;
            use_write <= 1'b1;

            sram_oe_n <= 1'b1;
            sram_we_n <= 1'b0;
            {sram_ub_n, sram_lb_n} <= ~mask;
          end else if (rd) begin
            state <= WAIT_STATE;
            wait_counter <= CYCLES_PER_OP;

            sram_a <= addr;
            use_write <= 1'b0;

            sram_oe_n <= 1'b0;
            sram_we_n <= 1'b1;
            {sram_ub_n, sram_lb_n} <= ~mask;
          end
        end
        WAIT_STATE: begin
          if (wait_counter > 0) begin
            wait_counter <= wait_counter - 4'h1;
          end else begin
            state <= INIT_STATE;

            if (~use_write) begin
              // Completed read, grab data
              q <= sram_dq;
            end
          end
        end
      endcase
    end
  end

endmodule
