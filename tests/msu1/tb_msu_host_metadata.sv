// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module msu_host_metadata_case #(
    parameter [15:0] DATA_SLOT = 16'd100,
    parameter [15:0] PCM_SLOT = 16'd101
)(output reg done = 0);
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg [31:0] bridge_addr = 0, bridge_wr_data = 0;
    reg bridge_wr = 0, bridge_endian_little = 0;
    wire [31:0] data_size, pcm_size;
    msu_pocket_host #(.DATA_SLOT(DATA_SLOT), .PCM_SLOT(PCM_SLOT)) dut (
        .clk(clk), .reset(reset), .init_req(1'b0),
        .data_req(1'b0), .data_offset(32'd0), .data_length(16'd0),
        .pcm_open_req(1'b0), .pcm_track(16'd0), .pcm_read_req(1'b0),
        .pcm_offset(32'd0), .pcm_length(16'd0),
        .bridge_addr(bridge_addr), .bridge_wr_data(bridge_wr_data),
        .bridge_wr(bridge_wr), .bridge_rd(1'b0),
        .bridge_endian_little(bridge_endian_little),
        .target_dataslot_ack(1'b0), .target_dataslot_done(1'b0),
        .target_dataslot_err(3'd0), .data_size(data_size), .pcm_size(pcm_size)
    );
    reg [15:0] ids [0:31];
    reg [31:0] slot_flags = 0;
    reg [31:0] expected_data = 0, expected_pcm = 0;
    reg expected_data_large = 0, expected_pcm_large = 0;
    integer entry;
    reg [31:0] value;

    function automatic [31:0] swap32(input [31:0] word_data);
        swap32 = {word_data[7:0], word_data[15:8], word_data[23:16], word_data[31:24]};
    endfunction

    task automatic write_entry(input integer index, input bit size_word, input [31:0] word_data);
        begin
            @(negedge clk);
            bridge_wr = 1;
            bridge_addr = 32'hF8002000 + index*8 + (size_word ? 4 : 0);
            bridge_wr_data = bridge_endian_little ? swap32(word_data) : word_data;
            if (size_word) begin
                if (ids[index] == DATA_SLOT) begin
                    expected_data = word_data;
                    expected_data_large = slot_flags[index];
                end
                if (ids[index] == PCM_SLOT) begin
                    expected_pcm = word_data;
                    expected_pcm_large = slot_flags[index];
                end
            end else begin
                ids[index] = word_data[15:0];
                slot_flags[index] = |word_data[31:16];
            end
            @(negedge clk);
            bridge_wr = 0;
            if (data_size !== expected_data || pcm_size !== expected_pcm ||
                dut.data_large !== expected_data_large || dut.pcm_large !== expected_pcm_large)
                $fatal(1, "Metadata mismatch DATA=%h PCM=%h index=%0d size=%0b", DATA_SLOT, PCM_SLOT, index, size_word);
        end
    endtask

    initial begin
        for (integer i=0; i<32; i=i+1) ids[i] = 16'hFFFF;
        repeat (2) @(negedge clk);
        reset = 0;
        for (integer endian=0; endian<2; endian=endian+1) begin
            bridge_endian_little = endian[0];
            for (integer i=0; i<32; i=i+1) begin
                // Unassigned sentinel, each target ID, replaced IDs, and large
                // flags must have exactly the same behavior in both byte orders.
                write_entry(i, 1, 32'h01020304 + i);
                write_entry(i, 0, {16'h1234, DATA_SLOT});
                write_entry(i, 1, 32'h11223344 + i);
                write_entry(i, 0, {16'h0000, PCM_SLOT});
                write_entry(i, 1, 32'h55667788 + i);
                write_entry(i, 0, {16'hFFFF, 16'h0123});
                write_entry(i, 1, 32'hAABBCCDD + i);
                write_entry(i, 0, 32'h0000FFFF);
                write_entry(i, 1, 32'hDEADBEEF + i);
            end
        end
        done = 1;
    end
endmodule

module tb_msu_host_metadata;
    wire [4:0] done;
    msu_host_metadata_case defaults(done[0]);
    msu_host_metadata_case #(.DATA_SLOT(16'hFFFF)) data_sentinel(done[1]);
    msu_host_metadata_case #(.PCM_SLOT(16'hFFFF)) pcm_sentinel(done[2]);
    msu_host_metadata_case #(.DATA_SLOT(101)) same_id(done[3]);
    msu_host_metadata_case #(.DATA_SLOT(16'hFFFF), .PCM_SLOT(16'hFFFF)) both_sentinel(done[4]);
    initial begin
        wait (&done);
        $display("PASS tb_msu_host_metadata: all entries, endian, overwrite, large flags, FFFF and shared IDs");
        $finish;
    end
    initial begin #100000; $fatal(1, "Metadata test timeout"); end
endmodule
