// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module tb_audit_init_guard;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,dataslot_requestwrite=0,dataslot_allcomplete=0,ioctl_download=0;
 reg[15:0]dataslot_requestwrite_id=0;
 wire init_req;
 msu_init_guard dut(.*);
 integer count=0;
 always @(negedge clk)if(init_req)count=count+1;
 task cycles(input integer n);repeat(n)begin @(posedge clk);#1;end endtask
 task set_write(input[15:0]slot);
 begin dataslot_requestwrite_id=slot;dataslot_requestwrite=1;cycles(2);dataslot_requestwrite=0;cycles(2);end endtask
 task finish_all;
 begin dataslot_allcomplete=1;cycles(2);dataslot_allcomplete=0;cycles(2);end endtask
 task expect_count(input integer expected);
 begin cycles(2);if(count!=expected)$fatal(1,"bootstrap count=%0d expected=%0d",count,expected);end endtask
 initial begin
 cycles(3);reset=0;cycles(2);
 // Real loader: ROM all-complete, then download fall; Save toggles afterward.
 ioctl_download=1;set_write(0);finish_all();expect_count(1);
 ioctl_download=0;expect_count(1);
 ioctl_download=1;set_write(10);finish_all();ioctl_download=0;expect_count(1);
 // Opposite ordering of the two completion indications must also coalesce.
 ioctl_download=1;set_write(0);ioctl_download=0;expect_count(2);finish_all();expect_count(2);
 // An ordinary APF load without Chip32 download pulses still works.
 set_write(0);finish_all();expect_count(3);
 // Save/data/audio activity and unrelated completion indications do nothing.
 set_write(10);finish_all();set_write(100);finish_all();set_write(101);finish_all();expect_count(3);
 ioctl_download=1;cycles(2);ioctl_download=0;expect_count(3);
 // Held request and held completion only cause one bootstrap.
 dataslot_requestwrite_id=0;dataslot_requestwrite=1;cycles(3);
 dataslot_allcomplete=1;cycles(5);expect_count(4);
 dataslot_requestwrite=0;dataslot_allcomplete=0;cycles(2);finish_all();expect_count(4);
 // Start and completion on the same edge are not lost or repeated.
 dataslot_requestwrite=1;dataslot_allcomplete=1;cycles(2);
 dataslot_requestwrite=0;dataslot_allcomplete=0;expect_count(5);finish_all();expect_count(5);
 // If a distinct new start coincides with prior completion, retain it.
 set_write(0);dataslot_requestwrite=1;dataslot_allcomplete=1;cycles(2);
 dataslot_requestwrite=0;dataslot_allcomplete=0;expect_count(6);finish_all();expect_count(7);
 // Reset abandons a prior pending load and rearms the edge detectors.
 set_write(0);reset=1;cycles(2);reset=0;finish_all();expect_count(7);
 set_write(0);finish_all();expect_count(8);
 $display("PASS tb_audit_init_guard: ROM/Save identity, duplicate event ordering, held edges, concurrent boundaries, reset");$finish;
 end
 initial begin #20000;$fatal(1,"guard timeout");end
endmodule
