library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;
entity DLHReference is port (
 CA : in std_logic_vector(23 downto 0);
 MAP_CTRL : in std_logic_vector(7 downto 0);
 CC_DR : in std_logic_vector(7 downto 0);
 ROMSEL_N : in std_logic;
 RAMSEL_N : in std_logic;
 BSRAM_MASK : in std_logic_vector(23 downto 0);
 ROM_MASK : in std_logic_vector(23 downto 0);
 ROM_Q : in std_logic_vector(15 downto 0);
 DSP_DO : in std_logic_vector(7 downto 0);
 SRTC_DO : in std_logic_vector(7 downto 0);
 CC_SR : in std_logic_vector(7 downto 0);
 BSRAM_Q : in std_logic_vector(7 downto 0);
 OPENBUS : in std_logic_vector(7 downto 0);
 CART_ADDR : out std_logic_vector(23 downto 0);
 BRAM_ADDR : out std_logic_vector(19 downto 0);
 ROM_SEL : out std_logic;
 BSRAM_SEL : out std_logic;
 NO_BSRAM_SEL : out std_logic;
 DP_SEL : out std_logic;
 DSP_SEL : out std_logic;
 DSP_A0 : out std_logic;
 OBC1_SEL : out std_logic;
 SRTC_SEL : out std_logic;
 CC_SEL : out std_logic;
 DO : out std_logic_vector(7 downto 0)
); end DLHReference;
architecture exact of DLHReference is

begin
-- Source: rtl/upstream/chip/DSP/DSP_LHRomMap.vhd
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
-- Source: rtl/upstream/chip/DSP/DSP_LHRomMap.vhd
ROM_SEL <= not ROMSEL_N and not DSP_SEL and not DP_SEL and not SRTC_SEL and not BSRAM_SEL and not OBC1_SEL and not CC_SEL and not NO_BSRAM_SEL;
-- Source: rtl/upstream/chip/DSP/DSP_LHRomMap.vhd
DO <= ROM_Q(7 downto 0) when ROM_SEL = '1' else
			DSP_DO when DSP_SEL = '1' or DP_SEL = '1' else
			SRTC_DO when SRTC_SEL = '1' else
			CC_SR when CC_SEL = '1' else
			BSRAM_Q when BSRAM_SEL = '1' or OBC1_SEL = '1' else
			OPENBUS;

end exact;
