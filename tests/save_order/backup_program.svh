 // Command-level source admission and actual readback, after the common
 // production queue/cart/RAM/reader harness above.
 wire host_reset_n,host_reset_hold,read_request,read_ack,source_ready,fence_ready,fence_request,backup_ready;
 wire[15:0]read_request_id;wire[31:0]cmd_rdata;
 save_backup_admission_boundary admission(.clk_74a(src),.clk_sys_21_48(sys),.pll_core_locked(locked),
 .reset_n(host_reset_n),.dataslot_requestread(read_request),.dataslot_requestread_id(read_request_id),
 .queue_source_ready(source_ready),.queue_save_read_ready(fence_ready),.queue_save_read_request(fence_request),
 .dataslot_requestread_ack(read_ack),.host_reset_s(host_reset_hold));
 core_bridge_cmd cb(.clk(src),.reset_n(host_reset_n),.bridge_endian_little(little),.bridge_addr(addr),.bridge_rd(bridge_rd),.bridge_rd_data(cmd_rdata),.bridge_wr(wr),.bridge_wr_data(data),
 .status_boot_done(locked),.status_setup_done(1'b0),.status_running(host_reset_n),.dataslot_requestread(read_request),.dataslot_requestread_id(read_request_id),
 .dataslot_requestread_ack(read_ack),.dataslot_requestread_ok(1'b1),.dataslot_requestwrite_ack(1'b1),.dataslot_requestwrite_ok(1'b1),
 .savestate_supported(1'b0),.savestate_addr(32'd0),.savestate_size(32'd0),.savestate_maxloadsize(32'd0),
 .savestate_start_ack(1'b0),.savestate_start_busy(1'b0),.savestate_start_ok(1'b0),.savestate_start_err(1'b0),
 .savestate_load_ack(1'b0),.savestate_load_busy(1'b0),.savestate_load_ok(1'b0),.savestate_load_err(1'b0),
 .target_dataslot_read(1'b0),.target_dataslot_write(1'b0),.target_dataslot_getfile(1'b0),.target_dataslot_openfile(1'b0),
 .target_dataslot_id(16'd0),.target_dataslot_slotoffset(32'd0),.target_dataslot_bridgeaddr(32'd0),.target_dataslot_length(32'd0),.target_buffer_param_struct(32'd0),.target_buffer_resp_struct(32'd0),
 .datatable_addr(10'd0),.datatable_wren(1'b0),.datatable_data(32'd0),.datatable_q());
 initial begin cb.hstate=0;cb.tstate=0;cb.host_cmd_start=0;end
 function automatic[31:0]swap(input[31:0]x);swap={x[7:0],x[15:8],x[23:16],x[31:24]};endfunction
 integer fence_count=0,slot10_acks=0;reg backup_interval=0;
 always @(posedge src)begin
 if(fence_request)begin
 if(!read_request||read_request_id!=10||!source_ready)$fatal(1,"FENCE_WRONG_REQUEST_ID_OR_ARM");
 fence_count=fence_count+1;
 end
 if(read_request&&read_ack&&read_request_id==10)begin
 if(!fence_ready||asv!=es||clear_busy||save_busy)$fatal(1,"BACKUP_ACK_BEFORE_ORDERED_DRAIN save=%0d/%0d",asv,es);
 slot10_acks=slot10_acks+1;
 end
 end
 always @(posedge sys)if(backup_interval&&locked)begin
 if(!host_reset_hold||run)$fatal(1,"CPU_REVIVED_DURING_BACKUP");
 end
 task command(input[15:0]c,input[15:0]slot);
 integer n,fc;
 begin fc=fence_count;
 if(c==16'h0080||c==16'h0082)packet(32'hf8000020,swap({16'b0,slot}),150,1);
 if(c==16'h0082)packet(32'hf8000024,swap(32'd8192),150,1);
 packet(32'hf8000000,swap({16'h434d,c}),150,1);
 n=0;while(cb.host_0[31:16]!==16'h4f4b&&n<4000000)begin @(negedge src);n=n+1;end
 if(cb.host_0!==32'h4f4b0000)$fatal(1,"COMMAND_RESULT cmd=%h slot=%0d got=%h",c,slot,cb.host_0);
 if(c==16'h0080&&slot!=10&&fence_count!=fc)$fatal(1,"NON_SAVE_SLOT_FENCED slot=%0d",slot);
 if(c==16'h0080&&slot==10&&(fence_count!=fc+1||asv!=es||clear_busy))$fatal(1,"SLOT10_ADMISSION");
 $display("PASS HOST_COMMAND cmd=%h slot=%0d ns=%0.3f save=%0d/%0d fences=%0d",c,slot,$realtime,asv,es,fence_count);$fflush();
 end endtask
 task read_backup_word(input[16:0]a,input[31:0]wanted);
 begin
 use_reader=1;@(negedge src);addr=32'h20000000+a;bridge_rd=1;little=1;@(negedge src);bridge_rd=0;
 repeat(250)@(negedge src);
 if(bridge_rdata!==wanted)$fatal(1,"BACKUP_APF_DATA addr=%h got=%h wanted=%h",a,bridge_rdata,wanted);
 use_reader=0;$display("PASS BACKUP_WORD addr=%h data=%h ns=%0.3f",a,bridge_rdata,$realtime);$fflush();
 end endtask
 integer i,before_fences;reg[31:0]v;
 initial begin
 clear_oracle();#112;reset_epoch(0);repeat(30)@(negedge src);
 command(16'h0082,0);begin_segment(17'h12345,75);packet(32'h10000000,32'h12345678,75,1);#1000000;
 for(i=0;i<128;i=i+1)packet(32'h10000004+i*4,32'habc00000+i,2,1);
 command(16'h008f,0);end_segment(75);
 begin_segment(17'h0eeee,75);command(16'h0082,10);packet(32'h20000000,32'h44332211,75,1);command(16'h008f,0);end_segment(75);
 command(16'h0011,0);command(16'h0010,0);backup_interval=1;
 // Previous ID100 must not authorize the first parse cycle of slot10.
 command(16'h0080,100);command(16'h008f,0);command(16'h0080,10);
 read_backup_word(0,32'h44332211);command(16'h008f,0);
 // Old ready remains high. A new slot10 request must acquire a distinct fence
 // while its preceding independent restore is deliberately ownership-stalled.
 flush_ack=0;packet(32'h20000000,32'ha8b7c6d5,75,1);wait(save_valid);before_fences=fence_count;
 fork
 begin command(16'h0080,10);end
 begin wait(fence_count>before_fences);repeat(100)@(negedge sys);flush_ack=1;end
 join
 read_backup_word(0,32'ha8b7c6d5);command(16'h008f,0);
 // Previous ID10 must not turn dynamic MSU slot101 into a Save fence.
 command(16'h0080,101);command(16'h008f,0);
 verify_ram(60);
 if(fence_count!=2||slot10_acks<2)$fatal(1,"BACKUP_COMMAND_COVERAGE fences=%0d acks=%0d",fence_count,slot10_acks);
 backup_interval=0;command(16'h0011,0);repeat(10)@(negedge sys);
 if(host_reset_hold)$fatal(1,"HOST_RESET_DID_NOT_RELEASE");
 $display("PASS UNIFIED_SAVE_CONTENTS PAL=%0d CASE=5 full_ram_checks=%0d command_fences=%0d slot10_acks=%0d",PAL,checks,fence_count,slot10_acks);$finish;
 end
 initial begin #120000000;$fatal(1,"TIMEOUT");end
endmodule
