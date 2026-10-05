`timescale 1ns/1ps
module tb_ram_clear_frontier;
 reg clk=0,reset_n=0,start=0,quiet=0; always #5 clk=~clk;
 reg [16:0] addr=0;wire active,busy,credit,credit16;wire[16:0] clear_addr,clear16;
 ram_clear_frontier dut(clk,reset_n,start,quiet,addr,active,busy,clear_addr,credit);
 ram_clear_frontier #(.BSRAM_BITS(16)) alias_dut(clk,reset_n,start,quiet,addr,,,clear16,credit16);
 task tick;begin @(posedge clk);#1;end endtask
 task begin_clear;begin @(negedge clk);start=1;#1;if(active||credit)$fatal(1,"BEGIN admission not immediate");tick();@(negedge clk);start=0;end endtask
 integer i,n;
 initial begin
 repeat(3)tick();reset_n=1;repeat(4)tick();
 if(busy||active||!credit)$fatal(1,"idle credit");
 begin_clear();repeat(12)begin tick();if(!busy||active||credit)$fatal(1,"clear before owner/PSRAM drain");end
 quiet=1;tick();if(!active||clear_addr!=0)$fatal(1,"drained start");
 for(i=0;i<8;i=i+1)begin if(credit)$fatal(1,"early halfword frontier");tick();end
 if(clear_addr!=2||!credit||credit16)$fatal(1,"physical frontier / alias final pass");
 addr=1;#1;if(credit)$fatal(1,"odd address credit");addr=0;
 quiet=0;begin_clear();repeat(7)begin tick();if(active||credit||clear_addr!=0)$fatal(1,"restart not pending");end
 quiet=1;tick();n=0;
 while(active)begin
  if(credit && clear_addr<2)$fatal(1,"frontier collision");
  if(credit16 && clear_addr<17'd65538)$fatal(1,"alias first-pass credit");
  n=n+1;tick();if(n>524288)$fatal(1,"full clear timeout");
 end
 if(n!=524288||!busy||!credit||!credit16)$fatal(1,"full 128 KiB clear length=%0d",n);
 tick();if(busy)$fatal(1,"tail drain did not complete");
 // An event on the old clear's final cycle must survive completion priority.
 begin_clear();tick();while(clear_addr!=17'h1ffff)tick();
 repeat(3)tick();quiet=0;begin_clear();tick();
 if(!busy||active||clear_addr!=0||credit)$fatal(1,"final-edge BEGIN lost");
 quiet=1;tick();repeat(20)tick();reset_n=0;#1;
 if(active||busy||credit)$fatal(1,"hard reset did not inhibit");
 $display("PASS full clear, pending drain, BEGIN priority, frontier, aliases and hard reset");$finish;
 end
endmodule
