`timescale 1ns/1ps
module tb_host_reset_guard;
 reg clk=0,locked=0,host_n=0;always #5 clk=~clk;
 wire hold_reset;
 host_reset_guard dut(clk,locked,host_n,hold_reset);
 task tick;begin @(posedge clk);#1;end endtask
 integer n;
 initial begin
 repeat(3)tick();if(!hold_reset)$fatal(1,"startup not held");
 locked=1;host_n=1;tick();if(!hold_reset)$fatal(1,"release1");tick();if(!hold_reset)$fatal(1,"release2");tick();if(hold_reset)$fatal(1,"release3");
 for(n=1;n<10;n=n+2)begin
 @(posedge clk);#(n);host_n=0;#0.1;if(!hold_reset)$fatal(1,"0010 assertion missed phase%0d",n);
 #0.2;host_n=1;tick();if(!hold_reset)$fatal(1,"short pulse lost1");tick();if(!hold_reset)$fatal(1,"short pulse lost2");tick();if(hold_reset)$fatal(1,"short pulse release");
 end
 @(negedge clk);locked=0;#0.1;if(!hold_reset)$fatal(1,"PLL assertion missed");
 locked=1;repeat(3)tick();if(hold_reset)$fatal(1,"PLL release");
 $display("PASS host reset asynchronous assertion, three-edge release, short pulses and PLL inhibition");$finish;
 end
endmodule
