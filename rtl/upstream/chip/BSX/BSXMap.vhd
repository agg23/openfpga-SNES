library STD;
use STD.TEXTIO.ALL;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;

entity BSXMap is
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
		ROM_D			: out  std_logic_vector(15 downto 0);
		ROM_Q			: in  std_logic_vector(15 downto 0);
		ROM_CE_N		: out std_logic;
		ROM_OE_N		: out std_logic;
		ROM_WE_N		: out std_logic;
		ROM_WORD		: out std_logic;
		
		BSRAM_ADDR	: out std_logic_vector(19 downto 0);
		BSRAM_D		: out std_logic_vector(7 downto 0);
		BSRAM_Q		: in  std_logic_vector(7 downto 0);
		BSRAM_CE_N	: out std_logic;
		BSRAM_OE_N	: out std_logic;
		BSRAM_WE_N	: out std_logic;

		EXT_RTC     : in std_logic_vector(64 downto 0);

		MAP_ACTIVE  : out std_logic;
		MAP_CTRL		: in std_logic_vector(7 downto 0);
		ROM_MASK		: in std_logic_vector(23 downto 0);
		BSRAM_MASK	: in std_logic_vector(23 downto 0)
	);
end BSXMap;

architecture rtl of BSXMap is

	--BS
	signal BS_DO			: std_logic_vector(7 downto 0);
	
	--MCC
	signal ADDR 			: std_logic_vector(19 downto 15);
	signal DO7	  			: std_logic;
	signal BIOS_CE_N 		: std_logic;
	signal SRAM_CE_N 		: std_logic;
	signal DPAK_CE_N 		: std_logic;
	signal DPAK_WR_N 		: std_logic;
	signal PSRAM_CE_N 	: std_logic;
	signal IOPORT_CE_N 	: std_logic;
	
	--BIOS
	signal BIOS_ADDR		: std_logic_vector(19 downto 0);
	
	--PSRAM
	signal PSRAM_ADDR		: std_logic_vector(18 downto 0);
	signal PSRAM_MEM_ADDR: std_logic_vector(18 downto 0);
	signal PSRAM_MEM_DATA: std_logic_vector(7 downto 0);
	signal PSRAM_MEM_WR	: std_logic;
	signal PSRAM_RD		: std_logic;
	
	--DataPak
	signal DPAK_ADDR		: std_logic_vector(19 downto 0);
	signal DPAK_DO			: std_logic_vector(7 downto 0);
	signal DPAK_MEM_ADDR : std_logic_vector(19 downto 0);
	signal DPAK_MEM_DO	: std_logic_vector(7 downto 0);
	signal DPAK_MEM_RD	: std_logic;
	signal DPAK_MEM_WR	: std_logic;
	signal DPAK_RD			: std_logic;
	
	--Memory 
	signal MEM_RD_PULSE	: std_logic;
	signal MEM_WR_PULSE	: std_logic;
	signal MEM_RW_PHASE	: std_logic;
	
	signal MAP_SEL	  		: std_logic;
	signal OPENBUS   		: std_logic_vector(7 downto 0);
	
begin
	
	MAP_SEL <= '1' when MAP_CTRL(7 downto 4) = x"3" else '0';
	MAP_ACTIVE <= MAP_SEL;
	
	BS : entity work.BS
	port map(
		CLK			=> MCLK,
		RST_N			=> RST_N and MAP_SEL,
		ENABLE		=> ENABLE,

		A				=> PA,
		DI				=> DI,
		DO				=> BS_DO,
		RD_N			=> PARD_N,
		WR_N			=> PAWR_N,
		SYSCLKF_CE	=> SYSCLKF_CE,
		
		EXT_RTC		=> EXT_RTC
	);
	
	MCC : entity work.MCC
	port map(
		CLK			=> MCLK,
		RST_N			=> RST_N and MAP_SEL,
		ENABLE		=> ENABLE,

		CA				=> CA(23 downto 12),
		DI7			=> DI(7),
		DO7			=> DO7,
		RD_N			=> CPURD_N,
		WR_N			=> CPUWR_N,
		
		SYSCLKF_CE	=> SYSCLKF_CE,
		
		BIOS_CE_N	=> BIOS_CE_N,
		SRAM_CE_N	=> SRAM_CE_N,
		
		ADDR			=> ADDR,
		DPAK_CE_N	=> DPAK_CE_N,
		DPAK_WR_N	=> DPAK_WR_N,
		PSRAM_CE_N	=> PSRAM_CE_N,
		
		IOPORT_CE_N	=> IOPORT_CE_N
	);
	
	
--	DPAK_ADDR <= ADDR&CA(14 downto 0);
	process( RST_N, MCLK)
	begin
		if RST_N = '0' then
			DPAK_RD <= '0';
		elsif rising_edge(MCLK) then
			if SYSCLKR_CE = '1' then
				DPAK_ADDR <= ADDR&CA(14 downto 0);
				DPAK_RD <= not DPAK_CE_N;
			end if;
		end if;
	end process;
	
	DP : entity work.DATAPAK
	port map(
		CLK			=> MCLK,
		RST_N			=> RST_N and MAP_SEL,
		ENABLE		=> ENABLE,

		A				=> ADDR&CA(14 downto 0),
		DI				=> DI,
		DO				=> DPAK_DO,
		CE_N			=> DPAK_CE_N,
		RD_N			=> CPURD_N,
		WR_N			=> DPAK_WR_N,
		SYSCLKF_CE	=> SYSCLKF_CE,
		SYSCLKR_CE	=> SYSCLKR_CE,
		
		MEM_ADDR		=> DPAK_MEM_ADDR,
		MEM_DI		=> ROM_Q(7 downto 0),
		MEM_DO		=> DPAK_MEM_DO,
		MEM_RD		=> DPAK_MEM_RD,
		MEM_WR		=> DPAK_MEM_WR
	);
	
	
--	PSRAM_ADDR <= ADDR(18 downto 15) & CA(14 downto 0);
	process( RST_N, MCLK)
	begin
		if RST_N = '0' then
			PSRAM_MEM_WR <= '0';
			PSRAM_MEM_ADDR <= (others => '0');
			PSRAM_MEM_DATA <= (others => '0');
			PSRAM_RD <= '0';
		elsif rising_edge(MCLK) then
			if SYSCLKF_CE = '1' then
				if PSRAM_CE_N = '0' and CPUWR_N = '0'  then
					PSRAM_MEM_ADDR <= ADDR(18 downto 15) & CA(14 downto 0);
					PSRAM_MEM_DATA <= DI;
					PSRAM_MEM_WR <= '1';
				else
					PSRAM_MEM_WR <= '0';
				end if;
			end if;
			
			if SYSCLKR_CE = '1' then
				PSRAM_ADDR <= ADDR(18 downto 15) & CA(14 downto 0);
				PSRAM_RD <= not PSRAM_CE_N;
			end if;
		end if;
	end process;
	
	
	process( RST_N, MCLK)
	begin
		if RST_N = '0' then
			MEM_RD_PULSE <= '0';
			MEM_WR_PULSE <= '0';
			MEM_RW_PHASE <= '0';
		elsif rising_edge(MCLK) then
			MEM_RD_PULSE <= SYSCLKF_CE or SYSCLKR_CE;
			MEM_WR_PULSE <= SYSCLKF_CE;
			if SYSCLKF_CE = '1' then
				MEM_RW_PHASE <= '1';
			elsif SYSCLKR_CE = '1' then
				MEM_RW_PHASE <= '0';
			end if;
			
			if SYSCLKR_CE = '1' then
				BIOS_ADDR <= CA(20 downto 16)&CA(14 downto 0);
			end if;
		end if;
	end process;
	
--	BIOS_ADDR <= CA(20 downto 16)&CA(14 downto 0);
	
	ROM_ADDR <= "001"&DPAK_MEM_ADDR      when (DPAK_MEM_WR = '1' or DPAK_MEM_RD = '1') and MEM_RW_PHASE = '1' else	--Datapak write/erase command only
					"010"&"0"&PSRAM_MEM_ADDR when PSRAM_MEM_WR = '1' and MEM_RW_PHASE = '1'                       else	--PSRAM write only
					"001"&DPAK_ADDR          when DPAK_RD = '1'                                                   else	--Datapak normal read
					"010"&"0"&PSRAM_ADDR     when PSRAM_RD = '1'                                                  else	--PSRAM normal read
					"000"&BIOS_ADDR;
	ROM_D    <= DPAK_MEM_DO&DPAK_MEM_DO       when DPAK_MEM_WR = '1' else 
					PSRAM_MEM_DATA&PSRAM_MEM_DATA when PSRAM_MEM_WR = '1' else 
					x"AA55";
	ROM_CE_N <= BIOS_CE_N and DPAK_CE_N and PSRAM_CE_N;
	ROM_OE_N <= not (MEM_RD_PULSE);
	ROM_WE_N <= not (MEM_WR_PULSE and (DPAK_MEM_WR or PSRAM_MEM_WR));
	ROM_WORD	<= '0';

	BSRAM_ADDR <="0000"&CA(19 downto 16)&CA(11 downto 0) and BSRAM_MASK(19 downto 0);
	BSRAM_D    <= DI;
	BSRAM_CE_N <= SRAM_CE_N;
	BSRAM_OE_N <= CPURD_N;
	BSRAM_WE_N <= CPUWR_N;
	
	
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

	DO <= BS_DO                   when PARD_N = '0' else 
			DO7&OPENBUS(6 downto 0) when IOPORT_CE_N = '0' else 
			BSRAM_Q                 when SRAM_CE_N = '0' else 
			DPAK_DO                 when DPAK_CE_N = '0' else 
			ROM_Q(7 downto 0)       when PSRAM_CE_N = '0' or BIOS_CE_N = '0' else 
			OPENBUS;

	IRQ_N <= '1';
	
end rtl;
