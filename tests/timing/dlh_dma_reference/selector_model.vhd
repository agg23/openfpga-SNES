library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;
entity SelectorModel is port (
 P65_A : in std_logic_vector(23 downto 0);
 DMA_A : in std_logic_vector(23 downto 0);
 DMA_B : in std_logic_vector(7 downto 0);
 ENABLE : in std_logic;
 REFRESHED : in std_logic;
 DMA_RUN : in std_logic;
 HDMA_RUN : in std_logic;
 CPU_RD : in std_logic;
 CPU_WR : in std_logic;
 DMA_TRANSFER : in std_logic;
 HDMA_BUS_ACTIVE : in std_logic;
 DMA_B_RD : in std_logic;
 DMA_B_WR : in std_logic;
 DMA_A_RD : in std_logic;
 DMA_A_WR : in std_logic;
 HDMA_A_RD : in std_logic;
 HDMA_A_WR : in std_logic;
 HDMA_B_RD : in std_logic;
 HDMA_B_WR : in std_logic;
 DI : in std_logic_vector(7 downto 0);
 BUSB_DO : in std_logic_vector(7 downto 0);
 CPU_DO : in std_logic_vector(7 downto 0);
 CA : out std_logic_vector(23 downto 0);
 PA : out std_logic_vector(7 downto 0);
 PARD_N : out std_logic;
 PAWR_N : out std_logic;
 WRAM_DI : out std_logic_vector(7 downto 0);
 RAM_D : out std_logic_vector(7 downto 0);
 RAM_CE_N : out std_logic;
 RAM_WE_N : out std_logic;
 DMA_ACTIVE : out std_logic;
 BUSA_SEL : out std_logic
); end SelectorModel;
architecture exact of SelectorModel is
 signal INT_A : std_logic_vector(23 downto 0);
 signal INT_RAMSEL_N, INT_ROMSEL_N, INT_CPUWR_N, INT_CPURD_N : std_logic;
 signal EN, P65_EN : std_logic;
 signal BUSA_DO : std_logic_vector(7 downto 0);
 alias INT_CA : std_logic_vector(23 downto 0) is CA;
 alias INT_PARD_N : std_logic is PARD_N;
 alias CPUWR_N : std_logic is INT_CPUWR_N;
 alias RAMSEL_N : std_logic is INT_RAMSEL_N;

begin
-- Source: rtl/upstream/CPU.vhd
DMA_ACTIVE <= DMA_RUN or HDMA_RUN;

-- Source: rtl/upstream/CPU.vhd
EN <= ENABLE and (not REFRESHED);

-- Source: rtl/upstream/CPU.vhd
P65_EN <= not DMA_ACTIVE and ENABLE;

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
process(P65_A, EN, CPU_RD, CPU_WR, DMA_B, DMA_B_RD, DMA_B_WR, DMA_A_RD, DMA_A_WR, 
			  HDMA_A_RD, HDMA_A_WR, HDMA_B_RD, HDMA_B_WR, DMA_TRANSFER, HDMA_BUS_ACTIVE, P65_EN)
	begin
		if HDMA_BUS_ACTIVE = '1' and EN = '1' then
			PA <= DMA_B;
			PARD_N <= not HDMA_B_RD;
			PAWR_N <= not HDMA_B_WR;
		elsif DMA_TRANSFER = '1' and EN = '1' then
			PA <= DMA_B;
			PARD_N <= not DMA_B_RD;
			PAWR_N <= not DMA_B_WR;
		elsif P65_A(22) = '0' and P65_A(15 downto 8) = x"21" and P65_EN = '1' then
			PA <= P65_A(7 downto 0);
			PARD_N <= not CPU_RD;
			PAWR_N <= not CPU_WR;
		else
			PA <= x"FF";
			PARD_N <= '1';
			PAWR_N <= '1';
		end if;
		
		if HDMA_BUS_ACTIVE = '1' and EN = '1' then
			INT_CPURD_N <= not HDMA_A_RD;
			INT_CPUWR_N <= not HDMA_A_WR; 
		elsif DMA_TRANSFER = '1' and EN = '1' then
			INT_CPURD_N <= not DMA_A_RD;
			INT_CPUWR_N <= not DMA_A_WR;
		elsif P65_EN = '1' then
			INT_CPURD_N <= not CPU_RD;
			INT_CPUWR_N <= not CPU_WR; 
		else
			INT_CPURD_N <= '1';
			INT_CPUWR_N <= '1'; 
		end if;
	end process;

-- Source: rtl/upstream/SNES.vhd
BUSA_SEL <= '1' when INT_CA(22) = '0' and INT_CA(15 downto 8) /= x"21" else
					'1' when INT_CA(23 downto 16) >= x"40" and INT_CA(23 downto 16) <= x"7D" else 
					'1' when INT_CA(23 downto 16) >= x"C0" else
					'0';

-- Source: rtl/upstream/SNES.vhd
BUSA_DO <= x"00" when INT_CA(22) = '0' and (INT_CA(15 downto 8) = x"40" or INT_CA(15 downto 8) = x"42" or INT_CA(15 downto 8) = x"43") else DI;

-- Source: rtl/upstream/SNES.vhd
WRAM_DI <= BUSA_DO when BUSA_SEL = '1' else
				  BUSB_DO when INT_PARD_N = '0' else
				  CPU_DO;

swrampart: block is
 alias DI : std_logic_vector(7 downto 0) is WRAM_DI;
begin

-- Source: rtl/upstream/SWRAM.vhd
RAM_D <= x"FF" when PA = x"80" and RAMSEL_N = '0' else DI;

-- Source: rtl/upstream/SWRAM.vhd
RAM_CE_N <= '0' when ENABLE = '0' else 
					'0' when RAMSEL_N = '0' else
					'0' when PA = x"80" else 
					'1';

-- Source: rtl/upstream/SWRAM.vhd
RAM_WE_N <= '1' when ENABLE = '0' else
					'0' when RAMSEL_N = '0' and CPUWR_N = '0' else
					'0' when PA = x"80" and PAWR_N = '0' and RAMSEL_N = '1' else 
					'1';

end block;
end exact;
