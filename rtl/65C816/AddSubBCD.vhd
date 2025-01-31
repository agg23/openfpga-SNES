library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.P65816_pkg.all;

entity AddSubBCD is
	port( 
		A		: in std_logic_vector(15 downto 0); 
		B		: in std_logic_vector(15 downto 0); 
		CI		: in std_logic;
		ADD	: in std_logic;
		BCD	: in std_logic; 
		w16	: in std_logic; 
		S		: out std_logic_vector(15 downto 0);
		CO		: out std_logic;
		VO		: out std_logic
    );
end AddSubBCD;

architecture rtl of AddSubBCD is

	signal VO1, VO3 : std_logic;
	signal CO0, CO1, CO2, CO3 : std_logic;

begin
	
	add0 : entity work.BCDAdder
	port map (
		A => A(3 downto 0),
		B => B(3 downto 0),
		CI => CI,
		
		S => S(3 downto 0),
		CO => CO0,
		
		ADD => ADD,
		BCD => BCD
	);
	
	add1 : entity work.BCDAdder
	port map (
		A => A(7 downto 4),
		B => B(7 downto 4),
		CI => CO0,
		
		S => S(7 downto 4),
		CO => CO1,
		VO => VO1,
		
		ADD => ADD,
		BCD => BCD
	);
	
	add2 : entity work.BCDAdder
	port map (
		A => A(11 downto 8),
		B => B(11 downto 8),
		CI => CO1,
		
		S => S(11 downto 8),
		CO => CO2,
		
		ADD => ADD,
		BCD => BCD
	);
	
	add3 : entity work.BCDAdder
	port map (
		A => A(15 downto 12),
		B => B(15 downto 12),
		CI => CO2,
		
		S => S(15 downto 12),
		CO => CO3,
		VO => VO3,
		
		ADD => ADD,
		BCD => BCD
	);
	
	
	VO <= VO1 when w16 = '0' else VO3;
	CO <= CO1 when w16 = '0' else CO3;

end rtl;