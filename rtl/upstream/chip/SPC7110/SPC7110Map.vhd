library STD;
use STD.TEXTIO.ALL;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;

entity SPC7110Map is
	port(
		MCLK			: in std_logic;
		RST_N			: in std_logic;
		ENABLE		: in std_logic := '1';

		CA   			: in std_logic_vector(23 downto 0);
		DI				: in std_logic_vector(7 downto 0);
		DO				: out std_logic_vector(7 downto 0);
		CPURD_N		: in std_logic;
		CPUWR_N		: in std_logic;
		
		PA				: in std_logic_vector(7 downto 0);
		PARD_N		: in std_logic;
		PAWR_N		: in std_logic;
		
		ROMSEL_N		: in std_logic;
		RAMSEL_N		: in std_logic;
		
		SYSCLKF_CE	: in std_logic;
		SYSCLKR_CE	: in std_logic;
		REFRESH		: in std_logic;
		
		IRQ_N			: out std_logic;

		ROM_ADDR		: out std_logic_vector(22 downto 0);
		ROM_Q			: in  std_logic_vector(15 downto 0);
		ROM_CE_N		: out std_logic;
		ROM_OE_N		: out std_logic;
		ROM_WORD		: out std_logic;
		
		BSRAM_ADDR	: out std_logic_vector(19 downto 0);
		BSRAM_D		: out std_logic_vector(7 downto 0);
		BSRAM_Q		: in  std_logic_vector(7 downto 0);
		BSRAM_CE_N	: out std_logic;
		BSRAM_OE_N	: out std_logic;
		BSRAM_WE_N	: out std_logic;

		MAP_ACTIVE  : out std_logic;
		MAP_CTRL		: in std_logic_vector(7 downto 0);
		ROM_MASK		: in std_logic_vector(23 downto 0);
		BSRAM_MASK	: in std_logic_vector(23 downto 0);
		
		EXT_RTC		: in std_logic_vector(64 downto 0)
	);
end SPC7110Map;

architecture rtl of SPC7110Map is

	signal PROM_OE_N 				: std_logic;
	
	signal SPC7110_DROM_A 		: std_logic_vector(22 downto 0);
	signal SPC7110_DROM_DO		: std_logic_vector(7 downto 0);
	signal SPC7110_DROM_OE_N	: std_logic;
	signal SPC7110_DROM_RDY 	: std_logic;
	signal SNES_DROM_A 			: std_logic_vector(22 downto 0);
	signal SNES_DROM_OE_N 		: std_logic;
	
	signal SRAM_CE_N 				: std_logic;
	
	signal RTC_DI 					: std_logic_vector(3 downto 0);
	signal RTC_DO 					: std_logic_vector(3 downto 0);
	signal RTC_CE 					: std_logic;
	signal RTC_CK 					: std_logic;
		
	signal SPC7110_DO 			: std_logic_vector(7 downto 0);
	signal SNES_ROM_ACTIVE 		: std_logic;
	signal SPC7110_DROM_ACTIVE	: std_logic;
	signal ROM_RD 					: std_logic;
	signal ROM_RD_LATE 			: std_logic;
	
	signal MAP_SEL	  				: std_logic;
	
begin
	
	MAP_SEL <= '1' when MAP_CTRL(7 downto 4) = X"D" else '0';
	MAP_ACTIVE <= MAP_SEL;

	SPC7110 : entity work.SPC7110
	port map(
		RST_N				=> RST_N and MAP_SEL,
		CLK				=> MCLK,
		ENABLE			=> ENABLE,

		CA					=> CA,
		DO					=> SPC7110_DO,
		DI					=> DI,
		CPURD_N			=> CPURD_N,
		CPUWR_N			=> CPUWR_N,
		
		SYSCLKF_CE		=> SYSCLKF_CE,
		SYSCLKR_CE		=> SYSCLKR_CE,

		DROM_A			=> SPC7110_DROM_A,
		DROM_OE_N		=> SPC7110_DROM_OE_N,
		DROM_DO			=> ROM_Q(7 downto 0),
		DROM_RDY			=> SPC7110_DROM_RDY,
		
		PROM_OE_N		=> PROM_OE_N,
		SNES_DROM_A		=> SNES_DROM_A,
		SNES_DROM_OE_N	=> SNES_DROM_OE_N,
		SRAM_CE_N		=> SRAM_CE_N,
		
		RTC_DO			=> RTC_DI,
		RTC_DI			=> RTC_DO,
		RTC_CE			=> RTC_CE,
		RTC_CK			=> RTC_CK
	);
	
	RTC : entity work.RTC4513
	port map(
		CLK			=> MCLK,
		ENABLE		=> ENABLE,

		DO				=> RTC_DO,
		DI				=> RTC_DI,
		CE				=> RTC_CE,
		CK				=> RTC_CK,
		
		EXT_RTC		=> EXT_RTC
	);
	
	
	process(MCLK, RST_N)
	begin
		if RST_N = '0' then
			SNES_ROM_ACTIVE <= '0';
			SPC7110_DROM_ACTIVE <= '0';
			SPC7110_DROM_RDY <= '0';
			ROM_RD_LATE <= '0';
		elsif rising_edge(MCLK) then
			if SYSCLKF_CE = '1' then
				SPC7110_DROM_ACTIVE <= not SPC7110_DROM_OE_N;
				SNES_ROM_ACTIVE <= '0';
			elsif SYSCLKR_CE = '1' then
				SPC7110_DROM_ACTIVE <= '0';
				SNES_ROM_ACTIVE <= '1';
			end if;
			
			ROM_RD_LATE <= ROM_RD;	--waiting for 2 cycles of reading sdram
						
			SPC7110_DROM_RDY <= '0';
			if SPC7110_DROM_RDY = '0' and ROM_RD_LATE = '1' and SPC7110_DROM_ACTIVE = '1' then
				SPC7110_DROM_RDY <= '1';
			end if;
		end if;
	end process;
	
	process(MCLK, RST_N)
	begin
		if RST_N = '0' then
			ROM_RD <= '0';
		elsif rising_edge(MCLK) then
			ROM_RD <= '0';
			if SYSCLKR_CE = '1' or SYSCLKF_CE = '1' then
				ROM_RD <= '1';
			end if;
		end if;
	end process;
	
	-- SYSCLK |___|---|
	-- 0 - slot for SPC7110 for DROM access if need, else same SNES access (for sdram refresh)
	-- 1 - slot for SNES for PROM/DROM access, first 1 MByte - PROM, rest - DROM
	process(CA, SPC7110_DROM_A, SNES_DROM_A, SPC7110_DROM_ACTIVE, SNES_DROM_OE_N, SNES_ROM_ACTIVE)
	begin
		if SNES_ROM_ACTIVE = '0' then
			if SPC7110_DROM_ACTIVE = '1' then
				ROM_ADDR <= std_logic_vector(unsigned(SPC7110_DROM_A(22 downto 20)) + "001") & SPC7110_DROM_A(19 downto 0);
			else
				ROM_ADDR <= (not CA(23) and CA(22)) & (not CA(23) and CA(22)) & "0" & CA(19 downto 0);
			end if;
		else
			if SNES_DROM_OE_N = '0' then
				ROM_ADDR <= std_logic_vector(unsigned(SNES_DROM_A(22 downto 20)) + "001") & SNES_DROM_A(19 downto 0);
			else
				ROM_ADDR <= (not CA(23) and CA(22)) & (not CA(23) and CA(22)) & "0" & CA(19 downto 0);
			end if;
		end if;
	end process;
	ROM_CE_N 	<= '0';
	ROM_OE_N 	<= not ROM_RD;
	ROM_WORD		<= '0';

	BSRAM_ADDR <= ("0000000" & CA(12 downto 0)) and BSRAM_MASK(19 downto 0);
	BSRAM_D    <= DI;
	BSRAM_CE_N <= SRAM_CE_N;
	BSRAM_OE_N <= CPURD_N;
	BSRAM_WE_N <= CPUWR_N;

	DO <= ROM_Q(7 downto 0) when PROM_OE_N = '0' or SNES_DROM_OE_N = '0' else
			BSRAM_Q when SRAM_CE_N = '0' else 
			SPC7110_DO;
			
	IRQ_N <= '1';
	
end rtl;
