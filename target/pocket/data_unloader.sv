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

// A data unloader for consuming APF bridge reads, reading from some underlying memory, and supplying that data to APF
//
// This consumes four / OUTPUT_WORD_SIZE words (4 separate bytes, or 2 16-bit words) and sends APF 32 bit words.
// You can configure the cycle delay by setting READ_MEM_CLOCK_DELAY
module data_unloader #(
    // Upper 4 bits of address
    parameter ADDRESS_MASK_UPPER_4 = 0,
    parameter ADDRESS_SIZE = 28,

    // Number of memory clock cycles it takes for a read to complete
    parameter READ_MEM_CLOCK_DELAY = 1,

    // Word size in number of bytes. Can either be 1 (input 8 bits), or 2 (input 16 bits)
    parameter INPUT_WORD_SIZE = 1
) (
    input wire clk_74a,
    input wire clk_memory,

    input wire bridge_rd,
    input wire bridge_endian_little,
    input wire [31:0] bridge_addr,
    output reg [31:0] bridge_rd_data = 0,

    // These outputs are synced to the memory clock
    output reg read_en = 0,
    output reg [ADDRESS_SIZE-1:0] read_addr = 0,
    input wire [8 * INPUT_WORD_SIZE - 1:0] read_data
);

  localparam WORD_SIZE = 8 * INPUT_WORD_SIZE;

  // APF address to memory FIFO
  reg [27:0] fifo_address_in = 0;
  reg address_read_req = 0;
  reg address_write_req = 0;
  wire address_empty;

  wire [27:0] fifo_address_out;

  dcfifo fifo_address_req (
      .data(fifo_address_in),
      .rdclk(clk_memory),
      .rdreq(address_read_req),
      .wrclk(clk_74a),
      .wrreq(address_write_req),
      .q(fifo_address_out),
      .rdempty(address_empty)
      // .wrempty(),
      // .aclr(),
      // .eccstatus(),
      // .rdfull(),
      // .rdusedw(),
      // .wrfull(),
      // .wrusedw()
  );
  defparam fifo_address_req.clocks_are_synchronized = "FALSE",
      fifo_address_req.intended_device_family = "Cyclone V", fifo_address_req.lpm_numwords = 4,
      fifo_address_req.lpm_showahead = "OFF", fifo_address_req.lpm_type = "dcfifo",
      fifo_address_req.lpm_width = 28, fifo_address_req.lpm_widthu = 2,
      fifo_address_req.overflow_checking = "OFF", fifo_address_req.rdsync_delaypipe = 5,
      fifo_address_req.underflow_checking = "OFF", fifo_address_req.use_eab = "OFF",
      fifo_address_req.wrsync_delaypipe = 5;

  // Memory output to APF FIFO
  reg [WORD_SIZE - 1:0] fifo_data_in = 0;
  reg data_read_req = 0;
  reg data_write_req = 0;
  wire data_empty;

  wire [WORD_SIZE - 1:0] fifo_data_out;

  dcfifo fifo_data_response (
      .data(fifo_data_in),
      .rdclk(clk_74a),
      .rdreq(data_read_req),
      .wrclk(clk_memory),
      .wrreq(data_write_req),
      .q(fifo_data_out),
      .rdempty(data_empty)
      // .wrempty(),
      // .aclr(),
      // .eccstatus(),
      // .rdfull(),
      // .rdusedw(),
      // .wrfull(),
      // .wrusedw()
  );
  defparam fifo_data_response.clocks_are_synchronized = "FALSE",
      fifo_data_response.intended_device_family = "Cyclone V", fifo_data_response.lpm_numwords = 4,
      fifo_data_response.lpm_showahead = "OFF", fifo_data_response.lpm_type = "dcfifo",
      fifo_data_response.lpm_width = WORD_SIZE, fifo_data_response.lpm_widthu = 2,
      fifo_data_response.overflow_checking = "OFF", fifo_data_response.rdsync_delaypipe = 5,
      fifo_data_response.underflow_checking = "OFF", fifo_data_response.use_eab = "OFF",
      fifo_data_response.wrsync_delaypipe = 5;

  /// APF side

  reg prev_bridge_rd = 0;
  reg [2:0] addr_count = 0;
  reg [2:0] addr_state = 0;

  localparam ADDR_START = 1;
  localparam ADDR_REQ = 2;

  // Receive APF read addresses and buffer them into the memory clock domain
  always @(posedge clk_74a) begin
    prev_bridge_rd <= bridge_rd;

    if (~prev_bridge_rd && bridge_rd && bridge_addr[31:28] == ADDRESS_MASK_UPPER_4) begin
      // Beginning APF read from core
      addr_state <= ADDR_REQ;
      address_write_req <= 1;
      addr_count <= 0;

      fifo_address_in <= bridge_addr[27:0];
    end

    case (addr_state)
      ADDR_START: begin
        address_write_req <= 1;

        addr_state <= ADDR_REQ;
      end
      ADDR_REQ: begin
        address_write_req <= 0;

        fifo_address_in <= fifo_address_in + INPUT_WORD_SIZE;

        addr_count <= addr_count + 1;

        if (addr_count == (4 / INPUT_WORD_SIZE) - 1) begin
          // Finished write
          addr_count <= 0;
          addr_state <= 0;
        end else begin
          addr_state <= ADDR_START;
        end
      end
    endcase
  end

  reg [2:0] data_send_state = 0;
  reg [2:0] apf_data_count = 0;
  reg [31:0] apf_bridge_write_data = 0;

  wire [31:0] apf_final_data = {fifo_data_out, apf_bridge_write_data[31-WORD_SIZE:0]};

  localparam READ_DATA_DELAY = 1;
  localparam READ_DATA_WRITE = 2;

  // Receive data from memory and write to APF bridge
  always @(posedge clk_74a) begin
    if (data_send_state != 0) begin
      data_send_state <= data_send_state + 1;
    end else if (~data_empty) begin
      // Start data read
      data_send_state <= READ_DATA_DELAY;
      data_read_req   <= 1;

      apf_data_count  <= 0;
    end

    case (data_send_state)
      READ_DATA_DELAY: begin
        data_read_req <= 0;

        // Shift current APF data
        apf_bridge_write_data <= apf_bridge_write_data >> WORD_SIZE;
      end
      READ_DATA_WRITE: begin
        // Data from memory is available
        if (apf_data_count == (4 / INPUT_WORD_SIZE) - 1) begin
          // We have all of the data we need, send to APF
          bridge_rd_data  <= bridge_endian_little ? apf_final_data :
            {apf_final_data[7:0], apf_final_data[15:8], apf_final_data[23:16], apf_final_data[31:24]};

          data_send_state <= 0;
        end else begin
          apf_bridge_write_data <= apf_final_data;

          data_read_req <= 1;
          data_send_state <= READ_DATA_DELAY;

          apf_data_count <= apf_data_count + 1;
        end
      end
    endcase
  end

  /// Mem side

  reg [5:0] data_read_state = 0;

  localparam READ_ADDRESS_DELAY = 1;
  localparam READ_MEM_START = 2;
  localparam READ_MEM_COMPLETE = READ_MEM_START + READ_MEM_CLOCK_DELAY;
  localparam READ_ADDRESS_END = READ_MEM_COMPLETE + 1;

  always @(posedge clk_memory) begin
    if (data_read_state != 0) begin
      data_read_state <= data_read_state + 1;
    end else if (~address_empty) begin
      // Start address read
      data_read_state  <= READ_ADDRESS_DELAY;
      address_read_req <= 1;
    end

    case (data_read_state)
      READ_ADDRESS_DELAY: begin
        address_read_req <= 0;
      end
      READ_MEM_START: begin
        // Address read data is available
        read_en   <= 1;

        read_addr <= fifo_address_out[ADDRESS_SIZE-1:0];
      end
      READ_MEM_COMPLETE: begin
        // We have data to send to APF
        read_en <= 0;

        data_write_req <= 1;
        fifo_data_in <= read_data;
      end
      READ_ADDRESS_END: begin
        data_write_req  <= 0;

        data_read_state <= 0;
      end
    endcase
  end

endmodule
