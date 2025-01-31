library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;
library work;

entity bit_adder is
	port(
		A		: in std_logic;
		B		: in std_logic;
		CI		: in std_logic;
		S		: out std_logic;
		CO		: out std_logic
	);
end bit_adder;

architecture rtl of bit_adder is
	
begin
				
	S <= (not A and not B and     CI) or
		  (not A and     B and not CI) or
		  (    A and not B and not CI) or
		  (    A and     B and     CI);
		  
	CO <= (not A and     B and     CI) or
			(    A and not B and     CI) or
			(    A and     B and not CI) or
			(    A and     B and     CI);

end rtl;



library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;
library work;

entity adder4 is
	port(
		A		: in std_logic_vector(3 downto 0);
		B		: in std_logic_vector(3 downto 0);
		CI		: in std_logic;
		S		: out std_logic_vector(3 downto 0);
		CO		: out std_logic
	);
end adder4;

architecture rtl of adder4 is

	component bit_adder is
	port(
		A		: in std_logic;
		B		: in std_logic;
		CI		: in std_logic;
		S		: out std_logic;
		CO		: out std_logic
	);
	end component;
	
	signal CO0, CO1, CO2 : std_logic;

begin
				
	b_add0: bit_adder port map (A(0), B(0), CI,  S(0), CO0);
	b_add1: bit_adder port map (A(1), B(1), CO0, S(1), CO1);
	b_add2: bit_adder port map (A(2), B(2), CO1, S(2), CO2);
	b_add3: bit_adder port map (A(3), B(3), CO2, S(3), CO); 

end rtl;


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;
library work;

entity BCDAdder is
	port(
		A		: in std_logic_vector(3 downto 0);
		B		: in std_logic_vector(3 downto 0);
		CI		: in std_logic;
		
		S		: out std_logic_vector(3 downto 0);
		CO		: out std_logic;
		VO		: out std_logic;
		
		ADD	: in std_logic;
		BCD	: in std_logic
	);
end BCDAdder;

architecture rtl of BCDAdder is

	signal B2 		: std_logic_vector(3 downto 0);
	signal BIN_S 	: std_logic_vector(3 downto 0);
	signal BIN_CO 	: std_logic;
	signal BCD_B 	: std_logic_vector(3 downto 0);
	signal BCD_CO 	: std_logic;

begin
				
	B2 <= B xor (3 downto 0 => not ADD);
	
	bin_adder : entity work.adder4
	port map(
		A		=> A,
		B		=> B2,
		CI		=> CI,
		S		=> BIN_S,
		CO		=> BIN_CO
	);
	

	BCD_CO <= (((BIN_S(3) and BIN_S(2)) or (BIN_S(3) and BIN_S(1))) and ADD) or (not (BIN_CO xor ADD));
	BCD_B <= not ADD & ((BCD_CO and BCD) xor not ADD) & ((BCD_CO and BCD) xor not ADD) & not ADD;
	
	bcd_corr_adder : entity work.adder4
	port map(
		A		=> BIN_S,
		B		=> BCD_B,
		CI		=> not ADD,
		S		=> S
	);
	
	CO <= BIN_CO when BCD = '0' else BCD_CO xor not ADD;
	VO <= (not (A(3) xor B2(3))) and (A(3) xor BIN_S(3));

end rtl;
