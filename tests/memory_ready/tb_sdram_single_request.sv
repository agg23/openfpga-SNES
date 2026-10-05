`timescale 1ns/1ps
module tb_sdram_single_request;
    parameter integer CLK_HZ=107386350;
    parameter integer PHYSICAL_CLK_HZ=CLK_HZ;
    parameter realtime RETURN_DELAY_NS=3.0;
    localparam realtime HALF_PERIOD_NS=5.0e8/PHYSICAL_CLK_HZ;
    logic clk_mem=0;
    always #(HALF_PERIOD_NS) clk_mem=~clk_mem;
    logic reset_n=0, pll_locked=0;
    logic req_valid=0, req_write=0, rsp_ready=0;
    logic [31:0] req_addr=0;
    logic [15:0] req_wdata=0;
    logic [1:0] req_wstrb=0;
    wire req_ready, rsp_valid, rsp_error, init_done;
    wire [15:0] rsp_rdata, dq_in, dq_out;
    wire cke,cs_n,ras_n,cas_n,we_n,dq_oe;
    wire [12:0] addr;
    wire [1:0] ba,dqm;
    wire dq_valid,dq_driving,device_initialized;
    sdram_single_request #(.CLK_HZ(CLK_HZ)) dut(
        .clk_mem, .reset_n, .pll_locked,
        .req_valid, .req_ready, .req_write, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_ready, .rsp_rdata, .rsp_error, .init_done,
        .dram_cke(cke),.dram_cs_n(cs_n),.dram_ras_n(ras_n),
        .dram_cas_n(cas_n),.dram_we_n(we_n),.dram_addr(addr),
        .dram_ba(ba),.dram_dqm(dqm),.dq_in,.dq_out,.dq_oe
    );
    as4c32m16msa_model #(.RETURN_DELAY_NS(RETURN_DELAY_NS)) model(
        .clk_mem,.epoch_ok(reset_n && pll_locked),.cke,.cs_n,.ras_n,.cas_n,.we_n,
        .addr,.ba,.dqm,.dq_out,.dq_oe,.dq_in,.dq_valid,.dq_driving,
        .initialized(device_initialized)
    );

    // A separately indexed logical scoreboard. It sees ONLY accepted requests
    // and responses, whereas the device sees ONLY SDRAM pins.
    logic [15:0] expected_mem[int unsigned];
    logic [15:0] expected_data,held_data;
    logic expected_error,expected_write,held_error;
    bit outstanding=0,held_last=0;
    integer accepted=0,completed=0,aborted=0,illegal_count=0;
    integer accepted_writes=0,accepted_reads=0,hold_cycles=0;
    integer baseline_act,baseline_read,baseline_write;
    integer latency,max_latency=0;
    int unsigned random_state=32'h87654321;

    function automatic int unsigned random_next;
        random_state ^= random_state << 13;
        random_state ^= random_state >> 17;
        random_state ^= random_state << 5;
        return random_state;
    endfunction
    function automatic logic [31:0] physical_address(input integer b,r,c);
        return 32'(b)*32'h1000000 + 32'(r)*32'h800 + 32'(c)*2;
    endfunction
    function automatic logic [15:0] pattern(input logic [31:0] a);
        // Mix every bank/row/column bit into a nonzero 16-bit test value.
        logic [31:0] mix;
        mix=(a>>1)*32'h9e3779b1;
        return 16'(mix ^ (mix>>16) ^ 32'hb65a);
    endfunction

    always @(posedge clk_mem) begin : transaction_monitor
        int unsigned key;
        logic [15:0] w;
        if(!reset_n || !pll_locked) begin
            if(outstanding) aborted++;
            outstanding=0; held_last=0; expected_mem.delete(); latency=0;
            #0.001;
            if(req_ready || rsp_valid || init_done || dq_oe)
                $fatal(1,"TB_RESET: interface not safely inhibited");
        end else begin
            if(held_last && (!rsp_valid || rsp_rdata!==held_data || rsp_error!==held_error))
                $fatal(1,"TB_HELD_RESPONSE: data/error/valid changed under backpressure");
            if(rsp_valid && !rsp_ready) begin
                if(req_ready) $fatal(1,"TB_ONE_OUTSTANDING: req_ready while response held");
                held_data=rsp_rdata; held_error=rsp_error; hold_cycles++;
            end
            held_last=rsp_valid && !rsp_ready;
            if(outstanding) begin latency++; if(latency>max_latency) max_latency=latency; end
            // Consuming an old response and accepting its replacement on the
            // same edge is allowed. Never permit two unconsumed requests.
            if(rsp_valid && rsp_ready) begin
                if(!outstanding) $fatal(1,"TB_DUPLICATE_RESPONSE: no accepted owner");
                if(rsp_error!==expected_error)
                    $fatal(1,"TB_RESPONSE_ERROR: expected=%b actual=%b",expected_error,rsp_error);
                if(!expected_error && !expected_write && rsp_rdata!==expected_data)
                    $fatal(1,"TB_DATA: expected=%h actual=%h accepted=%0d",expected_data,rsp_rdata,accepted);
                if(expected_error && (model.total_act!=baseline_act ||
                   model.total_read!=baseline_read || model.total_write!=baseline_write))
                    $fatal(1,"TB_ILLEGAL_SIDE_EFFECT: invalid request emitted access command");
                outstanding=0; completed++;
            end
            if(req_valid && req_ready) begin
                if(!init_done) $fatal(1,"TB_EARLY_READY: acceptance before initialization");
                if(outstanding) $fatal(1,"TB_ONE_OUTSTANDING: accepted second request");
                outstanding=1; accepted++; latency=0;
                expected_error=(req_addr[31:26]!=0 || req_addr[0]);
                expected_write=req_write;
                baseline_act=model.total_act; baseline_read=model.total_read;
                baseline_write=model.total_write;
                if(expected_error) illegal_count++;
                else begin
                    key=req_addr>>1;
                    if(req_write) begin
                        w=(expected_mem.exists(key)!=0) ? expected_mem[key] : 16'h0000;
                        if(req_wstrb[0]) w[7:0]=req_wdata[7:0];
                        if(req_wstrb[1]) w[15:8]=req_wdata[15:8];
                        expected_mem[key]=w; accepted_writes++;
                    end else begin
                        if(expected_mem.exists(key)==0) $fatal(1,"TB_SETUP: unwritten logical address %h",req_addr);
                        expected_data=expected_mem[key]; accepted_reads++;
                    end
                end
            end
        end
    end

    task automatic wait_initialized;
        integer guard;
        guard=0;
        while(!init_done) begin
            @(negedge clk_mem); #0.001; guard++;
            if(guard>30000) $fatal(1,"TB_INIT_TIMEOUT");
            if(req_ready && !init_done) $fatal(1,"TB_EARLY_READY");
        end
        // DUT signals readiness on a launch edge; allow the corresponding
        // physical sample before checking device-side initialization status.
        @(negedge clk_mem); #0.001;
        if(!device_initialized) $fatal(1,"TB_INIT_SEQUENCE: missing device initialization");
    endtask

    task automatic issue(input bit wr,input logic [31:0] a,
                         input logic [15:0] d,input logic [1:0] lanes);
        bit took;
        integer guard;
        @(negedge clk_mem); #0.001;
        req_valid=1;req_write=wr;req_addr=a;req_wdata=d;req_wstrb=lanes;
        guard=0;
        do begin
            @(posedge clk_mem); took=req_ready; #0.001; guard++;
            if(guard>31000) $fatal(1,"TB_REQUEST_TIMEOUT");
        end while(!took);
        req_valid=0;
    endtask
    task automatic wait_response;
        integer guard;
        guard=0;
        while(!rsp_valid) begin
            @(negedge clk_mem); #0.001; guard++;
            if(guard>100) $fatal(1,"TB_RESPONSE_TIMEOUT");
        end
    endtask
    task automatic consume;
        @(negedge clk_mem); #0.001; rsp_ready=1;
        @(posedge clk_mem); #0.001; rsp_ready=0;
    endtask
    task automatic transact(input bit wr,input logic [31:0] a,
                            input logic [15:0] d,input logic [1:0] lanes);
        issue(wr,a,d,lanes); wait_response(); consume();
    endtask

    task automatic continuous_stream(input integer count);
        integer sent,start_completed;
        int unsigned n,a;
        bit took;
        sent=0;start_completed=completed;
        @(negedge clk_mem); #0.001;
        req_valid=1; rsp_ready=1;
        while(sent<count) begin
            // Addresses are seeded earlier. Mix reads, writes, masks and bank
            // turnarounds while VALID remains asserted across busy cycles.
            n=random_next(); a=physical_address(n%4,4096,((n>>2)%32));
            req_addr=a;req_write=n[7];req_wdata=16'(n>>8);req_wstrb=n[10:9];
            do begin @(posedge clk_mem);took=req_ready;#0.001;end while(!took);
            sent++;
            @(negedge clk_mem);#0.001;
        end
        req_valid=0;
        while(completed-start_completed<count) begin @(negedge clk_mem);#0.001;end
        rsp_ready=0;
    endtask

    initial begin : stimulus
        logic [31:0] a;
        integer ar_before,pre_before,mr_before,emr_before,physical_writes_before;
        bit use_reset;
        realtime release_time;
        bit quick;
        quick=$test$plusargs("quick");
        // VALID before lock must not be accepted, even with arbitrary pins.
        req_valid=1;req_write=1;req_addr=0;req_wdata=16'hbabe;req_wstrb=3;
        repeat(7) @(negedge clk_mem);
        #0.001;reset_n=1;
        repeat(7) @(negedge clk_mem);
        #0.001;pll_locked=1; release_time=$realtime;
        wait_initialized();
        // Take the pre-initialization held request once, then remove VALID.
        do begin @(posedge clk_mem);#0.001;end while(accepted==0);
        req_valid=0; wait_response();consume();
        if(model.first_pre_time-release_time<200000.0)
            $fatal(1,"TB_INIT_TIME: shortened 200 us power-up delay");
        if(model.mr_count!=1 || model.emr_count!=1 || model.init_ar_count!=2)
            $fatal(1,"TB_INIT_COUNTS");
        transact(0,0,0,0);
        // Zero-byte writes, individual lanes, all walking data bits and read/
        // write/read turnarounds, repeated identical requests and extremes.
        for(integer b=0;b<4;b++) begin
            a=physical_address(b,8191,1023);
            transact(1,a,16'ha55a,3);
            transact(1,a,16'h1234,0);transact(0,a,0,0);
            transact(1,a,16'h12ff,1);transact(0,a,0,0);
            transact(1,a,16'h80ee,2);transact(0,a,0,0);
            for(integer bitno=0;bitno<16;bitno++) begin
                transact(1,a,16'(1<<bitno),3);transact(0,a,0,0);
                transact(1,a,~16'(1<<bitno),3);transact(0,a,0,0);
            end
            repeat(4) transact(0,a,0,0);
        end
        transact(1,32'h03fffffe,16'h0101,3);transact(0,32'h03fffffe,0,0);
        // Odd, exact-capacity, high and extreme addresses must not alias.
        transact(0,32'h00000001,0,0);transact(1,32'h03ffffff,16'hdead,3);
        transact(0,32'h04000000,0,0);transact(1,32'h80000000,16'hdead,3);
        transact(0,32'hffffffff,0,0);transact(0,32'h03fffffe,0,0);
        $display("PASS init, byte lanes, data walking bits, repeated requests, invalid-address rejection");

        if(!quick) begin
            // Write ALL 8192 rows in ALL 4 banks at both column boundaries,
            // then read them in a separate pass. This catches row/bank aliases
            // that an immediate write/read test could otherwise hide.
            for(integer b=0;b<4;b++)
                for(integer r=0;r<8192;r++)
                    for(integer c=0;c<2;c++) begin
                        a=physical_address(b,r,(c!=0) ? 1023 : 0);
                        transact(1,a,pattern(a),3);
                    end
            for(integer b=3;b>=0;b--)
                for(integer r=8191;r>=0;r--)
                    for(integer c=0;c<2;c++) begin
                        a=physical_address(b,r,(c!=0) ? 1023 : 0);
                        transact(0,a,0,0);
                    end
            // Every column (and all ten walking column bits) in each bank.
            for(integer b=0;b<4;b++)
                for(integer c=0;c<1024;c++) begin
                    a=physical_address(b,4096,c);
                    transact(1,a,pattern(a),3);
                end
            for(integer b=3;b>=0;b--)
                for(integer c=1023;c>=0;c--) begin
                    a=physical_address(b,4096,c);transact(0,a,0,0);
                end
            if($countones(model.rows_written)!=32768 || $countones(model.rows_read)!=32768 ||
               $countones(model.columns_written)!=1024 || $countones(model.columns_read)!=1024)
                $fatal(1,"TB_GEOMETRY_COVERAGE");
            $display("PASS full geometry: 32768 bank/rows, 1024 columns, independent pin/request maps");
        end
        for(integer b=0;b<4;b++) for(integer c=0;c<32;c++)
            transact(1,physical_address(b,4096,c),16'(b*1024+c),3);
        continuous_stream(4096);
        $display("PASS continuous VALID, 4096 randomized bank/row/column/lane turnarounds");

        // A held response spans a complete 8192-refresh sweep, not just one
        // tREFI. Other VALID requests are held too, but may not be accepted.
        transact(1,32'h00000820,16'hbeef,3);
        issue(0,32'h00000820,0,0);wait_response();
        ar_before=model.runtime_ar;pre_before=accepted;
        req_valid=1;req_write=0;req_addr=32'h00000820;
        if(quick) #20000; else #64100000;
        if(accepted!=pre_before) $fatal(1,"TB_ACCEPT_DURING_HOLD");
        if((!quick && model.runtime_ar-ar_before<8192) || model.runtime_ar-ar_before<2)
            $fatal(1,"TB_HELD_REFRESH: held response blocked refresh");
        req_valid=0;consume();
        $display("PASS held response: runtime ARs=%0d, max AR gap=%0.3f ns",model.runtime_ar-ar_before,model.max_refresh_gap);

        // Reset and PLL loss are independently exercised during initialization,
        // a pending READ, and a held response. They define new data epochs.
        for(integer phase=0;phase<8;phase++) begin
            use_reset=(phase<2 || (phase>=4 && phase<6));
            transact(1,32'h30,16'hcafe,3);
            physical_writes_before=model.total_write;
            if(phase<4) begin
                issue(0,32'h30,0,0);
                if(phase[0]) wait_response();
                else repeat(3) @(negedge clk_mem);
                #1.5;
            end else begin
                issue(1,32'h30,16'h1234,3);
                wait(dq_oe);
                // Odd phases interrupt after the actual external WRITE;
                // even phases interrupt before the SDRAM samples it.
                if(phase[0]) @(negedge clk_mem);
                #1.5;
                if(!dq_oe || model.total_write-physical_writes_before!=integer'(phase[0]))
                    $fatal(1,"TB_WRITE_ABORT_SETUP: did not interrupt intended driven/sample phase");
            end
            req_valid=0; rsp_ready=0;
            mr_before=model.mr_count;emr_before=model.emr_count;
            if(use_reset) reset_n=0; else pll_locked=0;
            #0.001;
            if(init_done || req_ready || rsp_valid || dq_oe)
                $fatal(1,"TB_ASYNC_ABORT: reset/PLL loss did not inhibit immediately");
            repeat(7) @(negedge clk_mem);
            #0.001;reset_n=1;pll_locked=1;
            // Interrupt the 200-us timer and verify it restarts from zero.
            repeat(1000) @(negedge clk_mem);
            #0.001; if(use_reset) reset_n=0;else pll_locked=0;
            repeat(5) @(negedge clk_mem);
            #0.001; reset_n=1;pll_locked=1;release_time=$realtime;
            wait_initialized();
            if(model.first_pre_time-release_time<200000.0 ||
               model.mr_count!=mr_before+1 || model.emr_count!=emr_before+1)
                $fatal(1,"TB_REINITIALIZATION: incomplete new epoch");
            repeat(10) @(negedge clk_mem);
            if(rsp_valid) $fatal(1,"TB_STALE_RESPONSE: aborted request escaped new epoch");
            transact(1,32'h30,16'h5a5a,3);transact(0,32'h30,0,0);
        end
        if(accepted!=completed+aborted || outstanding)
            $fatal(1,"TB_ACCOUNTING: accepted=%0d completed=%0d aborted=%0d",accepted,completed,aborted);
        $display("PASS reset and PLL-loss restart during wait/read/held/driven-write before and after sample; aborted=%0d",aborted);
        $display("SUMMARY CLK_HZ=%0d PHYSICAL_CLK_HZ=%0d R=%0.3f requests=%0d responses=%0d illegal=%0d AR=%0d max_AR_gap_ns=%0.3f",CLK_HZ,PHYSICAL_CLK_HZ,RETURN_DELAY_NS,accepted,completed,illegal_count,model.total_ar,model.max_refresh_gap);
        $display("LIMIT synthetic return delay; no PCB/PVT/fitted-I/O signoff or retention across reset/PLL loss");
        $display("PASS tb_sdram_single_request");
        $finish;
    end
    initial begin #200000000; $fatal(1,"TB_WATCHDOG");end
endmodule
