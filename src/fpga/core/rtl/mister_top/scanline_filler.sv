module scanline_filler #(
    parameter int SNAP_COUNT = 1,
    parameter int SNAP_POINTS[SNAP_COUNT] = '{240},
    parameter int HSYNC_DELAY = 6
) (
    input wire clk,

    input wire hsync_in,
    input wire vsync_in,

    input wire vblank_in,
    input wire hblank_in,

    input wire [23:0] rgb_in,

    output reg  hsync,
    output wire vsync,

    output reg de,
    output reg [23:0] rgb,
    output wire [7:0] snap_index,
    output wire [8:0] snap_point
);
  reg prev_de = 0;
  reg prev_hsync = 0;
  reg prev_vsync = 0;
  reg [2:0] hs_delay = 0;

  reg [8:0] output_line_count = 0;
  reg [8:0] visible_line_count = 0;
  // reg [9:0] clks_since_hsync_count = 0;
  // reg [8:0] black_pixel_count = 0;

  reg drawing_line = 0  /* synthesis noprune */;
  reg drawing_black = 0  /* synthesis noprune */;

  wire extended_vblank = vblank_in && ~(output_line_count < snap_point && output_line_count > 0)  /* synthesis keep */;
  wire de_blanks = ~(hblank_in || extended_vblank);

  always @(posedge clk) begin
    prev_hsync <= hsync_in;
    prev_vsync <= vsync_in;
    prev_de <= de_blanks;

    hsync <= 0;
    de <= 0;
    rgb <= 0;
    // clks_since_hsync_count <= clks_since_hsync_count + 1;

    if (vsync_in && ~prev_vsync) begin
      // Reset line count on start of vsync
      output_line_count  <= 0;
      visible_line_count <= 0;
    end

    if (de_blanks && ~prev_de) begin
      // We're drawing on this line
      drawing_line  <= 1;
      drawing_black <= 0;
    end
    // else if (output_line_count < snap_point && ~drawing_line &&
    //              clks_since_hsync_count > CLKS_UNTIL_BLANK_LINE[9:0] &&
    //              black_pixel_count < horizontal_width) begin
    //   // No data to render for this line, but we haven't met the snap point, so fill black
    //   de <= 1;
    //   rgb <= 0;
    //   black_pixel_count <= black_pixel_count + 1;
    //   drawing_black <= 1;
    // end

    if (de_blanks) begin
      de <= 1;
      if (vblank_in) begin
        // Extended blanking
        rgb <= 0;
        drawing_black <= 1;
      end else begin
        // Normal pixels
        rgb <= rgb_in;
      end
    end else if (~de_blanks && prev_de) begin
      // Falling edge of drawing
      output_line_count <= output_line_count + 1;
      if (~drawing_black) begin
        // If we drew black this line, it's not visible
        visible_line_count <= visible_line_count + 1;
      end
    end

    // Move hsync to not collide with vsync
    // ------------
    if (hs_delay > 0) begin
      hs_delay <= hs_delay - 1;
    end

    if (hs_delay == 1) begin
      hsync <= 1;
      // clks_since_hsync_count <= 0;
      // black_pixel_count <= 0;
      // drawing_black <= 0;
      drawing_line <= 0;
    end

    if (hsync_in && ~prev_hsync) begin
      if (HSYNC_DELAY <= 1) begin
        hsync <= 1;
        // clks_since_hsync_count <= 0;
        // black_pixel_count <= 0;
        // drawing_black <= 0;
        drawing_line <= 0;
      end else begin
        hs_delay <= HSYNC_DELAY[2:0];
      end
    end
  end

  always @(posedge clk) begin
    for (int i = 0; i < SNAP_COUNT; i = i + 1) begin
      if (visible_line_count <= SNAP_POINTS[i][8:0]) begin
        snap_index <= i[7:0];
        snap_point <= SNAP_POINTS[i][8:0];
      end
    end

  end

  assign vsync = vsync_in && ~prev_vsync;

endmodule
