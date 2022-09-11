library STD;
use STD.TEXTIO.ALL;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;

entity CX4Map is
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
		BSRAM_MASK	: in std_logic_vector(23 downto 0)
	);
end CX4Map;

architecture rtl of CX4Map is

	signal CX4_A : std_logic_vector(23 downto 0);
	signal CX4_DI : std_logic_vector(7 downto 0);
	signal SRAM_CE_N, ROM_CE1_N, ROM_CE2_N : std_logic;
	signal CART_ADDR : std_logic_vector(21 downto 0);
	signal BRAM_ADDR : std_logic_vector(19 downto 0);
	signal CX4_CE : std_logic;
	signal MAP_SEL	  : std_logic;
begin
	
	MAP_SEL <= '1' when MAP_CTRL(7 downto 4) = X"4" else '0';
	MAP_ACTIVE <= MAP_SEL;

	CEGen : entity work.CEGen
	port map(
		CLK     => MCLK,
		RST_N   => RST_N,
		IN_CLK  => 2147727,
		OUT_CLK => 2000000,
		CE      => CX4_CE
	);

	CX4 : entity work.CX4
	port map(
		CLK			=> MCLK,
		CE				=> CX4_CE,
		RST_N			=> RST_N and MAP_SEL,
		ENABLE		=> ENABLE,

		ADDR			=> CA,
		DO				=> DO,
		DI				=> DI,
		RD_N			=> CPURD_N,
		WR_N			=> CPUWR_N,
		
		SYSCLKF_CE	=> SYSCLKF_CE,
		SYSCLKR_CE	=> SYSCLKR_CE,
		
		IRQ_N			=> IRQ_N,
		
		BUS_A			=> CX4_A,
		BUS_DI		=> CX4_DI,
		BUS_DO		=> BSRAM_D,
		BUS_OE_N		=> BSRAM_OE_N,
		BUS_WE_N		=> BSRAM_WE_N,
		ROM_CE1_N	=> ROM_CE1_N,
		ROM_CE2_N	=> ROM_CE2_N,
		SRAM_CE_N	=> SRAM_CE_N,
		
		BUS_RD_N		=> ROM_OE_N,
		
		MAPPER		=> MAP_CTRL(0)
	);
	
	CART_ADDR <= CX4_A(22) & not ROM_CE2_N & CX4_A(20 downto 16) & CX4_A(14 downto 0);
	BRAM_ADDR <= CX4_A(20 downto 16) & CX4_A(14 downto 0);

	ROM_ADDR <= CART_ADDR and ROM_MASK(22 downto 0);
	ROM_CE_N <= ROM_CE1_N and ROM_CE2_N;
	ROM_WORD	<= '0';

	BSRAM_ADDR <= BRAM_ADDR and BSRAM_MASK(19 downto 0);
	BSRAM_CE_N <= SRAM_CE_N;

	CX4_DI <= BSRAM_Q when SRAM_CE_N = '0' else ROM_Q(7 downto 0);

end rtl;
