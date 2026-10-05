library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;use std.env.all;
entity tb_bsx_datapak_waits is generic(SCENARIO:natural:=0);end;
architecture test of tb_bsx_datapak_waits is
 signal clk:std_logic:='0';signal rst:std_logic:='0';signal enable:std_logic:='1';
 signal a,ma:std_logic_vector(19 downto 0):=(others=>'0');
 signal di,dout,mdi,mdo:std_logic_vector(7 downto 0):=(others=>'0');
 signal ce,rd,wr:std_logic:='1';signal fc,rc,mr,mw,ready,usesmem,credit:std_logic:='0';
 signal snes:std_logic_vector(7 downto 0):=x"96";
 signal service:std_logic:='1';signal busy:std_logic:='0';
 signal reads,writes,erase_writes,cycles:natural:=0;
 signal check_erase:std_logic:='0';signal erase_base:natural:=0;
 signal peek:std_logic_vector(7 downto 0);signal peek_addr:natural:=16#12345#;
 signal expected_program:std_logic_vector(7 downto 0):=x"24";
 signal check_program:std_logic:='0';
begin
 clk<=not clk after 5 ns;
 dut:entity work.DATAPAK generic map(MEM_TRANSACTIONAL=>true) port map(
 CLK=>clk,RST_N=>rst,ENABLE=>enable,A=>a,DI=>di,DO=>dout,CE_N=>ce,RD_N=>rd,WR_N=>wr,
 SYSCLKF_CE=>fc,SYSCLKR_CE=>rc,MEM_ADDR=>ma,MEM_DI=>mdi,MEM_DO=>mdo,MEM_RD=>mr,MEM_WR=>mw,
 MEM_READY=>ready,SNES_DATA=>snes,READ_USES_MEMORY=>usesmem,WRITE_CREDIT=>credit,DP_CREDIT_DATA=>di);
 -- The external memory model retains one accepted operation and its result.
 -- It commits each physical write once, regardless of ENABLE or reset, and
 -- holds completion until the core can retire (or reset discards delivery).
 memory:process(clk)
  type phase_t is(IDLE,WAITING,RESPONSE);
  variable phase:phase_t:=IDLE;
  variable held_a:std_logic_vector(19 downto 0);
  variable held_d:std_logic_vector(7 downto 0);
  variable held_w:std_logic;
  variable delay_count:natural:=0;
  variable erase_index:natural:=0;
  variable canceled:boolean:=false;
  variable first:std_logic_vector(7 downto 0):=x"A5";
  variable second:std_logic_vector(7 downto 0):=x"0F";
 begin if rising_edge(clk) then
  cycles<=cycles+1;
  if peek_addr=16#12345# then peek<=first;else peek<=second;end if;
  if check_erase='0' then erase_index:=0;end if;
  if rst='0' and phase/=IDLE then canceled:=true;end if;
  case phase is
   when IDLE=>
    busy<='0';
    if mr='1' or mw='1' then
     assert not(mr='1' and mw='1') report "DATAPAK simultaneous read/write" severity failure;
     held_a:=ma;held_d:=mdo;held_w:=mw;canceled:=false;busy<='1';
     delay_count:=to_integer(unsigned(ma(2 downto 0))) mod 3;
     phase:=WAITING;
    end if;
   when WAITING=>
    if rst='1' and not canceled then
     assert ma=held_a and mdo=held_d and mw=held_w and mr=not held_w
      report "DATAPAK request changed before matched completion" severity failure;
    end if;
    if service='1' then
     if delay_count=0 then
      if held_w='1' then
       writes<=writes+1;
       if check_erase='1' then
        assert to_integer(unsigned(held_a))=erase_base+erase_index and held_d=x"FF"
         report "DATAPAK erase address/data duplicate or skipped" severity failure;
        erase_index:=erase_index+1;erase_writes<=erase_writes+1;
       elsif check_program='1' then
        assert held_d=expected_program report "DATAPAK program old AND new mismatch" severity failure;
       end if;
       if unsigned(held_a)=16#12345# then first:=held_d;end if;
       if unsigned(held_a)=16#12346# then second:=held_d;end if;
      else
       reads<=reads+1;
       if unsigned(held_a)=16#12345# then mdi<=first;
       elsif unsigned(held_a)=16#12346# then mdi<=second;else mdi<=x"FF";end if;
      end if;
      ready<='1';phase:=RESPONSE;
     else delay_count:=delay_count-1;end if;
    end if;
   when RESPONSE=>
    if rst='1' and not canceled then
     assert ma=held_a and mdo=held_d and mw=held_w and mr=not held_w
      report "DATAPAK result consumer changed before retire" severity failure;
    end if;
    if enable='1' or canceled then ready<='0';phase:=IDLE;busy<='0';end if;
  end case;
 end if;end process;
 stimulus:process
  procedure tick(n:natural:=1) is begin for i in 1 to n loop wait until rising_edge(clk);wait for 1 ns;end loop;end;
  procedure command(address,data:natural;allow_blocked:boolean:=false) is begin
   wait until falling_edge(clk);a<=std_logic_vector(to_unsigned(address,20));di<=std_logic_vector(to_unsigned(data,8));ce<='0';wr<='0';fc<='1';wait for 1 ns;
   if not allow_blocked then assert credit='1' report "DATAPAK unexpected write-credit block" severity failure;end if;
   tick;wait until falling_edge(clk);wr<='1';ce<='1';fc<='0';tick;
  end;
  procedure view(address,expected:natural;memory_path:std_logic:='0') is begin
   a<=std_logic_vector(to_unsigned(address,20));tick(2);
   assert usesmem=memory_path and dout=std_logic_vector(to_unsigned(expected,8)) report "DATAPAK status/ordinary read mismatch" severity failure;
  end;
  procedure idle_wait is begin
   for i in 0 to 400 loop exit when mr='0' and mw='0' and busy='0';tick;end loop;
   assert mr='0' and mw='0' and busy='0' report "DATAPAK operation did not finish" severity failure;
   tick(2);
  end;
  procedure reset_chip is begin rst<='0';tick(3);rst<='1';tick(3);end;
  variable old_writes,old_reads,start_cycle,total,base:natural;
 begin
  reset_chip;
  if SCENARIO=0 then
   -- Ordinary data is a separate SNES-owned result, never an in-flight RMW byte.
   view(16#12345#,16#96#,'1');command(0,16#75#);view(16#7F00#,16#4D#);view(16#7F02#,16#50#);view(16#7F06#,16#1A#);
   command(0,16#FF#);view(16#7F06#,16#96#,'1');
   service<='0';check_program<='1';old_writes:=writes;old_reads:=reads;
   command(16#12345#,16#40#);command(16#12345#,16#3C#);tick(20);
   assert mr='1' and mw='0' and ma=std_logic_vector(to_unsigned(16#12345#,20)) and writes=old_writes and reads=old_reads report "DATAPAK read advanced without completion" severity failure;
   command(0,16#70#);view(0,0);
   command(0,16#71#);view(2,16#C0#);view(4,16#82#);
   command(0,16#FF#);view(0,16#96#,'1');
   -- A conflicting page/chip erase must not overwrite pending program state.
   command(0,16#20#);a<=x"30000";di<=x"D0";tick;
   assert credit='0' report "DATAPAK erase credit allowed overlapping program" severity failure;
   command(16#30000#,16#D0#,true);command(0,16#A7#);command(0,16#D0#,true);tick(6);
   -- Preserve the returned old byte while ENABLE pauses architectural progress.
   enable<='0';service<='1';tick(12);
   assert ready='1' and mr='1' and writes=old_writes report "DATAPAK paused read advanced" severity failure;
   enable<='1';idle_wait;
   assert writes=old_writes+1 and reads=old_reads+1 and peek=x"24" report "DATAPAK single program count/value wrong" severity failure;
   expected_program<=x"20";command(16#12345#,16#10#);command(16#12345#,16#F0#);
   for i in 0 to 50 loop exit when mw='1';tick;end loop;
   assert mw='1' report "DATAPAK write phase missing" severity failure;
   enable<='0';tick(12);assert ready='1' and mw='1' report "DATAPAK paused write completion retired" severity failure;
   enable<='1';idle_wait;
   assert peek=x"20" report "DATAPAK consecutive program not ANDed with previous byte" severity failure;
   expected_program<=x"20";command(16#12345#,16#40#);command(16#12345#,16#FF#);idle_wait;
   assert peek=x"20" report "DATAPAK program illegally restored cleared bits" severity failure;
   expected_program<=x"0A";peek_addr<=16#12346#;command(16#12346#,16#40#);command(16#12346#,16#AA#);idle_wait;
   assert peek=x"0A" report "DATAPAK consecutive address/lane incorrect" severity failure;
   -- Reset cancels visible state, but the external model still completes an
   -- already accepted physical write once. It must not trigger fresh traffic.
   check_program<='0';service<='0';command(16#12345#,16#40#);command(16#12345#,16#00#);tick(5);
   reset_chip;service<='1';idle_wait;tick(8);old_writes:=writes;tick(10);
   assert writes=old_writes and mr='0' and mw='0' report "DATAPAK reset reissued canceled work" severity failure;
   service<='1';command(16#12345#,16#40#);command(16#12345#,16#00#);
   for i in 0 to 50 loop exit when mw='1';tick;end loop;
   assert mw='1' report "DATAPAK reset test never reached write" severity failure;
   service<='0';tick(3);old_writes:=writes;rst<='0';tick(3);service<='1';tick(12);rst<='1';idle_wait;
   assert writes=old_writes+1 and mw='0' and mr='0' report "DATAPAK accepted write reset did not drain once" severity failure;
   -- Erase cannot depend on SCPU clocks withheld by credit backpressure.
   service<='0';command(16#20000#,16#20#);command(16#20000#,16#D0#);tick(6);
   command(0,16#70#);view(0,0);command(0,16#FF#);
   command(0,16#40#);a<=x"55555";di<=x"AB";tick;
   assert credit='0' report "DATAPAK program credit allowed during erase" severity failure;
   command(16#55555#,16#AB#,true);tick(6);assert ma=x"20000" and mdo=x"FF" report "DATAPAK erase payload overwritten by program" severity failure;
   reset_chip;service<='1';idle_wait;
   report "PASS actual DATAPAK program RMW/consecutive programs, pause, status/vendor/SNES data, conflicts and reset";
  else
   if SCENARIO=1 then total:=65536;base:=16#10000#;else total:=1048576;base:=0;end if;
   check_erase<='1';erase_base<=base;old_writes:=writes;start_cycle:=cycles;
   if SCENARIO=1 then command(base+16#ABCDE# mod 65536,16#20#);command(base+3,16#D0#);
   else command(0,16#A7#);command(0,16#D0#);end if;
   -- Query status and vendor registers during a live erase without altering
   -- its retained address. SYSCLKF_CE remains zero for the entire long loop.
   if SCENARIO=1 then command(0,16#70#);view(0,0);
   else command(0,16#71#);view(4,2);end if;
   command(0,16#FF#);command(0,16#75#);view(16#7F00#,16#4D#);command(0,16#FF#);
   if SCENARIO=1 then
    command(0,16#40#);a<=x"12345";di<=x"0F";tick;
    assert credit='0' report "DATAPAK queued program not backpressured during full erase" severity failure;
   end if;
   while erase_writes<total loop
    tick;
    assert mw='1' report "DATAPAK erase ended before full length" severity failure;
   end loop;
   enable<='0';tick(12);
   assert ready='1' and mw='1' and to_integer(unsigned(ma))=base+total-1 report "DATAPAK final erase byte retired while paused" severity failure;
   enable<='1';idle_wait;
   assert writes=old_writes+total and erase_writes=total and mr='0' and mw='0' report "DATAPAK erase count/final completion wrong" severity failure;
   if SCENARIO=2 then command(0,16#71#);view(4,16#82#);end if;
   assert peek=x"FF" report "DATAPAK full erase omitted programmed address" severity failure;
   if SCENARIO=1 then
    assert credit='1' report "DATAPAK completed erase did not restore pending program credit" severity failure;
    check_erase<='0';check_program<='1';expected_program<=x"0F";
    command(16#12345#,16#0F#);idle_wait;assert peek=x"0F" report "DATAPAK queued program failed after erase" severity failure;
   end if;
   report "PASS actual DATAPAK full erase bytes=" & integer'image(total) & " sys clocks=" & integer'image(cycles-start_cycle);
  end if;
  stop;wait;
 end process;
 process begin wait for 100 ms;assert false report "DATAPAK timeout" severity failure;end process;
end;
