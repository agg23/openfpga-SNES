-- SPDX-License-Identifier: GPL-3.0-or-later
-- Actual CPU configures channel 3 indirect HDMA mode 1. The first source
-- byte waits across falling VBLANK; both bytes must finish on the same channel.
-- A deferred frame initialization then produces exactly the second pair.
library ieee;
use ieee.std_logic_1164.all;use ieee.numeric_std.all;use std.env.all;
entity tb_scpu_hdma_wait is end;
architecture test of tb_scpu_hdma_wait is
 signal clk:std_logic:='0';signal rst:std_logic:='0';
 signal ca:std_logic_vector(23 downto 0);signal pa,di,dout:std_logic_vector(7 downto 0);
 signal rd,wr,prd,pwr,fc,rc,rf,bwait:std_logic;
 signal hb,vb:std_logic:='0';
 type memory_t is array(0 to 65535) of std_logic_vector(7 downto 0);
 function init return memory_t is variable m:memory_t := (others=>x"EA");begin
    m(32768) := x"78";
    m(32769) := x"D8";
    m(32770) := x"9C";
    m(32771) := x"00";
    m(32772) := x"42";
    m(32773) := x"A9";
    m(32774) := x"41";
    m(32775) := x"8D";
    m(32776) := x"30";
    m(32777) := x"43";
    m(32778) := x"A9";
    m(32779) := x"18";
    m(32780) := x"8D";
    m(32781) := x"31";
    m(32782) := x"43";
    m(32783) := x"A9";
    m(32784) := x"00";
    m(32785) := x"8D";
    m(32786) := x"32";
    m(32787) := x"43";
    m(32788) := x"A9";
    m(32789) := x"A0";
    m(32790) := x"8D";
    m(32791) := x"33";
    m(32792) := x"43";
    m(32793) := x"A9";
    m(32794) := x"00";
    m(32795) := x"8D";
    m(32796) := x"34";
    m(32797) := x"43";
    m(32798) := x"A9";
    m(32799) := x"00";
    m(32800) := x"8D";
    m(32801) := x"37";
    m(32802) := x"43";
    m(32803) := x"A9";
    m(32804) := x"08";
    m(32805) := x"8D";
    m(32806) := x"0C";
    m(32807) := x"42";
    m(32808) := x"AD";
    m(32809) := x"20";
    m(32810) := x"01";
    m(32811) := x"F0";
    m(32812) := x"FB";
    m(32813) := x"9C";
    m(32814) := x"0C";
    m(32815) := x"42";
    m(32816) := x"A9";
    m(32817) := x"5A";
    m(32818) := x"8D";
    m(32819) := x"0F";
    m(32820) := x"01";
    m(32821) := x"80";
    m(32822) := x"FE";
 m(65532):=x"00";m(65533):=x"80";m(288):=x"00";
 m(40960):=x"81";m(40961):=x"01";m(40962):=x"20";m(40963):=x"00";m(8194):=x"66";
 return m;end;
 signal mem:memory_t:=init;
 signal cycles,enable_cycle,stall_cycle,nread,commits,edges:natural:=0;
 signal enabled,stalled,ready:std_logic:='0';
 function sample(i:natural) return std_logic_vector is begin return std_logic_vector(to_unsigned(85+i*19,8));end;
begin
 clk<=not clk after 5 ns;rst<='1' after 40 ns;
 dut:entity work.SCPU port map(CLK=>clk,RST_N=>rst,ENABLE=>'1',BUS_WAIT=>bwait,
 CA=>ca,CPURD_N=>rd,CPUWR_N=>wr,PA=>pa,PARD_N=>prd,PAWR_N=>pwr,DI=>di,DO=>dout,
 RAMSEL_N=>open,ROMSEL_N=>open,JPIO67=>open,REFRESH=>rf,SYSCLK=>open,SYSCLKF_CE=>fc,SYSCLKR_CE=>rc,
 HBLANK=>hb,VBLANK=>vb,IRQ_N=>'1',JOY1_DI=>"11",JOY2_DI=>"11",JOY_STRB=>open,JOY1_CLK=>open,JOY2_CLK=>open,
 SNI_JOY=>open,TURBO=>'0',SS_BUSY=>'0',DBG_CPU_EN=>'1');
 bwait<='1' when ca=x"002001" and ready='0' else '0';
 di<=sample(nread) when ca=x"002001" and ready='1' else x"00" when ca=x"002001" else mem(to_integer(unsigned(ca(15 downto 0))));
 process(clk)
 variable oldrd,oldpwr:std_logic:='1';variable oldca:std_logic_vector(23 downto 0):=(others=>'0');
 begin if rising_edge(clk) then
 cycles<=cycles+1;
 if cycles mod 1364>=1096 then hb<='1';else hb<='0';end if;
 if enabled='1' and stalled='0' then
  if cycles-enable_cycle<400 then vb<='1';else vb<='0';end if;
 elsif stalled='1' then
  if cycles-stall_cycle>=300 and cycles-stall_cycle<700 then vb<='1';else vb<='0';end if;
 end if;
 if ca=x"002001" and stalled='0' then stalled<='1';stall_cycle<=cycles;end if;
 if stalled='1' and cycles-stall_cycle>=2500 then ready<='1';end if;
 if oldrd='0' and rd='1' and oldca=x"002001" then nread<=nread+1;end if;
 if rd='0' then oldca:=ca;end if;oldrd:=rd;
 if pwr='0' and oldpwr='1' and (pa=x"18" or pa=x"19") then
  assert ready='1' report "HDMA B-write before source ready" severity failure;
  assert (pa=x"18" and di=sample(nread)) or (pa=x"19" and di=x"66") report "HDMA source incorrect at write edge" severity failure;
  edges<=edges+1;
 end if;oldpwr:=pwr;
 if pwr='0' and fc='1' and (pa=x"18" or pa=x"19") then
  assert (commits mod 2=0 and di=sample(commits/2)) or (commits mod 2=1 and di=x"66") report "HDMA lost or duplicate byte" severity failure;
  commits<=commits+1;
  if commits=3 then mem(288)<=x"01";end if;
 end if;
 if wr='0' and fc='1' then
  mem(to_integer(unsigned(ca(15 downto 0))))<=dout;
  if ca=x"00420C" and dout=x"08" then enabled<='1';enable_cycle<=cycles;end if;
  if ca=x"7E010F" then
   assert nread=2 and commits=4 and edges=4 report "HDMA did not preserve channel 3 across stalled frame boundary" severity failure;
   report "PASS actual SCPU channel-3 HDMA wait spanning frame boundary; no lost/duplicate B-writes";
   stop;
  end if;
 end if;
 assert cycles<30000 report "HDMA stalled-frame deadlock" severity failure;
 end if;end process;
end;
