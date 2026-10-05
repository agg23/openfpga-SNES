`timescale 1ns/1ps
module tb_rom_download_queue;
    reg src=0,sys=0;
    always #6.734 src=~src;
    always #23.493 sys=~sys; // slower PAL destination, asynchronous phase
    reg hard_reset_n=0,active=0,wr=0,little=1,ready=0;
    reg [31:0] addr=0,data=0;
    wire valid,en,busy,complete,fault;
    wire [24:0] wa; wire [15:0] wd;
    reg [16:0] config_in=0, source_snapshot=0, next_config=17'h01431;
    wire [16:0] config_out; wire config_valid;
    rom_download_queue #(.FIFO_WORDS(8)) dut(
        .save_read_request(1'b0),.save_read_ready(),.save_read_quiescent(1'b1),
        .clk_74a(src),.clk_memory(sys),.hard_reset_n(hard_reset_n),
        .bridge_wr(wr),.bridge_endian_little(little),.bridge_addr(addr),
        .bridge_wr_data(data),.download_active(active),.config_in(config_in),
        .config_out(config_out),.config_valid(config_valid),.write_valid(valid),
        .write_ready(ready),.write_en(en),.write_addr(wa),.write_data(wd),
        .save_ready(1'b1),.image_busy(busy),.image_complete(complete),.fault(fault));
    reg [24:0] expected_addr[0:4095]; reg [15:0] expected_data[0:4095];
    reg [16:0] expected_config[0:4095];
    integer expected=0,accepted=0,images=0,config_accepted=0,config_changes=0;
    reg [16:0] config_before;
    reg accepted_now;
    always @(posedge sys) begin
        config_before=config_out; accepted_now=en;
        #1;
        if (!hard_reset_n) begin
            config_accepted=0;
            if(config_valid || config_out!==0) $fatal(1,"CONFIG_RESET retained invalid configuration");
        end else if (!fault) begin
            if(accepted_now && check_data) begin
                if(!config_valid || config_out!==expected_config[config_accepted])
                    $fatal(1,"CONFIG_ORDER n=%0d got=%h expected=%h",config_accepted,config_out,expected_config[config_accepted]);
                config_accepted=config_accepted+1;
            end
            if(config_out!==config_before) begin
                config_changes=config_changes+1;
                if(!accepted_now) $fatal(1,"CONFIG_EARLY changed without accepted nonempty DATA");
            end
        end
    end
    reg old_complete=0,stalled=0;
    reg [40:0] held;
    reg check_data=1;
    always @(posedge sys) begin
        if (!hard_reset_n) begin stalled=0; old_complete=0; end
        else begin
            if (stalled && !fault && (!valid || {wa,wd}!==held))
                $fatal(1,"READY_VALID changed stalled data");
            if (en !== (valid && ready)) $fatal(1,"acceptance pulse mismatch");
            if (en && check_data) begin
                if (accepted>=expected || wa!==expected_addr[accepted] || wd!==expected_data[accepted])
                    $fatal(1,"DATA_ORDER n=%0d got=%h:%h expected=%h:%h",accepted,wa,wd,expected_addr[accepted],expected_data[accepted]);
                accepted=accepted+1;
            end
            if (complete && !old_complete) begin
                images=images+1;
            end
            old_complete=complete;
            stalled=valid&&!ready&&!fault; held={wa,wd};
        end
    end
    task reset_epoch;
        begin
            @(negedge src);hard_reset_n=0;wr=0;active=0;ready=0;
            repeat(10) @(negedge src);
            expected=0;accepted=0;check_data=1;
            hard_reset_n=1;
            repeat(12) @(negedge src);
        end
    endtask
    task start_image;
        begin
            @(negedge src);config_in=next_config;source_snapshot=next_config;
            next_config=next_config+17'h03143;active=1;
            repeat(2) @(negedge src);
            // Subsequent loader staging writes belong to a later image.
            config_in=~source_snapshot;
        end
    endtask
    task stop_image;
        begin @(negedge src);active=0;repeat(2) @(negedge src);end
    endtask
    task packet(input [24:0] a,input [31:0] d,input bit le,input integer spacing);
        reg [31:0] ordered;
        begin
            ordered=le ? d : {d[7:0],d[15:8],d[23:16],d[31:24]};
            expected_config[expected]=source_snapshot;expected_addr[expected]=a;expected_data[expected]=ordered[15:0];expected=expected+1;
            expected_config[expected]=source_snapshot;expected_addr[expected]=a+25'd2;expected_data[expected]=ordered[31:16];expected=expected+1;
            @(negedge src);wr=1;addr={4'h1,3'b0,a};data=d;little=le;
            @(negedge src);wr=0;
            repeat(spacing) @(negedge src);
        end
    endtask
    task expect_done;
        integer limit;
        begin
            limit=0;
            while(!complete && !fault && limit<5000) begin @(negedge sys);limit=limit+1;end
            if(!complete || fault || busy || accepted!=expected)
                $fatal(1,"completion/fault accepted=%0d expected=%0d complete=%b fault=%b",accepted,expected,complete,fault);
        end
    endtask
    task expect_fault;
        begin
            repeat(30) @(negedge sys);
            if(!fault || complete || !busy || valid || config_valid) $fatal(1,"FAIL_CLOSED missing sticky fault");
            active=0;repeat(10) @(negedge src);active=1;repeat(10) @(negedge src);
            if(!fault || complete) $fatal(1,"fault cleared by BEGIN");
        end
    endtask
    integer i,j;
    initial begin
        reset_epoch();
        // Other APF regions (such as region 3) are unrelated.
        @(negedge src);wr=1;addr=32'h30000000;data=32'h11223344;
        @(negedge src);wr=0;repeat(12)@(negedge sys);
        if(fault||valid||busy||complete) $fatal(1,"EARLY_END or unrelated APF region entered ROM queue");
        // Save/empty download before any ROM must not validate an image.
        start_image();stop_image();repeat(20)@(negedge sys);
        if(complete||busy||fault||config_valid||config_out!==0) $fatal(1,"EMPTY_INITIAL mounted uninitialized ROM/config");
        start_image();
        // Stop before FIFO output/last word reaches destination; source level
        // falling is not proof of drain. Hold output through long backend stall.
        packet(25'h0,32'h01234567,1,0);stop_image();
        repeat(30) @(negedge sys);
        if(complete || !busy || !valid || accepted!=0) $fatal(1,"EARLY_END source stop released image");
        ready=1;expect_done();
        // Loader metadata writes before BEGIN cannot change the running image.
        config_in=17'h1ffff;repeat(12)@(negedge sys);
        if(config_out!==source_snapshot || !config_valid) $fatal(1,"CONFIG_EARLY source staging leaked before BEGIN");
        // Empty save cycle after a good ROM retains that already valid image.
        start_image();wait(busy);stop_image();expect_done();
        if(config_out!==expected_config[accepted-1] || !config_valid) $fatal(1,"CONFIG_EMPTY empty cycle replaced ROM metadata");
        // Three complete images with distinct metadata queued while output is
        // blocked. Snapshots must follow their own BEGIN through the FIFO.
        ready=0;
        for(j=0;j<3;j=j+1) begin
            start_image();packet(j*4,32'habcd5678+j,1,0);stop_image();
            if(j==0)repeat(20)@(negedge sys);
        end
        repeat(12)@(negedge sys);
        if(config_out!==expected_config[accepted-1]) $fatal(1,"CONFIG_EARLY changed while old output stalled");
        ready=1;wait(accepted==expected);expect_done();
        // Many FIFO pointer wraps, both endian modes, and byte-address carries.
        for(j=0;j<3;j=j+1) begin
            start_image();
            for(i=0;i<100;i=i+1) begin
                case(i%5)
                    0: packet(25'h3ffe,32'h12345678+i,i[0],25);
                    1: packet(25'h7ffffe,32'habcdef00+i,i[0],25);
                    2: packet(25'hfffffa,32'h76543210+i,i[0],25);
                    3: packet(25'hfffffc,32'hdeadbeef+i,i[0],25);
                    4: packet(i*4,32'h5aa5ffff+i,i[0],25);
                endcase
            end
            stop_image();expect_done();
        end
        // BEGIN+DATA and END+DATA on the same source clock are ordered tokens.
        @(negedge src);config_in=17'h19b72;source_snapshot=config_in;
        active=1;wr=1;addr=32'h10000004;data=32'h87654321;little=1;
        expected_config[expected]=source_snapshot;expected_addr[expected]=4;expected_data[expected]=16'h4321;expected=expected+1;
        expected_config[expected]=source_snapshot;expected_addr[expected]=6;expected_data[expected]=16'h8765;expected=expected+1;
        @(negedge src);wr=0;
        repeat(75) @(negedge src);
        @(negedge src);active=0;wr=1;addr=32'h10000008;data=32'h11223344;
        expected_config[expected]=source_snapshot;expected_addr[expected]=8;expected_data[expected]=16'h3344;expected=expected+1;
        expected_config[expected]=source_snapshot;expected_addr[expected]=10;expected_data[expected]=16'h1122;expected=expected+1;
        @(negedge src);wr=0;expect_done();
        // Valid strobe can be held; it must generate exactly one APF packet.
        start_image();
        expected_config[expected]=source_snapshot;expected_addr[expected]=12;expected_data[expected]=16'h7788;expected=expected+1;
        expected_config[expected]=source_snapshot;expected_addr[expected]=14;expected_data[expected]=16'h5566;expected=expected+1;
        @(negedge src);wr=1;addr=32'h1000000c;data=32'h55667788;
        repeat(12) @(negedge src);wr=0;stop_image();expect_done();
        // A full FIFO must reject the image, not overwrite or claim completion.
        reset_epoch();start_image();
        for(i=0;i<24;i=i+1) packet(i*4,32'h33330000+i,1,0);
        stop_image();expect_fault();
        // Malformed strobe overlaps, out-of-image, and address aliases fail shut.
        reset_epoch();start_image();check_data=0;
        @(negedge src);wr=1;addr=32'h10000000;data=1;
        @(negedge src);addr=32'h10000004;data=2;
        @(negedge src);wr=0;expect_fault();
        reset_epoch();check_data=0;
        @(negedge src);wr=1;addr=32'h10000000;
        @(negedge src);wr=0;expect_fault();
        reset_epoch();start_image();check_data=0;
        @(negedge src);wr=1;addr=32'h12000000;
        @(negedge src);wr=0;expect_fault();
        reset_epoch();start_image();check_data=0;
        @(negedge src);wr=1;addr=32'h10000001;
        @(negedge src);wr=0;expect_fault();
        reset_epoch();start_image();check_data=0;
        @(negedge src);wr=1;addr=32'h10fffffe;
        @(negedge src);wr=0;expect_fault();
        if(valid || accepted!=0) $fatal(1,"PACKET_SPAN accepted a partial boundary packet");
        reset_epoch();start_image();check_data=0;
        @(negedge src);wr=1;addr=32'h11000000;
        @(negedge src);wr=0;expect_fault();
        reset_epoch();start_image();check_data=0;
        @(negedge src);wr=1;addr=32'h11fffffe;
        @(negedge src);wr=0;expect_fault();
        reset_epoch();start_image();check_data=0;
        @(negedge src);wr=1;addr=0;data=1;
        @(negedge src);wr=0;expect_fault();
        // PLL loss invalidates accepted queued tokens. A still-high source does
        // not manufacture a new BEGIN; stop then restart is required.
        reset_epoch();start_image();packet(0,32'hcafeabba,1,0);
        repeat(15) @(negedge sys);
        @(negedge src);hard_reset_n=0;
        repeat(10) @(negedge src);hard_reset_n=1;
        repeat(30) @(negedge sys);
        if(valid || complete || busy || config_valid || config_out!==0) $fatal(1,"PLL_ABORT replayed invalid image");
        stop_image();expected=0;accepted=0;config_accepted=0;ready=1;
        start_image();packet(0,32'h55aa1234,0,0);stop_image();expect_done();
        if(config_changes<8) $fatal(1,"CONFIG_COVERAGE missing distinct image metadata");
        $display("PASS QUEUE: vendor CDC FIFO, endian, lanes/carries, delayed END, ready stability, wraps/full, strobe/BEGIN/address faults, PLL abort/restart; images=%0d config_changes=%0d",images,config_changes);
        $finish;
    end
    initial begin #2000000;$fatal(1,"timeout");end
endmodule
