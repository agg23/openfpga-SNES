`timescale 1ns/1ps
// SCPU is generated with GHDL from the current production VHDL, including P65C816.
// The cartridge completion source varies acceptance/result latency; no CPU model.
module tb_scpu_rom_transaction;
 reg clk=0;always #5 clk=~clk;
 reg rst=0;
 wire [23:0] ca;wire [7:0] pa,dout;wire rd,wr,prd,pwr,fc,rc,romsel;
 wire read_intent,write_intent,retire;wire [7:0] write_lookahead;
 reg saw_old_bus_data=0;wire [1:0] owner;
 wire wait_bus,client_ack,client_fault,request_valid,response_ready;
 wire [23:0] address;wire [1:0] request_owner;wire [7:0] tag,epoch;
 wire [15:0] result_data;
 reg [7:0] memory[0:65535];
 wire [7:0] din=!romsel ? result_data[7:0] : memory[ca[15:0]];
 integer write_wait_count=70;
 wire write_wait=write_intent && ca==24'h7e0100 && write_wait_count!=0;
 SCPU cpu(.CLK(clk),.RST_N(rst),.ENABLE(1'b1),.BUS_WAIT(wait_bus),.BUS_WRITE_WAIT(write_wait),
 .DI(din),.HBLANK(1'b0),.VBLANK(1'b0),.IRQ_N(1'b1),.JOY1_DI(2'b11),.JOY2_DI(2'b11),
 .TURBO(1'b0),.SS_BUSY(1'b0),.DBG_CPU_EN(1'b1),
 .BUS_A_READ_INTENT(read_intent),.BUS_A_WRITE_INTENT(write_intent),.BUS_A_OWNER(owner),
 .BUS_A_WRITE_DATA(write_lookahead),.BUS_A_RETIRE(retire),.CA(ca),.CPURD_N(rd),.CPUWR_N(wr),.PA(pa),.PARD_N(prd),.PAWR_N(pwr),
 .DO(dout),.ROMSEL_N(romsel),.SYSCLKF_CE(fc),.SYSCLKR_CE(rc));
 reg response_valid=0;reg [15:0] response_data=0;
 reg [1:0] response_owner=0;reg [7:0] response_tag=0,response_epoch=0;
 reg backend_busy=0;integer backend_delay=0;
 wire request_ready=!backend_busy && !response_valid;
 snes_rom_client client(.clk(clk),.hard_reset_n(rst),.flush(!rst),.epoch(8'h42),
 .read_intent(read_intent),.owner(owner),.selected(!romsel),.address(ca),.retire(retire),
 .bus_wait(wait_bus),.result_data(result_data),.flush_ack(client_ack),.fault(client_fault),
 .req_valid(request_valid),.req_ready(request_ready),.req_addr(address),.req_owner(request_owner),
 .req_tag(tag),.req_epoch(epoch),.rsp_valid(response_valid),.rsp_ready(response_ready),
 .rsp_data(response_data),.rsp_owner(response_owner),.rsp_tag(response_tag),.rsp_epoch(response_epoch),.rsp_error(1'b0));
 integer cpu_requests=0,dma_requests=0,retired=0,writes=0,dma_edges=0,dma_commits=0,cycles=0;
 reg old_pwr=1;
 always @(posedge clk) begin
  cycles<=cycles+1;
  if(write_wait && write_wait_count>0)begin
   write_wait_count<=write_wait_count-1;
   if(write_lookahead!==8'h34)$fatal(1,"CPU write lookahead unavailable before R");
   if(dout!==write_lookahead)saw_old_bus_data<=1;
  end
  if(request_valid && request_ready) begin
   backend_busy<=1;
   backend_delay<=3+(tag%11)*7;
   response_data<={memory[{address[15:1],1'b1}],memory[{address[15:1],1'b0}]};
   response_owner<=request_owner;response_tag<=tag;response_epoch<=epoch;
   if(request_owner==0)cpu_requests<=cpu_requests+1;
   else if(request_owner==1)dma_requests<=dma_requests+1;
   else $fatal(1,"unexpected owner in CPU/DMA fixture");
  end
  if(backend_busy) begin
   if(backend_delay==0)begin response_valid<=1;backend_busy<=0;end
   else backend_delay<=backend_delay-1;
  end
  if(response_valid && response_ready)response_valid<=0;
  if(retire && !romsel && !rd)retired<=retired+1;
  if(!pwr && old_pwr && pa==8'h18) begin
   if(wait_bus || din!==8'h7b) $fatal(1,"DMA destination began before matched ROM byte");
   dma_edges<=dma_edges+1;
  end
  old_pwr<=pwr;
  if(!pwr && fc && pa==8'h18) begin
   if(din!==8'h7b) $fatal(1,"DMA byte wrong");dma_commits<=dma_commits+1;
  end
  if(!wr && fc) begin
   memory[ca[15:0]]<=dout;
   if(ca==24'h7e0100)begin
    if(write_wait_count!=0) $fatal(1,"write retired without reserved credit");
    writes<=writes+1;
   end
   if(ca==24'h7e010f) begin
    if(dout!==8'h5a || memory[16'h100]!==8'h34 || memory[16'h101]!==8'h7b)
     $fatal(1,"CPU data/result marker corrupt");
    if(!saw_old_bus_data || writes!=1 || dma_requests!=3 || dma_edges!=3 || dma_commits!=3 || client_fault)
     $fatal(1,"transaction side effects duplicated/lost writes=%0d dma=%0d edges=%0d commits=%0d",writes,dma_requests,dma_edges,dma_commits);
    if(retired!=cpu_requests+dma_requests)$fatal(1,"accept/retire count differs");
    $display("PASS actual SCPU tagged ROM: cpu=%0d dma=%0d retired=%0d; fixed-source DMA, variable delays, write-credit exactly once",cpu_requests,dma_requests,retired);
    $finish;
   end
  end
  if(cycles>100000)$fatal(1,"SCPU transaction deadlock");
 end
 integer i;
 initial begin
  for(i=0;i<65536;i=i+1)memory[i]=8'hea;
  // SEI; CLD; LDA #34; STA 0100; LDA 8120; STA 0101; fixed-source DMA 3 bytes to2118.
  memory[16'h8000]=8'h78;
  memory[16'h8001]=8'hd8;
  memory[16'h8002]=8'ha9;
  memory[16'h8003]=8'h34;
  memory[16'h8004]=8'h8d;
  memory[16'h8005]=8'h00;
  memory[16'h8006]=8'h01;
  memory[16'h8007]=8'had;
  memory[16'h8008]=8'h20;
  memory[16'h8009]=8'h81;
  memory[16'h800a]=8'h8d;
  memory[16'h800b]=8'h01;
  memory[16'h800c]=8'h01;
  memory[16'h800d]=8'ha9;
  memory[16'h800e]=8'h08;
  memory[16'h800f]=8'h8d;
  memory[16'h8010]=8'h00;
  memory[16'h8011]=8'h43;
  memory[16'h8012]=8'ha9;
  memory[16'h8013]=8'h18;
  memory[16'h8014]=8'h8d;
  memory[16'h8015]=8'h01;
  memory[16'h8016]=8'h43;
  memory[16'h8017]=8'ha9;
  memory[16'h8018]=8'h20;
  memory[16'h8019]=8'h8d;
  memory[16'h801a]=8'h02;
  memory[16'h801b]=8'h43;
  memory[16'h801c]=8'ha9;
  memory[16'h801d]=8'h81;
  memory[16'h801e]=8'h8d;
  memory[16'h801f]=8'h03;
  memory[16'h8020]=8'h43;
  memory[16'h8021]=8'h9c;
  memory[16'h8022]=8'h04;
  memory[16'h8023]=8'h43;
  memory[16'h8024]=8'ha9;
  memory[16'h8025]=8'h03;
  memory[16'h8026]=8'h8d;
  memory[16'h8027]=8'h05;
  memory[16'h8028]=8'h43;
  memory[16'h8029]=8'h9c;
  memory[16'h802a]=8'h06;
  memory[16'h802b]=8'h43;
  memory[16'h802c]=8'ha9;
  memory[16'h802d]=8'h01;
  memory[16'h802e]=8'h8d;
  memory[16'h802f]=8'h0b;
  memory[16'h8030]=8'h42;
  memory[16'h8031]=8'ha9;
  memory[16'h8032]=8'h5a;
  memory[16'h8033]=8'h8d;
  memory[16'h8034]=8'h0f;
  memory[16'h8035]=8'h01;
  memory[16'h8036]=8'h80;
  memory[16'h8037]=8'hfe;
  memory[16'h8120]=8'h7b;memory[16'hfffc]=0;memory[16'hfffd]=8'h80;
  #40;rst=1;
 end
endmodule
