library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;
library work;

entity CX4 is
	port(
		CLK			: in std_logic;
		CE				: in std_logic;
		RST_N			: in std_logic;
		ENABLE		: in std_logic;
		ADDR   		: in std_logic_vector(23 downto 0);
		DI				: in std_logic_vector(7 downto 0);
		DO				: out std_logic_vector(7 downto 0);
		RD_N			: in std_logic;
		WR_N			: in std_logic;
		
		SYSCLKF_CE	: in std_logic;
		SYSCLKR_CE	: in std_logic;
		
		IRQ_N			: out std_logic;
		
		BUS_A   		: out std_logic_vector(23 downto 0);
		BUS_DI		: in std_logic_vector(7 downto 0);
		BUS_DO		: out std_logic_vector(7 downto 0);
		BUS_OE_N		: out std_logic;
		BUS_WE_N		: out std_logic;
		ROM_CE1_N	: out std_logic;
		ROM_CE2_N	: out std_logic;
		SRAM_CE_N	: out std_logic;
		
		BUS_RD_N		: out std_logic;
		
		MAPPER		: in std_logic
	);
end CX4;

architecture rtl of CX4 is

	constant FLAG_Z : integer range 0 to 3 := 0;
	constant FLAG_N : integer range 0 to 3 := 1;
	constant FLAG_T : integer range 0 to 3 := 2;
	constant FLAG_V : integer range 0 to 3 := 3;
	
	type Instr_t is (
		I_NOP,
		I_BR,
		I_SKIP,
		I_BSUB,
		I_MOV,
		I_RTS,
		I_INCEXT,
		I_CMP,
		I_EXTS,
		I_RDROM,
		I_RDRAM,
		I_LDP,
		I_ADDSUB,
		I_MUL,
		I_LOG,
		I_SHIFT,
		I_WRRAM,
		I_ST,
		I_SWAP,
		I_CLR,
		I_FINEXT,
		I_HLT
	);

	--CPU registers
	signal A : std_logic_vector(23 downto 0);
	signal FLAGS : std_logic_vector(3 downto 0);
	signal PC : std_logic_vector(7 downto 0);
	signal BANK : std_logic;
	type StackRam_t is array (0 to 7) of std_logic_vector(8 downto 0);
	signal STACK_RAM	: StackRam_t;
	signal SP : unsigned(2 downto 0);
	type GPR_t is array (0 to 15) of std_logic_vector(23 downto 0);
	signal GPR	: GPR_t;
	signal MACL, MACH : std_logic_vector(23 downto 0);
	signal MAR : std_logic_vector(23 downto 0);
	signal MBR : std_logic_vector(7 downto 0);
	signal ROMB, RAMB : std_logic_vector(23 downto 0);
	signal DPR : std_logic_vector(11 downto 0);
	signal P : std_logic_vector(14 downto 0);
	
	--MMIO registers
	signal DMA_SRC : std_logic_vector(23 downto 0);
	signal DMA_DST : std_logic_vector(23 downto 0);
	signal DMA_LEN : std_logic_vector(15 downto 0);
	signal ROM_BASE : std_logic_vector(23 downto 0);
	signal ROM_PAGE : std_logic_vector(14 downto 0);
	type Vectors_t is array (0 to 31) of std_logic_vector(7 downto 0);
	signal VEC_MEM : Vectors_t;
	signal PAGE_SEL : std_logic;
	signal PAGE_LOCK : std_logic_vector(1 downto 0);
	signal WS1, WS2 : std_logic_vector(2 downto 0);
	signal ROM_MODE : std_logic;
	signal SUSPEND : std_logic;
	signal IRQ_EN : std_logic;
	
	signal IR : std_logic_vector(15 downto 0);
	signal INST : Instr_t;
	signal RDB : std_logic_vector(23 downto 0);
	signal ALUR : std_logic_vector(23 downto 0);
	signal ALUC : std_logic;
	signal SH_A : std_logic_vector(23 downto 0);
	signal MULA, MULB : signed(23 downto 0);
	signal COND : std_logic;
	
	signal EN : std_logic;
	signal CLK_CNT : unsigned(1 downto 0);
	signal CPU_RUN, CACHE_RUN, DMA_RUN : std_logic;
	signal CPU_EN : std_logic;
	signal RD_Nr, WR_Nr : std_logic_vector(3 downto 0);
	signal MMIO_WR, RAMIO_WR : std_logic;
	signal MMIO_SEL, RAMIO_SEL : std_logic;
	signal ROM_SEL, SRAM_SEL, RAM_SEL : std_logic;
	signal BUSY : std_logic;
	signal IRQ, IRQ_FLAG : std_logic;
	signal CACHE_WAIT_CNT, DMA_WAIT_CNT : unsigned(2 downto 0);
	signal CACHE_ADDR : std_logic_vector(8 downto 0);
	signal CACHE_BANK : std_logic;
	type CachePage_t is array (0 to 1) of std_logic_vector(15 downto 0);
	signal CACHE_PAGE : CachePage_t;
	signal DMA_DST_ADDR : std_logic_vector(23 downto 0);
	signal DMA_SRC_ADDR : std_logic_vector(23 downto 0);
	signal DMA_DAT : std_logic_vector(7 downto 0);
	signal DMA_STATE : std_logic;
	signal DMA_CNT : unsigned(15 downto 0);
	signal ROM_ACCESS, SRAM_ACCESS, SRAM_WR : std_logic;
	signal BUS_ACCESS_CNT : unsigned(2 downto 0);
	signal EXT_BUS_ADDR : std_logic_vector(23 downto 0);
	signal INT_ADDR : std_logic_vector(23 downto 0);
	signal EXTRA_CYCLES : integer range 0 to 2;
	
	--Internal RAM/ROM
	signal CACHE_ADDR_WR : std_logic_vector(9 downto 0);
	signal CACHE_ADDR_RD : std_logic_vector(8 downto 0);
	signal CACHE_DI : std_logic_vector(7 downto 0);
	signal CACHE_Q_L, CACHE_Q_H : std_logic_vector(7 downto 0);
	signal CACHE_WE : std_logic;
	signal DATA_RAM_ADDR_A, DATA_RAM_ADDR_B : std_logic_vector(11 downto 0);
	signal DATA_RAM_DI_A, DATA_RAM_DI_B : std_logic_vector(7 downto 0);
	signal DATA_RAM_Q_A, DATA_RAM_Q_B : std_logic_vector(7 downto 0);
	signal DATA_RAM_WE_A, DATA_RAM_WE_B : std_logic;
	signal DATA_ROM_ADDR : std_logic_vector(9 downto 0);
	signal DATA_ROM_Q : std_logic_vector(23 downto 0);
	
	signal BUS_RD_CNT : unsigned(1 downto 0);
	
	impure function BitToInt (v : in std_logic) return integer is
        variable ret : integer range 0 to 1;
    begin   
        if v = '0' then 
				ret := 0;
			else
				ret := 1;
			end if;
        return ret;
    end function; 
	
begin

	EN <= ENABLE and CE;
	CPU_EN <= EN and CPU_RUN and (not CACHE_RUN) and (not DMA_RUN) and (not SUSPEND);
	
	--I/O Ports
	process(ADDR, MAPPER)
	begin
		RAMIO_SEL <= '0';
		MMIO_SEL <= '0';
		if (MAPPER = '0' and ADDR(22) = '0' and ADDR(15 downto 13) = "011") or												--LoROM: 00-3F:6000-7FFF, 80-BF:6000-7FFF 
			(MAPPER = '1' and ADDR(22) = '0' and ADDR(21 downto 20) <= "10" and ADDR(15 downto 13) = "011") then	--HiROM: 00-2F:6000-7FFF, 80-AF:6000-7FFF
			if ADDR(12) = '0' then
				RAMIO_SEL <= '1';
			else
				MMIO_SEL <= '1';
			end if;
		end if;
	end process; 
	
	MMIO_WR <= not WR_N and MMIO_SEL and SYSCLKF_CE;
	RAMIO_WR <= not WR_N and RAMIO_SEL and SYSCLKF_CE;
	
	process(CLK, RST_N, WR_Nr, RAMIO_SEL, MMIO_SEL, SYSCLKF_CE)
	begin
		if RST_N = '0' then
			DMA_SRC <= (others => '0');
			DMA_LEN <= (others => '0');
			DMA_DST <= (others => '0');
			PAGE_SEL <= '0';
			ROM_BASE <= (others => '0');
			ROM_PAGE <= (others => '0');
			PAGE_LOCK <= (others => '0');
			VEC_MEM <= (others => (others => '0'));
			WS1 <= "011";
			WS2 <= "011";
			IRQ_EN <= '0';
			ROM_MODE <= '0';
			SUSPEND <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				if MMIO_WR = '1' and ADDR(11 downto 8) = x"F" then
					if ADDR(7 downto 4) = x"4" then
						case ADDR(3 downto 0) is
							when x"0" =>						-- 7F40
								DMA_SRC(7 downto 0) <= DI;
							when x"1" =>						-- 7F41
								DMA_SRC(15 downto 8) <= DI;
							when x"2" =>						-- 7F42
								DMA_SRC(23 downto 16) <= DI;
							when x"3" =>						-- 7F43
								DMA_LEN(7 downto 0) <= DI;
							when x"4" =>						-- 7F44
								DMA_LEN(15 downto 8) <= DI;
							when x"5" =>						-- 7F45
								DMA_DST(7 downto 0) <= DI;
							when x"6" =>						-- 7F46
								DMA_DST(15 downto 8) <= DI;
							when x"7" =>						-- 7F47
								DMA_DST(23 downto 16) <= DI;
							when x"8" =>						-- 7F48
								PAGE_SEL <= DI(0);
							when x"9" =>						-- 7F49
								ROM_BASE(7 downto 0) <= DI;
							when x"A" =>						-- 7F4A
								ROM_BASE(15 downto 8) <= DI;
							when x"B" =>						-- 7F4B
								ROM_BASE(23 downto 16) <= DI;
							when x"C" =>						-- 7F4C
								PAGE_LOCK <= DI(1 downto 0);
							when x"D" =>						-- 7F4D
								ROM_PAGE(7 downto 0) <= DI;
							when x"E" =>						-- 7F4E
								ROM_PAGE(14 downto 8) <= DI(6 downto 0);
							when x"F" =>						-- 7F4F
							
							when others => null;
						end case;
					elsif ADDR(7 downto 4) = x"5" then
						case ADDR(3 downto 0) is
							when x"0" =>						-- 7F50
								WS1 <= DI(6 downto 4);
								WS2 <= DI(2 downto 0);
							when x"1" =>						-- 7F51
								IRQ_EN <= not DI(0);
							when x"2" =>						-- 7F52
								ROM_MODE <= DI(0);
							when x"5" =>						-- 7F55
								SUSPEND <= '1';
							when x"D" =>						-- 7F5D
								SUSPEND <= '0';
							when others => null;
						end case;
					elsif ADDR(7 downto 5) = "011" then	-- 7F60-7F7F
						VEC_MEM(to_integer(unsigned(ADDR(4 downto 0)))) <= DI;
					end if;
				end if;
			end if;
		end if;
	end process; 
	
	BUSY <= CPU_RUN or CACHE_RUN or DMA_RUN;

	process( MMIO_SEL, RAMIO_SEL, ADDR, DMA_SRC, DMA_LEN, DMA_DST, PAGE_SEL, PAGE_LOCK, ROM_BASE, ROM_PAGE, WS1, WS2, IRQ_EN, ROM_MODE, 
			   ROM_ACCESS, SRAM_ACCESS, VEC_MEM, GPR, CPU_RUN, DATA_RAM_Q_B, BUS_DI, IRQ_FLAG, SUSPEND, BUSY )
	begin
		DO <= x"00";
		if MMIO_SEL = '1' then
			if ADDR(11 downto 8) = x"F" then
				if ADDR(7 downto 4) = x"4" then
					case ADDR(3 downto 0) is
						when x"0" =>
							DO <= DMA_SRC(7 downto 0);
						when x"1" =>
							DO <= DMA_SRC(15 downto 8);
						when x"2" =>
							DO <= DMA_SRC(23 downto 16);
						when x"3" =>
							DO <= DMA_LEN(7 downto 0);
						when x"4" =>
							DO <= DMA_LEN(15 downto 8);
						when x"5" =>
							DO <= DMA_DST(7 downto 0);
						when x"6" =>
							DO <= DMA_DST(15 downto 8);
						when x"7" =>
							DO <= DMA_DST(23 downto 16);
						when x"8" =>
							DO <= "0000000" & PAGE_SEL;
						when x"9" =>
							DO <= ROM_BASE(7 downto 0);
						when x"A" =>
							DO <= ROM_BASE(15 downto 8);
						when x"B" =>
							DO <= ROM_BASE(23 downto 16);
						when x"C" =>
							DO <= "000000" & PAGE_LOCK;
						when x"D" =>
							DO <= ROM_PAGE(7 downto 0);
						when x"E" =>
							DO <= "0" & ROM_PAGE(14 downto 8);
						when x"F" =>
						
						when others => null;
					end case;
				elsif ADDR(7 downto 4) = x"5" then
					case ADDR(3 downto 0) is
						when x"0" =>																-- 7F50
							DO <= "0" & WS1 & "0" & WS2;
						when x"1" =>																-- 7F51
							DO <= "0000000" & not IRQ_EN;
						when x"2" =>																-- 7F52
							DO <= "0000000" & ROM_MODE;
						when x"E" =>																-- 7F5E
							DO <= (ROM_ACCESS or SRAM_ACCESS) & BUSY & "0000" & IRQ_FLAG & SUSPEND;
						when others => null;
					end case;
				elsif ADDR(7 downto 5) = "011" then											-- 7F60-7F7F
					DO <= VEC_MEM(to_integer(unsigned(ADDR(4 downto 0))));
				elsif ADDR(7 downto 4) >= x"8" and ADDR(7 downto 4) <= x"A" then	-- 7F80-7FAF
					case ADDR(7 downto 0) is
						when x"80" => DO <= GPR(0)(7 downto 0);
						when x"81" => DO <= GPR(0)(15 downto 8);
						when x"82" => DO <= GPR(0)(23 downto 16);
						when x"83" => DO <= GPR(1)(7 downto 0);
						when x"84" => DO <= GPR(1)(15 downto 8);
						when x"85" => DO <= GPR(1)(23 downto 16);
						when x"86" => DO <= GPR(2)(7 downto 0);
						when x"87" => DO <= GPR(2)(15 downto 8);
						when x"88" => DO <= GPR(2)(23 downto 16);
						when x"89" => DO <= GPR(3)(7 downto 0);
						when x"8A" => DO <= GPR(3)(15 downto 8);
						when x"8B" => DO <= GPR(3)(23 downto 16);
						when x"8C" => DO <= GPR(4)(7 downto 0);
						when x"8D" => DO <= GPR(4)(15 downto 8);
						when x"8E" => DO <= GPR(4)(23 downto 16);
						when x"8F" => DO <= GPR(5)(7 downto 0);
						when x"90" => DO <= GPR(5)(15 downto 8);
						when x"91" => DO <= GPR(5)(23 downto 16);
						when x"92" => DO <= GPR(6)(7 downto 0);
						when x"93" => DO <= GPR(6)(15 downto 8);
						when x"94" => DO <= GPR(6)(23 downto 16);
						when x"95" => DO <= GPR(7)(7 downto 0);
						when x"96" => DO <= GPR(7)(15 downto 8);
						when x"97" => DO <= GPR(7)(23 downto 16);
						when x"98" => DO <= GPR(8)(7 downto 0);
						when x"99" => DO <= GPR(8)(15 downto 8);
						when x"9A" => DO <= GPR(8)(23 downto 16);
						when x"9B" => DO <= GPR(9)(7 downto 0);
						when x"9C" => DO <= GPR(9)(15 downto 8);
						when x"9D" => DO <= GPR(9)(23 downto 16);
						when x"9E" => DO <= GPR(10)(7 downto 0);
						when x"9F" => DO <= GPR(10)(15 downto 8);
						when x"A0" => DO <= GPR(10)(23 downto 16);
						when x"A1" => DO <= GPR(11)(7 downto 0);
						when x"A2" => DO <= GPR(11)(15 downto 8);
						when x"A3" => DO <= GPR(11)(23 downto 16);
						when x"A4" => DO <= GPR(12)(7 downto 0);
						when x"A5" => DO <= GPR(12)(15 downto 8);
						when x"A6" => DO <= GPR(12)(23 downto 16);
						when x"A7" => DO <= GPR(13)(7 downto 0);
						when x"A8" => DO <= GPR(13)(15 downto 8);
						when x"A9" => DO <= GPR(13)(23 downto 16);
						when x"AA" => DO <= GPR(14)(7 downto 0);
						when x"AB" => DO <= GPR(14)(15 downto 8);
						when x"AC" => DO <= GPR(14)(23 downto 16);
						when x"AD" => DO <= GPR(15)(7 downto 0);
						when x"AE" => DO <= GPR(15)(15 downto 8);
						when x"AF" => DO <= GPR(15)(23 downto 16);
						when others => null;
					end case;
				end if;
			end if;
		elsif RAMIO_SEL = '1' then											--6000-6FFF
			DO <= DATA_RAM_Q_B;
		elsif ADDR(23 downto 16) = x"00" and ADDR(15 downto 5) = "11111111111" and BUSY = '1' then	--00:FFE0-FFFF
			DO <= VEC_MEM(to_integer(unsigned(ADDR(4 downto 0))));
		else
			DO <= BUS_DI;
		end if;
	end process;
	
	process( ADDR, CACHE_RUN, ROM_BASE, CACHE_PAGE, CACHE_ADDR, CACHE_BANK, DMA_RUN, DMA_STATE, DMA_SRC_ADDR, DMA_DST_ADDR, ROM_ACCESS, SRAM_ACCESS, EXT_BUS_ADDR )
	begin
		if CACHE_RUN = '1' then
			INT_ADDR <= std_logic_vector(unsigned(ROM_BASE) + (unsigned(CACHE_PAGE(BitToInt(CACHE_BANK))(14 downto 0)) & unsigned(CACHE_ADDR)));
		elsif DMA_RUN = '1' then
			if DMA_STATE = '0' then
				INT_ADDR <= DMA_SRC_ADDR;
			else
				INT_ADDR <= DMA_DST_ADDR;
			end if;
		elsif ROM_ACCESS = '1' or SRAM_ACCESS = '1' then
			INT_ADDR <= EXT_BUS_ADDR;
		else
			INT_ADDR <= ADDR;
		end if;
	end process;

	
	process(INT_ADDR, MAPPER)
	begin
		ROM_SEL <= '0';
		SRAM_SEL <= '0';
		RAM_SEL <= '0';
		if MAPPER = '0' then																										--LoROM
			if INT_ADDR(15) = '1' then																							--00-3F:8000-FFFF, 80-BF:8000-FFFF 
				ROM_SEL <= '1';
			elsif INT_ADDR(23 downto 19) = "01110" and INT_ADDR(15) = '0'	then									--70-77:0000-7FFF 
				SRAM_SEL <= '1';
			elsif INT_ADDR(22) = '0' and INT_ADDR(15 downto 12) = "0110" then										--00-3F:6000-6FFF, 80-BF:6000-6FFF 
				RAM_SEL <= '1';
			end if;
		else																															--HiROM
			if INT_ADDR(23 downto 22) = "11" then																			--C0-FF:0000-FFFF
				ROM_SEL <= '1';
			elsif INT_ADDR(23 downto 20) = "0011" and INT_ADDR(15 downto 13) = "011" then						--30-3F:6000-7FFF, B0-BF:6000-7FFF 
				SRAM_SEL <= '1';
			elsif INT_ADDR(22 downto 20) <= "010" and INT_ADDR(15 downto 12) = "0110" then					--00-2F:6000-6FFF, 80-AF:6000-6FFF 
				RAM_SEL <= '1';
			end if;
		end if;
	end process; 
		
	BUS_A <= INT_ADDR;

	process(SUSPEND, SRAM_SEL, DMA_RUN, DMA_STATE, SRAM_ACCESS, SRAM_WR, ROM_SEL, INT_ADDR, MAPPER, ROM_MODE, WR_N, RD_N)
	begin
		if SUSPEND = '1' then
			ROM_CE1_N <= '1';
			ROM_CE2_N <= '1';
			SRAM_CE_N <= '1';
			BUS_OE_N <= '1';
			BUS_WE_N <= '1';
		elsif SRAM_SEL = '1' and DMA_RUN = '1' then
			ROM_CE1_N <= '1';
			ROM_CE2_N <= '1';
			SRAM_CE_N <= '0';
			BUS_OE_N <= DMA_STATE;
			BUS_WE_N <= not DMA_STATE;
		elsif SRAM_SEL = '1' then
			ROM_CE1_N <= '1';
			ROM_CE2_N <= '1';
			SRAM_CE_N <= '0';
			if SRAM_ACCESS = '1' then
				BUS_OE_N <= SRAM_WR;
				BUS_WE_N <= not SRAM_WR;
			else
				BUS_OE_N <= RD_N;
				BUS_WE_N <= WR_N;
			end if;
		elsif ROM_SEL = '1' then
			if (MAPPER = '0' and ROM_MODE = '0') or (MAPPER = '1' and ROM_MODE = '1') then
				ROM_CE1_N <= INT_ADDR(21);
				ROM_CE2_N <= not INT_ADDR(21);
			elsif MAPPER = '0' and ROM_MODE = '1' then
				ROM_CE1_N <= '0';
				ROM_CE2_N <= '1';
			else
				ROM_CE1_N <= INT_ADDR(20);
				ROM_CE2_N <= not INT_ADDR(20);
			end if;
			SRAM_CE_N <= '1';
			BUS_OE_N <= '1';
			BUS_WE_N <= '1';
		else
			ROM_CE1_N <= '1';
			ROM_CE2_N <= '1';
			SRAM_CE_N <= '1';
			BUS_OE_N <= '1';
			BUS_WE_N <= '1';
		end if;
	end process; 
	
	--for MISTer
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			BUS_RD_N <= '1';
			BUS_RD_CNT <= (others => '0');
		elsif rising_edge(CLK) then
			BUS_RD_N <= '1';
			if BUSY = '1' then
				BUS_RD_CNT <= BUS_RD_CNT + 1;
				if BUS_RD_CNT = 1 then
					BUS_RD_CNT <= (others => '0');
					BUS_RD_N <= '0';
				end if;
			else
				if SYSCLKR_CE = '1' or SYSCLKF_CE = '1' then
					BUS_RD_N <= '0';
					BUS_RD_CNT <= (others => '0');
				end if;
			end if;
		end if;
	end process;

	--CACHE
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			CACHE_RUN <= '0';
			CACHE_BANK <= '0';
			CACHE_PAGE <= (others => (others => '1'));
			CACHE_ADDR <= (others => '0');
			CACHE_WAIT_CNT <= (others => '0');
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				if CACHE_RUN = '0' then
					if CPU_RUN = '0' then
						if MMIO_WR = '1' and ADDR(11 downto 0) = x"F48" then	--7F48
							if CACHE_PAGE(BitToInt(DI(0)))(14 downto 0) /= ROM_PAGE then
								CACHE_RUN <= '1';
								CACHE_BANK <= DI(0);
								CACHE_PAGE(BitToInt(DI(0)))(14 downto 0) <= ROM_PAGE;
								CACHE_ADDR <= (others => '0');
							end if;
						elsif MMIO_WR = '1' and ADDR(11 downto 0) = x"F4C" then	--7F4C
							CACHE_PAGE(0)(15) <= DI(0);
							if DI(0) = '1' then
								CACHE_PAGE(0)(14 downto 0) <= ROM_PAGE;
							end if;
							CACHE_PAGE(1)(15) <= DI(1);
							if DI(1) = '1' then
								CACHE_PAGE(1)(14 downto 0) <= ROM_PAGE;
							end if;
						elsif MMIO_WR = '1' and ADDR(11 downto 0) = x"F4F" then	--7F4F
							if CACHE_PAGE(0)(15) = '1' and CACHE_PAGE(0)(14 downto 0) = ROM_PAGE then
								CACHE_BANK <= '0';
							elsif CACHE_PAGE(1)(15) = '1' and CACHE_PAGE(1)(14 downto 0) = ROM_PAGE then
								CACHE_BANK <= '1';
							end if;
						end if;
					elsif CPU_EN = '1' then
						if (INST = I_BR or INST = I_BSUB) and IR(9) = '1' and COND = '1' then
							if CACHE_PAGE(BitToInt(not BANK))(14 downto 0) /= P then
								CACHE_RUN <= '1';
								CACHE_BANK <= not BANK;
								CACHE_PAGE(BitToInt(not BANK))(14 downto 0) <= P;
								CACHE_ADDR <= (others => '0');
							end if;
						end if;
					end if;
				elsif SUSPEND = '0' and EN = '1' then
					CACHE_WAIT_CNT <= CACHE_WAIT_CNT + 1;
					if (CACHE_WAIT_CNT = unsigned(WS1) and ROM_SEL = '1') or (CACHE_WAIT_CNT = unsigned(WS2) and SRAM_SEL = '1') then
						CACHE_ADDR <= std_logic_vector(unsigned(CACHE_ADDR) + 1);
						if CACHE_ADDR = "111111111" then
							CACHE_RUN <= '0';
						end if;
						CACHE_WAIT_CNT <= (others => '0');
					end if;
				end if;
			end if;
		end if;
	end process;
	
	--DMA
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			DMA_RUN <= '0';
			DMA_SRC_ADDR <= (others => '0');
			DMA_DST_ADDR <= (others => '0');
			DMA_CNT <= (others => '0');
			DMA_WAIT_CNT <= (others => '0');
			DMA_DAT <= (others => '0');
			DMA_STATE <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				if DMA_RUN = '0' then
					if MMIO_WR = '1' and ADDR(11 downto 0) = x"F47" then	--7F47
						DMA_RUN <= '1';
						DMA_SRC_ADDR <= DMA_SRC;
						DMA_DST_ADDR <= DMA_DST;
						DMA_CNT <= unsigned(DMA_LEN) - 1;
						DMA_STATE <= '0';
					end if;
				elsif SUSPEND = '0' and EN = '1' then
					if DMA_STATE = '0' then
						if DMA_WAIT_CNT = unsigned(WS1) then
							DMA_WAIT_CNT <= (others => '0');
							DMA_SRC_ADDR <= std_logic_vector(unsigned(DMA_SRC_ADDR) + 1);
							DMA_DAT <= BUS_DI;
							DMA_STATE <= not DMA_STATE;
						else
							DMA_WAIT_CNT <= DMA_WAIT_CNT + 1;
						end if;
					else
						if (DMA_WAIT_CNT = unsigned(WS2) and SRAM_SEL = '1') or 
							(DMA_WAIT_CNT = 0 and RAM_SEL = '1') then
							DMA_WAIT_CNT <= (others => '0');
							DMA_DST_ADDR <= std_logic_vector(unsigned(DMA_DST_ADDR) + 1);
							DMA_CNT <= DMA_CNT - 1;
							if DMA_CNT = 0 then
								DMA_RUN <= '0';
							end if;
							DMA_STATE <= not DMA_STATE;
						else
							DMA_WAIT_CNT <= DMA_WAIT_CNT + 1;
						end if;
					end if;
				end if;
			end if;
		end if;
	end process;
	
	BUS_DO <= DMA_DAT when DMA_RUN = '1' else
		  DI when (SRAM_SEL = '1' and SRAM_ACCESS = '0' and WR_n = '0') else
		  MBR;

	IR <= CACHE_Q_H & CACHE_Q_L;
	
	process(IR)
	begin
		INST <= I_NOP;
		if IR(15 downto 10) = "000000" then
			INST <= I_NOP;
		elsif IR(15 downto 14) = "00" and IR(12 downto 10) >= "010" and IR(12 downto 10) <= "110" then
			if IR(13) = '0' then
				INST <= I_BR;
			else
				INST <= I_BSUB;
			end if;
		elsif IR(15 downto 10) = "000111" then
			INST <= I_FINEXT;
		elsif IR(15 downto 10) = "001001" then
			INST <= I_SKIP;
		elsif IR(15 downto 10) = "001111" then
			INST <= I_RTS;
		elsif IR(15 downto 10) = "010000" then
			INST <= I_INCEXT;
		elsif IR(15 downto 11) = "01001" or IR(15 downto 11) = "01010" then
			INST <= I_CMP;
		elsif IR(15 downto 11) = "01011" then
			INST <= I_EXTS;
		elsif IR(15 downto 11) = "01100" then
			INST <= I_MOV;
		elsif IR(15 downto 9) = "0111110" then
			INST <= I_LDP;
		elsif IR(15 downto 11) = "01101" then
			INST <= I_RDRAM;
		elsif IR(15 downto 10) = "011100" then
			INST <= I_RDROM;
		elsif IR(15 downto 13) = "100" and IR(12 downto 10) >= "000" and IR(12 downto 10) <= "101" then
			INST <= I_ADDSUB;
		elsif IR(15 downto 11) = "10011" then
			INST <= I_MUL;
		elsif IR(15 downto 13) = "101" then
			INST <= I_LOG;
		elsif IR(15 downto 13) = "110" then
			INST <= I_SHIFT;
		elsif IR(15 downto 9) = "1110000" then
			INST <= I_ST;
		elsif IR(15 downto 11) = "11101" and IR(9 downto 8) /= "11" then
			INST <= I_WRRAM;
		elsif IR(15 downto 10) = "111100" then
			INST <= I_SWAP;
		elsif IR(15 downto 10) = "111110" then
			INST <= I_CLR;
		elsif IR(15 downto 10) = "111111" then
			INST <= I_HLT;
		end if;
	end process;

	
	RDB <= A when IR(7 downto 0) = x"00" else
			 MACH when IR(7 downto 0) = x"01" else
			 MACL when IR(7 downto 0) = x"02" else
			 x"0000" & MBR when IR(7 downto 0) = x"03" else
			 ROMB when IR(7 downto 0) = x"08" else
			 RAMB when IR(7 downto 0) = x"0C" else
			 MAR when IR(7 downto 0) = x"13" else
			 x"000" & DPR when IR(7 downto 0) = x"1C" else
			 x"00" & "0" & P when IR(7 downto 0) = x"28" else
			 x"0000" & MBR when IR(7 downto 0) = x"2E" else
			 x"000000" when IR(7 downto 0) = x"50" else
			 x"FFFFFF" when IR(7 downto 0) = x"51" else
			 x"00FF00" when IR(7 downto 0) = x"52" else
			 x"FF0000" when IR(7 downto 0) = x"53" else
			 x"00FFFF" when IR(7 downto 0) = x"54" else
			 x"FFFF00" when IR(7 downto 0) = x"55" else
			 x"800000" when IR(7 downto 0) = x"56" else
			 x"7FFFFF" when IR(7 downto 0) = x"57" else
			 x"008000" when IR(7 downto 0) = x"58" else
			 x"007FFF" when IR(7 downto 0) = x"59" else
			 x"FF7FFF" when IR(7 downto 0) = x"5A" else
			 x"FFFF7F" when IR(7 downto 0) = x"5B" else
			 x"010000" when IR(7 downto 0) = x"5C" else
			 x"FEFFFF" when IR(7 downto 0) = x"5D" else
			 x"000100" when IR(7 downto 0) = x"5E" else
			 x"00FEFF" when IR(7 downto 0) = x"5F" else
			 GPR(0) when IR(7 downto 0) = x"60" else
			 GPR(1) when IR(7 downto 0) = x"61" else
			 GPR(2) when IR(7 downto 0) = x"62" else
			 GPR(3) when IR(7 downto 0) = x"63" else
			 GPR(4) when IR(7 downto 0) = x"64" else
			 GPR(5) when IR(7 downto 0) = x"65" else
			 GPR(6) when IR(7 downto 0) = x"66" else
			 GPR(7) when IR(7 downto 0) = x"67" else
			 GPR(8) when IR(7 downto 0) = x"68" else
			 GPR(9) when IR(7 downto 0) = x"69" else
			 GPR(10) when IR(7 downto 0) = x"6A" else
			 GPR(11) when IR(7 downto 0) = x"6B" else
			 GPR(12) when IR(7 downto 0) = x"6C" else
			 GPR(13) when IR(7 downto 0) = x"6D" else
			 GPR(14) when IR(7 downto 0) = x"6E" else
			 GPR(15) when IR(7 downto 0) = x"6F" else
			 x"000000";
			 
	SH_A <= A                    when IR(9 downto 8) = "00" else
			  A(22 downto 0)&"0"   when IR(9 downto 8) = "01" else
			  A(15 downto 0)&x"00" when IR(9 downto 8) = "10" else
			  A(7 downto 0)&x"0000";
	
	--ALU
	process(INST, A, SH_A, RDB, IR)
	variable TEMP : std_logic_vector(24 downto 0);
	begin
		ALUR <= (others => '0');
		ALUC <= '0';
		if INST = I_ADDSUB then
			case IR(12 downto 10) is
				when "000" =>
					TEMP := std_logic_vector(("0" & unsigned(SH_A)) + ("0" & unsigned(RDB)));
				when "001" =>
					TEMP := std_logic_vector(("0" & unsigned(SH_A)) + ("0" & x"0000" & unsigned(IR(7 downto 0))));
				when "010" =>
					TEMP := std_logic_vector(("0" & unsigned(RDB)) - ("0" & unsigned(SH_A)));
				when "011" =>
					TEMP := std_logic_vector(("0" & x"0000" & unsigned(IR(7 downto 0))) - ("0" & unsigned(SH_A)));
				when "100" =>
					TEMP := std_logic_vector(("0" & unsigned(SH_A)) - ("0" & unsigned(RDB)));
				when "101" =>
					TEMP := std_logic_vector(("0" & unsigned(SH_A)) - ("0" & x"0000" & unsigned(IR(7 downto 0))));
				when others => 
					TEMP := (others => '0');
			end case;
			ALUR <= TEMP(23 downto 0);
			ALUC <= TEMP(24);
		elsif INST = I_LOG then
			case IR(12 downto 10) is
				when "000" =>
					ALUR <= SH_A xor (not RDB);
				when "001" =>
					ALUR <= SH_A xor (not (x"0000" & IR(7 downto 0)));
				when "010" =>
					ALUR <= SH_A xor RDB;
				when "011" =>
					ALUR <= SH_A xor (x"0000" & IR(7 downto 0));
				when "100" =>
					ALUR <= SH_A and RDB;
				when "101" =>
					ALUR <= SH_A and (x"0000" & IR(7 downto 0));
				when "110" =>
					ALUR <= SH_A or RDB;
				when "111" =>
					ALUR <= SH_A or (x"0000" & IR(7 downto 0));
				when others => null;
			end case;
		elsif INST = I_SHIFT then
			case IR(12 downto 10) is
				when "000" =>
					ALUR <= std_logic_vector(shift_right(unsigned(A), to_integer(unsigned(RDB(4 downto 0)))));
				when "001" =>
					ALUR <= std_logic_vector(shift_right(unsigned(A), to_integer(unsigned(IR(4 downto 0)))));
				when "010" =>
					ALUR <= std_logic_vector(shift_right(signed(A), to_integer(unsigned(RDB(4 downto 0)))));
				when "011" =>
					ALUR <= std_logic_vector(shift_right(signed(A), to_integer(unsigned(IR(4 downto 0)))));
				when "100" =>
					ALUR <= std_logic_vector(rotate_right(unsigned(A), to_integer(unsigned(RDB(4 downto 0)))));
				when "101" =>
					ALUR <= std_logic_vector(rotate_right(unsigned(A), to_integer(unsigned(IR(4 downto 0)))));
				when "110" =>
					ALUR <= std_logic_vector(shift_left(unsigned(A), to_integer(unsigned(RDB(4 downto 0)))));
				when "111" =>
					ALUR <= std_logic_vector(shift_left(unsigned(A), to_integer(unsigned(IR(4 downto 0)))));
				when others => null;
			end case;
		elsif INST = I_CMP then
			case IR(12 downto 10) is
				when "010" =>
					TEMP := std_logic_vector(("0" & unsigned(RDB)) - ("0" & unsigned(SH_A)));
				when "011" =>
					TEMP := std_logic_vector(("0" & x"0000" & unsigned(IR(7 downto 0))) - ("0" & unsigned(SH_A)));
				when "100" =>
					TEMP := std_logic_vector(("0" & unsigned(SH_A)) - ("0" & unsigned(RDB)));
				when "101" =>
					TEMP := std_logic_vector(("0" & unsigned(SH_A)) - ("0" & x"0000" & unsigned(IR(7 downto 0))));
				when others => 
					TEMP := (others => '0');
			end case;
			ALUR <= TEMP(23 downto 0);
			ALUC <= TEMP(24);
		elsif INST = I_EXTS then
			if IR(9 downto 8) = "01" then
				ALUR <= (0 to 15 => A(7)) & A(7 downto 0);
			elsif IR(9 downto 8) = "10" then
				ALUR <= (0 to 7 => A(15)) & A(15 downto 0);
			end if;
		end if;
	end process;

	--Flags
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			FLAGS <= (others => '0');
		elsif rising_edge(CLK) then
			if CPU_EN = '1' then
				if INST = I_ADDSUB or INST = I_LOG or INST = I_SHIFT or INST = I_CMP then
					FLAGS(FLAG_N) <= ALUR(23);
					if ALUR = x"000000" then
						FLAGS(FLAG_Z) <= '1';
					else
						FLAGS(FLAG_Z) <= '0';
					end if;
				end if;
				
				if INST = I_ADDSUB then
					case IR(12 downto 11) is
						when "00" =>
							FLAGS(FLAG_T) <= ALUC;
						when "01" | "10" =>
							FLAGS(FLAG_T) <= not ALUC;
						when others => null;
					end case;
				elsif INST = I_CMP then
					FLAGS(FLAG_T) <= not ALUC;
				end if;
				
				FLAGS(FLAG_V) <= '0';-----------------------------------------------
			end if;
		end if;
	end process; 
	
	--MUL
	process(CLK, RST_N)
		variable TEMP : signed(47 downto 0);
	begin
		if RST_N = '0' then
			MULA <= (others => '0');
			MULB <= (others => '0');
			MACL <= (others => '0');
			MACH <= (others => '0');
		elsif rising_edge(CLK) then
			if CPU_EN = '1' and INST = I_MUL then
				MULA <= signed(A);
				if IR(10) = '0' then
					MULB <= signed(RDB);
				else
					MULB <= signed(resize(unsigned(IR(7 downto 0)), MULB'length));
				end if;
			end if;
				
			if EN = '1' and SUSPEND = '0' then
				TEMP := MULA * MULB;
				MACL <= std_logic_vector(TEMP(23 downto 0));
				MACH <= std_logic_vector(TEMP(47 downto 24));
			end if;
		end if;
	end process; 
	
		
	--Registers
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			A <= (others => '0');
		elsif rising_edge(CLK) then
			if CPU_EN = '1' then
				if INST = I_MOV then 
					if IR(10 downto 8) = "000" then
						A <= RDB;
					elsif IR(10 downto 8) = "100" then
						A <= x"0000" & IR(7 downto 0);
					end if;
				elsif INST = I_ADDSUB or INST = I_LOG or INST = I_SHIFT or INST = I_EXTS then
					A <= ALUR;
				elsif INST = I_SWAP then
					A <= GPR(to_integer(unsigned(IR(3 downto 0))));
				elsif INST = I_CLR then
					A <= (others => '0');
				end if;
			end if;
		end if;
	end process;
	
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			MBR <= (others => '0');
			MAR <= (others => '0');
			EXT_BUS_ADDR <= (others => '0');
			BUS_ACCESS_CNT <= (others => '0');
			ROM_ACCESS <= '0';
			SRAM_ACCESS <= '0';
			SRAM_WR <= '0';
		elsif rising_edge(CLK) then
			if CPU_EN = '1' then
				if ROM_ACCESS = '1' or SRAM_ACCESS = '1' then 
					if BUS_ACCESS_CNT = 0 then
						ROM_ACCESS <= '0';
						SRAM_ACCESS <= '0';
						SRAM_WR <= '0';
					else
						BUS_ACCESS_CNT <= BUS_ACCESS_CNT - 1;
					end if;
				end if;

				if INST = I_MOV then
					case IR(10 downto 8) is
						when "001" =>
							MBR <= RDB(7 downto 0);
							if IR(7 downto 1) = "0010111" then
								EXT_BUS_ADDR <= MAR;
								if IR(0) = '0' then
									ROM_ACCESS <= '1';
									BUS_ACCESS_CNT <= unsigned(WS1);
								else
									SRAM_ACCESS <= '1';
									BUS_ACCESS_CNT <= unsigned(WS2);
									SRAM_WR <= '0';
								end if;
							end if;
						when "010" =>
							MAR <= GPR(to_integer(unsigned(IR(3 downto 0))));
						when "101" =>
							MBR <= IR(7 downto 0);
						when "110" =>
							MAR <= x"0000" & IR(7 downto 0);						
						when others => null;
					end case;
				elsif INST = I_INCEXT then
					MAR <= std_logic_vector(unsigned(MAR) + 1);
				elsif INST = I_FINEXT then
					if BUS_ACCESS_CNT = 0 then
						MBR <= BUS_DI;
					end if;
				elsif INST = I_ST then
					if IR(8) = '0' and IR(6 downto 0) = "0010011" then
						MAR <= A;
					elsif IR(8) = '0' and IR(6 downto 0) = "0000011" then
						MBR <= A(7 downto 0);
					elsif IR(8) = '1' and IR(7 downto 0) = "00101111" then
						SRAM_ACCESS <= '1';
						BUS_ACCESS_CNT <= unsigned(WS2);
						SRAM_WR <= '1';
					end if;
				end if;
			end if;
		end if;
	end process; 
			
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			P <= (others => '1');
		elsif rising_edge(CLK) then
			if CPU_EN = '1' then
				if INST = I_MOV then
					case IR(10 downto 8) is
						when "011" =>
							P <= GPR(to_integer(unsigned(IR(3 downto 0))))(14 downto 0);
						when "111" =>
							P <= "0000000" & IR(7 downto 0);
						when others => null;
					end case;
				elsif INST = I_LDP then
					if IR(8) = '0' then
						P(7 downto 0) <= IR(7 downto 0);
					else
						P(14 downto 8) <= IR(6 downto 0);
					end if;
				elsif INST = I_CLR then
					P <= (others => '0');
				end if;
			end if;
		end if;
	end process; 

	process(CLK, RST_N, INST, FLAGS, IR)
		variable NEXT_PC : std_logic_vector(7 downto 0);
	begin
		if INST = I_BR or INST = I_BSUB then
			case IR(12 downto 10) is
				when "010" => COND <= '1';
				when "011" => COND <= FLAGS(FLAG_Z);
				when "100" => COND <= FLAGS(FLAG_T);
				when "101" => COND <= FLAGS(FLAG_N);
				when "110" => COND <= FLAGS(FLAG_V);
				when others => COND <= '0';
			end case;
		elsif INST = I_SKIP then
			case IR(9 downto 8) is
				when "00" => COND <= FLAGS(FLAG_V) xor (not IR(0));
				when "01" => COND <= FLAGS(FLAG_T) xor (not IR(0));
				when "10" => COND <= FLAGS(FLAG_Z) xor (not IR(0));
				when "11" => COND <= FLAGS(FLAG_N) xor (not IR(0));
				when others => COND <= '0';
			end case;
		else
			COND <= '0';
		end if;
		
		if RST_N = '0' then
			PC <= (others => '0');
			BANK <= '0';
			STACK_RAM <= (others => (others => '0'));
			SP <= (others => '0');
			CPU_RUN <= '0';
			IRQ <= '0';
			IRQ_FLAG <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' and CPU_RUN = '0' then
				if MMIO_WR = '1' and ADDR(11 downto 0) = x"F48" then	--7F48
					BANK <= DI(0);
				elsif MMIO_WR = '1' and ADDR(11 downto 0) = x"F4F" then	--7F4F
					CPU_RUN <= '1';
					PC <= DI;
					if CACHE_PAGE(0)(15) = '1' and CACHE_PAGE(0)(14 downto 0) = ROM_PAGE then
						BANK <= '0';
					elsif CACHE_PAGE(1)(15) = '1' and CACHE_PAGE(1)(14 downto 0) = ROM_PAGE then
						BANK <= '1';
					end if;
					SP <= (others => '0');
				elsif MMIO_WR = '1' and ADDR(11 downto 0) = x"F53" then	--7F53
					CPU_RUN <= '0';
					IRQ <= IRQ_EN;
					IRQ_FLAG <= IRQ_EN;
				elsif MMIO_WR = '1' and ADDR(11 downto 0) = x"F51" then	--7F51
					if DI(0) = '1' then
						IRQ <= '0';
						IRQ_FLAG <= '0';
					end if;
				elsif MMIO_WR = '1' and ADDR(11 downto 0) = x"F5E" then	--7F5E
					IRQ_FLAG <= '0';
				end if;
			elsif CPU_EN = '1' then
				NEXT_PC := std_logic_vector(unsigned(PC) + 1);
				if INST = I_BR or INST = I_BSUB then
					EXTRA_CYCLES <= EXTRA_CYCLES + 1;
					case EXTRA_CYCLES is
						when 1 =>
							if INST = I_BSUB and COND = '1' then
								STACK_RAM(to_integer(SP)) <= BANK & NEXT_PC;
								SP <= SP + 1;
							end if;
						when 2 =>
							EXTRA_CYCLES <= 0;
							if COND = '1' then
								PC <= IR(7 downto 0);
								BANK <= BANK xor IR(9);
							else
								PC <= NEXT_PC;
							end if;
						when others => null;
					end case;
					
				elsif INST = I_SKIP then
					EXTRA_CYCLES <= EXTRA_CYCLES + 1;
					case EXTRA_CYCLES is
						when 1 =>
							EXTRA_CYCLES <= 0;
							if COND = '0' then
								PC <= NEXT_PC;
							else
								PC <= std_logic_vector(unsigned(NEXT_PC) + 1);
							end if;
						when others => null;
					end case;

				elsif INST = I_RTS then
					EXTRA_CYCLES <= EXTRA_CYCLES + 1;
					case EXTRA_CYCLES is
						when 0 =>
							SP <= SP - 1;
						when 1 =>
							EXTRA_CYCLES <= 0;
							PC <= STACK_RAM(to_integer(SP))(7 downto 0);
							BANK <= STACK_RAM(to_integer(SP))(8);
						when others => null;
					end case;

				elsif INST = I_FINEXT then
					if BUS_ACCESS_CNT = 0 then
						PC <= NEXT_PC;
					end if;
				else
					PC <= NEXT_PC;
				end if;
				
				if INST = I_HLT then
					CPU_RUN <= '0';
					IRQ <= IRQ_EN;
					IRQ_FLAG <= IRQ_EN;
				end if;
			end if;
		end if;
	end process; 
	
	IRQ_N <= not IRQ;
	
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			DPR <= (others => '0');
		elsif rising_edge(CLK) then
			if CPU_EN = '1' then
				if INST = I_ST and IR(8) = '0' and IR(6 downto 0) = "0011100" then
					DPR <= A(11 downto 0);
				end if;
			end if;
		end if;
	end process; 
	
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			GPR <= (others => (others => '0'));
		elsif rising_edge(CLK) then
			if ENABLE = '1' and CPU_RUN = '0' then
				if MMIO_WR = '1' and ADDR(11 downto 8) = x"F" then	--7F80-7FAF
					case ADDR(7 downto 0) is
						when x"80" => GPR(0)(7 downto 0) <= DI;
						when x"81" => GPR(0)(15 downto 8) <= DI;
						when x"82" => GPR(0)(23 downto 16) <= DI;
						when x"83" => GPR(1)(7 downto 0) <= DI;
						when x"84" => GPR(1)(15 downto 8) <= DI;
						when x"85" => GPR(1)(23 downto 16) <= DI;
						when x"86" => GPR(2)(7 downto 0) <= DI;
						when x"87" => GPR(2)(15 downto 8) <= DI;
						when x"88" => GPR(2)(23 downto 16) <= DI;
						when x"89" => GPR(3)(7 downto 0) <= DI;
						when x"8A" => GPR(3)(15 downto 8) <= DI;
						when x"8B" => GPR(3)(23 downto 16) <= DI;
						when x"8C" => GPR(4)(7 downto 0) <= DI;
						when x"8D" => GPR(4)(15 downto 8) <= DI;
						when x"8E" => GPR(4)(23 downto 16) <= DI;
						when x"8F" => GPR(5)(7 downto 0) <= DI;
						when x"90" => GPR(5)(15 downto 8) <= DI;
						when x"91" => GPR(5)(23 downto 16) <= DI;
						when x"92" => GPR(6)(7 downto 0) <= DI;
						when x"93" => GPR(6)(15 downto 8) <= DI;
						when x"94" => GPR(6)(23 downto 16) <= DI;
						when x"95" => GPR(7)(7 downto 0) <= DI;
						when x"96" => GPR(7)(15 downto 8) <= DI;
						when x"97" => GPR(7)(23 downto 16) <= DI;
						when x"98" => GPR(8)(7 downto 0) <= DI;
						when x"99" => GPR(8)(15 downto 8) <= DI;
						when x"9A" => GPR(8)(23 downto 16) <= DI;
						when x"9B" => GPR(9)(7 downto 0) <= DI;
						when x"9C" => GPR(9)(15 downto 8) <= DI;
						when x"9D" => GPR(9)(23 downto 16) <= DI;
						when x"9E" => GPR(10)(7 downto 0) <= DI;
						when x"9F" => GPR(10)(15 downto 8) <= DI;
						when x"A0" => GPR(10)(23 downto 16) <= DI;
						when x"A1" => GPR(11)(7 downto 0) <= DI;
						when x"A2" => GPR(11)(15 downto 8) <= DI;
						when x"A3" => GPR(11)(23 downto 16) <= DI;
						when x"A4" => GPR(12)(7 downto 0) <= DI;
						when x"A5" => GPR(12)(15 downto 8) <= DI;
						when x"A6" => GPR(12)(23 downto 16) <= DI;
						when x"A7" => GPR(13)(7 downto 0) <= DI;
						when x"A8" => GPR(13)(15 downto 8) <= DI;
						when x"A9" => GPR(13)(23 downto 16) <= DI;
						when x"AA" => GPR(14)(7 downto 0) <= DI;
						when x"AB" => GPR(14)(15 downto 8) <= DI;
						when x"AC" => GPR(14)(23 downto 16) <= DI;
						when x"AD" => GPR(15)(7 downto 0) <= DI;
						when x"AE" => GPR(15)(15 downto 8) <= DI;
						when x"AF" => GPR(15)(23 downto 16) <= DI;
						when others => null;
					end case;
				end if;
			elsif CPU_EN = '1' then
				if (INST = I_ST and IR(8) = '0' and IR(6 downto 4) = "110") or INST = I_SWAP then
					GPR(to_integer(unsigned(IR(3 downto 0)))) <= A;
				end if;
			end if;
		end if;
	end process; 
	
	process( IR, A, DPR, RAMB, DMA_RUN, DMA_DST_ADDR, RAM_SEL, DMA_DAT)
	begin
		if DMA_RUN = '1' and RAM_SEL = '1' then
			DATA_RAM_ADDR_A <= DMA_DST_ADDR(11 downto 0);
		elsif IR(10) = '0' then
			DATA_RAM_ADDR_A <= A(11 downto 0);
		else
			DATA_RAM_ADDR_A <= std_logic_vector(unsigned(DPR) + unsigned(IR(7 downto 0)));
		end if;
		
		if DMA_RUN = '1' and RAM_SEL = '1' then
			DATA_RAM_DI_A <= DMA_DAT;
		else
			case IR(9 downto 8) is
				when "00" =>   DATA_RAM_DI_A <= RAMB(7 downto 0);
				when "01" =>   DATA_RAM_DI_A <= RAMB(15 downto 8);
				when others => DATA_RAM_DI_A <= RAMB(23 downto 16);
			end case;
		end if;
	end process; 
		
	process(CLK, RST_N)
	begin
		if RST_N = '0' then
			RAMB <= (others => '0');
		elsif rising_edge(CLK) then
			if CPU_EN = '1' then
				if INST = I_RDRAM then
					case IR(9 downto 8) is
						when "00" => RAMB(7 downto 0) <= DATA_RAM_Q_A;
						when "01" => RAMB(15 downto 8) <= DATA_RAM_Q_A;
						when "10" => RAMB(23 downto 16) <= DATA_RAM_Q_A;
						when others => null;
					end case;
				elsif INST = I_ST and IR(8) = '0' and IR(6 downto 0) = "0001100" then
					RAMB <= A;
				elsif INST = I_CLR then
					RAMB <= (others => '0');
				end if;
			end if;
		end if;
	end process; 
	
	process(CLK, RST_N, IR, A)
	begin
		if IR(10) = '0' then
			DATA_ROM_ADDR <= A(9 downto 0);
		else
			DATA_ROM_ADDR <= IR(9 downto 0);
		end if;
		
		if RST_N = '0' then
			ROMB <= (others => '0');
		elsif rising_edge(CLK) then
			if CPU_EN = '1' then
				if INST = I_RDROM then
					ROMB <= DATA_ROM_Q;
				end if;
			end if;
		end if;
	end process; 

	DATA_ROM : entity work.spram generic map(10, 24, "rtl/chip/CX4/drom.mif")
	port map(
		clock		=> not CLK,
		address	=> DATA_ROM_ADDR,
		q			=> DATA_ROM_Q
	);
	
	DATA_RAM_WE_A <= '1' when (CPU_EN = '1' and INST = I_WRRAM) or (EN = '1' and DMA_RUN = '1' and RAM_SEL = '1' and DMA_STATE = '1') else '0';
	DATA_RAM_ADDR_B <= ADDR(11 downto 0);
	DATA_RAM_DI_B <= DI;
	DATA_RAM_WE_B <= '1' when ENABLE = '1' and RAMIO_WR = '1' and CPU_RUN = '0' else '0';
	DATA_RAM : entity work.dpram_difclk generic map(12, 8, 12, 8)
	port map(
		clock0		=> not CLK,
		address_a	=> DATA_RAM_ADDR_A,
		data_a		=> DATA_RAM_DI_A,
		wren_a		=> DATA_RAM_WE_A,
		q_a			=> DATA_RAM_Q_A,
		
		clock1		=> CLK,
		address_b	=> DATA_RAM_ADDR_B,
		data_b		=> DATA_RAM_DI_B,
		wren_b		=> DATA_RAM_WE_B,
		q_b			=> DATA_RAM_Q_B
	);

	CACHE_ADDR_RD <= BANK & PC;
	CACHE_ADDR_WR <= CACHE_BANK & CACHE_ADDR;
	CACHE_WE <= '1' when CACHE_RUN = '1' and EN = '1' and CACHE_WAIT_CNT = unsigned(WS1) else '0';
	CACHE_DI <= BUS_DI;
	
	CACHEL : entity work.cx4cache
	port map(
		clock			=> CLK,
		wraddress	=> CACHE_ADDR_WR(9 downto 1),
		data			=> CACHE_DI,
		wren			=> CACHE_WE and not CACHE_ADDR_WR(0),
		rdaddress	=> CACHE_ADDR_RD,
		q				=> CACHE_Q_L
	);
	
	CACHEH : entity work.cx4cache
	port map(
		clock			=> CLK,
		wraddress	=> CACHE_ADDR_WR(9 downto 1),
		data			=> CACHE_DI,
		wren			=> CACHE_WE and CACHE_ADDR_WR(0),
		rdaddress	=> CACHE_ADDR_RD,
		q				=> CACHE_Q_H
	);
	
end rtl;
