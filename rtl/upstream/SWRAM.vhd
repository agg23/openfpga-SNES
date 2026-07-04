library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;

entity SWRAM is
	port(
		CLK			: in std_logic;
		SYSCLK_CE	: in std_logic;
		RST_N			: in std_logic;
		ENABLE		: in std_logic;
		
		CA       	: in std_logic_vector(23 downto 0);
		CPURD_N		: in std_logic;
		CPUWR_N		: in std_logic;
		RAMSEL_N		: in std_logic;
		
		PA				: in std_logic_vector(7 downto 0);
		PARD_N		: in std_logic;
		PAWR_N		: in std_logic;

		DI				: in std_logic_vector(7 downto 0);
		DO				: out std_logic_vector(7 downto 0);
		
		RAM_A   		: out std_logic_vector(16 downto 0);
		RAM_D 		: out std_logic_vector(7 downto 0);
		RAM_Q 		: in  std_logic_vector(7 downto 0);
		RAM_WE_N		: out std_logic;
		RAM_CE_N		: out std_logic;
		RAM_OE_N		: out std_logic
	);
end SWRAM;

architecture rtl of SWRAM is

	signal WMADD : std_logic_vector(23 downto 0);

begin
	
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			WMADD <= (others => '0');
		elsif rising_edge(CLK) then
			if ENABLE = '1' and SYSCLK_CE = '1' then
				if PAWR_N = '0' then
					case PA is
						when x"80" =>
							if RAMSEL_N = '1'  then		--check if DMA use WRAM in ABUS
								WMADD <= std_logic_vector(unsigned(WMADD) + 1);
							end if;
						when x"81" =>
							WMADD(7 downto 0) <= DI;
						when x"82" =>
							WMADD(15 downto 8) <= DI;
						when x"83" =>
							WMADD(23 downto 16) <= DI;
						when others => null;
					end case;
				elsif PARD_N = '0' then
					case PA is
						when x"80" =>
							if RAMSEL_N = '1' then		--check if DMA use WRAM in ABUS
								WMADD <= std_logic_vector(unsigned(WMADD) + 1);
							end if;
						when others => null;
					end case;
				end if;
			end if;
		end if;
	end process;
	
	DO <= RAM_Q;
	RAM_D <= x"FF" when PA = x"80" and RAMSEL_N = '0' else DI;

	RAM_A 	<= CA(16 downto 0) when RAMSEL_N = '0' else
					WMADD(16 downto 0);
					
	RAM_CE_N <= '0' when ENABLE = '0' else 
					'0' when RAMSEL_N = '0' else
					'0' when PA = x"80" else 
					'1';
					
	RAM_OE_N <= '0' when ENABLE = '0' else 
					'0' when RAMSEL_N = '0' and CPURD_N = '0' else
					'0' when PA = x"80" and PARD_N = '0' and RAMSEL_N = '1' else 
					'1';
				
	RAM_WE_N <= '1' when ENABLE = '0' else
					'0' when RAMSEL_N = '0' and CPUWR_N = '0' else
					'0' when PA = x"80" and PAWR_N = '0' and RAMSEL_N = '1' else 
					'1';
			
end rtl;

