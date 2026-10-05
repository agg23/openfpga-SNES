// SPDX-License-Identifier: GPL-3.0-or-later
// One bootstrap per cartridge transaction. The Chip32 loader toggles download
// for both ROM and Save, and APF may also report all-complete for that ROM.
// Arm only from slot 0, consume the first completion, then ignore its duplicate.
module msu_init_guard (
    input wire clk, reset,
    input wire dataslot_requestwrite,
    input wire [15:0] dataslot_requestwrite_id,
    input wire dataslot_allcomplete,
    input wire ioctl_download,
    output reg init_req = 0
);
    reg pending = 0;
    reg rom_write_prev = 0, allcomplete_prev = 0, download_prev = 0;
    wire rom_write = dataslot_requestwrite && dataslot_requestwrite_id == 0;
    wire rom_start = rom_write && !rom_write_prev;
    wire complete = (dataslot_allcomplete && !allcomplete_prev) ||
                    (download_prev && !ioctl_download);
    always @(posedge clk) begin
        init_req <= 0;
        rom_write_prev <= rom_write;
        allcomplete_prev <= dataslot_allcomplete;
        download_prev <= ioctl_download;
        if (rom_start) pending <= 1;
        if (complete && (pending || rom_start)) begin
            init_req <= 1;
            // A distinct next start on a prior transaction's completion edge
            // remains armed; a zero-duration first transaction completes once.
            pending <= pending && rom_start;
        end
        if (reset) begin
            init_req <= 0;
            pending <= 0;
            rom_write_prev <= 0;
            allcomplete_prev <= 0;
            download_prev <= 0;
        end
    end
endmodule
