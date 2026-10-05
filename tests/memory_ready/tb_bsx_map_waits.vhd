library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use std.env.all;
entity tb_bsx_map_waits is generic(LATENCY:natural:=17);end;
architecture test of tb_bsx_map_waits is
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
 signal allow:std_logic:='1';signal delay_cycles:natural:=LATENCY;signal nreq,nwrite:natural:=0;
 signal waited:natural:=0;
 signal lastaddr:std_logic_vector(22 downto 0); signal lastdrain:std_logic;
 function initial(a:natural) return std_logic_vector is begin return std_logic_vector(to_unsigned((a*37 + a/256 + 93) mod 256,8));end;
begin
 clk<=not clk after 5 ns;
 process(clk) begin if rising_edge(clk) and ((ri='1' and waitr='1') or (wi='1' and waitw='1')) then waited<=waited+1;end if;end process;
 dut:entity work.BSXMap generic map(ROM_TRANSACTIONAL=>true) port map(
 MCLK=>clk,RST_N=>rst,ENABLE=>en,CA=>ca,DI=>di,DO=>dout,CPURD_N=>rd,CPUWR_N=>wr,
 PA=>pa,PARD_N=>pard,PAWR_N=>pawr,ROMSEL_N=>'0',RAMSEL_N=>'1',SYSCLKF_CE=>f,SYSCLKR_CE=>r,REFRESH=>'0',IRQ_N=>open,
 ROM_HARD_RESET_N=>hard,ROM_EPOCH=>epoch,ROM_FLUSH=>flush,ROM_FLUSH_ACK=>ack,ROM_FAULT=>fault,
 ROM_SNES_READ_INTENT=>ri,ROM_SNES_WRITE_INTENT=>wi,ROM_SNES_OWNER=>busowner,ROM_SNES_RETIRE=>ret,ROM_SNES_WRITE_DATA=>prewrite,
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
  begin for j in 0 to used-1 loop if addrs(j)=addr then return bytes(j);end if;end loop;return initial(addr);end;
  procedure setbyte(addr:natural;v:std_logic_vector(7 downto 0)) is
  begin for j in 0 to used-1 loop if addrs(j)=addr then bytes(j):=v;return;end if;end loop;
   assert used<256 severity failure;addrs(used):=addr;bytes(used):=v;used:=used+1;end;
 begin
 if hard='0' then qr<='0';sv<='0';busy:=false;nreq<=0;nwrite<=0;used:=0;
 elsif rising_edge(clk) then
  sv<='0';qr<=allow;
  if busy then qr<='0';if count=0 then sv<='1';busy:=false;else count:=count-1;end if;end if;
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
 stimulus:process
 procedure tick(n:natural:=1) is begin for k in 1 to n loop wait until rising_edge(clk);wait for 1 ns;end loop;end;
 procedure idle is begin ri<='0';wi<='0';ret<='0';rd<='1';wr<='1';r<='0';f<='0';tick(3);end;
 procedure readbus(address:natural;expected:std_logic_vector(7 downto 0);hold:natural:=0) is
 variable cycles:natural:=0;
 begin ca<=std_logic_vector(to_unsigned(address,24));ri<='1';rd<='1';tick;
 while waitr='1' loop tick;cycles:=cycles+1;assert cycles<3000 report "read deadlock" severity failure;end loop;
 tick(hold);rd<='0';r<='1';tick;r<='0';tick(2);
 assert dout=expected report "BSX read mismatch address="&integer'image(address)&" got="&to_hstring(dout)&" expected="&to_hstring(expected) severity failure;
 f<='1';ret<='1';tick;idle;
 end;
 procedure writebus(address:natural;v:std_logic_vector(7 downto 0)) is
 variable cycles:natural:=0;
 begin ca<=std_logic_vector(to_unsigned(address,24));di<=v;prewrite<=v;wi<='1';tick;
 while waitw='1' loop tick;cycles:=cycles+1;assert cycles<3000 report "write deadlock" severity failure;end loop;
 wr<='0';r<='1';tick;r<='0';tick(2);f<='1';ret<='1';tick;
 ri<='0';wi<='0';ret<='0';rd<='1';wr<='1';r<='0';f<='0';
 end;
 variable before:natural;variable oldreq:natural;
 begin
 tick(3);hard<='1';rst<='1';en<='1';tick(5);
 -- BIOS even, odd, repeated and a mapped bank boundary, captured lane result.
 readbus(16#008000#,initial(0),20);readbus(16#008001#,initial(1));readbus(16#008001#,initial(1));
 readbus(16#018000#,initial(16#8000#));
 -- Save RAM and RTC/MMIO do not consume SDRAM.
 before:=nreq;readbus(16#105000#,x"A6");assert nreq=before severity failure;
 -- Default HiROM PSRAM at 70:0000; posted write then immediate read must see new byte.
 writebus(16#700001#,x"12");writebus(16#700005#,x"9A");readbus(16#700005#,x"9A");readbus(16#700001#,x"12");
 writebus(16#700000#,x"34");readbus(16#700000#,x"34");readbus(16#700001#,x"12");
 -- Old write captured at F but not admitted: reset/mapping change may not drop it.
 allow<='0';tick(3);before:=nwrite;
 writebus(16#700003#,x"56");flush<='1';rst<='0';mapctrl<=x"00";tick(10);
 assert ack='0' report "posted write incorrectly flush-acked before admission" severity failure;
 assert qv='1' and qd='1' and qw='1' report "posted write did not remain drainable" severity failure;
 allow<='1';for i in 0 to 100 loop tick;exit when ack='1';end loop;
 assert ack='1' and nwrite=before+1 report "posted write lost/duplicated on flush" severity failure;
 epoch<=x"02";mapctrl<=x"30";rst<='1';flush<='0';tick(5);readbus(16#700003#,x"56");
 -- Enable DataPak writes, commit MCC map registers. Default 40:0000 is DataPak.
 writebus(16#0C5000#,x"80");writebus(16#0E5000#,x"80");
 readbus(16#400001#,initial(16#100001#));
 before:=nwrite;writebus(16#400001#,x"40");writebus(16#400001#,x"0F");
 -- Permit internal program to finish independently of all SCPU strobes.
 tick(150);assert nwrite=before+1 report "DataPak program did not finish independently" severity failure;
 readbus(16#400001#,initial(16#100001#) and x"0F");
 -- Status/vendor results bypass memory, including when normal requests cannot enter.
 allow<='0';tick(4);before:=nreq;
 writebus(16#400000#,x"75");readbus(16#407F00#,x"4D");
 writebus(16#400000#,x"71");readbus(16#400002#,x"C0");
 assert nreq=before report "status/vendor read allocated SDRAM" severity failure;
 allow<='1';writebus(16#400000#,x"FF");
 -- Buffered response survives pause, without duplicate requests.
 ca<=x"008007";ri<='1';tick;while waitr='1' loop tick;end loop;
 en<='0';oldreq:=nreq;tick(30);assert nreq=oldreq and waitr='0' severity failure;
 en<='1';rd<='0';r<='1';tick;r<='0';tick(2);assert dout=initial(7) severity failure;
 f<='1';ret<='1';tick;idle;
 -- Cancel an accepted read, drain its exact response before a new epoch.
 ca<=x"008009";ri<='1';tick;while qv/='1' loop tick;end loop;
 while qr/='1' loop tick;end loop;tick;
 flush<='1';rst<='0';ri<='0';tick;
 assert ack='0' report "accepted read flush barrier released early" severity failure;
 for i in 0 to 100 loop tick;exit when ack='1';end loop;
 assert ack='1' report "accepted read did not drain" severity failure;
 epoch<=x"03";rst<='1';flush<='0';tick(4);readbus(16#008009#,initial(9));
 -- CPU query data is independent of stale MDR/DI before R; DMA/HDMA
 -- cannot know their B-bus source byte yet and must reserve worst-case credit.
 writebus(16#0C5000#,x"80");writebus(16#0E5000#,x"80");
 writebus(16#400000#,x"FF");allow<='0';tick(3);
 writebus(16#400011#,x"40");writebus(16#400011#,x"0F");tick(3);
 writebus(16#400000#,x"20");
 ca<=x"400011";prewrite<=x"D0";di<=x"70";wi<='1';tick(3);
 assert waitw='1' report "CPU_CREDIT used stale bus DI instead of prewrite data" severity failure;
 prewrite<=x"70";tick;assert waitw='0' report "CPU status command unnecessarily stalled" severity failure;
 busowner<="01";tick;assert waitw='1' report "DMA_CREDIT allowed unknown source byte while flash busy" severity failure;
 busowner<="10";tick;assert waitw='1' report "HDMA_CREDIT allowed unknown source byte while flash busy" severity failure;
 wi<='0';busowner<="00";allow<='1';tick(150);
 writebus(16#400000#,x"70");readbus(16#400000#,x"80");
 -- Hard PLL reset removes both transport and posted obligation. This bench's
 -- memory is cleared too; mounted-image validity is tested at cart/queue level.
 allow<='0';tick(3);writebus(16#700007#,x"BC");flush<='1';rst<='0';tick(2);
 hard<='0';tick(3);assert qv='0' and fault='0' report "hard reset retained transport" severity failure;
 hard<='1';allow<='1';epoch<=x"00";rst<='1';flush<='0';tick(5);
 readbus(16#00800A#,initial(10));
 assert fault='0' report "unexpected BSX protocol fault" severity failure;
 report "PASS BSX actual mapper BIOS/PSRAM/DataPak/status/posted-drain/pause latency="&integer'image(LATENCY)&" wait_cycles="&integer'image(waited) severity note;stop;
 end process;
end;
