library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_sdd1_legacy is end;
architecture test of tb_sdd1_legacy is
    signal clk : std_logic := '0';
    signal rst, en, r, f : std_logic := '0';
    signal ca : std_logic_vector(23 downto 0) := (others=>'0');
    signal di, q0, q1 : std_logic_vector(7 downto 0) := (others=>'0');
    signal rd, wr, sel, oe0, oe1 : std_logic := '1';
    signal a0,a1 : std_logic_vector(23 downto 0);
    signal word : std_logic_vector(15 downto 0);
    signal cycle : natural := 0;
    function byte(a:natural) return std_logic_vector is
    begin return std_logic_vector(to_unsigned((a*73+(a/17)*11) mod 256,8)); end;
begin
    clk<=not clk after 5 ns;
    word<=byte(to_integer(unsigned(a0(22 downto 1)&'0'))+1)&byte(to_integer(unsigned(a0(22 downto 1)&'0')));
    ref: entity work.SDD1_Baseline port map(RST_N=>rst,CLK=>clk,ENABLE=>en,CA=>ca,DO=>q0,DI=>di,
        CPURD_N=>rd,CPUWR_N=>wr,ROMSEL_N=>sel,SYSCLKF_CE=>f,SYSCLKR_CE=>r,ROM_A=>a0,ROM_DO=>word,ROM_RD_N=>oe0);
    dut: entity work.SDD1 generic map(ROM_HANDSHAKE=>false)
        port map(RST_N=>rst,CLK=>clk,ENABLE=>en,CA=>ca,DO=>q1,DI=>di,
        CPURD_N=>rd,CPUWR_N=>wr,ROMSEL_N=>sel,SYSCLKF_CE=>f,SYSCLKR_CE=>r,ROM_A=>a1,ROM_DO=>word,ROM_RD_N=>oe1,
        SNES_ROM_ADDR=>open,DEC_ROM_ADDR=>open,DEC_ROM_NEED=>open,DEC_ROM_RETIRE=>open,DATA_WAIT=>open,DECOMP_READ=>open);
    process
        procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure write_reg(a,v:natural) is
        begin ca<=std_logic_vector(to_unsigned(a,24));di<=std_logic_vector(to_unsigned(v,8));wr<='0';f<='1';tick;
            wr<='1';f<='0';tick;end;
    begin
        tick; tick; rst<='1'; en<='1'; tick;
        write_reg(16#4302#,255);write_reg(16#4303#,15);write_reg(16#4304#,192);
        write_reg(16#4305#,0);write_reg(16#4306#,1);write_reg(16#4800#,1);write_reg(16#4801#,1);
        ca<=x"C00FFF";
        for i in 0 to 29999 loop
            r<='0';f<='0';rd<='1';sel<='1';en<='1';
            if i mod 8=0 then r<='1'; end if;
            if i mod 8=4 then f<='1'; end if;
            if i>200 and i mod 80<8 then rd<='0';sel<='0'; end if;
            if i mod 97>=20 and i mod 97<=23 then en<='0'; end if;
            tick;
        end loop;
        report "PASS legacy generic=false matches immutable b63f800 ROM address, read timing and byte output for 30000 clocks";
        stop;
    end process;
    process
    begin
        wait until rising_edge(clk); wait for 2 ns;
        if rst='1' then
            assert a0=a1 report "legacy address changed" severity failure;
            assert oe0=oe1 report "legacy OE changed" severity failure;
            assert q0=q1 report "legacy output changed" severity failure;
        end if;
    end process;
end;
