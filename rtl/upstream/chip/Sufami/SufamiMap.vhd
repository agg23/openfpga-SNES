library STD;
use STD.TEXTIO.ALL;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;

entity SufamiMap is
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

		ROM_ADDR		: out std_logic_vector(23 downto 0);
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

		EXT_RTC		: in  std_logic_vector(64 downto 0);
		
		CART_SWAP	: in std_logic
	);
end SufamiMap;

architecture rtl of SufamiMap is

	signal TURBO_SET  	: std_logic;
	signal SWAP  			: std_logic;
	
	signal CART_ADDR 		: std_logic_vector(23 downto 0);
	signal CART_MASK 		: std_logic_vector(23 downto 0);
	signal ROM_BIOS_SEL 	: std_logic;
	signal ROM_BASE_SEL 	: std_logic;
	signal ROM_TURBO_SEL : std_logic;
	signal SRAM_ADDR 		: std_logic_vector(19 downto 0);
	signal SRAM_MASK		: std_logic_vector(19 downto 0);
	signal SRAM_BASE_SEL : std_logic;
	signal SRAM_TURBO_SEL: std_logic;

	signal OPENBUS   		: std_logic_vector(7 downto 0);
	signal ROM_RD	  		: std_logic;

begin

	MAP_ACTIVE <= '1' when MAP_CTRL(7 downto 4) = x"2" else '0';
	TURBO_SET <= MAP_CTRL(3);
	SWAP <= CART_SWAP and TURBO_SET;
	
	CART_ADDR <= "00" & "0000" & CA(18 downto 16) & CA(14 downto 0) when CA(22 downto 21) = "00" else "00" & (CA(22) or SWAP) & (CA(21) and not SWAP) & CA(20 downto 16) & CA(14 downto 0);
	CART_MASK <= x"03FFFF" when CA(22 downto 21) = "00" else "0011" & ROM_MASK(19 downto 0);
	ROM_BIOS_SEL <= not ROMSEL_N when CA(22 downto 21) = "00" else '0';
	ROM_BASE_SEL <= not ROMSEL_N when CA(22 downto 21) = "01" else '0';
	ROM_TURBO_SEL <= not ROMSEL_N when CA(22 downto 21) = "10" and TURBO_SET = '1' and CART_SWAP = '0' else '0';
	
	SRAM_ADDR <= "00000000" & (CA(20) or SWAP) & CA(10 downto 0) when BSRAM_MASK(12 downto 11) = "00" else "000000" & (CA(20) or SWAP) & CA(12 downto 0);
	SRAM_MASK <= "00000000" & BSRAM_MASK(10) & BSRAM_MASK(10 downto 0) when BSRAM_MASK(12 downto 11) = "00" else "000000" & BSRAM_MASK(12) & BSRAM_MASK(12 downto 0);
	SRAM_BASE_SEL  <= not CA(20) and not ROMSEL_N when CA(22 downto 21) = "11"                     else '0';
	SRAM_TURBO_SEL <=     CA(20) and not ROMSEL_N when CA(22 downto 21) = "11" and TURBO_SET = '1' and CART_SWAP = '0' else '0';

--	ROM_RD <= (SYSCLKF_CE or SYSCLKR_CE) when rising_edge(MCLK);
	process(MCLK)
	begin
		if rising_edge(MCLK) then
			if SYSCLKR_CE = '1' then
				ROM_ADDR <= CART_ADDR and CART_MASK;
			end if;
			
			if SYSCLKR_CE = '1' or SYSCLKF_CE = '1' then
				ROM_RD <= '1';
			else
				ROM_RD <= '0';
			end if;
		end if;
	end process;

--	ROM_ADDR <= CART_ADDR and CART_MASK;
	ROM_CE_N <= ROMSEL_N;
	ROM_OE_N <= not ROM_RD;
	ROM_WORD	<= '0';

	BSRAM_ADDR <= SRAM_ADDR and SRAM_MASK;
	BSRAM_CE_N <= not (SRAM_BASE_SEL or SRAM_TURBO_SEL);
	BSRAM_OE_N <= CPURD_N;
	BSRAM_WE_N <= CPUWR_N;
	BSRAM_D    <= DI;

	process(MCLK, RST_N)
	begin
		if RST_N = '0' then
			OPENBUS <= (others => '1');
		elsif rising_edge(MCLK) then
			if SYSCLKR_CE = '1' then
				OPENBUS <= DI;
			end if;
		end if;
	end process;

	DO <= ROM_Q(7 downto 0) when ROM_BIOS_SEL = '1' or ROM_BASE_SEL = '1' or ROM_TURBO_SEL = '1' else
			BSRAM_Q when SRAM_BASE_SEL = '1' or SRAM_TURBO_SEL = '1' else
			OPENBUS;

	IRQ_N <= '1';

end rtl;
