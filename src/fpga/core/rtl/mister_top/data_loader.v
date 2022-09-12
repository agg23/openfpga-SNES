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

// A data loader for consuming APF bridge writes and directing them to some storage medium
//
// This takes the 32 bit words from APF, and splits it into four / OUTPUT_WORD_SIZE words (4 separate bytes, or 2 16-bit words).
// You can configure the cycle delay by setting WRITE_MEM_CLOCK_DELAY
module data_loader #(
    // Upper 4 bits of address
    parameter ADDRESS_MASK_UPPER_4 = 0,
    parameter ADDRESS_SIZE = 14,

    // Number of clk_memory cycles to delay each write output.
    // Be aware that APF sends data every ~75 74MHz cycles, so you cannot send data slower than this
    parameter WRITE_MEM_CLOCK_DELAY = 10,

    // Number of clk_memory cycles to hold the write_en signal high
    parameter WRITE_MEM_EN_CYCLE_LENGTH = 1,

    // Word size in number of bytes. Can either be 1 (output 8 bits), or 2 (output 16 bits)
    parameter OUTPUT_WORD_SIZE = 1
) (
    input wire clk_74a,
    input wire clk_memory,

    // DO NOT USE THE CORE RESET SIGNAL
    // That signal only goes high after data finishes loading, but you are using this to load data
    input wire reset_n,

    input wire bridge_wr,
    input wire bridge_endian_little,
    input wire [31:0] bridge_addr,
    input wire [31:0] bridge_wr_data,

    // These outputs are synced to the memory clock
    output reg write_en,
    output reg [ADDRESS_SIZE:0] write_addr,
    output reg [8 * OUTPUT_WORD_SIZE - 1:0] write_data
);

  localparam WORD_SIZE = 8 * OUTPUT_WORD_SIZE;

  reg start_memory_write;
  reg [1:0] start_memory_write_count;
  reg [ADDRESS_SIZE:0] buffered_addr;
  reg [31:0] buffered_data;

  wire start_memory_write_s;
  wire [ADDRESS_SIZE:0] buffered_addr_s;
  wire [31:0] buffered_data_s;

  synch_3 start_write_s (
      start_memory_write,
      start_memory_write_s,
      clk_memory
  );

  synch_3 #(
      .WIDTH(ADDRESS_SIZE + 1)
  ) addr_s (
      buffered_addr,
      buffered_addr_s,
      clk_memory
  );

  synch_3 #(
      .WIDTH(32)
  ) data_s (
      buffered_data,
      buffered_data_s,
      clk_memory
  );

  // Receive APF writes and buffer them into the memory clock domain
  always @(posedge clk_74a) begin
    if (~reset_n) begin
      start_memory_write <= 0;
    end else if (bridge_wr && bridge_addr[31:28] == ADDRESS_MASK_UPPER_4) begin
      // Set up buffered writes
      start_memory_write <= 1;
      start_memory_write_count <= 3;

      buffered_addr <= bridge_addr[ADDRESS_SIZE:0];

      if (bridge_endian_little) begin
        buffered_data <= bridge_wr_data;
      end else begin
        buffered_data <= {
          bridge_wr_data[7:0], bridge_wr_data[15:8], bridge_wr_data[23:16], bridge_wr_data[31:24]
        };
      end
    end else begin
      start_memory_write_count <= start_memory_write_count - 1;

      if (start_memory_write_count == 0) begin
        start_memory_write <= 0;
      end
    end
  end

  reg prev_has_data;
  reg needs_write_data;
  reg [1:0] write_byte;
  reg [7:0] write_delay_count;
  reg [31:0] data_shift_buffer;

  // Consume buffered and synced data, sending out to memory
  always @(posedge clk_memory) begin
    if (~reset_n) begin
      prev_has_data <= 0;
      needs_write_data <= 0;
      write_byte <= 0;
      write_delay_count <= 0;

      write_addr <= 0;
      write_data <= 0;
      write_en <= 0;
    end else begin
      prev_has_data <= start_memory_write_s;

      if (~prev_has_data && start_memory_write_s) begin
        // Newly received buffer data
        needs_write_data <= 1;
        write_byte <= 0;
        write_delay_count <= 0;
        // ack_memory_write <= 1;

        data_shift_buffer <= buffered_data_s;
      end

      if (write_delay_count != 0) begin
        write_delay_count <= write_delay_count - 1;
      end

      if (write_delay_count <= WRITE_MEM_CLOCK_DELAY - WRITE_MEM_EN_CYCLE_LENGTH) begin
        // Leave write_en on for WRITE_MEM_EN_CYCLE_LENGTH
        write_en <= 0;
      end

      if (needs_write_data && write_delay_count == 0) begin
        write_delay_count <= WRITE_MEM_CLOCK_DELAY - 1;
        write_en <= 1;

        if (write_byte == (4 / OUTPUT_WORD_SIZE) - 1) begin
          needs_write_data <= 0;
        end

        write_addr <= buffered_addr_s + (write_byte * OUTPUT_WORD_SIZE);

        write_data <= data_shift_buffer[WORD_SIZE-1:0];

        write_byte <= write_byte + 1;
        data_shift_buffer <= data_shift_buffer[31:WORD_SIZE];
      end
    end
  end

endmodule
