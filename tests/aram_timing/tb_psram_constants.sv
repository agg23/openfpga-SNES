// Query production parameter expressions and observe actual transaction edges.
`timescale 1ns/1ps
module tb_psram_constants;
 parameter real CLOCK_SPEED=85.9;
 reg clk=0;always #5 clk=~clk;
 reg wr=0,rd=0;wire busy,avail;wire[15:0]q;tri[15:0]dq;wire oe;
 assign dq=!oe ? 16'h9bc7:16'hzzzz;
 psram #(.CLOCK_SPEED(CLOCK_SPEED)) u(.clk(clk),.bank_sel(1'b0),.addr(22'h123),
 .write_en(wr),.read_en(rd),.data_in(16'h425a),.write_high_byte(1'b1),.write_low_byte(1'b1),
 .read_avail(avail),.data_out(q),.busy(busy),.cram_dq(dq),.cram_wait(1'b0),.cram_oe_n(oe));
 integer edge_no=0,accepted=-1,read_gap=-1,write_gap=-1,accept_interval=-1,last_read_accept=-1,returns=0;
 always @(posedge clk)begin
  edge_no=edge_no+1;
  if(u.state==u.STATE_NONE&&(wr||rd))begin
   accepted=edge_no;
   if(!wr&&rd)begin
    if(last_read_accept>=0)accept_interval=edge_no-last_read_accept;
    last_read_accept=edge_no;
   end
  end
  if(u.state==u.STATE_WRITE_DATA_END)begin write_gap=edge_no-accepted;end
  if(u.state==u.STATE_READ_DATA_RECEIVED)begin read_gap=edge_no-accepted;returns=returns+1;end
 end
 initial begin
  @(negedge clk);wr=1;@(negedge clk);wr=0;
  wait(write_gap>=0);@(negedge clk);rd=1;
  wait(returns==3);@(negedge clk);rd=0;
  if(q!==16'h9bc7)$fatal(1,"PSRAM_CONSTANT_PROBE_DATA");
  $display("PSRAM_CONSTANTS read_total=%0d write_total=%0d read_initial=%0d read_end=%0d write_initial=%0d write_end=%0d read_gap=%0d write_gap=%0d accept_interval=%0d",u.TOTAL_READ_CYCLE_COUNT,u.TOTAL_WRITE_CYCLE_COUNT,u.READ_INITIAL_COUNT,u.STATE_READ_DATA_RECEIVED,u.WRITE_INITIAL_COUNT,u.STATE_WRITE_DATA_END,read_gap,write_gap,accept_interval);
  if(read_gap!=u.STATE_READ_DATA_RECEIVED-u.READ_INITIAL_COUNT+1 || write_gap!=u.STATE_WRITE_DATA_END-u.WRITE_INITIAL_COUNT+1 || accept_interval!=read_gap+1)$fatal(1,"PSRAM_CONSTANT_PROBE_FSM");
  $finish;
 end
 initial begin #5000;$fatal(1,"PSRAM_CONSTANT_PROBE_TIMEOUT");end
endmodule
