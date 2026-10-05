library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;use std.env.all;
entity tb_bsx_datapak_legacy is end;
architecture test of tb_bsx_datapak_legacy is
 signal clk:std_logic:='0';signal rst:std_logic:='0';signal enable:std_logic:='1';
 signal a,ma,maref:std_logic_vector(19 downto 0):=(others=>'0');
 signal di,dout,dref,mdo,mdref:std_logic_vector(7 downto 0):=(others=>'0');
 signal ce,rd,wr:std_logic:='1';signal fc,rc,mr,mw,mrref,mwref:std_logic:='0';signal writes,compared:natural:=0;
begin
 clk<=not clk after 5 ns;
 dut:entity work.DATAPAK generic map(MEM_TRANSACTIONAL=>false) port map(CLK=>clk,RST_N=>rst,ENABLE=>enable,A=>a,DI=>di,DO=>dout,CE_N=>ce,RD_N=>rd,WR_N=>wr,SYSCLKF_CE=>fc,SYSCLKR_CE=>rc,MEM_ADDR=>ma,MEM_DI=>x"A5",MEM_DO=>mdo,MEM_RD=>mr,MEM_WR=>mw,MEM_READY=>'0',SNES_DATA=>x"96",READ_USES_MEMORY=>open,WRITE_CREDIT=>open);
 reference:entity work.DATAPAK_REF port map(CLK=>clk,RST_N=>rst,ENABLE=>enable,A=>a,DI=>di,DO=>dref,CE_N=>ce,RD_N=>rd,WR_N=>wr,SYSCLKF_CE=>fc,SYSCLKR_CE=>rc,MEM_ADDR=>maref,MEM_DI=>x"A5",MEM_DO=>mdref,MEM_RD=>mrref,MEM_WR=>mwref);
 compare:process(clk) begin
  if falling_edge(clk) and rst='1' then
   assert ma=maref and dout=dref and mdo=mdref and mr=mrref and mw=mwref report "DATAPAK legacy differs from pristine b63f800" severity failure;
   compared<=compared+1;
  end if;
  if rising_edge(clk) and enable='1' and fc='1' and mw='1' then writes<=writes+1;end if;
 end process;
 stimulus:process
  procedure tick(n:natural:=1) is begin for i in 1 to n loop wait until rising_edge(clk);wait for 1 ns;end loop;end;
  procedure command(address,data:natural) is begin wait until falling_edge(clk);a<=std_logic_vector(to_unsigned(address,20));di<=std_logic_vector(to_unsigned(data,8));ce<='0';wr<='0';fc<='1';tick;wait until falling_edge(clk);ce<='1';wr<='1';fc<='0';tick;end;
  variable start:natural;
 begin
  tick(3);rst<='1';rc<='1';tick(3);
  command(16#12345#,16#40#);command(16#12345#,16#3C#);fc<='1';tick(5);fc<='0';assert writes=1 severity failure;
  command(0,16#70#);tick(3);rd<='0';ce<='0';fc<='1';tick;rd<='1';ce<='1';fc<='0';
  command(0,16#71#);a<=x"00002";tick(3);a<=x"00004";tick(3);command(0,16#75#);a<=x"07F06";tick(3);command(0,16#FF#);
  start:=writes;command(16#30007#,16#20#);command(16#30008#,16#D0#);fc<='1';
  tick(30);enable<='0';tick(20);enable<='1';
  while writes<start+65536 loop tick;end loop;tick(2);fc<='0';assert mw='0' and writes=start+65536 severity failure;
  start:=writes;command(0,16#A7#);command(0,16#D0#);fc<='1';
  while writes<start+1048576 loop tick;end loop;tick(2);fc<='0';assert mw='0' and writes=start+1048576 severity failure;
  report "PASS actual DATAPAK legacy b63f800 cycle comparison, full page/chip erase, clocks=" & integer'image(compared);stop;wait;
 end process;
 process begin wait for 30 ms;assert false report "DATAPAK legacy timeout" severity failure;end process;
end;
