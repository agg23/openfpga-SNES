// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module tb_audio_memory_continuity;
 parameter PAL=0;
 localparam integer RATE=PAL ? 21281370 : 21477270;
 localparam real SYS_HALF=500000000.0/RATE;
 reg sys_clk=0,host_clk=0,mem_clk=0,reset=1;always #(SYS_HALF) sys_clk=~sys_clk;always #6.734 host_clk=~host_clk;always #(SYS_HALF/5.0) mem_clk=~mem_clk;
 reg init_req=0;wire soft_reset;wire init_busy;
 reg[31:0]bridge_addr=0,bridge_wr_data=0;reg bridge_rd=0,bridge_wr=0,bridge_endian_little=0;
 wire[31:0]bridge_rd_data,wrapper_bridge_data,cmd_bridge_rd_data;
 assign bridge_rd_data=bridge_addr[31:24]== 8'hF8 ? cmd_bridge_rd_data:wrapper_bridge_data;
 wire host_reset_n;
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
 msu_pocket #(.CLK_RATE(RATE),.PCM_BUFFER_BYTES(8192)) dut(.bridge_rd_data(wrapper_bridge_data),.*);
 // Use the actual repository APF command handler, not a target-done stub.
 core_bridge_cmd cb(
 .clk(host_clk),.reset_n(host_reset_n),.bridge_endian_little(bridge_endian_little),
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
 // One APF bus owner inserts commands while an already-accepted PCM payload
 // is deliberately held. Save uses the real queue; its RAM sink and clear-busy
 // duration are bounded behavioral lifecycle stimuli, not a full MAIN model.
 integer inject_kind=0,injected_count=0,released_count=0;
 reg release_lifecycle=0,release_payload=0,drain_monitor=0;
 reg save_accept=1,ram_clear_busy=0;
 integer drained_words=0,expected_drain_words=0,drained_completions=0;
 integer drained_apf_done=0,drained_host_done=0,save_words=0;
 reg previous_apf_done=0,apf_pcm_operation=0;
 integer drained_other_apf_done=0;
 function automatic[31:0]swap(input[31:0]v);swap={v[7:0],v[15:8],v[23:16],v[31:24]};endfunction
 task automatic wr(input[31:0]a,input[31:0]d);
 begin @(negedge host_clk);bridge_addr=a;bridge_wr_data=d;bridge_wr=1;@(negedge host_clk);bridge_wr=0;end endtask
 task automatic rd(input[31:0]a,output[31:0]d);
 begin @(negedge host_clk);bridge_addr=a;bridge_rd=1;
 @(negedge host_clk);bridge_rd=0;d=bridge_rd_data;end endtask
 task automatic host_command(input[15:0]command);
 reg[31:0]reply;
 begin
  wr(32'hF8000000,{16'h434D,command});
  do rd(32'hF8000000,reply);while(reply[31:16]!==16'h4F4B || cb.hstate!==0);
  if(reply[15:0]!=0)$fatal(1,"APF host command failed %04x",command);
 end endtask
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
 wait(!reset);host_command(16'h0011);
 forever begin
 if(rom_job!=rom_done)begin
   download_active=1;repeat(8)@(negedge host_clk);
   wr(32'h10000000,32'h11223344);
   repeat(8)@(negedge host_clk);download_active=0;
   rom_done=rom_job;
 end
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
 apf_pcm_operation=!is_get && !is_open && slot==101;
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
 if(active_pcm_payload && inject_kind!=0)begin
  if({dut.pcm_cdc.host_active,dut.pcm_cdc.host_accepted,dut.pcm_idle}!==3'b110 || len!==32'd1024)
    $fatal(1,"LIFECYCLE_VACUOUS: injection needs accepted 1024-byte PCM transport");
  drained_words=0;expected_drain_words=len/4;drained_completions=0;
  drained_apf_done=0;drained_other_apf_done=0;drained_host_done=0;drain_monitor=1;
  case(inject_kind)
   1:host_command(16'h0010);
   2:begin save_accept=0;wr(32'h20000000,32'h89abcdef);end
   3:ram_clear_busy=1;
   default:$fatal(1,"Unknown lifecycle injection");
  endcase
  injected_count=injected_count+1;
  wait(release_lifecycle);
  case(inject_kind)
   1:host_command(16'h0011);
   2:save_accept=1;
   3:ram_clear_busy=0;
  endcase
  released_count=released_count+1;
  wait(release_payload);inject_kind=0;
 end
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

 // ROM download, command CDC and physical-refresh engine are production RTL.
 // DQ is constant test ROM content; command service/refresh timing is real RTL.
 reg download_active=0;integer rom_job=0,rom_done=0;
 wire qvalid,qready,qen,image_busy,image_complete,queue_fault,image_config_valid;wire[16:0]image_config;
 wire[24:0]qaddr;wire[15:0]qdata;
 wire save_busy,save_valid,save_en,host_quiescent;
 wire[16:0]save_addr;wire[15:0]save_data;
 wire save_ready=save_accept && host_quiescent && !ram_clear_busy;
 rom_download_queue queue(.save_read_request(1'b0),.save_read_ready(),.save_read_quiescent(1'b1),
 .clk_74a(host_clk),.clk_memory(sys_clk),.hard_reset_n(!reset),
  .bridge_wr(bridge_wr),.bridge_endian_little(bridge_endian_little),.bridge_addr(bridge_addr),
  .bridge_wr_data(bridge_wr_data),.download_active(download_active),
  .config_in({1'(PAL),16'b0}),.config_out(image_config),.config_valid(image_config_valid),.write_valid(qvalid),
  .write_ready(qready),.write_en(qen),.write_addr(qaddr),.write_data(qdata),
  .save_valid(save_valid),.save_ready(save_ready),.save_en(save_en),
  .save_addr(save_addr),.save_data(save_data),.save_busy(save_busy),.image_begin(),.source_ready(),
  .image_busy(image_busy),.image_complete(image_complete),.fault(queue_fault));
 wire flush,run_ready,cart_fault,req_ready,rsp_valid,rsp_error,rsp_write;
 wire[7:0]epoch,rsp_tag,rsp_epoch;wire[4:0]rsp_owner;wire[15:0]rsp_data;
 reg req_valid=0,rsp_ready=1;reg[23:0]req_addr=0;reg[7:0]req_tag=0;
 wire cke,cs,ras,cas,we,dqoe;wire[12:0]da;wire[1:0]ba,dqm;wire[15:0]dq;
 wire core_reset,cart_core_reset,host_reset_s;
 audio_core_reset_input core_input(.clk_sys_21_48(sys_clk),.reset(reset),.init_busy(init_busy),
  .config_valid(image_config_valid),.reset_n(host_reset_n),.core_reset(core_reset),.host_reset_s(host_reset_s));
 audio_cart_reset_input cart_input(.core_reset(core_reset),.save_busy(save_busy),
  .ram_clear_busy(ram_clear_busy),.cart_core_reset(cart_core_reset));
 sdram_cart_port #(.CLK_HZ(RATE*5),.ENABLE_READ_CACHE(0)) cart(
  .clk_sys(sys_clk),.clk_sdram(mem_clk),.hard_reset_n(1'b1),.pll_locked(!reset),
  .soft_reset(cart_core_reset),.download_active(image_busy),.download_complete(image_complete),
  .download_fault(queue_fault),.download_valid(qvalid),.download_ready(qready),
  .download_addr(qaddr),.download_data(qdata),.client_flush(flush),.client_flush_ack(1'b1),.client_fault(1'b0),
  .epoch(epoch),.run_ready(run_ready),.host_quiescent(host_quiescent),.fault(cart_fault),
  .req_valid(req_valid),.req_ready(req_ready),.req_addr(req_addr),.req_channel(1'b0),
  .req_write(1'b0),.req_drain(1'b0),.req_wdata(16'b0),.req_wstrb(2'b0),.req_owner(5'd7),.req_tag(req_tag),.req_epoch(epoch),
  .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_data(rsp_data),.rsp_error(rsp_error),.rsp_write(rsp_write),
  .rsp_owner(rsp_owner),.rsp_tag(rsp_tag),.rsp_epoch(rsp_epoch),
  .dram_cke(cke),.dram_cs_n(cs),.dram_ras_n(ras),.dram_cas_n(cas),.dram_we_n(we),
  .dram_addr(da),.dram_ba(ba),.dram_dqm(dqm),.dq_in(16'hcafe),.dq_out(dq),.dq_oe(dqoe));
 reg cart_wait=0;
 audio_core_reset_boundary boundary(.clk_sys(sys_clk),.core_reset(core_reset),
  .cart_download(image_busy),.standard_run_ready(run_ready),.cart_wait(cart_wait),
  .save_busy(save_busy),.ram_clear_busy(ram_clear_busy),.msu_soft_reset(soft_reset));
 wire audio_mclk,audio_lrck,audio_dac;
 sound_i2s #(.CHANNEL_WIDTH(16),.SIGNED_INPUT(1)) i2s(
  .clk_74a(host_clk),.clk_audio(sys_clk),.audio_l(audio_l),.audio_r(audio_r),
  .audio_mclk(audio_mclk),.audio_lrck(audio_lrck),.audio_dac(audio_dac));
 // The existing I2S has FPGA power-up registers, not a reset input. Explicit
 // testbench initialization represents their zero-power-up state in 4-state sim.
 initial begin
  i2s.audio_mclk=0;i2s.audio_lrck=0;i2s.audio_dac=0;i2s.aud_mclk_divider=0;
  i2s.prev_audio_mclk=0;i2s.audio_lrck_cnt=0;i2s.prev_audgen_sclk=0;
  i2s.audgen_sampshift=0;i2s.prev_left=0;i2s.prev_right=0;
 end
 integer refreshes=0,rom_reads=0,lrck_edges=0,sample_ticks=0,watch_clocks=0,last_tick=0;
 reg watching=0;reg[31:0]previous_frame=0;reg expected_step=0;
 reg signed[15:0]expected_audio=255;
 always @(negedge mem_clk)if(cke&&!cs&&!ras&&!cas&&we)refreshes=refreshes+1;
 always @(posedge sys_clk)begin
  if(req_valid&&req_ready)rom_reads=rom_reads+1;
  if(watching)begin
   if(soft_reset || !run_ready || image_busy || cart_fault || queue_fault || dut.pcm_reset)
    $fatal(1,"MEMORY_WAIT_RESET: ordinary ROM activity interrupted PCM lifecycle");
   watch_clocks=watch_clocks+1;
   expected_step=dut.player.sample_ce;
   previous_frame=dut.player_frame;
   if(dut.player.sample_ce)begin
    if(last_tick && watch_clocks-last_tick!=RATE/44100 && watch_clocks-last_tick!=RATE/44100+1)
      $fatal(1,"PCM_CADENCE: bad fractional gap");
    last_tick=watch_clocks;sample_ticks=sample_ticks+1;
   end
   if((last_tick && watch_clocks-last_tick>RATE/44100+1) || (!last_tick && watch_clocks>RATE/44100+1))$fatal(1,"PCM_CADENCE: gated/missing clock tick");
  end
 end
 always @(negedge sys_clk)if(watching)begin
  if(dut.player_frame!==previous_frame+expected_step)$fatal(1,"PCM_FRAME: skipped/repeated consumption");
  if(i2s.audgen_sampdata_s!=={expected_audio,expected_audio})$fatal(1,"I2S_DATA: PCM sample CDC changed during ROM wait");
  if(audio_l!==expected_audio || audio_r!==expected_audio || dut.pcm_underrun_count!=0)
    $fatal(1,"PCM_AUDIO: gap, stale mix or underrun during ROM wait");
 end
 always @(posedge audio_lrck)if(watching)lrck_edges=lrck_edges+1;
 task automatic core_read(input[23:0]address,input bit hold_response);
 begin
  @(negedge sys_clk);req_addr=address;req_tag=req_tag+1;req_valid=1;rsp_ready=!hold_response;
  do @(posedge sys_clk);while(!req_ready);
  @(negedge sys_clk);req_valid=0;
  wait(rsp_valid);if(rsp_error)$fatal(1,"ROM engine error");
 end endtask
 task automatic bootstrap;
 begin
  rom_job=rom_job+1;wait(rom_done==rom_job);
  @(negedge host_clk);init_req=1;@(negedge host_clk);init_req=0;
  wait(msu_enable && run_ready && !soft_reset);
 end endtask
 integer data_seeks=0;
 // Concurrent ordinary MSU file-cache activity shares the actual APF host with
 // PCM refills. All packets still bypass the ROM region-1 download queue.
 initial begin: data_load
  forever begin
   wait(watching && dut.player_frame[6:0]==0);
   @(negedge sys_clk);data_addr=dut.player_frame[7] ? 32'd4219 : 32'd123;data_seek=1;
   wait(data_ack || !watching || reset);
   @(negedge sys_clk);data_seek=0;
   repeat(3)@(negedge sys_clk);
   if(watching && data!==8'd123)$fatal(1,"MSU_DATA: concurrent file refill corrupted");
   data_seeks=data_seeks+1;
   wait(!watching || dut.player_frame[6:0]!=0);
  end
 end
 // Prove that the old accepted APF operation completes through the real
 // host and CDC, and every stale word is discarded under the drain reset.
 always @(posedge host_clk)begin
  // APF done is a retained result semaphore; count its assertion edge, not
  // every clock while it remains high awaiting the next command.
  previous_apf_done<=target_dataslot_done;
  if(drain_monitor)begin
   if(target_dataslot_done && !previous_apf_done)begin
    if(apf_pcm_operation)drained_apf_done=drained_apf_done+1;
    else drained_other_apf_done=drained_other_apf_done+1;
   end
   if(dut.pcm_done)drained_host_done=drained_host_done+1;
  end
 end
 always @(posedge sys_clk)begin
  if(save_en)begin
   if(save_addr!==17'(save_words*2) || save_data!==(save_words==0?16'hab89:16'hefcd))
     $fatal(1,"SAVE_PAYLOAD: queue accepted wrong generated word");
   save_words=save_words+1;
  end
  if(drain_monitor)begin
   if(dut.track_load)$fatal(1,"LIFECYCLE_STALE_LOAD: old transport allowed a track load");
   if(dut.pcm_resp_valid)begin
    if({dut.pcm_reset,dut.pcm_drain,dut.player.loaded}!==3'b110 || audio_l!==0 || audio_r!==0)
      $fatal(1,"LIFECYCLE_STALE_PCM: old word survived drain reset");
    // pcm_reset is the production OR-ed resp_ready, so every valid is accepted.
    drained_words=drained_words+1;
   end
   if(dut.pcm_resp_done)begin
    if(drained_words!=expected_drain_words || drained_apf_done!=1 || drained_host_done!=1)
      $fatal(1,"LIFECYCLE_DRAIN: words=%0d expected=%0d APF=%0d host=%0d",drained_words,expected_drain_words,drained_apf_done,drained_host_done);
    drained_completions=drained_completions+1;drain_monitor=0;
   end
  end
 end
 task automatic lifecycle_scenario(input integer kind,input[15:0]next_track);
 integer job,first_frame,saves_before;
 reg[7:0]epoch_before;
 begin
  job=injected_count+1;saves_before=save_words;epoch_before=epoch;
  release_lifecycle=0;release_payload=0;inject_kind=kind;
  wait(injected_count==job);wait(soft_reset);
  repeat(10)@(negedge sys_clk);
  if({dut.pcm_reset,dut.pcm_drain,dut.pcm_idle,dut.player.loaded,msu_enable,init_busy,
      image_config_valid,image_busy,queue_fault,cart_fault,run_ready}!==11'b11001010000 || audio_l!==0 || audio_r!==0)
    $fatal(1,"LIFECYCLE_HOLD: kind=%0d did not mute/drain while retaining discovery and ROM",kind);
  if(kind==1 && {host_reset_s,host_reset_n,core_reset}!==3'b101)$fatal(1,"HOST_RESET: actual APF0010/guard path did not assert");
  if(kind==2 && ({save_busy,save_valid}!==2'b11 || save_words!=saves_before))$fatal(1,"SAVE_BUSY: real queued write not held");
  if(kind==3 && ram_clear_busy!==1'b1)$fatal(1,"CLEAR_BUSY: lifecycle input not held");
  release_lifecycle=1;wait(released_count==job);wait(!soft_reset);
  repeat(4)@(negedge sys_clk);
  if({dut.pcm_drain,dut.pcm_reset,dut.pcm_idle,active_pcm_payload,run_ready}!==5'b11011 ||
     (^epoch)===1'bx || epoch==epoch_before)
    $fatal(1,"LIFECYCLE_EARLY_RELEASE: accepted old PCM not retained past short reset kind=%0d",kind);
  if(kind==1 && {host_reset_s,host_reset_n,core_reset}!==3'b010)$fatal(1,"HOST_RESET: actual APF0011/guard path did not release");
  if(kind==2 && (save_busy!==1'b0 || save_words!=saves_before+2))$fatal(1,"SAVE_BUSY: ordered generated halfwords not drained");
  release_payload=1;wait(drained_completions==1);wait(dut.pcm_idle&&!dut.pcm_reset);
  start_track(next_track);audio_playing=1;
  expected_audio=next_track==1 ? 16'sd255 : 16'sd510;
  wait(audio_l==expected_audio && audio_r==expected_audio && i2s.audgen_sampdata_s=={expected_audio,expected_audio});
  first_frame=dut.player_frame;watch_clocks=0;last_tick=0;
  @(negedge sys_clk);#1;watching=1;
  wait(dut.player_frame>=first_frame+64);
  @(negedge sys_clk);#1;watching=0;
  $display("PASS expected interruption: kind=%0d (1=APF host reset 2=queued Save 3=modeled clear busy) accepted PCM drained APF=%0d host=%0d words=%0d otherAPF=%0d; recovered track=%0d frames=64 PAL=%0d",kind,drained_apf_done,drained_host_done,drained_words,drained_other_apf_done,next_track,PAL);
 end endtask
 integer frame_start,ref_start,pcm_start,frame_after,tick_start;
 initial begin
  repeat(8)@(negedge host_clk);reset=0;repeat(12)@(negedge host_clk);bootstrap();$display("STAGE initial ROM and MSU bootstrap ready PAL=%0d",PAL);
  start_track(1);audio_playing=1;wait(audio_l==16'sd255);
  repeat(4)@(negedge sys_clk);
  $display("STAGE PCM playing PAL=%0d frame=%0d",PAL,dut.player_frame);
  frame_start=dut.player_frame;ref_start=refreshes;pcm_start=pcm_read_count;
  // Hold an accepted ROM response for 1536 PCM frames. This deliberately
  // exceeds several PCM block refills and thousands of real SDRAM refreshes.
  core_read(24'h008000,1);cart_wait=1;
  @(negedge sys_clk);#1;watching=1;
  wait(dut.player_frame>=frame_start+1536);
  @(negedge sys_clk);#1;watching=0;cart_wait=0;rsp_ready=1;
  if(refreshes-ref_start<100 || pcm_read_count-pcm_start<3 || sample_ticks<1535 || lrck_edges<1000 || data_seeks<8)
    $fatal(1,"INSUFFICIENT_LOAD: refresh=%0d host refills=%0d samples=%0d lrck=%0d",refreshes-ref_start,pcm_read_count-pcm_start,sample_ticks,lrck_edges);
  $display("PASS continuity PAL=%0d: ROM response held, refreshes=%0d PCMrefills=%0d PCMframes=%0d I2Sframes=%0d DATAseeks=%0d",PAL,refreshes-ref_start,pcm_read_count-pcm_start,sample_ticks,lrck_edges,data_seeks);
  repeat(4)@(negedge sys_clk);
  // Exercise many cold physical reads after the held result drains.
  watch_clocks=0;last_tick=0;@(negedge sys_clk);#1;watching=1;
  for(integer n=0;n<128;n=n+1)begin core_read(24'h10000+n*2,0);repeat(4)@(negedge sys_clk);end
  @(negedge sys_clk);#1;watching=0;
  if(rom_reads!=129 || dut.pcm_underrun_count!=0)$fatal(1,"cold traffic affected PCM");
  lifecycle_scenario(1,2);
  lifecycle_scenario(2,1);
  lifecycle_scenario(3,2);
  // A new ROM image is intentionally a lifecycle reset, not continuous audio.
  rom_job=rom_job+1;wait(image_busy);wait(soft_reset);
  repeat(10)@(negedge sys_clk);
  if(dut.player.loaded || audio_l!==0 || audio_r!==0)$fatal(1,"DOWNLOAD_RESET: old PCM survived image replacement");
  audio_playing=0;wait(rom_done==rom_job);wait(run_ready&&!soft_reset);
  start_track(2);audio_playing=1;wait(audio_l==16'sd510);
  if(dut.pcm_underrun_count!=0)$fatal(1,"post-download recovery underrun");
  $display("PASS expected interruption: download image_busy stopped PCM, old transport drained, new track recovered");
  // Logical PLL-loss reset with clocks still supplied by the testbench. Real
  // PLL clock disappearance/relock and analogue output behavior are unproven.
  wait(!active_pcm_payload);@(negedge sys_clk);reset=1;audio_playing=0;
  repeat(12)@(negedge sys_clk);
  if(dut.player.loaded || msu_enable || !init_busy || dut.player.sample_ce || audio_l!==0 || audio_r!==0)
    $fatal(1,"PLL_RESET: PCM lifecycle did not enter reset");
  repeat(40)@(negedge host_clk);reset=0;repeat(12)@(negedge host_clk);bootstrap();$display("STAGE initial ROM and MSU bootstrap ready PAL=%0d",PAL);
  start_track(1);audio_playing=1;wait(audio_l==16'sd255);
  $display("PASS expected interruption: logical PLL reset cleared PCM, required ROM/bootstrap/track remount, recovered PAL=%0d",PAL);
  $finish;
 end
 initial begin repeat(3000000)@(posedge sys_clk);$fatal(1,"audio memory continuity timeout");end

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
