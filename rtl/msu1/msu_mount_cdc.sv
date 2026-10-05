// SPDX-License-Identifier: GPL-3.0-or-later
// Track number/size are bundled-data mailboxes, held through toggle handshake.
module msu_mount_cdc(
 input wire sys_clk,host_clk,reset,
 input wire cancel, // Cancel consumers; an accepted host open must still drain
 input wire track_request,track_update,input wire[15:0]track_num,
 output wire mounting,output reg mount_missing,
 output reg track_load,output reg[31:0]track_size,
 input wire player_busy, transport_idle,
 output wire host_req,output wire[15:0]host_track,
 input wire host_ack,host_done,input wire[2:0]host_error,
 input wire[31:0]host_size
);
 reg [2:0] sys_reset_pipe=7, host_reset_pipe=7;
 always @(posedge sys_clk or posedge reset)
   if(reset)sys_reset_pipe<=7;else sys_reset_pipe<={sys_reset_pipe[1:0],1'b0};
 always @(posedge host_clk or posedge reset)
   if(reset)host_reset_pipe<=7;else host_reset_pipe<={host_reset_pipe[1:0],1'b0};
 wire sys_reset=sys_reset_pipe[2],host_reset=host_reset_pipe[2];
 reg req_toggle,done_toggle;
 reg[15:0]track_hold;reg[31:0]size_hold;reg error_hold;
 (* async_reg="true", altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)reg[2:0]req_sync,done_sync;
 reg req_seen,done_seen,active,accepted;
 reg[2:0]state;
 reg update_seen,pending,cancelled;
 reg[15:0]pending_track;
 wire new_update=track_update!=update_seen;
 wire request_pending=track_request&&(pending||new_update);
 wire[15:0]next_track=new_update?track_num:pending_track;
 assign host_req=active&&!accepted;
 assign host_track=track_hold;
 assign mounting=state!=0 && state!=5;
 always @(posedge host_clk)begin
 req_sync<={req_sync[1:0],req_toggle};
 if(host_reset)begin req_sync<=0;req_seen<=0;done_toggle<=0;active<=0;accepted<=0;size_hold<=0;error_hold<=0;end
 else begin
 if(!active&&req_sync[2]!=req_seen)begin req_seen<=req_sync[2];active<=1;accepted<=0;end
 if(host_req&&host_ack)accepted<=1;
 if(active&&host_done)begin size_hold<=host_size;error_hold<=host_error!=0;done_toggle<=~done_toggle;active<=0;accepted<=0;end
 end end
 always @(posedge sys_clk)begin
 done_sync<={done_sync[1:0],done_toggle};track_load<=0;
 if(sys_reset)begin done_sync<=0;done_seen<=0;req_toggle<=0;state<=0;track_load<=0;track_size<=0;track_hold<=0;mount_missing<=0;update_seen<=0;pending<=0;pending_track<=0;cancelled<=0;end
 else begin
   if(new_update)begin update_seen<=track_update;if(track_request)begin pending<=1;pending_track<=track_num;end end
   if(!track_request)pending<=0;
   if(cancel)begin
     update_seen<=track_update;pending<=0;mount_missing<=0;cancelled<=1;
     if(state==1)begin
       if(done_sync[2]!=done_seen)begin done_seen<=done_sync[2];state<=0;end
     end else state<=0;
   end else case(state)
 0:if(track_request && request_pending)begin track_hold<=next_track;pending<=0;cancelled<=0;state<=6;mount_missing<=0;end
 6:if(transport_idle)begin req_toggle<=~req_toggle;state<=1;end
 1:if(done_sync[2]!=done_seen)begin
   done_seen<=done_sync[2];
   if(request_pending)begin track_hold<=next_track;pending<=0;cancelled<=0;state<=6;end
   else if(cancelled || !track_request)begin state<=0;end
   else begin track_size<=size_hold;mount_missing<=error_hold;track_load<=1;state<=2;end
 end
 2:state<=3;
 3:state<=4;
 4:if(request_pending)begin track_hold<=next_track;pending<=0;cancelled<=0;state<=6;end
   else if(!player_busy)state<=5;
 5:if(request_pending && track_request)begin track_hold<=next_track;pending<=0;cancelled<=0;state<=6;end
   else if(!track_request)state<=0;
 default:state<=0;
 endcase
 end
 end
endmodule
