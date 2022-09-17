// Naive ROM parser. The MiSTer C code for this is much better, but this runs on FPGA
module rom_parser (
    input wire clk_mem,

    input wire [31:0] rom_file_size,

    input wire [24:0] addr,
    input wire [15:0] data,
    input wire downloading,

    output wire has_header,

    output reg [7:0] parsed_rom_type = 0,
    output reg [7:0] parsed_rom_size = 0,
    output reg [7:0] parsed_sram_size = 0
);

  // 512 bytes at the beginning of the ROM to ignore
  assign has_header = (rom_file_size & 32'd512) > 0;

  wire [31:0] address_offset = has_header ? 'h200 : 0;

  // Start at BC (rather than C0 or D5) because we want to read 3 bytes before the header for GSU
  wire [2:0] rom_kind_area = 
  addr >= 'h7FBC + address_offset && addr < 'h8000 + address_offset ? 1 : // LoROM segment
  addr >= 'hFFBC + address_offset && addr < 'h10000 + address_offset ? 2 :  // HiROM segment
  addr >= 'h40FFBC + address_offset && addr < 'h410000 + address_offset ? 3 :  // ExHiROM segment
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

  reg [7:0] gsu_ramsz;

  reg [7:0] lorom_score = 0;
  reg [7:0] lorom_rom_size;
  reg [7:0] lorom_sram_size;
  reg [7:0] lorom_chip_type = 0;

  reg [7:0] hirom_score = 0;
  reg [7:0] hirom_rom_size;
  reg [7:0] hirom_sram_size;
  reg [7:0] hirom_chip_type = 0;

  reg [7:0] exhirom_score = 0;
  reg [7:0] exhirom_rom_size;
  reg [7:0] exhirom_sram_size;
  reg [7:0] exhirom_chip_type = 0;

  always @(posedge clk_mem) begin
    prev_rom_kind_area <= rom_kind_area;
    prev_downloading   <= downloading;

    if (rom_kind_area != 0) begin
      // Possible header segment
      case (header_addr)
        'h14:  // FD5 - End of title and mapping mode
        mapping_mode <= data[15:8];
        'h16: begin  // FD6/7 - ROM type and size
          rom_type <= data[7:0];
          rom_size <= data[15:8];
        end
        'h18: begin  // FD8/9 - SRAM size and region
          sram_size <= data[7:0];
          region <= data[15:8];
        end
        'h1A: begin  // FDA/B - Dev id and Version number
          dev_id <= data[7:0];
          version_number <= data[15:8];
        end
        'h1C:  // FDC/D - Checksum compliement
        checksum_compliment <= data;
        'h1E:  // FDE/F - Checksum
        checksum <= data;
      endcase

      if (addr[7:0] == 'hBC) begin
        // GSU ramsz
        gsu_ramsz <= data[15:8];
      end
    end

    if (prev_rom_kind_area && !rom_kind_area) begin
      // Finished processing header. Evaluate
      automatic reg [7:0] header_score = 0;
      automatic reg [7:0] chip_type = 0;
      automatic reg [7:0] ramsz = sram_size;

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

      // External chips
      if (mapping_mode == 'h20 && rom_type == 'h03) begin
        // DSP1
        chip_type = chip_type | 'h84;
      end else if (mapping_mode == 'h21 && rom_type == 'h03) begin
        // DSP1B
        chip_type = chip_type | 'h80;
      end else if (mapping_mode == 'h30 && rom_type == 'h05 && dev_id != 'hB2) begin
        // DSP1B
        chip_type = chip_type | 'h80;
      end else if (mapping_mode == 'h31 && (rom_type == 'h03 || rom_type == 'h05)) begin
        // DSP1B
        chip_type = chip_type | 'h80;
      end else if (mapping_mode == 'h20 && rom_type == 'h05) begin
        // DSP2
        chip_type = chip_type | 'h90;
      end else if (mapping_mode == 'h30 && rom_type == 'h05 && dev_id == 'hB2) begin
        // DSP3
        chip_type = chip_type | 'hA0;
      end else if (mapping_mode == 'h30 && rom_type == 'h03) begin
        // DSP4
        chip_type = chip_type | 'hB0;
      end else if (mapping_mode == 'h30 && rom_type == 'hF6) begin
        // ST010
        chip_type = chip_type | 'h88;

        if (rom_size < 10) chip_type = chip_type | 'h20;

        rom_size <= 1;
      end else if (mapping_mode == 'h30 && rom_type == 'h25) begin
        // OBC1
        chip_type = chip_type | 'hC0;
      end

      if (mapping_mode == 'h3A && (rom_type == 'hF5 || rom_type == 'hF9)) begin
        // SPC7110
        chip_type = chip_type | 'hD0;

        if (rom_type == 'hF9) chip_type = chip_type | 'h08;  // with RTC
      end

      if (mapping_mode == 'h35 && rom_type == 'h55) begin
        // S-RTC (+ExHigh)
        chip_type = chip_type | 'h08;
      end

      if (mapping_mode == 'h20 && rom_type == 'hF3) begin
        // CX4 4
        chip_type = chip_type | 'h40;
      end

      if (mapping_mode == 'h32 && (rom_type == 'h43 || rom_type == 'h45)) begin
        // SDD1 5
        if (rom_size < 14) chip_type = chip_type | 'h50;  // except Star Ocean un-SDD1
      end

      if (mapping_mode == 'h23 && (rom_type == 'h32 || rom_type == 'h34 || rom_type == 'h35)) begin
        // SA1 6
        chip_type = chip_type | 'h60;
      end

      if (mapping_mode == 'h20 && (rom_type == 'h13 || rom_type == 'h14 || rom_type == 'h15 || rom_type == 'h1A)) begin
        // GSU 7
        ramsz = gsu_ramsz;

        if (ramsz == 'hFF) begin
          ramsz = 5;  // StarFox
        end else if (ramsz > 6) begin
          ramsz = 6;
        end

        chip_type = chip_type | 'h70;
      end

      if (prev_rom_kind_area == 1) begin
        // Area was LoROM
        if (mapping_mode == 'h20 || mapping_mode == 'h22) begin
          // LoROM or SA1
          header_score = header_score + 2;
        end

        lorom_score <= header_score;
        lorom_rom_size <= rom_size;
        lorom_sram_size <= ramsz;
        lorom_chip_type <= chip_type;
      end else if (prev_rom_kind_area == 2) begin
        // Area was HiROM
        if (mapping_mode == 'h21) begin
          header_score = header_score + 2;
        end

        hirom_score <= header_score;
        hirom_rom_size <= rom_size;
        hirom_sram_size <= ramsz;
        hirom_chip_type <= chip_type;
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
        exhirom_rom_size <= rom_size;
        exhirom_sram_size <= ramsz;
        exhirom_chip_type <= chip_type;
      end
    end

    if (prev_downloading && ~downloading) begin
      // ROM loading ended, figure out what ROM this is
      if (lorom_score >= hirom_score && lorom_score >= exhirom_score) begin
        parsed_rom_type  <= 0 | lorom_chip_type;
        parsed_rom_size  <= lorom_rom_size;
        parsed_sram_size <= lorom_sram_size;
      end else if (hirom_score >= exhirom_score) begin
        parsed_rom_type  <= 1 | hirom_chip_type;
        parsed_rom_size  <= hirom_rom_size;
        parsed_sram_size <= hirom_sram_size;
      end else if (exhirom_score > 0) begin
        // Only set ExHiROM if there's actually a score, otherwise fall back to LoROM
        parsed_rom_type  <= 2 | exhirom_chip_type;
        parsed_rom_size  <= exhirom_rom_size;
        parsed_sram_size <= exhirom_sram_size;
      end
    end
  end

endmodule
