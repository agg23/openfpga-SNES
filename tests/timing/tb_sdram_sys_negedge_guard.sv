`timescale 1ns/1ps
// The controllers are real RTL. Only the vendor DDR clock output primitive is
// modeled; this checks cycle/edge behavior, not board-level SDRAM electrical timing.
module altddio_out #(
 parameter extend_oe_disable="OFF", intended_device_family="Cyclone V",
 invert_output="OFF", lpm_hint="UNUSED", lpm_type="altddio_out",
 oe_reg="UNREGISTERED", power_up_high="OFF", width=1
)(input [width-1:0] datain_h,datain_l,input outclock,aclr,aset,oe,outclocken,sclr,sset,
 output [width-1:0] dataout);
 assign dataout=outclock?datain_h:datain_l;
endmodule


module tb;
 initial begin #2000000; $fatal(1,"watchdog"); end
 reg clk=0,sysclk=0,run_clocks=1;
 integer osc_phase=0;
 // One oscillator fixes the locked 4:1 relationship. Pausing it models the
 // absence of useful PLL clocks, never an analog unlocked waveform.
 initial forever begin
  #5;
  if(run_clocks) begin
   clk=~clk;
   if(clk) begin
    if(osc_phase==0)sysclk=1;
    if(osc_phase==2)sysclk=0;
    osc_phase=(osc_phase+1)%4;
   end
  end
 end
 reg [23:0] addr=24'h100;
 reg cpu_read=0, cart_download=0, core_reset=0,word_mode=1;
 reg [15:0] memory_word=16'h1234;
 reg guard_enable=0;
 wire config_write;
 reg host_clk=0; always #6.5 host_clk=~host_clk;
 reg bridge_wr=0;
 reg [31:0] bridge_addr=0;
 pocket_sdram_config_event config_event(.clk_74a(host_clk),.bridge_wr(bridge_wr),
  .bridge_addr(bridge_addr),.cart_config_write(config_write));
 reg [1:0] div=0;
 reg RFSH=0;
 reg legacy_reset_n=1;
 wire ready_mem,guarded_reset_n;
 wire actual_reset_n=guard_enable ? guarded_reset_n:legacy_reset_n;
 wire [15:0] dq,q;
 wire rd=~cart_download & (actual_reset_n ? cpu_read:RFSH);
 wire [12:0] a; wire [1:0] ba;
 wire dqml,dqmh,ncs,nwe,nras,ncas,sclk,cke;
 assign dq=(!nwe&&!ncas)?16'hzzzz:memory_word;
 sdram dut(.clk(clk),.sys_clk(sysclk),.initialized(),.init(1'b0),.addr0(addr),.din0(16'b0),.dout0(q),.wr0(1'b0),.rd0(rd),.word0(word_mode),
 .addr1(24'b0),.din1(16'b0),.dout1(),.wr1(1'b0),.rd1(1'b0),.rfs1(1'b0),.word1(1'b0),
 .sni_addr(25'b0),.sni_din(16'b0),.sni_dout(),.sni_wr_req(1'b0),.sni_rd_req(1'b0),.sni_word(1'b0),.sni_ready(),
 .SDRAM_DQ(dq),.SDRAM_A(a),.SDRAM_DQML(dqml),.SDRAM_DQMH(dqmh),.SDRAM_BA(ba),.SDRAM_nCS(ncs),.SDRAM_nWE(nwe),.SDRAM_nRAS(nras),.SDRAM_nCAS(ncas),.SDRAM_CLK(sclk),.SDRAM_CKE(cke));
 wire async_reset=core_reset|cart_download|config_write;
 pocket_sdram_lifecycle_guard lifecycle(.mem_clk(clk),.sys_clk(sysclk),
  .reset_request(async_reset),.sdram_initialized(dut.initialized),
  .reset_n(guarded_reset_n),.memory_ready(ready_mem));
 always @(posedge sysclk) begin
  div<=div+1'b1;RFSH<=!div;
  if(div==2) legacy_reset_n<=~async_reset;
 end
 wire early=dut.data_read&&!dut.data_bank[1]&&!dut.data_rfs&&!dut.data_sni;
 wire [15:0] sys_q,candidate_dq;
 assign candidate_dq=dq;
 sdram #(.POCKET_SYS_CAPTURE(1)) candidate(.clk(clk),.sys_clk(sysclk),.initialized(),.init(1'b0),.addr0(addr),.din0(16'b0),.dout0(sys_q),.wr0(1'b0),.rd0(rd),.word0(word_mode),
 .addr1(24'b0),.din1(16'b0),.dout1(),.wr1(1'b0),.rd1(1'b0),.rfs1(1'b0),.word1(1'b0),
 .sni_addr(25'b0),.sni_din(16'b0),.sni_dout(),.sni_wr_req(1'b0),.sni_rd_req(1'b0),.sni_word(1'b0),.sni_ready(),
 .SDRAM_DQ(candidate_dq),.SDRAM_A(),.SDRAM_DQML(),.SDRAM_DQMH(),.SDRAM_BA(),.SDRAM_nCS(),.SDRAM_nWE(),.SDRAM_nRAS(),.SDRAM_nCAS(),.SDRAM_CLK(),.SDRAM_CKE());
 integer cycle=-1,normal_checks=0,bad_live=0,nonphase_reset=0,captures=0;
 integer earliest_bad,cache_captures;
 reg [15:0] expected_cached;
 bit checking=0,raw_counterexample=0;
 always @(posedge clk) begin
  cycle=cycle+1;
  if(early) begin
   captures++;
   if(cycle%4!=2 && !actual_reset_n) nonphase_reset++;
   if(raw_counterexample) $display("capture cycle=%0d phase=%0d q_new=%h reset_n=%b",cycle,cycle%4,dq,actual_reset_n);
  end
 end
 always @(posedge sysclk) if(!dut.init_done && guarded_reset_n) $fatal(1,"released before SDRAM init");
 always @(posedge sysclk) if(checking&&actual_reset_n) begin
  normal_checks++;
  if(q!==sys_q) begin
   bad_live++;
   if(guard_enable) $fatal(1,"guard live mismatch cycle=%0d mem=%h sys=%h",cycle,q,sys_q);
   else $display("EXPECTED UNGUARDED MISMATCH cycle=%0d mem=%h sys=%h RESET_N=%b",cycle,q,sys_q,actual_reset_n);
  end
 end
 always @(negedge clk) begin
  if({candidate.SDRAM_A,candidate.SDRAM_BA,candidate.SDRAM_nRAS,candidate.SDRAM_nCAS,candidate.SDRAM_nWE,candidate.dout_buf[0]}
     !== {dut.SDRAM_A,dut.SDRAM_BA,dut.SDRAM_nRAS,dut.SDRAM_nCAS,dut.SDRAM_nWE,dut.dout_buf[0]})
   $fatal(1,"controller command/data changed");
 end
 task tick;begin @(posedge clk);#1;end endtask
 task nextphase0;begin tick();while(cycle%4!=0)tick();end endtask
 initial begin
  // Even the very first short host pulse is observed before memory init.
  #2;cart_download=1;#13;
  if(guarded_reset_n)$fatal(1,"initial short pulse missed");
  cart_download=0;
  repeat(520)tick();
  if(!dut.init_done)$fatal(1,"init missing");
  // Establish old q, then launch a new normal request at M0.
  nextphase0();cpu_read=1;repeat(8)tick();cpu_read=0;repeat(8)tick();
  nextphase0();addr=24'h200;memory_word=16'h5678;cpu_read=1;
  checking=1;raw_counterexample=1;
  // 13 ns host pulse straddles M1 and is invisible to every sys rising edge.
  #1;cart_download=1;#13;cart_download=0;
  repeat(12)tick();cpu_read=0;checking=0;raw_counterexample=0;
  if(bad_live!=1)$fatal(1,"expected exactly one raw mismatch, got %0d",bad_live);
  $display("PASS exact raw-host counterexample detected");
  // Earliest SA1/turbo-style two-sys-cycle consumption, including repeated
  // requests. No behavioral CPU is substituted: compare at every live edge.
  checking=1;earliest_bad=bad_live;nextphase0();
  for(integer t=0;t<256;t++)begin
   addr=addr+2;memory_word=memory_word+16'h313;cpu_read=1;
   repeat(4)tick();cpu_read=0;
   repeat(4)tick();
  end
  if(bad_live!=earliest_bad)$fatal(1,"earliest two-system-cycle result mismatch");
  checking=0;
  // Guarded lifecycle: exercise short pulses at every sub-memory-cycle offset,
  // first-operation init wait, read/write-independent DQ, idle hit history.
  core_reset=1;guard_enable=1;#2;core_reset=0;
  repeat(32)tick();checking=1;
  for(integer trial=0;trial<1000;trial++)begin
   nextphase0();addr=addr+2+(trial%2);memory_word=memory_word+16'h113;cpu_read=1;
   if(trial%3!=0) begin
    #(1+(trial%33));cart_download=1;
    #13;
    if(actual_reset_n)$fatal(1,"short pulse did not assert reset immediately");
    cart_download=0;
   end
   repeat(32)tick();
   if(!actual_reset_n)$fatal(1,"guard did not release");
   nextphase0();cpu_read=0;
   repeat(8)tick();
  end

  // Normal-running same-word hits must preserve both live byte-address
  // selection and requested word mode; no lifecycle reset surrounds these.
  nextphase0();addr=24'h7000;memory_word=16'ha15c;word_mode=1;cpu_read=1;
  repeat(4)tick();cpu_read=0;repeat(4)tick();
  for(integer mode=0;mode<32;mode++)begin
   addr=24'h7000+(mode%2);word_mode=(mode/2)%2;cpu_read=1;
   expected_cached=(!word_mode&&addr[0])?16'ha1a1:16'ha15c;
   cache_captures=captures;
   repeat(4)tick();cpu_read=0;repeat(4)tick();
   if(!actual_reset_n||q!==expected_cached||sys_q!==expected_cached)
    $fatal(1,"same-word byte/word result mismatch mode=%0d q=%h/%h",mode,q,sys_q);
   if(captures!=cache_captures)$fatal(1,"same-word fixture unexpectedly re-read SDRAM");
  end
  $display("PASS 32 normal same-word byte0/byte1 word/byte mode changes");

  // Force each stale-result phase under reset, including phase3: after an
  // asynchronous configuration/download transition the reset refresh source
  // may already be high. A different address defeats the same-word cache.
  for(integer offset=0;offset<40;offset++)begin
   nextphase0();while(!RFSH)nextphase0();
   cart_download=1;addr=addr+2;word_mode=offset%2;memory_word=memory_word+16'h731;
   #(1+offset);cart_download=0;
   repeat(36)tick();
  end
  if(nonphase_reset==0)$fatal(1,"missing offphase-under-reset coverage");
  // Metadata writes and lock-loss indications need the same asynchronous
  // consumer assertion; neither is required to coincide with a sys edge.
  for(integer offset=0;offset<40;offset++)begin
   nextphase0();#(1+offset);bridge_addr=4*(1+offset%4);bridge_wr=1;addr=addr+2;
   @(posedge host_clk);#1;
   if(!config_write||actual_reset_n)$fatal(1,"metadata pulse missed");
   bridge_wr=0;
   repeat(36)tick();
   nextphase0();#(1+offset);core_reset=1;
   #13;if(actual_reset_n||ready_mem)$fatal(1,"lock-loss pulse missed");core_reset=0;
   repeat(36)tick();
   if(!actual_reset_n)$fatal(1,"lock-loss release failed");
  end
  // Stop both PLL clocks with an in-flight read. Immediate reset must still
  // assert without a single local edge. Restart at the next aligned edge.
  for(integer phase=0;phase<4;phase++)begin
   nextphase0();addr=addr+2;cpu_read=1;
   repeat(phase)tick();
   @(negedge clk);#1;core_reset=1;run_clocks=0;
   #101;
   if(actual_reset_n||ready_mem)$fatal(1,"clock-stop reset failed");
   core_reset=0;
   #83;if(actual_reset_n)$fatal(1,"released without clocks");
   run_clocks=1;
   repeat(48)tick();
   if(!actual_reset_n)$fatal(1,"clock restart did not release");
   nextphase0();cpu_read=0;repeat(8)tick();
  end
  $display("PASS guarded live-edge miter checks=%0d captures=%0d offphase_under_reset=%0d",normal_checks,captures,nonphase_reset);
  $finish;
 end
endmodule
