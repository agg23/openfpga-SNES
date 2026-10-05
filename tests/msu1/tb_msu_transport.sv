// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module tb_msu_transport;
  reg sys_clk=0,host_clk=0,reset=1;
  always #7 sys_clk=~sys_clk;
  always #5 host_clk=~host_clk;
  reg enable=0;
  reg [31:0] file_size=96,data_addr=0;
  reg data_seek=0,data_next=0;
  wire data_ack,busy,underrun;
  wire[7:0]data;
  wire req_valid,req_ready,resp_valid,resp_ready,resp_done,resp_error;
  wire[31:0]req_offset,resp_data;
  wire[15:0]req_length;
  reg allow_response=1;
  msu_data_cache #(.BLOCK_BYTES(16)) cache(
    .clk(sys_clk),.reset(reset),.enable(enable),.file_size(file_size),.data_addr(data_addr),
    .data_seek(data_seek),.data_next(data_next),.data_ack(data_ack),.data(data),.busy(busy),.underrun(underrun),
    .req_valid(req_valid),.req_ready(req_ready),.req_offset(req_offset),.req_length(req_length),
    .resp_valid(resp_valid&&allow_response),.resp_ready(resp_ready),.resp_data(resp_data),.resp_done(resp_done),.resp_error(resp_error));
  wire host_req;reg host_ack=0,host_done=0;
  wire[31:0]host_offset;wire[15:0]host_length;
  reg[2:0]host_error=0;reg[15:0]host_actual=0;
  reg host_we=0;reg[15:0]host_waddr=0;reg[31:0]host_wdata=0;reg[3:0]host_wmask=0;
  msu_block_cdc #(.MAX_BYTES(16)) cdc(
    .sys_clk(sys_clk),.host_clk(host_clk),.reset(reset),.req_valid(req_valid),.req_ready(req_ready),
    .req_offset(req_offset),.req_length(req_length),.resp_valid(resp_valid),.resp_ready(resp_ready&&allow_response),
    .resp_data(resp_data),.resp_done(resp_done),.resp_error(resp_error),.host_req(host_req),.host_ack(host_ack),
    .host_offset(host_offset),.host_length(host_length),.host_done(host_done),.host_error(host_error),.host_actual(host_actual),
    .host_we(host_we),.host_waddr(host_waddr),.host_wdata(host_wdata),.host_wmask(host_wmask));
  integer reads=0;
  reg fail_reads=0;
  initial begin: responder
    reg[31:0]off;reg[15:0]len;
    forever begin
      wait(host_req);off=host_offset;len=host_length;reads=reads+1;
      repeat(3)@(negedge host_clk);
      if(host_offset!=off||host_length!=len)$fatal(1,"CDC request payload changed before ack");
      host_ack=1;
      @(negedge host_clk);host_ack=0;
      for(integer j=0;j<len;j=j+4)begin
        repeat(2)@(negedge host_clk);
        host_we=1;host_waddr=j;host_wmask=15;
        for(integer k=0;k<4;k=k+1)host_wdata[k*8+:8]=(off+j+k)^8'hA5;
        @(negedge host_clk);host_we=0;
      end
      repeat(2)@(negedge host_clk);
      host_error=fail_reads?3'd2:3'd0;host_actual=fail_reads?16'd0:len;host_done=1;
      @(negedge host_clk);host_done=0;
    end
  end
  task automatic seek(input[31:0] addr);
    begin
      @(negedge sys_clk);data_addr=addr;data_seek=1;
      wait(data_ack);@(negedge sys_clk);data_seek=0;
      repeat(3)@(negedge sys_clk);
    end
  endtask
  task automatic check_byte(input[31:0]addr,input[7:0]expected);
    begin
      @(negedge sys_clk);data_addr=addr;
      wait(!busy);repeat(3)@(negedge sys_clk);
      if(data!==expected)$fatal(1,"Cache data addr=%0d wanted=%02x actual=%02x",addr,expected,data);
    end
  endtask
  integer count_before;
  initial begin
    repeat(6)@(negedge sys_clk);reset=0;repeat(8)@(negedge sys_clk);enable=1;
    // Backpressure must keep a response immutable and stop its consumption.
    allow_response=0;
    wait(resp_valid);repeat(8)@(negedge sys_clk);
    if(!busy||data_ack)$fatal(1,"Premature publication while backpressured");
    allow_response=1;seek(0);
    for(integer a=0;a<40;a=a+1)check_byte(a,a^8'hA5);
    // Supersede an uncompleted seek. Old response must retain its own tag.
    @(negedge sys_clk);data_addr=0;data_seek=1;
    wait(host_req);@(negedge sys_clk);data_addr=80;
    wait(data_ack);@(negedge sys_clk);data_seek=0;
    check_byte(80,80^8'hA5);
    // No out-of-file fetches or stale bytes past EOF.
    seek(96);if(data!==0||busy)$fatal(1,"EOF data/ack");
    // Outstanding read failure becomes a safe, acknowledged zero-filled block.
    fail_reads=1;seek(64);
    if(data!==0||busy)$fatal(1,"Failed block handling");
    fail_reads=0;
    // Hard reset with both clocks present must re-arm toggle mailboxes.
    enable=0;wait(req_ready);repeat(6)@(negedge sys_clk);
    reset=1;repeat(6)@(negedge sys_clk);reset=0;repeat(8)@(negedge sys_clk);enable=1;
    seek(16);check_byte(16,16^8'hA5);
    $display("PASS tb_msu_transport: asynchronous clocks, backpressure, two-block data, superseding seek, EOF, errors, reset");
    $finish;
  end
  initial begin repeat(10000)@(posedge sys_clk);$fatal(1,"Transport timeout");end
endmodule
