library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;use std.env.all;
entity tb_predecode_4state is end;
architecture test of tb_predecode_4state is
 signal a:std_logic_vector(23 downto 0):=x"002180";
 signal b:std_logic_vector(7 downto 0):=x"80";
 signal en,pen,enable,ram,rd,wr,br,bw,ar,aw,har,haw,hbr,hbw,dm,hd:std_logic:='0';
 signal pa:std_logic_vector(7 downto 0);
 signal pr,pw,pred,oc,oo,nc,no,eq,se:std_logic;
 type logic_values is array(0 to 3) of std_logic;
 constant q:logic_values:=('0','1','X','Z');
 function fourbyte(n: natural) return std_logic_vector is variable v:std_logic_vector(7 downto 0);variable t:natural:=n;
 begin for i in 0 to 7 loop v(i):=q(t mod 4);t:=t/4;end loop;return v;end;
begin
 dut:entity work.WramReadDecode port map(a,b,en,pen,enable,ram,rd,wr,br,bw,ar,aw,har,haw,hbr,hbw,dm,hd,pa,pr,pw,pred,oc,oo,nc,no,eq,se);
 process
 variable checks:natural:=0;
 procedure check is begin wait for 1 ns;checks:=checks+1;
  assert se='1' report "selected predicate mismatch" severity failure;
  assert eq='1' report "WRAM read qualification mismatch" severity failure;
 end;
 begin
 en<='1';pen<='1';enable<='1';ram<='1';rd<='1';br<='1';hbr<='1';
 -- Every 0/1/X/Z byte, through CPU, DMA, and HDMA. CPU P65_EN may be
 -- asserted during either DMA selector; priority must still be preserved.
 for mode in 0 to 2 loop
  dm<='0';hd<='0';if mode=1 then dm<='1';elsif mode=2 then hd<='1';end if;
  for n in 0 to 65535 loop
   if mode=0 then a(7 downto 0)<=fourbyte(n);b<=not fourbyte(n);
   else b<=fourbyte(n);a(7 downto 0)<=not fourbyte(n);end if;check;
  end loop;
 end loop;
 -- Every high-byte 0/1/X/Z value; an uncertain or non-$21 qualifier never
 -- selects CPU B-bus $80 in native std_logic source semantics.
 dm<='0';hd<='0';a(7 downto 0)<=x"80";
 for n in 0 to 65535 loop a(15 downto 8)<=fourbyte(n);check;end loop;
 -- All four-state combinations of ownership qualifiers, including inactive
 -- bus and simultaneous DMA/HDMA. Probe equal and unequal source bytes.
 a<=x"002180";
 for n in 0 to 4095 loop
  en<=q(n mod 4);pen<=q((n/4) mod 4);dm<=q((n/16) mod 4);hd<=q((n/64) mod 4);
  a(22)<=q((n/256) mod 4);enable<=q((n/1024) mod 4);
  for bb in 0 to 2 loop
   if bb=0 then b<=x"80";elsif bb=1 then b<=x"81";else b<="X0000000";end if;
   for ab in 0 to 2 loop
    if ab=0 then a(7 downto 0)<=x"80";elsif ab=1 then a(7 downto 0)<=x"81";else a(7 downto 0)<="Z0000000";end if;
    ram<=q(ab);rd<=q(bb);br<=q((ab+bb) mod 4);hbr<=q((ab+bb+1) mod 4);check;
   end loop;
  end loop;
 end loop;
 report "PASS native VHDL four-state cases=" & integer'image(checks);stop;wait;
 end process;
end;
