`timescale 1ns/1ps
// Actual vendor dcfifo -> cart lifecycle -> production CDC -> production engine.
// No ready shortcut. Pin scoreboard independently decodes legacy row/col/bank.
module tb_rom_download_backend #(
    parameter integer PAL=0
);
    localparam realtime SYS_HALF = PAL ? 23.495 : 23.281;
    reg src=0,sys=0,mem=0;
    always #6.734 src=~src;
    always #(SYS_HALF) sys=~sys;
    always #(SYS_HALF/5.0) mem=~mem;
    reg hard_reset_n=0,locked=0,active=0,wr=0,little=1;
    reg soft_reset=0,flush_ack=1;
    reg [31:0] addr=0,data=0;
    wire valid,en,busy,complete,qfault,ready;
    wire [24:0] wa;wire [15:0] wd;
    reg [16:0] config_in=0,source_snapshot=0;
    wire [16:0] config_out;wire config_valid;
    rom_download_queue queue(
        .save_read_request(1'b0),.save_read_ready(),.save_read_quiescent(1'b1),
        .clk_74a(src),.clk_memory(sys),.hard_reset_n(hard_reset_n&&locked),
        .bridge_wr(wr),.bridge_endian_little(little),.bridge_addr(addr),
        .bridge_wr_data(data),.download_active(active),.config_in(config_in),
        .config_out(config_out),.config_valid(config_valid),.write_valid(valid),
        .write_ready(ready),.write_en(en),.write_addr(wa),.write_data(wd),
        .save_ready(1'b1),.image_busy(busy),.image_complete(complete),.fault(qfault));
    wire client_flush,run,fault;
    wire [7:0] epoch;wire cke,cs,ras,cas,we,oe;
    wire [12:0] ma;wire [1:0] ba,dqm;wire [15:0] md;
    sdram_cart_port cart(
        .clk_sys(sys),.clk_sdram(mem),.hard_reset_n(hard_reset_n),.pll_locked(locked),
        .soft_reset(soft_reset),.download_active(busy),.download_complete(complete),
        .download_fault(qfault),.download_valid(valid),.download_ready(ready),
        .download_addr(wa),.download_data(wd),.client_flush(client_flush),
        .client_flush_ack(flush_ack),.client_fault(1'b0),.epoch(epoch),.run_ready(run),.fault(fault),
        .req_valid(1'b0),.req_ready(),.req_addr(24'b0),.req_channel(1'b0),.req_write(1'b0),
        .req_drain(1'b0),.req_wdata(16'b0),.req_wstrb(2'b0),.req_owner(5'b0),.req_tag(8'b0),.req_epoch(8'b0),
        .rsp_valid(),.rsp_ready(1'b1),.rsp_data(),.rsp_error(),.rsp_owner(),.rsp_tag(),.rsp_epoch(),
        .dram_cke(cke),.dram_cs_n(cs),.dram_ras_n(ras),.dram_cas_n(cas),.dram_we_n(we),
        .dram_addr(ma),.dram_ba(ba),.dram_dqm(dqm),.dq_in(16'b0),.dq_out(md),.dq_oe(oe));
    reg [24:0] expect_addr[0:65535];reg [15:0] expect_data[0:65535];
    reg [16:0] expect_config[0:65535];
    integer expected=0,accepted=0,writes=0,refreshes=0;
    integer config_accepted=0,config_changes=0;
    reg [16:0] config_before;
    reg accepted_now,safe_adoption;
    always @(posedge sys) begin
        config_before=config_out;accepted_now=en;
        safe_adoption=flush_ack && cart.transport_idle && !run;
        #1;
        if(!hard_reset_n || !locked) begin
            config_accepted=0;
            if(config_valid || config_out!==0) $fatal(1,"CONFIG_RESET retained invalid image config");
        end else if(!qfault) begin
            if(accepted_now) begin
                if(!config_valid || config_out!==expect_config[config_accepted])
                    $fatal(1,"CONFIG_ORDER n=%0d got=%h expected=%h",config_accepted,config_out,expect_config[config_accepted]);
                config_accepted=config_accepted+1;
            end
            if(config_out!==config_before) begin
                config_changes=config_changes+1;
                if(!accepted_now || !safe_adoption)
                    $fatal(1,"CONFIG_EARLY changed before old clients/physical transport drained");
            end
        end
    end
    integer max_pending=0,cycle=0,first_accept=0,last_accept=0;
    integer end_before_backend=0,stall_cycles=0;
    reg [12:0] row[0:3];reg bank_open[0:3];
    reg stalled=0;reg [40:0] held;
    realtime last_refresh=0.0,max_refresh_gap=0.0;
    reg refresh_seen=0;
    always @(negedge locked) begin refresh_seen=0;last_refresh=0.0;end
    always @(posedge sys) begin
        cycle=cycle+1;
        if(hard_reset_n&&locked) begin
            if(stalled && !qfault && (!valid || {wa,wd}!==held)) $fatal(1,"BACKPRESSURE changed word");
            stalled=valid&&!ready&&!qfault;held={wa,wd};
            if(valid&&!ready)stall_cycles=stall_cycles+1;
            if(en) begin
                if(accepted==0)first_accept=cycle;
                last_accept=cycle;
                if(accepted>=expected || wa!==expect_addr[accepted] || wd!==expect_data[accepted])
                    $fatal(1,"ACCEPT_ORDER n=%0d",accepted);
                accepted=accepted+1;
            end
            if(expected-accepted>max_pending)max_pending=expected-accepted;
            if(complete && !cart.transport_idle)end_before_backend=end_before_backend+1;
            if(run && (!config_valid || !complete || busy || valid || writes!=accepted || soft_reset || qfault))
                $fatal(1,"EARLY_RUN incomplete physical drain");
        end else stalled=0;
    end
    always @(negedge mem) if(hard_reset_n&&locked&&cke&&!cs) begin
        if(!ras&&cas&&we) begin row[ba]=ma;bank_open[ba]=1;end
        if(!ras&&cas&&!we) begin
            if(ma[10])begin for(integer b=0;b<4;b=b+1)bank_open[b]=0;end
            else bank_open[ba]=0;
        end
        if(refresh_seen && cart.engine.init_done && $realtime-last_refresh>7812.5)
            $fatal(1,"REFRESH_DEADLINE gap_ns=%0.3f",$realtime-last_refresh);
        if(!ras&&!cas&&we)begin
            refreshes=refreshes+1;
            if(refresh_seen&&$realtime-last_refresh>max_refresh_gap)max_refresh_gap=$realtime-last_refresh;
            refresh_seen=1;last_refresh=$realtime;
        end
        if(ras&&!cas&&!we) begin
            if(!bank_open[ba] || !oe || dqm!=0 || writes>=expected ||
               {ba[0],ma[8:0],row[ba],1'b0}!==expect_addr[writes][23:0] ||
               ba[1] || ma[9] || md!==expect_data[writes])
                $fatal(1,"PIN_WRITE n=%0d addr=%h data=%h expected=%h:%h",writes,{ba[0],ma[8:0],row[ba],1'b0},md,expect_addr[writes],expect_data[writes]);
            writes=writes+1;
        end
    end
    task start_image(input [16:0] cfg);
        begin
            @(negedge src);config_in=cfg;source_snapshot=cfg;active=1;
            repeat(2)@(negedge src);
            // A later loader's source staging writes must not alter this image.
            config_in=~cfg;
        end
    endtask
    task stop_image;
        begin @(negedge src);active=0;repeat(2)@(negedge src);end
    endtask
    task packet(input [24:0] a,input [31:0] d,input bit le,input integer period_cycles);
        reg [31:0] ordered;
        begin
            ordered=le ? d : {d[7:0],d[15:8],d[23:16],d[31:24]};
            expect_config[expected]=source_snapshot;expect_addr[expected]=a;expect_data[expected]=ordered[15:0];expected=expected+1;
            expect_config[expected]=source_snapshot;expect_addr[expected]=a+25'd2;expect_data[expected]=ordered[31:16];expected=expected+1;
            @(negedge src);wr=1;addr={4'h1,3'b0,a};data=d;little=le;
            @(negedge src);wr=0;
            repeat(period_cycles-2) @(negedge src);
        end
    endtask
    task await_run;
        integer n;
        begin
            n=0;while(!run&&!fault&&!qfault&&n<30000)begin @(negedge sys);n=n+1;end
            if(!run||fault||qfault||writes!=expected||accepted!=expected)
                $fatal(1,"DRAIN_FAIL run=%b fault=%b qfault=%b w=%0d a=%0d e=%0d",run,fault,qfault,writes,accepted,expected);
        end
    endtask
    integer i,good_words,good_packets,good_max_pending;
    initial begin
        for(i=0;i<4;i=i+1)begin row[i]=0;bank_open[i]=0;end
        #112;hard_reset_n=1;locked=1;repeat(12)@(negedge src);
        // Empty save/control transaction cannot create the first valid ROM.
        start_image(17'h14521);stop_image();repeat(20)@(negedge sys);
        if(run||complete||fault||qfault||config_valid||config_out!==0) $fatal(1,"EMPTY_INITIAL mounted uninitialized ROM");
        // Queue three different images while initialization blocks write_ready.
        // A live CDC bundle cannot represent this ordered sequence.
        start_image(17'h01234);packet(0,32'h01020304,1,2);stop_image();
        start_image(17'h1abcd);packet(4,32'h05060708,0,2);stop_image();
        start_image(17'h06598);packet(8,32'h09101112,1,2);stop_image();
        repeat(20)@(negedge sys);
        if(config_valid || config_out!==0 || accepted!=0) $fatal(1,"CONFIG_INIT adopted queued config before initialization");
        // Begin immediately, while engine still owes >=200us initialization.
        start_image(17'h09820);
        for(i=0;i<64;i=i+1)packet(i*4,32'h67891234^i,i[0],2);
        fork
            begin
                // Admission stall plus emulator reset during accepted download.
                // Queue itself has no soft-reset input; tokens must survive.
                wait(accepted>=1000);wait(en);@(posedge sys);
                @(negedge sys);soft_reset=1;flush_ack=0;
                repeat(500)@(negedge sys);flush_ack=1;
                repeat(100)@(negedge sys);soft_reset=0;
            end
            begin
                for(i=64;i<8192;i=i+1)packet((i*4096)&25'hfffffc,32'h89abcdef^i,i[0],75);
            end
        join
        // Finish final packet and END with no drain delay.
        packet(25'hfffffc,32'ha1b2c3d4,0,2);active=0;
        await_run();
        if(refreshes<500 || max_pending<350 || end_before_backend==0 || stall_cycles<1000)
            $fatal(1,"missing stress/END coverage refresh=%0d pending=%0d end=%0d",refreshes,max_pending,end_before_backend);
        // Actual loader writes map/region before BEGIN: while core can run,
        // source metadata changes must leave the active destination config alone.
        @(negedge src);config_in=17'h1fedc;repeat(20)@(negedge sys);
        if(!run || config_out!==17'h09820) $fatal(1,"CONFIG_EARLY staging changed running map/region");
        // Empty save cycle preserves an existing ROM and drains correctly.
        start_image(17'h13371);wait(busy);stop_image();
        repeat(20)@(negedge sys);await_run();
        if(config_out!==17'h09820 || !config_valid) $fatal(1,"CONFIG_EMPTY save changed map/region");
        // Soft reset on a valid mounted ROM retains config; source config can
        // differ throughout the client flush and resume.
        @(negedge sys);soft_reset=1;flush_ack=0;
        repeat(20)@(negedge sys);
        if(config_out!==17'h09820 || !config_valid || run) $fatal(1,"CONFIG_SOFT reset lost map/region");
        flush_ack=1;soft_reset=0;await_run();
        // Ordered successive mounts: second BEGIN follows END after only two
        // source clocks, well before the previous backend's final completion.
        start_image(17'h03410);
        packet(0,32'h10203040,1,2);@(negedge src);active=0;
        repeat(2)@(negedge src);start_image(17'h1a2d1);
        packet(25'h800000,32'h50607080,0,2);@(negedge src);active=0;
        repeat(40)@(negedge sys);await_run();
        // Adverse burst after init: 128 APF packets at two source cycles each.
        start_image(17'h05162);
        for(i=0;i<128;i=i+1)packet(i*4,32'h55aaff00+i,i[0],2);
        active=0;repeat(20)@(negedge sys);await_run();
        good_words=accepted;good_packets=expected/2;good_max_pending=max_pending;
        // Hard PLL abort while a final word is accepted but mailbox/physical
        // write is still outstanding. It must never mount a partial image.
        start_image(17'h12871);
        packet(0,32'hcafedead,1,2);
        wait(en);@(posedge sys);#1;locked=0;
        expected=0;accepted=0;writes=0;
        for(i=0;i<4;i=i+1)bank_open[i]=0;
        repeat(10)@(negedge src);locked=1;
        repeat(40)@(negedge sys);
        if(run||complete||valid||config_valid||config_out!==0) $fatal(1,"PLL_ABORT mounted/replayed partial image");
        @(negedge src);active=0;repeat(12)@(negedge src);
        start_image(17'h07650);
        packet(0,32'h1234abcd,0,2);active=0;
        repeat(40)@(negedge sys);await_run();
        // Backend admission deliberately blocked beyond the finite queue's
        // capacity. Overflow is a sticky invalid image, never silent success.
        flush_ack=0;start_image(17'h1fe32);
        for(i=0;i<600;i=i+1)packet(i*4,32'hbad00000+i,1,2);
        active=0;repeat(40)@(negedge sys);
        if(!qfault||!fault||run||complete||valid||config_valid) $fatal(1,"OVERFLOW fail-closed propagation");
        flush_ack=1;active=1;repeat(40)@(negedge sys);
        if(!qfault||!fault||run) $fatal(1,"OVERFLOW remount cleared fatal image error");
        // A whole 32-bit APF packet must fit channel 0. The final legal
        // fffffc packet above reaches the final byte; fffffe must enqueue neither
        // halfword and an empty Save cannot recover the invalid hard epoch.
        @(negedge src);hard_reset_n=0;locked=0;active=0;wr=0;
        expected=0;accepted=0;writes=0;
        for(i=0;i<4;i=i+1)bank_open[i]=0;
        repeat(10)@(negedge src);hard_reset_n=1;locked=1;
        repeat(12)@(negedge src);start_image(17'h10e31);
        @(negedge src);wr=1;addr=32'h10fffffe;data=32'hcafefade;
        @(negedge src);wr=0;stop_image();
        repeat(6000)@(negedge sys);
        if(!qfault || !fault || run || valid || config_valid || complete || accepted!=0 || writes!=0)
            $fatal(1,"PACKET_SPAN partial boundary packet reached physical SDRAM");
        start_image(17'h00800);stop_image();repeat(40)@(negedge sys);
        if(!qfault || !fault || run || config_valid || writes!=0)
            $fatal(1,"PACKET_SPAN empty Save revived rejected image");
        if(config_changes<8) $fatal(1,"CONFIG_COVERAGE insufficient distinct image snapshots");
        $display("PASS BACKEND PAL=%0d packets=%0d words=%0d writes=%0d refreshes=%0d max_pending_words=%0d stalled_sys=%0d END_before_drain_sys=%0d max_refresh_ns=%0.3f config_changes=%0d PLL_abort=PASS overflow=PASS packet_span=PASS",PAL,good_packets,good_words,good_words,refreshes,good_max_pending,stall_cycles,end_before_backend,max_refresh_gap,config_changes);
        $finish;
    end
    initial begin #20000000;$fatal(1,"timeout");end
endmodule
