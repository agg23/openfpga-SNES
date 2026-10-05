// Ordered host initialization. Each consumed BEGIN restarts the complete clear;
// Save halfwords may be committed only behind the last physical clear pass.
module ram_clear_frontier #(
    parameter integer BSRAM_BITS = 17
)(
    input wire clk_sys, hard_reset_n, image_begin, quiescent,
    input wire [16:0] save_byte_addr,
    output wire active, busy,
    output reg [16:0] clear_addr,
    output wire save_credit
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *)
    reg [1:0] reset_sync;
    always @(posedge clk_sys or negedge hard_reset_n)
        if (!hard_reset_n) reset_sync <= 0;
        else reset_sync <= {reset_sync[0], 1'b1};
    wire run = reset_sync[1];
    reg [1:0] divider;
    reg clearing, pending, draining;
    assign active = run && clearing && !image_begin;
    assign busy = image_begin || pending || clearing || draining;
    // Smaller physical BSRAMs alias the 128-KiB clear counter. Wait until its
    // final pass, not the first time the low address was crossed.
    localparam [16:0] RAM_MASK = (18'd1 << BSRAM_BITS) - 1;
    wire [16:0] last_clear_byte = (~RAM_MASK) | (save_byte_addr & RAM_MASK) | 17'd1;
    assign save_credit = run && !image_begin && !pending && !save_byte_addr[0] &&
                         (!clearing || clear_addr > last_clear_byte);
    always @(posedge clk_sys or negedge run) begin
        if (!run) begin clearing <= 0; pending <= 0; draining <= 0; clear_addr <= 0; divider <= 0; end
        else if (image_begin) begin
            // BEGIN closes client RAM admission immediately. The caller must
            // drain cartridge owners AND both physical PSRAM controllers.
            // A fresh event wins even on the final cycle of the preceding clear.
            clearing <= 0; pending <= 1; draining <= 0; clear_addr <= 0; divider <= 0;
        end else if (pending) begin
            if (quiescent) begin clearing <= 1; pending <= 0; end
        end else if (clearing) begin
            if (divider == 3) begin
                divider <= 0;
                if (&clear_addr) begin clearing <= 0; draining <= 1; end
                else clear_addr <= clear_addr + 1'b1;
            end else divider <= divider + 1'b1;
        end else if (draining) begin
            // Stop new clear writes before waiting for the last accepted
            // PSRAM beat. Keep clients reset/blocked until it completes.
            if (quiescent) draining <= 0;
        end else begin clear_addr <= 0; divider <= 0; end
    end
    // synthesis translate_off
    initial if (BSRAM_BITS < 1 || BSRAM_BITS > 17)
        $fatal(1,"ram_clear_frontier requires 1..17 physical address bits");
    // synthesis translate_on
endmodule
