LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

-- Hardware accurate SNES SA-1 arithmetic-unit divider (sign-magnitude division).
-- Based on the SA-1 reverse engineering effort by Vitor Vilela, his test rom and the
-- validation table on sneslab.net.

LIBRARY lpm;
USE lpm.all;

ENTITY SA1DIV IS
	PORT
	(
		clock    : IN  STD_LOGIC ;
		denom    : IN  STD_LOGIC_VECTOR (15 DOWNTO 0);
		numer    : IN  STD_LOGIC_VECTOR (15 DOWNTO 0);
		quotient : OUT STD_LOGIC_VECTOR (15 DOWNTO 0);
		remain   : OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
	);
END SA1DIV;


ARCHITECTURE SYN OF sa1div IS

	SIGNAL sub_wire0 : STD_LOGIC_VECTOR (15 DOWNTO 0);
	SIGNAL srem      : STD_LOGIC_VECTOR (15 DOWNTO 0);
	SIGNAL sub_wire1 : STD_LOGIC_VECTOR (15 DOWNTO 0);


	COMPONENT lpm_divide
	GENERIC (
		lpm_drepresentation : STRING;
		lpm_hint            : STRING;
		lpm_nrepresentation : STRING;
		lpm_pipeline        : NATURAL;
		lpm_type            : STRING;
		lpm_widthd          : NATURAL;
		lpm_widthn          : NATURAL
	);
	PORT (
			clock    : IN  STD_LOGIC ;
			remain   : OUT STD_LOGIC_VECTOR (15 DOWNTO 0);
			denom    : IN  STD_LOGIC_VECTOR (15 DOWNTO 0);
			numer    : IN  STD_LOGIC_VECTOR (15 DOWNTO 0);
			quotient : OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
	);
	END COMPONENT;

BEGIN
	srem     <= sub_wire0 when denom /= x"0000" else numer;
	remain   <= std_logic_vector(abs(signed(srem)));
	quotient <= sub_wire1 when denom /= x"0000" else x"FFFF" when numer(15) = '0' else x"0001";

	LPM_DIVIDE_component : LPM_DIVIDE
	GENERIC MAP (
		lpm_drepresentation => "UNSIGNED",
		lpm_nrepresentation => "SIGNED",
		lpm_hint     => "LPM_REMAINDERPOSITIVE=TRUE",
		lpm_pipeline => 6,
		lpm_type     => "LPM_DIVIDE",
		lpm_widthd   => 16,
		lpm_widthn   => 16
	)
	PORT MAP (
		clock    => clock,
		denom    => denom,
		numer    => numer,
		remain   => sub_wire0,
		quotient => sub_wire1
	);

END SYN;
