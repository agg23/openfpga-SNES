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
	signal divTemp : unsigned(16 downto 0);
	
begin
	
	process(CLK, RST_N)
		variable divTemp_shifted: unsigned(16 downto 0);
	begin
		if RST_N = '0' then
			mulA <= (others=>'0');
			mulY <= (others=>'0');
			mulRes <= (others=>'0');
			divTemp <= (others=>'0');
		elsif rising_edge(CLK) then 
			if EN = '1' then
				if CTRL.secOp = "1110" then
					mulRes <= mulTemp;
					mulA <= mulA(14 downto 0) & "0";
					mulY <= "0" & mulY(7 downto 1);
				elsif CTRL.secOp = "1111" then
					if (divTemp(15 downto 0) & divTemp(16)) >= unsigned(X & "000000000") then 
						divTemp_shifted := divTemp(15 downto 0) & not divTemp(16);
					else
						divTemp_shifted := divTemp(15 downto 0) &     divTemp(16);
					end if;
					if divTemp_shifted(0) = '1' then
						divTemp <= divTemp_shifted - unsigned(X & "000000000");
					else
						divTemp <= divTemp_shifted;
					end if;
				else
					mulA <= unsigned("00000000" & A);
					mulY <= unsigned(Y);
					mulRes <= (others=>'0');
					divTemp <= unsigned("0" & Y & A);
				end if;
			end if;
		end if;
	end process;

	process(CTRL, mulA, mulY, mulRes, mulTemp, divTemp)
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
			tResult <= std_logic_vector(divTemp(16 downto 9) & divTemp(7 downto 0));
			if divTemp(7 downto 0) = 0 then
				tZ <= '1';
			else
				tZ <= '0';
			end if;
			tV <= divTemp(8);
			tS <= divTemp(7);
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