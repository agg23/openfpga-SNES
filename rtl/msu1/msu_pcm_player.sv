// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded, native-rate MSU-1 PCM streamer for the Pocket SNES core.
// All ports are synchronous to clk. A CDC/host adapter belongs outside this module.
// File format: "MSU1", uint32 little-endian loop frame, then signed 16-bit L/R.
//
// Host protocol: one outstanding request, byte offset/length (4-byte aligned,
// at most 1024 bytes). Hold req fields until req_valid && req_ready. Deliver
// sequential little-endian words using resp_valid && resp_ready; resp_done is
// one pulse with/after the last accepted word, with resp_error valid that cycle.
// An accepted request MUST eventually complete, including failures. track_load
// cancels queued reads and drains any accepted read before requesting a new file.
// The host must bind each accepted request to the track selected at acceptance.
// Reset must reset both this module and its transport; it abandons transactions.
//
// audio_frame is the exact next PCM frame (not a byte or sector index), suitable
// for resume_frame. A fresh track_load parses its header and resumes at that frame
// iff ctl_resume is set. ctl_play=0 pauses at the next frame and silences output.
// Volume matches MiSTer: signed sample * unsigned volume / 256, arithmetic floor.
// Playback ticks at 44100 Hz; the existing Pocket I2S bridge samples the held
// mixed signal at 48 kHz. This is zero-order hold, not an interpolation filter.
module msu_pcm_player #(
    parameter integer CLK_RATE = 21477270,
    parameter integer BUFFER_BYTES = 8192
) (
    input  wire clk,
    input  wire reset,
    input  wire track_load,
    input  wire [31:0] track_size,
    input  wire track_missing,
    input  wire ctl_play,
    input  wire ctl_repeat,
    input  wire [7:0] ctl_volume,
    input  wire ctl_resume,
    input  wire [31:0] resume_frame,
    output wire busy,
    output reg  missing,
    output wire playing,
    output reg  stop,
    output reg  underrun,
    output reg  [31:0] underrun_count,
    output wire [15:0] fifo_level,
    output reg  [31:0] audio_frame,
    output reg  [31:0] audio_loop_index,
    output wire sample_ce,
    output wire req_valid,
    input  wire req_ready,
    output reg  [31:0] req_offset,
    output reg  [10:0] req_length,
    input  wire resp_valid,
    output wire resp_ready,
    input  wire [31:0] resp_data,
    input  wire resp_done,
    input  wire resp_error,
    input  wire signed [15:0] main_l,
    input  wire signed [15:0] main_r,
    output wire signed [15:0] pcm_l,
    output wire signed [15:0] pcm_r,
    output wire signed [15:0] mixed_l,
    output wire signed [15:0] mixed_r
);
    localparam integer DEPTH = BUFFER_BYTES / 4;
    localparam integer PTR_BITS = $clog2(DEPTH);
    localparam integer COUNT_BITS = PTR_BITS + 1;
    localparam integer PHASE_BITS = $clog2(CLK_RATE + 44100);
    localparam [2:0] IDLE=0, HEADER_REQ=1, HEADER_RX=2, FILL=3,
                     PCM_REQ=4, PCM_RX=5, DRAIN=6;
    reg [2:0] state;
    reg loaded, ready, ended, previous_play;
    reg [31:0] total_frames, fetch_frame, request_frame;
    reg [31:0] requested_resume;
    // Only equality with the fixed signature is needed after word zero.
    reg header_magic_ok;
    reg [31:0] header_loop;
    reg [9:0] received_words;
    reg [8:0] expected_words;
    reg response_bad;
    reg [PTR_BITS-1:0] write_ptr, read_ptr;
    reg [COUNT_BITS-1:0] fifo_count, startup_frames;
    assign fifo_level = 16'(fifo_count);
    // No reset on the RAM or its read data: supports inferred M10K block RAM.
    (* ramstyle = "M10K, no_rw_check" *) reg [31:0] pcm_ram [0:DEPTH-1];
    reg [31:0] ram_q, head;
    reg read_pending, head_valid;
    reg signed [15:0] raw_l, raw_r;
    reg [PHASE_BITS-1:0] phase;
    // For every supported CLK_RATE >= 44100, reset establishes phase < rate.
    // phase + 44100 >= rate is then equivalent to phase >= rate - 44100.
    // Select the increment before a single addition instead of adding 44100
    // and conditionally subtracting rate afterward. The sized negative constant
    // uses modulo-2^PHASE_BITS arithmetic; the result remains in [0, rate).
    // At CLK_RATE == 44100 the increment is zero and every clock is a tick.
    assign sample_ce = !reset && phase >= PHASE_BITS'(CLK_RATE - 44100);
    always @(posedge clk) begin
        if (reset) phase <= 0;
        else phase <= phase + (sample_ce ? PHASE_BITS'(44100 - CLK_RATE) : PHASE_BITS'(44100));
    end

    assign busy = loaded && !ready && !missing;
    assign playing = loaded && ready && ctl_play && !missing && !ended;
    assign req_valid = !reset && !track_load &&
                       ((state == HEADER_REQ) || (state == PCM_REQ));
    assign resp_ready = !reset && ((state == HEADER_RX) ||
                       (state == PCM_RX) || (state == DRAIN));
    wire receive_word = resp_valid && resp_ready;
    wire [10:0] completed_words = {1'b0, received_words} + {10'b0, receive_word};
    wire good_response = !resp_error && !response_bad &&
                         (completed_words == {2'b0, expected_words});
    wire block_commit = state == PCM_RX && resp_done && good_response;
    wire block_fail = ((state == PCM_RX) || (state == HEADER_RX)) &&
                      resp_done && !good_response;
    wire consume = sample_ce && playing && (audio_frame < total_frames) && head_valid;
    wire ram_read = !head_valid && !read_pending && fifo_count != 0;
    wire ram_write = (state == PCM_RX) && receive_word &&
                     (received_words < {1'b0, expected_words}) && !track_load;
    wire [PTR_BITS-1:0] received_offset = PTR_BITS'(received_words);
    wire [PTR_BITS-1:0] ram_write_addr = write_ptr + received_offset;
    always @(posedge clk) begin
        if (ram_write) pcm_ram[ram_write_addr] <= resp_data;
        if (ram_read) ram_q <= pcm_ram[read_ptr];
    end

    wire [31:0] next_fetch = (fetch_frame >= total_frames) ? audio_loop_index : fetch_frame;
    wire [31:0] frames_remaining = total_frames - next_fetch;
    wire [8:0] next_words = frames_remaining > 256 ? 9'd256 : frames_remaining[8:0];
    wire completed_magic_ok = receive_word && received_words == 0 ? resp_data == 32'h3155534d : header_magic_ok;
    wire [31:0] completed_loop = receive_word && received_words == 1 ? resp_data : header_loop;
    wire [31:0] resume_start = requested_resume < total_frames ? requested_resume : 0;
    wire [31:0] initial_frames = total_frames - resume_start;
    wire file_shape_valid = !track_missing && track_size >= 12 && track_size[1:0] == 0;
    wire restart = ctl_play && !previous_play && ended && loaded && !missing;

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
    assign pcm_l = playing ? scale_sample(raw_l, ctl_volume) : 16'sd0;
    assign pcm_r = playing ? scale_sample(raw_r, ctl_volume) : 16'sd0;
    assign mixed_l = saturated_add(main_l, pcm_l);
    assign mixed_r = saturated_add(main_r, pcm_r);

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            loaded <= 0; ready <= 0; missing <= 0; ended <= 0;
            previous_play <= 0; stop <= 0; underrun <= 0; underrun_count <= 0;
            audio_frame <= 0; audio_loop_index <= 0;
            total_frames <= 0; fetch_frame <= 0; request_frame <= 0;
            requested_resume <= 0; startup_frames <= 0;
            req_offset <= 0; req_length <= 8;
            received_words <= 0; expected_words <= 2; response_bad <= 0;
            header_magic_ok <= 0; header_loop <= 0;
            write_ptr <= 0; read_ptr <= 0; fifo_count <= 0;
            read_pending <= 0; head_valid <= 0; head <= 0;
            raw_l <= 0; raw_r <= 0;
        end else begin
            stop <= 0;
            previous_play <= ctl_play;
            read_pending <= ram_read;
            if (read_pending) begin
                head <= ram_q;
                head_valid <= 1;
            end
            // Counts include the prefetched head until it is actually played.
            case ({block_commit, consume})
                2'b10: fifo_count <= fifo_count + COUNT_BITS'(expected_words);
                2'b01: fifo_count <= fifo_count - 1'b1;
                2'b11: fifo_count <= fifo_count + COUNT_BITS'(expected_words) - 1'b1;
                default: ;
            endcase
            if (!ctl_play) begin
                raw_l <= 0;
                raw_r <= 0;
                underrun <= 0;
            end else if (sample_ce && playing) begin
                if (audio_frame >= total_frames) begin
                    // Keep the final frame for a full 1/44100 second before stop.
                    raw_l <= 0; raw_r <= 0;
                    ended <= 1;
                    stop <= 1;
                    underrun <= 0;
                end else if (head_valid) begin
                    raw_l <= $signed(head[15:0]);
                    raw_r <= $signed(head[31:16]);
                    head_valid <= 0;
                    read_ptr <= read_ptr + 1'b1;
                    audio_frame <= (audio_frame == total_frames - 1 && ctl_repeat) ?
                                   audio_loop_index : audio_frame + 1'b1;
                    underrun <= 0;
                end else begin
                    // A missing frame produces silence, never stale repeated PCM.
                    // Do not advance time in the file: resume at the same frame.
                    raw_l <= 0; raw_r <= 0;
                    underrun <= 1;
                    if (!(&underrun_count)) underrun_count <= underrun_count + 1'b1;
                end
            end

            if (receive_word && state != DRAIN) begin
                if (received_words < 1023) received_words <= received_words + 1'b1;
                if (received_words >= {1'b0, expected_words}) response_bad <= 1;
                if (state == HEADER_RX) begin
                    if (received_words == 0) header_magic_ok <= resp_data == 32'h3155534d;
                    if (received_words == 1) header_loop <= resp_data;
                end
            end
            case (state)
                HEADER_REQ, PCM_REQ: if (req_ready) begin
                    state <= state == HEADER_REQ ? HEADER_RX : PCM_RX;
                    received_words <= 0;
                    expected_words <= req_length[10:2];
                    response_bad <= 0;
                end
                HEADER_RX: if (resp_done && good_response) begin
                    if (!completed_magic_ok) begin
                        missing <= 1; ready <= 0; stop <= 1; state <= IDLE;
                    end else begin
                        // Broken loop indices safely restart at frame zero.
                        audio_loop_index <= completed_loop < total_frames ? completed_loop : 0;
                        audio_frame <= resume_start;
                        fetch_frame <= resume_start;
                        // Initial latency buys at least half a FIFO of protection
                        // against host jitter; short tails start when fully buffered.
                        startup_frames <= initial_frames < DEPTH/2 ?
                                          COUNT_BITS'(initial_frames) : COUNT_BITS'(DEPTH/2);
                        state <= FILL;
                    end
                end
                FILL: if (!ended && (fetch_frame < total_frames || ctl_repeat) &&
                          next_words != 0 && (COUNT_BITS'(DEPTH) - fifo_count >= COUNT_BITS'(next_words))) begin
                    req_offset <= 8 + (next_fetch << 2);
                    req_length <= {next_words, 2'b00};
                    request_frame <= next_fetch;
                    state <= PCM_REQ;
                end
                PCM_RX: if (block_commit) begin
                    write_ptr <= write_ptr + PTR_BITS'(expected_words);
                    fetch_frame <= request_frame + {23'b0, expected_words};
                    if (fifo_count + COUNT_BITS'(expected_words) >= startup_frames) ready <= 1;
                    state <= FILL;
                end
                DRAIN: if (resp_done) begin
                    state <= loaded && !missing ? HEADER_REQ : IDLE;
                    req_offset <= 0; req_length <= 8;
                    received_words <= 0; expected_words <= 2; response_bad <= 0;
                end
                default: ;
            endcase

            if (block_fail) begin
                missing <= 1; ready <= 0; stop <= 1; state <= IDLE;
                fifo_count <= 0; head_valid <= 0; read_pending <= 0;
                raw_l <= 0; raw_r <= 0;
            end
            // Replaying an ended track is the same safe transaction boundary as
            // a new load; re-read the header so queued loop data cannot leak.
            if (track_load || restart) begin
                if ((state == HEADER_RX || state == PCM_RX || state == DRAIN) && !resp_done)
                    state <= DRAIN;
                else state <= (track_load ? file_shape_valid : loaded && !missing) ? HEADER_REQ : IDLE;
                if (track_load) begin
                    loaded <= file_shape_valid;
                    missing <= !file_shape_valid;
                    total_frames <= (track_size - 8) >> 2;
                    requested_resume <= ctl_resume ? resume_frame : 0;
                end else requested_resume <= 0;
                ready <= 0; ended <= 0; underrun <= 0;
                audio_frame <= 0; audio_loop_index <= 0;
                fetch_frame <= 0; request_frame <= 0;
                req_offset <= 0; req_length <= 8;
                received_words <= 0; expected_words <= 2; response_bad <= 0;
                header_magic_ok <= 0; header_loop <= 0;
                write_ptr <= 0; read_ptr <= 0; fifo_count <= 0;
                read_pending <= 0; head_valid <= 0;
                raw_l <= 0; raw_r <= 0;
                stop <= track_load && !file_shape_valid;
            end
        end
    end

    initial begin
        if (BUFFER_BYTES != 4096 && BUFFER_BYTES != 8192 && BUFFER_BYTES != 16384)
            $error("BUFFER_BYTES must be 4096, 8192, or 16384");
        if (CLK_RATE < 44100) $error("CLK_RATE must be at least 44100");
    end
endmodule
