// One-outstanding bundled-data mailbox. Only hard_reset_n resets transport.
// flush closes admission but NEVER erases an accepted command/response.
// Soft-reset clients must accept/discard their old responses before flush_ack.
module sdram_transaction_cdc #(
    parameter integer META_WIDTH = 22
) (
    input  wire                  clk_sys,
    input  wire                  clk_sdram,
    input  wire                  hard_reset_n,
    input  wire                  flush,
    output wire                  flush_ack,
    output wire                  init_done,
    input  wire                  req_valid,
    output wire                  req_ready,
    input  wire [31:0]           req_addr,
    input  wire                  req_write,
    input  wire [15:0]           req_wdata,
    input  wire [1:0]            req_wstrb,
    input  wire [META_WIDTH-1:0] req_meta,
    output reg                   rsp_valid,
    input  wire                  rsp_ready,
    output reg  [15:0]           rsp_rdata,
    output reg                   rsp_error,
    output reg  [META_WIDTH-1:0]  rsp_meta,
    output reg                   rsp_write,
    input  wire                  engine_init_done,
    output wire                  engine_req_valid,
    input  wire                  engine_req_ready,
    output wire [31:0]           engine_req_addr,
    output wire                  engine_req_write,
    output wire [15:0]           engine_req_wdata,
    output wire [1:0]            engine_req_wstrb,
    input  wire                  engine_rsp_valid,
    output wire                  engine_rsp_ready,
    input  wire [15:0]           engine_rsp_rdata,
    input  wire                  engine_rsp_error
);
    // Synchronized reset release in each clock domain. Assertion is immediate.
    (* async_reg = "true", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *) reg [1:0] sys_reset_sync;
    (* async_reg = "true", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *) reg [1:0] mem_reset_sync;
    always @(posedge clk_sys or negedge hard_reset_n)
        if (!hard_reset_n) sys_reset_sync <= 0;
        else sys_reset_sync <= {sys_reset_sync[0],1'b1};
    always @(posedge clk_sdram or negedge hard_reset_n)
        if (!hard_reset_n) mem_reset_sync <= 0;
        else mem_reset_sync <= {mem_reset_sync[0],1'b1};

    reg request_toggle;
    reg sys_busy;
    reg [31:0] request_addr_hold;
    reg request_write_hold;
    reg [15:0] request_data_hold;
    reg [1:0] request_strb_hold;
    reg [META_WIDTH-1:0] request_meta_hold;

    (* async_reg = "true", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *) reg [1:0] init_sync;
    (* async_reg = "true", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *) reg [1:0] response_sync;
    reg response_seen;
    reg response_toggle;
    reg [15:0] response_data_hold;
    reg response_error_hold;

    assign init_done = init_sync[1] && sys_reset_sync[1];
    assign req_ready = init_done && !flush && !sys_busy;
    assign flush_ack = sys_reset_sync[1] && !sys_busy && !rsp_valid;

    always @(posedge clk_sys or negedge hard_reset_n) begin
        if (!hard_reset_n) begin
            init_sync <= 0;
            response_sync <= 0;
        end else if (!sys_reset_sync[1]) begin
            init_sync <= 0;
            response_sync <= 0;
        end else begin
            init_sync <= {init_sync[0],engine_init_done};
            response_sync <= {response_sync[0],response_toggle};
        end
    end

    always @(posedge clk_sys or negedge hard_reset_n) begin
        if (!hard_reset_n) begin
            request_toggle <= 0;
            sys_busy <= 0;
            response_seen <= 0;
            request_addr_hold <= 0;
            request_write_hold <= 0;
            request_data_hold <= 0;
            request_strb_hold <= 0;
            request_meta_hold <= 0;
            rsp_valid <= 0;
            rsp_rdata <= 0;
            rsp_error <= 0;
            rsp_meta <= 0;
            rsp_write <= 0;
        end else if (sys_reset_sync[1]) begin
            if (req_valid && req_ready) begin
                request_addr_hold <= req_addr;
                request_write_hold <= req_write;
                request_data_hold <= req_wdata;
                request_strb_hold <= req_wstrb;
                request_meta_hold <= req_meta;
                request_toggle <= ~request_toggle;
                sys_busy <= 1;
            end
            if (sys_busy && response_sync[1] != response_seen && !rsp_valid) begin
                // Payload has been stable for >= two complete system clocks.
                rsp_rdata <= response_data_hold;
                rsp_error <= response_error_hold;
                rsp_meta <= request_meta_hold;
                rsp_write <= request_write_hold;
                rsp_valid <= 1;
                response_seen <= response_sync[1];
            end
            if (rsp_valid && rsp_ready) begin
                rsp_valid <= 0;
                sys_busy <= 0;
            end
        end
    end

    (* async_reg = "true", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *) reg [1:0] request_sync;
    reg request_seen;
    reg mem_offer;
    reg mem_wait;
    reg [31:0] mem_addr;
    reg mem_write;
    reg [15:0] mem_data;
    reg [1:0] mem_strb;
    assign engine_req_valid = mem_offer && mem_reset_sync[1];
    assign engine_req_addr = mem_addr;
    assign engine_req_write = mem_write;
    assign engine_req_wdata = mem_data;
    assign engine_req_wstrb = mem_strb;
    assign engine_rsp_ready = mem_wait && mem_reset_sync[1];

    always @(posedge clk_sdram or negedge hard_reset_n) begin
        if (!hard_reset_n) request_sync <= 0;
        else if (!mem_reset_sync[1]) request_sync <= 0;
        else request_sync <= {request_sync[0],request_toggle};
    end
    always @(posedge clk_sdram or negedge hard_reset_n) begin
        if (!hard_reset_n) begin
            request_seen <= 0;
            mem_offer <= 0;
            mem_wait <= 0;
            mem_addr <= 0;
            mem_write <= 0;
            mem_data <= 0;
            mem_strb <= 0;
            response_toggle <= 0;
            response_data_hold <= 0;
            response_error_hold <= 0;
        end else if (mem_reset_sync[1]) begin
            if (!mem_offer && !mem_wait && request_sync[1] != request_seen) begin
                // Sys payload is held until sys response consumption. The two-
                // flop toggle synchronizer gives bundled data its settling time.
                mem_addr <= request_addr_hold;
                mem_write <= request_write_hold;
                mem_data <= request_data_hold;
                mem_strb <= request_strb_hold;
                request_seen <= request_sync[1];
                mem_offer <= 1;
            end
            if (engine_req_valid && engine_req_ready) begin
                mem_offer <= 0;
                mem_wait <= 1;
            end
            if (engine_rsp_valid && engine_rsp_ready) begin
                response_data_hold <= engine_rsp_rdata;
                response_error_hold <= engine_rsp_error;
                response_toggle <= request_seen;
                mem_wait <= 0;
            end
        end
    end
endmodule
