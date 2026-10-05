// The PSRAM word can finish on any 4x memory edge. Sample it and the current
// consuming byte lane together on sys falling, ahead of the next SCPU F edge.
// This stage is global: CPU, DMA/HDMA and cartridge-facing BUSB_DO all see it.
// It neither acknowledges a memory request nor changes the PSRAM transaction.
module wram_read_stage (
    input wire clk_sys,
    input wire [15:0] memory_data,
    input wire byte_lane,
    output wire [7:0] data
);
  reg [15:0] read_data;
  reg read_lane;
  always @(negedge clk_sys) begin
    read_data <= memory_data;
    read_lane <= byte_lane;
  end
  assign data = read_lane ? read_data[15:8] : read_data[7:0];
endmodule
