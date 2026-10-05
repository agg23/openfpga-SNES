// SPDX-License-Identifier: GPL-3.0-or-later
module msu_pocket #(parameter integer CLK_RATE=21477270, PCM_BUFFER_BYTES=8192, DEBUG=0)(
 input wire sys_clk, host_clk, reset,
 input wire soft_reset, // Synchronous SNES reset: drain transports, preserve file discovery
 input wire init_req, output wire init_busy,
 input wire [31:0] bridge_addr, input wire bridge_rd, bridge_wr,
 input wire [31:0] bridge_wr_data, input wire bridge_endian_little,
 output wire [31:0] bridge_rd_data,
 output wire target_dataslot_read,target_dataslot_write,target_dataslot_getfile,target_dataslot_openfile,
 input wire target_dataslot_ack,target_dataslot_done,input wire [2:0] target_dataslot_err,
 output wire[15:0]target_dataslot_id,
 output wire[31:0]target_dataslot_slotoffset,target_dataslot_bridgeaddr,target_dataslot_length,
 output wire[31:0]target_buffer_param_struct,target_buffer_resp_struct,
 output wire msu_enable,
 input wire[15:0]track_num,input wire track_request, track_update,
 output wire track_mounting,track_missing,
 input wire[7:0]volume,input wire audio_repeat,audio_playing,audio_resume,
 output wire audio_stop,output wire[21:0]audio_sector,
 output wire[31:0]audio_loop_index,
 input wire[21:0]resume_sector,input wire[31:0]resume_loop_index,
 input wire[31:0]data_addr,input wire data_seek,data_next,
 output wire[7:0]data,output wire data_ack,data_busy,
 input wire signed[15:0]main_l,main_r,output wire signed[15:0]audio_l,audio_r
);
 reg [2:0] sys_reset_pipe=7, host_reset_pipe=7;
 always @(posedge sys_clk or posedge reset)
   if(reset)sys_reset_pipe<=7;else sys_reset_pipe<={sys_reset_pipe[1:0],1'b0};
 always @(posedge host_clk or posedge reset)
   if(reset)host_reset_pipe<=7;else host_reset_pipe<={host_reset_pipe[1:0],1'b0};
 wire sys_reset=sys_reset_pipe[2],host_reset=host_reset_pipe[2];
 reg bootstrap=1,init_pending=0,init_inflight=0,host_init=0;
 reg quiesce_toggle,quiesce_wait,quiesce_ack;
 wire host_init_done,host_present;
 wire[31:0]host_data_size;
 (* async_reg="true", altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)reg[2:0]boot_sync,present_sync,quiesce_sync,ack_sync;
 reg[31:0]data_size_s;
 assign init_busy=boot_sync[2];
 assign msu_enable=present_sync[2]&&!boot_sync[2];
 wire player_busy,player_missing,track_load,mount_missing;
 wire[31:0]track_size,player_frame,player_loop;
 wire data_idle,pcm_idle;
 wire lifecycle_reset=soft_reset||init_busy;
 reg data_drain,pcm_drain;
 always @(posedge sys_clk)begin
   if(lifecycle_reset)begin data_drain<=1;pcm_drain<=1;end
   else begin if(data_idle)data_drain<=0;if(pcm_idle)pcm_drain<=0;end
   if(sys_reset)begin data_drain<=0;pcm_drain<=0;end
 end
 wire data_reset=sys_reset||lifecycle_reset||data_drain;
 wire pcm_reset=sys_reset||lifecycle_reset||pcm_drain;
 reg previous_track_update,pcm_suspend;
 wire pcm_can_request=!pcm_reset && !pcm_suspend && !(track_update!=previous_track_update);
 always @(posedge sys_clk)begin
   previous_track_update<=track_update;
   if(track_load)pcm_suspend<=0;
   if(track_update!=previous_track_update)pcm_suspend<=1;
   if(pcm_reset)begin previous_track_update<=track_update;pcm_suspend<=0;end
 end
 wire sys_idle=init_busy&&data_idle&&pcm_idle&&!track_mounting;
 // Bootstrap waits for the system side to observe the hold and drain.
 // A stale pre-bootstrap idle sample must never admit file reinitialization.
 // The data size is stable before bootstrap falls through three flops.
 always @(posedge sys_clk)begin
   boot_sync<={boot_sync[1:0],bootstrap};
   present_sync<={present_sync[1:0],host_present};
   data_size_s<=host_data_size;
   quiesce_sync<={quiesce_sync[1:0],quiesce_toggle};
   if(sys_idle)quiesce_ack<=quiesce_sync[2];
   if(sys_reset)begin boot_sync<=7;present_sync<=0;data_size_s<=0;quiesce_sync<=0;quiesce_ack<=0;end
 end
 always @(posedge host_clk)begin
   ack_sync<={ack_sync[1:0],quiesce_ack};host_init<=0;
   if(host_reset)begin bootstrap<=1;init_pending<=0;init_inflight<=0;ack_sync<=0;quiesce_toggle<=0;quiesce_wait<=0;end
   else begin
     if(init_req)begin bootstrap<=1;init_pending<=1;end
     if(init_pending&&!init_inflight&&!quiesce_wait)begin
       quiesce_toggle<=~quiesce_toggle;quiesce_wait<=1;
     end
     if(quiesce_wait&&ack_sync[2]==quiesce_toggle)begin
       host_init<=1;init_pending<=0;init_inflight<=1;quiesce_wait<=0;
     end
     if(host_init_done)begin init_inflight<=0;if(!init_pending && !init_req)bootstrap<=0;end
   end
 end
 wire[15:0]pcm_track;
 wire pcm_open_req,pcm_open_ack,pcm_open_done;
 wire[2:0]pcm_open_error;wire[31:0]pcm_size;
 msu_mount_cdc mount(.sys_clk(sys_clk),.host_clk(host_clk),.reset(reset),
 .cancel(lifecycle_reset),.track_request(track_request&&!lifecycle_reset),.track_update(track_update),.track_num(track_num),.mounting(track_mounting),
 .mount_missing(mount_missing),.track_load(track_load),.track_size(track_size),.player_busy(player_busy),.transport_idle(pcm_idle&&!pcm_reset),
 .host_req(pcm_open_req),.host_track(pcm_track),.host_ack(pcm_open_ack),.host_done(pcm_open_done),
 .host_error(pcm_open_error),.host_size(pcm_size));
 assign track_missing=mount_missing||player_missing;
 // Upstream resume_sector carries frame/1024, resume_loop_index carries the
 // exact full frame. This is an internal transport mapping, no register change.
 assign audio_sector=player_frame[31:10];
 assign audio_loop_index=player_frame;
 wire data_underrun,pcm_underrun;
 wire[31:0]pcm_underrun_count;
 wire[15:0]pcm_fifo_level;
 generate if(DEBUG != 0)begin:g_debug
   // SignalTap snapshots remain in sys_clk; no unsafe multi-bit bridge CDC.
   (* keep *)reg[31:0]debug_track,debug_pcm_frame,debug_data_offset;
   (* keep *)reg[31:0]debug_fifo_flags,debug_underrun_count;
   always @(posedge sys_clk)begin
     debug_track<={16'b0,track_num};debug_pcm_frame<=player_frame;
     debug_data_offset<=data_addr;
     debug_fifo_flags<={pcm_fifo_level,8'b0,msu_enable,track_mounting,track_missing,audio_playing,audio_repeat,data_busy,data_underrun,pcm_underrun};
     debug_underrun_count<=pcm_underrun_count;
   end
 end endgenerate
 wire data_req,data_ack_host,data_done,data_we;
 wire[31:0]data_offset,data_wdata;wire[15:0]data_length,data_actual,data_waddr;
 wire[2:0]data_error;wire[3:0]data_wmask;
 wire data_req_valid,data_resp_valid,data_resp_ready,data_resp_done,data_resp_error;
 wire[31:0]data_req_offset,data_resp_data;wire[15:0]data_req_length;
 msu_block_cdc #(.MAX_BYTES(4096)) data_cdc(
 .sys_clk(sys_clk),.host_clk(host_clk),.reset(reset),
 .req_valid(data_req_valid&&!data_reset),.req_ready(data_idle),.req_offset(data_req_offset),.req_length(data_req_length),
 .resp_valid(data_resp_valid),.resp_ready(data_resp_ready||data_reset),.resp_data(data_resp_data),.resp_done(data_resp_done),.resp_error(data_resp_error),
 .host_req(data_req),.host_ack(data_ack_host),.host_offset(data_offset),.host_length(data_length),
 .host_done(data_done),.host_error(data_error),.host_actual(data_actual),
 .host_we(data_we),.host_waddr(data_waddr),.host_wdata(data_wdata),.host_wmask(data_wmask));
 wire pcm_req,pcm_ack,pcm_done,pcm_we;
 wire[31:0]pcm_offset,pcm_wdata;wire[15:0]pcm_length,pcm_actual,pcm_waddr;
 wire[2:0]pcm_error;wire[3:0]pcm_wmask;
 wire pcm_req_valid,pcm_resp_valid,pcm_resp_ready,pcm_resp_done,pcm_resp_error;
 wire[31:0]pcm_req_offset,pcm_resp_data;wire[15:0]pcm_req_length;
 msu_block_cdc #(.MAX_BYTES(1024)) pcm_cdc(
 .sys_clk(sys_clk),.host_clk(host_clk),.reset(reset),
 .req_valid(pcm_req_valid&&pcm_can_request),.req_ready(pcm_idle),.req_offset(pcm_req_offset),.req_length(pcm_req_length),
 .resp_valid(pcm_resp_valid),.resp_ready(pcm_resp_ready||pcm_reset),.resp_data(pcm_resp_data),.resp_done(pcm_resp_done),.resp_error(pcm_resp_error),
 .host_req(pcm_req),.host_ack(pcm_ack),.host_offset(pcm_offset),.host_length(pcm_length),
 .host_done(pcm_done),.host_error(pcm_error),.host_actual(pcm_actual),
 .host_we(pcm_we),.host_waddr(pcm_waddr),.host_wdata(pcm_wdata),.host_wmask(pcm_wmask));
 msu_data_cache cache(.clk(sys_clk),.reset(data_reset),.enable(msu_enable),
 .file_size(data_size_s),.data_addr(data_addr),.data_seek(data_seek),.data_next(data_next),
 .data_ack(data_ack),.data(data),.busy(data_busy),.underrun(data_underrun),
 .req_valid(data_req_valid),.req_ready(data_idle&&!data_reset),.req_offset(data_req_offset),.req_length(data_req_length),
 .resp_valid(data_resp_valid),.resp_ready(data_resp_ready),.resp_data(data_resp_data),.resp_done(data_resp_done),.resp_error(data_resp_error));
 wire[10:0]pcm_req_length_short;
 assign pcm_req_length={5'b0,pcm_req_length_short};
 msu_pcm_player #(.CLK_RATE(CLK_RATE),.BUFFER_BYTES(PCM_BUFFER_BYTES)) player(
 .clk(sys_clk),.reset(pcm_reset),.track_load(track_load),.track_size(track_size),.track_missing(mount_missing),
 .ctl_play(audio_playing),.ctl_repeat(audio_repeat),.ctl_volume(volume),.ctl_resume(audio_resume),.resume_frame(resume_loop_index),
 .busy(player_busy),.missing(player_missing),.playing(),.stop(audio_stop),
 .audio_frame(player_frame),.audio_loop_index(player_loop),.underrun(pcm_underrun),.underrun_count(pcm_underrun_count),.fifo_level(pcm_fifo_level),.sample_ce(),
 .pcm_l(),.pcm_r(),.main_l(main_l),.main_r(main_r),.mixed_l(audio_l),.mixed_r(audio_r),
 .req_valid(pcm_req_valid),.req_ready(pcm_idle&&pcm_can_request),.req_offset(pcm_req_offset),.req_length(pcm_req_length_short),
 .resp_valid(pcm_resp_valid),.resp_ready(pcm_resp_ready),.resp_data(pcm_resp_data),.resp_done(pcm_resp_done),.resp_error(pcm_resp_error));
 msu_pocket_host host(.clk(host_clk),.reset(host_reset),.init_req(host_init),.init_done(host_init_done),.msu_present(host_present),.data_size(host_data_size),
 .data_req(data_req),.data_offset(data_offset),.data_length(data_length),.data_ack(data_ack_host),
 .data_done(data_done),.data_error(data_error),.data_actual(data_actual),
 .pcm_open_req(pcm_open_req),.pcm_track(pcm_track),.pcm_open_ack(pcm_open_ack),.pcm_open_done(pcm_open_done),.pcm_open_error(pcm_open_error),.pcm_size(pcm_size),
 .pcm_read_req(pcm_req),.pcm_offset(pcm_offset),.pcm_length(pcm_length),.pcm_read_ack(pcm_ack),.pcm_read_done(pcm_done),.pcm_read_error(pcm_error),.pcm_actual(pcm_actual),
 .bridge_addr(bridge_addr),
 .bridge_rd(bridge_rd),
 .bridge_wr(bridge_wr),
 .bridge_wr_data(bridge_wr_data),
 .bridge_endian_little(bridge_endian_little),
 .bridge_rd_data(bridge_rd_data),
 .data_we(data_we),
 .data_waddr(data_waddr),
 .data_wdata(data_wdata),
 .data_wmask(data_wmask),
 .pcm_we(pcm_we),
 .pcm_waddr(pcm_waddr),
 .pcm_wdata(pcm_wdata),
 .pcm_wmask(pcm_wmask),
 .target_dataslot_read(target_dataslot_read),
 .target_dataslot_write(target_dataslot_write),
 .target_dataslot_getfile(target_dataslot_getfile),
 .target_dataslot_openfile(target_dataslot_openfile),
 .target_dataslot_ack(target_dataslot_ack),
 .target_dataslot_done(target_dataslot_done),
 .target_dataslot_err(target_dataslot_err),
 .target_dataslot_id(target_dataslot_id),
 .target_dataslot_slotoffset(target_dataslot_slotoffset),
 .target_dataslot_bridgeaddr(target_dataslot_bridgeaddr),
 .target_dataslot_length(target_dataslot_length),
 .target_buffer_param_struct(target_buffer_param_struct),
 .target_buffer_resp_struct(target_buffer_resp_struct));
endmodule
