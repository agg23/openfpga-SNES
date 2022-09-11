library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;

entity SRTC is
	port(
		CLK			: in std_logic;

		A0   			: in std_logic;
		DI				: in std_logic_vector(7 downto 0);
		DO				: out std_logic_vector(7 downto 0);
		CS				: in std_logic;
		CPURD_N		: in std_logic;
		CPUWR_N		: in std_logic;

		SYSCLKF_CE	: in std_logic;

		EXT_RTC     : in std_logic_vector(64 downto 0)
	);
end SRTC;

architecture rtl of SRTC is

	type regs_t is array(0 to 12) of std_logic_vector(3 downto 0);
	signal REGS  : regs_t;

	signal INDEX : integer range 0 to 15 := 15;
	signal MODE  : integer range 0 to 3 := 0;
	
	signal SEC_DIV  	: integer := 0;
	signal SEC_TICK 	: std_logic := '0';
	signal LAST_RTC64 : std_logic := '0';
	
	type LastDayOfMonth_t is array(0 to 12) of std_logic_vector(7 downto 0);
	constant DAYS_TBL	: LastDayOfMonth_t := (
	x"31",--not use
	x"31",--01
	x"28",--02
	x"31",--03
	x"30",--04
	x"31",--05
	x"30",--06
	x"31",--07
	x"31",--08
	x"30",--09
	x"31",--10
	x"30",--11
	x"31" --12
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
	
	process( CLK)
	variable DAY_OF_MONTH_L : std_logic_vector(3 downto 0);
	variable DAY_OF_MONTH_H : std_logic_vector(3 downto 0);
	begin
		if rising_edge(CLK) then
			DAY_OF_MONTH_H := DAYS_TBL(to_integer(unsigned(REGS(8))))(7 downto 4);
			DAY_OF_MONTH_L := DAYS_TBL(to_integer(unsigned(REGS(8))))(3 downto 0);
			
			if SEC_TICK = '1' then
				REGS(0) <= std_logic_vector( unsigned(REGS(0)) + 1 );	--sec low inc
				if REGS(0) = x"9" then
					REGS(0) <= (others => '0');
					REGS(1) <= std_logic_vector( unsigned(REGS(1)) + 1 );	--sec high inc
					if REGS(1) = x"5" then
						REGS(1) <= (others => '0');
						REGS(2) <= std_logic_vector( unsigned(REGS(2)) + 1 );	--min low inc
						if REGS(2) = x"9" then
							REGS(2) <= (others => '0');
							REGS(3) <= std_logic_vector( unsigned(REGS(3)) + 1 );	--min high inc
							if REGS(3) = x"5" then
								REGS(3) <= (others => '0');
								REGS(4) <= std_logic_vector( unsigned(REGS(4)) + 1 );	--hour low inc
								if REGS(4) = x"9" and REGS(5) <= x"2" then
									REGS(4) <= (others => '0');
									REGS(5) <= std_logic_vector( unsigned(REGS(5)) + 1 );	--hour high inc
								elsif REGS(4) = x"3" and REGS(5) = x"2" then
									REGS(4) <= (others => '0');
									REGS(5) <= (others => '0');
									REGS(6) <= std_logic_vector( unsigned(REGS(6)) + 1 );	--day low inc
									if REGS(6) = x"9" and REGS(7)(1 downto 0) <= x"2" then
										REGS(6) <= (others => '0');
										REGS(7) <= std_logic_vector( unsigned(REGS(7)) + 1 );	--day high inc
									elsif REGS(6) = DAY_OF_MONTH_L and REGS(7) = DAY_OF_MONTH_H then
										REGS(6) <= x"1";
										REGS(7) <= (others => '0');
										REGS(8) <= std_logic_vector( unsigned(REGS(8)) + 1 );	--month inc
										if REGS(8) = x"C" then
											REGS(8) <= x"1";
											REGS(9) <= std_logic_vector( unsigned(REGS(9)) + 1 );	--year low inc
											if REGS(9) = x"9" then
												REGS(9) <= (others => '0');
												REGS(10) <= std_logic_vector( unsigned(REGS(10)) + 1 );	--year high inc
												if REGS(10) = x"9" then
													REGS(10) <= (others => '0');
													REGS(11) <= std_logic_vector( unsigned(REGS(11)) + 1 );	--century inc
													if REGS(11) = x"C" then
														REGS(11) <= (others => '0');
													end if;
												end if;
											end if;
										end if;
									end if;
									REGS(12) <= std_logic_vector( unsigned(REGS(12)) + 1 );	--weeks inc
									if REGS(12) = x"6" then
										REGS(12) <= (others => '0');
									end if;
								end if;
							end if;
						end if;
					end if;
				end if;
			end if;
			
			if EXT_RTC(64) /= LAST_RTC64 then
				LAST_RTC64 <= EXT_RTC(64);
				REGS(0) <= EXT_RTC(3 downto 0);
				REGS(1) <= EXT_RTC(7 downto 4);
				REGS(2) <= EXT_RTC(11 downto 8);
				REGS(3) <= EXT_RTC(15 downto 12);
				REGS(4) <= EXT_RTC(19 downto 16);
				REGS(5) <= EXT_RTC(23 downto 20);
				REGS(6) <= EXT_RTC(27 downto 24);
				REGS(7) <= EXT_RTC(31 downto 28);
				if EXT_RTC(36) = '0' then
					REGS(8) <= EXT_RTC(35 downto 32);
				else
					REGS(8) <= std_logic_vector( unsigned(EXT_RTC(35 downto 32)) + 10 );
				end if;
				REGS(9) <= EXT_RTC(43 downto 40);
				REGS(10) <= EXT_RTC(47 downto 44);
				REGS(11) <= x"A";
				REGS(12) <= EXT_RTC(51 downto 48);
			end if;
			
			if CS = '1' and SYSCLKF_CE = '1' then
				if CPUWR_N = '0' and A0 = '1' then
					if DI(3 downto 0) = x"D" then
						INDEX <= 15;
						MODE <= 0;
					elsif DI(3 downto 0) = x"E" then
						MODE <= 1;
					else
						if MODE = 1 then
							case DI(3 downto 0) is
								when x"0" => 
									MODE <= 2;
									INDEX <= 0;
								when others =>
									MODE <= 3;
							end case;
						elsif MODE = 2 then
							if INDEX < 12 then
								REGS(INDEX) <= DI(3 downto 0);
								INDEX <= INDEX + 1;
							end if;
						end if;
					end if;
				end if;

				if CPURD_N = '0' and A0 = '0' then
					if MODE = 0 then
						if INDEX = 13 then
							INDEX <= 15;
						else
							INDEX <= INDEX + 1;
						end if;
					end if;
				end if;
			end if;
		end if;
	end process;
	
	DO <=  x"0" & REGS(INDEX) when INDEX <= 12 else x"0F";

end rtl;
