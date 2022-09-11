library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;


entity SDD1_Decoder is
	port(
		RST_N			: in std_logic;
		CLK			: in std_logic;
		ENABLE		: in std_logic;
		
		INIT_SIZE	: in std_logic_vector(15 downto 0);
		IN_DATA		: in std_logic_vector(15 downto 0);
		HEADER		: in std_logic_vector(3 downto 0);
		
		INIT			: in std_logic;
		RUN			: in std_logic;
		DATA_REQ		: out std_logic;
		
		DO       	: out std_logic_vector(15 downto 0);
		
		PLANE_DONE	: out std_logic;
		DONE			: out std_logic
	);
end SDD1_Decoder;

architecture rtl of SDD1_Decoder is

	signal BIT_CNT	: unsigned(2 downto 0);
	signal BITPLANE_CNT : unsigned(2 downto 0);
	signal BIT_NUM : unsigned(6 downto 0);
	signal CURR_BP : integer range 0 to 7;
	signal CONTEXT2 : unsigned(4 downto 0);
	
	type BitsCtr_t is array(0 to 7) of unsigned(7 downto 0);
	signal BITS_CTR	: BitsCtr_t;
	
	type Evol_r is record
		CODE_NUM	: unsigned(2 downto 0);
		NEXT_MPS	: integer;
		NEXT_LPS	: integer;
	end record;
	
	type EvolTbl_t is array(0 to 32) of Evol_r;
	constant EVOL_TBL	: EvolTbl_t := (
	("000", 25, 25),
	("000",  2,  1),
	("000",  3,  1),
	("000",  4,  2),
	("000",  5,  3),
	("001",  6,  4),
	("001",  7,  5),
	("001",  8,  6),
	("001",  9,  7),
	("010", 10,  8),
	("010", 11,  9),
	("010", 12, 10),
	("010", 13, 11),
	("011", 14, 12),
	("011", 15, 13),
	("011", 16, 14),
	("011", 17, 15),
	("100", 18, 16),
	("100", 19, 17),
	("101", 20, 18),
	("101", 21, 19),
	("110", 22, 20),
	("110", 23, 21),
	("111", 24, 22),
	("111", 24, 23),
	("000", 26,  1),
	("001", 27,  2),
	("010", 28,  4),
	("011", 29,  8),
	("100", 30, 12),
	("101", 31, 16),
	("110", 32, 18),
	("111", 24, 22)
	);
	signal CODE_SIZE : unsigned(2 downto 0);
	
	type RunCounts_t is array(0 to 255) of unsigned(7 downto 0);
	constant  RUNCNT: RunCounts_t := (
	x"00", x"00", x"01", x"00", x"03", x"01", x"02", x"00",
	x"07", x"03", x"05", x"01", x"06", x"02", x"04", x"00",
	x"0f", x"07", x"0b", x"03", x"0d", x"05", x"09", x"01",
	x"0e", x"06", x"0a", x"02", x"0c", x"04", x"08", x"00",
	x"1f", x"0f", x"17", x"07", x"1b", x"0b", x"13", x"03",
	x"1d", x"0d", x"15", x"05", x"19", x"09", x"11", x"01",
	x"1e", x"0e", x"16", x"06", x"1a", x"0a", x"12", x"02",
	x"1c", x"0c", x"14", x"04", x"18", x"08", x"10", x"00",
	x"3f", x"1f", x"2f", x"0f", x"37", x"17", x"27", x"07",
	x"3b", x"1b", x"2b", x"0b", x"33", x"13", x"23", x"03",
	x"3d", x"1d", x"2d", x"0d", x"35", x"15", x"25", x"05",
	x"39", x"19", x"29", x"09", x"31", x"11", x"21", x"01",
	x"3e", x"1e", x"2e", x"0e", x"36", x"16", x"26", x"06",
	x"3a", x"1a", x"2a", x"0a", x"32", x"12", x"22", x"02",
	x"3c", x"1c", x"2c", x"0c", x"34", x"14", x"24", x"04",
	x"38", x"18", x"28", x"08", x"30", x"10", x"20", x"00",
	x"7f", x"3f", x"5f", x"1f", x"6f", x"2f", x"4f", x"0f",
	x"77", x"37", x"57", x"17", x"67", x"27", x"47", x"07",
	x"7b", x"3b", x"5b", x"1b", x"6b", x"2b", x"4b", x"0b",
	x"73", x"33", x"53", x"13", x"63", x"23", x"43", x"03",
	x"7d", x"3d", x"5d", x"1d", x"6d", x"2d", x"4d", x"0d",
	x"75", x"35", x"55", x"15", x"65", x"25", x"45", x"05",
	x"79", x"39", x"59", x"19", x"69", x"29", x"49", x"09",
	x"71", x"31", x"51", x"11", x"61", x"21", x"41", x"01",
	x"7e", x"3e", x"5e", x"1e", x"6e", x"2e", x"4e", x"0e",
	x"76", x"36", x"56", x"16", x"66", x"26", x"46", x"06",
	x"7a", x"3a", x"5a", x"1a", x"6a", x"2a", x"4a", x"0a",
	x"72", x"32", x"52", x"12", x"62", x"22", x"42", x"02",
	x"7c", x"3c", x"5c", x"1c", x"6c", x"2c", x"4c", x"0c",
	x"74", x"34", x"54", x"14", x"64", x"24", x"44", x"04",
	x"78", x"38", x"58", x"18", x"68", x"28", x"48", x"08",
	x"70", x"30", x"50", x"10", x"60", x"20", x"40", x"00"
	);


	type ContextStates_t is array(0 to 31) of integer range 0 to 32;
	signal CNTXT_STATES	: ContextStates_t;
	type ContextMPS_t is array(0 to 31) of std_logic;
	signal CNTXT_MPS : ContextMPS_t;
	signal STATE : integer range 0 to 32;
	
	type BitPlanes_t is array(0 to 7) of unsigned(15 downto 0);
	signal PREV_BP	: BitPlanes_t;
	
	signal LEFT_BYTES	: unsigned(15 downto 0);
	signal OUT_DATA0, OUT_DATA1	: std_logic_vector(7 downto 0);
	signal OUT_CNT	: unsigned(3 downto 0);
	signal RUN2	: std_logic;
	
begin
	
	process( RST_N, CLK, HEADER, BITPLANE_CNT, BIT_NUM, PREV_BP, CNTXT_STATES, BIT_CNT, IN_DATA, BITS_CTR, RUN )
		variable NEW_BIT_CNT : unsigned(3 downto 0);
		variable TCURR_BP : integer range 0 to 7;
		variable TCONTEXT : unsigned(4 downto 0);
		variable TSTATE : integer range 0 to 32;
		variable TCODE_SIZE : unsigned(2 downto 0);
		variable CODE : unsigned(7 downto 0);
	begin
		case HEADER(3 downto 2) is
			when "00" =>  
				TCURR_BP := to_integer(BITPLANE_CNT and "001");
			when "01" =>  
				TCURR_BP := to_integer(BITPLANE_CNT and "111");
			when "10" =>  
				TCURR_BP := to_integer(BITPLANE_CNT and "011");
			when others =>
				TCURR_BP := to_integer(BIT_NUM(2 downto 0));
		end case; 
		
		case HEADER(1 downto 0) is
			when "00" =>  
				TCONTEXT := BITPLANE_CNT(0) & (PREV_BP(TCURR_BP)(8 downto 6) and "111") & PREV_BP(TCURR_BP)(0);
			when "01" =>  
				TCONTEXT := BITPLANE_CNT(0) & (PREV_BP(TCURR_BP)(8 downto 6) and "110") & PREV_BP(TCURR_BP)(0);
			when "10" =>  
				TCONTEXT := BITPLANE_CNT(0) & (PREV_BP(TCURR_BP)(8 downto 6) and "011") & PREV_BP(TCURR_BP)(0);
			when others =>
				TCONTEXT := BITPLANE_CNT(0) & (PREV_BP(TCURR_BP)(8 downto 7) and "11") & PREV_BP(TCURR_BP)(1 downto 0);
		end case; 
		
		TSTATE := CNTXT_STATES(to_integer(TCONTEXT));
		TCODE_SIZE := EVOL_TBL(TSTATE).CODE_NUM;
		
		CODE := shift_left(unsigned(IN_DATA), to_integer(BIT_CNT))(15 downto 8);
		if IN_DATA(to_integer(not BIT_CNT) + 8) = '0' then
			NEW_BIT_CNT := resize(BIT_CNT, NEW_BIT_CNT'length) + 1;
		else
			NEW_BIT_CNT := resize(BIT_CNT, NEW_BIT_CNT'length) + 1 + resize(TCODE_SIZE, NEW_BIT_CNT'length);
		end if;
		
		if (RUN = '1' or BIT_NUM(3 downto 0) /= "0000") and BITS_CTR(to_integer(TCODE_SIZE))(6 downto 0) = 0 and NEW_BIT_CNT(3) = '1' then
			DATA_REQ <= '1';
		else
			DATA_REQ <= '0';
		end if;
						
		if RST_N = '0' then
			BIT_CNT <= "100";
			BITS_CTR <= (others => x"00");
			BITPLANE_CNT <= (others => '0');
			BIT_NUM <= (others => '0');
			RUN2 <= '0';

		elsif rising_edge(CLK) then
			RUN2 <= '0';
			if ENABLE = '1' then
				if INIT = '1' then
					BIT_NUM <= (others => '0');
					BITPLANE_CNT <= (others => '0');
					BIT_CNT <= "100";
					BITS_CTR <= (others => x"00");
					
				else
					if RUN = '1' or BIT_NUM(3 downto 0) /= "0000" then
						BIT_NUM <= BIT_NUM + 1;
						BITPLANE_CNT(0) <= not BITPLANE_CNT(0);
						if BIT_NUM = 127 then
							BITPLANE_CNT(2 downto 1) <= BITPLANE_CNT(2 downto 1) + 1;
						end if;
								
						if BITS_CTR(to_integer(TCODE_SIZE))(6 downto 0) = 0 then					
							BIT_CNT <= NEW_BIT_CNT(2 downto 0);
							
							if CODE(7) = '1' then
								BITS_CTR(to_integer(TCODE_SIZE)) <= x"80" or RUNCNT(to_integer(shift_right(CODE, to_integer(not TCODE_SIZE))));
							else
								BITS_CTR(to_integer(TCODE_SIZE)) <= (shift_left(x"01", to_integer(TCODE_SIZE)) - 1);
							end if;
						else
							BITS_CTR(to_integer(TCODE_SIZE)) <= BITS_CTR(to_integer(TCODE_SIZE)) - 1;
						end if;
			
						CONTEXT2 <= TCONTEXT;
						STATE <= TSTATE;
						CODE_SIZE <= TCODE_SIZE;
						CURR_BP <= TCURR_BP;
						RUN2 <= '1';
					end if;
				end if;
			end if;
		end if;
	end process; 

			
	process( RST_N, CLK)
		variable PBIT : std_logic;
	begin
		if RST_N = '0' then
			CNTXT_STATES <= (others => 0);
			CNTXT_MPS <= (others => '0');
			PREV_BP <= (others => (others => '0'));
			OUT_DATA0 <= (others => '0');
			OUT_DATA1 <= (others => '0');
			OUT_CNT <= (others => '0');
			LEFT_BYTES <= (others => '0');
			PLANE_DONE <= '0';
			DONE <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				if INIT = '1' then
					LEFT_BYTES <= unsigned(INIT_SIZE) - 1;
					DONE <= '0';
					PLANE_DONE <= '0';
					CNTXT_STATES <= (others => 0);
					CNTXT_MPS <= (others => '0');
					PREV_BP <= (others => (others => '0'));
					OUT_CNT <= (others => '0');
				elsif RUN2 = '1' then
					if BITS_CTR(to_integer(CODE_SIZE)) = x"80" then
						PBIT := not CNTXT_MPS(to_integer(CONTEXT2));
					else
						PBIT := CNTXT_MPS(to_integer(CONTEXT2));
					end if;
					
					if BITS_CTR(to_integer(CODE_SIZE)) = x"80" then
						CNTXT_STATES(to_integer(CONTEXT2)) <= EVOL_TBL(STATE).NEXT_LPS;
						if STATE < 2 then
							CNTXT_MPS(to_integer(CONTEXT2)) <= not CNTXT_MPS(to_integer(CONTEXT2));
						end if;
					elsif BITS_CTR(to_integer(CODE_SIZE)) = x"00" then
						CNTXT_STATES(to_integer(CONTEXT2)) <= EVOL_TBL(STATE).NEXT_MPS;
					end if;
					
					PREV_BP(CURR_BP) <= PREV_BP(CURR_BP)(14 downto 0) & PBIT;
					
					OUT_CNT <= OUT_CNT + 1;
					if OUT_CNT(0) = '0' then
						OUT_DATA0 <= OUT_DATA0(6 downto 0) & PBIT;
					else
						OUT_DATA1 <= OUT_DATA1(6 downto 0) & PBIT;
					end if;
					
					if OUT_CNT(3 downto 0) = 15 then
						PLANE_DONE <= '1';
					else
						PLANE_DONE <= '0';
					end if;
					
					if OUT_CNT(2 downto 0) = 7 then
						LEFT_BYTES <= LEFT_BYTES - 1;
						if LEFT_BYTES = 0 then
							DONE <= '1';
						end if;
					end if;
				end if;
			end if;
		end if;
	end process; 
	
	DO <= OUT_DATA1 & OUT_DATA0 when HEADER(3 downto 2) /= "11" else
			OUT_DATA1(0)&OUT_DATA0(0)&OUT_DATA1(1)&OUT_DATA0(1)&OUT_DATA1(2)&OUT_DATA0(2)&OUT_DATA1(3)&OUT_DATA0(3)&OUT_DATA1(4)&OUT_DATA0(4)&OUT_DATA1(5)&OUT_DATA0(5)&OUT_DATA1(6)&OUT_DATA0(6)&OUT_DATA1(7)&OUT_DATA0(7);
	
end rtl;
