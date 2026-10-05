`timescale 1ns/1ps
// Actual FIFO/cart/CDC/SDRAM engine. The local Save acceptance sink is a
// counter here; full Intel RAM/frontier integration is validated separately.
module tb_unified_download_fault_recovery #(parameter integer PAL=0);
    localparam realtime H=PAL?23.495:23.281;
    reg src=0,sys=0,mem=0;
    always #6.734 src=~src;
    always #(H) sys=~sys;
    always #(H/5.0) mem=~mem;
    reg reset_n=0,active=0,wr=0,client_fault=0;
    reg [31:0] addr=0,data=0;
    reg [16:0] cfg=17'h03421;
    wire rv,re,rr,sv,se,sr,ib,sb,busy,complete,qfault,cv,run,fault,quiet,flush;
    wire [24:0] ra;wire [16:0] sa,co;wire [15:0] rd,sd;
    wire cke,cs,ras,cas,we,oe;wire [12:0] ma;wire [1:0] ba,dqm;wire [15:0] md;
    rom_download_queue queue(.save_read_request(1'b0),.save_read_ready(),.save_read_quiescent(1'b1),
        .clk_74a(src),.clk_memory(sys),.hard_reset_n(reset_n),
        .bridge_wr(wr),.bridge_endian_little(1'b1),.bridge_addr(addr),.bridge_wr_data(data),
        .download_active(active),.config_in(cfg),.config_out(co),.config_valid(cv),
        .write_valid(rv),.write_ready(rr),.write_en(re),.write_addr(ra),.write_data(rd),
        .save_valid(sv),.save_ready(sr),.save_en(se),.save_addr(sa),.save_data(sd),
        .image_begin(ib),.save_busy(sb),.image_busy(busy),.image_complete(complete),.fault(qfault));
    assign sr=quiet&&!ib;
    sdram_cart_port cart(.clk_sys(sys),.clk_sdram(mem),.hard_reset_n(reset_n),.pll_locked(reset_n),
        .soft_reset(sb),.download_active(busy),.download_complete(complete),.download_fault(qfault),
        .download_valid(rv),.download_ready(rr),.download_addr(ra),.download_data(rd),
        .client_flush(flush),.client_flush_ack(1'b1),.client_fault(client_fault),.epoch(),
        .host_quiescent(quiet),.run_ready(run),.fault(fault),
        .req_valid(1'b0),.req_ready(),.req_addr(24'b0),.req_channel(1'b0),.req_write(1'b0),
        .req_drain(1'b0),.req_wdata(16'b0),.req_wstrb(2'b0),.req_owner(5'b0),.req_tag(8'b0),.req_epoch(8'b0),
        .rsp_valid(),.rsp_ready(1'b1),.rsp_data(),.rsp_error(),.rsp_write(),.rsp_owner(),.rsp_tag(),.rsp_epoch(),
        .dram_cke(cke),.dram_cs_n(cs),.dram_ras_n(ras),.dram_cas_n(cas),.dram_we_n(we),
        .dram_addr(ma),.dram_ba(ba),.dram_dqm(dqm),.dq_in(16'b0),.dq_out(md),.dq_oe(oe));
    integer saves=0,roms=0,writes=0,phase=0;
    always @(negedge mem)if(reset_n&&cke&&!cs&&ras&&!cas&&!we)writes=writes+1;
    always @(posedge sys)if(reset_n)begin
        if(re)roms=roms+1;
        if(se)begin
            if(!fault||run||co!==17'h03421||!cv||!quiet)
                $fatal(1,"SAVE_AUTHORITY unsafe credit or Save changed failed image authority");
            if(sa!==(saves%2)*2 || sd!==((saves%2)?16'h1234:16'h5678))
                $fatal(1,"SAVE_DATA");
            saves=saves+1;
        end
        if(phase==1&&!fault) $fatal(1,"SAVE_CLEARED_FAULT");
        if(phase==2&&roms==2&&!fault) $fatal(1,"BEGIN_CLEARED_FAULT before new ROM accepted");
        if(run&&(sb||busy||fault||!complete||writes!=roms)) $fatal(1,"EARLY_RUN");
        if(qfault) $fatal(1,"QUEUE_FAULT");
    end
    task start(input [16:0] value);
        begin @(negedge src);cfg=value;active=1;repeat(2)@(negedge src);end
    endtask
    task stop;
        begin @(negedge src);active=0;repeat(2)@(negedge src);end
    endtask
    task packet(input bit save);
        begin @(negedge src);addr=save?32'h20000000:32'h10000000;data=32'h12345678;wr=1;
            @(negedge src);wr=0;repeat(2)@(negedge src);end
    endtask
    initial begin
        #113;reset_n=1;repeat(12)@(negedge src);
        start(17'h03421);packet(0);stop();wait(run);
        if(writes!=2||!cv) $fatal(1,"INITIAL_ROM");
        // The real cart's public client-fault input models a detected mapper
        // protocol fault. All physical memory modules remain production RTL.
        @(negedge sys);client_fault=1;@(negedge sys);client_fault=0;
        if(!fault||run) $fatal(1,"FAULT_SETUP");phase=1;
        packet(1);wait(saves==2);repeat(5)@(negedge sys);
        if(!fault||run||co!==17'h03421) $fatal(1,"INDEPENDENT_SAVE_AUTHORITY");
        // A nonempty failed-image Save must drain without rehabilitating that
        // image, otherwise it permanently blocks the good ROM behind it.
        start(17'h19999);packet(1);stop();
        wait(saves==4);repeat(5)@(negedge sys);
        if(!fault||run||co!==17'h03421) $fatal(1,"SEGMENT_SAVE_AUTHORITY");
        phase=2;start(17'h18765);packet(0);stop();wait(run);phase=3;
        if(fault||writes!=4||roms!=4||saves!=4||co!==17'h18765||!cv)
            $fatal(1,"RECOVERY");
        $display("PASS SAVE_FAULT_RECOVERY PAL=%0d ROM_words=%0d physical_writes=%0d Save_words=%0d; failed-image Save drains without config/mount/fault recovery; later real ROM recovers",PAL,roms,writes,saves);
        $finish;
    end
    initial begin #2000000;$fatal(1,"FAULT_SAVE_HEAD_BLOCK timeout");end
endmodule
