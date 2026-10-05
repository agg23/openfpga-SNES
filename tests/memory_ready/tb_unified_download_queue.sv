`timescale 1ns/1ps
// Transport-level destination backpressure; full Intel RAM/frontier tests are
// in tests/save_order. This bench uses the actual Intel dcfifo implementation.
module tb_unified_download_queue;
    reg src=0,sys=0;
    always #6.734 src=~src;
    always #23.495 sys=~sys;
    reg reset_n=0,active=0,wr=0,little=1,rr=0,sr=0;
    reg [31:0] addr=0,data=0;
    reg [16:0] cfg=0,snapshot=0;
    wire rv,re,sv,se,ib,sb,busy,complete,fault,cv;
    wire [24:0] ra;wire [16:0] sa,co;wire [15:0] rd,sd;
    rom_download_queue dut(.save_read_request(1'b0),.save_read_ready(),.save_read_quiescent(1'b1),
        .clk_74a(src),.clk_memory(sys),.hard_reset_n(reset_n),
        .bridge_wr(wr),.bridge_endian_little(little),.bridge_addr(addr),.bridge_wr_data(data),
        .download_active(active),.config_in(cfg),.config_out(co),.config_valid(cv),
        .write_valid(rv),.write_ready(rr),.write_en(re),.write_addr(ra),.write_data(rd),
        .save_valid(sv),.save_ready(sr),.save_en(se),.save_addr(sa),.save_data(sd),
        .image_begin(ib),.save_busy(sb),.image_busy(busy),.image_complete(complete),.fault(fault));
    reg exp_save[0:8191];reg [24:0] exp_addr[0:8191];reg [15:0] exp_data[0:8191];
    reg [16:0] exp_cfg[0:8191];
    integer physical_accepts=0;
    integer expected=0,accepted=0,rom_words=0,save_words=0,begins=0,max_used=0;
    reg check_data=1,rs=0,ss=0;
    reg [40:0] rheld;reg [32:0] sheld;
    reg [16:0] oldcfg;reg oldcv,rom_accept,save_accept;
    always @(posedge sys) begin
        oldcfg=co;oldcv=cv;rom_accept=re;save_accept=se;
        if(reset_n&&(re||se)) physical_accepts=physical_accepts+1;
        if(!reset_n) begin rs=0;ss=0;end
        else if(!fault) begin
            if(re&&se) $fatal(1,"DESTINATION both outputs accepted");
            if(ib&&se) $fatal(1,"BEGIN_FENCE Save accepted on clear restart edge");
            if((sv||rv||ib)&&!sb) $fatal(1,"PENDING missing save/client busy");
            if(rs&&(!rv||{ra,rd}!==rheld)) $fatal(1,"ROM_STABLE");
            if(ss&&(!sv||{sa,sd}!==sheld)) $fatal(1,"SAVE_STABLE");
            if(ib)begins=begins+1;
            if((re||se)&&check_data) begin
                if(accepted>=expected||se!==exp_save[accepted]||
                   (se?{8'b0,sa}:ra)!==exp_addr[accepted]||
                   (se?sd:rd)!==exp_data[accepted])
                    $fatal(1,"UNIFIED_ORDER word=%0d save=%b addr=%h data=%h",accepted,se,se?{8'b0,sa}:ra,se?sd:rd);
                if(re)rom_words=rom_words+1;else save_words=save_words+1;
                accepted=accepted+1;
            end
            rs=rv&&!rr;rheld={ra,rd};ss=sv&&!sr;sheld={sa,sd};
        end
        #1;
        if(reset_n&&!fault&&check_data) begin
            if(rom_accept && (!cv||co!==exp_cfg[accepted-1])) $fatal(1,"CONFIG_ORDER");
            if(!rom_accept&&(co!==oldcfg||cv!==oldcv)) $fatal(1,"SAVE_CONFIG Save/control adopted ROM config");
        end
    end
    always @(posedge src) if(reset_n && dut.transport_fifo.wrusedw>max_used)
        max_used=dut.transport_fifo.wrusedw;
    task reset_epoch;
        begin
            @(negedge src);reset_n=0;active=0;wr=0;rr=0;sr=0;
            repeat(12)@(negedge src);expected=0;accepted=0;physical_accepts=0;check_data=1;
            reset_n=1;repeat(12)@(negedge src);
        end
    endtask
    task start(input [16:0] value);
        begin @(negedge src);cfg=value;snapshot=value;active=1;repeat(2)@(negedge src);cfg=~value;end
    endtask
    task stop;
        begin @(negedge src);active=0;repeat(2)@(negedge src);end
    endtask
    task expect_packet(input bit save,input [24:0] a,input [31:0] d,input bit le);
        reg [31:0] v;
        begin
            v=le?d:{d[7:0],d[15:8],d[23:16],d[31:24]};
            for(integer h=0;h<2;h=h+1)begin
                exp_save[expected]=save;exp_addr[expected]=a+h*2;exp_data[expected]=h?v[31:16]:v[15:0];exp_cfg[expected]=snapshot;expected=expected+1;
            end
        end
    endtask
    task packet(input bit save,input [24:0] a,input [31:0] d,input bit le,input integer gap);
        begin
            expect_packet(save,a,d,le);
            @(negedge src);wr=1;addr={save?4'h2:4'h1,3'b0,a};data=d;little=le;
            @(negedge src);wr=0;repeat(gap)@(negedge src);
        end
    endtask
    task drain;
        integer n;
        begin
            n=0;
            while((accepted!=expected||sb||busy)&&!fault&&n<20000)begin @(negedge sys);n=n+1;end
            repeat(16)@(negedge sys);
            if(fault||accepted!=expected||sb||busy) $fatal(1,"DRAIN accepted=%0d expected=%0d",accepted,expected);
        end
    endtask
    task fail_closed;
        begin repeat(40)@(negedge sys);
            if(!fault||rv||sv||complete||cv||!busy||!sb) $fatal(1,"FAIL_CLOSED");
            stop();start(17'h12345);stop();repeat(20)@(negedge sys);
            if(!fault) $fatal(1,"FAIL_STICKY");
        end
    endtask
    integer i,bc,good_max_used;
    initial begin
        reset_epoch();rr=1;sr=1;
        // Independent region-2 restores are legacy-supported even without a
        // download BEGIN. They must not clear RAM or validate/configure ROM.
        packet(1,0,32'h12345678,1,75);packet(1,25'h1fffc,32'habcdef01,0,75);drain();
        expect_packet(1,8,32'h55667788,1);
        @(negedge src);wr=1;addr=32'h20000008;data=32'h55667788;little=1;
        repeat(12)@(negedge src);wr=0;drain();
        if(begins||complete||cv||co!==0) $fatal(1,"INDEPENDENT_SAVE adopted image");
        // Initial Save-only segment also cannot create image validity.
        start(17'h11111);packet(1,0,32'hcafefeed,1,0);stop();drain();
        if(complete||cv) $fatal(1,"SAVE_CONFIG initial Save validated ROM");
        // Save data preceding ROM data in one segment cannot adopt metadata;
        // the later real ROM word alone creates the image authority.
        start(17'h04231);packet(1,4,32'h98765432,0,75);
        if(cv||co!==0) $fatal(1,"SAVE_CONFIG mixed segment adopted early");
        packet(0,0,32'h11223344,1,0);stop();drain();
        if(!cv||co!==17'h04231) $fatal(1,"CONFIG_ORDER mixed segment");
        // Retain a complete old ROM and its config through a Save segment.
        start(17'h03121);packet(0,25'hfffffc,32'h87654321,0,0);stop();drain();
        if(!complete||!cv||co!==17'h03121) $fatal(1,"ROM_VALID");
        sr=0;start(17'h1eeee);packet(1,0,32'h33221100,1,0);stop();
        wait(sv);repeat(40)@(negedge sys);
        if(!busy||complete||co!==17'h03121) $fatal(1,"SAVE_END escaped stalled output");
        sr=1;drain();if(!complete||co!==17'h03121) $fatal(1,"SAVE_CONFIG");
        // Two remounts and Saves queued while the first ROM endpoint is held.
        rr=0;sr=0;bc=begins;
        for(i=0;i<2;i=i+1)begin
            start(17'h09010+i);packet(0,i*4,32'h12345678+i,1,0);stop();
            start(17'h19999);packet(1,i*4,32'haabbccdd+i,0,0);stop();
        end
        repeat(30)@(negedge sys);rr=1;sr=1;drain();
        if(begins!=bc+4||co!==17'h09011) $fatal(1,"QUEUED_BEGIN every BEGIN must restart clear");
        // 128-packet ROM burst followed by Save burst, all ordered in one FIFO.
        rr=0;sr=0;start(17'h07731);
        for(i=0;i<128;i=i+1)packet(0,i*4,32'hfe120000+i,i[0],0);
        stop();start(17'h15555);
        for(i=0;i<128;i=i+1)packet(1,i*4,32'hab340000+i,i[0],0);
        stop();rr=1;sr=1;drain();if(co!==17'h07731) $fatal(1,"SAVE_CONFIG burst");
        // Same-edge BEGIN+Save and END+Save: no first-word acceptance through
        // the cycle before the clear sequencer observes image_begin.
        @(negedge src);snapshot=17'h10001;cfg=snapshot;active=1;wr=1;addr=32'h20000002;data=32'h90807060;little=1;
        expect_packet(1,2,data,1);@(negedge src);wr=0;repeat(75)@(negedge src);
        @(negedge src);active=0;wr=1;addr=32'h2001fffa;data=32'h11121314;little=0;
        expect_packet(1,25'h1fffa,data,0);@(negedge src);wr=0;drain();
        if(co!==17'h07731||!cv||!complete) $fatal(1,"SAVE_CONFIG simultaneous");
        // Independent Save after a good ROM must preserve completion throughout
        // a stall, but still demand client reset via save_busy.
        bc=begins;sr=0;packet(1,8,32'h12345678,1,0);wait(sv);
        repeat(20)@(negedge sys);
        if(!complete||busy||!sb||begins!=bc) $fatal(1,"INDEPENDENT_SAVE lifecycle");
        sr=1;drain();
        // Long paced Save stream exercises pointer wrap and sustained rate.
        start(17'h01234);for(i=0;i<1200;i=i+1)packet(1,i*4,i*32'h1020304,i[0],73);stop();drain();
        // Same metadata still represents two distinct BEGIN/clear events.
        bc=begins;
        for(i=0;i<2;i=i+1)begin
            start(17'h07731);packet(0,0,32'h12345678,1,0);stop();
            start(17'h07731);stop();
        end
        drain();if(begins!=bc+4) $fatal(1,"QUEUED_BEGIN same metadata suppressed clear");
        // Missing END remains busy even after all Save writes were accepted.
        start(17'h01234);packet(1,4,32'h01020304,1,75);
        repeat(100)@(negedge sys);
        if(!busy||complete||accepted!=expected) $fatal(1,"MISSING_END released unfinished segment");
        stop();drain();
        // A queued Save halfword must disappear on PLL loss, not replay.
        sr=0;packet(1,0,32'hcafeabba,1,0);wait(sv);reset_epoch();rr=1;sr=1;
        repeat(20)@(negedge sys);if(sv||sb||cv||complete) $fatal(1,"PLL_SAVE_REPLAY");
        good_max_used=max_used;
        // Whole four-byte Save span checked before either halfword can write.
        for(i=0;i<3;i=i+1)begin
            reset_epoch();check_data=0;sr=1;
            @(negedge src);wr=1;addr=i==0?32'h2001fffe:i==1?32'h20020000:32'h20000001;data=0;
            @(negedge src);wr=0;fail_closed();if(physical_accepts) $fatal(1,"SAVE_SPAN partial invalid packet");
        end
        // A changing Save strobe held high is malformed, as for ROM.
        reset_epoch();check_data=0;
        @(negedge src);wr=1;addr=32'h20000000;data=1;
        @(negedge src);addr=32'h20000004;data=2;
        @(negedge src);wr=0;fail_closed();
        // Overflow is explicit, including Save outside a download segment.
        reset_epoch();check_data=0;
        for(i=0;i<540;i=i+1)begin
            @(negedge src);wr=1;addr=32'h20000000+i*4;data=i;
            @(negedge src);wr=0;
        end
        fail_closed();
        $display("PASS UNIFIED: ROM_words=%0d Save_words=%0d BEGINs=%0d max_good_FIFO_used=%0d max_wrusedw_including_overflow=%0d; ordered destinations/config, independent Save, 128+128 burst, pacing, simultaneous boundaries, stalls, capacity/endian, reset, overflow",rom_words,save_words,begins,good_max_used,max_used);
        $finish;
    end
    initial begin #20000000;$fatal(1,"TIMEOUT");end
endmodule
