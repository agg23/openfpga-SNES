`timescale 1ns/1ps
module tb_snes_rom_client;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,flush=0,intent=0,selected=0,retire=0;
 reg [7:0] epoch=1;
 reg [1:0] owner=0;
 reg [23:0] address=0;
 wire wait_bus,ack,fault,rv,rr;
 wire [15:0] data;
 wire [23:0] a;
 wire [1:0] o;
 wire [7:0] t,e;
 reg ready=0,sv=0,se=0;
 reg [15:0] sd=0;
 reg [1:0] so=0;
 reg [7:0] st=0,sep=0;
 snes_rom_client dut(.clk(clk),.hard_reset_n(reset_n),.flush(flush),.epoch(epoch),
  .read_intent(intent),.owner(owner),.selected(selected),.address(address),.retire(retire),
  .bus_wait(wait_bus),.result_data(data),.flush_ack(ack),.fault(fault),
  .req_valid(rv),.req_ready(ready),.req_addr(a),.req_owner(o),.req_tag(t),.req_epoch(e),
  .rsp_valid(sv),.rsp_ready(rr),.rsp_data(sd),.rsp_owner(so),.rsp_tag(st),.rsp_epoch(sep),.rsp_error(se));
 integer accepts=0;
 always @(posedge clk) if(rv && ready) accepts<=accepts+1;
 task response(input [15:0] d);
  begin @(negedge clk);sd=d;so=o;st=t;sep=e;sv=1;
   @(posedge clk);@(negedge clk);sv=0;end
 endtask
 initial begin
  repeat(3) @(negedge clk);reset_n=1;
  intent=1;selected=1;address=24'h123451;owner=2;
  #1;if(!wait_bus) $fatal(1,"intent did not assert wait before strobe");
  wait(rv);repeat(4) @(negedge clk);
  if(a!==24'h123451 || o!==2) $fatal(1,"bad descriptor");
  ready=1;wait(rr); @(negedge clk);ready=0;
  address=24'hfffffe;owner=0;selected=0; // arbitration/live-decode change cannot change identity
  repeat(10) @(negedge clk);
  if(a!==24'h123451 || !wait_bus) $fatal(1,"owner/address not retained");
  response(16'habcd);
  repeat(4) @(negedge clk);
  if(wait_bus || data!==16'habab || accepts!=1) $fatal(1,"response not retained/lane wrong");
  retire=1;@(negedge clk);retire=0;
  // Same-address successor is a distinct transaction, no falling intent required.
  address=24'h123451;owner=2;selected=1;
  wait(rv);if(t!==1) $fatal(1,"same-address read reused tag");
  ready=1;wait(rr);@(negedge clk);ready=0;flush=1;
  repeat(5) @(negedge clk);
  if(ack) $fatal(1,"flush dropped accepted transaction");
  epoch=2;flush=0;@(negedge clk);flush=1; // repeated reset, same accepted token
  response(16'h1234);
  if(!ack || data!==16'habab) $fatal(1,"canceled response delivered or not drained");
  intent=0;selected=0;flush=0;
  repeat(4) @(negedge clk);
  if(rv || fault || accepts!=2) $fatal(1,"duplicate after cancel");
  $display("PASS SCPU ROM client: pre-strobe wait, stable identity, byte lane, repeated-address, canceled drain");
  $finish;
 end
 initial begin #20000;$fatal(1,"timeout");end
endmodule
