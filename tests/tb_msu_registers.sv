`timescale 1ns/1ps
module tb_msu_registers;
reg clk=0; always #5 clk=~clk;
reg rst=0,en=1,rd=1,wr=1,ce=0;
reg [23:0] addr=0;reg[7:0] din=0; wire[7:0] dout;wire sel;
wire[15:0]track;wire tr;reg mount=0,missing=0,stop=0;
wire[7:0]vol;wire repeat_audio,playing,resume_audio;wire[31:0]da;reg[7:0]data=8'hA5;reg ack=0,busy=0;wire seek,next_data;
MSU d(.CLK(clk),.RST_N(rst),.ENABLE(en),.RD_N(rd),.WR_N(wr),.SYSCLKF_CE(ce),.ADDR(addr),.DIN(din),.DOUT(dout),.MSU_SEL(sel),.track_num(track),.track_request(tr),.track_mounting(mount),.volume(vol),.status_track_missing(missing),.status_audio_repeat(repeat_audio),.status_audio_playing(playing),.audio_stop(stop),.audio_resume(resume_audio),.audio_sector(22'd123),.resume_sector(),.audio_loop_index(32'd45),.resume_loop_index(),.data_addr(da),.data(data),.data_ack(ack),.data_busy_external(busy),.data_seek(seek),.data_req(next_data));
task write_reg(input[2:0]a,input[7:0]v);begin @(negedge clk);addr=24'h002000+a;din=v;wr=0;ce=1;@(negedge clk);wr=1;ce=0;end endtask
task read_reg(input[23:0]a,input[7:0]expected);begin @(negedge clk);addr=a;rd=0;repeat(2)@(negedge clk);if(dout!==expected)$fatal(1,"read %h got %h expected %h",a,dout,expected);rd=1;@(negedge clk);end endtask
initial begin repeat(3)@(negedge clk);rst=1;
read_reg('h2002,"S");read_reg('h2003,"-");read_reg('h802004,"M");read_reg('h2005,"S");read_reg('h2006,"U");read_reg('h2007,"1");read_reg('h2000,2);
addr='h402000;#1;if(sel)$fatal(1,"bank decode");addr='h2008;#1;if(sel)$fatal(1,"range decode");
write_reg(0,'h78);write_reg(1,'h56);write_reg(2,'h34);write_reg(3,'h12);if(da!==32'h12345678||!seek)$fatal(1,"seek");read_reg('h2000,'h82);ack=1;@(negedge clk);ack=0;read_reg('h2000,2);read_reg('h2001,'hA5);if(da!==32'h12345679)$fatal(1,"increment");
busy=1;read_reg('h2000,'h82);busy=0;
write_reg(4,7);write_reg(5,0);if(track!=7||!tr)$fatal(1,"track request");mount=1;repeat(2)@(negedge clk);mount=0;repeat(2)@(negedge clk);if(tr)$fatal(1,"busy clear");
write_reg(6,255);write_reg(7,3);if(vol!=255||!playing||!repeat_audio)$fatal(1,"control");read_reg('h2000,'h32);
stop=1;@(negedge clk);stop=0;if(playing)$fatal(1,"eof stop");missing=1;write_reg(7,1);if(playing)$fatal(1,"missing play");read_reg('h2000,'h2A);
$display("PASS register ID, decode, revision, seek, increment, busy, track, missing, volume, repeat, stop");$finish;end
endmodule
