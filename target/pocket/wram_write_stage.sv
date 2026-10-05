// The SCPU launches WRAM write strobes on a sys rising edge. Capture the whole
// write packet on the following falling edge, after mapper/MSU read selection
// has settled. Only writes are staged; live read addressing is unchanged.
// A level-held write may still be accepted repeatedly by the existing psram
// FSM. Every such acceptance uses the same coherent address, lane and byte.
module wram_write_stage (
    input wire clk_sys,
    input wire write_en,
    input wire [16:0] address,
    input wire [7:0] data,
    output reg memory_write = 0,
    output wire [16:0] memory_address,
    output wire [7:0] memory_data
);
  reg [16:0] write_address;
  reg [7:0] write_data;
  always @(negedge clk_sys) begin
    memory_write <= write_en;
    if (write_en) begin
      write_address <= address;
      write_data <= data;
    end
  end
  assign memory_address = memory_write ? write_address : address;
  assign memory_data = write_data;
endmodule
