library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;
entity AddressReference is port (
 P65_A : in std_logic_vector(23 downto 0);
 DMA_A : in std_logic_vector(23 downto 0);
 DMA_RUN : in std_logic;
 HDMA_RUN : in std_logic;
 CA : out std_logic_vector(23 downto 0);
 RAMSEL_N : out std_logic;
 ROMSEL_N : out std_logic
); end AddressReference;
architecture exact of AddressReference is
 signal INT_A : std_logic_vector(23 downto 0);
 signal INT_RAMSEL_N, INT_ROMSEL_N, DMA_ACTIVE : std_logic;

begin
-- Source: rtl/upstream/CPU.vhd
INT_A <= DMA_A when HDMA_RUN = '1' or DMA_RUN = '1' else
				P65_A;
-- Source: rtl/upstream/CPU.vhd
process(INT_A)
	begin
		INT_RAMSEL_N <= '1';
		INT_ROMSEL_N <= '1';
		
		CA <= INT_A;

		if INT_A(22) = '0' then 							--$00-$3F, $80-$BF
			if INT_A(15 downto 13) = "000" then			--$0000-$1FFF | Slow  | Address Bus A + /WRAM (mirror $7E:0000-$1FFF)
				CA(23 downto 13) <= x"7E" & "000";
				INT_RAMSEL_N <= '0';
			elsif INT_A(15) = '1' then	 					--$8000-$FFFF | Slow  | Address Bus A + /CART
				INT_ROMSEL_N <= '0';
			end if;
		else														--$40-$7F, $C0-$FF
			if INT_A(23 downto 17) = "0111111" then	--$7E-$7F | $0000-$FFFF | Slow  | Address Bus A + /WRAM
				INT_RAMSEL_N <= '0';
			elsif INT_A(23 downto 22) = "01" or			--$40-$7D | $0000-$FFFF | Slow  | Address Bus A + /CART
				  INT_A(23 downto 22) = "11" then		--$C0-$FF | $0000-$FFFF | Fast,Slow | Address Bus A + /CART
				INT_ROMSEL_N <= '0';
			end if;
		end if;
	end process;
-- Source: rtl/upstream/CPU.vhd
RAMSEL_N <= INT_RAMSEL_N;
-- Source: rtl/upstream/CPU.vhd
ROMSEL_N <= INT_ROMSEL_N;

end exact;
