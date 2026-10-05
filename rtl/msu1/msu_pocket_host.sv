// SPDX-License-Identifier: MIT
// Pocket/APF dynamic-file backend for MSU-1. All ports are clk synchronous.
// This module does not implement CDC, PCM decoding, or the SNES registers.
// Request inputs are valid/ack handshakes; drop a request after its ack pulse.
// Read-data writes can arrive before completion. Consumers must not publish a
// buffer until done with error == 0. *_actual excludes any padded final bytes.
module msu_pocket_host #(
    parameter [15:0] ROM_SLOT = 16'd0,
    parameter [15:0] DATA_SLOT = 16'd100,
    parameter [15:0] PCM_SLOT = 16'd101,
    parameter [31:0] STRUCT_BASE = 32'h90000000,
    parameter [31:0] DATA_BASE = 32'h90010000,
    parameter [31:0] PCM_BASE = 32'h90020000,
    parameter [31:0] COMMAND_TIMEOUT = 32'd742500000
) (
    input wire clk,
    input wire reset,
    input wire init_req,
    output reg init_done,
    output reg msu_present,
    output reg [31:0] data_size,

    input wire data_req,
    input wire [31:0] data_offset,
    input wire [15:0] data_length,
    output reg data_ack,
    output reg data_done,
    output reg [2:0] data_error,
    output reg [15:0] data_actual,

    input wire pcm_open_req,
    input wire [15:0] pcm_track,
    output reg pcm_open_ack,
    output reg pcm_open_done,
    output reg [2:0] pcm_open_error,
    output reg [31:0] pcm_size,
    input wire pcm_read_req,
    input wire [31:0] pcm_offset,
    input wire [15:0] pcm_length,
    output reg pcm_read_ack,
    output reg pcm_read_done,
    output reg [2:0] pcm_read_error,
    output reg [15:0] pcm_actual,

    input wire [31:0] bridge_addr,
    input wire bridge_rd,
    input wire bridge_wr,
    input wire [31:0] bridge_wr_data,
    input wire bridge_endian_little,
    output wire [31:0] bridge_rd_data,
    output wire data_we,
    output wire [15:0] data_waddr,
    output wire [31:0] data_wdata,
    output wire [3:0] data_wmask,
    output wire pcm_we,
    output wire [15:0] pcm_waddr,
    output wire [31:0] pcm_wdata,
    output wire [3:0] pcm_wmask,

    output reg target_dataslot_read,
    output wire target_dataslot_write,
    output reg target_dataslot_getfile,
    output reg target_dataslot_openfile,
    input wire target_dataslot_ack,
    input wire target_dataslot_done,
    input wire [2:0] target_dataslot_err,
    output reg [15:0] target_dataslot_id,
    output reg [31:0] target_dataslot_slotoffset,
    output reg [31:0] target_dataslot_bridgeaddr,
    output reg [31:0] target_dataslot_length,
    output wire [31:0] target_buffer_param_struct,
    output wire [31:0] target_buffer_resp_struct
);
    function automatic [31:0] swap32(input [31:0] value);
        swap32 = {value[7:0], value[15:8], value[23:16], value[31:24]};
    endfunction
    function automatic [15:0] bounded_length(
        input [31:0] offset, input [15:0] requested, input [31:0] size
    );
        reg [31:0] remaining;
        begin
            remaining = offset < size ? size - offset : 32'd0;
            bounded_length = remaining < {16'd0, requested} ? remaining[15:0] : requested;
        end
    endfunction

    // APF numeric registers are big-endian; file bytes obey bridge endianness.
    // Internally byte zero is always bits [7:0], including PCM sample bytes.
    wire [31:0] file_word = bridge_endian_little ? bridge_wr_data : swap32(bridge_wr_data);
    wire [31:0] numeric_word = bridge_endian_little ? swap32(bridge_wr_data) : bridge_wr_data;
    wire [31:0] path_bridge_q, path_scan_q;
    reg path_read_valid, path_read_little;
    reg path_build_we;
    reg [7:0] path_build_byte;
    // Only membership in the two supported slots is needed. Classify each
    // metadata entry when its ID is written instead of storing and muxing all
    // 16 ID bits for every subsequent size write.
    reg [31:0] slot_is_data, slot_is_pcm;
    reg [31:0] slot_large;
    reg data_large, pcm_large;
    reg pcm_opened;
    reg filename_ready;
    reg init_pending;
    reg faulted;

    localparam [4:0] IDLE=0, ISSUE=1, WAIT_CLEAR=2, WAIT_DONE=3,
        SCAN=4, BUILD_MSU=5, BUILD_PCM=6, PCM_DIGIT=7, PCM_EXTENSION=8,
        FINISH=9, SCAN_FETCH=10;
    localparam [2:0] GET_NAME=0, OPEN_MSU=1, OPEN_PCM=2,
        READ_DATA=3, READ_PCM=4;
    reg [4:0] state;
    reg [2:0] operation;
    reg [2:0] result;
    reg [31:0] watchdog;
    reg [15:0] transfer_length;
    reg [7:0] scan_index;
    reg [7:0] last_dot;
    reg have_dot;
    reg [7:0] base_end;
    reg [7:0] build_index;
    reg [2:0] suffix_index;
    reg [15:0] track_remaining;
    reg [15:0] divisor;
    reg [3:0] digit;
    reg digit_started;
    reg last_was_pcm;
    wire [7:0] scan_char = path_scan_q[8*scan_index[1:0] +: 8];
    wire command_active = state == WAIT_CLEAR || state == WAIT_DONE;
    wire [31:0] data_relative = bridge_addr - DATA_BASE;
    wire [31:0] pcm_relative = bridge_addr - PCM_BASE;
    wire data_hit = data_relative < {16'd0, transfer_length};
    wire pcm_hit = pcm_relative < {16'd0, transfer_length};
    wire struct_hit = bridge_addr >= STRUCT_BASE && bridge_addr < STRUCT_BASE + 32'd264;
    wire [31:0] struct_relative = bridge_addr - STRUCT_BASE;
    wire path_bridge_we = bridge_wr && struct_relative < 256 && bridge_addr >= STRUCT_BASE;
    assign bridge_rd_data = !path_read_valid ? 32'd0 :
        (path_read_little ? path_bridge_q : swap32(path_bridge_q));

    // Four byte lanes permit both APF whole-word writes and local single-byte
    // suffix edits without a variable part-select write mux on every word.
    // Each clocked read port has a copy of the bytes in simple dual-port RAM,
    // allowing M10Ks instead of register arrays and large read muxes.
    // The APF response retains its original one-clock latency and holds until
    // the next structure read. Only the private filename scan takes an extra
    // fetch cycle per character.
    genvar path_lane;
    generate for (path_lane=0; path_lane<4; path_lane=path_lane+1) begin : path_bytes
        wire [7:0] bridge_q, scan_q;
        wire local_we = path_build_we && build_index[1:0] == path_lane;
        wire [5:0] write_addr = path_bridge_we ? struct_relative[7:2] : build_index[7:2];
        wire [7:0] write_byte = path_bridge_we ? file_word[8*path_lane +: 8] : path_build_byte;
        msu_path_byte_ram bridge_mem (
            .clk(clk), .we(path_bridge_we || local_we), .waddr(write_addr), .data(write_byte),
            .re(bridge_rd && struct_hit), .raddr(struct_relative[7:2]), .q(bridge_q)
        );
        msu_path_byte_ram scan_mem (
            .clk(clk), .we(path_bridge_we || local_we), .waddr(write_addr), .data(write_byte),
            .re(1'b1), .raddr(scan_index[7:2]), .q(scan_q)
        );
        assign path_bridge_q[8*path_lane +: 8] = bridge_q;
        assign path_scan_q[8*path_lane +: 8] = scan_q;
    end endgenerate

    always @* begin
        path_build_we = 0;
        path_build_byte = 0;
        case (state)
            BUILD_MSU: begin
                path_build_we = suffix_index <= 4;
                case (suffix_index)
                    0: path_build_byte = ".";
                    1: path_build_byte = "m";
                    2: path_build_byte = "s";
                    3: path_build_byte = "u";
                    default: path_build_byte = 0;
                endcase
            end
            BUILD_PCM: begin path_build_we = 1; path_build_byte = "-"; end
            PCM_DIGIT: begin
                path_build_we = track_remaining < divisor &&
                    (digit != 0 || digit_started || divisor == 1);
                path_build_byte = 8'h30 + {4'd0, digit};
            end
            PCM_EXTENSION: begin
                path_build_we = suffix_index <= 4;
                case (suffix_index)
                    0: path_build_byte = ".";
                    1: path_build_byte = "p";
                    2: path_build_byte = "c";
                    3: path_build_byte = "m";
                    default: path_build_byte = 0;
                endcase
            end
            default: begin end
        endcase
    end
    wire [15:0] requested_data_actual = bounded_length(data_offset, data_length, data_size);
    wire [15:0] requested_pcm_actual = bounded_length(pcm_offset, pcm_length, pcm_size);

    assign target_dataslot_write = 1'b0;
    assign target_buffer_param_struct = STRUCT_BASE;
    assign target_buffer_resp_struct = STRUCT_BASE;
    assign data_we = bridge_wr && command_active && operation == READ_DATA && data_hit;
    assign pcm_we = bridge_wr && command_active && operation == READ_PCM && pcm_hit;
    assign data_waddr = data_relative[15:0];
    assign pcm_waddr = pcm_relative[15:0];
    assign data_wdata = file_word;
    assign pcm_wdata = file_word;
    // data_we/pcm_we imply relative < transfer_length <= 65535. Therefore
    // relative[31:16] is zero whenever any mask bit can be asserted. Adding
    // lanes 0..3 needs only 17 bits (maximum 65534+3); this preserves the
    // original 32-bit comparison even at length 65535 and at wrapped addresses.
    genvar lane;
    generate for (lane=0; lane<4; lane=lane+1) begin : masks
        assign data_wmask[lane] = data_we && ({1'b0, data_relative[15:0]} + 17'(lane) < {1'b0, transfer_length});
        assign pcm_wmask[lane] = pcm_we && ({1'b0, pcm_relative[15:0]} + 17'(lane) < {1'b0, transfer_length});
    end endgenerate

    always @(posedge clk) begin
        init_done <= 0;
        data_ack <= 0;
        data_done <= 0;
        pcm_open_ack <= 0;
        pcm_open_done <= 0;
        pcm_read_ack <= 0;
        pcm_read_done <= 0;
        target_dataslot_read <= 0;
        target_dataslot_getfile <= 0;
        target_dataslot_openfile <= 0;

        // APF read data must persist after the strobe, until the next read.
        if (bridge_rd && struct_hit) begin
            path_read_valid <= struct_relative < 256;
            path_read_little <= bridge_endian_little;
        end

        // APF maintains this table when 0192 changes a file. Snooping avoids
        // contending with the SNES save-RAM sizing port on mf_datatable.
        if (bridge_wr && bridge_addr[31:24] == 8'hF8 && bridge_addr[15:8] == 8'h20) begin
            if (!bridge_addr[2]) begin
                slot_is_data[bridge_addr[7:3]] <= numeric_word[15:0] == DATA_SLOT;
                slot_is_pcm[bridge_addr[7:3]] <= numeric_word[15:0] == PCM_SLOT;
                slot_large[bridge_addr[7:3]] <= |numeric_word[31:16];
            end else begin
                if (slot_is_data[bridge_addr[7:3]]) begin
                    data_size <= numeric_word;
                    data_large <= slot_large[bridge_addr[7:3]];
                end
                if (slot_is_pcm[bridge_addr[7:3]]) begin
                    pcm_size <= numeric_word;
                    pcm_large <= slot_large[bridge_addr[7:3]];
                end
            end
        end
        if (init_req) init_pending <= 1;

        // GET_NAME completes all APF path writes before suffix construction.
        // If another write nevertheless arrives during a local byte edit,
        // finish that APF word and retry the local edit on the next free cycle.
        if (!(path_bridge_we && path_build_we)) case (state)
            IDLE: begin
                if (init_pending) begin
                    init_pending <= 0;
                    msu_present <= 0;
                    pcm_opened <= 0;
                    filename_ready <= 0;
                    operation <= GET_NAME;
                    target_dataslot_id <= ROM_SLOT;
                    result <= 0;
                    if (faulted) begin result <= 7; state <= FINISH; end
                    else state <= ISSUE;
                end else if (pcm_open_req) begin
                    pcm_open_ack <= 1;
                    pcm_opened <= 0;
                    operation <= OPEN_PCM;
                    result <= 0;
                    track_remaining <= pcm_track;
                    target_dataslot_id <= PCM_SLOT;
                    build_index <= base_end;
                    if (faulted || !filename_ready) begin
                        result <= faulted ? 3'd7 : 3'd3;
                        state <= FINISH;
                    end else if (base_end > (pcm_track >= 10000 ? 245 :
                                             pcm_track >= 1000 ? 246 :
                                             pcm_track >= 100 ? 247 :
                                             pcm_track >= 10 ? 248 : 249)) begin
                        result <= 4; state <= FINISH;
                    end else state <= BUILD_PCM;
                end else if (pcm_read_req && (!data_req || !last_was_pcm)) begin
                    pcm_read_ack <= 1;
                    last_was_pcm <= 1;
                    operation <= READ_PCM;
                    target_dataslot_id <= PCM_SLOT;
                    target_dataslot_slotoffset <= pcm_offset;
                    target_dataslot_bridgeaddr <= PCM_BASE;
                    transfer_length <= requested_pcm_actual;
                    target_dataslot_length <= {16'd0, requested_pcm_actual};
                    pcm_actual <= requested_pcm_actual;
                    result <= 0;
                    if (faulted || !pcm_opened || pcm_large) begin
                        result <= faulted ? 3'd7 : (pcm_large ? 3'd2 : 3'd3);
                        pcm_actual <= 0;
                        state <= FINISH;
                    end else if (requested_pcm_actual == 0) state <= FINISH;
                    else state <= ISSUE;
                end else if (data_req) begin
                    data_ack <= 1;
                    last_was_pcm <= 0;
                    operation <= READ_DATA;
                    target_dataslot_id <= DATA_SLOT;
                    target_dataslot_slotoffset <= data_offset;
                    target_dataslot_bridgeaddr <= DATA_BASE;
                    transfer_length <= requested_data_actual;
                    target_dataslot_length <= {16'd0, requested_data_actual};
                    data_actual <= requested_data_actual;
                    result <= 0;
                    if (faulted || !msu_present || data_large) begin
                        result <= faulted ? 3'd7 : (data_large ? 3'd2 : 3'd3);
                        data_actual <= 0;
                        state <= FINISH;
                    end else if (requested_data_actual == 0) state <= FINISH;
                    else state <= ISSUE;
                end
            end
            ISSUE: begin
                if (operation == GET_NAME) target_dataslot_getfile <= 1;
                else if (operation == OPEN_MSU || operation == OPEN_PCM) target_dataslot_openfile <= 1;
                else target_dataslot_read <= 1;
                watchdog <= 0;
                state <= WAIT_CLEAR;
            end
            WAIT_CLEAR, WAIT_DONE: begin
                // Existing APF handler keeps done high from the previous op
                // until it dequeues our new request. Never accept stale done.
                watchdog <= watchdog + 1'b1;
                if (state == WAIT_CLEAR && !target_dataslot_done) state <= WAIT_DONE;
                if (state == WAIT_DONE && target_dataslot_done) begin
                    result <= target_dataslot_err;
                    if (operation == GET_NAME && target_dataslot_err == 0) begin
                        scan_index <= 0;
                        last_dot <= 0;
                        have_dot <= 0;
                        state <= SCAN_FETCH;
                    end else state <= FINISH;
                end else if (COMMAND_TIMEOUT != 0 && watchdog >= COMMAND_TIMEOUT-1) begin
                    // We cannot cancel an in-flight APF command. Quarantine all
                    // future commands until hard reset rather than corrupting it.
                    result <= 7;
                    faulted <= 1;
                    state <= FINISH;
                end
            end
            SCAN_FETCH: state <= SCAN;
            SCAN: begin
                if (scan_char == 0) begin
                    base_end <= have_dot ? last_dot : scan_index;
                    build_index <= have_dot ? last_dot : scan_index;
                    suffix_index <= 0;
                    filename_ready <= scan_index != 0;
                    operation <= OPEN_MSU;
                    target_dataslot_id <= DATA_SLOT;
                    if (scan_index == 0 || (have_dot ? last_dot : scan_index) > 251) begin
                        result <= 4; state <= FINISH;
                    end else state <= BUILD_MSU;
                end else if (scan_index == 255) begin
                    result <= 4; state <= FINISH;
                end else begin
                    if (scan_char == 8'h2f) have_dot <= 0;
                    if (scan_char == 8'h2e) begin last_dot <= scan_index; have_dot <= 1; end
                    scan_index <= scan_index + 1'b1;
                    state <= SCAN_FETCH;
                end
            end
            BUILD_MSU: begin
                build_index <= build_index + 1'b1;
                suffix_index <= suffix_index + 1'b1;
                if (suffix_index == 4) state <= ISSUE;
            end
            BUILD_PCM: begin
                build_index <= build_index + 1'b1;
                divisor <= 16'd10000;
                digit <= 0;
                digit_started <= 0;
                state <= PCM_DIGIT;
            end
            PCM_DIGIT: begin
                // A short subtractive conversion avoids an inferred divider.
                if (track_remaining >= divisor) begin
                    track_remaining <= track_remaining - divisor;
                    digit <= digit + 1'b1;
                end else begin
                    if (digit != 0 || digit_started || divisor == 1) begin
                        build_index <= build_index + 1'b1;
                        digit_started <= 1;
                    end
                    digit <= 0;
                    case (divisor)
                        10000: divisor <= 1000;
                        1000: divisor <= 100;
                        100: divisor <= 10;
                        10: divisor <= 1;
                        default: begin suffix_index <= 0; state <= PCM_EXTENSION; end
                    endcase
                end
            end
            PCM_EXTENSION: begin
                build_index <= build_index + 1'b1;
                suffix_index <= suffix_index + 1'b1;
                if (suffix_index == 4) state <= ISSUE;
            end
            FINISH: begin
                case (operation)
                    GET_NAME: begin init_done <= 1; msu_present <= 0; end
                    OPEN_MSU: begin init_done <= 1; msu_present <= result == 0 && !data_large; end
                    OPEN_PCM: begin
                        pcm_open_done <= 1;
                        pcm_open_error <= result == 0 && pcm_large ? 3'd2 : result;
                        pcm_opened <= result == 0 && !pcm_large;
                    end
                    READ_DATA: begin
                        data_done <= 1;
                        data_error <= result;
                        if (result != 0) data_actual <= 0;
                    end
                    READ_PCM: begin
                        pcm_read_done <= 1;
                        pcm_read_error <= result;
                        if (result != 0) pcm_actual <= 0;
                    end
                    default: begin
                        // Fail closed on an invalid internal operation and
                        // release any bootstrap hold rather than hanging it.
                        faulted <= 1;
                        msu_present <= 0;
                        init_done <= 1;
                    end
                endcase
                state <= IDLE;
            end
            default: state <= IDLE;
        endcase

        if (reset) begin
            state <= IDLE;
            operation <= GET_NAME;
            result <= 0;
            init_pending <= 0;
            filename_ready <= 0;
            faulted <= 0;
            msu_present <= 0;
            pcm_opened <= 0;
            data_size <= 0;
            pcm_size <= 0;
            data_large <= 0;
            pcm_large <= 0;
            slot_large <= 0;
            last_was_pcm <= 0;
            init_done <= 0;
            data_ack <= 0;
            data_done <= 0;
            data_error <= 0;
            data_actual <= 0;
            pcm_open_ack <= 0;
            pcm_open_done <= 0;
            pcm_open_error <= 0;
            pcm_read_ack <= 0;
            pcm_read_done <= 0;
            pcm_read_error <= 0;
            pcm_actual <= 0;
            target_dataslot_read <= 0;
            target_dataslot_getfile <= 0;
            target_dataslot_openfile <= 0;
            target_dataslot_id <= 0;
            target_dataslot_slotoffset <= 0;
            target_dataslot_bridgeaddr <= 0;
            target_dataslot_length <= 0;
            path_read_valid <= 0;
            path_read_little <= 0;
            transfer_length <= 0;
            scan_index <= 0;
            base_end <= 0;
            build_index <= 0;
            watchdog <= 0;
            // Preserve the previous unassigned-ID sentinel for parameterized
            // instances, including either or both slots being 16'hFFFF.
            slot_is_data <= {32{DATA_SLOT == 16'hFFFF}};
            slot_is_pcm <= {32{PCM_SLOT == 16'hFFFF}};
        end
    end
    // target_dataslot_ack is intentionally not used as the completion guard:
    // immediate errors are permitted to finish without a visible busy interval.
    wire unused_ack = target_dataslot_ack;
endmodule

// Keep each read copy in a single-read/single-write inference boundary. In
// particular, Quartus must preserve OLD_DATA on simultaneous read and write.
// This private helper stays in the host source so every host-only build gets it.
/* verilator lint_off DECLFILENAME */
module msu_path_byte_ram (
    input wire clk, we, re,
    input wire [5:0] waddr, raddr,
    input wire [7:0] data,
    output reg [7:0] q
);
    (* ramstyle = "M10K" *) reg [7:0] mem [0:63];
    always @(posedge clk) begin
        if (we) mem[waddr] <= data;
        if (re) q <= mem[raddr];
    end
endmodule
/* verilator lint_on DECLFILENAME */
