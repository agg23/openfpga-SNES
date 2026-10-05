library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;use std.env.all;
entity tb_cx4_transaction_waits is end;
architecture test of tb_cx4_transaction_waits is

 signal clk:std_logic:='0'; signal rst,hard:std_logic:='0'; signal enable:std_logic:='0';
 signal addr:std_logic_vector(23 downto 0):=(others=>'0'); signal di,dout,ssdo:std_logic_vector(7 downto 0):=(others=>'0');
 signal rd,wr:std_logic:='1'; signal fc,rc,sswr,ssbusy:std_logic:='0'; signal irq:std_logic;
 signal epoch:std_logic_vector(7 downto 0):=x"01"; signal flush,ack,fault,si,sret,sw:std_logic:='0';
 signal so:std_logic_vector(1 downto 0):="10";
 signal qv,qr,pv,pr:std_logic:='0'; signal qa:std_logic_vector(22 downto 0);
 signal qo,qso,po:std_logic_vector(1 downto 0):="00";
 signal qt,qe,pt,pe:std_logic_vector(7 downto 0):=(others=>'0');
 signal pd:std_logic_vector(15 downto 0):=(others=>'0');signal perr:std_logic:='0';
 signal cache_writes,load_ends,fetch_ends,ram_writes:natural:=0;
 signal p_cachecount:std_logic_vector(2 downto 0);
 signal p_cachewe:std_logic;
 signal p_cacheaddr:std_logic_vector(9 downto 0);
 signal p_cachedata:std_logic_vector(7 downto 0);
 signal p_cacherun:std_logic;
 signal p_dmacount:std_logic_vector(15 downto 0);
 signal p_dmastate:std_logic;
 signal p_dmarun:std_logic;
 signal p_dmawait:std_logic_vector(2 downto 0);
 signal p_dmaaddr:std_logic_vector(23 downto 0);
 signal p_ramwe:std_logic;
 signal p_ramaddr:std_logic_vector(11 downto 0);
 signal p_ramdata:std_logic_vector(7 downto 0);
 signal p_extcount:std_logic_vector(2 downto 0);
 signal p_ext:std_logic;
 signal p_mbr:std_logic_vector(7 downto 0);
 signal p_pc:std_logic_vector(7 downto 0);
 signal p_cpu:std_logic;
signal busa:std_logic_vector(23 downto 0);signal busd:std_logic_vector(7 downto 0);signal busoe,buswe,ce1,ce2,sramce,busrd:std_logic;
 signal ca:std_logic_vector(9 downto 0):=(others=>'0');signal cd,cq:std_logic_vector(7 downto 0):=(others=>'0');signal csel,cwr,idle:std_logic:='0';

begin
 clk<=not clk after 5 ns;
 dut:entity work.CX4_PROBE generic map(ROM_HANDSHAKE=>true) port map(
ROM_HARD_RESET_N=>hard,ROM_EPOCH=>epoch,ROM_FLUSH=>flush,ROM_FLUSH_ACK=>ack,ROM_FAULT=>fault,
 ROM_SNES_READ_INTENT=>si,ROM_SNES_OWNER=>so,ROM_SNES_RETIRE=>sret,ROM_SNES_WAIT=>sw,
 ROM_REQ_VALID=>qv,ROM_REQ_READY=>qr,ROM_REQ_ADDR=>qa,ROM_REQ_OWNER=>qo,ROM_REQ_SNES_OWNER=>qso,
 ROM_REQ_TAG=>qt,ROM_REQ_EPOCH=>qe,ROM_RSP_VALID=>pv,ROM_RSP_READY=>pr,ROM_RSP_DATA=>pd,
 ROM_RSP_OWNER=>po,ROM_RSP_TAG=>pt,ROM_RSP_EPOCH=>pe,ROM_RSP_ERROR=>perr,
 CLK=>clk,RST_N=>rst,ENABLE=>enable,ADDR=>addr,DI=>di,DO=>dout,RD_N=>rd,WR_N=>wr,
 SYSCLKF_CE=>fc,SYSCLKR_CE=>rc,IRQ_N=>irq,SS_BUSY=>ssbusy,SS_WR=>sswr,SS_DO=>ssdo,
CE=>'1',BUS_A=>busa,BUS_DI=>x"EE",BUS_DO=>busd,BUS_OE_N=>busoe,BUS_WE_N=>buswe,ROM_CE1_N=>ce1,ROM_CE2_N=>ce2,SRAM_CE_N=>sramce,BUS_RD_N=>busrd,MAPPER=>'0',
 SS_CACHE_A=>ca,SS_CACHE_SEL=>csel,SS_CACHE_WR=>cwr,SS_CACHE_DI=>cd,SS_CACHE_DO=>cq,SS_IDLE=>idle,
p_cachecount=>p_cachecount,
p_cachewe=>p_cachewe,
p_cacheaddr=>p_cacheaddr,
p_cachedata=>p_cachedata,
p_cacherun=>p_cacherun,
p_dmacount=>p_dmacount,
p_dmastate=>p_dmastate,
p_dmarun=>p_dmarun,
p_dmawait=>p_dmawait,
p_dmaaddr=>p_dmaaddr,
p_ramwe=>p_ramwe,
p_ramaddr=>p_ramaddr,
p_ramdata=>p_ramdata,
p_extcount=>p_extcount,
p_ext=>p_ext,
p_mbr=>p_mbr,
p_pc=>p_pc,
p_cpu=>p_cpu);
 process(clk) begin if rising_edge(clk) then
  if p_cachewe='1' then cache_writes<=cache_writes+1;end if;
 if p_ramwe='1' then ram_writes<=ram_writes+1;end if;
end if;end process;
 stimulus:process

  procedure tick(n:natural:=1) is begin for i in 1 to n loop wait until rising_edge(clk);wait for 1 ns;end loop;end;
  procedure ss(a,d:natural) is begin wait until falling_edge(clk); addr<=std_logic_vector(to_unsigned(a,24));di<=std_logic_vector(to_unsigned(d,8));sswr<='1';tick;wait until falling_edge(clk);sswr<='0';tick;end;
  procedure mm(a,d:natural) is begin wait until falling_edge(clk);addr<=std_logic_vector(to_unsigned(a,24));di<=std_logic_vector(to_unsigned(d,8));fc<='1';wr<='0';tick;wait until falling_edge(clk);fc<='0';wr<='1';tick;end;
  procedure reset_chip is begin enable<='0';rst<='0';hard<='0';flush<='0';qr<='0';pv<='0';si<='0';sret<='0';tick(3);hard<='1';rst<='1';tick(3);end;
  procedure accept_req(owner:natural) is
  begin
   for i in 0 to 200 loop exit when qv='1';tick;end loop;
   assert qv='1' report "request missing" severity failure;
   assert to_integer(unsigned(qo))=owner report "wrong request owner" severity failure;
   assert qa(0)='0' report "request not word aligned" severity failure;
   po<=qo;pt<=qt;pe<=qe;qr<='1';tick;qr<='0';tick;
  end;
  procedure reply(d:natural;error:std_logic:='0') is begin
   pd<=std_logic_vector(to_unsigned(d,16));perr<=error;pv<='1';tick;pv<='0';perr<='0';tick;
  end;
  procedure cache_byte(a,d:natural) is begin
   ssbusy<='1';csel<='1';ca<=std_logic_vector(to_unsigned(a,10));cd<=std_logic_vector(to_unsigned(d,8));cwr<='1';tick;cwr<='0';tick;ssbusy<='0';csel<='0';tick;
  end;
  procedure program_word(a,d:natural) is begin cache_byte(a*2,d mod 256);cache_byte(a*2+1,d/256);end;
  procedure dma_setup is begin
   mm(16#7F40#,1);mm(16#7F41#,16#80#);mm(16#7F42#,0);
   mm(16#7F43#,3);mm(16#7F44#,0);mm(16#7F45#,0);mm(16#7F46#,16#60#);
  end;
  variable before_writes,before_ram,a:natural;
  variable saved_owner:std_logic_vector(1 downto 0);
  variable saved_tag,saved_epoch:std_logic_vector(7 downto 0);
 begin
  reset_chip;enable<='1';addr<=x"008001";si<='1';accept_req(0);tick(15);
  assert sw='1' report "CX4 SNES read did not wait" severity failure;
  reply(16#1234#);assert sw='0' and dout=x"12" report "CX4 SNES lane mismatch" severity failure;
  sret<='1';tick;sret<='0';si<='0';tick;

  reset_chip;enable<='1';mm(16#7F49#,1);mm(16#7F4A#,16#80#);mm(16#7F4B#,0);
  before_writes:=cache_writes;mm(16#7F48#,0);
  for i in 0 to 511 loop
   accept_req(1);a:=to_integer(unsigned(qa));tick(5+i mod 7);
   assert p_cachecount="011" and cache_writes=before_writes+i report "CX4 cache wrote/advanced before matched data" severity failure;
   assert a=((i+1)/2)*2 report "CX4 cache address skipped/repeated" severity failure;
   if i=0 then
    mm(16#7F55#,0);reply((a mod 256)+(((a+1) mod 256)*256));tick(20);
    assert cache_writes=before_writes report "CX4 suspended cache wrote" severity failure;
    mm(16#7F5D#,0);tick;
   else
    reply((a mod 256)+(((a+1) mod 256)*256));
   end if;
   assert cache_writes=before_writes+i+1 report "CX4 cache beat did not write exactly once" severity failure;
  end loop;
  tick(10);assert p_cacherun='0' and cache_writes=before_writes+512 report "CX4 final cache beat wrong" severity failure;
  ssbusy<='1';csel<='1';
  for i in 0 to 511 loop
   ca<=std_logic_vector(to_unsigned(i,10));tick;
   assert unsigned(cq)=to_unsigned((i+1) mod 256,8) report "CX4 cache content wrong/lane stale" severity failure;
  end loop;
  ssbusy<='0';csel<='0';

  reset_chip;enable<='1';dma_setup;before_ram:=ram_writes;mm(16#7F47#,0);
  for i in 0 to 2 loop
   accept_req(2);tick(20);
   assert p_dmastate='0' and p_dmawait="011" and ram_writes=before_ram+i
    report "CX4 DMA advanced/wrote before matching source" severity failure;
   if i=0 then mm(16#7F55#,0);end if;
   reply(16#A1A0#+(i/2)*16#202#);
   if i=0 then
    tick(10);assert ram_writes=before_ram report "CX4 DMA wrote while suspended" severity failure;mm(16#7F5D#,0);
   end if;
   tick(3);assert ram_writes=before_ram+i+1 report "CX4 DMA destination not exactly once" severity failure;
  end loop;
  tick(5);assert p_dmarun='0' and p_dmacount=x"0000" report "CX4 DMA final count underflow/run" severity failure;

  -- Run original hand-authored CX4 instructions from the real instruction
  -- decoder: MOV external, NOP, FINEXT, HLT. No commercial image is used.
  reset_chip;program_word(0,16#612E#);program_word(1,16#0000#);program_word(2,16#1C00#);program_word(3,16#FC00#);
  ss(16#2E#,1);ss(16#2F#,16#80#);ss(16#30#,0);enable<='1';dma_setup;
  mm(16#7F4F#,0);accept_req(3);tick(20);
  assert p_ext='1' and p_extcount="000" and p_pc=x"02" report "CX4 FINEXT advanced before response" severity failure;
  saved_owner:=po;saved_tag:=pt;saved_epoch:=pe;
  -- Start independent DMA while FINEXT waits; direct data is captured into
  -- its own slot even though DMA is the live external bus owner.
  before_ram:=ram_writes;mm(16#7F47#,0);reply(16#7A55#);tick(5);
  assert p_pc=x"02" and p_mbr/=x"7A" report "CX4 direct result retired while DMA owned execution" severity failure;
  for i in 0 to 2 loop accept_req(2);tick(8);reply(16#B1B0#);tick(3);end loop;
  tick(8);assert p_mbr=x"7A" and p_pc=x"04" and p_ext='0' and ram_writes=before_ram+3
   report "CX4 direct result/PC did not retire once after DMA" severity failure;



  reset_chip;program_word(0,16#612E#);program_word(1,16#1C00#);program_word(2,16#FC00#);
  ss(16#2E#,1);ss(16#2F#,16#80#);ss(16#30#,0);enable<='1';mm(16#7F50#,0);mm(16#7F4F#,0);
  accept_req(3);tick(20);assert p_extcount="000" and p_pc=x"01" report "CX4 zero wait-state counter underflowed" severity failure;
  reply(16#6755#);tick(5);assert p_mbr=x"67" and p_pc=x"03" report "CX4 zero wait-state direct completion wrong" severity failure;
  -- Cartridge-local ROM_MODE remap supersedes an in-flight cache byte. It
  -- retains destination index zero while draining the old physical address.
  reset_chip;enable<='1';mm(16#7F49#,1);mm(16#7F4A#,16#80#);mm(16#7F4B#,16#20#);mm(16#7F48#,0);
  before_writes:=cache_writes;accept_req(1);saved_tag:=pt;
  assert qa=std_logic_vector(to_unsigned(16#100000#,23)) report "CX4 initial chip-bank map wrong" severity failure;
  mm(16#7F52#,1);tick(4);reply(16#DEAD#);
  assert cache_writes=before_writes report "CX4 old-bank cache byte written" severity failure;
  accept_req(1);assert qa=std_logic_vector(to_unsigned(0,23)) and pt/=saved_tag report "CX4 remap did not recapture address/tag" severity failure;
  reply(16#C355#);assert cache_writes=before_writes+1 report "CX4 remap result did not retire" severity failure;

  -- Stop with a read outstanding, then restart at the same external address.
  -- Equal address is not equal generation; old response cannot finish FINEXT.
  reset_chip;program_word(0,16#612E#);program_word(1,16#FC00#);
  ss(16#2E#,1);ss(16#2F#,16#80#);ss(16#30#,0);enable<='1';mm(16#7F4F#,0);accept_req(3);saved_tag:=pt;tick(5);
  program_word(1,16#1C00#);program_word(2,16#FC00#);mm(16#7F4F#,0);tick(8);
  reply(16#DEAD#);tick(3);assert p_pc=x"01" report "CX4 restart consumed old direct read" severity failure;
  accept_req(3);assert pt/=saved_tag report "CX4 restarted direct read reused old tag" severity failure;
  reply(16#4255#);tick(5);assert p_mbr=x"42" and p_pc=x"03" report "CX4 restart replacement result wrong" severity failure;
  reset_chip;enable<='1';dma_setup;mm(16#7F47#,0);accept_req(2);rst<='0';tick(4);
  assert ack='0' report "CX4 soft reset erased accepted token" severity failure;
  reply(16#BEEF#);assert ack='1' report "CX4 old response not drained" severity failure;
  reset_chip;enable<='1';dma_setup;mm(16#7F47#,0);accept_req(2);hard<='0';tick;
  assert ack='1' report "CX4 PLL reset awaiting nonexistent response" severity failure;
  reset_chip;enable<='1';dma_setup;mm(16#7F47#,0);accept_req(2);before_ram:=ram_writes;reply(16#BEEF#,'1');tick(10);
  assert fault='1' and ram_writes=before_ram and p_dmastate='0' report "CX4 error response retired" severity failure;
  report "PASS CX4 actual RTL 512-byte cache, suspend, SNES lanes, DMA exact writes, FINEXT firmware/competing DMA, reset and error";stop;wait;
 end process;
 process begin wait for 1 ms;assert false report "CX4 timeout" severity failure;end process;
end;
