library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;


entity OBC1 is
	port(
		CLK			: in std_logic;
		RST_N			: in std_logic;
		ENABLE		: in std_logic;
		
		CA   			: in std_logic_vector(23 downto 0);
		DI				: in std_logic_vector(7 downto 0);
		CPURD_N		: in std_logic;
		CPUWR_N		: in std_logic;
		
		SYSCLKF_CE	: in std_logic;
		
		CS				: in std_logic;
						
		SRAM_A      : out std_logic_vector(12 downto 0);
		SRAM_DI		: in std_logic_vector(7 downto 0);
		SRAM_DO		: out std_logic_vector(7 downto 0)
	);
end OBC1;

architecture rtl of OBC1 is

	signal BASE			: std_logic;
	signal INDEX 		: std_logic_vector(6 downto 0);
	
	signal SRAM_ADDR 	: std_logic_vector(12 downto 0);
	
begin
		
	process( RST_N, CLK)
	begin
		if RST_N = '0' then
			INDEX <= (others => '0');
			BASE <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' and SYSCLKF_CE = '1' then
				if CPUWR_N = '0' and CS = '1' and CA(15 downto 4) = x"7FF" then 
					case CA(3 downto 0) is
						when x"5" =>
							BASE<= DI(0);
						when x"6" =>
							INDEX <= DI(6 downto 0);
						when others => null;
					end case; 
				end if;
			end if;
		end if;
	end process; 
	
	process( CA, BASE, INDEX )
	begin
		if CA(12 downto 3) = "1111111110" then	--7FF0-7FF7
			case CA(3 downto 0) is
				when x"0" | x"1" | x"2" | x"3" =>
					SRAM_ADDR <= "11" & not BASE & "0" & INDEX & CA(1 downto 0);
				when x"4" =>
					SRAM_ADDR <= "11" & not BASE & "1" & "0000" & INDEX(6 downto 2);
				when others =>
					SRAM_ADDR <= CA(12 downto 0);
			end case;
		else
			SRAM_ADDR <= CA(12 downto 0);
		end if;
	end process; 
	SRAM_A <= SRAM_ADDR;
	
	process( CA, DI, INDEX, SRAM_DI)
	begin
		if CA(12 downto 0) = "1111111110100" then	--7FF4
			case INDEX(1 downto 0) is
				when "00" =>
					SRAM_DO <= SRAM_DI(7 downto 2) & DI(1 downto 0);
				when "01" =>
					SRAM_DO <= SRAM_DI(7 downto 4) & DI(1 downto 0) & SRAM_DI(1 downto 0);
				when "10" =>
					SRAM_DO <= SRAM_DI(7 downto 6) & DI(1 downto 0) & SRAM_DI(3 downto 0);
				when others =>
					SRAM_DO <=                       DI(1 downto 0) & SRAM_DI(5 downto 0);
			end case;
		else
			SRAM_DO <= DI;
		end if;
	end process; 

end rtl;
