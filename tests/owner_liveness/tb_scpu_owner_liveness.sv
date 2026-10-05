`timescale 1ns/1ps
// Actual GHDL-translated SCPU and actual SA1RomBridge. Only ROM response timing
// and a saturated internal read client are modeled. The latter is a conservative
// demand contract for the two-owner SPC/SDD paths or one active GSU ROMST owner.
module tb_scpu_owner_liveness #(
 parameter integer INTERNAL_OWNER=1,
 parameter integer RESPONSE_DELAY=7,
 parameter integer RUN_CYCLES=120000,
 parameter integer TURBO=0
);
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0;
 wire [23:0] ca;wire [7:0] pa,dout;wire rd,wr,prd,pwr,fc,rc,romsel;
 wire intent,write_intent,retire;wire [7:0] lookahead;wire [1:0] subowner;
 wire [3:0] ready,lanes;wire [63:0] words;
 wire cpu_need=intent&&!romsel;
 wire cpu_wait=cpu_need&&!ready[0];
 wire [7:0] din=lanes[0]?words[15:8]:words[7:0];
 SCPU cpu(.CLK(clk),.RST_N(reset_n),.ENABLE(1'b1),.BUS_WAIT(cpu_wait),.BUS_WRITE_WAIT(1'b0),
 .DI(din),.HBLANK(1'b0),.VBLANK(1'b0),.IRQ_N(1'b1),.JOY1_DI(2'b11),.JOY2_DI(2'b11),
 .TURBO(TURBO!=0),.SS_BUSY(1'b0),.DBG_CPU_EN(1'b1),
 .BUS_A_READ_INTENT(intent),.BUS_A_WRITE_INTENT(write_intent),.BUS_A_OWNER(subowner),
 .BUS_A_WRITE_DATA(lookahead),.BUS_A_RETIRE(retire),.CA(ca),.CPURD_N(rd),.CPUWR_N(wr),
 .PA(pa),.PARD_N(prd),.PAWR_N(pwr),.DO(dout),.ROMSEL_N(romsel),.SYSCLKF_CE(fc),.SYSCLKR_CE(rc));
 wire [3:0] needs={3'b0,cpu_need}|(4'b1<<INTERNAL_OWNER);
 wire [3:0] retires={3'b0,(retire&&cpu_need&&ready[0])}|((4'b1<<INTERNAL_OWNER)&ready);
 reg [22:0] internal_addr=23'h600001;
 wire [91:0] addresses={internal_addr,internal_addr,internal_addr,ca[22:0]};
 wire qv,pr,ack,fault;wire [22:0] qa;wire [1:0] qo,qs;wire [7:0] qt,qe;
 reg busy=0,pv=0;reg [1:0] po=0;reg [7:0] pt=0,pe=0;reg [15:0] pd=0;
 integer cycle=0,remaining=0;
 wire qr=reset_n&&!busy&&!pv&&(cycle%7>=3);
 SA1RomBridge bridge(.CLK(clk),.HARD_RESET_N(reset_n),.ENABLE(1'b1),.FLUSH(!reset_n),
 .EPOCH(8'h73),.FLUSH_ACK(ack),.NEED(needs),.RETIRE(retires),.ADDRS(addresses),
 .SNES_OWNER(subowner),.READY(ready),.BYTES(lanes),.WORDS(words),
 .REQ_VALID(qv),.REQ_READY(qr),.REQ_ADDR(qa),.REQ_OWNER(qo),.REQ_SNES_OWNER(qs),
 .REQ_TAG(qt),.REQ_EPOCH(qe),.RSP_VALID(pv),.RSP_READY(pr),.RSP_OWNER(po),
 .RSP_TAG(pt),.RSP_EPOCH(pe),.RSP_DATA(pd),.RSP_ERROR(1'b0),.FAULT(fault));
 integer grants[0:3];integer last_grant[0:3];integer max_gap[0:3];
 integer wait_age[0:3];integer max_wait[0:3];
 integer high_grants=0,held_cycles=0,min_held=100000,cpu_returns=0;
 reg cpu_result_pending=0,saw_read_phase=0;
 always @(posedge clk)begin
  cycle=cycle+1;
  if(reset_n)begin
   if(fault)$fatal(1,"protocol fault");
   if(qv&&qr)begin
    if(qo!=0 && qo!=INTERNAL_OWNER)$fatal(1,"inactive internal owner granted");
    grants[qo]=grants[qo]+1;
    if(last_grant[qo]!=0 && cycle-last_grant[qo]>max_gap[qo])max_gap[qo]=cycle-last_grant[qo];
    last_grant[qo]=cycle;
    if(qo==0)begin
     high_grants=high_grants+1;
     if(high_grants>1)$fatal(1,"STARVATION SCPU repeatedly bypassed eligible internal owner");
    end else high_grants=0;
    busy<=1;remaining<=RESPONSE_DELAY;
    po<=qo;pt<=qt;pe<=qe;
    // Reset vector -> $8000. Thereafter execute real NOP fetches indefinitely.
    pd<=qo==0 && qa[15:0]==16'hfffc ? 16'h8000 : 16'heaea;
   end
   if(busy)begin
    if(remaining==0)begin busy<=0;pv<=1;end
    else remaining<=remaining-1;
   end
   if(pv&&pr)begin
    pv<=0;
    if(po==0)begin
     cpu_result_pending=1;held_cycles=0;saw_read_phase=0;cpu_returns=cpu_returns+1;
     if(retires[0])$fatal(1,"CPU retired on same edge as new response");
    end
   end
   if(cpu_result_pending)begin
    if(rc&&!cpu_wait)saw_read_phase=1;
    if(retires[0])begin
     if(!saw_read_phase || !fc || held_cycles<1)$fatal(1,"invalid CPU R/F retirement sequence");
     if(held_cycles<min_held)min_held=held_cycles;
     cpu_result_pending=0;
    end
    held_cycles=held_cycles+1;
   end
   if(retires[INTERNAL_OWNER])internal_addr<=internal_addr+1;
   for(integer i=0;i<4;i=i+1)begin
    if(needs[i]&&!ready[i])begin wait_age[i]=wait_age[i]+1;if(wait_age[i]>max_wait[i])max_wait[i]=wait_age[i];end
    else wait_age[i]=0;
   end
   if(cycle>=RUN_CYCLES)begin
    if(grants[0]<20 || grants[INTERNAL_OWNER]<20 || cpu_returns<20 || min_held<1)$fatal(1,"insufficient competition");
    // Conservative measured-contract bound: two serialized responses plus
    // at most three admission-blocked edges plus the next-offer edge per grant.
    if(max_wait[INTERNAL_OWNER]>2*(RESPONSE_DELAY+6))$fatal(1,"bounded endpoint service limit exceeded");
    $display("PASS SCPU_LIVENESS owner=%0d response_delay=%0d turbo=%0d cpu_grants=%0d internal_grants=%0d internal_max_wait_sys=%0d internal_max_grant_gap_sys=%0d cpu_min_result_hold_sys=%0d cycles=%0d",INTERNAL_OWNER,RESPONSE_DELAY,TURBO,grants[0],grants[INTERNAL_OWNER],max_wait[INTERNAL_OWNER],max_gap[INTERNAL_OWNER],min_held,cycle);
    $finish;
   end
  end
 end
 initial begin
  for(integer i=0;i<4;i=i+1)begin grants[i]=0;last_grant[i]=0;max_gap[i]=0;wait_age[i]=0;max_wait[i]=0;end
  #40;reset_n=1;
 end
endmodule
