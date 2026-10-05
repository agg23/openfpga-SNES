// SPDX-License-Identifier: MIT
// Resource-only wrapper: USE_DMA=0 keeps the original complete helper output;
// USE_DMA=1 adds an independent address/read selector sharing payload inputs.
module unit #(parameter USE_DMA=1)(
 input [23:0] cpu_ca,dma_ca,bsram_mask,rom_mask,
 input [7:0] map_ctrl,cc_dr,dsp_do,srtc_do,cc_sr,bsram_q,openbus,
 input [15:0] rom_q,
 input cpu_romsel_n,cpu_ramsel_n,dma_romsel_n,dma_ramsel_n,
 output [7:0] cpu_do,dma_do,
 output [23:0] cart,
 output [19:0] bram,
 output [8:0] flags);
DSP_LHReadSelect cpu (.ca(cpu_ca), .romsel_n(cpu_romsel_n), .ramsel_n(cpu_ramsel_n), .map_ctrl(map_ctrl), .cc_dr(cc_dr), .bsram_mask(bsram_mask), .rom_mask(rom_mask), .rom_q(rom_q), .dsp_do(dsp_do), .srtc_do(srtc_do), .cc_sr(cc_sr), .bsram_q(bsram_q), .openbus(openbus), .DO(cpu_do), .cart_addr_o(cart), .bram_addr_o(bram), .rom_sel_o(flags[0]), .bsram_sel_o(flags[1]), .no_bsram_sel_o(flags[2]), .dp_sel_o(flags[3]), .dsp_sel_o(flags[4]), .dsp_a0_o(flags[5]), .obc1_sel_o(flags[6]), .srtc_sel_o(flags[7]), .cc_sel_o(flags[8]));
generate if(USE_DMA) begin
DSP_LHReadSelect dma (.ca(dma_ca), .romsel_n(dma_romsel_n), .ramsel_n(dma_ramsel_n), .map_ctrl(map_ctrl), .cc_dr(cc_dr), .bsram_mask(bsram_mask), .rom_mask(rom_mask), .rom_q(rom_q), .dsp_do(dsp_do), .srtc_do(srtc_do), .cc_sr(cc_sr), .bsram_q(bsram_q), .openbus(openbus), .DO(dma_do), .cart_addr_o(), .bram_addr_o(), .rom_sel_o(), .bsram_sel_o(), .no_bsram_sel_o(), .dp_sel_o(), .dsp_sel_o(), .dsp_a0_o(), .obc1_sel_o(), .srtc_sel_o(), .cc_sel_o());
end else begin assign dma_do=8'd0; end endgenerate
endmodule
