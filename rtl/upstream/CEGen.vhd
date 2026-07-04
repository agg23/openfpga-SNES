LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY CEGen IS
	PORT
	(
		CLK       : in  STD_LOGIC;
		RST_N     : in  STD_LOGIC;

		IN_CLK    : in  integer;
		OUT_CLK   : in  integer;

		CE        : out STD_LOGIC
	);
END CEGen;

ARCHITECTURE SYN OF CEGen IS
BEGIN
	process( RST_N, CLK )
	variable CLK_SUM : integer;
	begin
		if RST_N = '0' then
			CLK_SUM := 0;
			CE <= '0';
		elsif falling_edge(CLK) then
			CE <= '0';
			CLK_SUM := CLK_SUM + OUT_CLK;
			if CLK_SUM >= IN_CLK then
				CLK_SUM := CLK_SUM - IN_CLK;
				CE <= '1';
			end if;
		end if;
	end process;
END SYN;
