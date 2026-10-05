`timescale 1ns/1ps
module tb_msu_data_cache;
reg clk=0;always #5 clk=~clk;
reg reset=1,enable=1,seek=0,next_data=0;
reg[31:0]size=1000,addr=0;
wire ack,busy,under;wire[7:0]data;wire req;wire[31:0]off;wire[15:0]len;
reg rv=0,done=0,err=0;reg[31:0]word_data=0;wire rr;
msu_data_cache #(.BLOCK_BYTES(64))d(.clk(clk),.reset(reset),.enable(enable),.file_size(size),.data_addr(addr),.data_seek(seek),.data_next(next_data),.data_ack(ack),.data(data),.busy(busy),.underrun(under),.req_valid(req),.req_ready(1'b1),.req_offset(off),.req_length(len),.resp_valid(rv),.resp_ready(rr),.resp_data(word_data),.resp_done(done),.resp_error(err));
integer state=0,delay_count=0,idx=0,n=0;reg[31:0]base=0;
function[7:0] pattern(input[31:0]a);pattern=(a*13+7)&255;endfunction
always @(negedge clk)begin
 rv=0;done=0;err=0;
 if(reset)state=0;else case(state)
 0:if(req)begin base=off;n=len;idx=0;delay_count=7;state=1;end
 1:if(delay_count==0)state=2;else delay_count=delay_count-1;
 2:begin rv=1;word_data={pattern(base+idx+3),pattern(base+idx+2),pattern(base+idx+1),pattern(base+idx)};idx=idx+4;if(idx>=n)state=3;end
 3:begin done=1;err=base==896;state=0;end
 endcase
end
task check(input[31:0]a,input[7:0]expected);integer t;begin
 @(negedge clk);addr=a;seek=1;@(negedge clk);t=0;
 while(busy&&t<1000)begin @(negedge clk);t=t+1;end
 repeat(4)@(negedge clk);if(t==1000||data!==expected)$fatal(1,"data %d got %h expected %h busy%b",a,data,expected,busy);
 seek=0;@(negedge clk);
end endtask
integer i;
initial begin repeat(4)@(negedge clk);reset=0;
check(0,pattern(0));for(i=1;i<300;i=i+1)check(i,pattern(i));
check(999,pattern(999));check(1000,0);check(32'hFFFF_FFFE,0);check(900,0);
@(negedge clk);addr=500;seek=1;repeat(3)@(negedge clk);addr=100;
repeat(200)@(negedge clk);if(data!==pattern(100))$fatal(1,"superseded seek");
size=32'hFFFF_FFFF;
check(32'hFFFF_FFE0,pattern(32'hFFFF_FFE0));
check(32'hFFFF_FFFE,pattern(32'hFFFF_FFFE));check(32'hFFFF_FFFF,0);
$display("PASS data cache sequential, block-boundary, large seek, EOF, error, superseded seek, near-4GiB offsets");$finish;end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
