library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;
library work;

entity RTC4513 is
	port(
		CLK			: in std_logic;
		ENABLE		: in std_logic;
		
		DO				: out std_logic_vector(3 downto 0);
		DI				: in std_logic_vector(3 downto 0);
		CE				: in std_logic;
		CK				: in std_logic;
		
		EXT_RTC		: in std_logic_vector(64 downto 0)
	);
end RTC4513;

architecture rtl of RTC4513 is

	type Regs_t is array(0 to 15) of std_logic_vector(3 downto 0);
	signal REGS  		: Regs_t := (x"0",x"0",x"0",x"0",x"0",x"0",x"1",x"0",x"1",x"0",x"0",x"0",x"0",x"2",x"F",x"4");
	signal INDEX  		: unsigned(3 downto 0) := (others => '0');
	signal REG_WR  	: std_logic := '0';
	signal STATE  		: std_logic_vector(1 downto 0) := (others => '0');
	signal CK_OLD 		: std_logic := '0';
	signal CE_OLD 		: std_logic := '0';
	signal LAST_HOLD 	: std_logic := '0';
	signal LAST_RTC64 : std_logic := '0';
	signal SEC_DIV  	: integer := 0;
	signal SEC_TICK 	: std_logic := '0';
	
	type LastDayOfMonth_t is array(0 to 18) of std_logic_vector(5 downto 0);
	constant DAYS_TBL	: LastDayOfMonth_t := (
	"110001",--not use
	"110001",--01
	"101000",--02
	"110001",--03
	"110000",--04
	"110001",--05
	"110000",--06
	"110001",--07
	"110001",--08
	"110000",--09
	"110001",--not use
	"110001",--not use
	"110001",--not use
	"110001",--not use
	"110001",--not use
	"110001",--not use
	"110001",--10
	"110000",--11
	"110001"	--12
	);

begin

	process( CLK)
	begin
		if rising_edge(CLK) then
			SEC_TICK <= '0';
			
			SEC_DIV <= SEC_DIV + 1;
			if SEC_DIV = 21477270-1 then
				SEC_DIV <= 0;
				SEC_TICK <= '1';
			end if;
		end if;
	end process;
				
	process( CLK )
	variable DAY_OF_MONTH_L : std_logic_vector(3 downto 0);
	variable DAY_OF_MONTH_H : std_logic_vector(1 downto 0);
	begin
		if rising_edge(CLK) then
			DAY_OF_MONTH_H := DAYS_TBL(to_integer(unsigned(REGS(9)(0)&REGS(8))))(5 downto 4);
			DAY_OF_MONTH_L := DAYS_TBL(to_integer(unsigned(REGS(9)(0)&REGS(8))))(3 downto 0);

			LAST_HOLD <= REGS(13)(0);
			if (SEC_TICK = '1' and REGS(13)(0) = '0' and REGS(15)(1) = '0') or (LAST_HOLD = '1' and REGS(13)(0) = '0') then
				REGS(0) <= std_logic_vector( unsigned(REGS(0)) + 1 );	--sec low inc
				if REGS(0) = x"9" then
					REGS(0) <= (others => '0');
					REGS(1)(2 downto 0) <= std_logic_vector( unsigned(REGS(1)(2 downto 0)) + 1 );	--sec high inc
					if REGS(1)(2 downto 0) = "101" then
						REGS(1)(2 downto 0) <= (others => '0');
						REGS(2) <= std_logic_vector( unsigned(REGS(2)) + 1 );	--min low inc
						if REGS(2) = x"9" then
							REGS(2) <= (others => '0');
							REGS(3)(2 downto 0) <= std_logic_vector( unsigned(REGS(3)(2 downto 0)) + 1 );	--min high inc
							if REGS(3)(2 downto 0) = "101" then
								REGS(3)(2 downto 0) <= (others => '0');
								REGS(4) <= std_logic_vector( unsigned(REGS(4)) + 1 );	--hour low inc
								if REGS(4) = x"9" and REGS(5)(1 downto 0) <= "01" then
									REGS(4) <= (others => '0');
									REGS(5)(1 downto 0) <= std_logic_vector( unsigned(REGS(5)(1 downto 0)) + 1 );	--hour high inc
								elsif REGS(4) = x"3" and REGS(5)(1 downto 0) = "10" then
									REGS(4) <= (others => '0');
									REGS(5)(1 downto 0) <= (others => '0');
									if REGS(13)(1) = '1' then	--CAL/HW
										REGS(6) <= std_logic_vector( unsigned(REGS(6)) + 1 );	--day low inc
										if REGS(6) = x"9" and REGS(7)(1 downto 0) <= "10" then
											REGS(6) <= (others => '0');
											REGS(7)(1 downto 0) <= std_logic_vector( unsigned(REGS(7)(1 downto 0)) + 1 );	--day high inc
										elsif REGS(6) = DAY_OF_MONTH_L and REGS(7)(1 downto 0) = DAY_OF_MONTH_H then
											REGS(6) <= x"1";
											REGS(7)(1 downto 0) <= (others => '0');
											REGS(8) <= std_logic_vector( unsigned(REGS(8)) + 1 );	--month low inc
											if REGS(8) = x"9" and REGS(9)(0) <= '0' then
												REGS(8) <= (others => '0');
												REGS(9)(0) <= '1';												--month high inc
											elsif REGS(8) = x"2" and REGS(9)(0) <= '1' then
												REGS(8) <= x"1";
												REGS(9)(0) <= '0';
												REGS(10) <= std_logic_vector( unsigned(REGS(10)) + 1 );	--year low inc
												if REGS(10) = x"9" then
													REGS(10) <= (others => '0');
													REGS(11) <= std_logic_vector( unsigned(REGS(11)) + 1 );	--year high inc
													if REGS(11) = x"9" then
														REGS(11) <= (others => '0');
													end if;
												end if;
											end if;
										end if;
									end if;
									REGS(12)(2 downto 0) <= std_logic_vector( unsigned(REGS(12)(2 downto 0)) + 1 );	--weeks inc
									if REGS(12) = x"6" then
										REGS(12)(2 downto 0) <= (others => '0');
									end if;
								end if;
							end if;
						end if;
					end if;
				end if;
			end if;
			
			if REGS(13)(0) = '0' and REGS(15)(1) = '0' then
				if EXT_RTC(64) /= LAST_RTC64 then
					LAST_RTC64 <= EXT_RTC(64);
					REGS(0) <= EXT_RTC(3 downto 0);
					REGS(1) <= EXT_RTC(7 downto 4);
					REGS(2) <= EXT_RTC(11 downto 8);
					REGS(3) <= EXT_RTC(15 downto 12);
					REGS(4) <= EXT_RTC(19 downto 16);
					REGS(5) <= EXT_RTC(23 downto 20);
					if REGS(13)(1) = '1' then	--CAL/HW
						REGS(6) <= EXT_RTC(27 downto 24);
						REGS(7) <= EXT_RTC(31 downto 28);
						REGS(8) <= EXT_RTC(35 downto 32);
						REGS(9) <= EXT_RTC(39 downto 36);
						REGS(10) <= EXT_RTC(43 downto 40);
						REGS(11) <= EXT_RTC(47 downto 44);
					end if;
					REGS(12) <= EXT_RTC(51 downto 48);
				end if;
			end if;
				
			if ENABLE = '1' then
				CE_OLD <= CE;
				if CE = '0' and CE_OLD = '1' then
					REG_WR <= '0';
					STATE <= (others => '0');
					REGS(3)(3) <= '0';
					REGS(5)(3) <= '0';
					if REGS(13)(1) = '1' then
						REGS(7)(3) <= '0';
						REGS(9)(3) <= '0';
					end if;
					REGS(12)(3) <= '0';
					if REGS(15)(0) = '1' then
						REGS(0) <= (others => '0');
						REGS(1) <= (others => '0');
						REGS(15)(0) <= '0';
					end if;
				end if;
				
				CK_OLD <= CK;
				if CK = '1' and CK_OLD = '0' and CE = '1' then
					case STATE is
						when "00" =>
							if DI = x"3" then
								REG_WR <= '1';
							end if;
							STATE <= "01";
							
						when "01" =>
							INDEX <= unsigned(DI);
							STATE <= "10";
							
						when "10" =>
							if REG_WR = '1' then
								REGS(to_integer(INDEX)) <= DI;
							end if;
							INDEX <= INDEX + 1;
						
						when others => null;
					end case; 
				end if;
				
				DO <= REGS(to_integer(INDEX));
			end if;
		end if;
	end process; 

end rtl;
