`timescale 1 ns / 10 ps  // time-unit = 1 ns, precision = 10 ps

module rom_parser_tb;
  reg clk_74a = 0;

  localparam period = 20;
  localparam half_period = period / 2;

  reg [31:0] rom_file_size;

  reg [24:0] addr;
  reg [15:0] data;
  reg downloading;

  wire [2:0] parsed_rom_type;

  rom_parser rom_parser (
    .clk_74a(clk_74a),

    .rom_file_size(rom_file_size),

    .addr(addr),
    .data(data),
    .downloading(downloading),

    .parsed_rom_type(parsed_rom_type)
  );

  always begin
    #half_period clk_74a = ~clk_74a;
  end

  integer fd;
  integer value;

  reg div;

  initial begin
    fd = $fopen("smw.smc", "rb");
    rom_file_size = 'h80200;
    downloading = 1;

    if (!fd) begin
      $error("Could not open file");
    end

    addr = 0;

    value = $fgetc(fd);
    div = 1;
    data[7:0] = value;

    while (value != -1) begin
      value = $fgetc(fd);

      if (div) begin
        data[15:8] = value;

        // Send data
        #period;

        addr += 2;
      end else begin
        data[7:0] = value;
      end

      div = ~div;
    end

    #period;

    downloading = 0;

    #(10 * period);

    $stop;
  end

endmodule
