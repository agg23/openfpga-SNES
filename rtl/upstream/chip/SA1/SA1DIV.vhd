-- ============================================================================
--
-- SA1DIV.vhd
-- (C) 2026 Alexey Melnikov
--
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

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

ARCHITECTURE rtl OF SA1DIV IS

	SIGNAL dividend_neg : STD_LOGIC := '0';
	SIGNAL denom_r      : UNSIGNED(16 DOWNTO 0) := (OTHERS => '0');
	SIGNAL cnt          : UNSIGNED(1 DOWNTO 0)  := (OTHERS => '0');

BEGIN

	PROCESS (clock)
		VARIABLE Q : UNSIGNED(15 DOWNTO 0);
		VARIABLE R : UNSIGNED(16 DOWNTO 0);
	BEGIN
		IF rising_edge(clock) THEN
			R := R(15 DOWNTO 0) & Q(15);
			IF R >= denom_r THEN
				R := R - denom_r;
				Q := Q(14 DOWNTO 0) & '1';
			ELSE
				Q := Q(14 DOWNTO 0) & '0';
			END IF;

			R := R(15 DOWNTO 0) & Q(15);
			IF R >= denom_r THEN
				R := R - denom_r;
				Q := Q(14 DOWNTO 0) & '1';
			ELSE
				Q := Q(14 DOWNTO 0) & '0';
			END IF;

			R := R(15 DOWNTO 0) & Q(15);
			IF R >= denom_r THEN
				R := R - denom_r;
				Q := Q(14 DOWNTO 0) & '1';
			ELSE
				Q := Q(14 DOWNTO 0) & '0';
			END IF;

			R := R(15 DOWNTO 0) & Q(15);
			IF R >= denom_r THEN
				R := R - denom_r;
				Q := Q(14 DOWNTO 0) & '1';
			ELSE
				Q := Q(14 DOWNTO 0) & '0';
			END IF;

			cnt <= cnt + 1;
			IF cnt = 0 THEN
				IF dividend_neg = '1' THEN
					quotient <= STD_LOGIC_VECTOR((NOT Q) + 1);
				ELSE
					quotient <= STD_LOGIC_VECTOR(Q);
				END IF;

				remain   <= STD_LOGIC_VECTOR(R(15 DOWNTO 0));

				-- new round
				dividend_neg <= numer(15);
				IF numer(15) = '1' THEN
					Q := (NOT UNSIGNED(numer)) + 1;
				ELSE
					Q := UNSIGNED(numer);
				END IF;

				R       := (OTHERS => '0');
				denom_r <= UNSIGNED('0' & denom);
			END IF;
		END IF;
	END PROCESS;

END rtl;