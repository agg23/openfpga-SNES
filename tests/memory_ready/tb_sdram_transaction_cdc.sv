`timescale 1ns/1ps
module tb_sdram_transaction_cdc;
    reg sys=0, mem=0;
    always #25 sys=~sys;
    always #5 mem=~mem;
    reg reset_n=0, flush=0, init=0;
    wire flush_ack,init_done;
    reg valid=0,write=0,ready_rsp=0;
    reg [31:0] addr=0;
    reg [15:0] data=0;
    reg [1:0] strb=0;
    reg [21:0] meta=0;
    wire ready,rv,error,write_rsp;
    wire [15:0] q;
    wire [21:0] meta_rsp;
    wire ev,er_ready;
    reg er=0,erv=0,ee=0;
    wire [31:0] ea;
    wire ew;
    wire [15:0] ed;
    wire [1:0] es;
    reg [15:0] eq=0;
    sdram_transaction_cdc dut (
        .clk_sys(sys),.clk_sdram(mem),.hard_reset_n(reset_n),.flush(flush),
        .flush_ack(flush_ack),.init_done(init_done),.req_valid(valid),.req_ready(ready),
        .req_addr(addr),.req_write(write),.req_wdata(data),.req_wstrb(strb),.req_meta(meta),
        .rsp_valid(rv),.rsp_ready(ready_rsp),.rsp_rdata(q),.rsp_error(error),
        .rsp_meta(meta_rsp),.rsp_write(write_rsp),.engine_init_done(init),
        .engine_req_valid(ev),.engine_req_ready(er),.engine_req_addr(ea),
        .engine_req_write(ew),.engine_req_wdata(ed),.engine_req_wstrb(es),
        .engine_rsp_valid(erv),.engine_rsp_ready(er_ready),
        .engine_rsp_rdata(eq),.engine_rsp_error(ee)
    );
    integer accepted=0,responded=0;
    always @(posedge mem) if(reset_n && ev && er) accepted<=accepted+1;
    always @(posedge sys) if(reset_n && rv && ready_rsp) responded<=responded+1;
    task offer(input [31:0] a,input [15:0] d,input [21:0] m,input w);
        begin
            @(negedge sys); addr=a;data=d;meta=m;write=w;strb=2'b10;valid=1;
            do @(posedge sys); while(!ready);
            @(negedge sys); valid=0;addr=32'hdeadbeef;data=16'hffff;meta=0;
        end
    endtask
    task answer(input [15:0] d,input e);
        begin
            @(negedge mem); eq=d;ee=e;erv=1;
            do @(posedge mem); while(!er_ready);
            @(negedge mem);erv=0;eq=16'hcccc;
        end
    endtask
    initial begin
        #112; reset_n=1;
        repeat(6) @(posedge sys);
        if(ready) $fatal(1,"ready before initialization");
        @(negedge mem);init=1;
        wait(ready);
        offer(32'h01234560,16'h5ac3,22'h214321,1);
        wait(ev); repeat(11) @(posedge mem);
        if(ea!==32'h01234560 || ed!==16'h5ac3 || !ew || es!==2'b10)
            $fatal(1,"request payload changed under engine stall");
        @(negedge sys);flush=1;
        if(flush_ack) $fatal(1,"flush acknowledged outstanding write");
        @(negedge mem);er=1;
        wait(er_ready); repeat(18) @(posedge mem);
        answer(16'hbeef,0);
        wait(rv); repeat(5) @(posedge sys);
        if(q!==16'hbeef || meta_rsp!==22'h214321 || !write_rsp || error)
            $fatal(1,"held response/metadata mismatch");
        if(ready || flush_ack) $fatal(1,"flush released before response consumed");
        // Quick repeated soft-reset/flush levels cannot destroy or replay a command.
        repeat(3) begin @(negedge sys);flush=0; @(negedge sys);flush=1; end
        if(accepted!=1 || !rv) $fatal(1,"soft flush duplicated/lost accepted command");
        @(negedge sys);ready_rsp=1;
        @(posedge sys); @(negedge sys);ready_rsp=0;
        if(!flush_ack) $fatal(1,"flush did not drain");
        flush=0;
        offer(32'h00001000,16'h1234,22'h31abcd,0);
        wait(er_ready); answer(16'h1234,1);
        wait(rv); @(negedge sys);
        if(!error || q!==16'h1234 || write_rsp || meta_rsp!==22'h31abcd)
            $fatal(1,"error/identity mismatch");
        ready_rsp=1; @(posedge sys); @(negedge sys);ready_rsp=0;
        if(accepted!=2 || responded!=2) $fatal(1,"transaction count mismatch");
        // Hard reset must clear both sides without a phantom toggle response.
        reset_n=0; init=0; #17;reset_n=1;
        repeat(8) @(posedge sys);
        if(rv || ev || ready) $fatal(1,"hard reset leaked state");
        @(negedge mem);init=1;
        wait(ready);
        offer(32'h00000002,16'h0,22'h222222,0);
        wait(er_ready);answer(16'h9876,0);
        wait(rv);@(negedge sys);
        if(q!==16'h9876 || meta_rsp!==22'h222222) $fatal(1,"postreset response wrong");
        ready_rsp=1;@(posedge sys);@(negedge sys);
        $display("PASS CDC: held payload, response backpressure, soft flush, error, hard reset");
        $finish;
    end
    initial begin #200000; $fatal(1,"timeout");end
endmodule
