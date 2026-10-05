`timescale 1ns/1ps
module tb_msu_seek_race;
reg clk=0;always #5 clk=~clk;reg reset=1;
reg[23:0]addr='h2003;reg[7:0]din=0;reg wr_n=1,ce=0;
wire[31:0]data_addr;wire seek,ack,req,busy;wire[7:0]data,dout;
MSU regs(.CLK(clk),.RST_N(!reset),.ENABLE(1'b1),.RD_N(1'b1),.WR_N(wr_n),.SYSCLKF_CE(ce),.ADDR(addr),.DIN(din),.DOUT(dout),.MSU_SEL(),
.track_num(),.track_request(),.track_update(),.track_mounting(1'b0),.volume(),.status_track_missing(1'b0),.status_audio_repeat(),.status_audio_playing(),.audio_stop(1'b0),.audio_resume(),.audio_sector(22'd0),.resume_sector(),.audio_loop_index(32'd0),.resume_loop_index(),.data_addr(data_addr),.data(data),.data_ack(ack),.data_busy_external(busy),.data_seek(seek),.data_req(req));
msu_data_cache #(.BLOCK_BYTES(64))cache(.clk(clk),.reset(reset),.enable(1'b1),.file_size(32'd0),.data_addr(data_addr),.data_seek(seek),.data_next(req),.data_ack(ack),.data(data),.busy(busy),.underrun(),.req_valid(),.req_ready(1'b0),.req_offset(),.req_length(),.resp_valid(1'b0),.resp_ready(),.resp_data(32'd0),.resp_done(1'b0),.resp_error(1'b0));
initial begin
repeat(3)@(negedge clk);reset=0;
wr_n=0;ce=1;@(negedge clk);wr_n=1;ce=0;
wait(ack);@(negedge clk);wr_n=0;ce=1; // new same-address seek at old acknowledgement
@(negedge clk);wr_n=1;ce=0;
repeat(10)@(negedge clk);
if(seek||regs.status_data_busy)$fatal(1,"Same-address seek at ack edge deadlocked");
$display("PASS seek/ack race: second same-address commit clears busy");$finish;end
initial begin #10000;$fatal(1,"timeout");end
endmodule
