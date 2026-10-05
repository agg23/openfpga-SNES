// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module tb_msu_pocket_integration;
 reg sys_clk=0,host_clk=0,reset=1;always #7 sys_clk=~sys_clk;always #5 host_clk=~host_clk;
 reg init_req=0,soft_reset=0;wire init_busy;
 reg[31:0]bridge_addr=0,bridge_wr_data=0;reg bridge_rd=0,bridge_wr=0,bridge_endian_little=0;
 wire[31:0]bridge_rd_data,wrapper_bridge_data,cmd_bridge_rd_data;
 assign bridge_rd_data=bridge_addr[31:24]== 8'hF8 ? cmd_bridge_rd_data:wrapper_bridge_data;
 wire target_dataslot_read,target_dataslot_write,target_dataslot_getfile,target_dataslot_openfile;
 wire target_dataslot_ack,target_dataslot_done;wire[2:0]target_dataslot_err;
 wire[15:0]target_dataslot_id;
 wire[31:0]target_dataslot_slotoffset,target_dataslot_bridgeaddr,target_dataslot_length,target_buffer_param_struct,target_buffer_resp_struct;
 wire msu_enable;reg[15:0]track_num=0;reg track_request=0,track_update=0;wire track_mounting,track_missing;
 reg[7:0]volume=255;reg audio_repeat=0,audio_playing=0,audio_resume=0;
 wire audio_stop;wire[21:0]audio_sector;wire[31:0]audio_loop_index;
 reg[21:0]resume_sector=0;reg[31:0]resume_loop_index=0;
 reg[31:0]data_addr=0;reg data_seek=0,data_next=0;wire[7:0]data;wire data_ack,data_busy;
 reg signed[15:0]main_l=0,main_r=0;wire signed[15:0]audio_l,audio_r;
 msu_pocket #(.CLK_RATE(441000),.PCM_BUFFER_BYTES(8192)) dut(.bridge_rd_data(wrapper_bridge_data),.*);
 // Use the actual repository APF command handler, not a target-done stub.
 core_bridge_cmd cb(
 .clk(host_clk),.reset_n(),.bridge_endian_little(bridge_endian_little),
 .bridge_addr(bridge_addr),.bridge_rd(bridge_rd),.bridge_wr(bridge_wr),
 .bridge_wr_data(bridge_wr_data),.bridge_rd_data(cmd_bridge_rd_data),
 .status_boot_done(1'b1),.status_setup_done(1'b0),.status_running(1'b0),
 .dataslot_requestread_ack(1'b1),.dataslot_requestread_ok(1'b1),
 .dataslot_requestwrite_ack(1'b1),.dataslot_requestwrite_ok(1'b1),
 .savestate_supported(1'b0),.savestate_addr(32'd0),.savestate_size(32'd0),.savestate_maxloadsize(32'd0),
 .savestate_start_ack(1'b0),.savestate_start_busy(1'b0),.savestate_start_ok(1'b0),.savestate_start_err(1'b0),
 .savestate_load_ack(1'b0),.savestate_load_busy(1'b0),.savestate_load_ok(1'b0),.savestate_load_err(1'b0),
 .target_dataslot_read(target_dataslot_read),.target_dataslot_write(target_dataslot_write),
 .target_dataslot_getfile(target_dataslot_getfile),.target_dataslot_openfile(target_dataslot_openfile),
 .target_dataslot_ack(target_dataslot_ack),.target_dataslot_done(target_dataslot_done),.target_dataslot_err(target_dataslot_err),
 .target_dataslot_id(target_dataslot_id),.target_dataslot_slotoffset(target_dataslot_slotoffset),
 .target_dataslot_bridgeaddr(target_dataslot_bridgeaddr),.target_dataslot_length(target_dataslot_length),
 .target_buffer_param_struct(target_buffer_param_struct),.target_buffer_resp_struct(target_buffer_resp_struct),
 .datatable_addr(10'd0),.datatable_wren(1'b0),.datatable_data(32'd0),.datatable_q());
 // Existing APF uses FPGA power-up zero for its FSMs rather than RTL resets.
 // Give that existing hardware power-up behavior explicit 4-state sim values.
 initial begin cb.hstate=0;cb.tstate=0;cb.host_cmd_start=0;end
 string filename="/Assets/snes/common/Game.sfc";
 integer current_track=0,pcm_open_count=0,pcm_read_count=0;
 reg active_pcm_payload=0,need_header=0;
 function automatic[31:0]swap(input[31:0]v);swap={v[7:0],v[15:8],v[23:16],v[31:24]};endfunction
 task automatic wr(input[31:0]a,input[31:0]d);
 begin @(negedge host_clk);bridge_addr=a;bridge_wr_data=d;bridge_wr=1;@(negedge host_clk);bridge_wr=0;end endtask
 task automatic rd(input[31:0]a,output[31:0]d);
 begin @(negedge host_clk);bridge_addr=a;bridge_rd=1;
 @(negedge host_clk);bridge_rd=0;d=bridge_rd_data;end endtask
 task automatic size_entry(input integer entry,input[15:0]slot,input[31:0]size);
 begin wr(32'hF8002000+entry*8,{16'd0,slot});wr(32'hF8002004+entry*8,size);end endtask
 task automatic read_path(output string value);
 reg[31:0]w;reg[7:0]c;
 begin value="";for(integer j=0;j<64;j=j+1)begin
 @(negedge host_clk);bridge_addr=32'h90000000+j*4;bridge_rd=1;
 @(negedge host_clk);bridge_rd=0;w=swap(bridge_rd_data);
 for(integer k=0;k<4;k=k+1)begin c=w[k*8+:8];if(c!=0)value={value,c};else begin j=64;k=4;end end
 end end endtask
 initial begin:host
 reg[15:0]slot;reg[31:0]off,len,dest,w,command,parameter0,pointer;reg is_get,is_open;string path;
 forever begin
 rd(32'hF8001000,command);
 if(command[31:16]===16'h636D)begin
 is_get=command[15:0]==16'h0190;is_open=command[15:0]==16'h0192;
 if(!is_get&&!is_open&&command[15:0]!=16'h0180)$fatal(1,"Unexpected APF command %08x",command);
 rd(32'hF8001004,pointer);
 if(pointer!=32'h20)$fatal(1,"Unexpected framework parameter pointer");
 rd(32'hF8001020,parameter0);slot=parameter0[15:0];
 rd(32'hF8001024,off);
 rd(32'hF8001028,dest);
 rd(32'hF800102C,len);
 if((is_get||is_open)&&off!=32'h90000000)$fatal(1,"Wrong struct pointer");
 wr(32'hF8001000,32'h62750000);
 if(is_get)begin
 for(integer j=0;j<256;j=j+4)begin w=0;for(integer k=0;k<4;k=k+1)if(j+k<filename.len())w[k*8+:8]=filename[j+k];wr(32'h90000000+j,swap(w));end
 end else if(is_open)begin
 read_path(path);
 if(slot==100)begin
 if(path!="/Assets/snes/common/Game.msu")$fatal(1,"MSU path");size_entry(2,100,8192);
 end else begin
 if(!dut.pcm_idle)$fatal(1,"PCM slot replaced before old response drained");
 pcm_open_count=pcm_open_count+1;
 if(path=="/Assets/snes/common/Game-1.pcm")current_track=1;
 else if(path=="/Assets/snes/common/Game-2.pcm")current_track=2;
 else $fatal(1,"Unexpected PCM filename %s",path);
 need_header=1;size_entry(3,101,16392);
 end
 end else begin
 if(slot==101)begin
 pcm_read_count=pcm_read_count+1;
 if(need_header&&off!=0)$fatal(1,"Old track offset read after replacement: %d",off);
 need_header=0;active_pcm_payload=off>=8;
 end
 repeat(40)@(negedge host_clk);
 for(integer j=0;j<len;j=j+4)begin
 if(slot==101)begin
 if(off+j==0)w=32'h3155534D;
 else if(off+j==4)w=0;
 else w=current_track==1?32'h01000100:32'h02000200;
 end else begin for(integer k=0;k<4;k=k+1)w[k*8+:8]=(off+j+k)&255;end
 wr(dest+j,swap(w));
 end
 active_pcm_payload=0;
 end
 repeat(3)@(negedge host_clk);wr(32'hF8001000,32'h6F6B0000);
 end
 end
 end
 task automatic start_track(input[15:0]number);
 begin @(negedge sys_clk);track_num=number;track_request=1;track_update=~track_update;audio_playing=0;
 wait(track_mounting);wait(!track_mounting);@(negedge sys_clk);track_request=0;
 if(track_missing)$fatal(1,"Track reported missing");repeat(4)@(negedge sys_clk);end endtask
 initial begin
 repeat(6)@(negedge host_clk);reset=0;repeat(8)@(negedge sys_clk);
 @(negedge host_clk);init_req=1;@(negedge host_clk);init_req=0;
 wait(msu_enable);if(init_busy)$fatal(1,"Enabled before bootstrap");
 @(negedge sys_clk);data_addr=123;data_seek=1;wait(data_ack);@(negedge sys_clk);data_seek=0;
 repeat(3)@(negedge sys_clk);if(data!==123)$fatal(1,"Integrated MSU data seek");
 start_track(1);audio_playing=1;
 wait(audio_l==16'sd255);
 // Trigger replacement after a refill is already accepted by the host.
 wait(active_pcm_payload);start_track(2);audio_playing=1;
 wait(audio_l==16'sd510);
 if(pcm_open_count!=2)$fatal(1,"Unexpected duplicate slot opens");
 if(audio_r!=16'sd510)$fatal(1,"New track stereo mismatch");
 $display("PASS tb_msu_pocket_integration: actual APF command handler, bootstrap, data, PCM mount, in-flight track replacement, mixed samples");$finish;
 end
 initial begin repeat(100000)@(posedge sys_clk);$fatal(1,"Pocket integration timeout");end
endmodule

// Behavioral replacement only for the vendor-specific data-table block RAM.
// The production implementation still uses the repository's Intel mf_datatable.
module mf_datatable(
 input wire[9:0]address_a,address_b,input wire clock_a,clock_b,
 input wire[31:0]data_a,data_b,input wire wren_a,wren_b,
 output reg[31:0]q_a,q_b
);
 reg[31:0]mem[0:1023];
 always @(posedge clock_a)begin if(wren_a)mem[address_a]<=data_a;q_a<=mem[address_a];end
 always @(posedge clock_b)begin if(wren_b)mem[address_b]<=data_b;q_b<=mem[address_b];end
endmodule
