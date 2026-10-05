// Test the exact main.v cache/registered-DOUT wait contract at block boundaries.
`timescale 1ns/1ps
module tb_msu_bus_backpressure;
reg clk=0;always #5 clk=~clk;
reg reset=1,rd_n=1,wr_n=1,ce=0;reg[23:0]addr='h2000;reg[7:0]din=0;
wire[7:0]dout,data;wire[31:0]data_addr;wire seek,ack,next_data,busy;
reg delayed_busy=1;always @(posedge clk)if(reset)delayed_busy<=1;else delayed_busy<=busy;
wire bus_wait=addr=='h2001&&(busy||delayed_busy);
MSU regs(.CLK(clk),.RST_N(!reset),.ENABLE(1'b1),.RD_N(rd_n),.WR_N(wr_n),.SYSCLKF_CE(ce),.ADDR(addr),.DIN(din),.DOUT(dout),.MSU_SEL(),.track_num(),.track_request(),.track_update(),.track_mounting(1'b0),.volume(),.status_track_missing(1'b0),.status_audio_repeat(),.status_audio_playing(),.audio_stop(1'b0),.audio_resume(),.audio_sector(22'd0),.resume_sector(),.audio_loop_index(32'd0),.resume_loop_index(),.data_addr(data_addr),.data(data),.data_ack(ack),.data_busy_external(busy),.data_seek(seek),.data_req(next_data));
wire req;wire[31:0]offset;wire[15:0]length;
reg resp_valid=0,resp_done=0;reg[31:0]resp_data=0;
msu_data_cache #(.BLOCK_BYTES(16))cache(.clk(clk),.reset(reset),.enable(1'b1),.file_size(32'd256),.data_addr(data_addr),.data_seek(seek),.data_next(next_data),.data_ack(ack),.data(data),.busy(busy),.underrun(),.req_valid(req),.req_ready(1'b1),.req_offset(offset),.req_length(length),.resp_valid(resp_valid),.resp_ready(),.resp_data(resp_data),.resp_done(resp_done),.resp_error(1'b0));
integer state=0,delay_count=0,word_index=0;reg[31:0]base;
always @(negedge clk)begin
 resp_valid=0;resp_done=0;
 if(reset)state=0;else case(state)
 0:if(req)begin base=offset;delay_count=150;word_index=0;state=1;end
 1:if(delay_count==0)state=2;else delay_count=delay_count-1;
 2:begin
 resp_valid=1;
 for(integer k=0;k<4;k=k+1)resp_data[8*k+:8]=(base+word_index*4+k)^8'hA5;
 word_index=word_index+1;if(word_index==4)state=3;end
 3:begin resp_done=1;state=0;end
 endcase
end
integer expected,stalled=0;
initial begin
repeat(4)@(negedge clk);reset=0;
// No repeated status polling: burst reads rely exclusively on BUS_WAIT.
for(expected=0;expected<256;expected=expected+1)begin
 @(negedge clk);addr='h2001;
 // Observe a full ready cycle before issuing the read-start phase.
 @(negedge clk);while(bus_wait)begin stalled=stalled+1;@(negedge clk);end
 rd_n=0;repeat(3)@(negedge clk);
 if(dout!==8'(expected^8'hA5))$fatal(1,"Stale byte at %0d: got%02x",expected,dout);
 rd_n=1;repeat(3)@(negedge clk);
 if(data_addr!==expected+1)$fatal(1,"Pointer lost or duplicated");
end
if(stalled<100)$fatal(1,"Test failed to force actual cache starvation");
$display("PASS register+cache bus backpressure: 256 burst bytes, no status polling, %0d stalled clocks",stalled);$finish;end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
