// Cartridge lifecycle + download/core arbitration, all public handshakes clk_sys.
// A soft reset closes client admission but drains old physical commands. A new
// mount may write only after old clients acknowledge flush and transport drains.
module sdram_cart_port #(
    parameter integer CLK_HZ=107386350,
    parameter ENABLE_READ_CACHE=1'b1
)(
    input wire clk_sys, clk_sdram, hard_reset_n, pll_locked,
    input wire soft_reset, download_active, download_complete, download_fault,
    input wire download_valid,
    output wire download_ready,
    input wire [24:0] download_addr,
    input wire [15:0] download_data,
    output wire client_flush,
    input wire client_flush_ack,
    input wire client_fault,
    output reg [7:0] epoch,
    output wire run_ready,
    output wire host_quiescent,
    output reg fault,
    input wire req_valid,
    output wire req_ready,
    input wire [23:0] req_addr,
    input wire req_channel,
    input wire req_write,
    input wire req_drain,
    input wire [15:0] req_wdata,
    input wire [1:0] req_wstrb,
    input wire [4:0] req_owner,
    input wire [7:0] req_tag, req_epoch,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire [15:0] rsp_data,
    output wire rsp_error,
    output wire rsp_write,
    output wire [4:0] rsp_owner,
    output wire [7:0] rsp_tag, rsp_epoch,
    output wire dram_cke,dram_cs_n,dram_ras_n,dram_cas_n,dram_we_n,
    output wire [12:0] dram_addr,
    output wire [1:0] dram_ba,dram_dqm,
    input wire [15:0] dq_in,
    output wire [15:0] dq_out,
    output wire dq_oe
);
    wire transport_reset_n=hard_reset_n && pll_locked;
    wire init_done,transport_idle;
    reg loading,mounted,flush_hold,download_old;
    reg retained_mount,load_has_writes,recovery_armed;
    reg response_is_download;
    wire bridge_req_ready,bridge_rsp_valid,bridge_rsp_ready,bridge_rsp_error;
    wire [15:0] bridge_rsp_data;
    wire [20:0] bridge_rsp_meta;
    wire bridge_rsp_write;
    // Preserve the legacy same-word read cache, now with physical and epoch tags.
    // Every accepted write invalidates it, including download and BSX writes.
    reg cache_valid;
    reg [31:0] cache_addr,accepted_addr;
    reg [7:0] cache_epoch,accepted_epoch;
    reg [15:0] cache_data;
    reg cache_rsp_valid;
    reg [15:0] cache_rsp_data;
    reg [20:0] cache_rsp_meta;
    wire cache_hit=ENABLE_READ_CACHE && cache_valid && !req_write &&
                   cache_addr==physical_address(req_channel,req_addr) && cache_epoch==req_epoch;
    wire all_transport_idle=transport_idle && !cache_rsp_valid;

    assign client_flush=soft_reset || download_active || download_fault || flush_hold || loading ||
                        !mounted || !init_done || fault;
    assign run_ready=!client_flush && !client_fault;
    // client_flush_ack includes any held accepted response. Transport idle adds
    // the last command's CDC acknowledgment; no old write can overlap new mount.
    assign download_ready=loading && client_flush_ack && bridge_req_ready && !cache_rsp_valid && (!fault || recovery_armed) && !download_fault && !(req_valid && drain_write);
    // A CPU-retired posted write is already committed even before the CDC
    // accepts it. Drain only explicitly marked writes through a soft flush.
    wire drain_write=req_drain && req_write;
    // Independent host Save writes do not create a new ROM mount. They may
    // touch BSRAM only after client reset/flush has closed all old ownership,
    // including a CPU-retired posted write that was not accepted by the CDC.
    // This credit is independent of download_valid, loading and ROM validity.
    // A drained failed ROM may accept/discard ordered Save traffic so it does
    // not block a later fresh-ROM recovery. It NEVER authorizes run or clears
    // fault/mounted state; only the existing physical ROM-write policy does.
    assign host_quiescent=client_flush && client_flush_ack && all_transport_idle &&
                          init_done && !download_fault &&
                          !(req_valid && drain_write);

    assign req_ready=(run_ready || drain_write) && bridge_req_ready && !cache_rsp_valid;
    wire choose_download=loading && !(req_valid && drain_write);
    wire bridge_req_valid=choose_download ? (download_valid && client_flush_ack && !cache_rsp_valid && (!fault || recovery_armed) && !download_fault) :
                                            (req_valid && (run_ready || drain_write) && !cache_hit && !cache_rsp_valid);
    wire bridge_req_fire=bridge_req_valid && bridge_req_ready;
    assign rsp_valid=cache_rsp_valid || (bridge_rsp_valid && !response_is_download);
    assign bridge_rsp_ready=response_is_download ? 1'b1 : rsp_ready;
    assign rsp_data=cache_rsp_valid ? cache_rsp_data : bridge_rsp_data;
    assign rsp_error=!cache_rsp_valid && bridge_rsp_error;
    assign rsp_write=!cache_rsp_valid && bridge_rsp_write;
    assign {rsp_owner,rsp_tag,rsp_epoch}=cache_rsp_valid ? cache_rsp_meta : bridge_rsp_meta;

    function automatic [31:0] physical_address(input channel,input [23:0] a);
        physical_address={6'b0,channel,a[23],a[13:1],1'b0,a[22:14],1'b0};
    endfunction
    wire [31:0] bridge_req_addr=choose_download ?
        ((download_addr[24] || download_addr[0]) ? 32'hffffffff :
          physical_address(1'b0,download_addr[23:0])) : physical_address(req_channel,req_addr);

    always @(posedge clk_sys or negedge transport_reset_n) begin
        if(!transport_reset_n) begin
            loading<=0;mounted<=0;flush_hold<=1;epoch<=0;
            retained_mount<=0;load_has_writes<=0;recovery_armed<=0;
            download_old<=0;response_is_download<=0;fault<=0;
            cache_valid<=0;cache_addr<=0;cache_epoch<=0;cache_data<=0;
            accepted_addr<=0;accepted_epoch<=0;
            cache_rsp_valid<=0;cache_rsp_data<=0;cache_rsp_meta<=0;
        end else begin
            download_old<=download_active;
            if(download_active && !download_old) begin
                // Empty Save segments may preserve only a previously proven
                // image, never create validity or clear a failed partial load.
                // Queued BEGINs can arrive while the prior segment still drains;
                // retain the batch's physical-success evidence in that case.
                if(!loading) begin
                    retained_mount<=mounted && !fault;
                    load_has_writes<=0;
                end
                loading<=1;
                mounted<=0;
                flush_hold<=1;
                cache_valid<=0;
                recovery_armed<=1;
            end
            if(soft_reset) flush_hold<=1;
            // Producer idle is required: download_active may fall before FIFO
            // delivers its last word. Acceptance alone is not write completion.
            if(loading && !download_active && download_complete && !download_valid &&
               client_flush_ack && all_transport_idle && !fault) begin
                loading<=0;
                mounted<=load_has_writes || retained_mount;
                recovery_armed<=0;
            end
            if(flush_hold && !soft_reset && !loading && !download_active &&
               client_flush_ack && all_transport_idle && init_done && !fault) begin
                flush_hold<=0;
                epoch<=epoch+1'b1;
            end
            if(bridge_req_fire) begin
                response_is_download<=choose_download;
                accepted_addr<=bridge_req_addr;
                accepted_epoch<=req_epoch;
                if(choose_download || req_write) cache_valid<=0;
                if(choose_download && recovery_armed) begin
                    // Only real new data can request recovery. BEGIN/END with
                    // no data cannot rehabilitate a backend-failed image.
                    fault<=0;
                    recovery_armed<=0;
                end
            end
            if(req_valid && req_ready && cache_hit) begin
                cache_rsp_valid<=1;
                cache_rsp_data<=cache_data;
                cache_rsp_meta<={req_owner,req_tag,req_epoch};
            end
            if(cache_rsp_valid && rsp_ready) cache_rsp_valid<=0;
            if(bridge_rsp_valid && bridge_rsp_ready && !bridge_rsp_error &&
               !bridge_rsp_write && !response_is_download && !download_active) begin
                cache_valid<=1;
                cache_addr<=accepted_addr;
                cache_epoch<=accepted_epoch;
                cache_data<=bridge_rsp_data;
            end
            if(bridge_rsp_valid && bridge_rsp_ready && response_is_download &&
               !bridge_rsp_error) load_has_writes<=1;
            // A mapper's local fault may clear when the resulting chip reset
            // asserts its FLUSH. Keep that event sticky here; otherwise a
            // one-clock fault pulse could reopen the same epoch before ACK.
            // Explicit nonempty remount or hard reset requests recovery;
            // every old owner/physical response must still drain before writes.
            if((bridge_rsp_valid && bridge_rsp_ready && bridge_rsp_error) ||
               download_fault || client_fault) begin
                fault<=1;
                mounted<=0;
                retained_mount<=0;
                load_has_writes<=0;
            end
        end
    end

    wire ev,er,ew,erv,err,ere,engine_init;
    wire [31:0] ea;
    wire [15:0] ed,eq;
    wire [1:0] es;
    sdram_transaction_cdc #(.META_WIDTH(21)) crossing(
        .clk_sys(clk_sys),.clk_sdram(clk_sdram),.hard_reset_n(transport_reset_n),
        // Lifecycle logic controls admission; never flush away a downloaded word.
        .flush(1'b0),.flush_ack(transport_idle),.init_done(init_done),
        .req_valid(bridge_req_valid),.req_ready(bridge_req_ready),.req_addr(bridge_req_addr),
        .req_write(choose_download ? 1'b1 : req_write),
        .req_wdata(choose_download ? download_data : req_wdata),
        .req_wstrb(choose_download ? 2'b11 : req_wstrb),
        .req_meta(choose_download ? {5'd16,8'b0,epoch} : {req_owner,req_tag,req_epoch}),
        .rsp_valid(bridge_rsp_valid),.rsp_ready(bridge_rsp_ready),
        .rsp_rdata(bridge_rsp_data),.rsp_error(bridge_rsp_error),.rsp_meta(bridge_rsp_meta),
        .rsp_write(bridge_rsp_write),.engine_init_done(engine_init),
        .engine_req_valid(ev),.engine_req_ready(er),.engine_req_addr(ea),
        .engine_req_write(ew),.engine_req_wdata(ed),.engine_req_wstrb(es),
        .engine_rsp_valid(erv),.engine_rsp_ready(err),.engine_rsp_rdata(eq),.engine_rsp_error(ere));
    sdram_single_request #(.CLK_HZ(CLK_HZ)) engine(
        .clk_mem(clk_sdram),.reset_n(hard_reset_n),.pll_locked(pll_locked),
        .req_valid(ev),.req_ready(er),.req_write(ew),.req_addr(ea),.req_wdata(ed),.req_wstrb(es),
        .rsp_valid(erv),.rsp_ready(err),.rsp_rdata(eq),.rsp_error(ere),.init_done(engine_init),
        .dram_cke(dram_cke),.dram_cs_n(dram_cs_n),.dram_ras_n(dram_ras_n),
        .dram_cas_n(dram_cas_n),.dram_we_n(dram_we_n),.dram_addr(dram_addr),
        .dram_ba(dram_ba),.dram_dqm(dram_dqm),.dq_in(dq_in),.dq_out(dq_out),.dq_oe(dq_oe));
endmodule
