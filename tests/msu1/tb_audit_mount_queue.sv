// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module tb_audit_mount_queue;
 reg sys_clk=0,host_clk=0,reset=1;
 always #7 sys_clk=~sys_clk;always #5 host_clk=~host_clk;
 reg cancel=0,track_request=0,track_update=0,player_busy=0,transport_idle=1;
 reg[15:0]track_num=0;wire mounting,mount_missing,track_load;
 wire[31:0]track_size;wire host_req;wire[15:0]host_track;
 reg host_ack=0,host_done=0;reg[2:0]host_error=0;reg[31:0]host_size=0;
 msu_mount_cdc dut(.*);
 integer opened=0,loaded=0;
 reg allow_done=0;
 integer track_log[0:9];
 always @(posedge sys_clk)if(track_load)begin loaded=loaded+1;end
 initial begin: host
 reg[15:0]held_track;
 forever begin
 wait(host_req);held_track=host_track;track_log[opened]=host_track;opened=opened+1;
 @(negedge host_clk);host_ack=1;
 @(negedge host_clk);host_ack=0;
 while(!allow_done)begin @(negedge host_clk);if(host_track!==held_track)$fatal(1,"bundled track mutated while in flight");end
 allow_done=0;host_size=1000+opened;host_done=1;
 @(negedge host_clk);host_done=0;
 end
 end
 task update_track(input[15:0]n);
 begin @(negedge sys_clk);track_request=1;track_num=n;track_update=~track_update;end endtask
 task finish_open;
 begin @(negedge host_clk);allow_done=1;end endtask
 initial begin
 repeat(5)@(negedge sys_clk);reset=0;repeat(5)@(negedge sys_clk);
 update_track(1);wait(opened==1);
 update_track(2);update_track(3);repeat(6)@(negedge sys_clk);finish_open();
 wait(opened==2);
 if(track_log[0]!=1||track_log[1]!=3||loaded!=0)$fatal(1,"latest queued mount did not supersede prior completions");
 // A second request for the exact same track still represents a new mount.
 update_track(3);repeat(6)@(negedge sys_clk);finish_open();wait(opened==3);
 if(track_log[2]!=3||loaded!=0)$fatal(1,"same-track update was lost");
 finish_open();wait(loaded==1);wait(!mounting);
 if(track_size!=1003||mount_missing)$fatal(1,"stale completion published");
 // Re-request while request is still high at the completed-mount boundary.
 update_track(4);wait(opened==4);finish_open();wait(loaded==2);wait(!mounting);
 if(track_log[3]!=4||track_size!=1004)$fatal(1,"held-request boundary update lost");
 @(negedge sys_clk);track_request=0;repeat(5)@(negedge sys_clk);
 if(mounting||opened!=4||loaded!=2)$fatal(1,"duplicate mount");
 // Keep an old PCM read busy: opening may not begin before it is drained.
 transport_idle=0;update_track(5);repeat(15)@(negedge sys_clk);
 if(opened!=4||!mounting)$fatal(1,"slot opened before read transport drained");
 transport_idle=1;wait(opened==5);finish_open();wait(loaded==3);wait(!mounting);
 $display("PASS tb_audit_mount_queue: latest and same-track queue, stable bundled payload, request boundary, drain ordering");$finish;
 end
 initial begin #100000;$fatal(1,"mount queue timeout state=%0d opened=%0d loaded=%0d",dut.state,opened,loaded);end
endmodule
