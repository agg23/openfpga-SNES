// Focused packing experiment: original MSU register and original scaling expression.
module unit(input clk, reset_n, msu_enable, sysclkf_ce, wr_n,
 input [23:0] addr, input [7:0] din,
 input sample_ce, input playing, input signed [15:0] sample_l, sample_r, main_l, main_r,
 output reg signed [15:0] pcm_l_q, pcm_r_q);
 wire [7:0] volume;
 reg signed [15:0] raw_l, raw_r;
 always @(posedge clk) if (sample_ce) begin raw_l <= sample_l; raw_r <= sample_r; end
 MSU msu (.CLK(clk), .RST_N(reset_n), .ENABLE(msu_enable), .RD_N(1'b1), .WR_N(wr_n),
 .SYSCLKF_CE(sysclkf_ce), .ADDR(addr), .DIN(din), .volume(volume),
 .track_mounting(1'b0), .status_track_missing(1'b0), .audio_stop(1'b0),
 .audio_sector(22'b0), .audio_loop_index(32'b0), .data(8'b0),
 .data_ack(1'b0), .data_busy_external(1'b0));
 function automatic signed [15:0] scale_sample;
 input signed [15:0] sample;
 input [7:0] gain;
 reg signed [24:0] product;
 begin
 product = sample * $signed({1'b0, gain});
 scale_sample = 16'(product >>> 8);
 end
 endfunction
 function automatic signed [15:0] saturated_add;
 input signed [15:0] a;
 input signed [15:0] b;
 reg signed [19:0] sum;
 begin
 sum = $signed({{4{a[15]}}, a}) + $signed({{4{b[15]}}, b});
 if (sum > 20'sd32767) saturated_add = 16'sh7fff;
 else if (sum < -20'sd32768) saturated_add = 16'sh8000;
 else saturated_add = sum[15:0];
 end
 endfunction
 wire signed [15:0] pcm_l = playing ? scale_sample(raw_l, volume) : 16'sd0;
 wire signed [15:0] pcm_r = playing ? scale_sample(raw_r, volume) : 16'sd0;
 always @(posedge clk) begin
 pcm_l_q <= saturated_add(main_l, pcm_l);
 pcm_r_q <= saturated_add(main_r, pcm_r);
 end
endmodule
