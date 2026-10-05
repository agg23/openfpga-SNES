// SCPU's single active A-bus ROM transaction, used by passive mappers.
// ROM lookahead and intent do not depend on a strobed bus phase.
module snes_rom_client #(parameter FORWARD_RESPONSE=1'b1) (
    input wire clk,
    input wire hard_reset_n,
    input wire flush,
    input wire [7:0] epoch,
    input wire read_intent,
    input wire [1:0] owner,
    input wire selected,
    input wire [23:0] address,
    input wire retire,
    output wire bus_wait,
    output wire [15:0] result_data,
    output wire flush_ack,
    output reg fault,
    output wire req_valid,
    input wire req_ready,
    output reg [23:0] req_addr,
    output reg [1:0] req_owner,
    output reg [7:0] req_tag,
    output reg [7:0] req_epoch,
    input wire rsp_valid,
    output wire rsp_ready,
    input wire [15:0] rsp_data,
    input wire [1:0] rsp_owner,
    input wire [7:0] rsp_tag,
    input wire [7:0] rsp_epoch,
    input wire rsp_error
);
    localparam [1:0] IDLE=0, OFFER=1, WAIT_RESPONSE=2, RESULT=3;
    reg [1:0] state;
    reg [7:0] next_tag;
    reg canceled;
    reg [15:0] result_hold;
    wire match_rsp = rsp_owner==req_owner && rsp_tag==req_tag && rsp_epoch==req_epoch;
    assign req_valid = state==OFFER && !flush && !fault;
    assign rsp_ready = state==WAIT_RESPONSE;
    assign flush_ack = state==IDLE;
    // Matched response forwarding avoids a needless extra sys-clock bubble
    // when data is already stable before the original SCPU start phase.
    wire forward_rsp = FORWARD_RESPONSE && state==WAIT_RESPONSE && rsp_valid && match_rsp &&
                       !rsp_error && !flush && !canceled && !fault;
    wire result_ready = state==RESULT || forward_rsp;
    assign result_data = forward_rsp ? (req_addr[0] ? {2{rsp_data[15:8]}} : rsp_data) : result_hold;
    // Once allocated the slot, not a later live decode, determines readiness.
    assign bus_wait = fault || (read_intent && selected && !result_ready) ||
                      state==OFFER || (state==WAIT_RESPONSE && !forward_rsp);
    always @(posedge clk or negedge hard_reset_n) begin
        if(!hard_reset_n) begin
            state<=IDLE; next_tag<=0; req_addr<=0; req_owner<=0;
            req_tag<=0;req_epoch<=0;canceled<=0;result_hold<=0;fault<=0;
        end else begin
            if(flush) begin
                fault<=0;
                if(state==WAIT_RESPONSE) canceled<=1;
                else begin state<=IDLE;canceled<=0;end
            end else if(state==IDLE && read_intent && selected && !fault) begin
                req_addr<=address;
                req_owner<=owner;
                req_tag<=next_tag;
                req_epoch<=epoch;
                next_tag<=next_tag+1'b1;
                canceled<=0;
                state<=OFFER;
            end
            if(req_valid && req_ready) state<=WAIT_RESPONSE;
            if(rsp_valid && rsp_ready) begin
                if(!match_rsp) begin
                    // Keep the accepted identity alive until its own response drains.
                    // A mismatched response cannot release this transaction.
                    fault<=1;
                end else if(flush || canceled) begin
                    state<=IDLE;
                    canceled<=0;
                end else if(rsp_error) begin
                    state<=IDLE;
                    fault<=1;
                end else begin
                    result_hold <= req_addr[0] ? {2{rsp_data[15:8]}} : rsp_data;
                    state<=retire ? IDLE : RESULT;
                end
            end
            if(state==RESULT && retire) state<=IDLE;
        end
    end
endmodule
