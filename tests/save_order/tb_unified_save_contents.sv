// SPDX-License-Identifier: MIT
// Candidate integration: real production queue/cart/CDC/engine + extracted MAIN
// initialization/Save credit + full installed Intel BSRAM and FIFO models.
`timescale 1ns/1ps
module tb_unified_save_contents;
 parameter integer PAL=0,CASE=0,BURST=1,PHASE_NS=0;
 localparam real SYS_HALF=500000000.0/(PAL?21281370:21477270);
 reg src=0,sys=0,mem=0;always #6.734 src=~src;initial begin #(PHASE_NS);forever #(SYS_HALF)sys=~sys;end initial begin #(PHASE_NS);forever #(SYS_HALF/5.0)mem=~mem;end
 reg hard_reset_n=0,locked=0,wr=0,little=1,active=0,soft_reset=0,flush_ack=1;
 reg[31:0]addr=0,data=0;reg[16:0]cfg_in=17'h12345,source_cfg=17'h12345;
 always @(posedge src)if(wr&&addr==0)active<=data[0];
 wire valid,en,busy,complete,qfault,ready,config_valid,image_begin,save_busy,save_valid,save_ready,save_en;
 wire[24:0]wa;wire[15:0]wd,save_data;wire[16:0]cfg,save_addr;
 rom_download_queue queue(.clk_74a(src),.clk_memory(sys),.hard_reset_n(hard_reset_n&&locked),
 .bridge_wr(wr),.bridge_endian_little(little),.bridge_addr(addr),.bridge_wr_data(data),.download_active(active),
 .config_in(cfg_in),.config_out(cfg),.config_valid(config_valid),.write_valid(valid),.write_ready(ready),.write_en(en),.write_addr(wa),.write_data(wd),
 .save_valid(save_valid),.save_ready(save_ready),.save_en(save_en),.save_addr(save_addr),.save_data(save_data),.image_begin(image_begin),.save_busy(save_busy),
`ifdef HAS_READ_FENCE
 .save_read_request(1'b0),.save_read_ready(),.save_read_quiescent(1'b1),
`endif
 .image_busy(busy),.image_complete(complete),.fault(qfault));
 wire run,fault,flush,host_quiescent;wire[7:0]epoch;
 wire cke,cs,ras,cas,we,oe;wire[12:0]ma;wire[1:0]ba,dqm;wire[15:0]md;
 reg req_valid=0,req_write=0,req_drain=0;wire req_ready,rsp_valid;
 // Production MAIN's host-busy term must be verified by the source-bound runner.
 sdram_cart_port #(.CLK_HZ(PAL?106406850:107386350)) cart(
 .clk_sys(sys),.clk_sdram(mem),.hard_reset_n(hard_reset_n),.pll_locked(locked),.soft_reset(soft_reset||save_busy||clear_busy),
 .download_active(busy),.download_complete(complete),.download_fault(qfault),.download_valid(valid),.download_ready(ready),
 .download_addr(wa),.download_data(wd),.client_flush(flush),.client_flush_ack(flush_ack),.client_fault(1'b0),.epoch(epoch),.run_ready(run),.host_quiescent(host_quiescent),.fault(fault),
 .req_valid(req_valid),.req_ready(req_ready),.req_addr(24'h600000),.req_channel(1'b1),.req_write(req_write),.req_drain(req_drain),.req_wdata(16'hcafe),.req_wstrb(2'b11),
 .req_owner(5'd3),.req_tag(8'h55),.req_epoch(epoch),.rsp_valid(rsp_valid),.rsp_ready(1'b1),.rsp_data(),.rsp_error(),.rsp_write(),.rsp_owner(),.rsp_tag(),.rsp_epoch(),
 .dram_cke(cke),.dram_cs_n(cs),.dram_ras_n(ras),.dram_cas_n(cas),.dram_we_n(we),.dram_addr(ma),.dram_ba(ba),.dram_dqm(dqm),.dq_in(16'b0),.dq_out(md),.dq_oe(oe));
 reg[16:0]read_addr=0,manual_backup_addr=0;
 reg use_reader=0,bridge_rd=0;wire reader_en;wire[16:0]reader_addr;
 wire[31:0]bridge_rdata;wire[16:0]backup_addr=use_reader?reader_addr:manual_backup_addr;
 save_backup_reader_boundary reader(
 .clk_74a(src),.clk_sys_21_48(sys),.pll_core_locked(locked),.bridge_rd(bridge_rd),.bridge_endian_little(little),.bridge_addr(addr),.bridge_rd_data(bridge_rdata),.read_en(reader_en),.read_addr(reader_addr),.read_data(backup_q));
 wire sd_rd=use_reader&&reader_en;
 integer backup_first_overlap=0,backup_last_samples=0;
wire[7:0]read_q;wire[15:0]backup_q;wire clearing,clear_pending,clear_busy;wire[16:0]clear_addr;wire[15:0]port_b_addr;
 unified_clear_boundary ram(.clk_sys(sys),.pll_locked(locked),.core_reset(soft_reset),.cart_download(busy),.image_begin(image_begin),.save_busy(save_busy),
 .host_quiescent(host_quiescent),.save_valid(save_valid),.save_ready(save_ready),.save_en(save_en),.save_addr(save_addr),.save_data(save_data),
 .qfault(qfault),.sd_rd(sd_rd),.read_addr(read_addr),.backup_addr(backup_addr),.read_q(read_q),.backup_q(backup_q),.port_b_addr(port_b_addr),.clearing(clearing),.clear_pending(clear_pending),.clear_busy(clear_busy),.clear_addr(clear_addr));
 reg[7:0]expected[0:131071];
 reg[16:0]exp_save_addr[0:65535];reg[15:0]exp_save_data[0:65535];
 reg[24:0]exp_rom_addr[0:65535];reg[15:0]exp_rom_data[0:65535];reg[16:0]exp_rom_cfg[0:65535];
 integer source_begins=0,dest_begins=0,es=0,asv=0,er=0,ar=0,pin_rom_writes=0;
 integer checks=0,stalled_save_cycles=0,save_accepts=0,clear_restarts=0,max_fifo_used=0;
 reg allow_fault=0,scoreboard_on=1,was_stalled=0;reg[32:0]held_save;
 reg cfg_accept,begin_seen;reg[16:0]cfg_before;
 function automatic[7:0]pattern(input integer a,input integer seed);pattern=8'(1+(a*37+a/17+seed*43)%251);endfunction
 task clear_oracle;begin for(integer j=0;j<131072;j=j+1)expected[j]=8'hff;end endtask
 task expect_word(input bit sv,input[24:0]a,input[31:0]d,input bit le);
 reg[31:0]v;
 begin v=le?d:{d[7:0],d[15:8],d[23:16],d[31:24]};
 if(sv)begin
 for(integer h=0;h<2;h=h+1)begin exp_save_addr[es]=a+h*2;exp_save_data[es]=h?v[31:16]:v[15:0];es=es+1;end
 for(integer b=0;b<4;b=b+1)expected[a+b]=v[8*b+:8];
 end else begin
 for(integer h=0;h<2;h=h+1)begin exp_rom_addr[er]=a+h*2;exp_rom_data[er]=h?v[31:16]:v[15:0];exp_rom_cfg[er]=source_cfg;er=er+1;end
 end end endtask
 task packet(input[31:0]a,input[31:0]d,input integer period,input bit le);
 begin
 if(a==0&&d[0]&&!active)begin clear_oracle();source_begins=source_begins+1;source_cfg=cfg_in;end
 if(scoreboard_on&&a[31:28]==2)expect_word(1,a[24:0],d,le);
 if(scoreboard_on&&a[31:28]==1)expect_word(0,a[24:0],d,le);
 @(negedge src);wr=1;addr=a;data=d;little=le;@(negedge src);wr=0;repeat(period-2)@(negedge src);
 end endtask
 task begin_segment(input[16:0]c,input integer spacing);
 begin cfg_in=c;packet(0,1,spacing,1);end endtask
 task end_segment(input integer spacing);begin packet(0,0,spacing,1);end endtask
 task save_pattern(input integer first,input integer bytes,input integer seed,input integer spacing);
 reg[31:0]v;
 begin for(integer j=first;j<first+bytes;j=j+4)begin
 v={pattern(j+3,seed),pattern(j+2,seed),pattern(j+1,seed),pattern(j,seed)};
 packet(32'h20000000+j,v,spacing,1);
 end end endtask
 task drain;
 integer n;
 begin n=0;while((save_busy||busy||valid||save_valid||ar!=er||asv!=es)&&!qfault&&!fault&&n<900000)begin @(negedge sys);n=n+1;end
 if(qfault||fault||n>=900000||ar!=er||asv!=es)$fatal(1,"DRAIN qfault=%b cart_fault=%b rom=%0d/%0d save=%0d/%0d",qfault,fault,ar,er,asv,es);
 repeat(20)@(negedge sys);
 end endtask
 task verify_ram(input integer label);
 integer n,bad;reg[7:0]got;string actual_path,expected_path;
 begin
 drain();n=0;while(clear_busy&&n<900000)begin @(negedge sys);n=n+1;end
 if(clear_busy)$fatal(1,"FULL_CLEAR_TIMEOUT label=%0d",label);
 repeat(5)@(negedge sys);bad=0;
 // All 131072 actual Intel RAM bytes, compared with a source-side oracle.
 for(integer j=0;j<131072;j=j+1)begin
 got=ram.bsram.altsyncram_component.m_default.altsyncram_inst.mem_data[j];
 if(got!==expected[j])begin if(bad<16)$display("RAM_BAD label=%0d addr=%0d got=%h expected=%h",label,j,got,expected[j]);bad=bad+1;end
 end
 actual_path=$sformatf("%s/label-%0d-actual.hex",oracle_dir,label);
 expected_path=$sformatf("%s/label-%0d-expected.hex",oracle_dir,label);
 $writememh(actual_path,ram.bsram.altsyncram_component.m_default.altsyncram_inst.mem_data);
 $writememh(expected_path,expected);
 if(bad)$fatal(1,"SAVE_CONTENT label=%0d bad_bytes=%0d",label,bad);
 // Also verify real registered A-port and backup B-port read behavior at
 // boundaries; hierarchical comparison above is not the only readback check.
 for(integer k=0;k<8;k=k+1)begin
 @(negedge sys);read_addr=k==7?17'h1ffff:k*1023;manual_backup_addr=(k==7?17'h1fffe:k*1024);
 repeat(3)@(negedge sys);
 if(read_q!==expected[read_addr]||backup_q!=={expected[backup_addr+1],expected[backup_addr]})$fatal(1,"BACKUP_READ label=%0d a=%h q=%h want=%h b=%h q=%h",label,read_addr,read_q,expected[read_addr],backup_addr,backup_q);
 end
 checks=checks+1;$display("PASS FULL_RAM label=%0d bytes=131072 source_begins=%0d dest_begins=%0d accepted_save_words=%0d",label,source_begins,dest_begins,asv);$fflush();
 end endtask
 task reset_epoch(input bit pll_only);
 begin
 @(negedge src);locked=0;if(!pll_only)hard_reset_n=0;active=0;wr=0;soft_reset=0;flush_ack=1;req_valid=0;req_write=0;req_drain=0;
 repeat(12)@(negedge src);es=0;asv=0;er=0;ar=0;pin_rom_writes=0;source_begins=0;dest_begins=0;scoreboard_on=1;allow_fault=0;was_stalled=0;
 hard_reset_n=1;locked=1;repeat(12)@(negedge src);
 end endtask
 always @(posedge sys) begin
 cfg_before=cfg;cfg_accept=en;begin_seen=image_begin;
 if(hard_reset_n&&locked)begin
 if(!allow_fault&&(qfault||fault))$fatal(1,"TRANSPORT_FAULT");
 if(image_begin)dest_begins=dest_begins+1;
 if(sd_rd&&save_en)$fatal(1,"BACKUP_INTERVAL_WRITE");
 if(use_reader&&reader.data_unloader.data_read_state==reader.data_unloader.READ_MEM_START&&save_en&&!reader_en)backup_first_overlap=backup_first_overlap+1;
 if(use_reader&&reader.data_unloader.data_read_state==reader.data_unloader.READ_MEM_COMPLETE)begin
 backup_last_samples=backup_last_samples+1;
 if(!reader_en||save_en)$fatal(1,"BACKUP_LAST_SAMPLE_WRITE");
 end
 if(was_stalled&&!qfault&&(!save_valid||{save_addr,save_data}!==held_save))$fatal(1,"SAVE_STABLE");
 was_stalled=save_valid&&!save_ready&&!qfault;held_save={save_addr,save_data};
 if(save_valid&&!save_ready)stalled_save_cycles=stalled_save_cycles+1;
 if(en&&scoreboard_on)begin
 if(ar>=er||wa!==exp_rom_addr[ar]||wd!==exp_rom_data[ar])$fatal(1,"ROM_ORDER word=%0d",ar);
 ar=ar+1;
 end
 if(save_en)begin
 if(!host_quiescent||image_begin||clear_pending)$fatal(1,"SAVE_BEFORE_QUIESCENCE_OR_BEGIN");
 if(clearing&&clear_addr<=({save_addr[16:1],1'b1}))$fatal(1,"SAVE_AHEAD_CLEAR addr=%h frontier=%h",save_addr,clear_addr);
 if(port_b_addr!==save_addr[16:1])$fatal(1,"WRITE_BACKUP_MUX");
 if(scoreboard_on)begin
 if(asv>=es||save_addr!==exp_save_addr[asv]||save_data!==exp_save_data[asv])$fatal(1,"SAVE_ORDER word=%0d addr=%h data=%h",asv,save_addr,save_data);
 asv=asv+1;
 end
 save_accepts=save_accepts+1;
 end else if(port_b_addr!==backup_addr[16:1])$fatal(1,"BACKUP_ADDRESS_MUX");
 if(qfault&&(save_en||en||config_valid||complete))$fatal(1,"FAULT_NOT_CLOSED");
 end else was_stalled=0;
 #1;
 if(hard_reset_n&&locked&&!qfault&&scoreboard_on)begin
 if(begin_seen&&((!clearing&&!clear_pending)||clear_addr!==0))$fatal(1,"BEGIN_FIRST_EDGE_NOT_RESTARTED");
 if(cfg_accept&&(!config_valid||cfg!==exp_rom_cfg[ar-1]))$fatal(1,"CONFIG_ORDER");
 if(!cfg_accept&&cfg!==cfg_before)$fatal(1,"SAVE_CHANGED_CONFIG");
 end
 end
 always @(posedge src)if(hard_reset_n&&locked&&queue.transport_fifo.wrusedw>max_fifo_used)max_fifo_used=queue.transport_fifo.wrusedw;
 always @(negedge mem)if(hard_reset_n&&locked&&cke&&!cs&&ras&&!cas&&!we&&ba[1]==0)pin_rom_writes=pin_rom_writes+1;
 string oracle_dir=".";
 initial if(!$value$plusargs("ORACLE_DIR=%s",oracle_dir))oracle_dir=".";
 integer i,before_begins,before_saves;reg[31:0]v;
 initial begin
 clear_oracle();#112;reset_epoch(0);
 if(CASE==0||CASE==1)begin
 begin_segment(17'h12345,75);packet(32'h10000000,32'h12345678,75,1);
 #30000000;if(clearing||clear_pending)$fatal(1,"INITIAL_FULL_CLEAR_NOT_FINISHED");
 for(i=0;i<128;i=i+1)packet(32'h10000004+i*4,32'habc00000+i,BURST?2:75,1);
 end_segment(75);
 if(CASE==1)begin begin_segment(17'h12345,75);packet(32'h10000000,32'h87654321,75,1);end_segment(75);end
 begin_segment(17'h0eeee,75);save_pattern(0,8192,0,75);end_segment(75);
 verify_ram(CASE);
 if(!config_valid||cfg!==17'h12345||!complete||pin_rom_writes!=er||dest_begins!=source_begins)$fatal(1,"FINAL_LIFECYCLE");
 end else if(CASE==2)begin
 // Empty initial Save clears but cannot validate a ROM.
 begin_segment(17'h1aaaa,8);end_segment(8);verify_ram(20);
 if(config_valid||complete||run)$fatal(1,"EMPTY_VALIDATED_ROM");
 // Save A restored while its 128KiB clear remains active; same-config B must
 // restart initialization, then a short Save B must leave every tail byte FF.
 begin_segment(17'h12345,8);packet(32'h10000000,32'h11223344,8,1);end_segment(8);
 begin_segment(17'h0eeee,8);save_pattern(0,256,1,75);end_segment(8);drain();
 if(!clearing)$fatal(1,"RAPID_REMOUNT_MISSING_ACTIVE_CLEAR");
 begin_segment(17'h12345,8);packet(32'h10000000,32'h11223344,8,1);end_segment(8);
 begin_segment(17'h0dddd,8);save_pattern(0,64,2,75);end_segment(8);drain();
 // Independent region2 write: no BEGIN/no clear/no config change. Stall it
 // behind old ownership while toggling unrelated backup-read addresses.
 before_begins=dest_begins;flush_ack=0;save_pattern(1024,64,3,75);wait(save_valid);before_saves=asv;
 repeat(100)begin @(negedge sys);manual_backup_addr=manual_backup_addr^17'h1fffe;if(save_en||host_quiescent)$fatal(1,"UNQUIESCED_SAVE");end
 if(asv!=before_saves)$fatal(1,"STALLED_SAVE_LOST");
 flush_ack=1;verify_ram(21);
 if(dest_begins!=before_begins||cfg!==17'h12345||!config_valid)$fatal(1,"INDEPENDENT_SAVE_LIFECYCLE");
 // Real APF unloader, with Save ready released on its first READ_MEM_START
 // edge. Its final sample edge must still see read_en high and writes stopped.
 flush_ack=0;save_pattern(2048,64,7,75);wait(save_valid);use_reader=1;
 @(negedge src);addr=32'h20000400;little=1;bridge_rd=1;@(negedge src);bridge_rd=0;
 wait(reader.data_unloader.data_read_state==reader.data_unloader.READ_MEM_START);@(negedge sys);flush_ack=1;
 repeat(200)@(negedge src);
 if(bridge_rdata!=={expected[1027],expected[1026],expected[1025],expected[1024]})$fatal(1,"BACKUP_APF_DATA got=%h",bridge_rdata);
 if(backup_first_overlap<1||backup_last_samples<2)$fatal(1,"BACKUP_EDGE_COVERAGE first=%0d last=%0d",backup_first_overlap,backup_last_samples);
 use_reader=0;verify_ram(23);
 // Empty Save after a valid image: every BEGIN intentionally requests a new
 // clear in this selected design; missing Save produces FF, not an old tail.
 begin_segment(17'h16345,8);packet(32'h10000000,32'h55667788,75,1);end_segment(8);
 begin_segment(17'h07777,8);end_segment(8);
 // Changed RAM_SIZE is committed with the ROM. The physical Save port still
 // accepts the final128KiB word; live source config must not alias/mask it.
 cfg_in=17'h05555;save_pattern(131068,4,8,75);verify_ram(22);
 if(cfg!==17'h16345||!complete)$fatal(1,"EMPTY_SAVE_CONFIG");
 end else if(CASE==3)begin
 // Simultaneous BEGIN+ROM packet on the queue API, followed by END.
 @(negedge src);source_cfg=17'h12345;cfg_in=source_cfg;clear_oracle();source_begins=source_begins+1;active=1;wr=1;addr=32'h10000000;data=32'h12345678;little=1;expect_word(0,0,data,1);
 @(negedge src);wr=0;repeat(75)@(negedge src);end_segment(8);drain();
 // Same-token BEGIN+Save, then END+Save, must fence the first clear restart.
 @(negedge src);cfg_in=17'h05555;source_cfg=cfg_in;clear_oracle();source_begins=source_begins+1;active=1;wr=1;addr=32'h20000000;data=32'h44332211;expect_word(1,0,data,1);
 @(negedge src);wr=0;repeat(75)@(negedge src);
 @(negedge src);active=0;wr=1;addr=32'h20000004;data=32'h88776655;expect_word(1,4,data,1);
 @(negedge src);wr=0;drain();
 // A soft reset while Save is held must not discard its words/config.
 flush_ack=0;soft_reset=1;save_pattern(32,64,4,75);wait(save_valid);repeat(30)@(negedge sys);flush_ack=1;drain();soft_reset=0;
 if(cfg!==17'h12345||!config_valid)$fatal(1,"SOFT_RESET_CONFIG");
 // A held Save cannot replay after logical PLL loss. The next mount is fresh.
 flush_ack=0;save_pattern(128,64,5,75);wait(save_valid);reset_epoch(1);repeat(40)@(negedge sys);
 if(save_en||save_valid||config_valid||complete||run)$fatal(1,"PLL_REPLAY");
 // Invalid entire Save span: neither halfword may write or alias byte zero.
 scoreboard_on=0;allow_fault=1;before_saves=save_accepts;packet(32'h2001fffe,32'hdeadbeef,75,1);repeat(40)@(negedge sys);
 if(!qfault||save_accepts!=before_saves)$fatal(1,"SAVE_SPAN");
 reset_epoch(0);scoreboard_on=0;allow_fault=1;flush_ack=0;before_saves=save_accepts;
 for(i=0;i<540;i=i+1)packet(32'h20000000+i*4,i,2,1);
 repeat(40)@(negedge sys);if(!qfault||save_accepts!=before_saves)$fatal(1,"SAVE_OVERFLOW");
 begin_segment(17'h11111,8);end_segment(8);repeat(40)@(negedge sys);if(!qfault)$fatal(1,"FAULT_REVIVED_BY_EMPTY");
 reset_epoch(0);begin_segment(17'h12345,8);packet(32'h10000000,32'habcdef12,75,0);end_segment(8);
 begin_segment(17'h0eeee,8);save_pattern(0,128,6,75);end_segment(8);
 verify_ram(30);if(cfg!==17'h12345||!complete)$fatal(1,"RESET_RECOVERY");
 end else if(CASE==4)begin
 // Short initial gaps and narrow source low interval are intentional. This
 // is a frontier/phase probe, not an assertion that a full clear has finished.
 begin_segment(17'h12345,2);packet(32'h10000000,32'h12345678,2,1);end_segment(2);
 begin_segment(17'h1aaaa,2);save_pattern(0,256,9,75);end_segment(2);drain();#100000;
 if(!clearing||clear_addr<256||dest_begins!=2)$fatal(1,"PHASE_COVERAGE");
 for(i=0;i<256;i=i+1)if(ram.bsram.altsyncram_component.m_default.altsyncram_inst.mem_data[i]!==expected[i])$fatal(1,"PHASE_CONTENT byte=%0d",i);
 $display("PASS PHASE_FRONTIER PAL=%0d phase_ns=%0d bytes=256",PAL,PHASE_NS);
 end
 $display("PASS UNIFIED_SAVE_CONTENTS PAL=%0d CASE=%0d BURST=%0d full_ram_checks=%0d save_accepts=%0d stalled_save_sys=%0d max_fifo=%0d",PAL,CASE,BURST,checks,save_accepts,stalled_save_cycles,max_fifo_used);$finish;
 end
 initial begin #220000000;$fatal(1,"TIMEOUT");end
endmodule
