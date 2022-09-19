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

// An easily reusable method for synchronizing multiple bits across clock domains
// Uses a shallow depth (4 entries) FIFO, so make sure to empty it quickly
module sync_fifo #(
    parameter WIDTH = 2
) (
    input wire clk_write,
    input wire clk_read,

    input wire write_en,
    input wire [WIDTH - 1:0] data_in,
    output reg [WIDTH - 1:0] data_out = 0
);

  reg read_req = 0;
  wire empty;

  wire [WIDTH - 1:0] fifo_out;

  dcfifo dcfifo_component (
      .data(data_in),
      .rdclk(clk_read),
      .rdreq(read_req),
      .wrclk(clk_write),
      .wrreq(write_en),
      .q(fifo_out),
      .rdempty(empty),
      .aclr(),
      .eccstatus(),
      .rdfull(),
      .rdusedw(),
      .wrempty(),
      .wrfull(),
      .wrusedw()
  );
  defparam dcfifo_component.intended_device_family = "Cyclone V", dcfifo_component.lpm_numwords = 4,
      dcfifo_component.lpm_showahead = "OFF", dcfifo_component.lpm_type = "dcfifo",
      dcfifo_component.lpm_width = 32, dcfifo_component.lpm_widthu = 2,
      dcfifo_component.overflow_checking = "ON", dcfifo_component.rdsync_delaypipe = 5,
      dcfifo_component.underflow_checking = "ON", dcfifo_component.use_eab = "ON",
      dcfifo_component.wrsync_delaypipe = 5;

  reg [1:0] read_state = 0;

  localparam READ_DELAY = 1;
  localparam READ_WRITE = 2;

  always @(posedge clk_read) begin
    read_req <= 0;

    if (~empty) begin
      read_state <= READ_DELAY;
      read_req   <= 1;
    end

    case (read_state)
      READ_DELAY: begin
        read_state <= READ_WRITE;
      end
      READ_WRITE: begin
        read_state <= 0;

        data_out   <= fifo_out;
      end
    endcase
  end

endmodule
