// APF 0010/0011 is an emulator soft-reset lifecycle, not SDRAM transport reset.
// Assert promptly; release only on system-clock edges after a stable host exit.
module host_reset_guard(
    input wire clk_sys, pll_locked, host_reset_n,
    output wire reset_hold
);
    wire release_allowed = pll_locked && host_reset_n;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *)
    reg [2:0] hold_sync;
    always @(posedge clk_sys or negedge release_allowed)
        if (!release_allowed) hold_sync <= 3'b111;
        else hold_sync <= {hold_sync[1:0],1'b0};
    assign reset_hold = hold_sync[2];
endmodule
