// Naive ROM parser. The MiSTer C code for this is much better, but this runs on FPGA
module rom_parser (
  input wire clk_74a,

  input wire [31:0] rom_file_size,

  input wire [24:0] addr,
  input wire [15:0] data,
  input wire downloading,

  output reg [2:0] parsed_rom_type = 0
);

// 512 bytes at the beginning of the ROM to ignore
wire has_header = (rom_file_size & 32'd512) > 0;

wire [31:0] address_offset = has_header ? 'h200 : 0;

wire [2:0] rom_kind_area = 
  addr >= 'h7FD4 + address_offset && addr < 'h8000 + address_offset ? 1 : // LoROM segment
  addr >= 'hFFD4 + address_offset && addr < 'h10000 + address_offset ? 2 : // HiROM segment
  addr >= 'h40FFD4 + address_offset && addr < 'h410000 + address_offset ? 3 : // ExHiROM segment
  0;


// 64 header bits. Only 5 bits because this is a 16bit address
wire [4:0] header_addr = ~addr[5] ? addr[4:0] : 0;

reg [2:0] prev_rom_kind_area;
reg prev_downloading;

reg [7:0] mapping_mode;
reg [7:0] rom_type;
reg [7:0] rom_size;
reg [7:0] sram_size;
reg [7:0] region;
reg [7:0] dev_id;
reg [7:0] version_number;
reg [15:0] checksum_compliment;
reg [15:0] checksum;

reg [7:0] lorom_score = 0;
reg [7:0] hirom_score = 0;
reg [7:0] exhirom_score = 0;

always @(posedge clk_74a) begin
  prev_rom_kind_area <= rom_kind_area;
  prev_downloading <= downloading;

  if (rom_kind_area != 0) begin
    // Possible header segment
    case (header_addr)
      'h14: // FD5 - End of title and mapping mode
        mapping_mode <= data[15:8];
      'h16: begin // FD6/7 - ROM type and size
        rom_type <= data[7:0];
        rom_size <= data[15:8];
      end
      'h18: begin // FD8/9 - SRAM size and region
        sram_size <= data[7:0];
        region <= data[15:8];
      end
      'h1A: begin // FDA/B - Dev id and Version number
        dev_id <= data[7:0];
        version_number <= data[15:8];
      end
      'h1C: // FDC/D - Checksum compliement
        checksum_compliment <= data;
      'h1E: // FDE/F - Checksum
        checksum <= data;
    endcase
  end

  if (prev_rom_kind_area && !rom_kind_area) begin
    // Finished processing header. Evaluate
    automatic reg [7:0] header_score = 0;

    if (checksum != 0 && checksum_compliment != 0 && checksum + checksum_compliment == 'hFFFF) begin
      // Checksum and compliment match. High probability this is header
      header_score = header_score + 4;
    end

    if (dev_id == 'h33) begin
      // 0x33 is an extended header
      header_score = header_score + 2;
    end

    if (rom_type < 8) begin
      header_score = header_score + 1;
    end

    if (rom_size < 16) begin
      header_score = header_score + 1;
    end

    if (sram_size < 8) begin
      header_score = header_score + 1;
    end

    if (region < 14) begin
      header_score = header_score + 1;
    end

    if (prev_rom_kind_area == 1) begin
      // Area was LoROM
      if (mapping_mode == 'h20 || mapping_mode == 'h22) begin
        // LoROM or SA1
        header_score = header_score + 2;
      end

      lorom_score <= header_score;
    end else if (prev_rom_kind_area == 2) begin
      // Area was HiROM
      if (mapping_mode == 'h21) begin
        header_score = header_score + 2;
      end

      hirom_score <= header_score;
    end else if (prev_rom_kind_area == 3) begin
      // Area was ExHiROM
      if (mapping_mode == 'h25 || mapping_mode == 'h35) begin
        header_score = header_score + 2;
      end

      if (header_score != 0) begin  
        // If there is some score for ExHiROM, it's probably ExHiROM
        header_score = header_score + 4;
      end

      exhirom_score <= header_score;
    end
  end

  if (prev_downloading && ~downloading) begin
    // ROM loading ended, figure out what ROM this is
    if (lorom_score >= hirom_score && lorom_score >= exhirom_score) begin
      parsed_rom_type <= 0;
    end else if (hirom_score >= exhirom_score) begin
      parsed_rom_type <= 1;
    end else if (exhirom_score > 0) begin
      // Only set ExHiROM if there's actually a score, otherwise fall back to LoROM
      parsed_rom_type <= 2;
    end
  end
end

endmodule
