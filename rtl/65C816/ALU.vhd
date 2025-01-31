library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.P65816_pkg.all;

entity ALU is
	port( 
		L   	: in std_logic_vector(15 downto 0); 
		R		: in std_logic_vector(15 downto 0); 
		CTRL	: in ALUCtrl_r;
		w16	: in std_logic; 
		BCD	: in std_logic; 
		CI		: in std_logic; 
		VI		: in std_logic; 
		SI		: in std_logic; 
		CO		: out std_logic; 
		VO		: out std_logic; 
		SO		: out std_logic; 
		ZO		: out std_logic; 
		RES	: out std_logic_vector(15 downto 0);
		IntR	: out std_logic_vector(15 downto 0)
	);
end ALU;

architecture rtl of ALU is

	signal IntR16 : std_logic_vector(15 downto 0);
	signal IntR8 : std_logic_vector(7 downto 0);
	signal CR8, CR16, CR, ZR : std_logic;
	signal CIIn, ADDIn, BCDIn: std_logic;
	
	signal AddR : std_logic_vector(15 downto 0);
	signal AddCO, AddVO : std_logic; 
	signal Result16 : std_logic_vector(15 downto 0);
	signal Result8 : std_logic_vector(7 downto 0);

begin
	
	process(CTRL, CI, R)
	begin
		CR8 <= CI; 
		CR16 <= CI; 
		case CTRL.fstOp is
			when "000" => 
				CR8 <= R(7);
				CR16 <= R(15);
				IntR8 <= R(6 downto 0) & "0";
				IntR16 <= R(14 downto 0) & "0";
			when "001"=> 
				CR8 <= R(7);
				CR16 <= R(15);
				IntR8 <= R(6 downto 0) & CI;
				IntR16 <= R(14 downto 0) & CI;
			when "010" => 
				CR8 <= R(0);
				CR16 <= R(0);
				IntR8 <= "0" & R(7 downto 1);
				IntR16 <= "0" & R(15 downto 1);
			when "011" => 
				CR8 <= R(0);
				CR16 <= R(0);
				IntR8 <= CI & R(7 downto 1);
				IntR16 <= CI & R(15 downto 1);
			when "100" => 
				IntR8 <= R(7 downto 0);
				IntR16 <= R;
			when "101" => 
				IntR8 <= R(15 downto 8);
				IntR16 <= R(7 downto 0) & R(15 downto 8);
			when "110" => 
				IntR8 <= std_logic_vector(unsigned(R(7 downto 0)) - 1); -- INC/DEC 
				IntR16 <= std_logic_vector(unsigned(R) - 1); -- INC/DEC 
			when "111" => 
				IntR8 <= std_logic_vector(unsigned(R(7 downto 0)) + 1); -- INC/DEC 
				IntR16 <= std_logic_vector(unsigned(R) + 1); -- INC/DEC 
			when others => null;
		end case;
	end process;
	
	CR <= CR8 when w16 = '0' else CR16; 
	
	CIIn <= CR or not CTRL.secOp(0);
	ADDIn <= not CTRL.secOp(2);
	BCDIn <= BCD and CTRL.secOp(0);
	
	AddSub: entity work.AddSubBCD
	port map (
		A     	=> L,
		B     	=> R, 
		CI     	=> CIIn, 
		ADD     	=> ADDIn, 
		BCD     	=> BCDIn,
		w16     	=> w16, 
		S     	=> AddR, 
		CO     	=> AddCO,
		VO     	=> AddVO
	);
	
	process(CTRL, w16, CR, IntR8, IntR16, L, AddCO, AddR)
		variable temp8 : std_logic_vector(7 downto 0);
		variable temp16 : std_logic_vector(15 downto 0);
	begin
		ZR <= '0';
		case CTRL.secOp is
			when "000" => 
				CO <= CR;
				Result8 <= L(7 downto 0) or IntR8;
				Result16 <= L or IntR16;
			when "001"=> 
				CO <= CR;
				Result8 <= L(7 downto 0) and IntR8;
				Result16 <= L and IntR16;
			when "010" => 
				CO <= CR;
				Result8 <= L(7 downto 0) xor IntR8;
				Result16 <= L xor IntR16;
			when "011" | "110" | "111" => 
				CO <= AddCO;
				Result8 <= AddR(7 downto 0);
				Result16 <= AddR;
			when "100" => 
				CO <= CR;
				Result8 <= IntR8;
				Result16 <= IntR16;
			when "101" => 			--TRB,TSB
				CO <= CR;
				if CTRL.fc = '0' then
					Result8 <= IntR8 and (not L(7 downto 0));
					Result16 <= IntR16 and (not L);
				else
					Result8 <= IntR8 or L(7 downto 0);
					Result16 <= IntR16 or L;
				end if;
				
				temp8 := IntR8 and L(7 downto 0);
				temp16 := IntR16 and L;
				if (temp8 = x"00" and w16 = '0') or
					(temp16 = x"0000" and w16 = '1') then
					ZR <= '1';
				end if;
			when others => null;
		end case;
	end process;
	
	process(CTRL, w16, VI, SI, IntR8, IntR16, Result8, Result16, AddVO)
	begin
		VO <= VI; 
		if w16 = '0' then
			SO <= Result8(7); 
		else
			SO <= Result16(15); 
		end if; 
		case CTRL.secOp is
			when "001" => 
				if CTRL.fc = '1' then
					if w16 = '0' then
						VO <= IntR8(6); 		-- Set V to 6th bit for BIT 
						SO <= IntR8(7); 
					else
						VO <= IntR16(14); 	-- Set V to 14th bit for BIT 
						SO <= IntR16(15); 
					end if;
				end if;
			when "011" => 
				VO <= AddVO;					-- ADC always sets V.
			when "101" => 						--TRB,TSB
				SO <= SI; 
			when "111" => 
				if CTRL.fc = '1' then
					VO <= AddVO;           	-- Only SBC sets V. 
				end if;
			when others => null;
		end case;
	end process;
	
	
	ZO <= ZR when CTRL.secOp = "101" else
		   '1' when (w16 = '0' and Result8 = x"00") or (w16 = '1' and Result16 = x"0000") else 
			'0'; 
	
	RES <= x"00"&Result8 when w16 = '0' else Result16;
	IntR <= x"00"&IntR8 when w16 = '0' else IntR16;
	
end rtl;