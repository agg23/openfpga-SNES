library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;
library work;

entity MCC is
	port(
		CLK			: in std_logic;
		RST_N			: in std_logic;
		ENABLE		: in std_logic;
		
		CA   			: in std_logic_vector(23 downto 12);
		DI7			: in std_logic;
		DO7			: out std_logic;
		RD_N			: in std_logic;
		WR_N			: in std_logic;
		SYSCLKF_CE	: in std_logic;
		
		BIOS_CE_N	: out std_logic;
		SRAM_CE_N	: out std_logic;
		
		ADDR   		: out std_logic_vector(19 downto 15);
		PSRAM_CE_N	: out std_logic;
		EXTMEM_CE_N	: out std_logic;
		DPAK_CE_N	: out std_logic;
		DPAK_WR_N	: out std_logic;
		
		IOPORT_CE_N	: out std_logic
	);
end MCC;

architecture rtl of MCC is
	
	signal IO_REG		: std_logic_vector(13 downto 2);
	signal REG 			: std_logic_vector(13 downto 2);
	signal ENIRQ		: std_logic;
	signal MAP_MODE	: std_logic;
	signal PSRAM_ON	: std_logic_vector(1 downto 0);
	signal PSRAM_MAP	: std_logic_vector(1 downto 0);
	signal BIOS_ON		: std_logic_vector(1 downto 0);
	signal EXT_ON		: std_logic_vector(1 downto 0);
	signal EXT_MAP		: std_logic;
	signal EN_DPAK_WR	: std_logic;
	signal EN_EXT_WR	: std_logic;
	signal IO_SEL		: std_logic;
	signal ROM_AREA	: std_logic;
	
begin

	IO_SEL <= '1' when CA(23 downto 20) = x"0" and CA(15 downto 12) = x"5" else '0'; -- 00:5XXX-0F:5XXX
	IOPORT_CE_N <= not IO_SEL;
	
	process( RST_N, CLK)
	begin
		if RST_N = '0' then
			IO_REG <= "001011111011";
			ENIRQ <= '0';
			MAP_MODE <= '1';
			PSRAM_ON <= "01";
			PSRAM_MAP <= "11";
			BIOS_ON <= "11";
			EXT_ON <= "01";
			EXT_MAP <= '1';
			EN_DPAK_WR <= '0';
			EN_EXT_WR <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				if IO_SEL = '1' and WR_N = '0' and SYSCLKF_CE = '1' then
					case CA(19 downto 16) is
						when x"0" =>
						when x"1" => ENIRQ <= DI7;
						when x"2" => IO_REG(2) <= DI7;
						when x"3" => IO_REG(3) <= DI7;
						when x"4" => IO_REG(4) <= DI7;
						when x"5" => IO_REG(5) <= DI7;
						when x"6" => IO_REG(6) <= DI7;
						when x"7" => IO_REG(7) <= DI7;
						when x"8" => IO_REG(8) <= DI7;
						when x"9" => IO_REG(9) <= DI7;
						when x"A" => IO_REG(10) <= DI7;
						when x"B" => IO_REG(11) <= DI7;
						when x"C" => IO_REG(12) <= DI7;
						when x"D" => IO_REG(13) <= DI7;
						when x"E" => 
							MAP_MODE <= IO_REG(2);
							PSRAM_ON <= IO_REG(4 downto 3);
							PSRAM_MAP <= IO_REG(6 downto 5);
							BIOS_ON <= IO_REG(8 downto 7);
							EXT_ON <= IO_REG(10 downto 9);
							EXT_MAP <= IO_REG(11);
							EN_DPAK_WR <= IO_REG(12);
							EN_EXT_WR <= IO_REG(13);
						when others => null;
					end case;
				end if;
			end if;
		end if;
	end process;
	
	process( RST_N, CLK)
	begin
		if RST_N = '0' then
			DO7 <= '0';
		elsif rising_edge(CLK) then
			if IO_SEL = '1' then 
				case CA(19 downto 16) is
					when x"0" => DO7 <= '0';
					when x"1" => DO7 <= ENIRQ;
					when x"2" => DO7 <= MAP_MODE;
					when x"3" => DO7 <= PSRAM_ON(0);
					when x"4" => DO7 <= PSRAM_ON(1);
					when x"5" => DO7 <= PSRAM_MAP(1);
					when x"6" => DO7 <= PSRAM_MAP(1);
					when x"7" => DO7 <= BIOS_ON(0);
					when x"8" => DO7 <= BIOS_ON(1);
					when x"9" => DO7 <= EXT_ON(0);
					when x"A" => DO7 <= EXT_ON(1);
					when x"B" => DO7 <= EXT_MAP;
					when x"C" => DO7 <= EN_DPAK_WR;
					when x"D" => DO7 <= EN_EXT_WR;
					when others => DO7 <= '0';
				end case;
			else
				DO7 <= '0';
			end if;
		end if;
	end process;
	
	ROM_AREA <= '0' when CA(23 downto 17) = "0111111" or (CA(22) = '0' and CA(15) = '0') else '1';
	
	process( CA, ROM_AREA, MAP_MODE, PSRAM_ON, PSRAM_MAP, BIOS_ON, EXT_ON, EXT_MAP )
	begin
		BIOS_CE_N <= '1';
		PSRAM_CE_N <= '1';
		EXTMEM_CE_N <= '1';
		DPAK_CE_N <= '1';
		
		if MAP_MODE = '0' then
			if ((not CA(23) and BIOS_ON(0)) = '1' or (CA(23) and BIOS_ON(1)) = '1') and CA(22) = '0' then
				BIOS_CE_N <= not ROM_AREA;
			elsif ((not CA(23) and PSRAM_ON(0)) = '1' or (CA(23) and PSRAM_ON(1)) = '1') and CA(22 downto 21) = PSRAM_MAP then
				PSRAM_CE_N <= not ROM_AREA;
			elsif ((not CA(23) and EXT_ON(0)) = '1' or (CA(23) and EXT_ON(1)) = '1') and CA(22) = EXT_MAP and CA(21) = '0' then
				EXTMEM_CE_N <= not ROM_AREA;
			else
				DPAK_CE_N <= not ROM_AREA;
			end if;
			
			if ((not CA(23) and PSRAM_ON(0)) = '1' or (CA(23) and PSRAM_ON(1)) = '1') and CA(22 downto 20) = "111" and CA(15) = '0' then	--70-7D:0000-7FFF,F0-FF:0000-7FFF
				PSRAM_CE_N <= not ROM_AREA;
			end if;
		else
			if ((not CA(23) and BIOS_ON(0)) = '1' or (CA(23) and BIOS_ON(1)) = '1') and CA(22) = '0' then
				BIOS_CE_N <= not ROM_AREA;
			elsif ((not CA(23) and PSRAM_ON(0)) = '1' or (CA(23) and PSRAM_ON(1)) = '1') and CA(21 downto 20) = PSRAM_MAP and CA(19) = '0'  then
				PSRAM_CE_N <= not ROM_AREA;
			elsif ((not CA(23) and EXT_ON(0)) = '1' or (CA(23) and EXT_ON(1)) = '1') and CA(21) = EXT_MAP and CA(20) = '0' then
				EXTMEM_CE_N <= not ROM_AREA;
			else
				DPAK_CE_N <= not ROM_AREA;
			end if;
			
			if CA(22 downto 21) = "01" and CA(15 downto 12) = x"6" then		--20-3F:6000-6FFF,A0-BF:6000-6FFF
				PSRAM_CE_N <= '0';
			end if;
		end if;
		
		if ((not CA(23) and PSRAM_ON(0)) = '1' or (CA(23) and PSRAM_ON(1)) = '1') and CA(23 downto 19) = "00010" and CA(15 downto 12) = x"5" then		--10-17:5000-5FFF
			SRAM_CE_N <= '0';
		else
			SRAM_CE_N <= '1';
		end if;
	end process;
	
	DPAK_WR_N <= WR_N or not EN_DPAK_WR;
	
	process( CA, MAP_MODE )
	begin
		if MAP_MODE = '0' then
			ADDR <= CA(20 downto 16);--LoROM
		else
			ADDR <= CA(19 downto 15);--HiROM
		end if;
	end process;
	
end rtl;