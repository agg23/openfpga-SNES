`timescale 1ns/1ps
module test_pcm_player;
    parameter BUFFER_BYTES = 4096;
    reg clk=0; always #5 clk=~clk;
    reg reset=1,track_load=0,track_missing=0,ctl_play=0,ctl_repeat=0,ctl_resume=0;
    reg [31:0] track_size=0,resume_frame=0;
    reg [7:0] ctl_volume=255;
    wire busy,missing,playing,stop,underrun,sample_ce;
    wire [31:0] underrun_count,audio_frame,audio_loop_index;
    wire [15:0] fifo_level;
    wire req_valid,resp_ready;
    reg req_ready=0,resp_valid=0,resp_done=0,resp_error=0;
    wire [31:0] req_offset;
    wire [10:0] req_length;
    reg [31:0] resp_data=0;
    reg signed [15:0] main_l=0,main_r=0;
    wire signed [15:0] pcm_l,pcm_r,mixed_l,mixed_r;
    msu_pcm_player #(.CLK_RATE(441000),.BUFFER_BYTES(BUFFER_BYTES)) dut(.*);

    integer selected_track=1,host_track=1,host_offset=0,host_words=0,host_index=0;
    integer accepted_requests=0,completed_requests=0,delay_cycles=0;
    integer inject_error=0,inject_short=0,inject_extra=0,host_active=0,host_done_pending=0;
    reg host_accept=1,host_pause=0,coincident_done=0;
    integer score_enabled=0,score_track=1,score_frame=0,score_total=0,score_loop=0;
    integer samples_checked=0,stop_count=0,consumed_before=0,requests_before=0;
    integer max_occupancy=0;
    localparam integer HUGE_FRAMES=1073741821; // (0xfffffffc - 8) / 4
    localparam integer HUGE_RESUME=HUGE_FRAMES-4;
    localparam integer HUGE_LOOP=HUGE_FRAMES-2;
    integer huge_header_reads=0,huge_tail_reads=0,huge_loop_reads=0;
    integer huge_stop_before=0;
    reg [31:0] last_request_offset=0;
    reg [10:0] last_request_length=0;
    reg [31:0] expected_word;
    integer expected_l,expected_r,expected_mix_l,expected_mix_r;

    function [31:0] file_word(input integer track,input integer word_index);
        integer frame,l,r;
        begin
            if(word_index==0) file_word = track==4 ? 32'h00000000 : 32'h3155534d;
            else if(word_index==1) file_word = track==1 ? 1 : track==3 ? 999999 : track==5 ? HUGE_LOOP : 257;
            else begin
                frame=word_index-2;
                if(track==1) begin
                    case(frame)
                        0: begin l=1000;r=-1000;end
                        1: begin l=-32768;r=32767;end
                        default: begin l=1234;r=-2345;end
                    endcase
                end else begin l=((frame*257+track*101)&65535)-32768; r=-l-1;end
                file_word={16'(r),16'(l)};
            end
        end
    endfunction

    // Variable-latency, backpressured host, binding a request to its file when
    // accepted. It can finish on the final data word or in a separate cycle.
    always @(negedge clk) begin
        req_ready = host_accept && !host_active;
        resp_valid=0;resp_done=0;resp_error=0;
        if (!reset && host_active && !host_pause) begin
            if(delay_cycles>0) delay_cycles=delay_cycles-1;
            else if(host_done_pending) begin
                resp_done=1;resp_error=(inject_error==1 || (inject_error==2 && host_offset!=0));
            end else if(host_index < host_words) begin
                resp_valid=1;resp_data=file_word(host_track,host_offset+host_index);
                if(coincident_done && host_index==host_words-1) begin
                    resp_done=1;resp_error=(inject_error==1 || (inject_error==2 && host_offset!=0));
                end
            end
        end
    end
    always @(posedge clk) begin
        if(reset) begin host_active=0;host_done_pending=0;end
        else begin
            if(req_valid && req_ready) begin
                if(req_length==0 || req_length>1024 || req_length[1:0] || req_offset[1:0])
                    $fatal(1,"bad request shape %0d/%0d",req_offset,req_length);
                last_request_offset=req_offset;last_request_length=req_length;
                if(selected_track==5) begin
                    if(req_offset==0) begin
                        huge_header_reads=huge_header_reads+1;
                        if(huge_header_reads!=1 || req_length!=8)
                            $fatal(1,"near-4GiB file re-read header or wrapped offset");
                    end else begin
                        if(huge_header_reads!=1 ||
                           ({1'b0,req_offset}+{22'b0,req_length}) > 33'h0fffffffc)
                            $fatal(1,"near-4GiB read outside file");
                        if(req_offset==32'hffffffec && req_length==16)
                            huge_tail_reads=huge_tail_reads+1;
                        else if(req_offset==32'hfffffff4 && req_length==8)
                            huge_loop_reads=huge_loop_reads+1;
                        else $fatal(1,"near-4GiB request offset/length %08x/%0d",req_offset,req_length);
                    end
                end
                host_active=1;host_track=selected_track;host_offset=req_offset/4;
                host_words=req_length/4;host_index=0;host_done_pending=0;
                if((inject_short==1 || (inject_short==2 && host_offset!=0)) && host_words>1) host_words=host_words-1;
                if(inject_extra && host_offset!=0) host_words=host_words+1;
                accepted_requests=accepted_requests+1;
            end
            if(resp_valid && resp_ready) begin
                host_index=host_index+1;
                if(host_index==host_words) host_done_pending=1;
            end
            if(resp_done) begin
                host_active=0;host_done_pending=0;
                completed_requests=completed_requests+1;
            end
            if(stop) stop_count=stop_count+1;
            if(dut.fifo_count > BUFFER_BYTES/4) $fatal(1,"buffer overflow");
            if(dut.fifo_count > max_occupancy) max_occupancy=dut.fifo_count;
            if(score_enabled && dut.consume) begin
                expected_word=file_word(score_track,score_frame+2);
                expected_l=($signed(expected_word[15:0]) * integer'(ctl_volume)) >>> 8;
                expected_r=($signed(expected_word[31:16]) * integer'(ctl_volume)) >>> 8;
                if(audio_frame != score_frame) $fatal(1,"file position %0d expected %0d",audio_frame,score_frame);
                expected_mix_l=expected_l+$signed(main_l);expected_mix_r=expected_r+$signed(main_r);
                if(expected_mix_l>32767) expected_mix_l=32767;
                if(expected_mix_l< -32768) expected_mix_l=-32768;
                if(expected_mix_r>32767) expected_mix_r=32767;
                if(expected_mix_r< -32768) expected_mix_r=-32768;
                score_frame=score_frame+1;
                if(score_frame==score_total && ctl_repeat) score_frame=score_loop;
                samples_checked=samples_checked+1;
                #1;
                if(pcm_l!==16'(expected_l)||pcm_r!==16'(expected_r))
                    $fatal(1,"sample mismatch frame %0d: got %0d,%0d expected %0d,%0d",score_frame,$signed(pcm_l),$signed(pcm_r),expected_l,expected_r);
                if(mixed_l!==16'(expected_mix_l)||mixed_r!==16'(expected_mix_r))
                    $fatal(1,"saturated mixer mismatch");
            end
        end
    end

    task cycles(input integer n);repeat(n) @(negedge clk);endtask
    task load_track(input integer track,input integer frames,input integer resume_at,input integer is_missing);
        begin
            score_enabled=0;ctl_play=0;ctl_repeat=0;
            @(negedge clk);
            selected_track=track;track_size=8+frames*4;track_missing=is_missing;
            if(track==5) begin huge_header_reads=0;huge_tail_reads=0;huge_loop_reads=0;end
            ctl_resume=resume_at!=0;resume_frame=resume_at;track_load=1;
            @(negedge clk);track_load=0;
        end
    endtask
    task ready_track;
        integer budget,required_frames;
        begin
            budget=20000;
            while(busy && budget>0) begin cycles(1);budget=budget-1;end
            if(budget==0||missing) $fatal(1,"load failed state=%0d missing=%0d",dut.state,missing);
            required_frames=dut.total_frames-dut.resume_start;
            if(required_frames>BUFFER_BYTES/8) required_frames=BUFFER_BYTES/8;
            if(fifo_level<required_frames) $fatal(1,"busy cleared before startup prefill");
            cycles(5);
        end
    endtask
    task score_start(input integer track,input integer frame,input integer frames,input integer loop_frame);
        begin score_track=track;score_frame=frame;score_total=frames;score_loop=loop_frame;score_enabled=1;ctl_play=1;end
    endtask
    task check_samples(input integer n);
        integer target,budget;
        begin
            target=samples_checked+n;budget=n*30+20000;
            while(samples_checked<target&&budget>0)begin cycles(1);budget=budget-1;end
            if(budget==0) $fatal(1,"timed out waiting samples");
        end
    endtask

    initial begin
        cycles(5);reset=0;cycles(2);
        // Header excluded, signed stereo exact, partial tail and final sample duration.
        load_track(1,3,0,0);ready_track();
        if(audio_loop_index!=1) $fatal(1,"bad loop");
        score_start(1,0,3,1);check_samples(3);cycles(15);
        if(!dut.ended || playing || pcm_l!==0 || pcm_r!==0 || score_frame!=3)
            $fatal(1,"EOF did not stop cleanly");
        if(stop_count!=1) $fatal(1,"EOF must pulse stop once: %0d",stop_count);
        // Play after EOF restarts; then continuous repeated exact nonzero loop.
        ctl_play=0;cycles(2);ctl_repeat=1;score_frame=0;ctl_play=1;
        check_samples(30);
        if(missing||stop_count!=1) $fatal(1,"repeat unexpectedly stopped");
        // Immediate volume and saturated signed mixing, including -32768.
        ctl_volume=0;cycles(1);
        if(pcm_l!==0||pcm_r!==0) $fatal(1,"zero volume");
        ctl_volume=255;main_l=32767;main_r=-32768;
        while(pcm_l<=0) cycles(1);
        if(mixed_l!==16'sh7fff) $fatal(1,"positive clipping");
        while(pcm_r>=0) cycles(1);
        if(mixed_r!==16'sh8000) $fatal(1,"negative clipping");
        main_l=0;main_r=0;
        ctl_volume=1;check_samples(10);ctl_volume=128;check_samples(10);ctl_volume=255;
        // Pause emits silence, retaining exact next-frame position.
        ctl_play=0;consumed_before=samples_checked;cycles(100);
        if(samples_checked!=consumed_before||pcm_l!==0||pcm_r!==0) $fatal(1,"pause advanced");
        ctl_play=1;check_samples(20);
        // Disabling repeat discards prefetched next-loop audio at the exact EOF.
        ctl_repeat=0;check_samples(score_total-score_frame);cycles(15);
        if(!dut.ended||playing) $fatal(1,"repeat-off played prefetched loop");
        // Hold an unaccepted request, then replace the track before acceptance.
        host_accept=0;requests_before=accepted_requests;
        load_track(2,300,0,0);cycles(30);
        if(!req_valid||req_offset!=0||req_length!=8||accepted_requests!=requests_before)
            $fatal(1,"request did not remain stable under backpressure");
        load_track(1,3,9999,0);cycles(5);host_accept=1;ready_track();
        score_start(1,0,3,1);check_samples(3);cycles(15);
        // Long file, ring wrap, 1KB block boundaries and arbitrary-frame resume.
        load_track(2,3000,253,0);coincident_done=1;ready_track();
        ctl_repeat=1;score_start(2,253,3000,257);check_samples(6500);
        if(max_occupancy<BUFFER_BYTES/4-256) $fatal(1,"prefetch did not use bounded buffer");
        // Starve an outstanding host read until all committed samples drain.
        host_pause=1;cycles((BUFFER_BYTES/4+300)*10);
        if(!underrun||underrun_count==0||pcm_l!==0||pcm_r!==0) $fatal(1,"underrun not silent");
        consumed_before=samples_checked;cycles(100);
        if(samples_checked!=consumed_before) $fatal(1,"underrun advanced file");
        host_pause=0;check_samples(600);
        if(underrun) $fatal(1,"underrun did not recover");
        // New track while an old request is held: discard, drain, then load.
        host_pause=1;
        while(!host_active) cycles(1);
        load_track(1,3,0,0);cycles(20);
        if(!busy||playing||pcm_l!==0) $fatal(1,"seek did not flush");
        host_pause=0;ready_track();score_start(1,0,3,1);check_samples(3);cycles(15);
        // Missing track and malformed/truncated headers fail closed.
        load_track(1,3,0,1);cycles(10);
        if(!missing||busy||playing||req_valid) $fatal(1,"missing track handling");
        load_track(4,300,0,0);cycles(100);
        if(!missing||busy) $fatal(1,"invalid magic accepted");
        inject_short=1;load_track(2,300,0,0);cycles(100);inject_short=0;
        if(!missing||busy) $fatal(1,"short header accepted");
        inject_error=1;load_track(2,300,0,0);cycles(100);inject_error=0;
        if(!missing||busy) $fatal(1,"transport error accepted");
        inject_short=2;load_track(2,300,0,0);cycles(600);inject_short=0;
        if(!missing||busy||fifo_level!=0) $fatal(1,"short PCM block committed");
        inject_extra=1;load_track(2,300,0,0);cycles(600);inject_extra=0;
        if(!missing||busy||fifo_level!=0) $fatal(1,"oversize PCM block committed");
        inject_error=2;load_track(2,300,0,0);cycles(600);inject_error=0;
        if(!missing||busy||fifo_level!=0) $fatal(1,"PCM transport error committed");
        load_track(1,0,0,0);cycles(10);
        if(!missing||busy||req_valid) $fatal(1,"empty PCM file accepted");
        @(negedge clk);track_size=14;track_load=1;
        @(negedge clk);track_load=0;cycles(10);
        if(!missing||busy||req_valid) $fatal(1,"non-frame-aligned file accepted");
        // Invalid loop point normalizes to frame zero, not an out-of-range read.
        load_track(3,10,0,0);ready_track();
        if(audio_loop_index!=0) $fatal(1,"invalid loop not clamped");
        ctl_repeat=1;score_start(3,0,10,0);check_samples(30);
        // Near-4GiB synthetic file: no allocation proportional to file size.
        // Resume at the last four frames, checking full-width byte arithmetic.
        load_track(5,HUGE_FRAMES,HUGE_RESUME,0);ready_track();
        if(track_size!==32'hfffffffc || dut.total_frames!=HUGE_FRAMES ||
           last_request_offset!==32'hffffffec || last_request_length!=16 ||
           audio_frame!=HUGE_RESUME || audio_loop_index!=HUGE_LOOP)
            $fatal(1,"near-4GiB file sizing, resume, or first request incorrect");
        huge_stop_before=stop_count;
        score_start(5,HUGE_RESUME,HUGE_FRAMES,HUGE_LOOP);check_samples(4);cycles(15);
        if(!dut.ended || playing || missing || pcm_l!==0 || pcm_r!==0 ||
           score_frame!=HUGE_FRAMES || audio_frame!=HUGE_FRAMES ||
           huge_header_reads!=1 || huge_tail_reads!=1 || huge_loop_reads!=0 ||
           stop_count!=huge_stop_before+1)
            $fatal(1,"near-4GiB final four frames/EOF incorrect");
        // The final two frames also make a legal nonzero loop near 0xffffffff.
        load_track(5,HUGE_FRAMES,HUGE_RESUME,0);ready_track();
        huge_stop_before=stop_count;ctl_repeat=1;
        score_start(5,HUGE_RESUME,HUGE_FRAMES,HUGE_LOOP);check_samples(40);
        if(missing || !playing || stop_count!=huge_stop_before ||
           huge_header_reads!=1 || huge_tail_reads!=1 || huge_loop_reads<2)
            $fatal(1,"near-4GiB loop failed or wrapped to header");
        $display("PASS near-4GiB PCM: bytes=fffffffc tail=ffffffec loop=fffffff4; four-frame EOF and 40-frame repeat checked");
        $display("PASS PCM buffer=%0d: samples=%0d requests=%0d max_frames=%0d underruns=%0d",BUFFER_BYTES,samples_checked,accepted_requests,max_occupancy,underrun_count);
        $finish;
    end
    initial begin #30000000;$fatal(1,"global timeout");end
endmodule
