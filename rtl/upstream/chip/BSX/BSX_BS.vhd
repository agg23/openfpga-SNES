library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;
library work;

entity BS is
	port(
		CLK			: in std_logic;
		RST_N			: in std_logic;
		ENABLE		: in std_logic;
		
		A   			: in std_logic_vector(7 downto 0);
		DI				: in std_logic_vector(7 downto 0);
		DO				: out std_logic_vector(7 downto 0);
		RD_N			: in std_logic;
		WR_N			: in std_logic;
		SYSCLKF_CE	: in std_logic;

		EXT_RTC     : in std_logic_vector(64 downto 0)
	);
end BS;

architecture rtl of BS is
	
	signal R14		: std_logic_vector(7 downto 0);
	signal R15		: std_logic_vector(7 downto 0);
	signal R17		: std_logic_vector(7 downto 0);
	signal R18		: std_logic_vector(7 downto 0);
	signal R19		: std_logic_vector(7 downto 0);
	signal R1A		: std_logic_vector(7 downto 0);
	
	type Stream_r is record
		CHANNEL		: std_logic_vector(13 downto 0);
		QUEUE			: unsigned(7 downto 0);
		SIZE			: unsigned(7 downto 0);
		QSTATUS		: std_logic_vector(7 downto 0);
		STATUS		: std_logic_vector(7 downto 0);
		OFFS			: unsigned(9 downto 0);
		STATUS_REQ	: std_logic;
		DATA_REQ		: std_logic;
	end record;
	signal STREAM1: Stream_r;
	signal STREAM2: Stream_r;
	signal STREAM1_STATUS_UPDATE : std_logic;
	signal STREAM2_STATUS_UPDATE : std_logic;
	
	type Channel_r is record
		OFFS			: unsigned(11 downto 0);
		SIZE			: unsigned(7 downto 0);
	end record;
	type ChannelList_t is array(0 to 4) of Channel_r;
	constant  CHANNEL_LIST: ChannelList_t := (
	(x"000",x"01"),--channel 0000 Time
	(x"000",x"03"),--channel 0121
	(x"042",x"0F"),--channel 0122
	(x"18C",x"02"),--channel 0123
	(x"1B8",x"05") --channel 0124
	);
	
	signal STREAM1_DATA_ADDR : std_logic_vector(9 downto 0);
	signal STREAM2_DATA_ADDR : std_logic_vector(9 downto 0);
	signal STREAM1_DATA_Q : std_logic_vector(7 downto 0);
	signal STREAM2_DATA_Q : std_logic_vector(7 downto 0);
	
	signal CONV_SEC : std_logic_vector(7 downto 0);
	signal CONV_MIN : std_logic_vector(7 downto 0);
	signal CONV_HOUR : std_logic_vector(7 downto 0);
	signal CONV_DAY : std_logic_vector(7 downto 0);
	signal CONV_MONTH : std_logic_vector(7 downto 0);
	signal CONV_WEEK : std_logic_vector(7 downto 0);
	signal CONV_YEAR : std_logic_vector(15 downto 0);
	signal SEC : std_logic_vector(7 downto 0);
	signal MIN : std_logic_vector(7 downto 0);
	signal HOUR : std_logic_vector(7 downto 0);
	signal DAY : std_logic_vector(7 downto 0);
	signal MONTH : std_logic_vector(7 downto 0);
	signal WEEK : std_logic_vector(7 downto 0);
	signal YEAR : std_logic_vector(15 downto 0);
	signal SEC_DIV  	: integer := 0;
	signal SEC_TICK 	: std_logic := '0';
	signal LAST_RTC64 : std_logic;
	
	type LastDayOfMonth_t is array(0 to 12) of std_logic_vector(7 downto 0);
	constant DAYS_TBL	: LastDayOfMonth_t := (
	x"1F",--
	x"1F",--01
	x"1D",--02
	x"1F",--03
	x"1E",--04
	x"1F",--05
	x"1E",--06
	x"1F",--07
	x"1F",--08
	x"1E",--09
	x"1F",--10
	x"1E",--11
	x"1F"	--12
	);
	
begin
	
	STREAM1_DATA_ADDR <= std_logic_vector(STREAM1.OFFS);
	STREAM2_DATA_ADDR <= std_logic_vector(STREAM2.OFFS);
	CH_DATA : entity work.dpram generic map(10, 8, "rtl/chip/BSX/bsx121-124.mif")
	port map(
		clock			=> CLK,
		address_a	=> STREAM1_DATA_ADDR,
		address_b	=> STREAM2_DATA_ADDR,
		q_a			=> STREAM1_DATA_Q,
		q_b			=> STREAM2_DATA_Q
	);
	
	process( RST_N, CLK)
		variable NEW_STREAM1_CHANNEL		: std_logic_vector(13 downto 0);
		variable NEW_STREAM2_CHANNEL		: std_logic_vector(13 downto 0);
	begin
		if RST_N = '0' then
			R14 <= (others => '0');
			R15 <= (others => '0');
			R17 <= x"FF";
			R18 <= x"80";
			R19 <= x"01";
			R1A <= x"10";
			STREAM1_STATUS_UPDATE <= '0';
			STREAM2_STATUS_UPDATE <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				if WR_N = '0' and SYSCLKF_CE = '1' then
					case A is
						when x"88" => 
							STREAM1.CHANNEL(7 downto 0) <= DI; 
						when x"89" => 
							STREAM1.CHANNEL(13 downto 8) <= DI(5 downto 0); 
							NEW_STREAM1_CHANNEL := DI(5 downto 0) & STREAM1.CHANNEL(7 downto 0);
							if NEW_STREAM1_CHANNEL = "00"&x"000" then
								STREAM1.OFFS <= (others => '0');
								STREAM1.SIZE <= x"01";
								STREAM1.QUEUE <= x"01";
								STREAM1.QSTATUS <= x"90";
								STREAM1.STATUS(4) <= '1';
								STREAM1.STATUS(7) <= '1';
							elsif NEW_STREAM1_CHANNEL >= "00"&x"121" and NEW_STREAM1_CHANNEL <= "00"&x"124" then
								STREAM1.OFFS <= CHANNEL_LIST(to_integer(unsigned(NEW_STREAM1_CHANNEL(3 downto 0)))).OFFS(9 downto 0);
								STREAM1.SIZE <= CHANNEL_LIST(to_integer(unsigned(NEW_STREAM1_CHANNEL(3 downto 0)))).SIZE;
								STREAM1.QUEUE <= CHANNEL_LIST(to_integer(unsigned(NEW_STREAM1_CHANNEL(3 downto 0)))).SIZE;
								STREAM1.QSTATUS <= x"10";
								STREAM1.STATUS(4) <= '1';
							else
								STREAM1.OFFS <= (others => '0');
								STREAM1.SIZE <= x"00";
								STREAM1.QUEUE <= x"00";
								STREAM1.QSTATUS <= x"00";
							end if;
						when x"8B" => 
							STREAM1.STATUS_REQ <= DI(0);
						when x"8C" => 
							STREAM1.DATA_REQ <= DI(0);
						when x"8E" => 
							STREAM2.CHANNEL(7 downto 0) <= DI; 
						when x"8F" => 
							STREAM2.CHANNEL(13 downto 8) <= DI(5 downto 0); 
							NEW_STREAM2_CHANNEL := DI(5 downto 0) & STREAM2.CHANNEL(7 downto 0);
							if NEW_STREAM2_CHANNEL = "00"&x"000" then
								STREAM2.OFFS <= (others => '0');
								STREAM2.SIZE <= x"01";
								STREAM2.QUEUE <= x"01";
								STREAM2.QSTATUS <= x"90";
								STREAM2.STATUS(4) <= '1';
								STREAM2.STATUS(7) <= '1';
							elsif NEW_STREAM2_CHANNEL >= "00"&x"121" and NEW_STREAM2_CHANNEL <= "00"&x"124" then
								STREAM2.OFFS <= CHANNEL_LIST(to_integer(unsigned(NEW_STREAM2_CHANNEL(3 downto 0)))).OFFS(9 downto 0);
								STREAM2.SIZE <= CHANNEL_LIST(to_integer(unsigned(NEW_STREAM2_CHANNEL(3 downto 0)))).SIZE;
								STREAM2.QUEUE <= CHANNEL_LIST(to_integer(unsigned(NEW_STREAM2_CHANNEL(3 downto 0)))).SIZE;
								STREAM2.QSTATUS <= x"10";
								STREAM2.STATUS(4) <= '1';
							else
								STREAM2.OFFS <= (others => '0');
								STREAM2.SIZE <= x"00";
								STREAM2.QUEUE <= x"00";
								STREAM2.QSTATUS <= x"00";
							end if;
						when x"91" => 
							STREAM2.STATUS_REQ <= DI(0);
						when x"92" => 
							STREAM2.DATA_REQ <= DI(0);
						when x"94" => R14 <= DI;
						when x"95" => R15 <= DI;
						when x"97" => R17 <= DI;
						when x"98" => R18 <= DI;
						when x"99" => R19 <= DI;
						when x"9A" => R1A <= DI;
						when others => null;
					end case;
				elsif RD_N = '0' and SYSCLKF_CE = '1' then
					case A is
						when x"8A" =>
							if STREAM1.CHANNEL >= "00"&x"121" and STREAM1.CHANNEL <= "00"&x"124" then
								STREAM1.OFFS <= CHANNEL_LIST(to_integer(unsigned(STREAM1.CHANNEL(3 downto 0)))).OFFS(9 downto 0);
							else
								STREAM1.OFFS <= (others => '0');
							end if;
						when x"8B" =>
							if STREAM1.STATUS_REQ = '1' then
								STREAM1.QUEUE <= STREAM1.QUEUE - 1;
								STREAM1_STATUS_UPDATE <= '1';
							end if;
						when x"8C" => 
							if STREAM1.DATA_REQ = '1' then
								STREAM1.OFFS <= STREAM1.OFFS + 1;
							end if;
						when x"8D" => 
							STREAM1.STATUS <= (others => '0');
						when x"90" =>
							if STREAM2.CHANNEL >= "00"&x"121" and STREAM2.CHANNEL <= "00"&x"124" then
								STREAM2.OFFS <= CHANNEL_LIST(to_integer(unsigned(STREAM2.CHANNEL(3 downto 0)))).OFFS(9 downto 0);
							else
								STREAM2.OFFS <= (others => '0');
							end if;
						when x"91" =>
							if STREAM2.STATUS_REQ = '1' then
								STREAM2.QUEUE <= STREAM2.QUEUE - 1;
								STREAM2_STATUS_UPDATE <= '1';
							end if;
						when x"92" =>
							if STREAM2.DATA_REQ = '1' then
								STREAM2.OFFS <= STREAM2.OFFS + 1;
							end if;
						when x"93" =>
							STREAM2.STATUS <= (others => '0');
						when others => null;
					end case;
				end if;
				
				if STREAM1_STATUS_UPDATE = '1' then
					STREAM1_STATUS_UPDATE <= '0';
					STREAM1.QSTATUS <= x"00";
					if STREAM1.SIZE > 0  then
						if STREAM1.QUEUE = 1 then
							STREAM1.QSTATUS(7) <= '1';
							STREAM1.STATUS(7) <= '1';
						end if;
					end if;
				end if;
				
				if STREAM2_STATUS_UPDATE = '1' then
					STREAM2_STATUS_UPDATE <= '0';
					STREAM2.QSTATUS <= x"00";
					if STREAM2.SIZE > 0 then
						if STREAM2.QUEUE = 1 then
							STREAM2.QSTATUS(7) <= '1';
							STREAM2.STATUS(7) <= '1';
						end if;
					end if;
				end if;
			end if;
		end if;
	end process;
	
	process( RST_N, CLK)
	begin
		if RST_N = '0' then
			DO <= (others => '0');
		elsif rising_edge(CLK) then
			if RD_N = '0' then 
				case A is
					when x"88" => 
						DO <= STREAM1.CHANNEL(7 downto 0);
					when x"89" => 
						DO <= "00" & STREAM1.CHANNEL(13 downto 8);
					when x"8A" => 
						if STREAM1.STATUS_REQ = '0' or STREAM1.DATA_REQ = '0' then
							DO <= x"00";
						else
							DO <= std_logic_vector(STREAM1.QUEUE);
						end if;
					when x"8B" => 
						if STREAM1.STATUS_REQ = '0' then
							DO <= x"00";
						else
							DO <= STREAM1.QSTATUS;
						end if;
					when x"8C" =>
						if STREAM1.DATA_REQ = '0' then
							DO <= x"00";
						elsif STREAM1.CHANNEL = "00"&x"000" then
							case to_integer(STREAM1.OFFS) is
								when 4 => DO <= x"10";
								when 5 => DO <= x"01";
								when 6 => DO <= x"01";
								when 10 => DO <= SEC;
								when 11 => DO <= MIN;
								when 12 => DO <= HOUR;
								when 13 => DO <= WEEK;
								when 14 => DO <= DAY;
								when 15 => DO <= MONTH;
								when 16 => DO <= YEAR(7 downto 0);
								when 17 => DO <= YEAR(15 downto 8);
								when others => DO <= (others => '0');
							end case;
						elsif STREAM1.CHANNEL >= "00"&x"121" and STREAM1.CHANNEL <= "00"&x"124" then
							DO <= STREAM1_DATA_Q;
						else
							DO <= x"00";
						end if;
					when x"8D" =>
						DO <= STREAM1.STATUS;
					when x"8E" => 
						DO <= STREAM2.CHANNEL(7 downto 0);
					when x"8F" => 
						DO <= "00" & STREAM2.CHANNEL(13 downto 8);
					when x"90" => 
						if STREAM2.STATUS_REQ = '0' or STREAM2.DATA_REQ = '0' then
							DO <= x"00";
						else
							DO <= std_logic_vector(STREAM2.QUEUE);
						end if;
					when x"91" =>
						if STREAM2.STATUS_REQ = '0' then
							DO <= x"00";
						else
							DO <= STREAM2.QSTATUS;
						end if;
					when x"92" =>
						if STREAM2.DATA_REQ = '0' then
							DO <= x"00";
						elsif STREAM2.CHANNEL = "00"&x"000" then
							case to_integer(STREAM2.OFFS) is
								when 4 => DO <= x"10";
								when 5 => DO <= x"01";
								when 6 => DO <= x"01";
								when 10 => DO <= SEC;
								when 11 => DO <= MIN;
								when 12 => DO <= HOUR;
								when 13 => DO <= WEEK;
								when 14 => DO <= DAY;
								when 15 => DO <= MONTH;
								when 16 => DO <= YEAR(7 downto 0);
								when 17 => DO <= YEAR(15 downto 8);
								when others => DO <= (others => '0');
							end case;
						elsif STREAM2.CHANNEL >= "00"&x"121" and STREAM2.CHANNEL <= "00"&x"124" then
							DO <= STREAM2_DATA_Q;
						else
							DO <= x"00";
						end if;
					when x"93" =>
						DO <= STREAM2.STATUS;
					when x"94" => DO <= R14;
					when x"95" => DO <= R15;
					when x"96" => DO <= (others => '0');
					when x"97" => DO <= R17;
					when x"98" => DO <= R18;
					when x"99" => DO <= R19;
					when x"9A" => DO <= R1A;
					when others => DO <= (others => '0');
				end case;
			else
				DO <= (others => '0');
			end if;
		end if;
	end process;
	
	CONV_SEC   <= std_logic_vector( ("0"&unsigned(EXT_RTC( 7 downto  4))&"000") + ("0000"&unsigned(EXT_RTC( 7 downto  4))) + ("0000"&unsigned(EXT_RTC( 7 downto  4))) + ("0000"&unsigned(EXT_RTC( 3 downto  0))) );
	CONV_MIN   <= std_logic_vector( ("0"&unsigned(EXT_RTC(15 downto 12))&"000") + ("0000"&unsigned(EXT_RTC(15 downto 12))) + ("0000"&unsigned(EXT_RTC(15 downto 12))) + ("0000"&unsigned(EXT_RTC(11 downto  8))) );
	CONV_HOUR  <= std_logic_vector( ("0"&unsigned(EXT_RTC(23 downto 20))&"000") + ("0000"&unsigned(EXT_RTC(23 downto 20))) + ("0000"&unsigned(EXT_RTC(23 downto 20))) + ("0000"&unsigned(EXT_RTC(19 downto 16))) );
	CONV_DAY   <= std_logic_vector( ("0"&unsigned(EXT_RTC(31 downto 28))&"000") + ("0000"&unsigned(EXT_RTC(31 downto 28))) + ("0000"&unsigned(EXT_RTC(31 downto 28))) + ("0000"&unsigned(EXT_RTC(27 downto 24))) );
	CONV_MONTH <= std_logic_vector( ("0"&unsigned(EXT_RTC(39 downto 36))&"000") + ("0000"&unsigned(EXT_RTC(39 downto 36))) + ("0000"&unsigned(EXT_RTC(39 downto 36))) + ("0000"&unsigned(EXT_RTC(35 downto 32))) );
	CONV_WEEK  <= std_logic_vector( ("00000"&unsigned(EXT_RTC(50 downto 48))) + 1 );
	CONV_YEAR  <= std_logic_vector( x"07D0" + ("0"&unsigned(EXT_RTC(47 downto 44))&"000") + ("0000"&unsigned(EXT_RTC(47 downto 44))) + ("0000"&unsigned(EXT_RTC(47 downto 44))) + ("0000"&unsigned(EXT_RTC(43 downto 40))) );
	
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
	begin
		if rising_edge(CLK) then
			if SEC_TICK = '1' then
				SEC <= std_logic_vector( unsigned(SEC) + 1 );	--sec inc
				if SEC = x"3B" then
					SEC <= (others => '0');
					MIN <= std_logic_vector( unsigned(MIN) + 1 );	--min inc
					if MIN = x"3B" then
						MIN <= (others => '0');
						HOUR <= std_logic_vector( unsigned(HOUR) + 1 );	--hour inc
						if HOUR = x"17" then
							HOUR <= (others => '0');
							DAY <= std_logic_vector( unsigned(DAY) + 1 );	--day inc
							if DAY = DAYS_TBL(to_integer(unsigned(MONTH))) then
								DAY <= x"01";
								MONTH <= std_logic_vector( unsigned(MONTH) + 1 );	--month inc
								if MONTH = x"0C" then
									MONTH <= x"01";
									YEAR <= std_logic_vector( unsigned(YEAR) + 1 );	--year inc
								end if;
							end if;
							
							WEEK <= std_logic_vector( unsigned(WEEK) + 1 );	--day of week inc
							if MONTH = x"07" then
								WEEK <= x"01";
							end if;
						end if;
					end if;
				end if;
			end if;
			
			if EXT_RTC(64) /= LAST_RTC64 then
				LAST_RTC64 <= EXT_RTC(64);
				SEC <= CONV_SEC;
				MIN <= CONV_MIN;
				HOUR <= CONV_HOUR;
				DAY <= CONV_DAY;
				WEEK <= CONV_WEEK;
				MONTH <= CONV_MONTH;
				YEAR <= CONV_YEAR;
			end if;
		end if;
	end process;
	
end rtl;
