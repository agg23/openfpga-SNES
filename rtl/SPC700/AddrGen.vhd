library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.SPC700_pkg.all;

entity SPC700_AddrGen is
    port( 
        CLK				: in std_logic;
		  RST_N			: in std_logic;
		  EN				: in std_logic;
		  ADDR_CTRL		: in std_logic_vector(5 downto 0); 
		  LOAD_PC		: in std_logic_vector(2 downto 0); 
		  GotInterrupt	: in std_logic; 
        D_IN			: in std_logic_vector(7 downto 0);
		  X				: in std_logic_vector(7 downto 0);
		  Y				: in std_logic_vector(7 downto 0);
		  S				: in std_logic_vector(7 downto 0);
		  T				: in std_logic_vector(7 downto 0);
		  P				: in std_logic; 
		  PC				: out std_logic_vector(15 downto 0);
        AX				: out std_logic_vector(15 downto 0);
		  ALCarry		: out std_logic;
		  
		  REG_DAT		: in std_logic_vector(15 downto 0);
		  REG_SET		: in std_logic
    );
end SPC700_AddrGen;

architecture rtl of SPC700_AddrGen is

	signal AL, AH : std_logic_vector(7 downto 0);
	signal SavedCarry : std_logic;
	
	signal NewAL, NewAH : std_logic_vector(8 downto 0);
	signal NewAHWithCarry : std_logic_vector(7 downto 0);
	signal NextAX : std_logic_vector(15 downto 0);
	
	signal DR : std_logic_vector(7 downto 0);
	signal PCr: std_logic_vector(15 downto 0);
	signal NextPC, NewPCWithOffset: std_logic_vector(15 downto 0);
		
	signal ALCtrl : std_logic_vector(1 downto 0);
	signal AHCtrl : std_logic_vector(1 downto 0);
	signal MuxCtrl : std_logic_vector(1 downto 0);

begin
	
	ALCtrl <= ADDR_CTRL(5 downto 4);
	AHCtrl <= ADDR_CTRL(3 downto 2);
	MuxCtrl <= ADDR_CTRL(1 downto 0);
		
	NewPCWithOffset <= std_logic_vector(unsigned(PCr) + unsigned((7 downto 0 => DR(7)) & DR)); 
	
	process(LOAD_PC, PCr, D_IN, DR, NewPCWithOffset, AL, AH, GotInterrupt)
	begin
		case LOAD_PC is
			when "000" =>
				NextPC <= PCr;
			when "001" => 
				if GotInterrupt = '0' then
					NextPC <= std_logic_vector(unsigned(PCr) + 1); 
				else
					NextPC <= PCr;
				end if;
			when "010"=> 
				NextPC <= D_IN & DR;
			when "011" => 
				NextPC <= NewPCWithOffset; 
			when "100" => 
				NextPC <= AH & AL; 
			when "101" => 
				NextPC <= x"FF" & AL; 
			when others =>
				NextPC <= PCr;
		end case;
	end process;
	
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			PCr <= (others=>'0');
			DR <= (others=>'0');
		elsif rising_edge(CLK) then 
			if REG_SET = '1' then
				PCr <= REG_DAT;
			elsif EN = '0' then
				
			else
				DR <= D_IN;
				PCr <= NextPC;
			end if;
		end if;
	end process;
	

	process(MuxCtrl, AL, X, Y, DR)
	begin
		case MuxCtrl is
			when "00" => 
				NewAL <= std_logic_vector(unsigned("0" & AL) + unsigned("0" & X));
			when "01" => 
				NewAL <= std_logic_vector(unsigned("0" & AL) + unsigned("0" & Y));
			when "10"=> 
				NewAL <= "0" & DR;
			when "11" => 
				NewAL <= std_logic_vector(unsigned("0" & DR) + unsigned("0" & Y));
			when others => null;
		end case;
	end process;
	  
	NewAHWithCarry <= std_logic_vector(unsigned(AH) + ("0000000"&SavedCarry));
	NextAX <= std_logic_vector((unsigned(AH) & unsigned(AL)) + 1);
	
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			AL <= (others=>'0');
			AH <= (others=>'0');
			SavedCarry <= '0';
		elsif rising_edge(CLK) then
			if EN = '1' then
				case ALCtrl is
					when "00" => SavedCarry <= '0';
					when "01" => AL <= NewAL(7 downto 0); SavedCarry <= NewAL(8); 
					when "10" => 
						case MuxCtrl is
							when "00" => AL <= D_IN; 
							when "01" => AL <= X;
							when "10" => AL <= Y;
							when others => null;
						end case;
						SavedCarry <= '0';
					when "11" => AL <= std_logic_vector(NextAX(7 downto 0)); SavedCarry <= '0';
					when others => null;
				end case;
					
				case AHCtrl is
					when "00" => null; 
					when "01" => AH <= "0000000"&P;
					when "10" => AH <= D_IN;
					when "11" => 
						if ALCtrl /= "11" then
							AH <= NewAHWithCarry;
						else
							AH <= std_logic_vector(NextAX(15 downto 8));
						end if;
					when others => null;
				end case;
				
			end if;
		end if;
	end process;

	ALCarry <= NewAL(8);
	AX <= AH & AL; 
	PC <= PCr;
	
end rtl;