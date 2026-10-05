library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;use std.env.all;
entity tb_gsu_zero_wait_equivalence is generic(HANDSHAKE:boolean:=true;LATENCY:natural:=0);end;
architecture test of tb_gsu_zero_wait_equivalence is

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
 signal p_state:std_logic_vector(2 downto 0);
 signal p_count:std_logic_vector(2 downto 0);
 signal p_load:std_logic;
 signal p_fetch:std_logic;
 signal p_cachewe:std_logic;
 signal p_cacheaddr:std_logic_vector(8 downto 0);
 signal p_cachedata:std_logic_vector(7 downto 0);
 signal p_romdr:std_logic_vector(7 downto 0);
 signal p_rombuf:std_logic_vector(7 downto 0);
 signal p_cpu:std_logic;
 signal p_r15:std_logic_vector(15 downto 0);
 signal p_en:std_logic;
 signal roma:std_logic_vector(20 downto 0); signal rama:std_logic_vector(16 downto 0); signal ramd:std_logic_vector(7 downto 0);signal romrd,ramwe,ramce:std_logic;
 signal dout_ref:std_logic_vector(7 downto 0);
 signal ssdo_ref:std_logic_vector(7 downto 0);
 signal irq_ref:std_logic;
 signal p_state_ref:std_logic_vector(2 downto 0);
 signal p_count_ref:std_logic_vector(2 downto 0);
 signal p_load_ref:std_logic;
 signal p_fetch_ref:std_logic;
 signal p_cachewe_ref:std_logic;
 signal p_cacheaddr_ref:std_logic_vector(8 downto 0);
 signal p_cachedata_ref:std_logic_vector(7 downto 0);
 signal p_romdr_ref:std_logic_vector(7 downto 0);
 signal p_rombuf_ref:std_logic_vector(7 downto 0);
 signal p_cpu_ref:std_logic;
 signal p_r15_ref:std_logic_vector(15 downto 0);
 signal p_en_ref:std_logic;
 signal roma_ref:std_logic_vector(20 downto 0);
 signal rama_ref:std_logic_vector(16 downto 0);
 signal ramd_ref:std_logic_vector(7 downto 0);
 signal romrd_ref:std_logic;
 signal ramwe_ref:std_logic;
 signal ramce_ref:std_logic;

 function memory_byte(a:natural) return std_logic_vector is
 begin
 case a mod 32768 is
   when 16#0200#=>return x"FE"; when 16#0201#=>return x"01";
   when 16#0202#=>return x"90"; when 16#0203#=>return x"EF";
   when 16#0204#=>return x"01"; when 16#0205#=>return x"00";
   when 16#1001#=>return x"6D";
   when others=>return x"01"; end case;
 end function;

begin
 clk<=not clk after 5 ns;
 dut:entity work.GSU_PROBE generic map(ROM_HANDSHAKE=>HANDSHAKE) port map(
ROM_HARD_RESET_N=>hard,ROM_EPOCH=>epoch,ROM_FLUSH=>flush,ROM_FLUSH_ACK=>ack,ROM_FAULT=>fault,
 ROM_SNES_READ_INTENT=>si,ROM_SNES_OWNER=>so,ROM_SNES_RETIRE=>sret,ROM_SNES_WAIT=>sw,
 ROM_REQ_VALID=>qv,ROM_REQ_READY=>qr,ROM_REQ_ADDR=>qa,ROM_REQ_OWNER=>qo,ROM_REQ_SNES_OWNER=>qso,
 ROM_REQ_TAG=>qt,ROM_REQ_EPOCH=>qe,ROM_RSP_VALID=>pv,ROM_RSP_READY=>pr,ROM_RSP_DATA=>pd,
 ROM_RSP_OWNER=>po,ROM_RSP_TAG=>pt,ROM_RSP_EPOCH=>pe,ROM_RSP_ERROR=>perr,
 CLK=>clk,RST_N=>rst,ENABLE=>enable,ADDR=>addr,DI=>di,DO=>dout,RD_N=>rd,WR_N=>wr,
 SYSCLKF_CE=>fc,SYSCLKR_CE=>rc,IRQ_N=>irq,SS_BUSY=>ssbusy,SS_WR=>sswr,SS_DO=>ssdo,
TURBO=>'1',FASTROM=>'1',ROM_A=>roma,ROM_DI=>memory_byte(to_integer(unsigned(roma))),ROM_RD_N=>romrd,
 RAM_A=>rama,RAM_DI=>x"77",RAM_DO=>ramd,RAM_WE_N=>ramwe,RAM_CE_N=>ramce,
 DBG_IN_CACHE=>open,DBG_MC=>open,DBG_GO_CNT=>open,
p_state=>p_state,
p_count=>p_count,
p_load=>p_load,
p_fetch=>p_fetch,
p_cachewe=>p_cachewe,
p_cacheaddr=>p_cacheaddr,
p_cachedata=>p_cachedata,
p_romdr=>p_romdr,
p_rombuf=>p_rombuf,
p_cpu=>p_cpu,
p_r15=>p_r15,
p_en=>p_en); reference:entity work.GSU_REF port map(
CLK=>clk,RST_N=>rst,ENABLE=>enable,ADDR=>addr,DI=>di,DO=>dout_ref,RD_N=>rd,WR_N=>wr,
 SYSCLKF_CE=>fc,SYSCLKR_CE=>rc,IRQ_N=>irq_ref,SS_BUSY=>ssbusy,SS_WR=>sswr,SS_DO=>ssdo_ref,
TURBO=>'1',FASTROM=>'1',ROM_A=>roma_ref,ROM_DI=>memory_byte(to_integer(unsigned(roma_ref))),ROM_RD_N=>romrd_ref,
 RAM_A=>rama_ref,RAM_DI=>x"77",RAM_DO=>ramd_ref,RAM_WE_N=>ramwe_ref,RAM_CE_N=>ramce_ref,
 DBG_IN_CACHE=>open,DBG_MC=>open,DBG_GO_CNT=>open,
p_state=>p_state_ref,
p_count=>p_count_ref,
p_load=>p_load_ref,
p_fetch=>p_fetch_ref,
p_cachewe=>p_cachewe_ref,
p_cacheaddr=>p_cacheaddr_ref,
p_cachedata=>p_cachedata_ref,
p_romdr=>p_romdr_ref,
p_rombuf=>p_rombuf_ref,
p_cpu=>p_cpu_ref,
p_r15=>p_r15_ref,
p_en=>p_en_ref);
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
   if p_en='1' then clocks:=clocks+1;
   elsif old_active='1' then
    report "MEASURE GSU program active sys clocks=" & integer'image(clocks) &
           " HANDSHAKE=" & boolean'image(HANDSHAKE) & " LATENCY=" & integer'image(LATENCY);
    clocks:=0;
   end if;
   old_active:=p_en;
  end if;
 end if;end process;
 compare:process begin wait until falling_edge(clk);wait for 1 ns; if rst='1' and LATENCY=0 then
 if true then assert p_state=p_state_ref report "GSU zero-wait trace differs: p_state" severity failure;end if;
 if true then assert p_load=p_load_ref report "GSU zero-wait trace differs: p_load" severity failure;end if;
 if true then assert p_fetch=p_fetch_ref report "GSU zero-wait trace differs: p_fetch" severity failure;end if;
 if true then assert p_cachewe=p_cachewe_ref report "GSU zero-wait trace differs: p_cachewe" severity failure;end if;
 if true then assert p_cacheaddr=p_cacheaddr_ref report "GSU zero-wait trace differs: p_cacheaddr" severity failure;end if;
 if p_cachewe='1' then assert p_cachedata=p_cachedata_ref report "GSU zero-wait trace differs: p_cachedata" severity failure;end if;
 if p_load='1' or p_fetch='1' or p_cachewe='1' then assert p_romdr=p_romdr_ref report "GSU zero-wait trace differs: p_romdr" severity failure;end if;
 if p_load='1' or p_fetch='1' or p_cachewe='1' then assert p_rombuf=p_rombuf_ref report "GSU zero-wait trace differs: p_rombuf" severity failure;end if;
 if true then assert p_cpu=p_cpu_ref report "GSU zero-wait trace differs: p_cpu" severity failure;end if;
 if true then assert p_r15=p_r15_ref report "GSU zero-wait trace differs: p_r15" severity failure;end if;
 if true then assert p_en=p_en_ref report "GSU zero-wait trace differs: p_en" severity failure;end if;
 if true then assert roma=roma_ref report "GSU zero-wait trace differs: roma" severity failure;end if;
 if true then assert rama=rama_ref report "GSU zero-wait trace differs: rama" severity failure;end if;
 if true then assert ramd=ramd_ref report "GSU zero-wait trace differs: ramd" severity failure;end if;
 if true then assert romrd=romrd_ref report "GSU zero-wait trace differs: romrd" severity failure;end if;
 if true then assert ramwe=ramwe_ref report "GSU zero-wait trace differs: ramwe" severity failure;end if;
 if true then assert ramce=ramce_ref report "GSU zero-wait trace differs: ramce" severity failure;end if;
 if true then assert irq=irq_ref report "GSU zero-wait trace differs: irq" severity failure;end if;
end if;end process;
 stimulus:process
  procedure tick(n:natural:=1) is begin for i in 1 to n loop wait until rising_edge(clk);wait for 1 ns;end loop;end;
  procedure ss(a,d:natural) is begin wait until falling_edge(clk); addr<=std_logic_vector(to_unsigned(a,24));di<=std_logic_vector(to_unsigned(d,8));sswr<='1';tick;wait until falling_edge(clk);sswr<='0';tick;end;
  procedure mm(a,d:natural) is begin wait until falling_edge(clk);addr<=std_logic_vector(to_unsigned(a,24));di<=std_logic_vector(to_unsigned(d,8));fc<='1';wr<='0';tick;wait until falling_edge(clk);fc<='0';wr<='1';tick;end;
  procedure reset_chip is begin enable<='0';rst<='0';hard<='0';flush<='0';si<='0';sret<='0';tick(3);hard<='1';rst<='1';enable<='1';fc<='1';tick(4);fc<='0';enable<='0';tick(2);end;
  procedure seed_load(odd:natural:=1) is begin
   mm(16#301C#,odd);mm(16#301D#,16#80#);ss(4,2);ss(16#1A#,16#20#);ss(16#1B#,16#20#);ss(16#1C#,6);ss(0,10);
  end;
 begin
 reset_chip;
 enable<='1';fc<='1';tick(4);fc<='0';
  mm(16#303A#,16#10#);mm(16#301E#,0);mm(16#301F#,16#82#);
  for i in 0 to 400+8*LATENCY loop tick;end loop;
  assert p_romdr=x"6D" report "GSU test program did not execute ROM load" severity failure;
  addr<=x"003000";tick;
  assert dout=x"6D" report "GSU variable-latency firmware GETB destination wrong" severity failure;
  -- Also start a cached program. Fill source is NOPs, then the complete line
  -- is available to execute independently from external read timing.
  rst<='0';hard<='0';tick(4);rst<='1';hard<='1';tick(4);
  mm(16#303A#,16#10#);mm(16#301E#,0);mm(16#301F#,0);
  tick(200+16*LATENCY);
 if LATENCY=0 then
  report "PASS GSU zero-wait actual-source trace against b63f800 HANDSHAKE=" & boolean'image(HANDSHAKE);
 else
  report "PASS GSU actual-source firmware functional result LATENCY=" & integer'image(LATENCY);
 end if;stop;wait;
 end process;
end;
