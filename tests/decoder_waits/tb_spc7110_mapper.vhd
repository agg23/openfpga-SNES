library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_spc7110_mapper is generic(MODE_ID:natural:=0; DELAY_MAX:positive:=211; OFFSET_WORDS:natural:=0); end;
architecture test of tb_spc7110_mapper is
 signal clk:std_logic:='0';
 signal rst,hard,flush,en:std_logic:='0';
 signal epoch:std_logic_vector(7 downto 0):=x"01";
 signal ca:std_logic_vector(23 downto 0):=(others=>'0');
 signal di,q:std_logic_vector(7 downto 0):=(others=>'0');
 signal rd,wr:std_logic:='1';
 signal ce_f,ce_r,intent,retire,wait_rom,ack,fault:std_logic:='0';
 signal owner:std_logic_vector(1 downto 0):="00";
 signal req_v,req_r,rsp_v,rsp_r,rsp_e:std_logic:='0';
 signal req_a:std_logic_vector(22 downto 0);
 signal req_o,req_s,rsp_o:std_logic_vector(1 downto 0):="00";
 signal req_t,req_e,rsp_t,rsp_epoch:std_logic_vector(7 downto 0):=(others=>'0');
 signal rsp_d:std_logic_vector(15 downto 0):=(others=>'0');
 signal pause_mem,force_error,bad_reply:std_logic:='0';
 signal requests,replies,cpu_requests,dec_requests,wait_cycles,cycles:natural:=0;
 signal snes_seen:std_logic_vector(3 downto 0):="0000";
 signal crossed_low,crossed_high:std_logic:='0';
 signal ref_rst,ref_init,ref_run,ref_rd,ref_wr:std_logic:='0';
 signal ref_di:std_logic_vector(7 downto 0);
 signal ref_q:std_logic_vector(31 downto 0);
 signal ref_ptr,ref_count:natural:=0;
 type golden_t is array(0 to 511) of std_logic_vector(7 downto 0);
 signal golden:golden_t;
 constant STREAM:natural:=16#00fff8#;
 function byte_at(a:natural) return std_logic_vector is
 begin
  if a>=16#100000# and a<16#100004# then
   case a-16#100000# is
    when 0=>return std_logic_vector(to_unsigned(MODE_ID,8));
    when 1=>return std_logic_vector(to_unsigned(STREAM/65536,8));
    when 2=>return std_logic_vector(to_unsigned((STREAM/256) mod 256,8));
    when others=>return std_logic_vector(to_unsigned(STREAM mod 256,8));
   end case;
  end if;
  return std_logic_vector(to_unsigned((a*73+(a/7)*19+165) mod 256,8));
 end;
begin
 clk<=not clk after 5 ns;
 dut:entity work.SPC7110Map generic map(ROM_HANDSHAKE=>true) port map(
  MCLK=>clk,RST_N=>rst,ENABLE=>en,CA=>ca,DI=>di,DO=>q,CPURD_N=>rd,CPUWR_N=>wr,
  PA=>x"00",PARD_N=>'1',PAWR_N=>'1',ROMSEL_N=>'0',RAMSEL_N=>'1',SYSCLKF_CE=>ce_f,SYSCLKR_CE=>ce_r,REFRESH=>'0',IRQ_N=>open,
  ROM_ADDR=>open,ROM_Q=>x"DEAD",ROM_CE_N=>open,ROM_OE_N=>open,ROM_WORD=>open,
  BSRAM_ADDR=>open,BSRAM_D=>open,BSRAM_Q=>x"00",BSRAM_CE_N=>open,BSRAM_OE_N=>open,BSRAM_WE_N=>open,
  MAP_ACTIVE=>open,MAP_CTRL=>x"D0",ROM_MASK=>x"7FFFFF",BSRAM_MASK=>x"000FFF",EXT_RTC=>(others=>'0'),
  ROM_HARD_RESET_N=>hard,ROM_EPOCH=>epoch,ROM_FLUSH=>flush,ROM_FLUSH_ACK=>ack,ROM_FAULT=>fault,
  ROM_SNES_READ_INTENT=>intent,ROM_SNES_OWNER=>owner,ROM_SNES_RETIRE=>retire,ROM_SNES_WAIT=>wait_rom,
  ROM_REQ_VALID=>req_v,ROM_REQ_READY=>req_r,ROM_REQ_ADDR=>req_a,ROM_REQ_OWNER=>req_o,ROM_REQ_SNES_OWNER=>req_s,ROM_REQ_TAG=>req_t,ROM_REQ_EPOCH=>req_e,
  ROM_RSP_VALID=>rsp_v,ROM_RSP_READY=>rsp_r,ROM_RSP_DATA=>rsp_d,ROM_RSP_OWNER=>rsp_o,ROM_RSP_TAG=>rsp_t,ROM_RSP_EPOCH=>rsp_epoch,ROM_RSP_ERROR=>rsp_e);
 ref_di<=byte_at(16#100000#+STREAM+ref_ptr);
 reference:entity work.SPC7110_DEC_BASELINE port map(RST_N=>ref_rst,CLK=>clk,ENABLE=>'1',DI=>ref_di,RD=>ref_rd,INIT=>ref_init,RUN=>ref_run,MODE=>std_logic_vector(to_unsigned(MODE_ID,2)),DAT_OUT=>ref_q,WR=>ref_wr,DBG_PROB=>open,DBG_CON=>open);
 process(clk)
  variable p:natural;
  variable b0,b1,b2,b3:std_logic_vector(7 downto 0);
 begin
  if rising_edge(clk) and ref_rst='1' then
   if ref_rd='1' then ref_ptr<=ref_ptr+1; end if;
   if ref_wr='1' and ref_count<128 then
    if MODE_ID=0 then golden(ref_count)<=ref_q(7 downto 0);
    elsif MODE_ID=1 then
     for i in 0 to 7 loop b0(i):=ref_q(i*2+1);b1(i):=ref_q(i*2);end loop;
     golden(ref_count*2)<=b0;golden(ref_count*2+1)<=b1;
    else
     for i in 0 to 7 loop b0(i):=ref_q(i*4+3);b1(i):=ref_q(i*4+2);b2(i):=ref_q(i*4+1);b3(i):=ref_q(i*4);end loop;
     p:=(ref_count/8)*32+(ref_count mod 8)*2;
     golden(p)<=b0;golden(p+1)<=b1;golden(p+16)<=b2;golden(p+17)<=b3;
    end if;
    ref_count<=ref_count+1;
   end if;
  end if;
 end process;
 process(clk,hard)
  variable pending:boolean:=false;
  variable delay:natural:=0;
  variable n:natural:=0;
  variable held_a:std_logic_vector(22 downto 0);
  variable held_o,held_s:std_logic_vector(1 downto 0);
  variable held_t,held_e:std_logic_vector(7 downto 0);
  variable stalled:boolean:=false;
  variable stable_payload:std_logic_vector(42 downto 0);
 begin
  if hard='0' then pending:=false;rsp_v<='0';req_r<='0';delay:=0;stalled:=false;
  elsif rising_edge(clk) then
   cycles<=cycles+1;
   assert cycles<500000 report "Mapper deadlock" severity failure;
   if wait_rom='1' then wait_cycles<=wait_cycles+1;end if;
   if stalled and flush='0' then
    assert req_v='1' and req_a & req_o & req_s & req_t & req_e=stable_payload report "Request changed under backpressure" severity failure;
   end if;
   stalled:=req_v='1' and req_r='0';
   stable_payload:=req_a & req_o & req_s & req_t & req_e;
   if rsp_v='1' and rsp_r='1' then
    rsp_v<='0';
    if rsp_o=held_o and rsp_t=held_t then pending:=false;replies<=replies+1;end if;
   end if;
   if req_v='1' and req_r='1' then
    assert not pending report "Multiple physical requests" severity failure;
    pending:=true;delay:=5+(n*37 mod DELAY_MAX);n:=n+1;
    held_a:=req_a;held_o:=req_o;held_s:=req_s;held_t:=req_t;held_e:=req_e;
    requests<=requests+1;
    if req_o="00" then
     cpu_requests<=cpu_requests+1;snes_seen(to_integer(unsigned(req_s)))<='1';
     assert req_s=owner report "SNES subowner not retained" severity failure;
    else
     dec_requests<=dec_requests+1;
     if unsigned(req_a)=16#10FFFE# then crossed_low<='1';end if;
     if unsigned(req_a)=16#110000# then crossed_high<='1';end if;
    end if;
   end if;
   if pending and rsp_v='0' and bad_reply='1' then
    rsp_v<='1';rsp_o<="11";rsp_t<=not held_t;rsp_epoch<=held_e;rsp_e<='0';rsp_d<=x"BAD0";
   elsif pending and rsp_v='0' and pause_mem='0' then
    if delay>0 then delay:=delay-1;else
     rsp_v<='1';rsp_o<=held_o;rsp_t<=held_t;rsp_epoch<=held_e;rsp_e<=force_error;
     rsp_d<=byte_at(to_integer(unsigned(held_a))+1)&byte_at(to_integer(unsigned(held_a)));
    end if;
   end if;
   if not pending and cycles mod 7/=0 and pause_mem='0' then req_r<='1';else req_r<='0';end if;
  end if;
 end process;
 process
  procedure tick is begin wait until rising_edge(clk);wait for 1 ns;end;
  procedure write_reg(a:natural;v:natural) is begin
   wait until falling_edge(clk);ca<=std_logic_vector(to_unsigned(a,24));di<=std_logic_vector(to_unsigned(v,8));wr<='0';ce_f<='1';tick;
   wr<='1';ce_f<='0';tick;
  end;
  procedure read_byte(a:natural;expected:std_logic_vector(7 downto 0);subowner:natural:=0) is
  begin
   wait until falling_edge(clk);ca<=std_logic_vector(to_unsigned(a,24));owner<=std_logic_vector(to_unsigned(subowner,2));intent<='1';
   tick;while wait_rom='1' loop tick;end loop;
   ce_r<='1';rd<='0';tick;ce_r<='0';tick;
   assert q=expected report "CPU read mismatch address="&to_hstring(ca)&" expected="&to_hstring(expected)&" got="&to_hstring(q) severity failure;
   ce_f<='1';retire<='1';tick;ce_f<='0';retire<='0';rd<='1';intent<='0';tick;
  end;
  variable before_count:natural;
 begin
  wait for 22 ns;hard<='1';rst<='1';en<='1';ref_rst<='1';ref_init<='1';
  tick;wait until falling_edge(clk);ref_init<='0';ref_run<='1';
  write_reg(16#4801#,0);write_reg(16#4802#,0);write_reg(16#4803#,0);write_reg(16#4804#,0);
  while dec_requests<4 or replies<4 loop tick;end loop;
  for i in 0 to 4 loop tick;end loop;
  if OFFSET_WORDS>0 then write_reg(16#480B#,2);end if;
  write_reg(16#4805#,OFFSET_WORDS);write_reg(16#4806#,0);
  -- Hold DROM response while independent MMIO and multiplier keep advancing.
  before_count:=requests;while requests=before_count loop tick;end loop;pause_mem<='1';
  write_reg(16#4820#,7);write_reg(16#4821#,0);write_reg(16#4824#,9);write_reg(16#4825#,0);
  for i in 0 to 40 loop tick;end loop;
  read_byte(16#482F#,x"00");read_byte(16#4828#,x"3F");read_byte(16#4829#,x"00");
  pause_mem<='0';
  if OFFSET_WORDS>0 then while ref_count<64 loop tick;end loop;end if;
  for i in 0 to 63 loop
   read_byte(16#4800#,golden(i+OFFSET_WORDS*4));
   if i mod 4=0 and OFFSET_WORDS=0 then
    read_byte(16#C01234#+((i/4) mod 2),byte_at(16#001234#+((i/4) mod 2)),(i/4) mod 4);
    read_byte(16#C01234#+((i/4) mod 2),byte_at(16#001234#+((i/4) mod 2)),(i/4+1) mod 4);
   end if;
  end loop;
  -- Data-port prefetch must wait for the matching byte, then increment once.
  write_reg(16#4811#,16#FE#);write_reg(16#4812#,16#FF#);write_reg(16#4813#,0);write_reg(16#4818#,0);
  for i in 0 to 7 loop read_byte(16#4810#,byte_at(16#10FFFE#+i));end loop;
  read_byte(16#4811#,x"06");read_byte(16#4812#,x"00");read_byte(16#4813#,x"01");
  assert fault='0' report "Unexpected bridge fault" severity failure;
  -- Force an accepted operation to survive a soft reset; it must drain, never
  -- deliver into the new epoch, even across repeated reset and enable pauses.
  pause_mem<='1';before_count:=requests;
  wait until falling_edge(clk);ca<=x"C00007";intent<='1';
  pause_mem<='0';while requests=before_count loop tick;end loop;pause_mem<='1';
  flush<='1';rst<='0';intent<='0';tick;
  assert ack='0' report "Flush acknowledged before accepted reply drained" severity failure;
  rst<='1';tick;rst<='0';en<='0';for i in 0 to 11 loop tick;end loop;
  assert ack='0' severity failure;pause_mem<='0';while ack='0' loop tick;end loop;
  epoch<=x"02";flush<='0';rst<='1';en<='1';tick;
  read_byte(16#C00007#,byte_at(7),3);
  -- Coordinated PLL loss may discard the physical command and local token.
  pause_mem<='1';before_count:=requests;ca<=x"C00009";intent<='1';pause_mem<='0';
  while requests=before_count loop tick;end loop;pause_mem<='1';hard<='0';rst<='0';intent<='0';tick;
  assert ack='1' report "Hard reset failed to clear canceled transaction" severity failure;
  hard<='1';rst<='1';pause_mem<='0';tick;read_byte(16#C00009#,byte_at(9));
  -- Wrong identity cannot release the CPU; matching error cannot retire data.
  pause_mem<='1';before_count:=requests;ca<=x"C0000B";intent<='1';pause_mem<='0';
  while requests=before_count loop tick;end loop;pause_mem<='1';bad_reply<='1';tick;bad_reply<='0';tick;tick;
  assert wait_rom='1' and fault='1' report "Mismatched reply released CPU or lacked fault" severity failure;
  force_error<='1';pause_mem<='0';while ack='0' loop tick;end loop;tick;
  assert wait_rom='1' and fault='1' report "Error response retired as data" severity failure;
  flush<='1';intent<='0';force_error<='0';tick;tick;flush<='0';epoch<=x"03";tick;
  assert fault='0' report "Flush did not clear sticky fault" severity failure;
  read_byte(16#C0000B#,byte_at(11));
  -- Unaccepted flush cancels immediately and never creates a response.
  pause_mem<='1';for i in 0 to 2 loop tick;end loop;
  ca<=x"C0000D";intent<='1';tick;tick;flush<='1';intent<='0';tick;
  assert ack='1' and req_v='0' report "Unaccepted cancellation failed" severity failure;
  flush<='0';pause_mem<='0';epoch<=x"04";tick;
  -- Decompression remains usable after reset/remount, not just CPU ROM reads.
  before_count:=dec_requests;
  write_reg(16#4801#,0);write_reg(16#4802#,0);write_reg(16#4803#,0);write_reg(16#4804#,0);
  while dec_requests<before_count+4 or ack='0' loop tick;end loop;
  for i in 0 to 4 loop tick;end loop;
  write_reg(16#4805#,0);write_reg(16#4806#,0);
  for i in 0 to 3 loop read_byte(16#4800#,golden(i));end loop;
  assert (snes_seen="1111" or OFFSET_WORDS>0) and crossed_low='1' and crossed_high='1' report "Missing subowner/bank coverage" severity failure;
  report "SPC mapper PASS mode="&integer'image(MODE_ID)&" requests="&integer'image(requests)&" cpu="&integer'image(cpu_requests)&" decoder="&integer'image(dec_requests)&" waits="&integer'image(wait_cycles)&" sys="&integer'image(cycles);
  stop;wait;
 end process;
end;
