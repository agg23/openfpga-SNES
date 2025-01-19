library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;


entity SA1 is
	port(
		RST_N			: in std_logic;
		CLK			: in std_logic;
		ENABLE		: in std_logic;
		
		SNES_A   	: in std_logic_vector(23 downto 0);
		SNES_DO		: out std_logic_vector(7 downto 0);
		SNES_DI		: in std_logic_vector(7 downto 0);
		SNES_RD_N	: in std_logic;
		SNES_WR_N	: in std_logic;
		
		SYSCLKF_CE	: in std_logic;
		SYSCLKR_CE	: in std_logic;
		
		REFRESH		: in std_logic;
		
		PAL			: in std_logic;
		
		ROM_A       : out std_logic_vector(22 downto 0);
		ROM_DI		: in std_logic_vector(15 downto 0);
		ROM_RD_N		: out std_logic;							--for MISTer sdram
		
		BWRAM_A		: out std_logic_vector(17 downto 0);
		BWRAM_DI		: in std_logic_vector(7 downto 0);
		BWRAM_DO		: out std_logic_vector(7 downto 0);
		BWRAM_OE_N	: out std_logic;
		BWRAM_WE_N	: out std_logic;
		
		IRQ_N			: out std_logic
	);
end SA1;

architecture rtl of SA1 is

signal CLK_CE					: std_logic;
signal EN						: std_logic;
signal WINDOW					: std_logic;
signal DOT_CLK					: std_logic; 
signal SNES_SYSCLK			: std_logic; 
signal SYSCLKR_CE_NEXT: std_logic; 
signal SA1_EN					: std_logic;

--65C816
signal P65_R_WN				: std_logic;
signal P65_A					: std_logic_vector(23 downto 0);
signal P65_DO					: std_logic_vector(7 downto 0);
signal P65_DI					: std_logic_vector(7 downto 0);
signal P65_NMI_N				: std_logic;
signal P65_IRQ_N				: std_logic;
signal P65_RST_N				: std_logic;
signal P65_EN					: std_logic;
signal P65_VDA					: std_logic;
signal P65_VPA					: std_logic;
signal P65_VPB					: std_logic;
signal P65_BRK					: std_logic;
signal P65_WR					: std_logic;
signal P65_RD					: std_logic;

--BUS
signal INT_SNES_A				: std_logic_vector(23 downto 0);
signal INT_ROM_A				: std_logic_vector(23 downto 0);
signal ROM_MAP_A				: std_logic_vector(23 downto 0);
signal SNES_BWRAM_A			: std_logic_vector(23 downto 0);
signal SNES_BWRAM_MAP_A		: std_logic_vector(17 downto 0);
signal SA1_BWRAM_MAP_A		: std_logic_vector(17 downto 0);
signal SA1_BWRAM_DAT			: std_logic_vector(7 downto 0);
signal SNES_ROM_ACCESS		: std_logic;
signal SNES_BWRAM_ACCESS	: std_logic;
signal SNES_IRAM_ACCESS		: std_logic;
signal SNES_CCDMA_IRAM_ACCESS : std_logic;
signal SNES_MMIO_READ_ACCESS : std_logic;
signal SNES_MMIO_WRITE_ACCESS : std_logic;
signal SA1_ROM_ACCESS		: std_logic;
signal SA1_BWRAM_ACCESS		: std_logic;
signal SA1_BBF_ACCESS		: std_logic;
signal SA1_IRAM_ACCESS		: std_logic;
signal SA1_MMIO_READ_ACCESS : std_logic;
signal SA1_MMIO_WRITE_ACCESS : std_logic;
signal SNES_ROM_SEL			: std_logic;
signal SNES_BWRAM_SEL		: std_logic;
signal SNES_BWRAM_WE		   : std_logic;
signal SNES_IRAM_SEL			: std_logic;
signal SNES_IRAM_WE			: std_logic;
signal SA1_INT_SEL			: std_logic;
signal SA1_ROM_SEL			: std_logic;
signal SA1_BWRAM_SEL			: std_logic;
signal SA1_BWRAM_WE		   : std_logic;
signal SA1_IRAM_SEL			: std_logic;
signal SA1_IRAM_WE			: std_logic;
signal SA1_BWRAM_WAIT		: std_logic;
signal SA1_IRAM_WAIT			: std_logic;
signal SA1_MMIO_READ			: std_logic;
signal SA1_MMIO_WRITE		: std_logic;
signal SNES_MMIO_WRITE		: std_logic;
signal SNES_ROM_EN			: std_logic;
signal SNES_BWRAM_EN			: std_logic;
signal SNES_IRAM_EN			: std_logic;
signal SA1_ROM_EN				: std_logic;
signal SA1_BWRAM_EN			: std_logic;
signal SA1_IRAM_EN			: std_logic;
signal SA1_INT_EN				: std_logic;
signal SA1_BWRAM_VALID		: std_logic;
signal BWRAM_WP_MASK			: std_logic_vector(9 downto 0);
signal OPENBUS					: std_logic_vector(7 downto 0);

--DMA
signal DMA_ROM_DAT			: std_logic_vector(7 downto 0);
signal INT_DMA_DAT			: std_logic_vector(7 downto 0);
signal DMA_SRC_ROM_SEL		: std_logic;
signal DMA_SRC_BWRAM_SEL	: std_logic;
signal DMA_SRC_IRAM_SEL		: std_logic;
signal DMA_DST_BWRAM_SEL	: std_logic;
signal DMA_DST_IRAM_SEL		: std_logic;
signal DMA_BWRAM_WAIT		: std_logic;
signal DMA_IRAM_WAIT			: std_logic;
signal CCDMA_SRC_BWRAM_SEL : std_logic;
signal CCDMA_DST_IRAM_SEL	: std_logic;
signal DMA_ROM_MSB			: std_logic_vector(7 downto 0);
signal DMA_ROM_MSB_VALID	: std_logic;
signal DMA_SRC_ROM_EN		: std_logic;
signal DMA_SRC_BWRAM_EN		: std_logic;
signal DMA_SRC_IRAM_EN		: std_logic;
signal DMA_DST_BWRAM_EN		: std_logic;
signal DMA_DST_IRAM_EN		: std_logic;
signal CCDMA_BWRAM_VALID	: std_logic;
signal CCDMA_BWRAM_EN		: std_logic;
signal CCDMA_IRAM_EN			: std_logic;
signal DMA_RUN					: std_logic;
signal DMA_EN					: std_logic;
signal NDMA_EN					: std_logic;

--CC DMA
type CCBppTable is array (0 to 3) of unsigned(2 downto 0);
constant CC_BPP_TAB			: CCBppTable := ("111","011","001","000");
signal CC_BPP					: unsigned(2 downto 0);
signal CC_TILE_Y				: unsigned(2 downto 0);
signal CC_TILE_N				: unsigned(14 downto 0);
signal CCDMA_RW				: std_logic;
signal CC1_BWRAM_RD_ADDR	: std_logic_vector(17 downto 0);
signal CC1_IRAM_RD_ADDR		: std_logic_vector(10 downto 0);
signal CC12_IRAM_WR_ADDR	: std_logic_vector(10 downto 0);
signal CC12_IRAM_WR_DAT		: std_logic_vector(7 downto 0);
signal CC1DMA_EXEC			: std_logic;

--VBP
signal VBIT						: unsigned(3 downto 0);
signal VBP_BUF					: std_logic_vector(31 downto 0);
signal VBP_EN					: std_logic;
signal VBP_RUN					: std_logic;
signal VBP_PRELOAD			: std_logic;
signal VBP_DAT					: std_logic_vector(7 downto 0);

--IRQ
signal SA1_NMI_FLAG			: std_logic;
signal SA1_IRQ_FLAG			: std_logic;
signal DMA_IRQ_FLAG			: std_logic;
signal TM_IRQ_FLAG			: std_logic;
signal SNES_IRQ_FLAG			: std_logic;
signal CDMA_IRQ_FLAG			: std_logic;
signal SA1_IRQ					: std_logic;
signal SA1_NMI					: std_logic;
signal SNES_IRQ				: std_logic;

--MATH
signal MULR						: std_logic_vector(31 downto 0);
signal DIVQ						: std_logic_vector(15 downto 0);
signal DIVR						: std_logic_vector(15 downto 0);
signal MATH_CLK_CNT			: unsigned(2 downto 0);
signal MATH_REQ				: std_logic;

-- IO Registers
signal SMSG						: std_logic_vector(3 downto 0);
signal SA1RST					: std_logic;
signal SA1WAIT					: std_logic;
signal SNES_IRQ_EN			: std_logic;
signal CDMA_IRQ_EN			: std_logic;
signal CRV						: std_logic_vector(15 downto 0);
signal CNV						: std_logic_vector(15 downto 0);
signal CIV						: std_logic_vector(15 downto 0);
signal CMSG						: std_logic_vector(3 downto 0);
signal NMISEL					: std_logic;
signal IRQSEL					: std_logic;
signal SA1_NMI_EN				: std_logic;
signal SA1_IRQ_EN				: std_logic;
signal DMA_IRQ_EN				: std_logic;
signal TM_IRQ_EN				: std_logic;
signal SNV						: std_logic_vector(15 downto 0);
signal SIV						: std_logic_vector(15 downto 0);
signal HVEN						: std_logic_vector(1 downto 0);
signal TMMODE					: std_logic;
signal HCNT						: std_logic_vector(8 downto 0);
signal VCNT						: std_logic_vector(8 downto 0);
signal CXB						: std_logic_vector(2 downto 0);
signal DXB						: std_logic_vector(2 downto 0);
signal EXB						: std_logic_vector(2 downto 0);
signal FXB						: std_logic_vector(2 downto 0);
signal CBMAP					: std_logic;
signal DBMAP					: std_logic;
signal EBMAP					: std_logic;
signal FBMAP					: std_logic;
signal BMAPS					: std_logic_vector(7 downto 0);
signal BMAP						: std_logic_vector(6 downto 0);
signal SBW46					: std_logic;
signal BBF						: std_logic;
signal SBWE						: std_logic_vector(7 downto 0);
signal CBWE						: std_logic_vector(7 downto 0);
signal BWPA						: std_logic_vector(7 downto 0);
signal SIWP						: std_logic_vector(7 downto 0);
signal CIWP						: std_logic_vector(7 downto 0);
signal DMASD					: std_logic_vector(1 downto 0);
signal DMADD					: std_logic;
signal CDSEL					: std_logic;
signal CDEN						: std_logic;
signal DPRIO					: std_logic;
signal DMAEN					: std_logic;
signal CDMACB					: std_logic_vector(1 downto 0);
signal CDMASIZE				: std_logic_vector(2 downto 0);
--signal CDMAEND					: std_logic;
signal SDA						: std_logic_vector(23 downto 0);
signal DDA						: std_logic_vector(17 downto 0);
signal DTC						: std_logic_vector(15 downto 0);
type BRFReg_t is array (0 to 15) of std_logic_vector(7 downto 0); 
signal BRF						: BRFReg_t;
signal AM						: std_logic_vector(1 downto 0);
signal MA						: std_logic_vector(15 downto 0);
signal MB						: std_logic_vector(15 downto 0);
signal MR						: std_logic_vector(39 downto 0);
signal VB						: std_logic_vector(3 downto 0);
signal HL						: std_logic;
signal VDA						: std_logic_vector(23 downto 0);
signal VDP						: std_logic_vector(15 downto 0);
signal HCR						: std_logic_vector(8 downto 0);
signal VCR						: std_logic_vector(8 downto 0);
signal MOF						: std_logic;
signal H_CNT					: unsigned(8 downto 0);
signal V_CNT					: unsigned(8 downto 0);
signal MDR 						: std_logic_vector(7 downto 0);

--IRAM
signal IRAM_A					: std_logic_vector(10 downto 0);
signal IRAM_DI					: std_logic_vector(7 downto 0);
signal IRAM_DO					: std_logic_vector(7 downto 0);
signal IRAM_WE					: std_logic;

begin

process( RST_N, CLK )
begin
	if RST_N = '0' then
		CLK_CE <= '0';
		SNES_SYSCLK <= '0';
	elsif rising_edge(CLK) then
		if ENABLE = '1' then
			CLK_CE <= not CLK_CE;
			if SYSCLKF_CE = '1' then
				CLK_CE <= '0';
				WINDOW <= '1';
				SNES_SYSCLK <= '0';
			elsif SYSCLKR_CE = '1' then
				SNES_SYSCLK <= '1';
				INT_SNES_A <= SNES_A;
			end if;
			
			SYSCLKR_CE_NEXT <= SYSCLKR_CE;
			if CLK_CE = '1' then
				if SYSCLKR_CE = '1' or SYSCLKR_CE_NEXT = '1' then
					WINDOW <= '0';
				end if;
			end if;
		end if;
	end if;
end process;

EN <= ENABLE and CLK_CE;

-- 65C816
P65_RST_N <= not SA1RST and RST_N;
P65_EN <= not SA1WAIT and SA1_EN and ENABLE;
P65_NMI_N <= not SA1_NMI;
P65_IRQ_N <= not SA1_IRQ;

P65C816: entity work.P65C816 
port map (
	CLK         => CLK,
	RST_N       => P65_RST_N,
	CE       	=> CLK_CE,
	WE          => P65_R_WN,
	D_IN     	=> P65_DI,
	D_OUT    	=> P65_DO,
	A_OUT 		=> P65_A,
	RDY_IN      => P65_EN,
	NMI_N			=> P65_NMI_N,   
	IRQ_N			=> P65_IRQ_N,
	ABORT_N		=> '1',
	VPA      	=> P65_VPA,
	VDA      	=> P65_VDA,
	VPB      	=> P65_VPB
); 

P65_WR <= not P65_R_WN and (P65_VPA or P65_VDA);
P65_RD <=     P65_R_WN and (P65_VPA or P65_VDA);

--BUS control
SNES_ROM_ACCESS <= '1' when (SNES_A(22) = '0' and SNES_A(15) = '1') or (SNES_A(23 downto 22) = "11") else '0';
SNES_BWRAM_ACCESS <= not CC1DMA_EXEC when SNES_A(23 downto 20) = x"4" or (SNES_A(15 downto 13) = "011" and SNES_A(22) = '0') else '0';			
SNES_IRAM_ACCESS <= not REFRESH when SNES_A(22) = '0' and SNES_A(15 downto 11) = x"3" & "0"  else '0';	
SNES_CCDMA_IRAM_ACCESS <= CC1DMA_EXEC when SNES_A(23 downto 20) = x"4" else '0';	
SNES_MMIO_WRITE_ACCESS <= '1' when SNES_A(22) = '0' and SNES_A(15 downto 8) = x"22" else '0';	
SNES_MMIO_READ_ACCESS <= '1' when SNES_A(22) = '0' and SNES_A(15 downto 8) = x"23" else '0';	

SNES_ROM_SEL <= SNES_ROM_ACCESS and not WINDOW;
SNES_BWRAM_SEL <= SNES_BWRAM_ACCESS and not WINDOW;
SNES_IRAM_SEL <= (SNES_IRAM_ACCESS and SNES_SYSCLK) or (SNES_CCDMA_IRAM_ACCESS and not WINDOW);

SA1_ROM_ACCESS <= '1' when (P65_A(22) = '0' and P65_A(15) = '1') or (P65_A(23 downto 22) = "11") else '0';
SA1_BWRAM_ACCESS <= '1' when P65_A(23 downto 20) = x"4" or P65_A(23 downto 20) = x"5" or (P65_A(22) = '0' and P65_A(15 downto 13) = "011" and SBW46 = '0') else '0';
SA1_BBF_ACCESS <= '1' when P65_A(23 downto 20) = x"6" or (P65_A(22) = '0' and P65_A(15 downto 13) = "011" and SBW46 = '1') else '0';
SA1_IRAM_ACCESS <= '1' when P65_A(22) = '0' and (P65_A(15 downto 11) = x"0" & "0" or P65_A(15 downto 11) = x"3" & "0") else '0';	
SA1_MMIO_WRITE_ACCESS <= '1' when P65_A(22) = '0' and P65_A(15 downto 8) = x"22" else '0';	
SA1_MMIO_READ_ACCESS <= '1' when P65_A(22) = '0' and P65_A(15 downto 8) = x"23" else '0';	

SA1_ROM_SEL <= SA1_ROM_ACCESS and (P65_VPA or P65_VDA) and not DMA_SRC_ROM_SEL and not VBP_RUN;
SA1_BWRAM_SEL <= (SA1_BWRAM_ACCESS or SA1_BBF_ACCESS) and (P65_VPA or P65_VDA);
SA1_IRAM_SEL <= SA1_IRAM_ACCESS and (P65_VPA or P65_VDA);
SA1_INT_SEL <= (not P65_VPA and not P65_VDA) or (not SA1_ROM_ACCESS and not SA1_BWRAM_ACCESS and not SA1_BBF_ACCESS and not SA1_IRAM_ACCESS and (P65_VPA or P65_VDA));

SA1_BWRAM_WAIT <= ((DMA_SRC_BWRAM_SEL or DMA_DST_BWRAM_SEL) and DPRIO) or (DMA_RUN and DMAEN and CDEN and CDSEL);
SA1_IRAM_WAIT <= ((DMA_SRC_IRAM_SEL or DMA_DST_IRAM_SEL) and DPRIO) or CCDMA_DST_IRAM_SEL;

process( CLK, RST_N)
begin
	if RST_N = '0' then
		SA1_BWRAM_VALID <= '0';
	elsif rising_edge(CLK) then
		if EN = '1' then
			if SNES_BWRAM_SEL = '1' or SA1_BWRAM_SEL = '0' or SA1_BWRAM_WAIT = '1' then
				SA1_BWRAM_VALID <= '0';
			else
				SA1_BWRAM_VALID <= not SA1_BWRAM_VALID;
			end if;
		end if;
	end if;
end process;

SA1_ROM_EN <= SA1_ROM_SEL and not SNES_ROM_SEL;
SA1_BWRAM_EN <= SA1_BWRAM_SEL and not SA1_BWRAM_WAIT and not SNES_BWRAM_SEL and SA1_BWRAM_VALID;
SA1_IRAM_EN <= SA1_IRAM_SEL and not SA1_IRAM_WAIT and not SNES_IRAM_SEL;
SA1_INT_EN <= SA1_INT_SEL;
SA1_EN <= SA1_INT_EN or SA1_ROM_EN or SA1_BWRAM_EN or SA1_IRAM_EN;

process( INT_SNES_A, P65_A, SDA, VDA, SNES_ROM_SEL, SA1_ROM_SEL, DMA_SRC_ROM_SEL, VBP_RUN)
begin
	if SNES_ROM_SEL = '1' then
		INT_ROM_A <= INT_SNES_A;
	elsif VBP_RUN = '1' then
		INT_ROM_A <= VDA;
	elsif DMA_SRC_ROM_SEL = '1' then
		INT_ROM_A <= SDA;
--	elsif SA1_ROM_SEL = '1' then
--		INT_ROM_A <= P65_A;
	else
		INT_ROM_A <= P65_A;
	end if;
end process;


process( CLK, RST_N)
begin
	if RST_N = '0' then
		MDR <= (others => '1');
	elsif rising_edge(CLK) then
		if EN = '1' then
			if SA1_EN = '1' and (P65_VPA = '1' or P65_VDA = '1') then
				if P65_R_WN = '0' then
					MDR <= P65_DO;
				else
					MDR <= P65_DI;
				end if;
			end if;
		end if;
	end if;
end process;

process( P65_A, P65_VPB, ROM_DI, SA1_MMIO_READ_ACCESS, SA1_BWRAM_ACCESS, SA1_BBF_ACCESS, SA1_IRAM_ACCESS, SA1_ROM_ACCESS, IRAM_DO, BWRAM_DI, SBW46, 
			CRV, CIV, CNV, SA1_IRQ_FLAG, TM_IRQ_FLAG, DMA_IRQ_FLAG, SA1_NMI_FLAG, SMSG, MR, MOF, VDP, BBF, HCR, VCR, H_CNT, MDR)
begin
	if SA1_ROM_ACCESS = '1' then												--ROM 00h-3Fh/80h-BFh:8000h-FFFFh, C0h-FFh:0000h-FFFFh 
		if P65_A(3 downto 1) = "110" and P65_VPB = '0' then	--00FFEC/D, 00FFFC/D
			if P65_A(0) = '0' then
				P65_DI <= CRV(7 downto 0);
			else
				P65_DI <= CRV(15 downto 8);
			end if;
		elsif P65_A(3 downto 1) = "111" and P65_VPB = '0' then	--00FFEE/F, 00FFFE/F
			if P65_A(0) = '0' then
				P65_DI <= CIV(7 downto 0);
			else
				P65_DI <= CIV(15 downto 8);
			end if;
		elsif P65_A(3 downto 1) = "101" and P65_VPB = '0' then	--00FFEA/B, 00FFFA/B
			if P65_A(0) = '0' then
				P65_DI <= CNV(7 downto 0);
			else
				P65_DI <= CNV(15 downto 8);
			end if;
		else
			if P65_A(0) = '0' then
				P65_DI <= ROM_DI(7 downto 0);
			else
				P65_DI <= ROM_DI(15 downto 8);
			end if;
		end if;
	elsif SA1_MMIO_READ_ACCESS = '1' then	--SA1 Port Read
		case P65_A(7 downto 0) is
			when x"01" =>
				P65_DI <= SA1_IRQ_FLAG & TM_IRQ_FLAG & DMA_IRQ_FLAG & SA1_NMI_FLAG & SMSG;
			when x"02" =>
				P65_DI <= std_logic_vector(H_CNT(7 downto 0));
			when x"03" =>
				P65_DI <= "0000000" & HCR(8);
			when x"04" =>
				P65_DI <= VCR(7 downto 0);
			when x"05" =>
				P65_DI <= "0000000" & VCR(8);
			when x"06" =>
				P65_DI <= MR(7 downto 0);
			when x"07" =>
				P65_DI <= MR(15 downto 8);
			when x"08" =>
				P65_DI <= MR(23 downto 16);
			when x"09" =>
				P65_DI <= MR(31 downto 24);
			when x"0A" =>
				P65_DI <= MR(39 downto 32);
			when x"0B" =>
				P65_DI <= MOF & "0000000";	--OF
			when x"0C" =>
				P65_DI <= VDP(7 downto 0);
			when x"0D" =>
				P65_DI <= VDP(15 downto 8);
			when others =>
				P65_DI <= x"00";
		end case;
	elsif SA1_IRAM_ACCESS = '1' then											--I-RAM 00h-3Fh/80h-BFh:0000h-07FFh/3000h-37FFh
		P65_DI <= IRAM_DO;
	elsif SA1_BWRAM_ACCESS = '1' then
		P65_DI <= BWRAM_DI;
	elsif SA1_BBF_ACCESS = '1' then	
		if BBF = '0' then															--BW-RAM 60h-6Fh:0000h-FFFFh
			case P65_A(0) is
				when '0' => P65_DI <= "0000" & BWRAM_DI(3 downto 0);
				when others => P65_DI <= "0000" & BWRAM_DI(7 downto 4);
			end case;
		else
			case P65_A(1 downto 0) is
				when "00" => P65_DI <= "000000" & BWRAM_DI(1 downto 0);
				when "01" => P65_DI <= "000000" & BWRAM_DI(3 downto 2);
				when "10" => P65_DI <= "000000" & BWRAM_DI(5 downto 4);
				when others => P65_DI <= "000000" & BWRAM_DI(7 downto 6);
			end case;
		end if;
	else
		P65_DI <= MDR;
	end if;
end process;


--ROM
process( INT_ROM_A, SIV, SNV, NMISEL, IRQSEL, CMSG, CBMAP, DBMAP, EBMAP, FBMAP, CXB, DXB, EXB, FXB)
begin
	if INT_ROM_A(23 downto 21) = "000" and INT_ROM_A(15) = '1' then		--00-1f:8000-ffff 
		if CBMAP = '0' then
			ROM_MAP_A <= "0" & "000" & INT_ROM_A(20 downto 16) & INT_ROM_A(14 downto 0);
		else
			ROM_MAP_A <= "0" & CXB & INT_ROM_A(20 downto 16) & INT_ROM_A(14 downto 0);
		end if;
	elsif INT_ROM_A(23 downto 21) = "001" and INT_ROM_A(15) = '1' then	--20-3f:8000-ffff 
		if DBMAP = '0' then
			ROM_MAP_A <= "0" & "001" & INT_ROM_A(20 downto 16) & INT_ROM_A(14 downto 0);
		else
			ROM_MAP_A <= "0" & DXB & INT_ROM_A(20 downto 16) & INT_ROM_A(14 downto 0);
		end if;
	elsif INT_ROM_A(23 downto 21) = "100" and INT_ROM_A(15) = '1' then	--80-9f:8000-ffff 
		if EBMAP = '0' then
			ROM_MAP_A <= "0" & "010" & INT_ROM_A(20 downto 16) & INT_ROM_A(14 downto 0);
		else
			ROM_MAP_A <= "0" & EXB & INT_ROM_A(20 downto 16) & INT_ROM_A(14 downto 0);
		end if;
	elsif INT_ROM_A(23 downto 21) = "101" and INT_ROM_A(15) = '1' then	--a0-bf:8000-ffff 
		if FBMAP = '0' then
			ROM_MAP_A <= "0" & "011" & INT_ROM_A(20 downto 16) & INT_ROM_A(14 downto 0);
		else
			ROM_MAP_A <= "0" & FXB & INT_ROM_A(20 downto 16) & INT_ROM_A(14 downto 0);
		end if;
	elsif INT_ROM_A(23 downto 20) = "1100" then									--c0-cf:0000-ffff 
		ROM_MAP_A <= "0" & CXB & INT_ROM_A(19 downto 0);
	elsif INT_ROM_A(23 downto 20) = "1101" then									--d0-df:0000-ffff 
		ROM_MAP_A <= "0" & DXB & INT_ROM_A(19 downto 0);
	elsif INT_ROM_A(23 downto 20) = "1110" then									--e0-ef:0000-ffff 
		ROM_MAP_A <= "0" & EXB & INT_ROM_A(19 downto 0);
	elsif INT_ROM_A(23 downto 20) = "1111" then									--f0-ff:0000-ffff 
		ROM_MAP_A <= "0" & FXB & INT_ROM_A(19 downto 0);
	else
		ROM_MAP_A <= INT_ROM_A;
	end if;
end process;
ROM_A <= ROM_MAP_A(22 downto 0);
ROM_RD_N <= CLK_CE;


--BWRAM
process( SNES_A, BMAPS)
begin
	if SNES_A(22) = '1' then
		SNES_BWRAM_MAP_A <= SNES_A(17 downto 0);
	else
		SNES_BWRAM_MAP_A <= BMAPS(4 downto 0) & SNES_A(12 downto 0);			--SNES BW-RAM 8K 00h-3Fh/80h-BFh:6000h-7FFFh
	end if;
end process;

process( P65_A, P65_DO, SA1_BWRAM_ACCESS, SBW46, BMAP, BBF, BWRAM_DI)
variable INT_BWRAM_A : std_logic_vector(19 downto 0);
begin
	if P65_A(22) = '0' then																	--SA1 BW-RAM 8K 00h-3Fh/80h-BFh:6000h-7FFFh
		if SBW46 = '0' then
			INT_BWRAM_A := "00" & BMAP(4 downto 0) & P65_A(12 downto 0);		--map to 40h-4Fh:0000h-FFFFh
		else
			INT_BWRAM_A := BMAP & P65_A(12 downto 0);									--map to 60h-6Fh:0000h-FFFFh
		end if;
	else
		INT_BWRAM_A := P65_A(19 downto 0);
	end if;

	if SA1_BWRAM_ACCESS = '1' then	--map to 40h-4Fh:0000h-FFFFh
		SA1_BWRAM_MAP_A <= INT_BWRAM_A(17 downto 0);
		SA1_BWRAM_DAT <= P65_DO;
	elsif BBF = '0' then																		--BW-RAM 60h-6Fh:0000h-FFFFh
		SA1_BWRAM_MAP_A <= INT_BWRAM_A(18 downto 1);
		case INT_BWRAM_A(0) is
			when '0' =>	   SA1_BWRAM_DAT <= BWRAM_DI(7 downto 4) & P65_DO(3 downto 0);
			when others =>	SA1_BWRAM_DAT <= P65_DO(3 downto 0) & BWRAM_DI(3 downto 0);
		end case;
	else
		SA1_BWRAM_MAP_A <= INT_BWRAM_A(19 downto 2);
		case INT_BWRAM_A(1 downto 0) is
			when "00" =>	SA1_BWRAM_DAT <= BWRAM_DI(7 downto 2) & P65_DO(1 downto 0);
			when "01" =>	SA1_BWRAM_DAT <= BWRAM_DI(7 downto 4) & P65_DO(1 downto 0) & BWRAM_DI(1 downto 0);
			when "10" =>	SA1_BWRAM_DAT <= BWRAM_DI(7 downto 6) & P65_DO(1 downto 0) & BWRAM_DI(3 downto 0);
			when others =>	SA1_BWRAM_DAT <=                        P65_DO(1 downto 0) & BWRAM_DI(5 downto 0);
		end case;
	end if;
end process;

process( BWPA)
begin
	case BWPA(3 downto 0) is
		when "0000" =>	BWRAM_WP_MASK <= "0000000000";
		when "0001" =>	BWRAM_WP_MASK <= "0000000001";
		when "0010" =>	BWRAM_WP_MASK <= "0000000011";
		when "0011" =>	BWRAM_WP_MASK <= "0000000111";
		when "0100" =>	BWRAM_WP_MASK <= "0000001111";
		when "0101" =>	BWRAM_WP_MASK <= "0000011111";
		when "0110" =>	BWRAM_WP_MASK <= "0000111111";
		when "0111" =>	BWRAM_WP_MASK <= "0001111111";
		when "1000" =>	BWRAM_WP_MASK <= "0011111111";
		when "1001" =>	BWRAM_WP_MASK <= "0111111111";
		when others =>	BWRAM_WP_MASK <= "1111111111";
	end case;
end process;

SA1_BWRAM_WE <= SBWE(7) or CBWE(7) when (SA1_BWRAM_MAP_A(17 downto 8) and not BWRAM_WP_MASK) = "0000000000" and SA1_BWRAM_ACCESS = '1' else '1';
SNES_BWRAM_WE <= SBWE(7) or CBWE(7) when (SNES_BWRAM_MAP_A(17 downto 8) and not BWRAM_WP_MASK) = "0000000000" and SNES_BWRAM_ACCESS = '1' else '1';
BWRAM_A <= CC1_BWRAM_RD_ADDR					                        when CCDMA_SRC_BWRAM_SEL = '1' else 
			  SNES_BWRAM_MAP_A					                        when SNES_BWRAM_SEL = '1' else 
			  SDA(17 downto 0)					                        when DMA_SRC_BWRAM_SEL = '1' and DMA_BWRAM_WAIT = '0' else 
			  DDA(17 downto 0)					                        when DMA_DST_BWRAM_SEL = '1' and DMA_BWRAM_WAIT = '0' else 
			  SA1_BWRAM_MAP_A						                        when SA1_BWRAM_SEL = '1' else 
			  (others => '0');
BWRAM_DO <= SNES_DI								                        when SNES_BWRAM_SEL = '1' else 
				INT_DMA_DAT							                        when DMA_DST_BWRAM_SEL = '1' and DMA_BWRAM_WAIT = '0' else 
				SA1_BWRAM_DAT						                        when SA1_BWRAM_SEL = '1' else 
				x"00";      
BWRAM_WE_N <= '1'									                        when ENABLE = '0' else 
				  '1'									                        when CCDMA_SRC_BWRAM_SEL = '1' else 
				  not(not SNES_WR_N and SNES_BWRAM_WE and SYSCLKF_CE) when SNES_BWRAM_SEL = '1' else 
				  '1'									                        when DMA_SRC_BWRAM_SEL = '1' and DMA_BWRAM_WAIT = '0' else 
				  not DMA_EN						                        when DMA_DST_BWRAM_SEL = '1' and DMA_BWRAM_WAIT = '0' else 
				  not (P65_WR and SA1_BWRAM_WE)						      when SA1_BWRAM_SEL = '1' and SA1_BWRAM_VALID = '1' else --
				  '1';
BWRAM_OE_N <= '0'									                        when ENABLE = '0' else 
				  '0'									                        when CCDMA_SRC_BWRAM_SEL = '1' else 
				  SNES_RD_N							                        when SNES_BWRAM_SEL = '1' else 
				  '0'									                        when DMA_SRC_BWRAM_SEL = '1' and DMA_BWRAM_WAIT = '0' else 
				  DMA_EN								                        when DMA_DST_BWRAM_SEL = '1' and DMA_BWRAM_WAIT = '0' else 
				  P65_WR								                        when SA1_BWRAM_SEL = '1' and SA1_BWRAM_VALID = '1' else 
				  '1';

--IRAM
SA1_IRAM_WE <= CIWP(to_integer(unsigned(P65_A(10 downto 8))));
SNES_IRAM_WE <= SIWP(to_integer(unsigned(SNES_A(10 downto 8))));
IRAM_A <= SNES_A(10 downto 0)					               when SNES_IRAM_SEL = '1' and SNES_IRAM_ACCESS = '1' else 
			 CC1_IRAM_RD_ADDR						               when SNES_IRAM_SEL = '1' and SNES_CCDMA_IRAM_ACCESS = '1' else 
			 SDA(10 downto 0)						               when DMA_SRC_IRAM_SEL = '1' and DMA_IRAM_WAIT = '0' else 
			 DDA(10 downto 0)						               when DMA_DST_IRAM_SEL = '1' and DMA_IRAM_WAIT = '0' else 
			 CC12_IRAM_WR_ADDR					               when CCDMA_DST_IRAM_SEL = '1' else 
			 P65_A(10 downto 0)					               when SA1_IRAM_SEL = '1' else 
			 (others => '0');
IRAM_DI <= SNES_DI								               when SNES_IRAM_SEL = '1' and SNES_IRAM_ACCESS = '1' else 
			  INT_DMA_DAT							               when DMA_DST_IRAM_SEL = '1' and DMA_IRAM_WAIT = '0' else 
			  CC12_IRAM_WR_DAT					               when CCDMA_DST_IRAM_SEL = '1' else 
			  P65_DO									               when SA1_IRAM_SEL = '1' else 
			  x"00";
IRAM_WE <= '0'										               when ENABLE = '0' else 
			  not SNES_WR_N and SNES_IRAM_WE and SYSCLKF_CE	when SNES_IRAM_SEL = '1' and SNES_IRAM_ACCESS = '1' else 
			  '0'										               when SNES_IRAM_SEL = '1' and SNES_CCDMA_IRAM_ACCESS = '1' else 
			  '0'										               when DMA_SRC_IRAM_SEL = '1' and DMA_IRAM_WAIT = '0' else 
			  DMA_EN									               when DMA_DST_IRAM_SEL = '1' and DMA_IRAM_WAIT = '0' else 
			  CCDMA_IRAM_EN						               when CCDMA_DST_IRAM_SEL = '1' else 
			  P65_WR and SA1_IRAM_WE			               when SA1_IRAM_SEL = '1' else 
			  '0';
			  
IRAM: entity work.spram generic map(11, 8)
port map (
	clock    => CLK,
	wren     => IRAM_WE,
	data     => IRAM_DI,
	q    		=> IRAM_DO,
	address  => IRAM_A
);  

-- DMA
DMA_SRC_ROM_SEL <= DMA_RUN and DMAEN and not CDEN and not DMASD(0) and not DMASD(1);
DMA_SRC_BWRAM_SEL <= DMA_RUN and DMAEN and not CDEN and DMASD(0) and not DMASD(1);
DMA_SRC_IRAM_SEL <= DMA_RUN and DMAEN and not CDEN and not DMASD(0) and DMASD(1);

DMA_DST_BWRAM_SEL <= DMA_RUN and DMAEN and not CDEN and DMADD;
DMA_DST_IRAM_SEL <= DMA_RUN and DMAEN and not CDEN and not DMADD;

DMA_BWRAM_WAIT <= SA1_BWRAM_SEL and not DPRIO and not CDEN;
DMA_IRAM_WAIT <= SA1_IRAM_SEL and not DPRIO and not CDEN;

CCDMA_SRC_BWRAM_SEL <= DMA_RUN and DMAEN and CDEN and CDSEL and not CCDMA_RW;
CCDMA_DST_IRAM_SEL <= DMA_RUN and DMAEN and CDEN and CCDMA_RW;

process( CLK, RST_N)
begin
	if RST_N = '0' then
		NDMA_EN <= '0';
	elsif rising_edge(CLK) then
		if EN = '1' then
			if DMA_RUN = '0' or 
				(DMA_SRC_ROM_SEL = '1' and SNES_ROM_SEL = '1') or
				((DMA_SRC_BWRAM_SEL = '1' or DMA_DST_BWRAM_SEL = '1') and (SNES_BWRAM_SEL = '1' or DMA_BWRAM_WAIT = '1')) or
				((DMA_SRC_IRAM_SEL = '1' or DMA_DST_IRAM_SEL = '1') and (SNES_IRAM_SEL = '1' or DMA_IRAM_WAIT = '1')) then
				NDMA_EN <= '0';
			elsif DMA_SRC_ROM_SEL = '1' and DMA_DST_IRAM_SEL = '1' then
				NDMA_EN <= '1';
			else
				NDMA_EN <= not NDMA_EN;
			end if;
		end if;
	end if;
end process;

process( CLK, RST_N)
begin
	if RST_N = '0' then
		CCDMA_BWRAM_VALID <= '0';
	elsif rising_edge(CLK) then
		if EN = '1' then
			if (CCDMA_SRC_BWRAM_SEL = '0' and CC1DMA_EXEC = '1') or DMA_RUN = '0' then
				CCDMA_BWRAM_VALID <= '0';
			else
				CCDMA_BWRAM_VALID <= not CCDMA_BWRAM_VALID;
			end if;
		end if;
	end if;
end process;

DMA_SRC_ROM_EN <= DMA_SRC_ROM_SEL and not SNES_ROM_SEL and NDMA_EN;
DMA_SRC_BWRAM_EN <= DMA_SRC_BWRAM_SEL and not DMA_BWRAM_WAIT and not SNES_BWRAM_SEL and NDMA_EN;
DMA_SRC_IRAM_EN <= DMA_SRC_IRAM_SEL and not DMA_IRAM_WAIT and not SNES_IRAM_SEL and NDMA_EN;
DMA_DST_BWRAM_EN <= DMA_DST_BWRAM_SEL and not DMA_BWRAM_WAIT and not SNES_BWRAM_SEL and NDMA_EN;
DMA_DST_IRAM_EN <= DMA_DST_IRAM_SEL and not DMA_IRAM_WAIT and not SNES_IRAM_SEL and NDMA_EN;

CCDMA_BWRAM_EN <= CCDMA_SRC_BWRAM_SEL and CCDMA_BWRAM_VALID;
CCDMA_IRAM_EN <= CCDMA_DST_IRAM_SEL and not SNES_IRAM_SEL;

DMA_EN <= (DMA_SRC_ROM_EN and (DMA_DST_BWRAM_EN or DMA_DST_IRAM_EN)) or 
			 (DMA_SRC_BWRAM_EN and DMA_DST_IRAM_EN) or 
			 (DMA_SRC_IRAM_EN and DMA_DST_BWRAM_EN) or 
			 CCDMA_BWRAM_EN or CCDMA_IRAM_EN;

process( RST_N, CLK )
	variable NDMA_SEL : std_logic;
	variable CC1DMA_SEL : std_logic;
	variable CC2DMA_SEL : std_logic;
	variable CC1_SNES_BWRAM_MASK : std_logic_vector(5 downto 0);
begin
	if RST_N = '0' then
		DMASD <= (others => '0');
		DMADD <= '0';
		CDSEL <= '0';
		CDEN <= '0';
		DPRIO <= '0';
		DMAEN <= '0';
		CDMACB <= (others => '0');
		CDMASIZE <= (others => '0');
--		CDMAEND <= '0';
		SDA <= (others => '0');
		DDA <= (others => '0');
		DTC <= (others => '0');
		BRF <= (others => (others => '0'));
		DMA_RUN <= '0';
		DMA_IRQ_FLAG <= '0';
		CCDMA_RW <= '0';
		CC_BPP <= (others => '0');
		CC_TILE_Y <= (others => '0');
		CC_TILE_N <= (others => '0');
		CC1DMA_EXEC <= '0';
		CDMA_IRQ_FLAG <= '0';
	elsif rising_edge(CLK) then
		NDMA_SEL := DMAEN and not CDEN and ((not DMASD(0) and not DMASD(1)) or (DMASD(0) xor DMADD));
		CC1DMA_SEL := DMAEN and CDEN and CDSEL;
		CC2DMA_SEL := DMAEN and CDEN and not CDSEL;
			
		if ENABLE = '1' then
			case CDMACB is
				when "00" =>   CC1_SNES_BWRAM_MASK :=        SNES_A(5 downto 0);
				when "01" =>   CC1_SNES_BWRAM_MASK := "0"  & SNES_A(4 downto 0);
				when others => CC1_SNES_BWRAM_MASK := "00" & SNES_A(3 downto 0);
			end case;
			if SNES_MMIO_WRITE = '1' then	--SNES Port Write
				case SNES_A(7 downto 0) is
					when x"02" =>							--SIC (CDMA IRQ Ack)
						if SNES_DI(5) = '1' then
							CDMA_IRQ_FLAG <= '0';
						end if;
					when x"31" =>							--CDMA
						CDMACB <= SNES_DI(1 downto 0);
						CDMASIZE <= SNES_DI(4 downto 2);
--						CDMAEND <= SNES_DI(7);
						if SNES_DI(7) = '1' then
							CC1DMA_EXEC <= '0';
							CCDMA_RW <= '0';
							CC_BPP <= (others => '0');
							CC_TILE_Y <= (others => '0');
							CC_TILE_N <= (others => '0');
						end if;
					when x"32" =>							--SDA
						SDA(7 downto 0) <= SNES_DI;
					when x"33" =>
						SDA(15 downto 8) <= SNES_DI;
					when x"34" =>
						SDA(23 downto 16) <= SNES_DI;
					when x"35" =>							--DDA
						DDA(7 downto 0) <= SNES_DI;
					when x"36" =>
						DDA(15 downto 8) <= SNES_DI;
						DMA_RUN <= (not DMADD and NDMA_SEL) or CC1DMA_SEL;
						CCDMA_RW <= '0';
						CC_BPP <= (others => '0');
						CC_TILE_Y <= (others => '0');
						CC_TILE_N <= (others => '0');
						CC1DMA_EXEC <= CC1DMA_SEL;
					when x"37" =>
						DDA(17 downto 16) <= SNES_DI(1 downto 0);
					when others => null;
				end case;
			elsif SNES_CCDMA_IRAM_ACCESS = '1' and CC1_SNES_BWRAM_MASK = "000000" then
				DMA_RUN <= CC1DMA_SEL;
			end if;
		end if;
			
		if EN = '1' then
			if SA1_MMIO_WRITE = '1' then
				case P65_A(7 downto 0) is
					when x"0B" =>							--CIC (DMA IRQ Ack)
						if P65_DO(5) = '1' then
							DMA_IRQ_FLAG <= '0';
						end if;
					when x"30" =>							--DCNT
						DMASD <= P65_DO(1 downto 0);
						DMADD <= P65_DO(2);
						CDSEL <= P65_DO(4);
						CDEN <= P65_DO(5);
						DPRIO <= P65_DO(6);
						DMAEN <= P65_DO(7);
						if P65_DO(7) = '0' then
							CCDMA_RW <= '0';
							CC_BPP <= (others => '0');
							CC_TILE_Y <= (others => '0');
							CC_TILE_N <= (others => '0');
							DMA_RUN <= '0';
						end if;
					when x"31" =>							--CDMA
						CDMACB <= P65_DO(1 downto 0);
						CDMASIZE <= P65_DO(4 downto 2);
--						CDMAEND <= P65_DO(7);
						if P65_DO(7) = '1' then
							CC1DMA_EXEC <= '0';
							CCDMA_RW <= '0';
							CC_BPP <= (others => '0');
							CC_TILE_Y <= (others => '0');
							CC_TILE_N <= (others => '0');
						end if;
					when x"32" =>							--SDA
						SDA(7 downto 0) <= P65_DO;
					when x"33" =>
						SDA(15 downto 8) <= P65_DO;
					when x"34" =>
						SDA(23 downto 16) <= P65_DO;
					when x"35" =>							--DDA
						DDA(7 downto 0) <= P65_DO;
					when x"36" =>
						DDA(15 downto 8) <= P65_DO;
						DMA_RUN <= not DMADD and NDMA_SEL;
					when x"37" =>
						DDA(17 downto 16) <= P65_DO(1 downto 0);
						DMA_RUN <= DMADD and NDMA_SEL;
					when x"38" =>							--DTC
						DTC(7 downto 0) <= P65_DO;
					when x"39" =>
						DTC(15 downto 8) <= P65_DO;
					when x"40" =>							--BRF
						BRF(0) <= P65_DO;
					when x"41" =>
						BRF(1) <= P65_DO;
					when x"42" =>
						BRF(2) <= P65_DO;
					when x"43" =>
						BRF(3) <= P65_DO;
					when x"44" =>
						BRF(4) <= P65_DO;
					when x"45" =>
						BRF(5) <= P65_DO;
					when x"46" =>
						BRF(6) <= P65_DO;
					when x"47" =>
						BRF(7) <= P65_DO;
						CCDMA_RW <= '1';
						DMA_RUN <= CC2DMA_SEL;
					when x"48" =>
						BRF(8) <= P65_DO;
					when x"49" =>
						BRF(9) <= P65_DO;
					when x"4A" =>
						BRF(10) <= P65_DO;
					when x"4B" =>
						BRF(11) <= P65_DO;
					when x"4C" =>
						BRF(12) <= P65_DO;
					when x"4D" =>
						BRF(13) <= P65_DO;
					when x"4E" =>
						BRF(14) <= P65_DO;
					when x"4F" =>
						BRF(15) <= P65_DO;
						CCDMA_RW <= '1';
						DMA_RUN <= CC2DMA_SEL;
					when others => null;
				end case;
			end if;
				
			if DMA_RUN = '1' and DMA_EN = '1' then
				if NDMA_SEL = '1' then-- and NDMA_EN = '1'
					SDA <= std_logic_vector(unsigned(SDA) + 1);
					DDA <= std_logic_vector(unsigned(DDA) + 1);
					DTC <= std_logic_vector(unsigned(DTC) - 1);
					if DTC = x"0001" then
						DMA_RUN <= '0';
						DMA_IRQ_FLAG <= '1';
					end if;
				elsif CC1DMA_SEL = '1' then
					if CCDMA_RW = '0' then
						case CDMACB is
							when "00" =>
								BRF(to_integer(CC_TILE_Y(0)&CC_BPP)) <= BWRAM_DI;
							when "01" =>
								BRF(to_integer(CC_TILE_Y(0)&CC_BPP(1 downto 0)&"0")) <= "0000" & BWRAM_DI(3 downto 0);
								BRF(to_integer(CC_TILE_Y(0)&CC_BPP(1 downto 0)&"1")) <= "0000" & BWRAM_DI(7 downto 4);
							when "10" =>
								BRF(to_integer(CC_TILE_Y(0)&CC_BPP(0 downto 0)&"00")) <= "000000" & BWRAM_DI(1 downto 0);
								BRF(to_integer(CC_TILE_Y(0)&CC_BPP(0 downto 0)&"01")) <= "000000" & BWRAM_DI(3 downto 2);
								BRF(to_integer(CC_TILE_Y(0)&CC_BPP(0 downto 0)&"10")) <= "000000" & BWRAM_DI(5 downto 4);
								BRF(to_integer(CC_TILE_Y(0)&CC_BPP(0 downto 0)&"11")) <= "000000" & BWRAM_DI(7 downto 6);
							when others => null;
						end case;

						CC_BPP <= CC_BPP + 1;
						if CC_BPP = CC_BPP_TAB(to_integer(unsigned(CDMACB))) then
							CC_BPP <= (others => '0');
							CCDMA_RW <= '1';
						end if;
					else
						CC_BPP <= CC_BPP + 1;
						if CC_BPP = CC_BPP_TAB(to_integer(unsigned(CDMACB))) then
							CC_BPP <= (others => '0');
							CCDMA_RW <= '0';
							CC_TILE_Y <= CC_TILE_Y + 1;
							if CC_TILE_Y = 7 then
								CC_TILE_N <= CC_TILE_N + 1;
								if CC_TILE_N = 0 then
									CDMA_IRQ_FLAG <= '1';
								end if;
								DMA_RUN <= '0';
							end if;
						end if;
					end if;
				elsif CC2DMA_SEL = '1' then
					CC_BPP <= CC_BPP + 1;
					if CC_BPP = CC_BPP_TAB(to_integer(unsigned(CDMACB))) then
						CC_BPP <= (others => '0');
						CC_TILE_Y <= CC_TILE_Y + 1;
						if CC_TILE_Y = 7 then
							CC_TILE_N <= CC_TILE_N + 1;
						end if;
						DMA_RUN <= '0';
					end if;
				end if;
			end if;
		end if;
	end if;
end process;

process( CDMASIZE, CDMACB, CC_BPP, CC_TILE_Y, CC_TILE_N, SDA, DDA, SNES_A)
	variable TEMP1, TEMP2 : unsigned(17 downto 0);
	variable TEMP3, TEMP4 : unsigned(10 downto 0);
begin
	case CDMASIZE is
		when "000" =>  TEMP1 := CC_TILE_N(14 downto 0) & CC_TILE_Y;
		when "001" =>  TEMP1 := CC_TILE_N(14 downto 1) & CC_TILE_Y & CC_TILE_N(0 downto 0);
		when "010" =>  TEMP1 := CC_TILE_N(14 downto 2) & CC_TILE_Y & CC_TILE_N(1 downto 0);
		when "011" =>  TEMP1 := CC_TILE_N(14 downto 3) & CC_TILE_Y & CC_TILE_N(2 downto 0);
		when "100" =>  TEMP1 := CC_TILE_N(14 downto 4) & CC_TILE_Y & CC_TILE_N(3 downto 0);
		when others => TEMP1 := CC_TILE_N(14 downto 5) & CC_TILE_Y & CC_TILE_N(4 downto 0);
	end case;
	case CDMACB is
		when "00" =>   TEMP2 := TEMP1(14 downto 0) & CC_BPP(2 downto 0);
		when "01" =>   TEMP2 := TEMP1(15 downto 0) & CC_BPP(1 downto 0);
		when others => TEMP2 := TEMP1(16 downto 0) & CC_BPP(0 downto 0);
	end case;
	CC1_BWRAM_RD_ADDR <= std_logic_vector( unsigned(SDA(17 downto 0)) + TEMP2);
	
	case CDMACB is
		when "00" =>   TEMP3 := "0000"   & CC_TILE_N(0) & CC_BPP(2 downto 1) & CC_TILE_Y & CC_BPP(0);
		when "01" =>   TEMP3 := "00000"  & CC_TILE_N(0) & CC_BPP(1 downto 1) & CC_TILE_Y & CC_BPP(0);
		when others => TEMP3 := "000000" & CC_TILE_N(0) &                      CC_TILE_Y & CC_BPP(0);
	end case;
	CC12_IRAM_WR_ADDR <= std_logic_vector( unsigned(DDA(10 downto 0)) + TEMP3 );
	
	case CDMACB is
		when "00" =>   TEMP4 := "0000"   & unsigned(SNES_A(6 downto 0));
		when "01" =>   TEMP4 := "00000"  & unsigned(SNES_A(5 downto 0));
		when others => TEMP4 := "000000" & unsigned(SNES_A(4 downto 0));
	end case;
	CC1_IRAM_RD_ADDR <= std_logic_vector( unsigned(DDA(10 downto 0)) + TEMP4 );
end process;

CC12_IRAM_WR_DAT <= BRF(to_integer(CC_TILE_Y(0 downto 0)&"000"))(to_integer(CC_BPP)) & 
						  BRF(to_integer(CC_TILE_Y(0 downto 0)&"001"))(to_integer(CC_BPP)) & 
						  BRF(to_integer(CC_TILE_Y(0 downto 0)&"010"))(to_integer(CC_BPP)) & 
						  BRF(to_integer(CC_TILE_Y(0 downto 0)&"011"))(to_integer(CC_BPP)) & 
						  BRF(to_integer(CC_TILE_Y(0 downto 0)&"100"))(to_integer(CC_BPP)) & 
						  BRF(to_integer(CC_TILE_Y(0 downto 0)&"101"))(to_integer(CC_BPP)) & 
						  BRF(to_integer(CC_TILE_Y(0 downto 0)&"110"))(to_integer(CC_BPP)) & 
						  BRF(to_integer(CC_TILE_Y(0 downto 0)&"111"))(to_integer(CC_BPP));

						 

process( SDA, ROM_DI)
begin
	if SDA(0) = '0' then
		DMA_ROM_DAT <= ROM_DI(7 downto 0);
	else
		DMA_ROM_DAT <= ROM_DI(15 downto 8);
	end if;
end process;

INT_DMA_DAT <= DMA_ROM_DAT when DMA_SRC_ROM_SEL = '1' else
					BWRAM_DI when DMA_SRC_BWRAM_SEL = '1' else
					IRAM_DO when DMA_SRC_IRAM_SEL = '1' else
					MDR;
					
				
--VBP
VBP_EN <= '1' when VBP_RUN = '1' and SNES_ROM_SEL = '0' else '0';

process( RST_N, CLK )
	variable NEW_VBIT : unsigned(4 downto 0);
begin
	if RST_N = '0' then
		VB <= (others => '0');
		HL <= '0';
		VDA <= (others => '0');
		VBIT <= (others => '0');
		VBP_BUF <= (others => '0');
		VBP_RUN <= '0';
		VBP_PRELOAD <= '0';
	elsif rising_edge(CLK) then
		if EN = '1' then
			if VBP_RUN = '0' then
				if SA1_MMIO_WRITE = '1' then
					case P65_A(7 downto 0) is
						when x"58" =>							--VBD
							VB <= P65_DO(3 downto 0);
							HL <= P65_DO(7);
							if P65_DO(7) = '0' then
								NEW_VBIT := "0"&VBIT + unsigned(not (P65_DO(0) or P65_DO(1) or P65_DO(2) or P65_DO(3))&P65_DO(3 downto 0));
								VBIT <= NEW_VBIT(3 downto 0);
								if NEW_VBIT(4) = '1' then
									VDA <= std_logic_vector( unsigned(VDA) + 2 );
									VBP_BUF <= x"0000" & VBP_BUF(31 downto 16);
									VBP_RUN <= '1';
								end if;
							end if;
						when x"59" =>							--VDA
							VDA(7 downto 0) <= P65_DO;
						when x"5A" =>
							VDA(15 downto 8) <= P65_DO;
						when x"5B" =>
							VDA(23 downto 16) <= P65_DO;
							VBIT <= (others => '0');
							VBP_RUN <= '1';
							VBP_PRELOAD <= '1';
						when others => null;
					end case;
				elsif SA1_MMIO_READ = '1' then
					case P65_A(7 downto 0) is
						when x"0D" =>							--VDP Msb
							if HL = '1' then
								NEW_VBIT := "0"&VBIT + unsigned(not (VB(0) or VB(1) or VB(2) or VB(3))&VB(3 downto 0));
								VBIT <= NEW_VBIT(3 downto 0);
								if NEW_VBIT(4) = '1' then
									VDA <= std_logic_vector( unsigned(VDA) + 2 );
									VBP_BUF <= x"0000" & VBP_BUF(31 downto 16);
									VBP_RUN <= '1';
								end if;
							end if;
						when others => null;
					end case;
				end if;
			elsif VBP_EN = '1' then
				if VBP_PRELOAD = '1' then
					VBP_BUF <= x"0000" & ROM_DI;
					VDA <= std_logic_vector( unsigned(VDA) + 2 );
					VBP_PRELOAD <= '0';
				else
					VBP_BUF(31 downto 16) <= ROM_DI;
					VBP_RUN <= '0';
				end if;
			end if;
		end if;
	end if;
end process;

VDP <= std_logic_vector( resize(unsigned(VBP_BUF) srl to_integer(VBIT), VDP'length) );

	
--MMIO
SNES_MMIO_WRITE <= SNES_MMIO_WRITE_ACCESS and not SNES_WR_N and SYSCLKF_CE;
SA1_MMIO_WRITE <= SA1_MMIO_WRITE_ACCESS and P65_WR;
SA1_MMIO_READ <= SA1_MMIO_READ_ACCESS and P65_RD;

process( RST_N, CLK )
variable SUM : signed(40 downto 0);
begin
	if RST_N = '0' then
		SMSG <= (others => '0');
		SA1RST <= '1';
		SA1WAIT <= '0';
		CRV <= (others => '0');
		CNV <= (others => '0');
		CIV <= (others => '0');
		CMSG <= (others => '0');
		NMISEL <= '0';
		IRQSEL <= '0';
		HVEN <= (others => '0');
		TMMODE <= '0';
		HCNT <= (others => '0');
		VCNT <= (others => '0');
		BMAP <= (others => '0');
		SBW46 <= '0';
		SNV <= (others => '0');
		SIV <= (others => '0');
		CXB <= "000";
		DXB <= "001";
		EXB <= "010";
		FXB <= "011";
		CBMAP <= '0';
		DBMAP <= '0';
		EBMAP <= '0';
		FBMAP <= '0';
		BMAPS <= (others => '0');
		BBF <= '0';
		CIWP <= (others => '0');
		SIWP <= (others => '0');
		SBWE <= (others => '0');
		CBWE <= (others => '0');
		BWPA <= (others => '1');
		AM <= (others => '0');
		MOF <= '0';
		MA <= (others => '0');
		MB <= (others => '0');
		MR <= (others => '0');
		HCR <= (others => '0');
		VCR <= (others => '0');
		TM_IRQ_EN <= '0';
		DMA_IRQ_EN <= '0';
		SA1_IRQ_EN <= '0';
		SA1_NMI_EN <= '0';
		SNES_IRQ_EN <= '0';
		CDMA_IRQ_EN <= '0';
		
		TM_IRQ_FLAG <= '0';
		SA1_IRQ_FLAG <= '0';
		SA1_NMI_FLAG <= '0';
		SNES_IRQ_FLAG <= '0';
		
		MATH_REQ <= '0';
		MATH_CLK_CNT <= (others => '0');

	elsif rising_edge(CLK) then
		if ENABLE = '1' then
			if SNES_MMIO_WRITE = '1' then			--SNES Port Write
				case SNES_A(7 downto 0) is
					when x"00" =>						--CCNT
						SMSG <= SNES_DI(3 downto 0);
						SA1RST <= SNES_DI(5);
						SA1WAIT <= SNES_DI(6);
						if SNES_DI(7) = '1' then
							SA1_IRQ_FLAG <= '1';
						end if;
						if SNES_DI(4) = '1' then
							SA1_NMI_FLAG <= '1';
						end if;
						if SNES_DI(5) = '1' then
							CIWP <= (others => '0');
						end if;
					when x"01" =>						--SIE
						CDMA_IRQ_EN <= SNES_DI(5);
						SNES_IRQ_EN <= SNES_DI(7);
					when x"02" =>						--SIC
						if SNES_DI(7) = '1' then
							SNES_IRQ_FLAG <= '0';
						end if;
					when x"03" =>						--CRV
						CRV(7 downto 0) <= SNES_DI;
					when x"04" =>
						CRV(15 downto 8) <= SNES_DI;
					when x"05" =>						--CNV
						CNV(7 downto 0) <= SNES_DI;
					when x"06" =>
						CNV(15 downto 8) <= SNES_DI;
					when x"07" =>						--CIV
						CIV(7 downto 0) <= SNES_DI;
					when x"08" =>
						CIV(15 downto 8) <= SNES_DI;
					when x"20" =>						--CXB
						CXB <= SNES_DI(2 downto 0);
						CBMAP <= SNES_DI(7);
					when x"21" =>						--DXB
						DXB <= SNES_DI(2 downto 0);
						DBMAP <= SNES_DI(7);
					when x"22" =>						--EXB
						EXB <= SNES_DI(2 downto 0);
						EBMAP <= SNES_DI(7);
					when x"23" =>						--FXB
						FXB <= SNES_DI(2 downto 0);
						FBMAP <= SNES_DI(7);
					when x"24" =>						--BMAPS
						BMAPS <= SNES_DI;
					when x"26" =>						--SBWE
						SBWE <= SNES_DI;
					when x"28" =>						--BWPA
						BWPA <= SNES_DI;
					when x"29" =>						--SIWP
						SIWP <= SNES_DI;
						
					--it's contrary to the documentation, but some SMW hacks write inerrupt vectors here!
					when x"0C" =>						--SNV
						SNV(7 downto 0) <= SNES_DI;
					when x"0D" =>
						SNV(15 downto 8) <= SNES_DI;
					when x"0E" =>						--SIV
						SIV(7 downto 0) <= SNES_DI;
					when x"0F" =>
						SIV(15 downto 8) <= SNES_DI;
					when others => null;
				end case;
			end if;
		end if;
		
		if EN = '1' then
			if TM_IRQ_FLAG = '0' then
				if (H_CNT = unsigned(HCNT) and V_CNT = unsigned(VCNT) and HVEN = "11") or
					(H_CNT = unsigned(HCNT) and HVEN = "01") or
					(V_CNT = unsigned(VCNT) and HVEN = "10") then
					TM_IRQ_FLAG <= '1';
				end if;
			end if;
			
			if MATH_REQ = '1' then
				MATH_CLK_CNT <= MATH_CLK_CNT + 1;
				if AM(1) = '0' and MATH_CLK_CNT = 5-1 then
					if AM(0) = '0' then
						MR(39 downto 0) <= x"00" & MULR;
						MB <= (others => '0');
					else
						if MB = x"0000" then 
							MR(39 downto 0) <= (others => '0');
						else
							MR(39 downto 0) <= x"00" & DIVR & DIVQ;
						end if;
						MA <= (others => '0');
						MB <= (others => '0');
					end if;
					MATH_CLK_CNT <= (others => '0');
					MATH_REQ <= '0';
				elsif AM(1) = '1' and MATH_CLK_CNT = 6-1 then
					SUM := resize(signed(MR), SUM'length) + resize(signed(MULR), SUM'length);
					MR <= std_logic_vector(SUM(39 downto 0));
					MOF <= SUM(40);
					MB <= (others => '0');
					MATH_CLK_CNT <= (others => '0');
					MATH_REQ <= '0';
				end if;
			end if;
				
			if SA1_MMIO_WRITE = '1' then			--SA1 Port Write
				case P65_A(7 downto 0) is
					when x"09" =>						--SCNT
						CMSG <= P65_DO(3 downto 0);
						NMISEL <= P65_DO(4);
						IRQSEL <= P65_DO(6);
						if P65_DO(7) = '1' then
							SNES_IRQ_FLAG <= '1';
						end if;
					when x"0A" =>						--CIE
						SA1_NMI_EN <= P65_DO(4);
						DMA_IRQ_EN <= P65_DO(5);
						TM_IRQ_EN <= P65_DO(6);
						SA1_IRQ_EN <= P65_DO(7);
					when x"0B" =>						--CIC
						if P65_DO(4) = '1' then
							SA1_NMI_FLAG <= '0';
						end if;
						if P65_DO(6) = '1' then
							TM_IRQ_FLAG <= '0';
						end if;
						if P65_DO(7) = '1' then
							SA1_IRQ_FLAG <= '0';
						end if;
					when x"0C" =>						--SNV
						SNV(7 downto 0) <= P65_DO;
					when x"0D" =>
						SNV(15 downto 8) <= P65_DO;
					when x"0E" =>						--SIV
						SIV(7 downto 0) <= P65_DO;
					when x"0F" =>
						SIV(15 downto 8) <= P65_DO;
					when x"10" =>						--TMC
						HVEN <= P65_DO(1 downto 0);
						TMMODE <= P65_DO(7);
					when x"12" =>						--HCNT
						HCNT(7 downto 0) <= P65_DO;
					when x"13" =>
						HCNT(8) <= P65_DO(0);
					when x"14" =>						--VCNT
						VCNT(7 downto 0) <= P65_DO;
					when x"15" =>
						VCNT(8) <= P65_DO(0);
					when x"25" =>						--BMAP
						BMAP <= P65_DO(6 downto 0) ;
						SBW46 <= P65_DO(7);
					when x"27" =>						--CBWE
						CBWE <= P65_DO;
					when x"2A" =>						--CIWP
						CIWP <= P65_DO;
					when x"3F" =>						--BBF
						BBF <= P65_DO(7);
					when x"50" =>						--MCNT
						AM <= P65_DO(1 downto 0);
						if P65_DO(1) = '1' then
							MR <= (others => '0');
						end if;
					when x"51" =>						--MA
						MA(7 downto 0) <= P65_DO;
					when x"52" =>
						MA(15 downto 8) <= P65_DO;
					when x"53" =>						--MB
						MB(7 downto 0) <= P65_DO;
					when x"54" =>
						MB(15 downto 8) <= P65_DO;
						MATH_REQ <= '1';
					when others => null;
				end case;
			elsif SA1_MMIO_READ = '1' then
				case P65_A(7 downto 0) is
					when x"02" =>						--HCR Lsb
						HCR <= std_logic_vector(H_CNT);
						VCR <= std_logic_vector(V_CNT);
					when others => null;
				end case;
			end if;
		end if;
	end if;
end process;

SNES_IRQ <= (SNES_IRQ_EN and SNES_IRQ_FLAG) or (CDMA_IRQ_EN and CDMA_IRQ_FLAG);
SA1_IRQ <= (SA1_IRQ_EN and SA1_IRQ_FLAG) or (TM_IRQ_EN and TM_IRQ_FLAG) or (DMA_IRQ_EN and DMA_IRQ_FLAG);
SA1_NMI <= (SA1_NMI_EN and SA1_NMI_FLAG);

process( RST_N, CLK )
begin
	if RST_N = '0' then
		OPENBUS <= (others => '0');
	elsif rising_edge(CLK) then
		if EN = '1' then
			if SYSCLKF_CE = '1' then
--				if SNES_RD_N = '0' then
--					OPENBUS <= SNES_DO;
--				els
--				if SNES_WR_N = '0' then
					OPENBUS <= SNES_DI;
--				end if;
			end if;
		end if;
	end if;
end process;

process( SNES_A, SNES_IRAM_ACCESS, SNES_CCDMA_IRAM_ACCESS, SNES_BWRAM_ACCESS, SNES_MMIO_READ_ACCESS, SNES_ROM_ACCESS, 
			SNES_BWRAM_A, ROM_DI, IRAM_DO, BWRAM_DI, SIV, SNV, NMISEL, IRQSEL, SNES_IRQ_FLAG, CDMA_IRQ_FLAG, CMSG, OPENBUS )
begin
	if SNES_ROM_ACCESS = '1' then													--ROM 00h-3Fh/80h-BFh:8000h-FFFFh, C0h-FFh:0000h-FFFFh 
		if SNES_A(23 downto 1) = x"00FFE" & "101" and NMISEL = '1' then	--00FFEA/B
			if SNES_A(0) = '0' then
				SNES_DO <= SNV(7 downto 0);
			else
				SNES_DO <= SNV(15 downto 8);
			end if;
		elsif SNES_A(23 downto 1) = x"00FFE" & "111" and IRQSEL = '1' then--00FFEE/F
			if SNES_A(0) = '0' then
				SNES_DO <= SIV(7 downto 0);
			else
				SNES_DO <= SIV(15 downto 8);
			end if;
		else
			if SNES_A(0) = '0' then
				SNES_DO <= ROM_DI(7 downto 0);
			else
				SNES_DO <= ROM_DI(15 downto 8);
			end if;
		end if;
	elsif SNES_MMIO_READ_ACCESS = '1' then												--SNES Port Read
		case SNES_A(7 downto 0) is
			when x"00" =>						--CCNT
				SNES_DO <= SNES_IRQ_FLAG & IRQSEL & CDMA_IRQ_FLAG & NMISEL & CMSG;
			when others => 
				SNES_DO <= OPENBUS;
		end case;
	elsif SNES_IRAM_ACCESS = '1' or 													--I-RAM 00h-3Fh/80h-BFh:3000h-37FFh
			SNES_CCDMA_IRAM_ACCESS = '1' then										--CC1 SNES DMA BW-RAM 40h-4Fh:0000h-FFFFh
		SNES_DO <= IRAM_DO;
	elsif SNES_BWRAM_ACCESS = '1' then												--BW-RAM 40h-4Fh:0000h-FFFFh
		SNES_DO <= BWRAM_DI;
	else
		SNES_DO <= OPENBUS;
	end if;
end process;

IRQ_N <= not SNES_IRQ;


--MATH
MULT: entity work.SA1MULT
port map (
	dataa		=> MA,
	datab		=> MB,
	result	=> MULR
); 

DIV: entity work.SA1DIV
port map (
	clock    => CLK,
	numer		=> MA,
	denom		=> MB,
	quotient	=> DIVQ,
	remain	=> DIVR
); 


-- H/V Counters
process( RST_N, CLK )
begin
	if RST_N = '0' then
		H_CNT <= (others => '0');
		V_CNT <= (others => '0');
		DOT_CLK <= '0';
	elsif rising_edge(CLK) then
		if EN = '1' then
			DOT_CLK <= not DOT_CLK;
			if SA1_MMIO_WRITE = '1' and P65_A(7 downto 0) = x"11" then
				H_CNT <= (others => '0');
				V_CNT <= (others => '0');
			elsif DOT_CLK = '1' then
				if TMMODE = '0' then
					if H_CNT = 340 then
						H_CNT <= (others => '0');
						if (V_CNT = 261 and PAL = '0') or (V_CNT = 311 and PAL = '1') then
							V_CNT <= (others => '0');
						else
							V_CNT <= V_CNT + 1;
						end if;
					else
						H_CNT <= H_CNT + 1;
					end if;
				else
					if H_CNT = 511 then
						H_CNT <= (others => '0');
						V_CNT <= V_CNT + 1;
					else
						H_CNT <= H_CNT + 1;
					end if;
				end if;
			end if;
		end if;
	end if;
end process;
	
end rtl;