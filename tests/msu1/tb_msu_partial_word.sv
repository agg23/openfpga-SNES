`timescale 1ns/1ps
module tb_msu_partial_word;
reg sys_clk=0,host_clk=0;always #5 sys_clk=~sys_clk;always #7 host_clk=~host_clk;
reg reset=1,req_valid=0;wire req_ready;reg[31:0]req_offset=123;reg[15:0]req_length=7;
wire resp_valid,resp_done,resp_error;reg resp_ready=1;wire[31:0]resp_data;
wire host_req;reg host_ack=0,host_done=0;wire[31:0]host_offset;wire[15:0]host_length;
reg[2:0]host_error=0;reg[15:0]host_actual=7;reg host_we=0;reg[15:0]host_waddr=0;
reg[31:0]host_wdata=0;reg[3:0]host_wmask=0;
msu_block_cdc #(.MAX_BYTES(16)) dut(.*);
integer count=0;
always @(posedge sys_clk)if(!reset && resp_valid && resp_ready)begin
if(count==0&&resp_data!==32'h11223344)$fatal(1,"Full word changed");
if(count==1&&resp_data!==32'h00BBCCDD)$fatal(1,"Partial word/padding changed: %h",resp_data);
count=count+1;end
initial begin
repeat(5)@(negedge sys_clk);reset=0;wait(req_ready);@(negedge sys_clk);req_valid=1;
@(negedge sys_clk);req_valid=0;wait(host_req);
@(negedge host_clk);host_ack=1;@(negedge host_clk);host_ack=0;
host_we=1;host_waddr=0;host_wdata='h11223344;host_wmask=15;
@(negedge host_clk);host_waddr=4;host_wdata='hAABBCCDD;host_wmask=7;
@(negedge host_clk);host_we=0;host_done=1;
@(negedge host_clk);host_done=0;wait(resp_done);@(negedge sys_clk);
if(count!=2||resp_error)$fatal(1,"Incorrect partial completion");
$display("PASS block RAM partial final word: valid seven bytes preserved, padding zeroed");$finish;end
initial begin #10000;$fatal(1,"timeout");end
endmodule
