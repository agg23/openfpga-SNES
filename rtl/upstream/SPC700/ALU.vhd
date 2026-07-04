library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.SPC700_pkg.all;

entity SPC700_ALU is
    port( 
        CLK		: in std_logic;
		  RST_N	: in std_logic;
		  EN 		: in std_logic;
		  L		: in std_logic_vector(7 downto 0); 
		  R		: in std_logic_vector(7 downto 0); 
		  CTRL	: in ALUCtrl_r;
		  CI		: in std_logic; 
		  VI		: in std_logic; 
		  SI		: in std_logic; 
		  ZI		: in std_logic; 
		  HI		: in std_logic; 
		  DivZI	: in std_logic; 
		  DivVI  : in std_logic; 
		  DivHI  : in std_logic; 
		  DivSI  : in std_logic; 
        CO		: out std_logic; 
		  VO		: out std_logic; 
		  SO		: out std_logic; 
		  ZO		: out std_logic; 
		  HO		: out std_logic; 
        RES		: out std_logic_vector(7 downto 0)
    );
end SPC700_ALU;

architecture rtl of SPC700_ALU is

	signal tIntR : std_logic_vector(7 downto 0);
	signal CR, COut, HOut, VOut, SOut, tZ, SaveC  : std_logic;
	signal CIIn, ADDIn: std_logic;
	
	signal AddR, BCDR : std_logic_vector(7 downto 0);
	signal AddCO, AddVO, AddHO : std_logic; 
	signal BCDCO : std_logic; 
	signal tResult : std_logic_vector(7 downto 0);

begin
	
	process(CTRL, CI, R)
	begin
		CR <= CI;
		case CTRL.fstOp is
			when "000" => 
				CR <= R(7);
				tIntR <= R(6 downto 0) & "0";
			when "001"=> 
				CR <= R(7);
				tIntR <= R(6 downto 0) & CI;
			when "010" => 
				CR <= R(0);
				tIntR <= "0" & R(7 downto 1);
			when "011" => 
				CR <= R(0);
				tIntR <= CI & R(7 downto 1);
			when "100" => 
				tIntR <= x"00";
			when "101" => 			--INC,DEC
				tIntR <= x"01";
			when "110" => 
				tIntR <= R;
			when "111" => 
				tIntR <= not R;
			when others => null;
		end case;
	end process;
	
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			SaveC <= '0';
		elsif rising_edge(CLK) then 
			if EN = '1' then
				if CTRL.secOp(3) = '1' then
					SaveC <= AddCO;
				end if;
			end if;
		end if;
	end process;
	
	CIIn <= SaveC when CTRL.intC = '1' else 
			  CI when CTRL.secOp(0) = '0' else
			  CTRL.secOp(1);
			  
	ADDIn <= not CTRL.secOp(1);
	
	AddSub: entity work.SPC700_AddSub
	port map (
		A     	=> L,
		B     	=> tIntR, 
		CI     	=> CIIn, 
		ADD     	=> ADDIn, 
		S     	=> AddR, 
		CO     	=> AddCO,
		VO     	=> AddVO,
		HO    	=> AddHO
	);
	
	BCD: entity work.SPC700_BCDAdj
	port map (
		A     	=> L,
		ADD     	=> CTRL.secOp(0), 
		CI     	=> CI, 
		HI     	=> HI, 
		R     	=> BCDR, 
		CO     	=> BCDCO
	);
	
	process(CTRL, CR, tIntR, L, AddCO, AddHO, BCDCO, AddR, BCDR, DivHI)
	begin
		HOut <= '0';
		COut <= CR;
		case CTRL.secOp is
			when "0000" => 
				tResult <= L or tIntR;
			when "0001"=> 
				tResult <= L and tIntR;
			when "0010" => 
				tResult <= L xor tIntR;
			when "0011" => 
				tResult <= tIntR;
			when "0100" => 			--TCLR1
				tResult <= tIntR and (not L);
			when "0101" => 			--TSET1
				tResult <= tIntR or L;
			when "0110" => 			--XCN
				tResult <= tIntR(3 downto 0) & tIntR(7 downto 4);
			when "1000" | "1010" | "1001" | "1011" => --ADC,SBC, ADD,SUB
				tResult <= AddR;
				COut <= AddCO;
				HOut <= AddHO;
			when "1100" | "1101" =>	--DAA,DAS
				tResult <= BCDR;
				COut <= BCDCO;
			when "1110" =>				--MUL
				tResult <= tIntR;
			when "1111" =>				--DIV
				tResult <= tIntR;
				HOut <= DivHI;
			when others => 
				tResult <= x"00";
		end case;
	end process;
	
	process(CTRL, VI, AddVO, DivVI)
	begin
		VOut <= VI; 
		case CTRL.secOp is
			when "1000" | "1001" => --ADC,ADD
				VOut <= AddVO;	
			when "1010" | "1011" => --SBC,SUB
				VOut <= AddVO;
			when "1111" =>				--DIV
				VOut <= DivVI;
			when others => null;
		end case;
	end process;
	
	process(CTRL, SI, tResult, DivSI)
	begin
		SOut <= SI; 
		case CTRL.secOp is
			when "1110" =>				--MUL
				SOut <= DivSI;
			when "1111" =>				--DIV
				SOut <= DivSI;
			when others =>
				SOut <= tResult(7);
		end case;
	end process;
	
	tZ <= DivZI when CTRL.secOp(3 downto 1) = "111" else 
			'1' when tResult = x"00" else '0'; 
	ZO <= ZI and tZ when CTRL.w = '1' else tZ;
	CO <= COut when CTRL.chgCO = '1' else CI;
	VO <= VOut when CTRL.chgVO = '1' else VI;
	HO <= HOut when CTRL.chgHO = '1' else HI;
	SO <= SOut;  
	
	RES <= tResult;
	
end rtl;