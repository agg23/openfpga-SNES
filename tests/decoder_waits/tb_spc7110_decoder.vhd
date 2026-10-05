library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_spc7110_decoder is
  generic (MODE_ID : natural := 0; SEED : natural := 1; WORDS : positive := 256);
end;
architecture test of tb_spc7110_decoder is
  signal clk : std_logic := '0';
  signal rst, init, run_dut : std_logic := '0';
  signal run_ref : std_logic;
  signal en, valid : std_logic := '1';
  signal rd_ref, rd_dut, wr_ref, wr_dut : std_logic;
  signal di_ref, di_dut : std_logic_vector(7 downto 0);
  signal q_ref, q_dut : std_logic_vector(31 downto 0);
  signal ptr_ref, ptr_dut : natural := 0;
  signal count_ref, count_dut : natural := 0;
  signal elapsed, empty_cycles, disabled_cycles, baseline_cycles : natural := 0;
  type words_t is array(0 to WORDS-1) of std_logic_vector(31 downto 0);
  type ptrs_t is array(0 to WORDS-1) of natural;
  signal expected : words_t;
  signal expected_ptr : ptrs_t;
  function source(i : natural) return std_logic_vector is
  begin return std_logic_vector(to_unsigned((i*73 + (i/7)*19 + 165 + SEED*17) mod 256,8)); end;
begin
  clk <= not clk after 5 ns;
  run_ref <= run_dut when count_ref<WORDS else '0';
  di_ref <= source(ptr_ref);
  di_dut <= source(ptr_dut) when valid='1' else x"ED";
  ref: entity work.SPC7110_DEC_BASELINE port map(RST_N=>rst,CLK=>clk,ENABLE=>'1',DI=>di_ref,RD=>rd_ref,INIT=>init,RUN=>run_ref,MODE=>std_logic_vector(to_unsigned(MODE_ID,2)),DAT_OUT=>q_ref,WR=>wr_ref,DBG_PROB=>open,DBG_CON=>open);
  dut: entity work.SPC7110_DEC port map(RST_N=>rst,CLK=>clk,ENABLE=>en,DI=>di_dut,DI_VALID=>valid,RD=>rd_dut,INIT=>init,RUN=>run_dut,MODE=>std_logic_vector(to_unsigned(MODE_ID,2)),DAT_OUT=>q_dut,WR=>wr_dut,DBG_PROB=>open,DBG_CON=>open);
  process
  begin
    wait for 22 ns; rst<='1'; init<='1';
    wait until falling_edge(clk); wait for 1 ns; init<='0'; run_dut<='1';
    wait until count_dut=WORDS;
    report "SPC7110 PASS mode=" & integer'image(MODE_ID) & " seed=" & integer'image(SEED) & " words=" & integer'image(WORDS) & " cycles=" & integer'image(elapsed) & " baseline=" & integer'image(baseline_cycles) & " empty=" & integer'image(empty_cycles) & " disabled=" & integer'image(disabled_cycles);
    stop; wait;
  end process;
  process(clk)
    variable rng : unsigned(31 downto 0) := to_unsigned(SEED+1,32);
  begin
    if falling_edge(clk) then
      if rst='1' and init='1' then valid<='0'; end if;
      if rst='1' and init='0' then
        rng := rng xor shift_left(rng,13); rng := rng xor shift_right(rng,17); rng := rng xor shift_left(rng,5);
        if ptr_dut<4 then
          if elapsed mod 37=10 then valid<='1';else valid<='0';end if;
        elsif (elapsed mod 211) < 37 or rng(2 downto 0) < 4 then valid<='0'; else valid<='1'; end if;
        if (elapsed mod 97) < 9 or rng(5 downto 3)=0 then en<='0'; else en<='1'; end if;
      end if;
    elsif rising_edge(clk) then
      if rst='1' then
        elapsed <= elapsed+1;
        if valid='0' then empty_cycles<=empty_cycles+1; end if;
        if en='0' then disabled_cycles<=disabled_cycles+1; end if;
        assert elapsed<300000 report "Decoder deadlocked" severity failure;
        if rd_ref='1' then ptr_ref<=ptr_ref+1; end if;
        if rd_dut='1' then
          assert valid='1' and en='1' report "Unaccepted input pop" severity failure;
          ptr_dut<=ptr_dut+1;
        end if;
        if wr_ref='1' and count_ref<WORDS then
          expected(count_ref)<=q_ref; expected_ptr(count_ref)<=ptr_ref; count_ref<=count_ref+1;
          if count_ref=WORDS-1 then baseline_cycles<=elapsed+1; end if;
        end if;
        if wr_dut='1' and count_dut<WORDS then
          assert count_dut<count_ref report "DUT outran baseline" severity failure;
          assert q_dut=expected(count_dut) report "Output mismatch index=" & integer'image(count_dut) & " expected=" & to_hstring(expected(count_dut)) & " got=" & to_hstring(q_dut) severity failure;
          assert ptr_dut=expected_ptr(count_dut) report "Input byte conservation mismatch index=" & integer'image(count_dut) & " expected=" & integer'image(expected_ptr(count_dut)) & " got=" & integer'image(ptr_dut) severity failure;
          count_dut<=count_dut+1;
        end if;
      end if;
    end if;
  end process;
end;
