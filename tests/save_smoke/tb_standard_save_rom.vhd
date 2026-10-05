-- SPDX-License-Identifier: GPL-3.0-or-later
-- Actual unmodified SCPU/P65 executes the generated ROM. This is intentionally
-- a simple asynchronous WRAM/SRAM and PPU-register fixture, NOT a full console,
-- save transport, mapper, SDRAM/PSRAM, scanout, vendor model or Pocket test.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;
entity tb_standard_save_rom is
    generic (ROM_FILE : string := "rom.hex"; SAVE_FILE : string := "save.hex"; OUTPUT_FILE : string := "output.hex";
             EXPECT_COLOR : natural := 0; EXPECT_WRITES : natural := 0;
             EXPECT_READ_ALL : boolean := false; EXPECT_WRITE_ALL : boolean := false;
             REQUIRED_READ : integer := -1; TURBO_MODE : boolean := false);
end;
architecture test of tb_standard_save_rom is
    subtype byte_t is std_logic_vector(7 downto 0);
    type memory_t is array(natural range <>) of byte_t;
    impure function load_hex(name : string; size : natural) return memory_t is
        file f : text open read_mode is name;
        variable row : line;
        variable value : byte_t;
        variable memory : memory_t(0 to size-1);
    begin
        for i in memory'range loop
            assert not endfile(f) report "fixture input too short" severity failure;
            readline(f, row); hread(row, value); memory(i) := value;
        end loop;
        assert endfile(f) report "fixture input too long" severity failure;
        return memory;
    end;
    constant rom : memory_t(0 to 32767) := load_hex(ROM_FILE, 32768);
    signal sram : memory_t(0 to 2047) := load_hex(SAVE_FILE, 2048);
    signal wram : memory_t(0 to 8191) := (others => x"00");
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal ca : std_logic_vector(23 downto 0);
    signal pa, di, data_out : byte_t;
    signal rd, wr, prd, pwr, f, r, refresh, turbo : std_logic;
    signal hb : std_logic := '0';
    signal cycles : natural := 0;
begin
    clk <= not clk after 5 ns;
    reset_n <= '1' after 40 ns;
    turbo <= '1' when TURBO_MODE else '0';
    cpu : entity work.SCPU port map(
        CLK=>clk, RST_N=>reset_n, ENABLE=>'1', BUS_WAIT=>'0', BUS_WRITE_WAIT=>'0',
        CA=>ca, CPURD_N=>rd, CPUWR_N=>wr, PA=>pa, PARD_N=>prd, PAWR_N=>pwr,
        DI=>di, DO=>data_out, RAMSEL_N=>open, ROMSEL_N=>open, JPIO67=>open,
        REFRESH=>refresh, SYSCLK=>open, SYSCLKF_CE=>f, SYSCLKR_CE=>r,
        HBLANK=>hb, VBLANK=>'0', IRQ_N=>'1', JOY1_DI=>"11", JOY2_DI=>"11",
        JOY_STRB=>open, JOY1_CLK=>open, JOY2_CLK=>open, SNI_JOY=>open,
        TURBO=>turbo, SS_BUSY=>'0', DBG_CPU_EN=>'1');

    memory_read : process(all)
        variable bank, address : natural;
    begin
        bank := to_integer(unsigned(ca(23 downto 16)));
        address := to_integer(unsigned(ca(15 downto 0)));
        di <= x"FF";
        if bank = 0 and address >= 32768 then di <= rom(address-32768);
        elsif (bank = 0 or bank = 16#7E#) and address < 8192 then di <= wram(address);
        elsif bank = 16#70# and address < 2048 then di <= sram(address);
        end if;
    end process;

    monitor : process(clk)
        type seen_t is array(0 to 2047) of boolean;
        variable read_seen, write_seen : seen_t := (others=>false);
        variable reads, writes, refreshes, read_unique, write_unique : natural := 0;
        variable palette, palette_index, color_byte_count : natural := 0;
        variable low_byte : byte_t := x"00";
        variable high_next : boolean := false;
        variable blanked, complete : boolean := false;
        variable completion_cycle, completion_writes : natural := 0;
        variable bank, address, paddress : natural;
        file output : text open write_mode is OUTPUT_FILE;
        variable row : line;
    begin
        if rising_edge(clk) then
            cycles <= cycles + 1;
            if cycles mod 1364 >= 1096 then hb <= '1'; else hb <= '0'; end if;
            if reset_n='1' then
                assert cycles < 1800000 report "ROM execution timeout" severity failure;
                if refresh='1' then refreshes := refreshes + 1; end if;
                bank := to_integer(unsigned(ca(23 downto 16)));
                address := to_integer(unsigned(ca(15 downto 0)));
                paddress := to_integer(unsigned(pa));
                if f='1' then
                    if bank = 16#70# and (rd='0' or wr='0') then
                        assert address<2048 report "SRAM address exceeds $70:07FF" severity failure;
                        if rd='0' then
                            reads := reads + 1; read_seen(address) := true;
                        end if;
                        if wr='0' then
                            assert not complete report "SRAM write after displayed result" severity failure;
                            if writes=0 and EXPECT_READ_ALL then
                                for i in 0 to 2047 loop
                                    assert read_seen(i) report "SRAM changed before complete read/validation at " & integer'image(i) severity failure;
                                end loop;
                            end if;
                            writes := writes + 1; write_seen(address) := true;
                            sram(address) <= data_out;
                        end if;
                    end if;
                    if wr='0' and (bank=0 or bank=16#7E#) and address<8192 then wram(address)<=data_out; end if;
                    if pwr='0' then
                        assert blanked or (paddress=0 and data_out=x"80")
                            report "PPU programmed outside forced blank" severity failure;
                        if paddress=0 then
                            if data_out=x"80" then blanked:=true;
                            elsif data_out=x"0F" then
                                assert color_byte_count>=2 and palette_index=1
                                    report "backdrop color not fully written to CGRAM entry zero" severity failure;
                                assert palette=EXPECT_COLOR report "unexpected backdrop color" severity failure;
                                assert writes=EXPECT_WRITES report "unexpected SRAM write count" severity failure;
                                if REQUIRED_READ>=0 then
                                    assert read_seen(REQUIRED_READ) report "required boundary address was not read" severity failure;
                                end if;
                                for i in 0 to 2047 loop
                                    if read_seen(i) then read_unique:=read_unique+1; end if;
                                    if write_seen(i) then write_unique:=write_unique+1; end if;
                                    if EXPECT_READ_ALL then assert read_seen(i) report "missing SRAM read address " & integer'image(i) severity failure; end if;
                                    if EXPECT_WRITE_ALL then assert write_seen(i) report "missing SRAM write address " & integer'image(i) severity failure; end if;
                                end loop;
                                assert refreshes>0 report "SCPU refresh not exercised" severity failure;
                                complete:=true; completion_cycle:=cycles; completion_writes:=writes;
                            else assert false report "unexpected INIDISP value" severity failure;
                            end if;
                        elsif paddress=16#21# then
                            palette_index:=to_integer(unsigned(data_out)); high_next:=false; color_byte_count:=0;
                        elsif paddress=16#22# then
                            if not high_next then low_byte:=data_out; high_next:=true;
                            else
                                assert data_out(7)='0' report "invalid 15-bit color" severity failure;
                                if palette_index=0 then palette:=to_integer(unsigned(data_out(6 downto 0)))*256+to_integer(unsigned(low_byte)); end if;
                                palette_index:=(palette_index+1) mod 256; high_next:=false;
                            end if;
                            color_byte_count:=color_byte_count+1;
                        elsif paddress=16#2C# or paddress=16#2D# or paddress=16#30# or paddress=16#31# then
                            assert data_out=x"00" report "layers/color math must be disabled" severity failure;
                        end if;
                    end if;
                end if;
                if complete and cycles=completion_cycle+2000 then
                    assert writes=completion_writes report "SRAM changed while idle" severity failure;
                    for i in 0 to 2047 loop hwrite(row,sram(i)); writeline(output,row); end loop;
                    report "PASS actual SCPU/P65 save ROM color=" & integer'image(palette) &
                        " writes=" & integer'image(writes) & " reads=" & integer'image(reads) &
                        " read_unique=" & integer'image(read_unique) & " write_unique=" & integer'image(write_unique) &
                        " refresh_sys=" & integer'image(refreshes) & " cycles=" & integer'image(cycles);
                    stop;
                end if;
            end if;
        end if;
    end process;
end;
