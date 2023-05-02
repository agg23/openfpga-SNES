library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.SPC700_pkg.all;


entity MulDiv is
    port( 
		  CLK		: in std_logic;
		  RST_N	: in std_logic;
		  EN		: in std_logic;
		  CTRL	: in ALUCtrl_r;
		  A		: in std_logic_vector(7 downto 0); 
		  X		: in std_logic_vector(7 downto 0); 
		  Y		: in std_logic_vector(7 downto 0); 
        RES		: out std_logic_vector(15 downto 0);
		  ZO 		: out std_logic;
		  VO 		: out std_logic;
		  HO 		: out std_logic;
		  SO 		: out std_logic
    );
end MulDiv;

architecture rtl of MulDiv is

	signal tResult  : std_logic_vector(15 downto 0);
	signal tV, tZ, tS : std_logic;
	signal mulRes, mulTemp  : unsigned(15 downto 0);
	signal mulA  : unsigned(15 downto 0);
	signal mulY  : unsigned(7 downto 0);
	signal divt  : unsigned(15 downto 0);
	signal quotient : unsigned(8 downto 0);
	signal remainder : unsigned(15 downto 0);
	
begin
	
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			mulA <= (others=>'0');
			mulY <= (others=>'0');
			mulRes <= (others=>'0');
			divt <= (others=>'0');
			remainder <= (others=>'0');
			quotient <= (others=>'0');
		elsif rising_edge(CLK) then 
			if EN = '1' then
				if CTRL.secOp = "1110" then
					mulRes <= mulTemp;
					mulA <= mulA(14 downto 0) & "0";
					mulY <= "0" & mulY(7 downto 1);
				elsif CTRL.secOp = "1111" then
					if remainder >= divt then 
						remainder <= remainder - divt;
						quotient <= quotient(7 downto 0) & "1"; 
					else
						quotient <= quotient(7 downto 0) & "0"; 
					end if;
					divt <= "0" & divt(15 downto 1); 
				else
					mulA <= unsigned("00000000" & A);
					mulY <= unsigned(Y);
					mulRes <= (others=>'0');
					divt <= unsigned(X & "00000000");
					remainder <= unsigned(Y & A);
					quotient <= (others=>'0');
				end if;
			end if;
		end if;
	end process;

	process(CTRL, mulA, mulY, mulRes, mulTemp, quotient, remainder)
	begin
		mulTemp <= (others=>'0');
		if CTRL.secOp = "1110" then
			if mulY(0) = '1' then
				mulTemp <= mulRes + mulA;
			else
				mulTemp <= mulRes;
			end if;
			tResult <= std_logic_vector(mulTemp);
			if mulTemp(15 downto 8) = 0 then
				tZ <= '1';
			else
				tZ <= '0';
			end if;
			tV <= '0';
			tS <= mulTemp(15);
		elsif CTRL.secOp = "1111" then
			tResult <= std_logic_vector(remainder(7 downto 0) & quotient(7 downto 0));
			if quotient(7 downto 0) = 0 then
				tZ <= '1';
			else
				tZ <= '0';
			end if;
			tV <= quotient(8);
			tS <= quotient(7);
		else
			tResult <= (others=>'0');
			tZ <= '0';
			tV <= '0';
			tS <= '0';
		end if;
	end process;
	
	RES <= tResult;
	ZO <= tZ;
	VO <= tV;
	SO <= tS;
	HO <= '1' when Y(3 downto 0) >= X(3 downto 0) else '0';
	
end rtl;