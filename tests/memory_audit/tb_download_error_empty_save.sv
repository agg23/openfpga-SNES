`timescale 1ns/1ps
// Actual vendor dcfifo -> cart lifecycle -> production CDC -> production engine.
// No ready shortcut. Pin scoreboard independently decodes legacy row/col/bank.
module tb_download_error_empty_save #(
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
    // run.py deliberately uses the historical pre-bounds queue interface.
    // Do not add current Save-fence ports to this pinned negative-control chain.
    rom_download_queue queue(
        .clk_74a(src),.clk_memory(sys),.hard_reset_n(hard_reset_n&&locked),
        .bridge_wr(wr),.bridge_endian_little(little),.bridge_addr(addr),
        .bridge_wr_data(data),.download_active(active),.write_valid(valid),
        .write_ready(ready),.write_en(en),.write_addr(wa),.write_data(wd),
        .image_busy(busy),.image_complete(complete),.fault(qfault));
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

    integer writes=0;
    always @(negedge mem) if(locked&&cke&&!cs&&ras&&!cas&&!we) writes=writes+1;
    initial begin
        #112;hard_reset_n=1;locked=1;
        repeat(12) @(negedge src);
        active=1;
        repeat(3) @(negedge src);
        // Queue explicitly permits even (not necessarily 4-byte aligned)
        // packet addresses. First half is inside 16MiB; upper half crosses the
        // cart port's supported bound and gets an actual engine error reply.
        addr=32'h10fffffe;data=32'hbadd1234;wr=1;
        @(negedge src);wr=0;
        repeat(3) @(negedge src);active=0;
        wait(fault);repeat(8) @(negedge sys);
        if(qfault || !complete || busy || writes!=1 || run)
            $fatal(1,"unexpected setup: qfault=%b complete=%b busy=%b writes=%0d run=%b",qfault,complete,busy,writes,run);
        // The real loader emits a following empty ROM begin/end around Save.
        @(negedge src);active=1;repeat(20) @(negedge src);active=0;
        repeat(40) @(negedge sys);
        if(run) $fatal(1,"AUDIT_REPRO: failed partial ROM became runnable after empty Save BEGIN/END; fault=%b complete=%b writes=%0d",fault,complete,writes);
        $display("PASS failed image remains unmounted across empty Save");$finish;
    end
    initial begin #2000000;$fatal(1,"audit timeout");end
endmodule
