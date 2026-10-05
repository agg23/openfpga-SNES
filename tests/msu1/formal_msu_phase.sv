// SPDX-License-Identifier: MIT
// Arithmetic-step miter for every supported signed-integer rate >= 44100,
// every phase < rate, and either reset value. It also proves the next-state
// range invariant. Actual sized-counter RTL is checked by test_pcm_phase.sv.
// This proves the phase arithmetic, not the complete sequential PCM player.
module phase_equiv(input [31:0] rate, phase, input reset, output equivalent);
wire valid = rate >= 44100 && rate <= 32'h7fffffff && phase < rate;
wire [32:0] sum = {1'b0,phase} + 33'd44100;
wire old_ce = !reset && sum >= {1'b0,rate};
wire new_ce = !reset && phase >= rate - 32'd44100;
wire [31:0] old_next = reset ? 32'd0 : 32'(old_ce ? sum - {1'b0,rate} : sum);
wire [31:0] new_next = reset ? 32'd0 : phase + (new_ce ? 32'd44100 - rate : 32'd44100);
assign equivalent = !valid || (old_ce == new_ce && old_next == new_next && old_next < rate);
endmodule
