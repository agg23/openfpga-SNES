LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY lpm;
USE lpm.all;

ENTITY SPC7110_UMULT IS
	PORT
	(
		dataa		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		datab		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		result		: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
END SPC7110_UMULT;


ARCHITECTURE SYN OF SPC7110_UMULT IS

	SIGNAL sub_wire0	: STD_LOGIC_VECTOR (31 DOWNTO 0);



	COMPONENT lpm_mult
	GENERIC (
		lpm_hint		: STRING;
		lpm_representation		: STRING;
		lpm_type		: STRING;
		lpm_widtha		: NATURAL;
		lpm_widthb		: NATURAL;
		lpm_widthp		: NATURAL
	);
	PORT (
			dataa	: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
			datab	: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
			result	: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
	END COMPONENT;

BEGIN
	result    <= sub_wire0(31 DOWNTO 0);

	lpm_mult_component : lpm_mult
	GENERIC MAP (
		lpm_hint => "MAXIMIZE_SPEED=5",
		lpm_representation => "UNSIGNED",
		lpm_type => "LPM_MULT",
		lpm_widtha => 16,
		lpm_widthb => 16,
		lpm_widthp => 32
	)
	PORT MAP (
		dataa => dataa,
		datab => datab,
		result => sub_wire0
	);



END SYN;

---------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY lpm;
USE lpm.all;

ENTITY SPC7110_SMULT IS
	PORT
	(
		dataa		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		datab		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		result		: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
END SPC7110_SMULT;


ARCHITECTURE SYN OF SPC7110_SMULT IS

	SIGNAL sub_wire0	: STD_LOGIC_VECTOR (31 DOWNTO 0);



	COMPONENT lpm_mult
	GENERIC (
		lpm_hint		: STRING;
		lpm_representation		: STRING;
		lpm_type		: STRING;
		lpm_widtha		: NATURAL;
		lpm_widthb		: NATURAL;
		lpm_widthp		: NATURAL
	);
	PORT (
			dataa	: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
			datab	: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
			result	: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
	END COMPONENT;

BEGIN
	result    <= sub_wire0(31 DOWNTO 0);

	lpm_mult_component : lpm_mult
	GENERIC MAP (
		lpm_hint => "MAXIMIZE_SPEED=5",
		lpm_representation => "SIGNED",
		lpm_type => "LPM_MULT",
		lpm_widtha => 16,
		lpm_widthb => 16,
		lpm_widthp => 32
	)
	PORT MAP (
		dataa => dataa,
		datab => datab,
		result => sub_wire0
	);



END SYN;

---------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY lpm;
USE lpm.all;

ENTITY SPC7110_UDIV IS
	PORT
	(
		clock		: IN STD_LOGIC ;
		denom		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		numer		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		quotient		: OUT STD_LOGIC_VECTOR (31 DOWNTO 0);
		remain		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
	);
END SPC7110_UDIV;


ARCHITECTURE SYN OF SPC7110_UDIV IS

	SIGNAL sub_wire0	: STD_LOGIC_VECTOR (15 DOWNTO 0);
	SIGNAL sub_wire1	: STD_LOGIC_VECTOR (31 DOWNTO 0);



	COMPONENT lpm_divide
	GENERIC (
		lpm_drepresentation		: STRING;
		lpm_hint		: STRING;
		lpm_nrepresentation		: STRING;
		lpm_pipeline		: NATURAL;
		lpm_type		: STRING;
		lpm_widthd		: NATURAL;
		lpm_widthn		: NATURAL
	);
	PORT (
			clock	: IN STD_LOGIC ;
			remain	: OUT STD_LOGIC_VECTOR (15 DOWNTO 0);
			denom	: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
			numer	: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			quotient	: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
	END COMPONENT;

BEGIN
	remain    <= sub_wire0(15 DOWNTO 0);
	quotient    <= sub_wire1(31 DOWNTO 0);

	LPM_DIVIDE_component : LPM_DIVIDE
	GENERIC MAP (
		lpm_drepresentation => "UNSIGNED",
		lpm_hint => "LPM_REMAINDERPOSITIVE=TRUE",
		lpm_nrepresentation => "UNSIGNED",
		lpm_pipeline => 8,
		lpm_type => "LPM_DIVIDE",
		lpm_widthd => 16,
		lpm_widthn => 32
	)
	PORT MAP (
		clock => clock,
		denom => denom,
		numer => numer,
		remain => sub_wire0,
		quotient => sub_wire1
	);



END SYN;

---------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY lpm;
USE lpm.all;

ENTITY SPC7110_SDIV IS
	PORT
	(
		clock		: IN STD_LOGIC ;
		denom		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		numer		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		quotient		: OUT STD_LOGIC_VECTOR (31 DOWNTO 0);
		remain		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
	);
END SPC7110_SDIV;


ARCHITECTURE SYN OF SPC7110_SDIV IS

	SIGNAL sub_wire0	: STD_LOGIC_VECTOR (15 DOWNTO 0);
	SIGNAL sub_wire1	: STD_LOGIC_VECTOR (31 DOWNTO 0);



	COMPONENT lpm_divide
	GENERIC (
		lpm_drepresentation		: STRING;
		lpm_hint		: STRING;
		lpm_nrepresentation		: STRING;
		lpm_pipeline		: NATURAL;
		lpm_type		: STRING;
		lpm_widthd		: NATURAL;
		lpm_widthn		: NATURAL
	);
	PORT (
			clock	: IN STD_LOGIC ;
			remain	: OUT STD_LOGIC_VECTOR (15 DOWNTO 0);
			denom	: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
			numer	: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			quotient	: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
	END COMPONENT;

BEGIN
	remain    <= sub_wire0(15 DOWNTO 0);
	quotient    <= sub_wire1(31 DOWNTO 0);

	LPM_DIVIDE_component : LPM_DIVIDE
	GENERIC MAP (
		lpm_drepresentation => "SIGNED",
		lpm_hint => "LPM_REMAINDERPOSITIVE=TRUE",
		lpm_nrepresentation => "SIGNED",
		lpm_pipeline => 8,
		lpm_type => "LPM_DIVIDE",
		lpm_widthd => 16,
		lpm_widthn => 32
	)
	PORT MAP (
		clock => clock,
		denom => denom,
		numer => numer,
		remain => sub_wire0,
		quotient => sub_wire1
	);



END SYN;
