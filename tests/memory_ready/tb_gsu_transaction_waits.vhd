library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;use std.env.all;
entity tb_gsu_transaction_waits is end;
architecture test of tb_gsu_transaction_waits is

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

begin
 clk<=not clk after 5 ns;
 dut:entity work.GSU_PROBE generic map(ROM_HANDSHAKE=>true) port map(
ROM_HARD_RESET_N=>hard,ROM_EPOCH=>epoch,ROM_FLUSH=>flush,ROM_FLUSH_ACK=>ack,ROM_FAULT=>fault,
 ROM_SNES_READ_INTENT=>si,ROM_SNES_OWNER=>so,ROM_SNES_RETIRE=>sret,ROM_SNES_WAIT=>sw,
 ROM_REQ_VALID=>qv,ROM_REQ_READY=>qr,ROM_REQ_ADDR=>qa,ROM_REQ_OWNER=>qo,ROM_REQ_SNES_OWNER=>qso,
 ROM_REQ_TAG=>qt,ROM_REQ_EPOCH=>qe,ROM_RSP_VALID=>pv,ROM_RSP_READY=>pr,ROM_RSP_DATA=>pd,
 ROM_RSP_OWNER=>po,ROM_RSP_TAG=>pt,ROM_RSP_EPOCH=>pe,ROM_RSP_ERROR=>perr,
 CLK=>clk,RST_N=>rst,ENABLE=>enable,ADDR=>addr,DI=>di,DO=>dout,RD_N=>rd,WR_N=>wr,
 SYSCLKF_CE=>fc,SYSCLKR_CE=>rc,IRQ_N=>irq,SS_BUSY=>ssbusy,SS_WR=>sswr,SS_DO=>ssdo,
TURBO=>'1',FASTROM=>'1',ROM_A=>roma,ROM_DI=>x"EE",ROM_RD_N=>romrd,
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
p_en=>p_en);
 process(clk) begin if rising_edge(clk) then
  if p_cachewe='1' then cache_writes<=cache_writes+1;end if;
 if p_load='1' and p_en='1' then load_ends<=load_ends+1;end if; if p_fetch='1' and p_en='1' then fetch_ends<=fetch_ends+1;end if;
end if;end process;
 stimulus:process

  procedure tick(n:natural:=1) is begin for i in 1 to n loop wait until rising_edge(clk);wait for 1 ns;end loop;end;
  procedure ss(a,d:natural) is begin wait until falling_edge(clk); addr<=std_logic_vector(to_unsigned(a,24));di<=std_logic_vector(to_unsigned(d,8));sswr<='1';tick;wait until falling_edge(clk);sswr<='0';tick;end;
  procedure mm(a,d:natural) is begin wait until falling_edge(clk);addr<=std_logic_vector(to_unsigned(a,24));di<=std_logic_vector(to_unsigned(d,8));fc<='1';wr<='0';tick;wait until falling_edge(clk);fc<='0';wr<='1';tick;end;
  procedure reset_chip is begin enable<='0';rst<='0';hard<='0';flush<='0';qr<='0';pv<='0';si<='0';sret<='0';tick(3);hard<='1';rst<='1';enable<='1';fc<='1';tick(4);fc<='0';enable<='0';tick(2);end;
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
  procedure seed_load(odd:natural:=1) is begin
   mm(16#301C#,odd);mm(16#301D#,16#80#);ss(4,2);ss(16#1A#,16#20#);ss(16#1B#,16#20#);ss(16#1C#,6);ss(0,10);
  end;
  variable before_writes,before_load,before_fetch:natural;
  variable oldtag:std_logic_vector(7 downto 0);
 begin
  reset_chip;seed_load;enable<='1';accept_req(1);before_load:=load_ends;
  tick(40);assert p_count="000" and p_romdr=x"00" and load_ends=before_load
   report "GSU LOAD retired/underflowed without result" severity failure;
  -- RON is a pause, not cancellation. Response capture frees the fabric while
  -- this owner waits; SNES gets a separate lane-qualified result in the gap.
  enable<='0';tick(2);ss(4,0);reply(16#ABCD#);
  assert p_romdr=x"00" report "GSU LOAD retired while paused" severity failure;
  addr<=x"008001";si<='1';accept_req(0);
  assert qso="10" report "SNES HDMA subowner lost" severity failure;
  reply(16#1234#);assert sw='0' and dout=x"12" report "GSU competing SNES lane/data wrong" severity failure;
  sret<='1';tick;sret<='0';si<='0';ss(4,2);enable<='1';tick(3);
  assert p_romdr=x"AB" and load_ends=before_load+1 report "GSU retained LOAD result not retired once dr=" & to_hstring(p_romdr) & " count=" & integer'image(load_ends) & " before=" & integer'image(before_load) & " state=" & to_hstring(p_state) & " en=" & std_logic'image(p_en) severity failure;
  enable<='0';tick(2);

  reset_chip;mm(16#301E#,1);mm(16#301F#,16#81#);ss(4,2);ss(16#1B#,16#20#);ss(16#1C#,1);ss(0,10);
  enable<='1';accept_req(2);before_fetch:=fetch_ends;tick(32);
  assert p_count="000" and fetch_ends=before_fetch report "GSU FETCH advanced without result" severity failure;
  reply(16#FE01#);enable<='0';tick(3);
  assert p_rombuf=x"FE" and fetch_ends=before_fetch+1 report "GSU FETCH lane/completion wrong" severity failure;

  reset_chip;ss(4,2);ss(16#0D#,0);ss(16#0E#,16#80#);ss(16#0F#,0);
  ss(16#1B#,16#20#);ss(16#1C#,3);ss(0,10);enable<='1';before_writes:=cache_writes;
  for i in 0 to 15 loop
   accept_req(3);tick(9+i mod 5);
   assert cache_writes=before_writes+i and p_count="000" report "GSU cache wrote or count wrapped before response" severity failure;
   assert unsigned(qa)=to_unsigned((i/2)*2,23) report "GSU cache request address duplicate/skipped" severity failure;
   reply(16#4040#+(i/2)*16#202#);
  end loop;
  enable<='0';tick(4);assert cache_writes=before_writes+16 report "GSU cache fill not exactly sixteen writes" severity failure;

  reset_chip;seed_load;enable<='1';accept_req(1);enable<='0';tick(2);
  -- Supersede accepted load with another R14 while stopped. The old byte must
  -- drain, then the new address gets a distinct transaction and original lane.
  mm(16#301C#,3);mm(16#301D#,16#80#);tick(2);oldtag:=pt;
  reply(16#AA11#);assert p_romdr=x"00" report "GSU superseded response delivered" severity failure;
  accept_req(1);assert qa=std_logic_vector(to_unsigned(2,23)) and pt/=oldtag report "GSU supersede did not recapture address/tag" severity failure;
  reply(16#5678#);enable<='1';tick(3);assert p_romdr=x"56" report "GSU replacement result lost" severity failure;


  reset_chip;mm(16#301E#,1);mm(16#301F#,16#81#);ss(4,2);ss(16#1B#,16#20#);ss(16#1C#,1);ss(0,10);enable<='1';
  tick(3);assert qv='1' report "GSU prefetch offer missing" severity failure;
  oldtag:=qt;ssbusy<='1';fc<='1';tick(4);fc<='0';mm(16#3034#,1);tick(3);
  assert qa=std_logic_vector(to_unsigned(16#100#,23)) and qt=oldtag report "GSU locked prefetch payload changed on bank write" severity failure;
  accept_req(2);reply(16#AA11#);assert p_fetch='0' report "GSU old-bank prefetch completed" severity failure;
  accept_req(2);assert qa=std_logic_vector(to_unsigned(16#8100#,23)) and pt/=oldtag report "GSU new-bank prefetch mapping/tag wrong" severity failure;
  reply(16#CD22#);ssbusy<='0';fc<='1';tick(4);fc<='0';tick(3);assert p_rombuf=x"CD" report "GSU new-bank prefetch data wrong" severity failure;

  reset_chip;seed_load;enable<='1';accept_req(1);oldtag:=pt;
  pt<=std_logic_vector(unsigned(pt)+1);reply(16#DEAD#);tick(10);
  assert p_romdr=x"00" and p_count="000" and fault='1' report "GSU mismatched tag released wait" severity failure;
  pt<=oldtag;reply(16#FEED#);tick(3);assert p_romdr=x"FE" report "GSU matching identity failed after stale response" severity failure;

  reset_chip;seed_load;enable<='1';accept_req(1);mm(16#3030#,0);tick(3);
  assert p_en='0' report "GSU STOP did not stop dependent execution" severity failure;
  reply(16#DEAD#);mm(16#3030#,16#20#);tick(8);
  assert p_romdr=x"00" report "GSU STOP/start delivered stale load" severity failure;
  reset_chip;seed_load;enable<='1';accept_req(1);rst<='0';tick(3);
  assert ack='0' report "GSU soft reset forgot accepted token" severity failure;
  reply(16#BEEF#);assert ack='1' report "GSU soft-reset response did not drain" severity failure;
  reset_chip;seed_load;enable<='1';accept_req(1);hard<='0';tick;
  assert ack='1' report "GSU hard reset waiting for nonexistent response" severity failure;
  reset_chip;seed_load;enable<='1';accept_req(1);reply(16#BEEF#,'1');tick(8);
  assert fault='1' and p_romdr=x"00" and p_state="110" report "GSU error response retired" severity failure;
  report "PASS GSU actual RTL LOAD/FETCH/CACHE, odd lanes, competing SNES, pause, supersede, soft/hard reset and error";stop;wait;
 end process;
 process begin wait for 100 us;assert false report "GSU timeout" severity failure;end process;
end;
