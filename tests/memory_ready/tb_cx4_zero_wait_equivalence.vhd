library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;use std.env.all;
entity tb_cx4_zero_wait_equivalence is generic(HANDSHAKE:boolean:=true;LATENCY:natural:=0);end;
architecture test of tb_cx4_zero_wait_equivalence is

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
 signal dout_ref:std_logic_vector(7 downto 0);
 signal ssdo_ref:std_logic_vector(7 downto 0);
 signal irq_ref:std_logic;
 signal p_cachecount_ref:std_logic_vector(2 downto 0);
 signal p_cachewe_ref:std_logic;
 signal p_cacheaddr_ref:std_logic_vector(9 downto 0);
 signal p_cachedata_ref:std_logic_vector(7 downto 0);
 signal p_cacherun_ref:std_logic;
 signal p_dmacount_ref:std_logic_vector(15 downto 0);
 signal p_dmastate_ref:std_logic;
 signal p_dmarun_ref:std_logic;
 signal p_dmawait_ref:std_logic_vector(2 downto 0);
 signal p_dmaaddr_ref:std_logic_vector(23 downto 0);
 signal p_ramwe_ref:std_logic;
 signal p_ramaddr_ref:std_logic_vector(11 downto 0);
 signal p_ramdata_ref:std_logic_vector(7 downto 0);
 signal p_extcount_ref:std_logic_vector(2 downto 0);
 signal p_ext_ref:std_logic;
 signal p_mbr_ref:std_logic_vector(7 downto 0);
 signal p_pc_ref:std_logic_vector(7 downto 0);
 signal p_cpu_ref:std_logic;
 signal busa_ref:std_logic_vector(23 downto 0);
 signal busd_ref:std_logic_vector(7 downto 0);
 signal busoe_ref:std_logic;
 signal buswe_ref:std_logic;
 signal ce1_ref:std_logic;
 signal ce2_ref:std_logic;
 signal sramce_ref:std_logic;
 signal busrd_ref:std_logic;
 signal cq_ref:std_logic_vector(7 downto 0);
 signal idle_ref:std_logic;

 function memory_byte(a:natural) return std_logic_vector is
 begin
 return std_logic_vector(to_unsigned(a mod 256,8));
 end function;

begin
 clk<=not clk after 5 ns;
 dut:entity work.CX4_PROBE generic map(ROM_HANDSHAKE=>HANDSHAKE) port map(
ROM_HARD_RESET_N=>hard,ROM_EPOCH=>epoch,ROM_FLUSH=>flush,ROM_FLUSH_ACK=>ack,ROM_FAULT=>fault,
 ROM_SNES_READ_INTENT=>si,ROM_SNES_OWNER=>so,ROM_SNES_RETIRE=>sret,ROM_SNES_WAIT=>sw,
 ROM_REQ_VALID=>qv,ROM_REQ_READY=>qr,ROM_REQ_ADDR=>qa,ROM_REQ_OWNER=>qo,ROM_REQ_SNES_OWNER=>qso,
 ROM_REQ_TAG=>qt,ROM_REQ_EPOCH=>qe,ROM_RSP_VALID=>pv,ROM_RSP_READY=>pr,ROM_RSP_DATA=>pd,
 ROM_RSP_OWNER=>po,ROM_RSP_TAG=>pt,ROM_RSP_EPOCH=>pe,ROM_RSP_ERROR=>perr,
 CLK=>clk,RST_N=>rst,ENABLE=>enable,ADDR=>addr,DI=>di,DO=>dout,RD_N=>rd,WR_N=>wr,
 SYSCLKF_CE=>fc,SYSCLKR_CE=>rc,IRQ_N=>irq,SS_BUSY=>ssbusy,SS_WR=>sswr,SS_DO=>ssdo,
CE=>'1',BUS_A=>busa,BUS_DI=>memory_byte(to_integer(unsigned(busa))),BUS_DO=>busd,BUS_OE_N=>busoe,BUS_WE_N=>buswe,ROM_CE1_N=>ce1,ROM_CE2_N=>ce2,SRAM_CE_N=>sramce,BUS_RD_N=>busrd,MAPPER=>'0',
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
p_cpu=>p_cpu); reference:entity work.CX4_REF port map(
CLK=>clk,RST_N=>rst,ENABLE=>enable,ADDR=>addr,DI=>di,DO=>dout_ref,RD_N=>rd,WR_N=>wr,
 SYSCLKF_CE=>fc,SYSCLKR_CE=>rc,IRQ_N=>irq_ref,SS_BUSY=>ssbusy,SS_WR=>sswr,SS_DO=>ssdo_ref,
CE=>'1',BUS_A=>busa_ref,BUS_DI=>memory_byte(to_integer(unsigned(busa_ref))),BUS_DO=>busd_ref,BUS_OE_N=>busoe_ref,BUS_WE_N=>buswe_ref,ROM_CE1_N=>ce1_ref,ROM_CE2_N=>ce2_ref,SRAM_CE_N=>sramce_ref,BUS_RD_N=>busrd_ref,MAPPER=>'0',
 SS_CACHE_A=>ca,SS_CACHE_SEL=>csel,SS_CACHE_WR=>cwr,SS_CACHE_DI=>cd,SS_CACHE_DO=>cq_ref,SS_IDLE=>idle_ref,
p_cachecount=>p_cachecount_ref,
p_cachewe=>p_cachewe_ref,
p_cacheaddr=>p_cacheaddr_ref,
p_cachedata=>p_cachedata_ref,
p_cacherun=>p_cacherun_ref,
p_dmacount=>p_dmacount_ref,
p_dmastate=>p_dmastate_ref,
p_dmarun=>p_dmarun_ref,
p_dmawait=>p_dmawait_ref,
p_dmaaddr=>p_dmaaddr_ref,
p_ramwe=>p_ramwe_ref,
p_ramaddr=>p_ramaddr_ref,
p_ramdata=>p_ramdata_ref,
p_extcount=>p_extcount_ref,
p_ext=>p_ext_ref,
p_mbr=>p_mbr_ref,
p_pc=>p_pc_ref,
p_cpu=>p_cpu_ref);
 -- Retained one-command memory with programmable service delay. LATENCY=0
 -- is nominal one-edge service; larger values model refresh/competing owners.
 process(clk)
  variable busy:boolean:=false;
  variable delay_count:natural:=0;
 begin if rising_edge(clk) then
  if hard='0' then busy:=false;pv<='0';qr<='1';
  else
   if pv='1' and pr='1' then pv<='0';busy:=false;qr<='1';end if;
   if qv='1' and qr='1' then
    busy:=true;qr<='0';delay_count:=LATENCY;
    po<=qo;pt<=qt;pe<=qe;
    pd<=memory_byte(to_integer(unsigned(qa))+1) & memory_byte(to_integer(unsigned(qa)));
    if LATENCY=0 then pv<='1';end if;
   elsif busy and pv='0' then
    if delay_count<=1 then pv<='1';else delay_count:=delay_count-1;end if;
   end if;
  end if;
 end if;end process;
 measure:process(clk)
  variable old_active:std_logic:='0';variable clocks:natural:=0;
 begin if rising_edge(clk) then
  if rst='0' then old_active:='0';clocks:=0;
  else
   if p_cacherun='1' then clocks:=clocks+1;
   elsif old_active='1' then
    report "MEASURE CX4 512-byte-cache active sys clocks=" & integer'image(clocks) &
           " HANDSHAKE=" & boolean'image(HANDSHAKE) & " LATENCY=" & integer'image(LATENCY);
    clocks:=0;
   end if;
   old_active:=p_cacherun;
  end if;
 end if;end process;
 compare:process begin wait until falling_edge(clk);wait for 1 ns; if rst='1' and LATENCY=0 then
 if true then assert p_cachecount=p_cachecount_ref report "CX4 zero-wait trace differs: p_cachecount" severity failure;end if;
 if true then assert p_cachewe=p_cachewe_ref report "CX4 zero-wait trace differs: p_cachewe" severity failure;end if;
 if true then assert p_cacheaddr=p_cacheaddr_ref report "CX4 zero-wait trace differs: p_cacheaddr" severity failure;end if;
 if p_cachewe='1' then assert p_cachedata=p_cachedata_ref report "CX4 zero-wait trace differs: p_cachedata" severity failure;end if;
 if true then assert p_cacherun=p_cacherun_ref report "CX4 zero-wait trace differs: p_cacherun" severity failure;end if;
 if true then assert p_dmastate=p_dmastate_ref report "CX4 zero-wait trace differs: p_dmastate" severity failure;end if;
 if true then assert p_dmarun=p_dmarun_ref report "CX4 zero-wait trace differs: p_dmarun" severity failure;end if;
 if true then assert p_dmawait=p_dmawait_ref report "CX4 zero-wait trace differs: p_dmawait" severity failure;end if;
 if true then assert p_dmaaddr=p_dmaaddr_ref report "CX4 zero-wait trace differs: p_dmaaddr" severity failure;end if;
 if true then assert p_ramwe=p_ramwe_ref report "CX4 zero-wait trace differs: p_ramwe" severity failure;end if;
 if true then assert p_ramaddr=p_ramaddr_ref report "CX4 zero-wait trace differs: p_ramaddr" severity failure;end if;
 if p_ramwe='1' then assert p_ramdata=p_ramdata_ref report "CX4 zero-wait trace differs: p_ramdata" severity failure;end if;
 if true then assert p_extcount=p_extcount_ref report "CX4 zero-wait trace differs: p_extcount" severity failure;end if;
 if true then assert p_ext=p_ext_ref report "CX4 zero-wait trace differs: p_ext" severity failure;end if;
 if true then assert p_mbr=p_mbr_ref report "CX4 zero-wait trace differs: p_mbr" severity failure;end if;
 if true then assert p_pc=p_pc_ref report "CX4 zero-wait trace differs: p_pc" severity failure;end if;
 if true then assert p_cpu=p_cpu_ref report "CX4 zero-wait trace differs: p_cpu" severity failure;end if;
 if true then assert busa=busa_ref report "CX4 zero-wait trace differs: busa" severity failure;end if;
 if true then assert busd=busd_ref report "CX4 zero-wait trace differs: busd" severity failure;end if;
 if true then assert busoe=busoe_ref report "CX4 zero-wait trace differs: busoe" severity failure;end if;
 if true then assert ce1=ce1_ref report "CX4 zero-wait trace differs: ce1" severity failure;end if;
 if true then assert ce2=ce2_ref report "CX4 zero-wait trace differs: ce2" severity failure;end if;
 if true then assert sramce=sramce_ref report "CX4 zero-wait trace differs: sramce" severity failure;end if;
 if true then assert busrd=busrd_ref report "CX4 zero-wait trace differs: busrd" severity failure;end if;
 if true then assert irq=irq_ref report "CX4 zero-wait trace differs: irq" severity failure;end if;
end if;end process;
 stimulus:process
  procedure tick(n:natural:=1) is begin for i in 1 to n loop wait until rising_edge(clk);wait for 1 ns;end loop;end;
  procedure ss(a,d:natural) is begin wait until falling_edge(clk); addr<=std_logic_vector(to_unsigned(a,24));di<=std_logic_vector(to_unsigned(d,8));sswr<='1';tick;wait until falling_edge(clk);sswr<='0';tick;end;
  procedure mm(a,d:natural) is begin wait until falling_edge(clk);addr<=std_logic_vector(to_unsigned(a,24));di<=std_logic_vector(to_unsigned(d,8));fc<='1';wr<='0';tick;wait until falling_edge(clk);fc<='0';wr<='1';tick;end;
  procedure reset_chip is begin enable<='0';rst<='0';hard<='0';flush<='0';si<='0';sret<='0';tick(3);hard<='1';rst<='1';tick(3);end;
  procedure cache_byte(a,d:natural) is begin
   ssbusy<='1';csel<='1';ca<=std_logic_vector(to_unsigned(a,10));cd<=std_logic_vector(to_unsigned(d,8));cwr<='1';tick;cwr<='0';tick;ssbusy<='0';csel<='0';tick;
  end;
  procedure program_word(a,d:natural) is begin cache_byte(a*2,d mod 256);cache_byte(a*2+1,d/256);end;
  procedure dma_setup is begin
   mm(16#7F40#,1);mm(16#7F41#,16#80#);mm(16#7F42#,0);
   mm(16#7F43#,3);mm(16#7F44#,0);mm(16#7F45#,0);mm(16#7F46#,16#60#);
  end;
 begin
 reset_chip;
 enable<='1';mm(16#7F49#,0);mm(16#7F4A#,16#80#);mm(16#7F4B#,0);mm(16#7F48#,0);tick(2200+512*LATENCY);
  assert p_cacherun='0' report "CX4 zero-wait cache did not finish" severity failure;
  dma_setup;mm(16#7F47#,0);tick(50+3*LATENCY);
  assert p_dmarun='0' report "CX4 zero-wait DMA did not finish" severity failure;
  program_word(0,16#612E#);program_word(1,16#1C00#);program_word(2,16#FC00#);
  ss(16#2E#,1);ss(16#2F#,16#80#);ss(16#30#,0);mm(16#7F4F#,0);tick(30+LATENCY);
  assert p_mbr=x"01" and p_pc=x"03" report "CX4 zero-wait FINEXT program did not finish" severity failure;
 if LATENCY=0 then
  report "PASS CX4 zero-wait actual-source trace against b63f800 HANDSHAKE=" & boolean'image(HANDSHAKE);
 else
  report "PASS CX4 actual-source firmware functional result LATENCY=" & integer'image(LATENCY);
 end if;stop;wait;
 end process;
end;
