// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module pcm_phase_case #(parameter integer CLK_RATE=44100)(output reg done=0);
    localparam integer PHASE_BITS=$clog2(CLK_RATE+44100);
    reg clk=0; always #5 clk=~clk;
    reg reset=1;
    wire sample_ce;
    reg [31:0] random_word=32'h1629bcde;
    msu_pcm_player #(.CLK_RATE(CLK_RATE), .BUFFER_BYTES(4096)) dut (
        .clk(clk), .reset(reset), .track_load(1'b0), .track_size(32'd0), .track_missing(1'b0),
        .ctl_play(1'b0), .ctl_repeat(1'b0), .ctl_volume(8'd0), .ctl_resume(1'b0), .resume_frame(32'd0),
        .req_ready(1'b0), .resp_valid(1'b0), .resp_data(32'd0), .resp_done(1'b0), .resp_error(1'b0),
        .main_l(16'sd0), .main_r(16'sd0), .sample_ce(sample_ce)
    );
    // Seed valid counter states so the highest supported rates exercise their
    // rollover without simulating billions of clocks. The independent 64-bit
    // reference avoids the RTL's sized and signed arithmetic.
    task automatic check_phase(input [31:0] value);
        reg [63:0] sum, next_phase;
        begin
            @(negedge clk); reset=0; dut.phase=PHASE_BITS'(value);
            sum={32'd0,value}+64'd44100;
            next_phase=sum>=64'(CLK_RATE) ? sum-64'(CLK_RATE) : sum;
            #1;
            if(sample_ce !== (sum>=64'(CLK_RATE)))
                $fatal(1,"Phase tick rate=%0d phase=%0d",CLK_RATE,value);
            @(negedge clk);
            if(dut.phase !== PHASE_BITS'(next_phase) || dut.phase>=CLK_RATE)
                $fatal(1,"Phase next/range rate=%0d phase=%0d next=%0d",CLK_RATE,value,dut.phase);
        end
    endtask
    task automatic check_reset;
        begin
            @(negedge clk); reset=1; #1;
            if(sample_ce!==0)$fatal(1,"Phase tick during reset rate=%0d",CLK_RATE);
            @(negedge clk);
            if(dut.phase!==0)$fatal(1,"Phase reset state rate=%0d",CLK_RATE);
            reset=0; #1;
            if(sample_ce !== (CLK_RATE==44100))
                $fatal(1,"Phase reset release rate=%0d",CLK_RATE);
        end
    endtask
    initial begin
        check_reset();
        check_phase(0); check_phase(1);
        if(CLK_RATE>44100)check_phase(CLK_RATE-44101);
        check_phase(CLK_RATE-44100); check_phase(CLK_RATE-44099); check_phase(CLK_RATE-1);
        for(integer i=0;i<128;i=i+1) begin
            random_word=random_word*32'd1103515245+32'd12345;
            check_phase(random_word % CLK_RATE);
            if(i%17==0)check_reset();
        end
        check_reset();
        done=1;
    end
endmodule

module test_pcm_phase;
    wire [36:0] done;
    // Test both sides of every possible PHASE_BITS width transition.
    genvar bit_count;
    generate for(bit_count=17;bit_count<=31;bit_count=bit_count+1)begin : widths
        pcm_phase_case #(.CLK_RATE(32'((64'd1<<bit_count)-44100))) below(done[2*(bit_count-17)]);
        pcm_phase_case #(.CLK_RATE(32'((64'd1<<bit_count)-44099))) above(done[2*(bit_count-17)+1]);
    end endgenerate
    pcm_phase_case #(.CLK_RATE(44100)) minimum(done[30]);
    pcm_phase_case #(.CLK_RATE(44101)) near_minimum(done[31]);
    pcm_phase_case #(.CLK_RATE(88200)) twice_rate(done[32]);
    pcm_phase_case #(.CLK_RATE(21477270)) ntsc(done[33]);
    pcm_phase_case #(.CLK_RATE(21281370)) pal(done[34]);
    pcm_phase_case #(.CLK_RATE(2147483647)) maximum(done[35]);
    pcm_phase_case #(.CLK_RATE(1000000)) arbitrary_rate(done[36]);
    initial begin
        wait(&done);
        $display("PASS phase: 37 rates, width boundaries, minimum/maximum, NTSC/PAL, seeded rollover and reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"Phase test timeout"); end
endmodule
