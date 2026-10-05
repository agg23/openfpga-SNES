`timescale 1ns/1ps
module test_pcm_rate;
    reg clk=0; always #1 clk=~clk;
    reg reset=1;
    wire ntsc_ce,pal_ce;
    msu_pcm_player #(.CLK_RATE(21477270),.BUFFER_BYTES(4096)) ntsc(
        .clk(clk),.reset(reset),.track_load(1'b0),.track_size(32'd0),.track_missing(1'b0),
        .ctl_play(1'b0),.ctl_repeat(1'b0),.ctl_volume(8'd0),.ctl_resume(1'b0),.resume_frame(32'd0),
        .req_ready(1'b0),.resp_valid(1'b0),.resp_data(32'd0),.resp_done(1'b0),.resp_error(1'b0),
        .main_l(16'sd0),.main_r(16'sd0),.sample_ce(ntsc_ce));
    msu_pcm_player #(.CLK_RATE(21281370),.BUFFER_BYTES(4096)) pal(
        .clk(clk),.reset(reset),.track_load(1'b0),.track_size(32'd0),.track_missing(1'b0),
        .ctl_play(1'b0),.ctl_repeat(1'b0),.ctl_volume(8'd0),.ctl_resume(1'b0),.resume_frame(32'd0),
        .req_ready(1'b0),.resp_valid(1'b0),.resp_data(32'd0),.resp_done(1'b0),.resp_error(1'b0),
        .main_l(16'sd0),.main_r(16'sd0),.sample_ce(pal_ce));
    integer n=0,p=0,cycles=0,last_n=0,last_p=0;
    integer gap;
    always @(posedge clk) if(!reset) begin
        cycles=cycles+1;
        if(ntsc_ce) begin
            gap=cycles-last_n;
            if(last_n!=0&&gap!=487&&gap!=488) $fatal(1,"NTSC bad cadence %0d",gap);
            last_n=cycles;n=n+1;
        end
        if(pal_ce) begin
            gap=cycles-last_p;
            if(last_p!=0&&gap!=482&&gap!=483) $fatal(1,"PAL bad cadence %0d",gap);
            last_p=cycles;p=p+1;
        end
    end
    initial begin
        repeat(3) @(negedge clk);reset=0;
        // 0.1 NTSC seconds: exactly 4410 ticks, PAL independently checked.
        repeat(2147727) @(negedge clk);
        if(n!=4410 || p!=4450) $fatal(1,"wrong average NTSC=%0d PAL=%0d",n,p);
        $display("PASS rate: %0d cycles, NTSC=%0d PAL=%0d; floor/ceil cadence checked",cycles,n,p);
        $finish;
    end
endmodule
