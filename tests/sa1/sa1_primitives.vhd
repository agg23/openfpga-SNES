-- Simulation-only inference equivalents of the project's FPGA storage/math
-- primitives. SA1 and its P65C816 are compiled from the real production files.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity spram is
    generic (addr_width : positive := 11; data_width : positive := 8);
    port(clock, wren : in std_logic; data : in std_logic_vector(data_width-1 downto 0);
         q : out std_logic_vector(data_width-1 downto 0); address : in std_logic_vector(addr_width-1 downto 0));
end;
architecture simulation of spram is
    type memory is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
    signal ram : memory := (others=>(others=>'0'));
begin
    process(clock) begin
        if rising_edge(clock) then
            if wren='1' then ram(to_integer(unsigned(address)))<=data; end if;
            q<=ram(to_integer(unsigned(address)));
        end if;
    end process;
end;
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity SA1MULT is
    port(dataa, datab : in std_logic_vector(15 downto 0); result : out std_logic_vector(31 downto 0));
end;
architecture simulation of SA1MULT is
begin
    result<=std_logic_vector(signed(dataa)*signed(datab));
end;
