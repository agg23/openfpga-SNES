library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.SPC700_pkg.all;

entity SPC700_BCDAdj is
    port( 
        A		: in std_logic_vector(7 downto 0);   
		  ADD		: in std_logic; 
		  CI		: in std_logic; 
		  HI		: in std_logic; 
        R		: out std_logic_vector(7 downto 0);
        CO		: out std_logic
    );
end SPC700_BCDAdj;

architecture rtl of SPC700_BCDAdj is

	signal res : unsigned(7 downto 0);
	signal tempC : std_logic;
	
begin

	process(A, CI, HI, ADD)
		variable temp0, temp1 : unsigned(7 downto 0);
	begin
		temp0 := unsigned(A);
		tempC <= CI;
		
		temp1 := temp0;
		if CI = not ADD or temp0 > x"99" then
			if ADD = '0' then
				temp1 := temp0 + x"60";
			else
				temp1 := temp0 - x"60";
			end if;
			tempC <= not ADD;
		end if;
		
		res <= temp1;
		if HI = not ADD or temp1(3 downto 0) > x"9" then
			if ADD = '0' then
				res <= temp1 + x"06";
			else
				res <= temp1 - x"06";
			end if;
		end if;
	end process;
	
	R <= std_logic_vector(res);
	CO <= tempC;

end rtl;