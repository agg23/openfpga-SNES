-- Behavioral primitives only: the tests compile the complete production chip
-- RTL. No chip FSM, counter, bus decoder or transaction logic is modeled here.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity spram is
 generic(addr_width:integer:=8; data_width:integer:=8; mem_init_file:string:=""; mem_name:string:="");
 port(clock:in std_logic; address:in std_logic_vector(addr_width-1 downto 0); data:in std_logic_vector(data_width-1 downto 0):=(others=>'0'); enable:in std_logic:='1'; wren:in std_logic:='0'; q:out std_logic_vector(data_width-1 downto 0); cs:in std_logic:='1');
end; architecture sim of spram is begin process(clock) begin if rising_edge(clock) and enable='1' and cs='1' then q<=(others=>'0'); end if; end process; end;
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity dpram_difclk is
 generic(addr_width_a:integer:=8; data_width_a:integer:=8; addr_width_b:integer:=8; data_width_b:integer:=8; mem_init_file:string:="");
 port(clock0:in std_logic; address_a:in std_logic_vector(addr_width_a-1 downto 0); data_a:in std_logic_vector(data_width_a-1 downto 0):=(others=>'0'); enable_a:in std_logic:='1'; wren_a:in std_logic:='0'; q_a:out std_logic_vector(data_width_a-1 downto 0); cs_a:in std_logic:='1'; clock1:in std_logic; address_b:in std_logic_vector(addr_width_b-1 downto 0); data_b:in std_logic_vector(data_width_b-1 downto 0):=(others=>'0'); enable_b:in std_logic:='1'; wren_b:in std_logic:='0'; q_b:out std_logic_vector(data_width_b-1 downto 0); cs_b:in std_logic:='1');
end; architecture sim of dpram_difclk is
 type ram_t is array(0 to 2**addr_width_a-1) of std_logic_vector(data_width_a-1 downto 0);
 signal ram:ram_t:=(others=>(others=>'0'));
begin
 assert data_width_a=data_width_b and addr_width_a=addr_width_b severity failure;
 process(clock0,clock1) begin
 if rising_edge(clock0) and enable_a='1' and cs_a='1' then
  q_a<=ram(to_integer(unsigned(address_a))); if wren_a='1' then ram(to_integer(unsigned(address_a)))<=data_a; end if;
 end if;
 if rising_edge(clock1) and enable_b='1' and cs_b='1' then
  q_b<=ram(to_integer(unsigned(address_b))); if wren_b='1' then ram(to_integer(unsigned(address_b)))<=data_b; end if;
 end if;
 end process;
end;
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity cx4cache is port(clock:in std_logic; data:in std_logic_vector(7 downto 0); rdaddress,wraddress:in std_logic_vector(8 downto 0); wren:in std_logic:='0'; q:out std_logic_vector(7 downto 0)); end;
architecture sim of cx4cache is type ram_t is array(0 to 511) of std_logic_vector(7 downto 0); signal ram:ram_t:=(others=>(others=>'0')); begin
 process(clock) begin if rising_edge(clock) and wren='1' then ram(to_integer(unsigned(wraddress)))<=data; end if; end process;
 q<=ram(to_integer(unsigned(rdaddress)));
end;
