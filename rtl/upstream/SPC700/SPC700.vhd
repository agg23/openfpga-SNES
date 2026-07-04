library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.SPC700_pkg.all; 

entity SPC700 is
    port( 
        CLK 			: in std_logic;
		  RST_N 			: in std_logic; 
		  RDY 			: in std_logic;
		  IRQ_N 			: in std_logic;
        D_IN         : in std_logic_vector(7 downto 0);
        D_OUT        : out std_logic_vector(7 downto 0);
        A_OUT			: out std_logic_vector(15 downto 0);
        WE				: out std_logic;

		  REG_DAT		: in std_logic_vector(55 downto 0);
		  REG_SET		: in std_logic
    );
end SPC700;

architecture rtl of SPC700 is 

	signal A, X, Y, SP, PSW, T : std_logic_vector(7 downto 0);
	signal PC    : std_logic_vector(15 downto 0);
	
	signal IR    : std_logic_vector(7 downto 0);
	signal NextState    : unsigned(3 downto 0);

	signal NextIR    : std_logic_vector(7 downto 0);
	signal STATE     : unsigned(3 downto 0);
	signal LAST_CYCLE : std_logic;
	signal GotInterrupt : std_logic;
	signal JumpTaken : std_logic;
	signal IsResetInterrupt, IsIRQInterrupt : std_logic;
	signal EN : std_logic;
	signal STPExec : std_logic;
	signal IrqActive : std_logic;
	signal AYLoad : std_logic;
	signal CToBit, BitToC : std_logic_vector(7 downto 0);

	signal MC : MCode_r;
	signal SB, DB    : std_logic_vector(7 downto 0);

	-- AddrGen 
	signal AX: std_logic_vector(15 downto 0);
	signal ALCarry : std_logic;
	
	-- ALU 
	signal AluR: std_logic_vector(7 downto 0);
	signal MulDivR: std_logic_vector(15 downto 0);
	signal CO, VO, SO, ZO, HO, DivZO, DivVO, DivHO, DivSO : std_logic;
	signal BitMask: std_logic_vector(7 downto 0);
	signal nBit : integer range 0 to 7;
	
	constant ONE : unsigned(7 downto 0) := x"01";

begin
	EN <= RDY and not STPExec;
	
	NextIR <= IR when (STATE /= "0000") else
				 x"0F" when GotInterrupt = '1' else 
				 D_IN; 
				 
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			JumpTaken <= '0';
			BitMask <= (others=>'0');
			nBit <= 0;
		elsif rising_edge(CLK) then
			if EN = '1' then
				if STATE = "0000" and D_IN(3 downto 0) = x"0" then
					case D_IN(7 downto 4) is
						when x"1" => JumpTaken <= not PSW(7); -- BPL
						when x"3" => JumpTaken <=     PSW(7); -- BMI
						when x"5" => JumpTaken <= not PSW(6); -- BVC
						when x"7" => JumpTaken <=     PSW(6); -- BVS
						when x"9" => JumpTaken <= not PSW(0); -- BCC
						when x"B" => JumpTaken <=     PSW(0); -- BCS
						when x"D" => JumpTaken <= not PSW(1); -- BNE
						when x"F" => JumpTaken <=     PSW(1); -- BEQ
						when others => null;
					end case; 
				elsif STATE = "0010" and IR(3 downto 0) = x"3" then
					case IR(7 downto 4) is
						when x"0" => JumpTaken <=     D_IN(0); -- BBS0
						when x"1" => JumpTaken <= not D_IN(0); -- BBC0
						when x"2" => JumpTaken <=     D_IN(1); -- BBS1
						when x"3" => JumpTaken <= not D_IN(1); -- BBC1
						when x"4" => JumpTaken <=     D_IN(2); -- BBS1
						when x"5" => JumpTaken <= not D_IN(2); -- BBC2
						when x"6" => JumpTaken <=     D_IN(3); -- BBS3
						when x"7" => JumpTaken <= not D_IN(3); -- BBC3
						when x"8" => JumpTaken <=     D_IN(4); -- BBS4
						when x"9" => JumpTaken <= not D_IN(4); -- BBC4
						when x"A" => JumpTaken <=     D_IN(5); -- BBS5
						when x"B" => JumpTaken <= not D_IN(5); -- BBC5
						when x"C" => JumpTaken <=     D_IN(6); -- BBS6
						when x"D" => JumpTaken <= not D_IN(6); -- BBC6
						when x"E" => JumpTaken <=     D_IN(7); -- BBS7
						when x"F" => JumpTaken <= not D_IN(7); -- BBC7
						when others => null;
					end case; 
				elsif STATE = "0010" and IR = x"FE" then -- DBNZ
					JumpTaken <= not ZO;
				elsif STATE = "0010" and IR = x"6E" then 
					JumpTaken <= not ZO;
				elsif STATE = "0010" and IR = x"2E" then -- CBNE
					JumpTaken <= not ZO;
				elsif STATE = "0011" and IR = x"DE" then
					JumpTaken <= not ZO;
				elsif MC.STATE_CTRL = "10" then
					JumpTaken <= '0';
				end if;
				
				if STATE = "0001" and IR(3 downto 0) = x"2" then
					BitMask <= std_logic_vector(ONE sll (to_integer(unsigned(IR(7 downto 5)))));
				elsif STATE = "0010" and IR(4 downto 0) = "0"&x"A" then
					BitMask <= std_logic_vector(ONE sll (to_integer(unsigned(D_IN(7 downto 5)))));
					nBit <= to_integer(unsigned(D_IN(7 downto 5)));
				end if;
			end if;
		end if;
	end process;

	process(MC, STATE, ALCarry, JumpTaken)
	begin
		case MC.STATE_CTRL is
			when "00" => 
				NextState <= STATE + 1; 
			when "01" => 
				if ALCarry = '1' then
					NextState <= STATE + 1;
				else
					NextState <= STATE + 2;
				end if;
			when "10" => 
				if JumpTaken = '1' then
					NextState <= STATE + 1;
				else
					NextState <= "0000";
				end if; 
			when others =>
				NextState <= "0000";
		end case;
	end process;
	
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			STATE <= (others=>'0');
			IR <= (others=>'0');
		elsif rising_edge(CLK) then
			if EN = '1' then
				IR <= NextIR;
				STATE <= NextState;
			end if;
		end if;
	end process;
	
	LAST_CYCLE <= '1' when NextState = "0000" else '0';
	
	
	MCode: entity work.SPC700_MCode
	port map (
		CLK	=> CLK,
		RST_N	=> RST_N,
		EN		=> EN,
		IR		=> NextIR,
		STATE	=> NextState,
		M		=> MC
	);
	
	AddrGen: entity work.SPC700_AddrGen
	port map (
		CLK   		=> CLK,
		RST_N   		=> RST_N,
		EN   			=> EN,
		ADDR_CTRL	=> MC.ADDR_CTRL,
		LOAD_PC   	=> MC.LOAD_PC,
		GotInterrupt=> GotInterrupt,
		D_IN 			=> D_IN,
		X     		=> X, 
		Y     		=> Y, 
		S     		=> SP,
		T     		=> T,
		P     		=> PSW(5),
		PC     		=> PC, 
		AX     		=> AX, 
		ALCarry     => ALCarry, 
		REG_DAT	   => REG_DAT(15 downto 0), 
		REG_SET	   => REG_SET
	);
	
	BitToC <= std_logic_vector(unsigned(D_IN) srl nBit);
	CToBit <= std_logic_vector(unsigned(PSW and x"01") sll nBit);

	SB <= A                   when MC.BUS_CTRL(5 downto 3) = "000" else
		   X                   when MC.BUS_CTRL(5 downto 3) = "001" else
		   Y                   when MC.BUS_CTRL(5 downto 3) = "010" else
		   T                   when MC.BUS_CTRL(5 downto 3) = "011" else
			D_IN                when MC.BUS_CTRL(5 downto 3) = "100" else
			"0000000"&PSW(0)    when MC.BUS_CTRL(5 downto 3) = "101" else
			MulDivR(7 downto 0) when MC.BUS_CTRL(5 downto 3) = "110" else
			SP                  when MC.BUS_CTRL(5 downto 3) = "111" else
			x"00";
	
	DB <= D_IN    when MC.BUS_CTRL(2 downto 0) = "000" else
		   SB      when MC.BUS_CTRL(2 downto 0) = "001" else
		   BitMask when MC.BUS_CTRL(2 downto 0) = "010" else
			BitToC  when MC.BUS_CTRL(2 downto 0) = "011" else
			CToBit  when MC.BUS_CTRL(2 downto 0) = "100" else
			T       when MC.BUS_CTRL(2 downto 0) = "101" else
			x"00";
	
	ALU: entity work.SPC700_ALU
	port map (
		CLK   	=> CLK,
		RST_N   	=> RST_N,
		EN   		=> EN,
		L     	=> SB,
		R     	=> DB,
		CTRL   	=> MC.ALU_CTRL,
		CI   	 	=> PSW(0),
		VI  		=> PSW(6),
		SI  		=> PSW(7),
		ZI  		=> PSW(1),
		HI  		=> PSW(3),
		DivZI		=> DivZO,
		DivVI		=> DivVO,
		DivHI		=> DivHO,
		DivSI		=> DivSO,
		CO   		=> CO,
		VO    	=> VO,
		SO   		=> SO,
		ZO   		=> ZO,
		HO   		=> HO,
		RES		=> AluR
	);

	MulDiv: entity work.MulDiv
	port map (
		CLK   	=> CLK,
		EN   		=> EN,
		RST_N   	=> RST_N,
		CTRL   	=> MC.ALU_CTRL,
		A     	=> A,
		X     	=> X,
		Y   	 	=> Y,
		RES		=> MulDivR,
		ZO			=> DivZO,
		VO			=> DivVO,
		HO			=> DivHO,
		SO			=> DivSO
	);
	
	AYLoad <= '1' when IR = x"CF" or IR = x"9E" else '0';	--MUL/DIV
		
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			A <= (others=>'0');
			X <= (others=>'0');
			Y <= (others=>'0');
		elsif rising_edge(CLK) then
			if REG_SET = '1' then
				A <= REG_DAT(23 downto 16); 
				X <= REG_DAT(31 downto 24);
				Y <= REG_DAT(39 downto 32);
			elsif EN = '0' then
				
			else
				if MC.LOAD_AXY = "10" then 
					X <= AluR;
				end if;
				if MC.LOAD_AXY = "01" then 
					if AYLoad = '0' then
						A <= AluR;
					else
						A <= AluR;
					end if;
				end if;
				if MC.LOAD_AXY = "11" then 
					Y <= AluR;
				elsif MC.LOAD_AXY = "01" and AYLoad = '1' then 
					Y <= MulDivR(15 downto 8);
				end if; 
			end if; 
		end if;
	end process;
	
	
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			PSW <= (others=>'0');
			SP <= (others=>'0');
			T <= (others=>'0');
		elsif rising_edge(CLK) then
			if REG_SET = '1' then
				PSW <= REG_DAT(47 downto 40);
				SP <= REG_DAT(55 downto 48);
			elsif EN = '0' then
				
			else
				case MC.LOAD_SP is
					when "00" => null;
					when "01"=> 
						SP <= std_logic_vector(unsigned(SP) + 1);
					when "10" => 
						SP <= std_logic_vector(unsigned(SP) - 1);
					when "11" => 
						SP <= X;
					when others => null;
				end case;
				
				case MC.LOAD_T is
					when "01" => 
						T <= D_IN;
					when "10" => 
						T <= AluR;
					when others => null;
				end case;

				case MC.LOAD_P is
					when "000" =>       -- No Op
						PSW <= PSW;
					when "001" => 
						PSW(1 downto 0) <= ZO & CO; PSW(3) <= HO; PSW(7 downto 6) <= SO & VO; -- ALU
					when "010" => PSW(2) <= '0'; PSW(4) <= not IsResetInterrupt ;    -- BRK
					when "011" => PSW <= D_IN; -- RETI/POP PSW
					when "100" => 
						case IR(7 downto 5) is
							when "001" => PSW(5) <= '0'; -- CLRP 20
							when "010" => PSW(5) <= '1'; -- SETP 40
							when "011" => PSW(0) <= '0'; -- CLRC 60
							when "100" => PSW(0) <= '1'; -- SETC 80
							when "101" => PSW(2) <= '1'; -- EI A0
							when "110" => PSW(2) <= '0'; -- DI C0
							when "111" => PSW(6) <= '0'; -- CLRV E0 
											  PSW(3) <= '0';
							when others => null;
						end case;
					when "101" => 
						PSW(0) <= AluR(0);
					when others =>
						PSW <= PSW;
				end case;
			end if;
		end if;
	end process;

	D_OUT <= SB when MC.OUT_BUS = "001" else
				AluR when MC.OUT_BUS = "010" else
				PSW when MC.OUT_BUS = "011" else
				PC(7 downto 0) when MC.OUT_BUS = "100" else
				PC(15 downto 8) when MC.OUT_BUS = "101" else
				x"FF";
					
	
	process(MC, IsResetInterrupt)
	begin
		WE <= '1';
		if MC.OUT_BUS /= "000" and IsResetInterrupt = '0' then
			WE <= '0';
		end if;
	end process;

	process(MC, PC, AX, SP, STATE, IR, IsResetInterrupt, IsIRQInterrupt, GotInterrupt)
	begin
		case MC.ADDR_BUS is
			when "00" => 
				A_OUT <= PC; 
			when "01"=> 
				if IR = x"0A" or IR = x"2A" or IR = x"4A" or IR = x"6A" or IR = x"8A" or IR = x"AA" or IR = x"CA" or IR = x"EA" then
					A_OUT <= AX and x"1FFF";
				else
					A_OUT <= AX;
				end if;
			when "10" => 
				A_OUT <= x"01" & SP;
			when "11" => 
				if IR(3 downto 0) = x"1" then
					A_OUT <= x"FF" & "110" & not IR(7 downto 4) & STATE(0); --FFC0-FFDF
				else
					if GotInterrupt = '1' then
						A_OUT <= x"FF" & "11" & not IsIRQInterrupt & "1111" & STATE(0); --FFFE/F
					else
						A_OUT <= x"FF" & "110" & not IR(7 downto 4) & STATE(0);
					end if;
				end if;
			when others => null;
		end case;
	end process;

	IrqActive <= not IRQ_N and not PSW(2);
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			GotInterrupt <= '1';
			IsResetInterrupt <= '1';
			IsIRQInterrupt <= '0'; 
			STPExec <= '0'; 
		elsif rising_edge(CLK) then
			if REG_SET = '1' then	--need for SPC Player
				GotInterrupt <= '0'; 
				IsResetInterrupt <= '0';
			elsif EN = '0' then
				
			else
				if LAST_CYCLE = '1' then
					GotInterrupt <= IrqActive;
					IsResetInterrupt <= '0';
					
					if IrqActive = '1' and IsIRQInterrupt = '0' then
						IsIRQInterrupt <= '1';
					else
						IsIRQInterrupt <= '0';
					end if;
				end if;
				
				if STATE = "0001" then 
					if IR = x"EF" or IR = x"FF" then				-- SLEEP, STP
						STPExec <= '1';
					end if;
				end if;
			end if;
		end if;
	end process;
	
end rtl;
