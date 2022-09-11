library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.P65816_pkg.all;

entity AddrGen is
    port( 
        CLK 			: in std_logic;
		  RST_N 			: in std_logic;
		  EN 				: in std_logic;
		  LOAD_PC		: in std_logic_vector(2 downto 0); 
		  PCDec 			: in std_logic;
		  GotInterrupt	: in std_logic; 
        ADDR_CTRL		: in std_logic_vector(7 downto 0); 
		  IND_CTRL  	: in std_logic_vector(1 downto 0); 
        D_IN   		: in std_logic_vector(7 downto 0);
		  X   			: in std_logic_vector(15 downto 0);
		  Y   			: in std_logic_vector(15 downto 0);
		  D   			: in std_logic_vector(15 downto 0);
		  S   			: in std_logic_vector(15 downto 0);
		  T     			: in std_logic_vector(15 downto 0);
		  DR   			: in std_logic_vector(7 downto 0);
		  DBR   			: in std_logic_vector(7 downto 0);
		  e6502 			: in std_logic;
		  PC				: out std_logic_vector(15 downto 0);
        AA     		: out std_logic_vector(16 downto 0);
		  AB     		: out std_logic_vector(7 downto 0);
		  DX				: out std_logic_vector(15 downto 0);
		  AALCarry 		: out std_logic;
		  JumpNoOfl		: out std_logic
    );
end AddrGen;

architecture rtl of AddrGen is

	signal AAL, AAH : std_logic_vector(7 downto 0);
	signal DL, DH : std_logic_vector(7 downto 0);
	signal SavedCarry, AAHCarry : std_logic;
	
	signal NewAAL, NewAAH, NewAAHWithCarry, NewDL : std_logic_vector(8 downto 0);
	signal InnerDS : std_logic_vector(15 downto 0);
	
	signal PCr: std_logic_vector(15 downto 0);
	signal NextPC, NewPCWithOffset, NewPCWithOffset16: std_logic_vector(15 downto 0);
	signal PCOffset: unsigned(15 downto 0);
		
	signal AALCtrl : std_logic_vector(2 downto 0);
	signal AAHCtrl : std_logic_vector(2 downto 0);
	signal ABSCtrl : std_logic_vector(1 downto 0);

begin

	NewPCWithOffset16 <= std_logic_vector(unsigned(PCr) + PCOffset); 
	NewPCWithOffset <= std_logic_vector(unsigned(PCr) + unsigned((7 downto 0 => DR(7)) & DR)); 
	
	process(CLK, RST_N, LOAD_PC, PCr, GotInterrupt, D_IN, DR, NewPCWithOffset16, NewPCWithOffset, AAH, AAL, PCDec )
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
				NextPC <= NewPCWithOffset16;
			when "100" => 
				NextPC <= NewPCWithOffset; 
			when "101" => 
				NextPC <= NewPCWithOffset16; 
			when "110" => 
				NextPC <= AAH & AAL; 
			when "111" => 
				if PCDec = '1' then
					NextPC <= std_logic_vector(unsigned(PCr) - 3);
				else
					NextPC <= PCr;
				end if;
			when others => 
				NextPC <= PCr;
		end case;
		
		if RST_N = '0' then
			PCr <= (others=>'0');
			PCOffset <= (others=>'0');
		elsif rising_edge(CLK) then
			if EN = '1' then
				PCOffset <= unsigned(D_IN & DR);
				PCr <= NextPC;
			end if;
		end if;
	end process;
	
	JumpNoOfl <= (not (PCr(8) xor NewPCWithOffset(8))) and (not LOAD_PC(0)) and (not LOAD_PC(1)) and LOAD_PC(2);
		
	
	AALCtrl <= ADDR_CTRL(7 downto 5);
	AAHCtrl <= ADDR_CTRL(4 downto 2);
	ABSCtrl <= ADDR_CTRL(1 downto 0);
	
	process(IND_CTRL, AALCtrl, AAHCtrl, e6502, AAL, AAH, DL, DH, X, Y, NewAAL)
	begin
		case IND_CTRL is
			when "00" => 
				if AALCtrl(2) = '0' then
					NewAAL <= std_logic_vector(unsigned("0" & AAL) + unsigned("0" & X(7 downto 0)));
				else
					NewAAL <= std_logic_vector(unsigned("0" & DL) + unsigned("0" & X(7 downto 0)));
				end if;
			when "01" => 
				if AALCtrl(2) = '0' then
					NewAAL <= std_logic_vector(unsigned("0" & AAL) + unsigned("0" & Y(7 downto 0)));
				else
					NewAAL <= std_logic_vector(unsigned("0" & DL) + unsigned("0" & Y(7 downto 0)));
				end if;
			when "10"=> 
				NewAAL <= "0" & X(7 downto 0);
			when "11" => 
				NewAAL <= "0" & Y(7 downto 0);
			when others => null;
		end case;
		
		if e6502 = '0' then
			case IND_CTRL is
				when "00" => 
					if AAHCtrl(2) = '0' then
						NewAAH <= std_logic_vector( unsigned("0" & AAH) + unsigned("0" & X(15 downto 8)) );
					else
						NewAAH <= std_logic_vector( unsigned("0" & DH) + unsigned("0" & X(15 downto 8)) + ("00000000"&NewAAL(8)) );
					end if;
				when "01" => 
					if AAHCtrl(2) = '0' then
						NewAAH <= std_logic_vector( unsigned("0" & AAH) + unsigned("0" & Y(15 downto 8)) );
					else
						NewAAH <= std_logic_vector( unsigned("0" & DH) + unsigned("0" & Y(15 downto 8)) + ("00000000"&NewAAL(8)) );
					end if;
				when "10"=> 
					NewAAH <= "0" & X(15 downto 8);
				when "11" => 
					NewAAH <= "0" & Y(15 downto 8);
				when others => null;
			end case;
		else 
			if AAHCtrl(2) = '0' then
				NewAAH <= "0" & AAH;
			else
				NewAAH <= "0" & DH;
			end if;
		end if;
	end process;

	InnerDS <= S when ABSCtrl = "11" and (AALCtrl(2) = '1' or AAHCtrl(2) = '1') else
				  D when e6502 = '0' else 
				  D(15 downto 8) & x"00";
				  
	NewDL <= std_logic_vector(unsigned("0" & InnerDS(7 downto 0)) + unsigned("0" & D_IN));
	NewAAHWithCarry <= std_logic_vector(unsigned(NewAAH) + ("00000000"&SavedCarry));
	
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			AAL <= (others=>'0');
			AAH <= (others=>'0');
			AB <= (others=>'0');
			DL <= (others=>'0');
			DH <= (others=>'0');
			AAHCarry <= '0';
			SavedCarry <= '0';
		elsif rising_edge(CLK) then
			if EN = '1' then
				case AALCtrl is
					when "000" => 
						if IND_CTRL(1) = '1' then
							AAL <= NewAAL(7 downto 0);
						end if;
						SavedCarry <= '0';
					when "001" => AAL <= NewAAL(7 downto 0); SavedCarry <= NewAAL(8); 
					when "010" => AAL <= D_IN; SavedCarry <= '0';
					when "011" => AAL <= NewPCWithOffset16(7 downto 0); SavedCarry <= '0';
					when "100" => DL <= NewAAL(7 downto 0); SavedCarry <= NewAAL(8); 
					when "101" => DL <= NewDL(7 downto 0); SavedCarry <= NewDL(8);
					when "111" => null;
					when others => null;
				end case;
					
				case AAHCtrl is
					when "000" => 
						if IND_CTRL(1) = '1' then
							AAH <= NewAAH(7 downto 0);
							AAHCarry <= '0';
						end if;
					when "001" => 
						AAH <= NewAAHWithCarry(7 downto 0); 
						AAHCarry <= NewAAHWithCarry(8);
					when "010" => AAH <= D_IN; AAHCarry <= '0';
					when "011" => AAH <= NewPCWithOffset16(15 downto 8); AAHCarry <= '0';
					when "100" => DH <= NewAAH(7 downto 0); AAHCarry <= '0';
					when "101" => DH <= InnerDS(15 downto 8); AAHCarry <= '0';
					when "110" => DH <= std_logic_vector(unsigned(DH) + ("0000000"&SavedCarry)); AAHCarry <= '0';
					when "111" => null;
					when others => null;
				end case;

				case ABSCtrl is
					when "00" => null;
					when "01" => 
						AB <= D_IN;
					when "10" => 
						AB <= std_logic_vector(unsigned(D_IN) + ("0000000"&NewAAHWithCarry(8)));
					when "11" => 	
						if AALCtrl(2) = '0' and AAHCtrl(2) = '0' then
							AB <= std_logic_vector(unsigned(DBR));
						end if;
					when others => null;
				end case;
				
			end if;
		end if;
	end process;

	AALCarry <= NewAAL(8);
	AA <= AAHCarry & AAH & AAL; 
	DX <= DH & DL;
	PC <= PCr;
	
end rtl;