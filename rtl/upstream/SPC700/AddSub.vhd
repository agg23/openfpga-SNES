library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.SPC700_pkg.all;

entity SPC700_AddSub is
    port( 
        A		: in std_logic_vector(7 downto 0);  
		  B		: in std_logic_vector(7 downto 0);  
		  CI		: in std_logic; 
		  ADD		: in std_logic; 
        S		: out std_logic_vector(7 downto 0);
        CO		: out std_logic;
		  VO		: out std_logic;
		  HO		: out std_logic
    );
end SPC700_AddSub;

architecture rtl of SPC700_AddSub is

	signal tempB : std_logic_vector(7 downto 0);
	signal res : unsigned(7 downto 0);
	signal C7 : std_logic;
	
begin

	tempB <= B when ADD = '1' else B xor x"FF";

	process(A, tempB, CI, ADD)
		variable temp0, temp1 : unsigned(4 downto 0);
	begin
		temp0 := ('0' & unsigned(A(3 downto 0))) + ('0' & unsigned(tempB(3 downto 0))) + ("0000" & CI);
		temp1 := ('0' & unsigned(A(7 downto 4))) + ('0' & unsigned(tempB(7 downto 4))) + ("0000" & temp0(4));
		
		res <= temp1(3 downto 0) & temp0(3 downto 0);
		C7 <= temp1(4);
	end process;
	
	S <= std_logic_vector(res);
	VO <= (not (A(7) xor tempB(7))) and (A(7) xor res(7));
	HO <= (A(4) xor B(4) xor res(4)) xor not ADD;
	CO <= C7;

end rtl;