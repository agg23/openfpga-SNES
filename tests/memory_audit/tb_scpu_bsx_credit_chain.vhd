library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use std.env.all;
entity tb_scpu_bsx_credit_chain is generic(MISWIRE:boolean:=false);end;
architecture test of tb_scpu_bsx_credit_chain is
 signal clk:std_logic:='0'; signal rst,hard,en:std_logic:='0';
 signal ca:std_logic_vector(23 downto 0):=(others=>'0'); signal di,dout:std_logic_vector(7 downto 0):=(others=>'0');
 signal rd,wr,pard,pawr:std_logic:='1'; signal pa:std_logic_vector(7 downto 0):=(others=>'0');
 signal prewrite:std_logic_vector(7 downto 0):=x"00";
 signal busowner:std_logic_vector(1 downto 0):="00";
 signal f,r,ri,wi,ret,flush:std_logic:='0'; signal epoch:std_logic_vector(7 downto 0):=x"01";
 signal waitr,waitw,ack,fault,qv,qr,qw,qd,sv,sready,serr,sw:std_logic:='0';
 signal qa:std_logic_vector(22 downto 0);signal qo,qso,so,strobes:std_logic_vector(1 downto 0);
 signal qt,qe,st,se:std_logic_vector(7 downto 0);signal qdata,sdata:std_logic_vector(15 downto 0);
 signal mapctrl:std_logic_vector(7 downto 0):=x"30";
 signal allow:std_logic:='1';signal delay_cycles:natural:=17;signal nreq,nwrite:natural:=0;
 signal waited:natural:=0;
 signal lastaddr:std_logic_vector(22 downto 0); signal lastdrain:std_logic;
 type ram_t is array(0 to 65535) of std_logic_vector(7 downto 0);
 signal ram:ram_t:=(others=>x"EA");
 signal cpu_in, credit_data:std_logic_vector(7 downto 0);
 signal romsel,ramsel:std_logic;
 signal blocked,confirm_commits,erase_starts:natural:=0;
 signal stale_seen,erase_seen:std_logic:='0';
 function bios(a:natural) return std_logic_vector is
 begin case a is when 0=>return x"5C";when 1|2|32764=>return x"00";
 when 3=>return x"7E";when 32765=>return x"80";when others=>return x"EA";end case;end;
 function initial(a:natural) return std_logic_vector is begin return std_logic_vector(to_unsigned((a*37 + a/256 + 93) mod 256,8));end;
begin
 clk<=not clk after 5 ns;
 process(clk) begin if rising_edge(clk) and ((ri='1' and waitr='1') or (wi='1' and waitw='1')) then waited<=waited+1;end if;end process;
 dut:entity work.BSXMap generic map(ROM_TRANSACTIONAL=>true) port map(
 MCLK=>clk,RST_N=>rst,ENABLE=>en,CA=>ca,DI=>di,DO=>dout,CPURD_N=>rd,CPUWR_N=>wr,
 PA=>pa,PARD_N=>pard,PAWR_N=>pawr,ROMSEL_N=>romsel,RAMSEL_N=>ramsel,SYSCLKF_CE=>f,SYSCLKR_CE=>r,REFRESH=>'0',IRQ_N=>open,
 ROM_HARD_RESET_N=>hard,ROM_EPOCH=>epoch,ROM_FLUSH=>flush,ROM_FLUSH_ACK=>ack,ROM_FAULT=>fault,
 ROM_SNES_READ_INTENT=>ri,ROM_SNES_WRITE_INTENT=>wi,ROM_SNES_OWNER=>busowner,ROM_SNES_RETIRE=>ret,ROM_SNES_WRITE_DATA=>credit_data,
 ROM_SNES_WAIT=>waitr,ROM_SNES_WRITE_WAIT=>waitw,
 ROM_REQ_VALID=>qv,ROM_REQ_READY=>qr,ROM_REQ_ADDR=>qa,ROM_REQ_OWNER=>qo,ROM_REQ_SNES_OWNER=>qso,
 ROM_REQ_TAG=>qt,ROM_REQ_EPOCH=>qe,ROM_REQ_WRITE=>qw,ROM_REQ_DRAIN=>qd,ROM_REQ_WDATA=>qdata,ROM_REQ_WSTRB=>strobes,
 ROM_RSP_VALID=>sv,ROM_RSP_READY=>sready,ROM_RSP_OWNER=>so,ROM_RSP_TAG=>st,ROM_RSP_EPOCH=>se,
 ROM_RSP_DATA=>sdata,ROM_RSP_ERROR=>serr,ROM_RSP_WRITE=>sw,
 ROM_ADDR=>open,ROM_D=>open,ROM_Q=>x"DEAD",ROM_CE_N=>open,ROM_OE_N=>open,ROM_WE_N=>open,ROM_WORD=>open,
 BSRAM_ADDR=>open,BSRAM_D=>open,BSRAM_Q=>x"A6",BSRAM_CE_N=>open,BSRAM_OE_N=>open,BSRAM_WE_N=>open,
 EXT_RTC=>(others=>'0'),MAP_ACTIVE=>open,MAP_CTRL=>mapctrl,ROM_MASK=>x"FFFFFF",BSRAM_MASK=>x"FFFFFF");
 backend:process(clk,hard)
  type addresses_t is array(0 to 255) of natural;
  type data_t is array(0 to 255) of std_logic_vector(7 downto 0);
  variable addrs:addresses_t:=(others=>0);variable bytes:data_t;variable used:natural:=0;
  variable busy:boolean:=false;variable count:natural:=0;variable a:natural;
  variable data16:std_logic_vector(15 downto 0);
  impure function getbyte(addr:natural) return std_logic_vector is
  begin for j in 0 to used-1 loop if addrs(j)=addr then return bytes(j);end if;end loop;if addr<16#100000# then return bios(addr);end if;return x"FF";end;
  procedure setbyte(addr:natural;v:std_logic_vector(7 downto 0)) is
  begin for j in 0 to used-1 loop if addrs(j)=addr then bytes(j):=v;return;end if;end loop;
   assert used<256 severity failure;addrs(used):=addr;bytes(used):=v;used:=used+1;end;
 begin
 if hard='0' then qr<='0';sv<='0';busy:=false;nreq<=0;nwrite<=0;used:=0;
 elsif rising_edge(clk) then
  sv<='0';qr<=allow;
  if busy then qr<='0';
   if so="01" and sw='0' and blocked<50 then null;
   elsif count=0 then sv<='1';busy:=false;else count:=count-1;end if;end if;
  if qv='1' and qr='1' then
   assert not busy report "backend double accept" severity failure;
   assert qa(0)='0' report "unaligned BSX request" severity failure;
   a:=to_integer(unsigned(qa));data16:=getbyte(a+1)&getbyte(a);
   if qw='1' then
    if strobes(0)='1' then setbyte(a,qdata(7 downto 0));end if;
    if strobes(1)='1' then setbyte(a+1,qdata(15 downto 8));end if;nwrite<=nwrite+1;
   end if;
   so<=qo;st<=qt;se<=qe;sw<=qw;sdata<=data16;serr<='0';
   busy:=true;count:=delay_cycles;qr<='0';nreq<=nreq+1;lastaddr<=qa;lastdrain<=qd;
  end if;
 end if;
 end process;

 credit_data <= di when MISWIRE else prewrite;
 cpu_in <= ram(to_integer(unsigned(ca(15 downto 0)))) when ramsel='0' else dout;
 cpu:entity work.SCPU port map(CLK=>clk,RST_N=>rst,ENABLE=>en,
  BUS_WAIT=>waitr,BUS_WRITE_WAIT=>waitw,BUS_A_READ_INTENT=>ri,BUS_A_WRITE_INTENT=>wi,
  BUS_A_OWNER=>busowner,BUS_A_WRITE_DATA=>prewrite,BUS_A_RETIRE=>ret,
  CA=>ca,CPURD_N=>rd,CPUWR_N=>wr,PA=>pa,PARD_N=>pard,PAWR_N=>pawr,DI=>cpu_in,DO=>di,
  RAMSEL_N=>ramsel,ROMSEL_N=>romsel,JPIO67=>open,REFRESH=>open,SYSCLK=>open,
  SYSCLKF_CE=>f,SYSCLKR_CE=>r,HBLANK=>'0',VBLANK=>'0',IRQ_N=>'1',JOY1_DI=>"11",JOY2_DI=>"11",
  JOY_STRB=>open,JOY1_CLK=>open,JOY2_CLK=>open,SNI_JOY=>open,TURBO=>'0',SS_BUSY=>'0',DBG_CPU_EN=>'1');
 monitor:process(clk)
  type program_t is array(natural range<>) of std_logic_vector(7 downto 0);
  constant program:program_t:=(
   x"78",x"D8",x"A9",x"80",x"8F",x"00",x"50",x"0C",x"8F",x"00",x"50",x"0E",
   x"A9",x"40",x"8F",x"11",x"00",x"40",x"A9",x"0F",x"8F",x"11",x"00",x"40",
   x"A9",x"20",x"8F",x"00",x"00",x"40",x"A9",x"D0",x"8F",x"00",x"00",x"40",
   x"A9",x"5A",x"8D",x"0F",x"01",x"80",x"FE");
  variable cycles:natural:=0;
 begin
  if rising_edge(clk) then
   if rst='0' then for i in program'range loop ram(i)<=program(i);end loop;
   else
    cycles:=cycles+1;assert cycles<30000 report "CPU BSX credit chain deadlock" severity failure;
    if wi='1' and ca=x"400000" and prewrite=x"D0" and blocked<50 then
     assert busowner="00" and waitw='1' and wr='1' and r='0'
      report "LOOKAHEAD_CREDIT did not block real CPU before bus R" severity failure;
     blocked<=blocked+1;
     if di/=prewrite then stale_seen<='1';end if;
    end if;
    if qv='1' and qr='1' and qo="01" and qw='1' and unsigned(qa)=16#100000# and strobes="01" then erase_seen<='1';erase_starts<=erase_starts+1;end if;
    if wr='0' and f='1' and ca=x"400000" and di=x"D0" then confirm_commits<=confirm_commits+1;end if;
    if wr='0' and f='1' and ramsel='0' then
     ram(to_integer(unsigned(ca(15 downto 0))))<=di;
     if ca=x"7E010F" then
      assert di=x"5A" and blocked=50 and stale_seen='1' and erase_seen='1' and confirm_commits=1 and erase_starts=1 and fault='0'
        report "CPU BSX marker/credit/erase side effects failed" severity failure;
      report "PASS actual SCPU to BSX pre-R credit chain; 50 blocked clocks, stale MDR observed, D0 erase accepted once";
      stop;
     end if;
    end if;
   end if;
  end if;
 end process;
 process begin wait for 35 ns;hard<='1';rst<='1';en<='1';wait;end process;
end;
