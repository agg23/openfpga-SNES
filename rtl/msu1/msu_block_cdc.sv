// SPDX-License-Identifier: GPL-3.0-or-later
// One outstanding read. Payloads are held stable until the return handshake;
// only toggle flags cross synchronizers. RAM is written only by host and read
// only after completion, then held immutable until the next request.
module msu_block_cdc #(
 parameter integer MAX_BYTES=4096,
 parameter integer AW=$clog2(MAX_BYTES/4)
)(
 input wire sys_clk, host_clk, reset,
 input wire req_valid, output wire req_ready,
 input wire [31:0] req_offset, input wire [15:0] req_length,
 output reg resp_valid, input wire resp_ready,
 output reg [31:0] resp_data,
 output reg resp_done, output reg resp_error,
 output wire host_req, input wire host_ack,
 output wire [31:0] host_offset, output wire [15:0] host_length,
 input wire host_done, input wire [2:0] host_error,
 input wire [15:0] host_actual,
 input wire host_we, input wire [15:0] host_waddr,
 input wire [31:0] host_wdata, input wire [3:0] host_wmask
);
 reg [2:0] sys_reset_pipe=7, host_reset_pipe=7;
 always @(posedge sys_clk or posedge reset)
   if(reset)sys_reset_pipe<=7;else sys_reset_pipe<={sys_reset_pipe[1:0],1'b0};
 always @(posedge host_clk or posedge reset)
   if(reset)host_reset_pipe<=7;else host_reset_pipe<={host_reset_pipe[1:0],1'b0};
 wire sys_reset=sys_reset_pipe[2],host_reset=host_reset_pipe[2];
 (* ramstyle = "M10K, no_rw_check" *) reg [31:0] ram [0:MAX_BYTES/4-1];
 reg [31:0] offset_hold;
 reg [15:0] length_hold;
 reg request_toggle, complete_toggle;
 (* async_reg="true", altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] request_sync, complete_sync;
 reg host_seen, host_active, host_accepted;
 reg result_error;
 reg [15:0] result_length;
 reg [1:0] state;
 reg [AW:0] words, index;
 (* ramstyle = "M10K, no_rw_check" *) reg [31:0] ram_q;
 assign req_ready = state==0 && !sys_reset;
 assign host_req = host_active && !host_accepted;
 assign host_offset=offset_hold;
 assign host_length=length_hold;
 // APF transfers write each word once. The mask describes only valid bytes
 // of the final word; padding is not file data and is deterministically zero.
 // Whole-word writes in a dedicated clocked process are the canonical Intel
 // dual-clock RAM pattern (byte writes in the control FSM became 40k flops).
 wire ram_we=host_active && host_we && !host_reset && {16'd0,host_waddr}<MAX_BYTES;
 wire[31:0]ram_wdata={host_wmask[3]?host_wdata[31:24]:8'd0,
                      host_wmask[2]?host_wdata[23:16]:8'd0,
                      host_wmask[1]?host_wdata[15:8]:8'd0,
                      host_wmask[0]?host_wdata[7:0]:8'd0};
 always @(posedge host_clk)
   if(ram_we)ram[host_waddr[AW+1:2]]<=ram_wdata;
 always @(posedge host_clk) begin
   request_sync <= {request_sync[1:0],request_toggle};
   if(host_reset) begin
     request_sync<=0; host_seen<=0; host_active<=0;
     host_accepted<=0; complete_toggle<=0;
     result_error<=0; result_length<=0;
   end else begin
     if(!host_active && request_sync[2]!=host_seen) begin
       host_seen<=request_sync[2];host_active<=1;host_accepted<=0;
     end
     if(host_req && host_ack) host_accepted<=1;
     if(host_active && host_done) begin
       result_error<=host_error!=0 || host_actual!=length_hold;
       result_length<=host_actual;
       complete_toggle<=~complete_toggle;
       host_active<=0;host_accepted<=0;
     end
   end
 end
 reg complete_seen;
 // Explicit synchronous RAM read; this is suitable for an M10K read port.
 always @(posedge sys_clk) ram_q <= ram[index[AW-1:0]];
 always @(posedge sys_clk) begin
   complete_sync <= {complete_sync[1:0],complete_toggle};
   resp_done<=0;
   if(sys_reset) begin
     complete_sync<=0;complete_seen<=0;request_toggle<=0;
     state<=0;resp_valid<=0;resp_done<=0;resp_error<=0;
     index<=0;words<=0;offset_hold<=0;length_hold<=0;resp_data<=0;
   end else case(state)
     0: if(req_valid) begin
       offset_hold<=req_offset;length_hold<=req_length;
       resp_error<=0;index<=0;resp_valid<=0;
       if(req_length==0 || {16'd0,req_length}>MAX_BYTES) begin resp_done<=1;resp_error<=1;end
       else begin request_toggle<=~request_toggle;state<=1;end
     end
     1: if(complete_sync[2]!=complete_seen) begin
       complete_seen<=complete_sync[2];resp_error<=result_error;
       words<= (AW+1)'(({1'b0,result_length}+17'd3)>>2);
       index<=0;
       if(result_error || result_length==0) begin resp_done<=1;state<=0;end
       else state<=2;
     end
     2: state<=3;
     3: begin
       if(!resp_valid) begin resp_data<=ram_q;resp_valid<=1;end
       else if(resp_ready) begin
         resp_valid<=0;
         if(index+1>=words) begin resp_done<=1;state<=0;end
         else begin index<=index+1'b1;state<=2;end
       end
     end
   endcase
 end
endmodule
