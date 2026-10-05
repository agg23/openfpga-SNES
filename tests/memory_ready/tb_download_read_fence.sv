`timescale 1ns/1ps
module tb_download_read_fence;
    reg src=0,sys=0;
    always #6.734 src=~src;
    always #23.495 sys=~sys;
    reg reset_n=0,active=0,wr=0,save_ready=0,request=0,quiet=0;
    reg [31:0] addr=0,data=0;
    wire source_ready;
    wire ack,valid,en,busy,ib,qbusy,complete,fault;
    wire [16:0] sa;wire [15:0] sd;
    rom_download_queue #(.FIFO_WORDS(16)) dut(.clk_74a(src),.clk_memory(sys),.hard_reset_n(reset_n),
        .bridge_wr(wr),.bridge_endian_little(1'b1),.bridge_addr(addr),.bridge_wr_data(data),
        .download_active(active),.config_in(17'h03141),.config_out(),.config_valid(),
        .write_valid(),.write_ready(1'b1),.write_en(),.write_addr(),.write_data(),
        .save_valid(valid),.save_ready(save_ready),.save_en(en),.save_addr(sa),.save_data(sd),
        .save_busy(busy),.image_begin(ib),.image_busy(qbusy),.image_complete(complete),.fault(fault),
        .source_ready(source_ready),.save_read_request(request),.save_read_ready(ack),.save_read_quiescent(quiet));
    integer accepted=0,acks=0,require_words=0;
    reg old_ack=0;
    always @(posedge sys)if(reset_n&&en)begin
        if(ib) $fatal(1,"FENCE_BEGIN");
        accepted=accepted+1;
    end
    always @(posedge src)begin
        if(!reset_n)old_ack=0;
        else begin
            if(ack&&!old_ack)begin
                acks=acks+1;
                if(accepted<require_words) $fatal(1,"FENCE_EARLY prior Save not accepted");
            end
            old_ack=ack;
        end
    end
    task reset_epoch;
        begin @(negedge src);reset_n=0;active=0;wr=0;request=0;save_ready=0;quiet=0;
            repeat(12)@(negedge src);if(source_ready) $fatal(1,"FENCE_ARM reset capture allowed");accepted=0;require_words=0;reset_n=1;
            #1;if(source_ready) $fatal(1,"FENCE_ARM capture before reset synchronizers");
            wait(source_ready);
            if(ack||fault) $fatal(1,"FENCE_RESET");
        end
    endtask
    task packet;
        begin @(negedge src);wr=1;addr=32'h20000000;data=32'h12345678;
            @(negedge src);wr=0;end
    endtask
    task fence;
        begin @(negedge src);request=1;#1;
            if(ack) $fatal(1,"FENCE_STALE reused previous request ack");
            @(negedge src);request=0;end
    endtask
    task await_ack;
        integer n;
        begin n=0;while(!ack&&!fault&&n<300)begin @(negedge src);n=n+1;end
            if(!ack||fault) $fatal(1,"FENCE_TIMEOUT");
            repeat(4)@(negedge src);
        end
    endtask
    initial begin
        reset_epoch();
        // The sink still sees an empty FIFO when these adjacent source events
        // occur. A synchronized empty level is not an acknowledgment of either.
        quiet=1;packet();require_words=2;fence();
        repeat(30)@(negedge src);
        if(ack||!busy||accepted) $fatal(1,"FENCE_EARLY acknowledged held prior data");
        quiet=0;save_ready=1;wait(accepted==2);
        repeat(20)@(negedge sys);
        if(ack||!busy) $fatal(1,"FENCE_PHYSICAL ignored physical clear/drain barrier");
        quiet=1;await_ack();
        // A second request cannot borrow the first request's still-high ready.
        quiet=0;fence();repeat(20)@(negedge sys);
        if(ack||!busy) $fatal(1,"FENCE_STALE");
        quiet=1;await_ack();
        // BEGIN+Save+fence share one token; END is queued behind it.
        quiet=0;require_words=4;
        @(negedge src);active=1;wr=1;addr=32'h20000000;data=32'h89abcdef;request=1;
        #1;if(ack) $fatal(1,"FENCE_STALE coincident request");
        @(negedge src);wr=0;request=0;active=0;
        wait(accepted==4);repeat(10)@(negedge sys);
        if(ack||!busy) $fatal(1,"FENCE_PHYSICAL combined token escaped barrier");
        quiet=1;await_ack();repeat(20)@(negedge sys);
        if(busy||qbusy||complete) $fatal(1,"FENCE_IMAGE Save-only frame created ROM validity");
        // A still-pending request must not replay an ack across PLL loss.
        quiet=0;fence();repeat(20)@(negedge sys);reset_epoch();quiet=1;
        repeat(20)@(negedge sys);if(ack) $fatal(1,"FENCE_RESET stale ack replay");
        fence();await_ack();
        // Interrupted-high download cannot arm the source after PLL release.
        @(negedge src);reset_n=0;active=1;request=0;
        repeat(12)@(negedge src);reset_n=1;
        repeat(12)@(negedge src);
        if(source_ready||ack) $fatal(1,"FENCE_ARM high interrupted download armed");
        @(negedge src);active=0;wait(source_ready);fence();await_ack();
        // Multiple outstanding read requests have no unbounded request queue;
        // an illegal second request explicitly fails this epoch closed.
        quiet=0;fence();repeat(5)@(negedge src);fence();repeat(20)@(negedge sys);
        if(!fault||ack||!busy) $fatal(1,"FENCE_DUPLICATE not fail closed");
        // A fence cannot be accepted as successful after transport overflow.
        reset_epoch();for(integer i=0;i<20;i=i+1)packet();fence();
        repeat(30)@(negedge sys);quiet=1;save_ready=1;repeat(20)@(negedge sys);
        if(!fault||ack||!busy) $fatal(1,"FENCE_OVERFLOW not fail closed");
        if(acks<4) $fatal(1,"FENCE_COVERAGE");
        $display("PASS READ_FENCE: %0d matched source acks; ordered write prefix, CDC empty gap, physical barrier, stale-ready rejection, coincident flags, reset, duplicate/overflow fail closed",acks);
        $finish;
    end
    initial begin #2000000;$fatal(1,"TIMEOUT");end
endmodule
