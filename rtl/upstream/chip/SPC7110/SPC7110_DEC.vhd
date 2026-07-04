library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;
library work;
use work.SPC7110_DEC_PKG.all;


entity SPC7110_DEC is
	port(
		RST_N			: in std_logic;
		CLK			: in std_logic;
		ENABLE		: in std_logic;
		
		DI				: in std_logic_vector(7 downto 0);
		RD      		: out std_logic;
		
		INIT			: in std_logic;
		RUN			: in std_logic;
		MODE			: in std_logic_vector(1 downto 0);
		
		DAT_OUT		: out std_logic_vector(31 downto 0);
		WR      		: out std_logic;
		
		DBG_PROB		: out unsigned(7 downto 0);
		DBG_CON		: out unsigned(4 downto 0)
	);
end SPC7110_DEC;

architecture rtl of SPC7110_DEC is
	
	type DecompStates_t is (
		DCS_IDLE,
		DCS_INIT,
		DCS_PRELOAD,
		DCS_WORK
	);
	signal DCS : DecompStates_t; 
	
	signal CTX_TBL 		: ContextTbl_t;
	signal CON 				: unsigned(4 downto 0);
	signal TOP 				: unsigned(7 downto 0);
	signal LPS 				: std_logic;
	signal LPS_INV 		: std_logic;
	signal INVERTS 		: unsigned(3 downto 0);
	signal LPSS 			: unsigned(3 downto 0);
	signal SHIFT 			: std_logic;
	signal PROB_BIG_HALF : std_logic;
	signal IN_HIGH 		: unsigned(7 downto 0);
	signal IN_MID 			: unsigned(7 downto 0);
	signal IN_LOW 			: unsigned(7 downto 0);
	signal IN_BUF 			: unsigned(7 downto 0);
	signal IN_CNT 			: unsigned(2 downto 0);
	signal PIX_ORDER		: PixelOrder_t;
	signal REAL_ORDER 	: PixelOrder_t;
	signal OUTPUT			: std_logic_vector(35 downto 0);
	signal PIX_CNT 		: unsigned(2 downto 0);
	signal BIT_CNT 		: unsigned(1 downto 0);
	signal BIT_CNT_LAST	: unsigned(1 downto 0);
	
	signal LOAD 			: unsigned(1 downto 0);
	signal INT_RD 			: std_logic;
	signal INT_WR 			: std_logic;

begin
	
	process( RST_N, CLK)
		variable INV : std_logic;
		variable PROB : unsigned(7 downto 0);
		variable OFFS : unsigned(7 downto 0);
		variable MPS : std_logic;
		variable A,B,C : unsigned(3 downto 0);
		variable SHIFT_POS : unsigned(2 downto 0);
		variable NEW_IN_CNT : unsigned(3 downto 0);
		variable M2CON : unsigned(4 downto 0);
		variable NEW_INVERTS : unsigned(3 downto 0);
		variable NEW_LPSS : unsigned(3 downto 0);
		variable NEW_OUTPUT : std_logic_vector(35 downto 0);
		variable NEW_IN_HIGH, NEW_TOP : unsigned(7 downto 0);
		variable NEXT_CON : unsigned(4 downto 0);
	begin
		if RST_N = '0' then
			CTX_TBL <= (others => (0,'0'));
			PIX_CNT <= (others => '0');
			BIT_CNT <= (others => '0');
			INVERTS <= (others => '0');
			LPSS <= (others => '0');
			LPS <= '0';
			SHIFT <= '0';
			PROB_BIG_HALF <= '0';
			OUTPUT <= (others => '0');
			TOP <= (others => '1');
			IN_HIGH <= (others => '0');
			IN_MID <= (others => '0');
			IN_LOW <= (others => '0');
			IN_CNT <= (others => '0');
			DCS <= DCS_IDLE;
			LOAD <= (others => '0');
			INT_RD <= '0';
			INT_WR <= '0';
		elsif rising_edge(CLK) then
			INT_WR <= '0';
			if INT_RD = '1' then
				IN_BUF <= unsigned(DI);
			end if;
			
			case DCS is
				when DCS_IDLE =>
					
				when DCS_INIT =>
					CTX_TBL <= (others => (0,'0'));
					PIX_CNT <= (others => '0');
					BIT_CNT <= (others => '0');
					BIT_CNT_LAST <= GetBitMask(MODE);
					INVERTS <= (others => '0');
					LPSS <= (others => '0');
					LPS_INV <= '0';
					OUTPUT <= (others => '0');
					LOAD <= (others => '0');
					DCS <= DCS_PRELOAD;
					
				when DCS_PRELOAD =>
					LOAD <= LOAD + 1;
					if LOAD = 2 then
						DCS <= DCS_WORK;
					end if;
			
				when DCS_WORK =>
					if RUN = '1' and INIT = '0' then
						INV := CTX_TBL(to_integer(CON)).INV;
						NEW_LPSS := LPSS(2 downto 0) & LPS;
						NEW_INVERTS := INVERTS(2 downto 0) & INV;
						
						if MODE = "01" then
							NEW_OUTPUT := OUTPUT(33 downto 0) & std_logic_vector(REAL_ORDER(to_integer("00"&NEW_LPSS(1 downto 0) xor "00"&NEW_INVERTS(1 downto 0)))(1 downto 0));
						elsif MODE = "10" then
							NEW_OUTPUT := OUTPUT(31 downto 0) & std_logic_vector(REAL_ORDER(to_integer(NEW_LPSS(3 downto 0) xor NEW_INVERTS(3 downto 0))));
						else
							MPS := OUTPUT(15) xor INV;
							NEW_OUTPUT := OUTPUT(34 downto 0) & (MPS xor LPS);
						end if;
						
						if LPS = '1' and PROB_BIG_HALF = '1' then
							CTX_TBL(to_integer(CON)).INV <= not CTX_TBL(to_integer(CON)).INV;
						end if;
						
						if LPS = '1' then
							CTX_TBL(to_integer(CON)).INDEX <= GetNextLPS(CON, CTX_TBL);
						elsif SHIFT = '1' then
							CTX_TBL(to_integer(CON)).INDEX <= GetNextMPS(CON, CTX_TBL);
						end if;
						
						LPSS <= NEW_LPSS;
						INVERTS <= NEW_INVERTS;
						LPS_INV <= LPS xor INV;	
						
						BIT_CNT <= BIT_CNT + 1;
						if BIT_CNT = BIT_CNT_LAST then
							OUTPUT <= NEW_OUTPUT;
							BIT_CNT <= (others => '0');
							PIX_CNT <= PIX_CNT + 1;
							if PIX_CNT = 7 then
								DAT_OUT <= NEW_OUTPUT(31 downto 0);
								INT_WR <= '1';
							end if;
						end if;
					end if;
					
				when others => null;
			end case;
			
			if INIT = '1' then
				DCS <= DCS_INIT;
			end if;
			
			DBG_PROB <= PROB;
		elsif falling_edge(CLK) then
			INT_RD <= '0';
			
			case DCS is
				when DCS_INIT =>
					CON <= (others => '0');
					LPS <= '0';
					TOP <= (others => '0');
					PIX_ORDER <= (x"0",x"1",x"2",x"3",x"4",x"5",x"6",x"7",x"8",x"9",x"A",x"B",x"C",x"D",x"E",x"F");
					REAL_ORDER <= (x"0",x"1",x"2",x"3",x"4",x"5",x"6",x"7",x"8",x"9",x"A",x"B",x"C",x"D",x"E",x"F");
					IN_CNT <= (others => '0');
					INT_RD <= '1';
				
				when DCS_PRELOAD =>
					INT_RD <= '1';
					IN_LOW <= IN_BUF;
					IN_MID <= IN_LOW;
					IN_HIGH <= IN_MID;
					
				when DCS_WORK =>
					if RUN = '1' and INIT = '0' then
						if MODE = "01" then
							A := "00" & unsigned(OUTPUT(3 downto 2));
							B := "00" & unsigned(OUTPUT(15 downto 14));
							C := "00" & unsigned(OUTPUT(17 downto 16));
						else
							A := unsigned(OUTPUT(3 downto 0));
							B := unsigned(OUTPUT(31 downto 28));
							C := unsigned(OUTPUT(35 downto 32));
						end if;
						if BIT_CNT = 0 then
							PIX_ORDER <= Reorder(PIX_ORDER, A);
							REAL_ORDER <= Reorder(Reorder(Reorder(PIX_ORDER, C), B), A);
							if MODE = "00" then
								case PIX_CNT(1 downto 0) is
									when "00" =>   NEXT_CON := PIX_CNT(2)&"0000" + ((INVERTS(3 downto 0) xor LPSS(3 downto 0)) and "0000");
									when "01" =>   NEXT_CON := PIX_CNT(2)&"0001" + ((INVERTS(3 downto 0) xor LPSS(3 downto 0)) and "0001");
									when "10" =>   NEXT_CON := PIX_CNT(2)&"0011" + ((INVERTS(3 downto 0) xor LPSS(3 downto 0)) and "0011");
									when others => NEXT_CON := PIX_CNT(2)&"0111" + ((INVERTS(3 downto 0) xor LPSS(3 downto 0)) and "0111");
								end case;
							elsif MODE = "01" then
								NEXT_CON := "00"&GetDiff(A,B,C);
							else
								NEXT_CON := "00000";
							end if;
						else
							if MODE = "00" then
								case PIX_CNT(1 downto 0) is
									when "00" =>   NEXT_CON := PIX_CNT(2)&"0000" + ((INVERTS(3 downto 0) xor LPSS(3 downto 0)) and "0000");
									when "01" =>   NEXT_CON := PIX_CNT(2)&"0001" + ((INVERTS(3 downto 0) xor LPSS(3 downto 0)) and "0001");
									when "10" =>   NEXT_CON := PIX_CNT(2)&"0011" + ((INVERTS(3 downto 0) xor LPSS(3 downto 0)) and "0011");
									when others => NEXT_CON := PIX_CNT(2)&"0111" + ((INVERTS(3 downto 0) xor LPSS(3 downto 0)) and "0111");
								end case;
							elsif MODE = "01" then
								NEXT_CON := ("0" & CON(2 downto 0) & LPS_INV) + 5;
							else
								if LPS_INV = '0' then
									M2CON := M2C_TBL(to_integer(CON)).NEXT0;
								else
									M2CON := M2C_TBL(to_integer(CON)).NEXT1;
								end if;
								if CON = 1 then
									NEXT_CON := M2CON + GetDiff(A,B,C);
								else
									NEXT_CON := M2CON;
								end if;
							end if;
						end if;
						CON <= NEXT_CON;
	
						PROB := GetProb(NEXT_CON, CTX_TBL);
						OFFS := TOP - PROB;
						if IN_HIGH < OFFS then
							NEW_IN_HIGH := IN_HIGH;
							NEW_TOP := OFFS;
							LPS <= '0';
						else
							NEW_IN_HIGH := IN_HIGH - OFFS;
							NEW_TOP := TOP - OFFS;
							LPS <= '1';
						end if;
						
						SHIFT_POS := GetZeroBitCnt(NEW_TOP);
						TOP <= shift_left(NEW_TOP, to_integer(SHIFT_POS));
						
						NEW_IN_CNT := ("0"&IN_CNT) + ("0"&SHIFT_POS);
						IN_HIGH <= shift_left(NEW_IN_HIGH, to_integer(SHIFT_POS)) or shift_right(IN_MID, 8 - to_integer(SHIFT_POS));
						if NEW_IN_CNT = 8 then
							IN_MID <= shift_left(IN_MID, to_integer(SHIFT_POS)) or shift_right(IN_LOW, 8 - to_integer(SHIFT_POS));
							IN_LOW <= IN_BUF;
						elsif NEW_IN_CNT > 8 then
							IN_MID <= shift_left(IN_MID, to_integer(SHIFT_POS)) or shift_right(IN_LOW, 8 - to_integer(SHIFT_POS)) or shift_right(IN_BUF, 8 - to_integer(NEW_IN_CNT(2 downto 0)));
							IN_LOW <= shift_left(IN_BUF, to_integer(NEW_IN_CNT(2 downto 0)));
						else 
							IN_MID <= shift_left(IN_MID, to_integer(SHIFT_POS)) or shift_right(IN_LOW, 8 - to_integer(SHIFT_POS));
							IN_LOW <= shift_left(IN_LOW, to_integer(SHIFT_POS));
						end if;
						
						IN_CNT <= NEW_IN_CNT(2 downto 0);
						
						if NEW_IN_CNT(3) = '1' then
							INT_RD <= '1';
						end if;
						
						if SHIFT_POS > 0 then
							SHIFT <= '1';
						else
							SHIFT <= '0';
						end if;
						
						if PROB > x"55" then
							PROB_BIG_HALF <= '1';
						else
							PROB_BIG_HALF <= '0';
						end if;
					end if;
					
				when others => null;
			end case;
		end if;
	end process; 
	
	DBG_CON <= CON;
	
	RD <= INT_RD;
	WR <= INT_WR;

	
end rtl;
