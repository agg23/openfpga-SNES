library STD;
use STD.TEXTIO.ALL;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;

entity DSP_LHRomMap is
	generic (
		USE_DSPn	: in std_logic := '1'
	);
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

		EXT_RTC		: in std_logic_vector(64 downto 0);
		
		CC_DIP		: in std_logic_vector(7 downto 0);

		SS_BUSY			: in std_logic;
		SS_RAM_A		: in std_logic_vector(11 downto 0);
		SS_DSPN_RAM_SEL	: in std_logic;
		SS_DSPN_REGS_SEL: in std_logic;
		SS_DI			: in std_logic_vector(7 downto 0);
		SS_DO			: out std_logic_vector(7 downto 0)
	);
end DSP_LHRomMap;

architecture rtl of DSP_LHRomMap is

	signal CART_ADDR 		: std_logic_vector(23 downto 0);
	signal ROM_SEL 		: std_logic;
	signal BRAM_ADDR 		: std_logic_vector(19 downto 0);
	signal BSRAM_SEL 		: std_logic;
	signal NO_BSRAM_SEL	: std_logic;
	signal DP_SEL    		: std_logic;

	signal DSP_SEL	  		: std_logic;
	signal DSP_DO    		: std_logic_vector(7 downto 0);
	signal DSP_A0	  		: std_logic;
	signal DSP_CS_N  		: std_logic;
	signal DSP_CE	  		: std_logic;

	signal OBC1_SEL		: std_logic;
	signal OBC1_SRAM_A 	: std_logic_vector(12 downto 0);
	signal OBC1_SRAM_DO 	: std_logic_vector(7 downto 0);

	signal SRTC_DO 		: std_logic_vector(7 downto 0);
	signal SRTC_SEL		: std_logic;
	
	signal CC_SEL			: std_logic;
	signal CC_DR   		: std_logic_vector(7 downto 0);
	signal CC_SR   		: std_logic_vector(7 downto 0);
	signal CC_TM_ON		: std_logic;
	signal CC_TM_CNT  	: unsigned(4 downto 0);
	signal CC_TM_DIV 		: integer;

	signal OPENBUS   		: std_logic_vector(7 downto 0);

	signal MAP_DSP_VER	: std_logic_vector(2 downto 0);
	signal MAP_DSP_SEL	: std_logic;
	signal MAP_OBC1_SEL 	: std_logic;
	signal MAP_CC_SEL 	: std_logic;
	signal DSP_CLK	  		: integer;
	signal ROM_RD	  		: std_logic;
	

begin

	MAP_DSP_VER <= MAP_CTRL(3) & MAP_CTRL(5 downto 4) when MAP_CTRL(6) = '0' else "000";
	MAP_DSP_SEL <= not MAP_CTRL(6) and (MAP_CTRL(7) or not (MAP_CTRL(5) or MAP_CTRL(4)));	--8..B
	MAP_OBC1_SEL <= MAP_CTRL(7) and MAP_CTRL(6) and not MAP_CTRL(5) and not MAP_CTRL(4);	--C
	MAP_CC_SEL <= MAP_CTRL(7) and MAP_CTRL(6) and MAP_CTRL(5);	--E..F
	MAP_ACTIVE <= MAP_DSP_SEL or MAP_OBC1_SEL or MAP_CC_SEL;

	CEGen : entity work.CEGen
	port map(
		CLK     => MCLK,
		RST_N   => RST_N,
		IN_CLK  => 2147727,
		OUT_CLK => DSP_CLK,
		CE      => DSP_CE
	);

	DSP_CLK <= 760000 when MAP_CTRL(3) = '0' else 1000000;

	process( CA, MAP_CTRL, CC_DR, ROMSEL_N, RAMSEL_N, BSRAM_MASK, ROM_MASK )
	begin
		DP_SEL <= '0';
		DSP_SEL <= '0';
		OBC1_SEL <= '0';
		SRTC_SEL <= '0';
		CC_SEL <= '0';
		BSRAM_SEL <= '0';
		NO_BSRAM_SEL <= '0';
		if MAP_CTRL(7 downto 4) = x"E" then	--Campus Challenge '92
			if CA(23) = '1' and CA(15) = '1' then
				CART_ADDR <= "000000" & CA(18 downto 16) & CA(14 downto 0);
			elsif CC_DR = x"09" then
				CART_ADDR <= ("00000" & CA(19 downto 16) & CA(14 downto 0)) + x"040000";
			elsif CC_DR = x"05" then
				CART_ADDR <= ("00000" & CA(19 downto 16) & CA(14 downto 0)) + x"040000" + x"080000";
			elsif CC_DR = x"03" then
				CART_ADDR <= ("00000" & CA(19 downto 16) & CA(14 downto 0)) + x"040000" + x"080000" + x"080000";
			else
				CART_ADDR <= "000000" & CA(18 downto 16) & CA(14 downto 0);
			end if;
			
			BRAM_ADDR <= "0000000" & CA(12 downto 0);
			if CA(22 downto 20) = "111" and CA(15) = '0' and ROMSEL_N = '0' then									--70-7D/F0-FF:0000-7FFF
				BSRAM_SEL <= BSRAM_MASK(10);											
			end if;
			
			if CA(22 downto 21) = "01" and CA(15) = '1' then															--20-3F/A0-BF:8000-FFFF
				DSP_SEL <= '1';
			end if;
			DSP_A0 <= CA(14);
			
			if CA(23 downto 20) = x"C" or CA(23 downto 20) = x"E" then	--C0-CF:0000-FFFF/E0-EF:0000-FFFF
				CC_SEL <= '1';
			end if;
		elsif MAP_CTRL(7 downto 4) = x"F" then	--PowerFest '94
			if CA(21) = '1' and CA(15) = '1' then
				CART_ADDR <= "000000" & CA(18 downto 16) & CA(14 downto 0);
			elsif CC_DR = x"09" then
				CART_ADDR <= ("00000" & CA(19 downto 16) & CA(14 downto 0)) + x"040000";
			elsif CC_DR = x"0C" then
				CART_ADDR <= ("00000" & CA(18 downto 0)) + x"040000" + x"080000";
			elsif CC_DR = x"0A" then
				CART_ADDR <= ("0000" & CA(20 downto 16) & CA(14 downto 0)) + x"040000" + x"080000" + x"080000";
			else
				CART_ADDR <= "000000" & CA(18 downto 16) & CA(14 downto 0);
			end if;
			
			BRAM_ADDR <= "0000000" & CA(12 downto 0);
			if CA(22 downto 20) = "011" and CA(15 downto 13) = "011" and BSRAM_MASK(10) = '1' then	--30-3F/B0-BF:6000-7FFF
				BSRAM_SEL <= '1';
			end if;
			
			if CA(22 downto 20) = "000" and CA(15 downto 13) = "011" then									--00-0F/80-8F:6000-7FFF
				DSP_SEL <= '1';
			end if;
			DSP_A0 <= CA(12);
			
			if (CA(23 downto 20) = x"1" or CA(23 downto 20) = x"2") and CA(15 downto 13) = "011" then	--10-2F/90-AF:6000-7FFF
				CC_SEL <= '1';
			end if;
		elsif ROM_MASK(23) = '0' then
			case MAP_CTRL(1 downto 0) is
				when "00" =>							-- LoROM/ExLoROM
					CART_ADDR <= '0' & not CA(23) & CA(22 downto 16) & CA(14 downto 0);
					BRAM_ADDR <= CA(20 downto 16) & CA(14 downto 0);
					if MAP_CTRL(3) = '0' then
						if CA(22 downto 20) = "111" and ROMSEL_N = '0' then
							if ROM_MASK(20) = '1' or BSRAM_MASK(15) = '1' or MAP_CTRL(7) = '1' then
								BSRAM_SEL <= not CA(15) and BSRAM_MASK(10);
								NO_BSRAM_SEL <= not CA(15) and not MAP_CTRL(7) and not BSRAM_MASK(10);
							else
								BRAM_ADDR <= CA(19 downto 0);
								BSRAM_SEL <= BSRAM_MASK(10);
								NO_BSRAM_SEL <= not MAP_CTRL(7) and not BSRAM_MASK(10);
							end if;
						end if;
						if (CA(22 downto 21) = "01" and CA(15) = '1' and ROM_MASK(20) = '0') or		--20-3F/A0-BF:8000-FFFF
							(CA(22 downto 20) = "110" and CA(15) = '0' and ROM_MASK(20) = '1') then	--60-6F/E0-EF:0000-7FFF
							DSP_SEL <= MAP_CTRL(7) and not MAP_CTRL(6);
						end if;
						DSP_A0 <= CA(14);
						if CA(22) = '0' and CA(15 downto 13) = "011" then									--00-3F/80-BF:6000-7FFF
							OBC1_SEL <= MAP_CTRL(7) and MAP_CTRL(6);
						end if;
					else
						if CA(22 downto 19) = "1101" and ROMSEL_N = '0' then 								--68-6F/E8-EF:0000-0FFF
							DP_SEL <= not CA(11);
							BSRAM_SEL <= CA(11);
						end if;

						if CA(22 downto 19) = "1100" then														--60-67/E0-E7:0000-0001
							DSP_SEL <= MAP_CTRL(7) and not MAP_CTRL(6);
						end if;
						DSP_A0 <= CA(0);
					end if;
				when "01" =>							-- HiROM
					CART_ADDR <= "00" & CA(21 downto 0);
					BRAM_ADDR <= "00" & CA(20 downto 16) & CA(12 downto 0);
					if CA(22 downto 21) = "01" and CA(15 downto 13) = "011" and BSRAM_MASK(10) = '1' then
						BSRAM_SEL <= '1';
					end if;
					if CA(22 downto 21) = "00" and CA(15 downto 13) = "011" then						--00-1F/80-9f:6000-7FFF
						DSP_SEL <= MAP_CTRL(7) and not MAP_CTRL(6);
					end if;
					DSP_A0 <= CA(12);
				when "10" =>					-- ExHiROM
					CART_ADDR <= "0" & (not CA(23)) & CA(21 downto 0);
					BRAM_ADDR <= "0" & CA(21 downto 16) & CA(12 downto 0);
					if CA(22 downto 21) = "01" and CA(15 downto 13) = "011" and BSRAM_MASK(10) = '1' then
						BSRAM_SEL <= '1';
					end if;
					DSP_SEL <= '0';
					DSP_A0 <= '1';
					if CA(22) = '0' and CA(15 downto 1) = x"280"&"000" and MAP_CTRL(3) = '1' then
						SRTC_SEL <= '1';
					end if;
				when others =>					-- SpecialLoROM
					CART_ADDR <= "00" & (CA(23) and not CA(21)) & CA(21 downto 16) & CA(14 downto 0);--00-1F:8000-FFFF; 20-3F/A0-BF:8000-FFFF; 80-9F:8000-FFFF
					BRAM_ADDR <= CA(20 downto 16) & CA(14 downto 0);
					if CA(22 downto 20) = "111" and CA(15) = '0' and ROMSEL_N = '0' and BSRAM_MASK(10) = '1' then
						BSRAM_SEL <= '1';
					end if;
					DSP_SEL <= '0';
					DSP_A0 <= '1';
			end case;
		else												--96Mbit 
			if CA(15) = '0' then
				CART_ADDR <= "10" & CA(23) & CA(21 downto 16) & CA(14 downto 0);
			else
				CART_ADDR <= "0" & CA(23 downto 16) & CA(14 downto 0);
			end if;
			BRAM_ADDR <= "00" & CA(20 downto 16) & CA(12 downto 0);
			if CA(22 downto 21) = "01" and CA(15 downto 13) = "011" and BSRAM_MASK(10) = '1' then
				BSRAM_SEL <= '1';
			end if;
			DSP_SEL <= '0';
			DSP_A0 <= '1';
		end if;
	end process;
	
	ROM_SEL <= not ROMSEL_N and not DSP_SEL and not DP_SEL and not SRTC_SEL and not BSRAM_SEL and not OBC1_SEL and not CC_SEL and not NO_BSRAM_SEL;
	DSP_CS_N <= not DSP_SEL;

	DSPn_BLOCK: if USE_DSPn = '1' generate
	DSPn : entity work.DSPn
	port map(
		CLK			=> MCLK,
		CE				=> DSP_CE,
		RST_N			=> RST_N and (MAP_DSP_SEL or MAP_CC_SEL),
		ENABLE		=> ENABLE,
		A0				=> DSP_A0,
		DI				=> DI,
		DO				=> DSP_DO,
		CS_N			=> DSP_CS_N,
		RD_N			=> CPURD_N,
		WR_N			=> CPUWR_N,

		DP_ADDR     => CA(11 downto 0),
		DP_SEL      => DP_SEL,

		VER			=> MAP_DSP_VER,
		REV			=> not MAP_CTRL(2),

		-- save states
		SS_BUSY			=> SS_BUSY,
		CA				=> CA,
		SS_RAM_A		=> SS_RAM_A,
		SS_RAM_WR		=> not PAWR_N and SS_DSPN_RAM_SEL,
		SS_RAM_SEL		=> SS_DSPN_RAM_SEL,
		SS_REGS_SEL		=> SS_DSPN_REGS_SEL,
		SS_DI			=> SS_DI,
		SS_DO			=> SS_DO
	);
	end generate;

	OBC1 : entity work.OBC1
	port map(
		CLK			=> MCLK,
		RST_N			=> RST_N and MAP_OBC1_SEL,
		ENABLE		=> ENABLE,

		CA				=> CA,
		DI				=> DI,
		CPURD_N		=> CPURD_N,
		CPUWR_N		=> CPUWR_N,

		SYSCLKF_CE	=> SYSCLKF_CE,

		CS				=> OBC1_SEL,

		SRAM_A		=> OBC1_SRAM_A,
		SRAM_DI  	=> BSRAM_Q,
		SRAM_DO		=> OBC1_SRAM_DO
	);

	SRTC : entity work.SRTC
	port map(
		CLK			=> MCLK,

		A0				=> CA(0),
		DI				=> DI,
		DO				=> SRTC_DO,
		CS				=> SRTC_SEL,
		CPURD_N		=> CPURD_N,
		CPUWR_N		=> CPUWR_N,

		SYSCLKF_CE	=> SYSCLKF_CE,

		EXT_RTC		=> EXT_RTC
	);
	
	--Competition Cart
	process (MCLK, RST_N)
	begin
		if RST_N = '0' then
			CC_DR <= (others => '0');
			CC_SR <= (others => '0');
			CC_TM_ON <= '0';
			CC_TM_CNT <= (others => '0');
		elsif rising_edge(MCLK) then
			CC_TM_DIV <= CC_TM_DIV + 1;
			if CC_TM_DIV = 21477270*60-1 then
				CC_TM_DIV <= 0;
				if CC_TM_CNT = 0 then
					CC_SR(1) <= CC_TM_ON;
					CC_TM_ON <= '0';
				else
					CC_TM_CNT <= CC_TM_CNT - 1;
				end if;
			end if;
			
			if CC_SEL = '1' and CA(21) = '1' and CPUWR_N = '0' and SYSCLKF_CE = '1' then
				CC_DR <= DI;
				if DI = x"09" then
					CC_TM_ON <= '1';
					CC_TM_CNT <= "0"&unsigned(CC_DIP(3 downto 0)) + 3;
					CC_TM_DIV <= 0;
				end if;
			end if;
		end if;
	end process;

	process (MCLK)
	begin
		if rising_edge(MCLK) then
			if SYSCLKR_CE = '1' then
				ROM_ADDR <= CART_ADDR and ROM_MASK;
			end if;
			
			if SYSCLKR_CE = '1' or SYSCLKF_CE = '1' then
				ROM_RD <= '1';
			else
				ROM_RD <= '0';
			end if;
		end if;
	end process;
	
	ROM_CE_N <= ROMSEL_N;
	ROM_OE_N <= not ROM_RD;
	ROM_WORD	<= '0';

	BSRAM_ADDR <= "0000000" & OBC1_SRAM_A when OBC1_SEL = '1' else BRAM_ADDR and BSRAM_MASK(19 downto 0);
	BSRAM_CE_N <= not (BSRAM_SEL or OBC1_SEL);
	BSRAM_OE_N <= CPURD_N;
	BSRAM_WE_N <= CPUWR_N;
	BSRAM_D    <= OBC1_SRAM_DO when OBC1_SEL = '1' else DI;

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

	DO <= ROM_Q(7 downto 0) when ROM_SEL = '1' else
			DSP_DO when DSP_SEL = '1' or DP_SEL = '1' else
			SRTC_DO when SRTC_SEL = '1' else
			CC_SR when CC_SEL = '1' else
			BSRAM_Q when BSRAM_SEL = '1' or OBC1_SEL = '1' else
			OPENBUS;

	IRQ_N <= '1';

end rtl;
