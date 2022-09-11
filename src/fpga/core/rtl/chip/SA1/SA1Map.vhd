library STD;
use STD.TEXTIO.ALL;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;

entity SA1Map is
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
		
		PAL			: in std_logic;
		
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
		BSRAM_MASK	: in std_logic_vector(23 downto 0)
	);
end SA1Map;

architecture rtl of SA1Map is

	signal ROM_A		: std_logic_vector(22 downto 0);
	signal BWRAM_A 	: std_logic_vector(17 downto 0);
	signal MAP_SEL		: std_logic;

begin

	MAP_SEL <= '1' when MAP_CTRL(7 downto 4) = X"6" else '0';
	MAP_ACTIVE <= MAP_SEL;
	
	SA1 : entity work.SA1
	port map(
		CLK			=> MCLK,
		RST_N			=> RST_N and MAP_SEL,
		ENABLE		=> ENABLE,

		SNES_A		=> CA,
		SNES_DO		=> DO,
		SNES_DI		=> DI,
		SNES_RD_N	=> CPURD_N,
		SNES_WR_N	=> CPUWR_N,
		
		SYSCLKF_CE	=> SYSCLKF_CE,
		SYSCLKR_CE	=> SYSCLKR_CE,
		
		REFRESH		=> REFRESH,
		
		PAL			=> PAL,
		
		ROM_A			=> ROM_A,
		ROM_DI		=> ROM_Q,
		ROM_RD_N		=> ROM_OE_N,
		
		BWRAM_A		=> BWRAM_A,
		BWRAM_DI		=> BSRAM_Q,
		BWRAM_DO		=> BSRAM_D,
		BWRAM_OE_N	=> BSRAM_OE_N,
		BWRAM_WE_N	=> BSRAM_WE_N,
		
		IRQ_N			=> IRQ_N
	);

	ROM_ADDR 	<= ROM_A and ROM_MASK(22 downto 0);
	ROM_CE_N 	<= '0';
	ROM_WORD		<= '1';

	BSRAM_ADDR 	<= ("00" & BWRAM_A) and BSRAM_MASK(19 downto 0);
	BSRAM_CE_N 	<= '0';

end rtl;