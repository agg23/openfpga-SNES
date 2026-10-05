// SPDX-License-Identifier: GPL-3.0-or-later
// Standard-profile ordered APF ROM/Save transport. The legacy data_loader is unchanged.
//
// APF has no ready signal. Each rising bridge_wr in region 1 or 2 is retained as a
// complete 32-bit packet, then split at the ready/valid destination. BEGIN/END
// are FIFO-ordered flags, including when coincident with the last/first packet.
// Full or malformed input permanently invalidates this hard-reset epoch.
//
// FIFO_WORDS=512 is bounded transport buffering (40,448 bits), NOT a ROM copy.
// The supported continuous source contract is >=75 clk_74a cycles/32-bit write.
// Bursts are allowed only while this bounded FIFO has room; overflow fails shut.
// hard_reset_n must include PLL lock, but must NOT include emulator soft reset.
// After hard reset, source must observe download_active=0 before a fresh BEGIN.
module rom_download_queue #(
    parameter integer FIFO_WORDS = 512,
    parameter integer FIFO_ADDR_BITS = $clog2(FIFO_WORDS)
)(
    input wire clk_74a, clk_memory, hard_reset_n,
    input wire bridge_wr, bridge_endian_little,
    input wire [31:0] bridge_addr, bridge_wr_data,
    input wire download_active,
    // Source staging registers, sampled atomically only by an accepted BEGIN.
    // {PAL, RAM_SIZE[3:0], ROM_SIZE[3:0], ROM_TYPE[7:0]}.
    input wire [16:0] config_in,
    output reg [16:0] config_out,
    output wire config_valid,
    output wire write_valid,
    input wire write_ready,
    output wire write_en,
    output reg [24:0] write_addr,
    output reg [15:0] write_data,
    // Save writes share the token order but never adopt ROM configuration or
    // validity. Addresses remain byte addresses, matching legacy data_loader.
    output wire save_valid,
    input wire save_ready,
    output wire save_en,
    output wire [16:0] save_addr,
    output wire [15:0] save_data,
    // Every consumed BEGIN, including consecutive queued and empty segments.
    // Consumers must restart their clear sequencer on this pulse and suppress
    // save_ready until both byte addresses have passed the clear frontier.
    output reg image_begin,
    // Includes pending independent Save writes outside download_active. Use
    // this to hold client reset/admission until the local Save RAM accepts them.
    // It does not imply a new ROM image or request a clear without image_begin.
    output wire save_busy,
    // clk74 request pulse inserts an ordered backup-read fence. Exactly one
    // request may be outstanding. ready acknowledges that request only, after
    // all prior writes/control and the system-domain physical barrier drain.
    // Capture eligibility after reset release + observed source idle. This is
    // not FIFO-space credit; the APF stream still has explicit overflow failure.
    output wire source_ready,
    input wire save_read_request,
    output wire save_read_ready,
    input wire save_read_quiescent,
    output wire image_busy,
    output wire image_complete,
    output wire fault
);
    (* async_reg = "true", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *) reg [1:0] source_reset_sync, sink_reset_sync;
    always @(posedge clk_74a or negedge hard_reset_n)
        if (!hard_reset_n) source_reset_sync <= 0;
        else source_reset_sync <= {source_reset_sync[0],1'b1};
    always @(posedge clk_memory or negedge hard_reset_n)
        if (!hard_reset_n) sink_reset_sync <= 0;
        else sink_reset_sync <= {sink_reset_sync[0],1'b1};

    reg source_armed, prev_download, prev_wr, source_fault;
    reg prev_read_request, read_pending, read_ready, read_request_toggle;
    reg read_ack_toggle;
    (* async_reg = "true", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *) reg [1:0] read_ack_sync;
    wire read_event = save_read_request && !prev_read_request;
    assign save_read_ready = read_ready && !read_event && source_reset_sync[1] && !source_fault;
    always @(posedge clk_74a or negedge hard_reset_n)
        if (!hard_reset_n) read_ack_sync <= 0;
        else if (source_reset_sync[1]) read_ack_sync <= {read_ack_sync[0],read_ack_toggle};
    reg [31:0] prev_addr, prev_data;
    reg prev_endian;
    wire begin_event = download_active && !prev_download;
    wire end_event = !download_active && prev_download;
    wire rom_event = bridge_wr && !prev_wr && bridge_addr[31:28] == 4'h1;
    wire save_event = bridge_wr && !prev_wr && bridge_addr[31:28] == 4'h2;
    wire [31:0] ordered_data = bridge_endian_little ? bridge_wr_data :
        {bridge_wr_data[7:0],bridge_wr_data[15:8],bridge_wr_data[23:16],bridge_wr_data[31:24]};
    // 79 bits retain read fence, destination and metadata for coincident events.
    // Later source staging-register writes cannot alter an accepted BEGIN.
    wire [78:0] fifo_in = {read_event,save_event,begin_event ? config_in : 17'b0,
                          begin_event,end_event,rom_event,bridge_addr[24:0],ordered_data};
    wire [78:0] fifo_out;
    wire fifo_full, fifo_empty;
    wire source_event = begin_event || end_event || rom_event || save_event || read_event;
    // Both halfwords must fit the 16 MiB ROM or 128 KiB Save channel. Validate the
    // entire APF packet before enqueueing either half; never partially write a
    // packet whose second word crosses the backend's physical address limit.
    wire malformed_address = rom_event && (bridge_addr[27:24] != 0 ||
        bridge_addr[0] || bridge_addr[23:1] == 23'h7fffff) ||
        (save_event && (bridge_addr[27:17] != 0 || bridge_addr[0] ||
                        bridge_addr[16:1] == 16'hffff));
    wire overlapping_strobe = bridge_wr && prev_wr &&
        (bridge_addr[31:28] == 4'h1 || prev_addr[31:28] == 4'h1 ||
         bridge_addr[31:28] == 4'h2 || prev_addr[31:28] == 4'h2) &&
        ({bridge_addr,bridge_wr_data,bridge_endian_little} != {prev_addr,prev_data,prev_endian});
    // A distinct BEGIN command while already open is not a fresh mount. Level
    // transition detection alone could otherwise silently merge two images.
    wire duplicate_begin = bridge_wr && !prev_wr && bridge_addr == 0 &&
                           bridge_wr_data[0] && download_active && prev_download;
    wire malformed = malformed_address || overlapping_strobe || duplicate_begin ||
                     (read_event && read_pending) ||
                     (rom_event && !(download_active || prev_download));
    assign source_ready = source_reset_sync[1] && source_armed && !source_fault;
    wire fifo_write = source_ready &&
                      source_event && !malformed && !fifo_full;
    wire fifo_read;
    dcfifo #(
        .intended_device_family("Cyclone V"), .lpm_type("dcfifo"),
        .lpm_width(79), .lpm_widthu(FIFO_ADDR_BITS), .lpm_numwords(FIFO_WORDS),
        .lpm_showahead("ON"), .use_eab("ON"), .ram_block_type("M10K"),
        .overflow_checking("ON"), .underflow_checking("ON"),
        .rdsync_delaypipe(5), .wrsync_delaypipe(5),
        .read_aclr_synch("ON"), .write_aclr_synch("ON"),
        .clocks_are_synchronized("FALSE")
    ) transport_fifo (
        .aclr(!hard_reset_n), .wrclk(clk_74a), .rdclk(clk_memory),
        .data(fifo_in), .wrreq(fifo_write), .rdreq(fifo_read),
        .q(fifo_out), .wrfull(fifo_full), .rdempty(fifo_empty),
        .rdfull(), .wrempty(), .rdusedw(), .wrusedw(), .eccstatus()
    );
    always @(posedge clk_74a or negedge hard_reset_n) begin
        if (!hard_reset_n) begin
            source_armed <= 0; prev_download <= 0; prev_wr <= 0;
            prev_read_request <= 0; read_pending <= 0; read_ready <= 0; read_request_toggle <= 0;
            prev_addr <= 0; prev_data <= 0; prev_endian <= 0; source_fault <= 0;
        end else if (source_reset_sync[1]) begin
            prev_download <= download_active;
            prev_read_request <= save_read_request;
            if (read_pending && read_ack_sync[1] == read_request_toggle) begin
                read_pending <= 0;
                read_ready <= 1;
            end
            if (read_event) begin
                read_pending <= 1;
                read_ready <= 0;
                read_request_toggle <= ~read_request_toggle;
            end
            prev_wr <= bridge_wr;
            prev_addr <= bridge_addr; prev_data <= bridge_wr_data;
            prev_endian <= bridge_endian_little;
            if (!download_active) source_armed <= 1;
            if (source_armed && (malformed || (source_event && fifo_full)))
                source_fault <= 1;
        end
    end

    (* async_reg = "true", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *) reg [1:0] fault_sync;
    always @(posedge clk_memory or negedge hard_reset_n)
        if (!hard_reset_n) fault_sync <= 0;
        else if (sink_reset_sync[1]) fault_sync <= {fault_sync[0],source_fault};

    reg holding, holding_save, holding_fence, upper_half, packet_end, sink_open, complete, sink_fault;
    reg [15:0] upper_data;
    reg image_has_data, have_image;
    reg [16:0] pending_config;
    reg config_pending, config_adopted;
    // This is a retained configuration-valid level, not image completion.
    // Fatal transport errors invalidate it externally until hard reset.
    assign config_valid = config_adopted && sink_reset_sync[1] && !fault;
    assign fault = fault_sync[1] || sink_fault;
    assign write_valid = holding && !holding_save && sink_reset_sync[1] && !fault;
    // Acceptance event, not a separately registered duplicate of the request.
    assign write_en = write_valid && write_ready;
    // A same-token BEGIN+Save cannot exploit the cycle before MAIN observes
    // image_begin and starts/restarts clearing. MAIN also gates pending clear.
    assign save_valid = holding && holding_save && !image_begin && sink_reset_sync[1] && !fault;
    assign save_en = save_valid && save_ready;
    assign save_addr = write_addr[16:0];
    assign save_data = write_data;
    assign save_busy = sink_reset_sync[1] && (!fifo_empty || holding || holding_fence || image_begin || fault);
    assign image_busy = sink_open || fault;
    assign image_complete = complete && !fault && sink_reset_sync[1];
    assign fifo_read = sink_reset_sync[1] && !fault && !holding && !holding_fence && !fifo_empty;

    always @(posedge clk_memory or negedge hard_reset_n) begin
        if (!hard_reset_n) begin
            holding <= 0; holding_save <= 0; holding_fence <= 0; read_ack_toggle <= 0; image_begin <= 0; upper_half <= 0; packet_end <= 0;
            sink_open <= 0; complete <= 0; sink_fault <= 0;
            image_has_data <= 0; have_image <= 0;
            pending_config <= 0; config_out <= 0;
            config_pending <= 0; config_adopted <= 0;
            write_addr <= 0; write_data <= 0; upper_data <= 0;
        end else begin
            image_begin <= 0;
            if (sink_reset_sync[1] && !fault) begin
                // A fence following DATA cannot acknowledge on that DATA's
                // acceptance edge. BEGIN also reaches MAIN before this barrier.
                if (holding_fence && !holding && !image_begin && save_read_quiescent) begin
                    holding_fence <= 0;
                    read_ack_toggle <= ~read_ack_toggle;
                end
                if (fifo_read) begin
                    if ((fifo_out[59] && sink_open) ||
                        // Legacy region-2 restores may arrive without a BEGIN. They
                        // neither clear RAM nor create a new image/config epoch.
                        (!fifo_out[59] && !sink_open && !((fifo_out[77] || fifo_out[78]) && !fifo_out[58] && !fifo_out[57])) ||
                        !(|{fifo_out[78:77],fifo_out[59:57]})) begin
                        sink_fault <= 1;
                    end else begin
                        if (fifo_out[78]) holding_fence <= 1;
                        if (fifo_out[59]) begin
                            sink_open <= 1; image_begin <= 1; complete <= 0; image_has_data <= 0;
                            pending_config <= fifo_out[76:60];
                            config_pending <= 1;
                        end
                        if (fifo_out[57] || fifo_out[77]) begin
                            holding_save <= fifo_out[77];
                            write_addr <= fifo_out[56:32];
                            write_data <= fifo_out[15:0];
                            upper_data <= fifo_out[31:16];
                            packet_end <= fifo_out[58];
                            upper_half <= 0;
                            holding <= 1;
                        end else if (fifo_out[58]) begin
                            sink_open <= 0; config_pending <= 0;
                            // Chip32 also toggles download for Save. An empty cycle
                            // may retain a previously valid ROM, but must not mount
                            // uninitialized SDRAM after a hard reset.
                            complete <= image_has_data || have_image;
                            if (image_has_data) have_image <= 1;
                        end
                    end
                end
                if (write_en || save_en) begin
                    // The cart's write_ready proves old clients have acknowledged
                    // flush and the previous physical transaction has drained.
                    // Commit only for a nonempty image; an empty Save cycle must
                    // preserve the preceding image's config and validity.
                    if (write_en && config_pending) begin
                        config_out <= pending_config;
                        config_adopted <= 1;
                        config_pending <= 0;
                    end
                    if (write_en) image_has_data <= 1;
                    if (!upper_half) begin
                        write_addr <= write_addr + 25'd2;
                        write_data <= upper_data;
                        upper_half <= 1;
                    end else begin
                        holding <= 0;
                        if (packet_end) begin
                            sink_open <= 0; config_pending <= 0;
                            complete <= image_has_data || have_image || !holding_save;
                            if (image_has_data || !holding_save) have_image <= 1;
                        end
                    end
                end
            end
        end
    end
    // synthesis translate_off
    initial begin
        if (FIFO_WORDS < 4 || FIFO_WORDS != (1 << FIFO_ADDR_BITS))
            $fatal(1,"rom_download_queue requires power-of-two FIFO_WORDS >=4");
    end
    // synthesis translate_on
endmodule
