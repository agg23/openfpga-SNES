// Combinational observational proof only. Real selector RTL is extracted verbatim
// by tools/extract_p65_wram_selectors.py, then synthesized by GHDL. No instruction/clock assumptions here
// other than the explicitly listed reachable-state invariants below.
module miter (
 input [23:0] p65_a, dma_a,
 input [7:0] dma_b, di, busb_do, cpu_do,
 input enable, refreshed, dma_run, hdma_run, cpu_rd, cpu_wr,
 input dma_transfer, hdma_bus_active,
 input dma_b_rd, dma_b_wr, dma_a_rd, dma_a_wr,
 input hdma_a_rd, hdma_a_wr, hdma_b_rd, hdma_b_wr,
 output assumptions, observed_write, equivalent, always_cpu_safe,
 output cpu_payload_independent, read_bus_write_needs_dma,
 output [7:0] ram_d, wram_di,
 output [23:0] ca,
 output [7:0] pa,
 output ram_we_n, pard_n, pawr_n, dma_active, busa_sel
);
 wire ram_ce_n;
 SelectorModel original (
 .P65_A(p65_a), .DMA_A(dma_a), .DMA_B(dma_b),
 .ENABLE(enable), .REFRESHED(refreshed), .DMA_RUN(dma_run), .HDMA_RUN(hdma_run),
 .CPU_RD(cpu_rd), .CPU_WR(cpu_wr), .DMA_TRANSFER(dma_transfer), .HDMA_BUS_ACTIVE(hdma_bus_active),
 .DMA_B_RD(dma_b_rd), .DMA_B_WR(dma_b_wr), .DMA_A_RD(dma_a_rd), .DMA_A_WR(dma_a_wr),
 .HDMA_A_RD(hdma_a_rd), .HDMA_A_WR(hdma_a_wr), .HDMA_B_RD(hdma_b_rd), .HDMA_B_WR(hdma_b_wr),
 .DI(di), .BUSB_DO(busb_do), .CPU_DO(cpu_do), .CA(ca), .PA(pa),
 .PARD_N(pard_n), .PAWR_N(pawr_n), .WRAM_DI(wram_di), .RAM_D(ram_d),
 .RAM_CE_N(ram_ce_n), .RAM_WE_N(ram_we_n), .DMA_ACTIVE(dma_active), .BUSA_SEL(busa_sel));

 // These must separately hold in sequential SCPU operation. They are NOT
 // assumptions that are valid for arbitrary transient/glitch waveforms.
 assign assumptions = !(cpu_rd && cpu_wr)
                   && (!dma_transfer || dma_run)
                   && (!hdma_bus_active || hdma_run);

 // RAM writes at the PSRAM capture, plus writes to SWRAM.WMADD ($2181-83).
 wire ram_write = !ram_ce_n && !ram_we_n;
 wire wmadd_write = enable && !pawr_n && (pa == 8'h81 || pa == 8'h82 || pa == 8'h83);
 assign observed_write = ram_write || wmadd_write;

 // Smallest useful high-level selector candidate. This is not claimed to remove
 // a graph path through the original shared mapper by itself.
 wire [7:0] candidate_wram_di = dma_active ? wram_di : cpu_do;
 // This equivalence is on the SWRAM input, leaving its forced-FF mux intact.
 assign always_cpu_safe = !observed_write || wram_di == cpu_do;
 assign equivalent = !observed_write || candidate_wram_di == wram_di;
 assign cpu_payload_independent = dma_active || !observed_write || wram_di == cpu_do;
 assign read_bus_write_needs_dma = !observed_write || !busa_sel || dma_active;
endmodule
