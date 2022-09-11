library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;
use work.PPU_PKG.all;

entity SPPU is
	port(
		RST_N			: in std_logic;
		CLK			: in std_logic;
		
		ENABLE		: in std_logic;
		
		PA				: in std_logic_vector(7 downto 0);
		PARD_N		: in std_logic;
		PAWR_N		: in std_logic;
		DI				: in std_logic_vector(7 downto 0);
		DO				: out std_logic_vector(7 downto 0);
		
		SYSCLK_CE	: in std_logic;
		
		VRAM_ADDRA	: out std_logic_vector(15 downto 0);
		VRAM_ADDRB	: out std_logic_vector(15 downto 0);
		VRAM_DAI		: in std_logic_vector(7 downto 0);
		VRAM_DBI		: in std_logic_vector(7 downto 0);
		VRAM_DAO		: out std_logic_vector(7 downto 0);
		VRAM_DBO		: out std_logic_vector(7 downto 0);
		VRAM_WRA_N	: out std_logic;
		VRAM_WRB_N	: out std_logic;
		VRAM_RD_N	: out std_logic;
		
		EXTLATCH		: in std_logic;
		
		PAL			: in std_logic;
		BLEND			: in std_logic;

		HIGH_RES		: out std_logic;
		DOTCLK		: out std_logic;
		
		HBLANK		: out std_logic;
		VBLANK		: out std_logic;

		COLOR_OUT	: out std_logic_vector(23 downto 0);	-- RGB 8:8:8
		X_OUT			: out std_logic_vector(8 downto 0);
		Y_OUT			: out std_logic_vector(8 downto 0);
		FRAME_OUT	: out std_logic;
		V224			: out std_logic;
		
		FIELD_OUT	: out std_logic;
		INTERLACE	: out std_logic;
		
		HSYNC			: out std_logic;
		VSYNC			: out std_logic;
		HDE 			: out std_logic;
		VDE 			: out std_logic;
		
		BG_EN			: in std_logic_vector(4 downto 0)
	);
end SPPU;

architecture rtl of SPPU is

signal DOT_CLK 			: std_logic;
signal DOT_CLKR_CE 		: std_logic;
signal DOT_CLKF_CE 		: std_logic;
signal CLK_CNT 			: unsigned(2 downto 0);
signal MDR1					: std_logic_vector(7 downto 0);
signal MDR2					: std_logic_vector(7 downto 0);
signal D_OUT 				: std_logic_vector(7 downto 0);

-- Registers
signal FORCE_BLANK 		: std_logic;
signal MB 					: std_logic_vector(3 downto 0);
signal OBJADDR 			: std_logic_vector(2 downto 0);
signal OBJNAME 			: std_logic_vector(1 downto 0);
signal OBJSIZE 			: std_logic_vector(2 downto 0);
signal OAMADD 				: std_logic_vector(8 downto 0);
signal OAM_PRIO 			: std_logic;
signal TM 					: std_logic_vector(7 downto 0);
signal TS 					: std_logic_vector(7 downto 0);
signal BGINTERLACE 		: std_logic;
signal OBJINTERLACE 		: std_logic;
signal OVERSCAN 			: std_logic;
signal PSEUDOHIRES 		: std_logic;
signal M7EXTBG				: std_logic;
signal BG_MODE				: std_logic_vector(2 downto 0);
signal BG3PRIO				: std_logic;
signal BG_SIZE				: std_logic_vector(3 downto 0);
signal BG_MOSAIC_EN		: std_logic_vector(3 downto 0);
signal MOSAIC_SIZE 		: std_logic_vector(3 downto 0);
signal BG_SC_ADDR			: BgScAddr_t;
signal BG_SC_SIZE			: BgScSize_t;
signal BG_NBA 				: BgTileAddr_t;
signal CGADD 				: std_logic_vector(8 downto 0);
signal VMAIN_ADDRINC 	: std_logic;
signal VMAIN_ADDRTRANS 	: std_logic_vector(1 downto 0);
signal VMADD 				: std_logic_vector(15 downto 0);

signal BG_HOFS				: BgScroll_t;
signal BG_VOFS				: BgScroll_t;

signal M7SEL				: std_logic_vector(7 downto 0);
signal M7A					: std_logic_vector(15 downto 0);
signal M7B					: std_logic_vector(15 downto 0);
signal M7C					: std_logic_vector(15 downto 0);
signal M7D					: std_logic_vector(15 downto 0);
signal M7HOFS				: std_logic_vector(12 downto 0);
signal M7VOFS				: std_logic_vector(12 downto 0);
signal M7X					: std_logic_vector(12 downto 0);
signal M7Y					: std_logic_vector(12 downto 0);

signal WH0 					: std_logic_vector(7 downto 0);
signal WH1 					: std_logic_vector(7 downto 0);
signal WH2 					: std_logic_vector(7 downto 0);
signal WH3 					: std_logic_vector(7 downto 0);
signal W12SEL 				: std_logic_vector(7 downto 0);
signal W34SEL 				: std_logic_vector(7 downto 0);
signal WOBJSEL 			: std_logic_vector(7 downto 0);
signal WBGLOG 				: std_logic_vector(7 downto 0);
signal WOBJLOG 			: std_logic_vector(7 downto 0);
signal TMW 					: std_logic_vector(7 downto 0);
signal TSW 					: std_logic_vector(7 downto 0);
signal CGWSEL 				: std_logic_vector(7 downto 0);
signal CGADSUB				: std_logic_vector(7 downto 0);
signal SUBCOLBD 			: std_logic_vector(14 downto 0);
signal OPHCT 				: std_logic_vector(8 downto 0);
signal OPVCT 				: std_logic_vector(8 downto 0);

signal OPHCT_latch 		: std_logic;
signal OPVCT_latch 		: std_logic;
signal EXTLATCHr 			: std_logic;
signal F_LATCH 			: std_logic;
signal CGRAM_Lsb 			: std_logic_vector(7 downto 0);
signal BGOFS_latch 		: std_logic_vector(7 downto 0);
signal M7_latch 			: std_logic_vector(7 downto 0);
signal BGHOFS_latch 		: std_logic_vector(2 downto 0);
signal OAM_latch 			: std_logic_vector(7 downto 0);
signal VRAMDATA_Prefetch: std_logic_vector(15 downto 0);
signal VMADD_INC 			: unsigned(7 downto 0);
signal OBJ_TIME_OFL 		: std_logic;
signal OBJ_RANGE_OFL 	: std_logic;
signal PARD_Nr 			: std_logic;

signal BG_FORCE_BLANK	: std_logic;
signal VMADD_TRANS 		: std_logic_vector(15 downto 0);
signal VRAM1_WRITE 		: std_logic;
signal VRAM2_WRITE 		: std_logic;
signal VRAM_ADDR_INC 	: std_logic;
signal OAM_ADDR_REQ 		: std_logic;
signal OAM_PRIO_REQ 		: std_logic;
signal VRAMPRERD_REQ 	: std_logic;
signal VRAMRD_CNT 		: unsigned(1 downto 0);

-- HV COUNTERS
signal H_CNT 				: unsigned(8 downto 0);
signal V_CNT 				: unsigned(8 downto 0);
signal FIELD 				: std_logic;
signal LAST_VIS_LINE 	: unsigned(8 downto 0);
signal LAST_LINE			: unsigned(8 downto 0);
signal LAST_DOT			: unsigned(8 downto 0);
signal IN_HBL 				: std_logic;
signal IN_VBL 				: std_logic;

-- BACKGROUND
signal BG_VRAM_ADDRA 	: std_logic_vector(15 downto 0);
signal BG_VRAM_ADDRB 	: std_logic_vector(15 downto 0);
signal BG_FETCH 			: std_logic;
signal M7_FETCH 			: std_logic;
signal SPR_GET_PIXEL 	: std_logic;
signal BG_GET_PIXEL 		: std_logic;
signal BG_MATH 			: std_logic;
signal BG_OUT 				: std_logic;
signal GET_PIXEL_X		: unsigned(7 downto 0);
signal WINDOW_X			: unsigned(7 downto 0);
signal OUT_X				: unsigned(7 downto 0);
signal OUT_Y				: unsigned(7 downto 0);
signal BG_MOSAIC_X 		: unsigned(3 downto 0);
signal BG_MOSAIC_Y 		: unsigned(3 downto 0);
signal BF 					: BgFetch_r;
signal BG3_OPT_DATA0 	: std_logic_vector(15 downto 0);
signal BG3_OPT_DATA1 	: std_logic_vector(15 downto 0);
signal BG_DATA 			: BgData_t;
signal BG_TILE_INFO 		: BgTileInfo_t;
signal BG_TILES 			: BgTileInfos_t;
signal BG1_PIX_DATA 		: std_logic_vector(11 downto 0);
signal BG2_PIX_DATA 		: std_logic_vector(7 downto 0);
signal BG3_PIX_DATA 		: std_logic_vector(5 downto 0);
signal BG4_PIX_DATA 		: std_logic_vector(5 downto 0);
signal M7_PIX_DATA 		: std_logic_vector(7 downto 0);

signal MPY 					: signed(23 downto 0);
signal M7_SCREEN_X  		: unsigned(7 downto 0);
signal M7_TEMP_X 			: signed(23 downto 0);
signal M7_TEMP_Y 			: signed(23 downto 0);
signal M7_TILE_N 			: unsigned(7 downto 0);
signal M7_TILE_ROW 		: unsigned(2 downto 0);
signal M7_TILE_COL 		: unsigned(2 downto 0);
signal M7_TILE_OUTSIDE 	: std_logic;

-- OBJ
signal OAM_D 				: std_logic_vector(15 downto 0);
signal OAM_Q 				: std_logic_vector(31 downto 0);
signal OAMIO_Q 			: std_logic_vector(15 downto 0);
signal OAM_ADDR_A 		: std_logic_vector(7 downto 0);
signal OAM_ADDR_B 		: std_logic_vector(6 downto 0);
signal OAM_WE 				: std_logic;
signal HOAM_Q 				: std_logic_vector(7 downto 0);
signal HOAM_ADDR 			: std_logic_vector(4 downto 0);
signal HOAM_WE 			: std_logic;
signal HOAM_X8 			: std_logic;
signal HOAM_S 				: std_logic;

signal OAM_ADDR 			: std_logic_vector(9 downto 0);
signal OAM_RANGE 			: RangeOam_t;
signal OAM_PRIO_INDEX 	: std_logic_vector(6 downto 0);
signal OAM_TIME_INDEX 	: std_logic_vector(6 downto 0);
signal RANGE_CNT 			: unsigned(5 downto 0);
signal TILES_OAM_CNT 	: unsigned(5 downto 0);
signal TILES_CNT 			: unsigned(2 downto 0);

signal OBJ_RANGE 			: std_logic;
signal OBJ_TIME 			: std_logic;
signal OBJ_FETCH 			: std_logic;
signal OBJ_RANGE_DONE 	: std_logic;
signal OBJ_TIME_DONE 	: std_logic;

signal OBJ_TILE_COL 		: unsigned(3 downto 0);
signal OBJ_TILE_ROW 		: unsigned(3 downto 0);
signal OBJ_TILE_LINE 	: unsigned(2 downto 0);
signal OBJ_TILE_GAP 		: unsigned(14 downto 0);
signal OBJ_TILE_HFLIP 	: std_logic;
signal OBJ_TILE_PAL 		: std_logic_vector(2 downto 0);
signal OBJ_TILE_PRIO 	: std_logic_vector(1 downto 0);
signal OBJ_TILE_X 		: unsigned(8 downto 0);

signal SPR_PIX_DATA 		: std_logic_vector(8 downto 0);
signal SPR_PIX_DATA_BUF : std_logic_vector(8 downto 0);
signal SPR_PIXEL_X 		: unsigned(7 downto 0);
signal OBJ_VRAM_ADDR 	: std_logic_vector(15 downto 0);
signal SPR_TILE_DATA 	: std_logic_vector(31 downto 0);
signal SPR_TILE_DATA_TEMP: std_logic_vector(15 downto 0);
signal SPR_TILE_X 		: unsigned(8 downto 0);
signal SPR_TILE_PAL 		: std_logic_vector(2 downto 0);
signal SPR_TILE_PRIO 	: std_logic_vector(1 downto 0);
signal OBJ_TIME_SAVE 	: std_logic;

signal SPR_PIX_D 			: std_logic_vector(8 downto 0);
signal SPR_PIX_Q 			: std_logic_vector(8 downto 0);
signal SPR_PIX_ADDR_A 	: std_logic_vector(7 downto 0);
signal SPR_PIX_WE_A 		: std_logic;
signal SPR_PIX_WE_B 		: std_logic;
signal SPR_PIX_CNT 		: unsigned(2 downto 0);

-- CRAM
signal CGRAM_Q 			: std_logic_vector(14 downto 0);
signal CGRAM_D 			: std_logic_vector(14 downto 0);
signal CGRAM_WE			: std_logic;
signal CGRAM_FETCH_ADDR : std_logic_vector(7 downto 0);
signal CGRAM_ADDR 		: std_logic_vector(7 downto 0);
signal CGRAM_ADDR_INC	: std_logic;

signal CGRAM_ADDR_CLR	: unsigned(7 downto 0);

-- COLOR MATH
signal PREV_COLOR			: std_logic_vector(14 downto 0);
signal SUB_BD 				: std_logic;
signal MAIN_R				: unsigned(4 downto 0);
signal MAIN_G				: unsigned(4 downto 0);
signal MAIN_B				: unsigned(4 downto 0);
signal SUB_R				: unsigned(4 downto 0);
signal SUB_G				: unsigned(4 downto 0);
signal SUB_B				: unsigned(4 downto 0);
signal SUB_MATH_R			: unsigned(4 downto 0);
signal SUB_MATH_G			: unsigned(4 downto 0);
signal SUB_MATH_B			: unsigned(4 downto 0);
signal HIRES 				: std_logic;
	
begin

process( RST_N, CLK )
variable DOT_CYCLES: unsigned(2 downto 0);
begin
	if RST_N = '0' then
		CLK_CNT <= (others => '0');
		DOT_CLK <= '0';
		DOT_CLKR_CE <= '0';
		DOT_CLKF_CE <= '0';
	elsif rising_edge(CLK) then
		if ENABLE = '0' then
			DOT_CYCLES := "100";
		elsif V_CNT = 240 and BGINTERLACE = '0' and FIELD = '1' and PAL = '0' then
			DOT_CYCLES := "100";
		elsif H_CNT = 323 or H_CNT = 327 then
			DOT_CYCLES := "110";
		else
			DOT_CYCLES := "100";
		end if;
		
		DOT_CLKR_CE <= '0';
		DOT_CLKF_CE <= '0';
		CLK_CNT <= CLK_CNT + 1;
		if CLK_CNT = 1  then
			DOT_CLK <= '0';
		elsif CLK_CNT = DOT_CYCLES-1  then
			CLK_CNT <= (others => '0');
			DOT_CLK <= '1';
		end if;

		if CLK_CNT = 0 then			
			DOT_CLKF_CE <= '1';
		elsif CLK_CNT = DOT_CYCLES-1-1  then
			DOT_CLKR_CE <= '1';
		end if;
	end if;
end process;


CGRAM : entity work.dpram generic map(8,15)
port map(
	clock		 => CLK,
	address_a => CGRAM_ADDR,
	data_a	 => CGRAM_D,
	wren_a	 => CGRAM_WE,
	q_a		 => CGRAM_Q,
	
	address_b => std_logic_vector(CGRAM_ADDR_CLR),
	data_b	 => std_logic_vector(CGRAM_ADDR_CLR(6 downto 0)) & std_logic_vector(CGRAM_ADDR_CLR),
	wren_b	 => not RST_N
);

CGRAM_ADDR_CLR <= CGRAM_ADDR_CLR + 1 when rising_edge(CLK);

CGRAM_ADDR <= CGRAM_FETCH_ADDR when BG_MATH = '1' and FORCE_BLANK = '0' else 
				  CGADD(8 downto 1);
CGRAM_D <= DI(6 downto 0) & CGRAM_Lsb;
CGRAM_WE <= '1' when CGADD(0) = '1' and PAWR_N = '0' and PA = x"22" and SYSCLK_CE = '1' else '0';

process( RST_N, CLK )
begin
	if RST_N = '0' then
		FORCE_BLANK <= '1';
		MB <= (others => '0');
		OBJADDR <= (others => '0');
		OBJNAME <= (others => '0');
		OBJSIZE <= (others => '0');
		OAMADD <= (others => '0');
		TM <= (others => '0');
		TS <= (others => '0');
		BGINTERLACE <= '0';
		OBJINTERLACE <= '0';
		OVERSCAN <= '0';
		PSEUDOHIRES <= '0';
		M7EXTBG <= '0';
		BG_MODE <= (others => '0'); 
		BG3PRIO <= '0';
		BG_SIZE <= (others => '0');
		BG_MOSAIC_EN <= (others => '0');
		MOSAIC_SIZE <= (others => '0');
		BG_SC_ADDR <= (others => (others => '0'));
		BG_SC_SIZE <= (others => (others => '0'));
		BG_NBA <= (others => (others => '0'));
		CGADD <= (others => '0');
		VMAIN_ADDRINC <= '0';
		VMAIN_ADDRTRANS <= (others => '0');
		VMADD <= (others => '0');
		BG_HOFS <= (others => (others => '0'));
		BG_VOFS <= (others => (others => '0'));
		M7SEL <= (others => '0');
		M7A <= (others => '0');
		M7B <= (others => '0');
		M7C <= (others => '0');
		M7D <= (others => '0');
		M7HOFS <= (others => '0');
		M7VOFS <= (others => '0');
		M7X <= (others => '0');
		M7Y <= (others => '0');
		WH0 <= (others => '0');
		WH1 <= (others => '0');
		WH2 <= (others => '0');
		WH3 <= (others => '0');
		W12SEL <= (others => '0');
		W34SEL <= (others => '0');
		WOBJSEL <= (others => '0');
		WBGLOG <= (others => '0');
		WOBJLOG <= (others => '0');
		TMW <= (others => '0');
		TSW <= (others => '0');
		CGWSEL <= (others => '0');
		CGADSUB <= (others => '0');
		OPHCT <= (others => '0');
		OPVCT <= (others => '0');
		SUBCOLBD <= (others => '0');
		
		VRAMDATA_Prefetch <= (others => '0');
		VMADD_INC <= x"01";
		VRAMPRERD_REQ <= '0';
		VRAMRD_CNT <= (others => '0');
		
		OPHCT_latch <= '0';
		OPVCT_latch <= '0';
		F_LATCH <= '0';
		M7_latch <= (others => '0');
		BGOFS_latch <= (others => '0');
		BGHOFS_latch <= (others => '0');
		EXTLATCHr <= '1';
		PARD_Nr <= '1';
		
		OAM_ADDR <= (others => '0');
		OAM_PRIO <= '0';
		OAM_latch <= (others => '0');
		OAM_PRIO_INDEX <= (others => '0');
		OAM_ADDR_REQ <= '0';
		OAM_PRIO_REQ <= '0';
		
		CGRAM_Lsb <= (others => '0');
	elsif rising_edge(CLK) then
		if ENABLE = '1' then
			if OAM_ADDR_REQ = '1' and DOT_CLKR_CE = '1' then
				OAM_ADDR <= OAMADD & "0";
				OAM_PRIO_INDEX <= OAMADD(7 downto 1);
				OAM_ADDR_REQ <= '0';
			end if;
	
			if OAM_PRIO_REQ = '1' and DOT_CLKR_CE = '1' then
				OAM_PRIO_INDEX <= OAM_ADDR(8 downto 2);
				OAM_PRIO_REQ <= '0';
			end if;
	
			if H_CNT = LAST_DOT and (V_CNT < LAST_VIS_LINE or V_CNT = LAST_LINE) and FORCE_BLANK = '0' and DOT_CLKR_CE = '1' then
				if OAM_PRIO = '0' then
					OAM_ADDR <= (others => '0');
				else
					OAM_ADDR <= "0" & OAM_PRIO_INDEX & "00";
				end if;
			end if;
	
			if OBJ_RANGE = '1' and FORCE_BLANK = '0' and H_CNT(0) = '1' and DOT_CLKR_CE = '1' then
				OAM_ADDR <= std_logic_vector(unsigned(OAM_ADDR) + 4);
			end if;
	
			if OBJ_TIME = '1' and H_CNT(0) = '0' and FORCE_BLANK = '0' and DOT_CLKR_CE = '1' then
				OAM_ADDR <= "0" & OAM_TIME_INDEX & "00";
			end if;
	
			
			if VRAMPRERD_REQ = '1' then
				if VRAMRD_CNT = 3 then
					if FORCE_BLANK = '1' or IN_VBL = '1' then
						VRAMDATA_Prefetch <= VRAM_DBI & VRAM_DAI;
					else
						VRAMDATA_Prefetch <= (others => '0');
					end if;
					VRAMPRERD_REQ <= '0';
				end if;
				VRAMRD_CNT <= VRAMRD_CNT + 1;
			end if;
			
			if PAWR_N = '0' and SYSCLK_CE = '1' then
				case PA is
					when x"00" =>						--INIDISP
						FORCE_BLANK <= DI(7);
						MB <= DI(3 downto 0);
						if FORCE_BLANK = '1' and V_CNT = LAST_VIS_LINE + 1 then
							OAM_ADDR_REQ <= '1';
						end if;
					when x"01" =>						--OBSEL
						OBJADDR <= DI(2 downto 0);
						OBJNAME <= DI(4 downto 3);
						OBJSIZE <= DI(7 downto 5);
					when x"02" =>						--OAMADDL
						OAMADD(7 downto 0) <= DI;
						OAM_ADDR_REQ <= '1';
					when x"03" =>						--OAMADDH
						OAMADD(8) <= DI(0);
						OAM_PRIO <= DI(7);
						OAM_ADDR_REQ <= '1';
					when x"04" =>						--OAMDI
						if OAM_ADDR(0) = '0' then
							OAM_latch <= DI;
						end if;
						OAM_ADDR <= std_logic_vector(unsigned(OAM_ADDR) + 1);
						OAM_PRIO_REQ <= '1';
					when x"05" =>						--BGMODE
						BG_MODE <= DI(2 downto 0);
						BG3PRIO <= DI(3);
						BG_SIZE <= DI(7 downto 4);
					when x"06" =>						--MOSAIC
						BG_MOSAIC_EN <= DI(3 downto 0);
						MOSAIC_SIZE <= DI(7 downto 4);
					when x"07" =>						--BG1SC
						BG_SC_SIZE(BG1) <= DI(1 downto 0);
						BG_SC_ADDR(BG1) <= DI(7 downto 2);
					when x"08" =>						--BG2SC
						BG_SC_SIZE(BG2) <= DI(1 downto 0);
						BG_SC_ADDR(BG2) <= DI(7 downto 2);
					when x"09" =>						--BG3SC
						BG_SC_SIZE(BG3) <= DI(1 downto 0);
						BG_SC_ADDR(BG3) <= DI(7 downto 2);
					when x"0A" =>						--BG4SC
						BG_SC_SIZE(BG4) <= DI(1 downto 0);
						BG_SC_ADDR(BG4) <= DI(7 downto 2);
					when x"0B" =>						--BG12NBA
						BG_NBA(BG1) <= DI(3 downto 0);
						BG_NBA(BG2) <= DI(7 downto 4);
					when x"0C" =>						--BG34NBA
						BG_NBA(BG3) <= DI(3 downto 0);
						BG_NBA(BG4) <= DI(7 downto 4);
					when x"0D" =>						--BG1HOFS
						BGOFS_latch <= DI;
						BGHOFS_latch <= DI(2 downto 0);
						BG_HOFS(BG1) <= DI(1 downto 0) & BGOFS_latch(7 downto 3) & BGHOFS_latch;
						
						M7_latch <= DI;
						M7HOFS <= DI(4 downto 0) & M7_latch;
					when x"0E" =>						--BG1VOFS
						BGOFS_latch <= DI;
						BG_VOFS(BG1) <= DI(1 downto 0) & BGOFS_latch;
						
						M7_latch <= DI;
						M7VOFS <= DI(4 downto 0) & M7_latch;
					when x"0F" =>						--BG2HOFS
						BGOFS_latch <= DI;
						BGHOFS_latch <= DI(2 downto 0);
						BG_HOFS(BG2) <= DI(1 downto 0) & BGOFS_latch(7 downto 3) & BGHOFS_latch;
					when x"10" =>						--BG2VOFS
						BGOFS_latch <= DI;
						BG_VOFS(BG2) <= DI(1 downto 0) & BGOFS_latch;
					when x"11" =>						--BG3HOFS
						BGOFS_latch <= DI;
						BGHOFS_latch <= DI(2 downto 0);
						BG_HOFS(BG3) <= DI(1 downto 0) & BGOFS_latch(7 downto 3) & BGHOFS_latch;
					when x"12" =>						--BG3VOFS
						BGOFS_latch <= DI;
						BG_VOFS(BG3) <= DI(1 downto 0) & BGOFS_latch;
					when x"13" =>						--BG4HOFS
						BGOFS_latch <= DI;
						BGHOFS_latch <= DI(2 downto 0);
						BG_HOFS(BG4) <= DI(1 downto 0) & BGOFS_latch(7 downto 3) & BGHOFS_latch;
					when x"14" =>						--BG4VOFS
						BGOFS_latch <= DI;
						BG_VOFS(BG4) <= DI(1 downto 0) & BGOFS_latch;
					when x"15" =>						--VMAIN
						VMAIN_ADDRINC <= DI(7);
						VMAIN_ADDRTRANS <= DI(3 downto 2);
						case DI(1 downto 0) is
							when "00" =>
								VMADD_INC <= x"01";
							when "01" =>
								VMADD_INC <= x"20";
							when others =>
								VMADD_INC <= x"80";
						end case;
					when x"16" =>						--VMADDL
						VMADD(7 downto 0) <= DI;
						VRAMPRERD_REQ <= '1';
					when x"17" =>						--VMADDH
						VMADD(15 downto 8) <= DI;
						VRAMPRERD_REQ <= '1';
					when x"18" =>						--VMDIL
						if VMAIN_ADDRINC = '0' then
							VMADD <= std_logic_vector(unsigned(VMADD) + VMADD_INC);
						end if;
					when x"19" =>						--VMDIH
						if VMAIN_ADDRINC = '1' then
							VMADD <= std_logic_vector(unsigned(VMADD) + VMADD_INC);
						end if;
					when x"1A" =>						--M7SEL
						M7SEL <= DI;
					when x"1B" =>						--M7A
						M7_latch <= DI;
						M7A <= DI & M7_latch;
					when x"1C" =>						--M7B
						M7_latch <= DI;
						M7B <= DI & M7_latch;
					when x"1D" =>						--M7C
						M7_latch <= DI;
						M7C <= DI & M7_latch;
					when x"1E" =>						--M7D
						M7_latch <= DI;
						M7D <= DI & M7_latch;
					when x"1F" =>						--M7X
						M7_latch <= DI;
						M7X <= DI(4 downto 0) & M7_latch;
					when x"20" =>						--M7Y
						M7_latch <= DI;
						M7Y <= DI(4 downto 0) & M7_latch;
					when x"21" =>						--CGADD
						CGADD <= DI & '0';
					when x"22" =>						--CGDI
						if CGADD(0) = '0' then
							CGRAM_Lsb <= DI;
						end if;
						CGADD <= std_logic_vector(unsigned(CGADD) + 1);
					when x"23" =>						--W12SEL
						W12SEL <= DI;
					when x"24" =>						--W34SEL
						W34SEL <= DI;
					when x"25" =>						--WOBJSEL
						WOBJSEL <= DI;
					when x"26" =>						--WH0
						WH0 <= DI;
					when x"27" =>						--WH1
						WH1 <= DI;
					when x"28" =>						--WH2
						WH2 <= DI;
					when x"29" =>						--WH3
						WH3 <= DI;
					when x"2A" =>						--WBGLOG
						WBGLOG <= DI;
					when x"2B" =>						--WOBJLOG
						WOBJLOG <= DI;
					when x"2C" =>						--TM
						TM <= DI;
					when x"2D" =>						--TS
						TS <= DI;
					when x"2E" =>						--TMW
						TMW <= DI;
					when x"2F" =>						--TSW
						TSW <= DI;
					when x"30" =>						--CGWSEL
						CGWSEL <= DI;
					when x"31" =>						--CGADSUB
						CGADSUB <= DI;
					when x"32" =>						--COLDI
						if DI(7) = '1' then
							SUBCOLBD(14 downto 10) <= DI(4 downto 0);
						end if;
						if DI(6) = '1' then
							SUBCOLBD(9 downto 5) <= DI(4 downto 0);
						end if;
						if DI(5) = '1' then
							SUBCOLBD(4 downto 0) <= DI(4 downto 0);
						end if;
					when x"33" =>						--SETINI
						BGINTERLACE <= DI(0);
						OBJINTERLACE <= DI(1);
						OVERSCAN <= DI(2);
						PSEUDOHIRES <= DI(3);
						M7EXTBG <= DI(6);
					when others => null;
				end case;
	
			elsif PARD_N = '0' and SYSCLK_CE = '1' then
				case PA is
					when x"38" =>			--RDOAM
						OAM_ADDR <= std_logic_vector(unsigned(OAM_ADDR) + 1);
						OAM_PRIO_REQ <= '1';
					when x"3B" =>			--RDCGRAM
						CGADD <= std_logic_vector(unsigned(CGADD) + 1);
					when x"39" =>						--RDVRAML
						if VMAIN_ADDRINC = '0' then
							VMADD <= std_logic_vector(unsigned(VMADD) + VMADD_INC);
							if FORCE_BLANK = '1' or IN_VBL = '1' then
								VRAMDATA_Prefetch <= VRAM_DBI & VRAM_DAI;
							else
								VRAMDATA_Prefetch <= (others => '0');
							end if;
						end if;
					when x"3A" =>						--RDVRAMH
						if VMAIN_ADDRINC = '1' then
							VMADD <= std_logic_vector(unsigned(VMADD) + VMADD_INC);
							if FORCE_BLANK = '1' or IN_VBL = '1' then
								VRAMDATA_Prefetch <= VRAM_DBI & VRAM_DAI;
							else
								VRAMDATA_Prefetch <= (others => '0');
							end if;
						end if;
					when x"3C" =>						--OPHCT
						OPHCT_latch <= not OPHCT_latch;
					when x"3D" =>						--OPVCT
						OPVCT_latch <= not OPVCT_latch;
					when x"3F" =>						--STAT78
						OPHCT_latch <= '0';
						OPVCT_latch <= '0';
						if EXTLATCH = '1' then
							F_LATCH <= '0';
						end if;
					when others => null;
				end case;
			end if;
			
			if H_CNT = LAST_DOT and V_CNT = LAST_VIS_LINE and FORCE_BLANK = '0' and DOT_CLKR_CE = '1' then
				OAM_ADDR <= OAMADD & "0";
				OAM_PRIO_INDEX <= OAMADD(7 downto 1);
			end if;
			
			EXTLATCHr <= EXTLATCH;
			PARD_Nr <= PARD_N;
			if (EXTLATCH = '0' and EXTLATCHr = '1') or 
				(PARD_N = '0' and PARD_Nr = '1' and PA = x"37") then	--SLHV 
				OPHCT <= std_logic_vector(H_CNT);
				OPVCT <= std_logic_vector(V_CNT);	
				F_LATCH <= '1';
			end if;
		end if;
	end if;
end process;

process( RST_N, CLK )
begin
	if RST_N = '0' then
		MDR1 <= (others => '1');
		MDR2 <= (others => '1');
	elsif rising_edge(CLK) then
		if PARD_N = '0' and SYSCLK_CE = '1' then
			if PA = x"34" or PA = x"35" or PA = x"36" or PA = x"38" or PA = x"39" or PA = x"3A" or PA = x"3E" then
				MDR1 <= D_OUT;
			end if;
			if PA = x"3B" or PA = x"3C" or PA = x"3D" or PA = x"3F" then
				MDR2 <= D_OUT;
			end if;
		end if;
	end if;
end process;

process( RST_N, CLK)
begin 
	if RST_N = '0' then
		D_OUT <= (others => '0');
	elsif rising_edge(CLK) then
		case PA is
			when x"04" | x"05" | x"06" | x"08" | x"09" | x"0A" | 
				  x"14" | x"15" | x"16" | x"18" | x"19" | x"1A" | 
				  x"24" | x"25" | x"26" | x"28" | x"29" =>	
				D_OUT <= MDR1;
			when x"34" =>						--MPYL
				D_OUT <= std_logic_vector(MPY(7 downto 0));
			when x"35" =>						--MPYM
				D_OUT <= std_logic_vector(MPY(15 downto 8));
			when x"36" =>						--MPYH
				D_OUT <= std_logic_vector(MPY(23 downto 16));
			when x"38" =>						--RDOAM
				if OAM_ADDR(9) = '0' then
					if OAM_ADDR(0) = '0' then
						D_OUT <= OAMIO_Q(7 downto 0);
					else
						D_OUT <= OAMIO_Q(15 downto 8);
					end if;
				else
					D_OUT <= HOAM_Q;
				end if;
			when x"39" =>						--RDVRAML
				D_OUT <= VRAMDATA_Prefetch(7 downto 0);
			when x"3A" =>						--RDVRAMH
				D_OUT <= VRAMDATA_Prefetch(15 downto 8);
			when x"3E" =>						--STAT77
				D_OUT <= OBJ_TIME_OFL & OBJ_RANGE_OFL & "0" & MDR1(4) & x"1";
			when x"3B" =>						--RDCGRAM
				if CGADD(0) = '0' then
					D_OUT <= CGRAM_Q(7 downto 0);
				else
					D_OUT <= MDR2(7) & CGRAM_Q(14 downto 8);
				end if;
			when x"3C" =>						--OPHCT
				if OPHCT_latch = '0' then
					D_OUT <= OPHCT(7 downto 0);
				else
					D_OUT <= MDR2(7 downto 1) & OPHCT(8);
				end if;
			when x"3D" =>						--OPVCT
				if OPVCT_latch = '0' then
					D_OUT <= OPVCT(7 downto 0);
				else
					D_OUT <= MDR2(7 downto 1) & OPVCT(8);
				end if;
			when x"3F" =>						--STAT78
				D_OUT <= FIELD & ((not EXTLATCH) or F_LATCH) & MDR2(5) & PAL & x"3";
			when others =>
				D_OUT <= DI;
		end case;
	end if;
end process;

DO <= D_OUT;

				 
VMADD_TRANS <= VMADD(15 downto  8) & VMADD(4 downto 0) & VMADD(7 downto 5) when VMAIN_ADDRTRANS = "01" else 
					VMADD(15 downto  9) & VMADD(5 downto 0) & VMADD(8 downto 6) when VMAIN_ADDRTRANS = "10" else 
					VMADD(15 downto 10) & VMADD(6 downto 0) & VMADD(9 downto 7) when VMAIN_ADDRTRANS = "11" else 
					VMADD(15 downto  0);
					
VRAM1_WRITE <= '1' when PAWR_N = '0' and PA = x"18" and (BG_FORCE_BLANK = '1' or IN_VBL = '1') else '0';
VRAM2_WRITE <= '1' when PAWR_N = '0' and PA = x"19" and (BG_FORCE_BLANK = '1' or IN_VBL = '1') else '0';			

		
VRAM_ADDRA <= BG_VRAM_ADDRA when BG_FETCH = '1' and BG_FORCE_BLANK = '0'else 
				  OBJ_VRAM_ADDR when OBJ_FETCH = '1' and FORCE_BLANK = '0' else
				  VMADD_TRANS;
VRAM_ADDRB <= BG_VRAM_ADDRB when BG_FETCH = '1' and BG_FORCE_BLANK = '0'else 
				  OBJ_VRAM_ADDR when OBJ_FETCH = '1' and FORCE_BLANK= '0' else
				  VMADD_TRANS;			 
				 

VRAM_DAO <= DI;
VRAM_DBO <= DI;

VRAM_RD_N <= '0' when ENABLE = '0' else 
             '0' when BG_FORCE_BLANK = '0' and IN_VBL = '0' else
			    '0' when PA /= x"18" and PA /= x"19" else
			    '1';
VRAM_WRA_N <= '1' when ENABLE = '0' else not VRAM1_WRITE;
VRAM_WRB_N <= '1' when ENABLE = '0' else not VRAM2_WRITE;



--HV counters
process( PAL, BGINTERLACE, FIELD, V_CNT )
begin
	if PAL = '0' then
		if BGINTERLACE = '1' and FIELD = '0' then
			LAST_LINE <= LINE_NUM_NTSC;
		else
			LAST_LINE <= LINE_NUM_NTSC-1;
		end if;
		LAST_DOT <= DOT_NUM-1;
	else
		if BGINTERLACE = '1' and FIELD = '0' then
			LAST_LINE <= LINE_NUM_PAL;
		else
			LAST_LINE <= LINE_NUM_PAL-1;
		end if;
		if V_CNT = 311 and BGINTERLACE = '1' and FIELD = '1' then
			LAST_DOT <= DOT_NUM;
		else
			LAST_DOT <= DOT_NUM-1;
		end if;
	end if;
end process;

LAST_VIS_LINE <= '0' & x"E0" when OVERSCAN = '0' else '0' & x"EF";

process( RST_N, CLK )
variable VSYNC_LINE: unsigned(8 downto 0);
variable VSYNC_HSTART: unsigned(8 downto 0);
begin
	if RST_N = '0' then
		H_CNT <= (others => '0');
		V_CNT <= (others => '0');
		FIELD <= '0';
		IN_HBL <= '0';
		IN_VBL <= '0';
	elsif rising_edge(CLK) then
		if ENABLE = '1' and DOT_CLKR_CE = '1' then
			if PAL = '0' then
				VSYNC_LINE := LINE_VSYNC_NTSC;
			else
				VSYNC_LINE := LINE_VSYNC_PAL;
			end if;
			
			if BGINTERLACE = '1' and FIELD = '0' then
				VSYNC_HSTART := VSYNC_I_HSTART;
				VSYNC_LINE := VSYNC_LINE + 1;
			else
				VSYNC_HSTART := HSYNC_START;
			end if;

			if OVERSCAN = '1' then
				VSYNC_LINE := VSYNC_LINE + 8;
			end if;

			H_CNT <= H_CNT + 1;
			if H_CNT = LAST_DOT then
				H_CNT <= (others => '0');
				V_CNT <= V_CNT + 1;			
				if V_CNT = LAST_LINE then
					V_CNT <= (others => '0');
					FIELD <= not FIELD;
				end if;
			end if;

			if H_CNT = 274-1 then
				IN_HBL <= '1';
			elsif H_CNT = LAST_DOT then
				IN_HBL <= '0';
			end if;
			
			if V_CNT = LAST_VIS_LINE and H_CNT = LAST_DOT then
				IN_VBL <= '1';
			elsif V_CNT = LAST_LINE and H_CNT = LAST_DOT then
				IN_VBL <= '0';
			end if;
			
			if H_CNT = 19-1  then HDE <= '1'; end if;
			if H_CNT = 275-1 then HDE <= '0'; end if;

			if H_CNT = HSYNC_START then HSYNC <= '1'; end if;
			if H_CNT = HSYNC_START+23 then HSYNC <= '0'; end if;

			if V_CNT = 1               then VDE <= '1'; end if;
			if V_CNT = LAST_VIS_LINE+1 then VDE <= '0'; end if;
			if V_CNT = VSYNC_LINE-3    then VDE <= '0'; end if; -- make sure VDE deactivated before VSync!

			if H_CNT = VSYNC_HSTART then
				if V_CNT = VSYNC_LINE then VSYNC <= '1'; end if;
				if V_CNT = VSYNC_LINE+3 then VSYNC <= '0'; end if;
			end if;
		end if;
	end if;
end process;


process( H_CNT, V_CNT, LAST_VIS_LINE )
begin
	if H_CNT <= BG_FETCH_END and V_CNT >= 0 and V_CNT <= LAST_VIS_LINE then
		BG_FETCH <= '1';
	else
		BG_FETCH <= '0';
	end if;
	
	if H_CNT >= M7_FETCH_START and H_CNT <= M7_FETCH_END and V_CNT >= 0 and V_CNT <= LAST_VIS_LINE then
		M7_FETCH <= '1';
	else
		M7_FETCH <= '0';
	end if;

	if H_CNT >= SPR_GET_PIX_START and H_CNT <= SPR_GET_PIX_END and V_CNT >= 1 and V_CNT <= LAST_VIS_LINE then
		SPR_GET_PIXEL <= '1';
	else
		SPR_GET_PIXEL <= '0';
	end if;
	
	if H_CNT >= BG_GET_PIX_START and H_CNT <= BG_GET_PIX_END and V_CNT >= 1 and V_CNT <= LAST_VIS_LINE then
		BG_GET_PIXEL <= '1';
	else
		BG_GET_PIXEL <= '0';
	end if;
	
	if H_CNT >= BG_MATH_START and H_CNT <= BG_MATH_END and V_CNT >= 1 and V_CNT <= LAST_VIS_LINE then
		BG_MATH <= '1';
	else
		BG_MATH <= '0';
	end if;
	
	if H_CNT >= BG_OUT_START and H_CNT <= BG_OUT_END and V_CNT >= 1 and V_CNT <= LAST_VIS_LINE then
		BG_OUT <= '1';
	else
		BG_OUT <= '0';
	end if;
	
	if H_CNT <= OBJ_RANGE_END and V_CNT < LAST_VIS_LINE then
		OBJ_RANGE <= '1';
	else
		OBJ_RANGE <= '0';
	end if;
	
	if H_CNT >= OBJ_TIME_START and H_CNT <= OBJ_TIME_END and V_CNT < LAST_VIS_LINE then
		OBJ_TIME <= '1';
	else
		OBJ_TIME <= '0';
	end if;
	
	if H_CNT >= OBJ_FETCH_START and H_CNT <= OBJ_FETCH_END and V_CNT < LAST_VIS_LINE then
		OBJ_FETCH <= '1';
	else
		OBJ_FETCH <= '0';
	end if;
end process;


--Background engine
HIRES <= '1' when BG_MODE = "101" or BG_MODE = "110" else '0';

BF <= BF_TBL(to_integer(unsigned(BG_MODE)), to_integer(H_CNT(2 downto 0)));

process( RST_N, CLK, BF, BG_MODE, BG_SIZE, BG_SC_ADDR, BG_SC_SIZE, BG_NBA, BG_HOFS, BG_VOFS, H_CNT, V_CNT, IN_VBL, FORCE_BLANK,
			BG_DATA, BG_TILE_INFO, BG3_OPT_DATA0, BG3_OPT_DATA1, BG_MOSAIC_Y ,BG_MOSAIC_EN, FIELD, HIRES, BGINTERLACE, VRAM_DAI,
			M7_SCREEN_X, M7_TEMP_X, M7_TEMP_Y, M7_TILE_N, M7_TILE_COL, M7_TILE_ROW, M7SEL, M7HOFS, M7VOFS, M7X, M7Y, M7A, M7B, M7C, M7D)
variable SCREEN_X : unsigned(8 downto 0);
variable SCREEN_Y : unsigned(7 downto 0);
variable OPTH_EN, OPTV_EN : std_logic;
variable IS_OPT : std_logic;
variable OPT_HOFS, OPT_VOFS : unsigned(9 downto 0);
variable MOSAIC_Y : unsigned(7 downto 0);
variable TILE_INFO_N : unsigned(9 downto 0);
variable TILE_INFO_HFLIP : std_logic;
variable TILE_INFO_VFLIP : std_logic;
variable TILE_X : unsigned(5 downto 0);
variable TILE_Y : unsigned(5 downto 0);
variable OFFSET_X : unsigned(9 downto 0);
variable OFFSET_Y : unsigned(9 downto 0);
variable TILE_N : unsigned(9 downto 0);
variable OFFSET : unsigned(11 downto 0);
variable TILE_INC : unsigned(4 downto 0);
variable FLIP_Y : unsigned(2 downto 0);
variable TILE_OFFS : unsigned(14 downto 0);
variable TILEPOS_INC : unsigned(4 downto 0);
variable M7_VRAM_X, M7_VRAM_Y : signed(23 downto 0);
variable ORG_X, ORG_Y : signed(13 downto 0);
variable M7_X, M7_Y : signed(8 downto 0);
variable M7_TILE : unsigned(7 downto 0);
variable BG_TILEMAP_ADDR, BG_TILEDATA_ADDR : unsigned(15 downto 0);
variable M7_VRAM_ADDRA, M7_VRAM_ADDRB : unsigned(13 downto 0);
variable M7_IS_OUTSIDE : std_logic;
begin
	case BG_MODE is
		when "000" =>
			BG_TILE_INFO(0) <= BG_DATA(3);
			BG_TILE_INFO(1) <= BG_DATA(2);
			BG_TILE_INFO(2) <= BG_DATA(1);
			BG_TILE_INFO(3) <= BG_DATA(0);
		when "001" =>
			BG_TILE_INFO(0) <= BG_DATA(2);
			BG_TILE_INFO(1) <= BG_DATA(1);
			BG_TILE_INFO(2) <= BG_DATA(0);
			BG_TILE_INFO(3) <= (others => '0');
		when others =>
			BG_TILE_INFO(0) <= BG_DATA(1);
			BG_TILE_INFO(1) <= BG_DATA(0);
			BG_TILE_INFO(2) <= (others => '0');
			BG_TILE_INFO(3) <= (others => '0');
	end case;
	
	SCREEN_X := H_CNT;
	SCREEN_Y := V_CNT(7 downto 0);

	if BG_MOSAIC_EN(BF.BG) = '0' then
		MOSAIC_Y    := SCREEN_Y;
	else
		MOSAIC_Y    := SCREEN_Y   - BG_MOSAIC_Y;
	end if;
	
	-- MODE 0-6
	IS_OPT := (BG_MODE(2) or BG_MODE(1)) and (not BG_MODE(0));	-- MODE 2,4,6
	
	case BF.BG is
		when BG1 => 
			OPTH_EN := (BG_MODE(1) and BG3_OPT_DATA0(13)) or (not BG_MODE(1) and not BG3_OPT_DATA0(15) and BG3_OPT_DATA0(13));
			OPTV_EN := (BG_MODE(1) and BG3_OPT_DATA1(13)) or (not BG_MODE(1) and     BG3_OPT_DATA0(15) and BG3_OPT_DATA0(13));
		when BG2 => 
			OPTH_EN := (BG_MODE(1) and BG3_OPT_DATA0(14)) or (not BG_MODE(1) and not BG3_OPT_DATA0(15) and BG3_OPT_DATA0(14));
			OPTV_EN := (BG_MODE(1) and BG3_OPT_DATA1(14)) or (not BG_MODE(1) and     BG3_OPT_DATA0(15) and BG3_OPT_DATA0(14));
		when others => 
			OPTH_EN := '0';
			OPTV_EN := '0';
	end case;
	
	OPT_HOFS := unsigned(BG3_OPT_DATA0(9 downto 0));
	if BG_MODE(1) = '0' then
		OPT_VOFS := unsigned(BG3_OPT_DATA0(9 downto 0));
	else
		OPT_VOFS := unsigned(BG3_OPT_DATA1(9 downto 0));
	end if;
	
	TILE_INFO_N := unsigned(BG_TILE_INFO(BF.BG)(9 downto 0));
	TILE_INFO_HFLIP := BG_TILE_INFO(BF.BG)(14);
	TILE_INFO_VFLIP := BG_TILE_INFO(BF.BG)(15);
			
	if BF.MODE = BF_OPT0 then
		OFFSET_X := resize(SCREEN_X(8 downto 3)&"000", OFFSET_X'length) + unsigned(BG_HOFS(BF.BG));
	elsif BF.MODE = BF_OPT1 then
		OFFSET_X := resize(SCREEN_X(8 downto 3)&"000", OFFSET_X'length) + unsigned(BG_HOFS(BF.BG));
	else
		if IS_OPT = '1' and OPTH_EN = '1' then	--OPT
			OFFSET_X := resize(SCREEN_X(8 downto 3)&"000", OFFSET_X'length) + (OPT_HOFS(9 downto 3) & unsigned(BG_HOFS(BF.BG)(2 downto 0)));
		else
			OFFSET_X := resize(SCREEN_X(8 downto 3)&"000", OFFSET_X'length) + unsigned(BG_HOFS(BF.BG));
		end if;
	end if;

	
	if BF.MODE = BF_OPT0 then
		OFFSET_Y := unsigned(BG_VOFS(BF.BG));
	elsif BF.MODE = BF_OPT1 then
		OFFSET_Y := unsigned(BG_VOFS(BF.BG)) + 8;
	else
		if IS_OPT = '1' and OPTV_EN = '1' then	--OPT
			OFFSET_Y := resize(MOSAIC_Y, OFFSET_Y'length) + OPT_VOFS;
		elsif HIRES = '1' and BGINTERLACE = '1' then
			OFFSET_Y := resize(MOSAIC_Y & FIELD, OFFSET_Y'length) + unsigned(BG_VOFS(BF.BG));
		else
			OFFSET_Y := resize(MOSAIC_Y, OFFSET_Y'length) + unsigned(BG_VOFS(BF.BG));
		end if;
	end if;
	
	if BG_SIZE(BF.BG) = '0' or HIRES = '1' then
		TILE_X := OFFSET_X(8 downto 3);
	else
		TILE_X := OFFSET_X(9 downto 4);
	end if;
	if BG_SIZE(BF.BG) = '0' then
		TILE_Y := OFFSET_Y(8 downto 3);
	else
		TILE_Y := OFFSET_Y(9 downto 4);
	end if;
	
	case BG_SC_SIZE(BF.BG) is
		when "00" =>
			OFFSET := "00" & TILE_Y(4 downto 0) & TILE_X(4 downto 0);
		when "01" =>
			OFFSET := "0" & TILE_X(5) & TILE_Y(4 downto 0) & TILE_X(4 downto 0); 
		when "10" =>
			OFFSET := "0" & TILE_Y(5) & TILE_Y(4 downto 0) & TILE_X(4 downto 0); 
		when others =>
			OFFSET := TILE_Y(5) & TILE_X(5) & TILE_Y(4 downto 0) & TILE_X(4 downto 0); 
	end case;
	BG_TILEMAP_ADDR := (resize(unsigned(BG_SC_ADDR(BF.BG)),BG_TILEMAP_ADDR'length) sll 10) + resize(OFFSET,BG_TILEMAP_ADDR'length);
	
	if BG_SIZE(BF.BG) = '0'then
		TILE_INC := (others => '0');
	elsif BG_SIZE(BF.BG) = '1' and HIRES = '1' then
		TILE_INC := (OFFSET_Y(3) xor TILE_INFO_VFLIP) & "0000";
	else
		TILE_INC := (OFFSET_Y(3) xor TILE_INFO_VFLIP) & "000" & (OFFSET_X(3) xor TILE_INFO_HFLIP);
	end if;
	TILE_N := TILE_INFO_N + resize(TILE_INC,TILE_N'length);
	
	if TILE_INFO_VFLIP = '0' then
		FLIP_Y := OFFSET_Y(2 downto 0);
	else
		FLIP_Y := not OFFSET_Y(2 downto 0);
	end if;
	
	case BG_MODE is
		when "000" =>
			TILE_OFFS := resize((TILE_N & FLIP_Y),TILE_OFFS'length);
		when "001" =>
			if BF.BG = BG1 or BF.BG = BG2 then
				TILE_OFFS := resize((TILE_N & "0" & FLIP_Y),TILE_OFFS'length);
			else
				TILE_OFFS := resize((TILE_N & FLIP_Y),TILE_OFFS'length);
			end if;
		when "010" =>
			TILE_OFFS := resize((TILE_N & "0" & FLIP_Y),TILE_OFFS'length);
		when "011" =>
			if BF.BG = BG1 then
				TILE_OFFS := resize((TILE_N & "00" & FLIP_Y),TILE_OFFS'length);
			else
				TILE_OFFS := resize((TILE_N & "0" & FLIP_Y),TILE_OFFS'length);
			end if;
		when "100" =>
			if BF.BG = BG1 then
				TILE_OFFS := resize((TILE_N & "00" & FLIP_Y),TILE_OFFS'length);
			else
				TILE_OFFS := resize((TILE_N & FLIP_Y),TILE_OFFS'length);
			end if;
		when "101" =>
			if BF.BG = BG1 then
				TILE_OFFS := resize((TILE_N & "0" & FLIP_Y),TILE_OFFS'length);
			else
				TILE_OFFS := resize((TILE_N & FLIP_Y),TILE_OFFS'length);
			end if;
		when others =>
			TILE_OFFS := resize((TILE_N & "0" & FLIP_Y),TILE_OFFS'length);
	end case;
	
	case BF.MODE is
		when BF_TILEDAT1 =>
			TILEPOS_INC := "01000";	--8
		when BF_TILEDAT2 =>
			TILEPOS_INC := "10000";	--16
		when BF_TILEDAT3 =>
			TILEPOS_INC := "11000";	--24
		when others =>
			TILEPOS_INC := "00000";	--0
	end case;
	BG_TILEDATA_ADDR := (resize(unsigned(BG_NBA(BF.BG)),BG_TILEDATA_ADDR'length) sll 12) + TILE_OFFS + TILEPOS_INC;
	
	-- MODE 7
	ORG_X := signed(resize(signed(M7HOFS), ORG_X'length)) - signed(resize(signed(M7X), ORG_X'length));
	ORG_Y := signed(resize(signed(M7VOFS), ORG_Y'length)) - signed(resize(signed(M7Y), ORG_Y'length));
	
	if M7SEL(0) = '0' then
		M7_X := signed(resize(M7_SCREEN_X, 9));
	else
		M7_X := signed(resize(not M7_SCREEN_X, 9));
	end if;
	
	if M7SEL(1) = '0' then
		M7_Y := signed(resize(MOSAIC_Y, 9));
	else
		M7_Y := signed(resize(not MOSAIC_Y, 9));
	end if;
				
	MPY <= resize(signed(M7A) * signed(M7B(15 downto 8)), MPY'length);
	
	M7_VRAM_X := M7_TEMP_X + resize(signed(M7A) * M7_X, M7_VRAM_X'length);
	M7_VRAM_Y := M7_TEMP_Y + resize(signed(M7C) * M7_X, M7_VRAM_Y'length);
					 
	if M7_VRAM_X(23 downto 18) = "000000" and M7_VRAM_Y(23 downto 18) = "000000" then
		M7_IS_OUTSIDE := '0';
	else
		M7_IS_OUTSIDE := '1';
	end if;
	
	if M7SEL(7 downto 6) = "11" and M7_IS_OUTSIDE = '1' then 
		M7_TILE := x"00";
	else 
		M7_TILE := unsigned(VRAM_DAI);
	end if;
			
	M7_VRAM_ADDRA := unsigned(M7_VRAM_Y(17 downto 11)) & unsigned(M7_VRAM_X(17 downto 11));
	M7_VRAM_ADDRB := M7_TILE_N & M7_TILE_ROW & M7_TILE_COL;
	
	case BF.MODE is
		when BF_TILEDATM7 => 
			BG_VRAM_ADDRA <= "00"&std_logic_vector(M7_VRAM_ADDRA);
			BG_VRAM_ADDRB <= "00"&std_logic_vector(M7_VRAM_ADDRB);
		when BF_TILEMAP | BF_OPT0 | BF_OPT1 => 
			BG_VRAM_ADDRA <= std_logic_vector(BG_TILEMAP_ADDR);
			BG_VRAM_ADDRB <= std_logic_vector(BG_TILEMAP_ADDR);
		when others => 
			BG_VRAM_ADDRA <= std_logic_vector(BG_TILEDATA_ADDR);
			BG_VRAM_ADDRB <= std_logic_vector(BG_TILEDATA_ADDR);
	end case;
	
	if RST_N = '0' then
		M7_SCREEN_X <= (others => '0');

		M7_TILE_N <= (others => '0');
		M7_TILE_ROW <= (others => '0');
		M7_TILE_COL <= (others => '0');
		M7_TILE_OUTSIDE <= '0';
	elsif rising_edge(CLK) then 
		if ENABLE = '1' and DOT_CLKR_CE = '1' then
			if M7_FETCH = '1' then
				M7_SCREEN_X <= M7_SCREEN_X + 1;
			elsif H_CNT = LAST_DOT then
				M7_SCREEN_X <= (others => '0');
			end if;
			
			if H_CNT = M7_XY_LATCH then
				M7_TEMP_X <= (resize(signed(M7X), M7_TEMP_X'length) sll 8) + 
								 (resize(signed(M7A) * Mode7Clip(ORG_X), M7_TEMP_X'length) and x"FFFFC0") + 
								 (resize(signed(M7B) * Mode7Clip(ORG_Y), M7_TEMP_X'length) and x"FFFFC0") + 
								 (resize(signed(M7B) * M7_Y, M7_TEMP_X'length) and x"FFFFC0");
				M7_TEMP_Y <= (resize(signed(M7Y), M7_TEMP_Y'length) sll 8) + 
								 (resize(signed(M7C) * Mode7Clip(ORG_X), M7_TEMP_Y'length) and x"FFFFC0") + 
								 (resize(signed(M7D) * Mode7Clip(ORG_Y), M7_TEMP_Y'length) and x"FFFFC0") + 
								 (resize(signed(M7D) * M7_Y, M7_TEMP_Y'length) and x"FFFFC0");
			end if;

			M7_TILE_N <= M7_TILE;
			M7_TILE_COL <= unsigned(M7_VRAM_X(10 downto 8));
			M7_TILE_ROW <= unsigned(M7_VRAM_Y(10 downto 8));
			M7_TILE_OUTSIDE <= M7_IS_OUTSIDE;
		end if;
	end if;
end process;

process( RST_N, CLK )
variable M7_PIX : std_logic_vector(7 downto 0);
begin
	if RST_N = '0' then
		BG_DATA <= (others => (others => '0'));
		BG3_OPT_DATA0 <= (others => '0');
		BG3_OPT_DATA1 <= (others => '0');
		BG_MOSAIC_Y <= (others => '0');
		BG_FORCE_BLANK <= '1';
	elsif rising_edge(CLK) then 
		if ENABLE = '1' and DOT_CLKR_CE = '1' then
			if H_CNT = LAST_DOT and V_CNT <= LAST_VIS_LINE then
				BG_DATA <= (others => (others => '0'));
				BG3_OPT_DATA0 <= (others => '0');
				BG3_OPT_DATA1 <= (others => '0');
			end if;
			
			if H_CNT = LAST_DOT and V_CNT >= 1 and V_CNT <= LAST_VIS_LINE then
				if BG_MOSAIC_Y = unsigned(MOSAIC_SIZE) then
					BG_MOSAIC_Y <= (others => '0');
				else
					BG_MOSAIC_Y <= BG_MOSAIC_Y + 1;
				end if;
			elsif H_CNT = LAST_DOT and V_CNT = LAST_LINE then
				BG_MOSAIC_Y <= (others => '0');
			end if;

			if BG_FETCH = '0' then
				BG_FORCE_BLANK <= FORCE_BLANK;
			elsif BG_FETCH = '1' and H_CNT(2 downto 0) = 0 then
				BG_FORCE_BLANK <= FORCE_BLANK;
			end if;
			
			if BG_FETCH = '1' and BG_FORCE_BLANK = '0' then
				if BG_MODE /= "111" then 
					BG_DATA(to_integer(H_CNT(2 downto 0))) <= VRAM_DBI & VRAM_DAI;
				end if;
				
				if H_CNT(2 downto 0) = 0 then
					case BG_MODE is
						when "000" =>
							BG_TILES(0).PLANES( 0) <= FlipPlane(BG_DATA(7)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 1) <= FlipPlane(BG_DATA(7)(15 downto 8), BG_TILE_INFO(BG1)(14));
							
							BG_TILES(0).PLANES( 8) <= FlipPlane(BG_DATA(6)( 7 downto 0), BG_TILE_INFO(BG2)(14));
							BG_TILES(0).PLANES( 9) <= FlipPlane(BG_DATA(6)(15 downto 8), BG_TILE_INFO(BG2)(14));
							
							BG_TILES(0).PLANES( 4) <= FlipPlane(BG_DATA(5)( 7 downto 0), BG_TILE_INFO(BG3)(14));
							BG_TILES(0).PLANES( 5) <= FlipPlane(BG_DATA(5)(15 downto 8), BG_TILE_INFO(BG3)(14));
							
							BG_TILES(0).PLANES( 6) <= FlipPlane(BG_DATA(4)( 7 downto 0), BG_TILE_INFO(BG4)(14));
							BG_TILES(0).PLANES( 7) <= FlipPlane(BG_DATA(4)(15 downto 8), BG_TILE_INFO(BG4)(14));
							
						when "001" =>
							BG_TILES(0).PLANES( 0) <= FlipPlane(BG_DATA(6)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 1) <= FlipPlane(BG_DATA(6)(15 downto 8), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 2) <= FlipPlane(BG_DATA(7)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 3) <= FlipPlane(BG_DATA(7)(15 downto 8), BG_TILE_INFO(BG1)(14));
							
							BG_TILES(0).PLANES( 8) <= FlipPlane(BG_DATA(4)( 7 downto 0), BG_TILE_INFO(BG2)(14));
							BG_TILES(0).PLANES( 9) <= FlipPlane(BG_DATA(4)(15 downto 8), BG_TILE_INFO(BG2)(14));
							BG_TILES(0).PLANES(10) <= FlipPlane(BG_DATA(5)( 7 downto 0), BG_TILE_INFO(BG2)(14));
							BG_TILES(0).PLANES(11) <= FlipPlane(BG_DATA(5)(15 downto 8), BG_TILE_INFO(BG2)(14));
							
							BG_TILES(0).PLANES( 4) <= FlipPlane(BG_DATA(3)( 7 downto 0), BG_TILE_INFO(BG3)(14));
							BG_TILES(0).PLANES( 5) <= FlipPlane(BG_DATA(3)(15 downto 8), BG_TILE_INFO(BG3)(14));
							
						when "010" =>
							BG_TILES(0).PLANES( 0) <= FlipPlane(BG_DATA(6)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 1) <= FlipPlane(BG_DATA(6)(15 downto 8), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 2) <= FlipPlane(BG_DATA(7)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 3) <= FlipPlane(BG_DATA(7)(15 downto 8), BG_TILE_INFO(BG1)(14));
							
							BG_TILES(0).PLANES( 8) <= FlipPlane(BG_DATA(4)( 7 downto 0), BG_TILE_INFO(BG2)(14));
							BG_TILES(0).PLANES( 9) <= FlipPlane(BG_DATA(4)(15 downto 8), BG_TILE_INFO(BG2)(14));
							BG_TILES(0).PLANES(10) <= FlipPlane(BG_DATA(5)( 7 downto 0), BG_TILE_INFO(BG2)(14));
							BG_TILES(0).PLANES(11) <= FlipPlane(BG_DATA(5)(15 downto 8), BG_TILE_INFO(BG2)(14));
						
						when "011" =>
							BG_TILES(0).PLANES( 0) <= FlipPlane(BG_DATA(4)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 1) <= FlipPlane(BG_DATA(4)(15 downto 8), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 2) <= FlipPlane(BG_DATA(5)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 3) <= FlipPlane(BG_DATA(5)(15 downto 8), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 4) <= FlipPlane(BG_DATA(6)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 5) <= FlipPlane(BG_DATA(6)(15 downto 8), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 6) <= FlipPlane(BG_DATA(7)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 7) <= FlipPlane(BG_DATA(7)(15 downto 8), BG_TILE_INFO(BG1)(14));
							
							BG_TILES(0).PLANES( 8) <= FlipPlane(BG_DATA(2)( 7 downto 0), BG_TILE_INFO(BG2)(14));
							BG_TILES(0).PLANES( 9) <= FlipPlane(BG_DATA(2)(15 downto 8), BG_TILE_INFO(BG2)(14));
							BG_TILES(0).PLANES(10) <= FlipPlane(BG_DATA(3)( 7 downto 0), BG_TILE_INFO(BG2)(14));
							BG_TILES(0).PLANES(11) <= FlipPlane(BG_DATA(3)(15 downto 8), BG_TILE_INFO(BG2)(14));
							
						when "100" =>
							BG_TILES(0).PLANES( 0) <= FlipPlane(BG_DATA(4)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 1) <= FlipPlane(BG_DATA(4)(15 downto 8), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 2) <= FlipPlane(BG_DATA(5)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 3) <= FlipPlane(BG_DATA(5)(15 downto 8), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 4) <= FlipPlane(BG_DATA(6)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 5) <= FlipPlane(BG_DATA(6)(15 downto 8), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 6) <= FlipPlane(BG_DATA(7)( 7 downto 0), BG_TILE_INFO(BG1)(14));
							BG_TILES(0).PLANES( 7) <= FlipPlane(BG_DATA(7)(15 downto 8), BG_TILE_INFO(BG1)(14));
							
							BG_TILES(0).PLANES( 8) <= FlipPlane(BG_DATA(3)( 7 downto 0), BG_TILE_INFO(BG2)(14));
							BG_TILES(0).PLANES( 9) <= FlipPlane(BG_DATA(3)(15 downto 8), BG_TILE_INFO(BG2)(14));
						
						when "101" =>
							BG_TILES(0).PLANES( 0) <= FlipBGPlaneHR(BG_DATA(4)( 7 downto 0) & BG_DATA(6)( 7 downto 0), BG_TILE_INFO(BG1)(14), '0');
							BG_TILES(0).PLANES( 1) <= FlipBGPlaneHR(BG_DATA(4)(15 downto 8) & BG_DATA(6)(15 downto 8), BG_TILE_INFO(BG1)(14), '0');
							BG_TILES(0).PLANES( 2) <= FlipBGPlaneHR(BG_DATA(5)( 7 downto 0) & BG_DATA(7)( 7 downto 0), BG_TILE_INFO(BG1)(14), '0');
							BG_TILES(0).PLANES( 3) <= FlipBGPlaneHR(BG_DATA(5)(15 downto 8) & BG_DATA(7)(15 downto 8), BG_TILE_INFO(BG1)(14), '0');
							BG_TILES(0).PLANES( 4) <= FlipBGPlaneHR(BG_DATA(4)( 7 downto 0) & BG_DATA(6)( 7 downto 0), BG_TILE_INFO(BG1)(14), '1');
							BG_TILES(0).PLANES( 5) <= FlipBGPlaneHR(BG_DATA(4)(15 downto 8) & BG_DATA(6)(15 downto 8), BG_TILE_INFO(BG1)(14), '1');
							BG_TILES(0).PLANES( 6) <= FlipBGPlaneHR(BG_DATA(5)( 7 downto 0) & BG_DATA(7)( 7 downto 0), BG_TILE_INFO(BG1)(14), '1');
							BG_TILES(0).PLANES( 7) <= FlipBGPlaneHR(BG_DATA(5)(15 downto 8) & BG_DATA(7)(15 downto 8), BG_TILE_INFO(BG1)(14), '1');
							
							BG_TILES(0).PLANES( 8) <= FlipBGPlaneHR(BG_DATA(2)( 7 downto 0) & BG_DATA(3)( 7 downto 0), BG_TILE_INFO(BG2)(14), '0');
							BG_TILES(0).PLANES( 9) <= FlipBGPlaneHR(BG_DATA(2)(15 downto 8) & BG_DATA(3)(15 downto 8), BG_TILE_INFO(BG2)(14), '0');
							BG_TILES(0).PLANES(10) <= FlipBGPlaneHR(BG_DATA(2)( 7 downto 0) & BG_DATA(3)( 7 downto 0), BG_TILE_INFO(BG2)(14), '1');
							BG_TILES(0).PLANES(11) <= FlipBGPlaneHR(BG_DATA(2)(15 downto 8) & BG_DATA(3)(15 downto 8), BG_TILE_INFO(BG2)(14), '1');
						
						when "110" =>
							BG_TILES(0).PLANES( 0) <= FlipBGPlaneHR(BG_DATA(4)( 7 downto 0) & BG_DATA(6)( 7 downto 0), BG_TILE_INFO(BG1)(14), '0');
							BG_TILES(0).PLANES( 1) <= FlipBGPlaneHR(BG_DATA(4)(15 downto 8) & BG_DATA(6)(15 downto 8), BG_TILE_INFO(BG1)(14), '0');
							BG_TILES(0).PLANES( 2) <= FlipBGPlaneHR(BG_DATA(5)( 7 downto 0) & BG_DATA(7)( 7 downto 0), BG_TILE_INFO(BG1)(14), '0');
							BG_TILES(0).PLANES( 3) <= FlipBGPlaneHR(BG_DATA(5)(15 downto 8) & BG_DATA(7)(15 downto 8), BG_TILE_INFO(BG1)(14), '0');
							BG_TILES(0).PLANES( 4) <= FlipBGPlaneHR(BG_DATA(4)( 7 downto 0) & BG_DATA(6)( 7 downto 0), BG_TILE_INFO(BG1)(14), '1');
							BG_TILES(0).PLANES( 5) <= FlipBGPlaneHR(BG_DATA(4)(15 downto 8) & BG_DATA(6)(15 downto 8), BG_TILE_INFO(BG1)(14), '1');
							BG_TILES(0).PLANES( 6) <= FlipBGPlaneHR(BG_DATA(5)( 7 downto 0) & BG_DATA(7)( 7 downto 0), BG_TILE_INFO(BG1)(14), '1');
							BG_TILES(0).PLANES( 7) <= FlipBGPlaneHR(BG_DATA(5)(15 downto 8) & BG_DATA(7)(15 downto 8), BG_TILE_INFO(BG1)(14), '1');
							
						when others => null;
					end case;

					BG_TILES(0).ATR(0) <= BG_TILE_INFO(BG1)(13 downto 10);
					BG_TILES(0).ATR(1) <= BG_TILE_INFO(BG2)(13 downto 10);
					BG_TILES(0).ATR(2) <= BG_TILE_INFO(BG3)(13 downto 10);
					BG_TILES(0).ATR(3) <= BG_TILE_INFO(BG4)(13 downto 10);
					BG_TILES(1) <= BG_TILES(0);
				end if;
				
				if H_CNT(2 downto 0) = 7 then
					BG3_OPT_DATA0 <= BG_DATA(2);
					BG3_OPT_DATA1 <= BG_DATA(3);
				end if;
			end if;
			
		end if;
	end if;
end process;


--Sprites engine
OAM : entity work.dpram_dif generic map(8,16,7,32)
port map(
	clock			=> CLK,
	data_a		=> OAM_D,
	address_a	=> OAM_ADDR_A,
	address_b	=> OAM_ADDR_B,
	wren_a		=> OAM_WE,
	q_a			=> OAMIO_Q,
	q_b			=> OAM_Q
);
OAM_D <= DI & OAM_latch;
OAM_ADDR_A <= OAM_ADDR(8 downto 1);
OAM_ADDR_B <= OAM_ADDR(8 downto 2);
OAM_WE <= ENABLE when (OAM_ADDR(9) = '0' or (IN_VBL = '0' and FORCE_BLANK = '0')) and OAM_ADDR(0) = '1' and PAWR_N = '0' and PA = x"04" and SYSCLK_CE = '1' else '0';

HOAM : entity work.spram generic map(5,8)
port map(
	clock		=> CLK,
	data		=> DI,
	address	=> HOAM_ADDR,
	wren		=> HOAM_WE,
	q			=> HOAM_Q
);
HOAM_ADDR <= OAM_ADDR(8 downto 4) when IN_VBL = '0' and FORCE_BLANK = '0' else
				 OAM_ADDR(4 downto 0);
HOAM_WE <= ENABLE when (OAM_ADDR(9) = '1' or (IN_VBL = '0' and FORCE_BLANK = '0')) and PAWR_N = '0' and PA = x"04" and SYSCLK_CE = '1' else '0';

HOAM_X8 <= HOAM_Q(to_integer(unsigned(OAM_ADDR(3 downto 2))&"0"));
HOAM_S  <= HOAM_Q(to_integer(unsigned(OAM_ADDR(3 downto 2))&"1"));


process( RST_N, CLK )
variable SCREEN_Y 		: unsigned(7 downto 0);
variable X 					: unsigned(8 downto 0);
variable Y 					: unsigned(7 downto 0);
variable W, H, H2 		: unsigned(5 downto 0);
variable NEW_RANGE_CNT 	: unsigned(5 downto 0);
variable TILE_X 			: unsigned(8 downto 0);
variable CUR_TILES_CNT 	: unsigned(2 downto 0);
variable OAM_OBJ_X			: unsigned(8 downto 0);
variable OAM_OBJ_Y			: unsigned(7 downto 0);
variable OAM_OBJ_S 			: std_logic;
variable OAM_OBJ_TILE	: unsigned(7 downto 0);
variable OAM_OBJ_N		: std_logic;
variable OAM_OBJ_PAL		: std_logic_vector(2 downto 0);
variable OAM_OBJ_PRIO	: std_logic_vector(1 downto 0);
variable OAM_OBJ_HFLIP	: std_logic;
variable OAM_OBJ_VFLIP	: std_logic;
variable TEMP 				: unsigned(5 downto 0);
begin
	if RST_N = '0' then
		RANGE_CNT <= (others => '1');
		OAM_RANGE <= (others => (others => '0'));
		TILES_OAM_CNT <= (others => '0');
		TILES_CNT <= (others => '0');
		OBJ_RANGE_OFL <= '0';
		OBJ_TIME_OFL <= '0';
		OBJ_RANGE_DONE <= '0';
		OBJ_TIME_DONE <= '0';
		OBJ_TIME_SAVE <= '0';
		OAM_TIME_INDEX <= (others => '0');
		OBJ_TILE_LINE <= (others => '0');
		OBJ_TILE_COL <= (others => '0');
		OBJ_TILE_ROW <= (others => '0');
		OBJ_TILE_GAP <= (others => '0');
		OBJ_TILE_HFLIP <= '0';
		OBJ_TILE_PAL <= (others => '0');
		OBJ_TILE_PRIO <= (others => '0');
		OBJ_TILE_X <= (others => '0');
		SPR_TILE_DATA <= (others => '0');
		SPR_TILE_X <= (others => '0');
		SPR_TILE_PAL <= (others => '0');
		SPR_TILE_PRIO <= (others => '0');
		SPR_TILE_DATA_TEMP <= (others => '0');
	elsif rising_edge(CLK) then 
		if ENABLE = '1' and  DOT_CLKR_CE = '1' then
			if H_CNT = LAST_DOT and V_CNT < LAST_VIS_LINE then
				RANGE_CNT <= (others => '1');
				if RANGE_CNT(5) /= '1' and TILES_OAM_CNT = 34 then
					OBJ_TIME_OFL <= '1';
				end if;
				OBJ_RANGE_DONE <= '0';
			end if;
			
			if H_CNT = LAST_DOT and V_CNT = LAST_LINE then
				OBJ_RANGE_OFL <= '0';
				OBJ_TIME_OFL <= '0';
			end if;
			
			OAM_OBJ_X := HOAM_X8 & unsigned(OAM_Q(7 downto 0));
			OAM_OBJ_Y := unsigned(OAM_Q(15 downto 8));
			OAM_OBJ_S := HOAM_S;	
			OAM_OBJ_TILE := unsigned(OAM_Q(23 downto 16));
			OAM_OBJ_N := OAM_Q(24);
			OAM_OBJ_PAL := OAM_Q(27 downto 25);
			OAM_OBJ_PRIO := OAM_Q(29 downto 28);
			OAM_OBJ_HFLIP := OAM_Q(30);
			OAM_OBJ_VFLIP := OAM_Q(31);
					
			SCREEN_Y := V_CNT(7 downto 0);
			W := SprWidth(OAM_OBJ_S & OBJSIZE);
			H := SprHeight(OAM_OBJ_S & OBJSIZE);
			if OBJINTERLACE = '1' then
				H2 := (H srl 1);
			else
				H2 := H;
			end if;		
			
			if OBJ_RANGE = '1' and H_CNT(0) = '1' and FORCE_BLANK = '0' then
				if (OAM_OBJ_X <= 256 or (0 - OAM_OBJ_X) <= W) and (SCREEN_Y - OAM_OBJ_Y) <= H2 then
					if OBJ_RANGE_DONE = '0' then
						NEW_RANGE_CNT := RANGE_CNT + 1;
						OAM_RANGE(to_integer(NEW_RANGE_CNT(4 downto 0))) <= OAM_ADDR(8 downto 2);
						RANGE_CNT <= NEW_RANGE_CNT;
						if NEW_RANGE_CNT = 31 then
							OBJ_RANGE_DONE <= '1';
						end if;
					elsif OBJ_RANGE_OFL = '0' then
						OBJ_RANGE_OFL <= '1';
					end if;
				end if;
			end if;
			
			
			if H_CNT = OBJ_TIME_START-1 and V_CNT < LAST_VIS_LINE then
				if RANGE_CNT(5) /= '1' then
					OAM_TIME_INDEX <= OAM_RANGE(to_integer(RANGE_CNT(4 downto 0)));
				end if;
			end if;
			
			if H_CNT = OBJ_TIME_START-1 and V_CNT < LAST_VIS_LINE then
				TILES_OAM_CNT <= (others => '0');
				TILES_CNT <= (others => '0');
				OBJ_TIME_DONE <= '1';
			end if;
			
			if OBJ_TIME = '1' and H_CNT(0) = '1' then
				if RANGE_CNT(5) /= '1' then
					if OAM_OBJ_X(8) = '1' and TILES_CNT = 0 then
						TEMP := 0 - unsigned(OAM_OBJ_X(5 downto 0));
						CUR_TILES_CNT := TEMP(5 downto 3);
					else
						CUR_TILES_CNT := TILES_CNT;
					end if;
					
					if OAM_OBJ_VFLIP = '0' then
						Y := SCREEN_Y - OAM_OBJ_Y;
					else
						Y := not (SCREEN_Y - OAM_OBJ_Y);
					end if;
					if OBJINTERLACE = '1' then
						Y := (Y(6 downto 0) & FIELD);
					end if;
					OBJ_TILE_LINE <= Y(2 downto 0);

					if OAM_OBJ_HFLIP = '0' then
						OBJ_TILE_COL <= unsigned(OAM_OBJ_TILE(3 downto 0)) + CUR_TILES_CNT;
					else
						OBJ_TILE_COL <= unsigned(OAM_OBJ_TILE(3 downto 0)) + ((not CUR_TILES_CNT) and W(5 downto 3));
					end if;
					OBJ_TILE_ROW <= unsigned(OAM_OBJ_TILE(7 downto 4)) + (Y(5 downto 3) and H(5 downto 3));
					if OAM_OBJ_N = '0' then
						OBJ_TILE_GAP <= (others => '0');
					else
						OBJ_TILE_GAP <= 4096 + (resize(unsigned(OBJNAME), OBJ_TILE_GAP'length) sll 12);
					end if;
					
					TILE_X := OAM_OBJ_X + (resize(CUR_TILES_CNT,9) sll 3);
					
					OBJ_TILE_HFLIP <= OAM_OBJ_HFLIP;
					OBJ_TILE_PAL <= OAM_OBJ_PAL ;
					OBJ_TILE_PRIO <= OAM_OBJ_PRIO;
					OBJ_TILE_X <= TILE_X;
					
					TILES_OAM_CNT <= TILES_OAM_CNT + 1;
					TILES_CNT <= CUR_TILES_CNT + 1;
					if CUR_TILES_CNT = W(5 downto 3) or ((TILE_X + 8) >= 256 and OAM_OBJ_X /= 256) then
						NEW_RANGE_CNT := RANGE_CNT - 1;
						TILES_CNT <= (others => '0');
						RANGE_CNT <= NEW_RANGE_CNT;
						if NEW_RANGE_CNT(5) /= '1' then
							OAM_TIME_INDEX <= OAM_RANGE(to_integer(NEW_RANGE_CNT(4 downto 0)));
						end if;
					end if;
					
					OBJ_TIME_DONE <= '0';
				else
					OBJ_TIME_DONE <= '1';
				end if;
			end if;
			
			if OBJ_FETCH = '1' and FORCE_BLANK = '0' then 
				if OBJ_TIME_DONE = '0' then
					case H_CNT(0) is
						when '0' =>
							SPR_TILE_DATA_TEMP <= FlipPlane(VRAM_DBI, OBJ_TILE_HFLIP) & FlipPlane(VRAM_DAI, OBJ_TILE_HFLIP);
						when others =>
							SPR_TILE_DATA <= FlipPlane(VRAM_DBI, OBJ_TILE_HFLIP) & 
												  FlipPlane(VRAM_DAI, OBJ_TILE_HFLIP) & 
												  SPR_TILE_DATA_TEMP(15 downto 0);
							SPR_TILE_X <= OBJ_TILE_X;
							SPR_TILE_PAL <= OBJ_TILE_PAL;
							SPR_TILE_PRIO <= OBJ_TILE_PRIO;
					end case;
				end if;
			end if;
				
			if OBJ_FETCH = '1' and OBJ_TIME_DONE = '0' and H_CNT(0) = '1' then 
				OBJ_TIME_SAVE <= '1';
			elsif OBJ_TIME_SAVE = '1' and H_CNT(0) = '1' then
				OBJ_TIME_SAVE <= '0';
			end if;
		end if;
	end if;
end process;

OBJ_VRAM_ADDR <= std_logic_vector( (resize(unsigned(OBJADDR), OBJ_VRAM_ADDR'length) sll 13) + 
												resize(OBJ_TILE_GAP, OBJ_VRAM_ADDR'length) + 
												resize((OBJ_TILE_ROW & OBJ_TILE_COL & H_CNT(0) & OBJ_TILE_LINE), OBJ_VRAM_ADDR'length) );


process( RST_N, CLK )
variable X : unsigned(8 downto 0);
variable PIX_DATA : std_logic_vector(3 downto 0);
begin
	if RST_N = '0' then
		SPR_PIX_WE_A <= '0';
		SPR_PIX_D <= (others => '0');
		SPR_PIX_ADDR_A <= (others => '0');
		SPR_PIX_CNT <= (others => '0');
	elsif rising_edge(CLK) then 
		SPR_PIX_WE_A <= '0';
		if OBJ_TIME_SAVE = '1' and CLK_CNT(2) = '0' then
			X := SPR_TILE_X + SPR_PIX_CNT;
			case SPR_PIX_CNT is
				when "000" => PIX_DATA := SPR_TILE_DATA(31-0) & SPR_TILE_DATA(23-0) & SPR_TILE_DATA(15-0) & SPR_TILE_DATA(7-0);
				when "001" => PIX_DATA := SPR_TILE_DATA(31-1) & SPR_TILE_DATA(23-1) & SPR_TILE_DATA(15-1) & SPR_TILE_DATA(7-1);
				when "010" => PIX_DATA := SPR_TILE_DATA(31-2) & SPR_TILE_DATA(23-2) & SPR_TILE_DATA(15-2) & SPR_TILE_DATA(7-2);
				when "011" => PIX_DATA := SPR_TILE_DATA(31-3) & SPR_TILE_DATA(23-3) & SPR_TILE_DATA(15-3) & SPR_TILE_DATA(7-3);
				when "100" => PIX_DATA := SPR_TILE_DATA(31-4) & SPR_TILE_DATA(23-4) & SPR_TILE_DATA(15-4) & SPR_TILE_DATA(7-4);
				when "101" => PIX_DATA := SPR_TILE_DATA(31-5) & SPR_TILE_DATA(23-5) & SPR_TILE_DATA(15-5) & SPR_TILE_DATA(7-5);
				when "110" => PIX_DATA := SPR_TILE_DATA(31-6) & SPR_TILE_DATA(23-6) & SPR_TILE_DATA(15-6) & SPR_TILE_DATA(7-6);
				when others => PIX_DATA := SPR_TILE_DATA(31-7) & SPR_TILE_DATA(23-7) & SPR_TILE_DATA(15-7) & SPR_TILE_DATA(7-7);
			end case;
			
			if X(8) = '0' and PIX_DATA /= "0000" then
				SPR_PIX_D <= SPR_TILE_PRIO & SPR_TILE_PAL & PIX_DATA;
				SPR_PIX_ADDR_A <= std_logic_vector(X(7 downto 0));
				SPR_PIX_WE_A <= '1';
			end if;
			SPR_PIX_CNT <= SPR_PIX_CNT + 1;
		end if;
	end if;
end process;

SPR_BUF : entity work.dpram generic map(8,9)
port map(
	clock			=> CLK,
	data_a		=> SPR_PIX_D,
	address_a	=> SPR_PIX_ADDR_A,
	address_b	=> std_logic_vector(SPR_PIXEL_X),
	wren_a		=> SPR_PIX_WE_A,
	wren_b		=> SPR_PIX_WE_B,
	q_b			=> SPR_PIX_Q
);
SPR_PIX_WE_B <= '1' when SPR_GET_PIXEL = '1' and DOT_CLKR_CE = '1'  else '0';

process( RST_N, CLK )
begin
	if RST_N = '0' then
		SPR_PIX_DATA_BUF <= (others => '0');
		SPR_PIXEL_X <= (others => '0');
	elsif rising_edge(CLK) then 
		if ENABLE = '1' and DOT_CLKR_CE = '1' then
			if H_CNT = LAST_DOT and V_CNT >= 1 and V_CNT <= LAST_VIS_LINE then
				SPR_PIXEL_X <= (others => '0');
			end if;

			if SPR_GET_PIXEL = '1' then
				SPR_PIX_DATA_BUF <= SPR_PIX_Q;
				
				if M7SEL(7 downto 6) = "10" and M7_TILE_OUTSIDE = '1' then 
					M7_PIX_DATA <= (others => '0');
				else  
					M7_PIX_DATA <= VRAM_DBI;
				end if;
			
				SPR_PIXEL_X <= SPR_PIXEL_X + 1;
			end if;
		end if;
	end if;
end process;


process( RST_N, CLK )
variable N1,N2,N3,N4	: unsigned(3 downto 0);
begin
	if RST_N = '0' then
		GET_PIXEL_X <= (others => '0');
		BG1_PIX_DATA <= (others => '0');
		BG2_PIX_DATA <= (others => '0');
		BG3_PIX_DATA <= (others => '0');
		BG4_PIX_DATA <= (others => '0');
		SPR_PIX_DATA <= (others => '0');
	elsif rising_edge(CLK) then 
		if ENABLE = '1' and DOT_CLKR_CE = '1' then
			if H_CNT = LAST_DOT and V_CNT >= 1 and V_CNT <= LAST_VIS_LINE then
				GET_PIXEL_X <= (others => '0');
				BG_MOSAIC_X <= (others => '0');
			end if;
			
			if BG_GET_PIXEL = '1' then
				if BG_MOSAIC_EN(BG1) = '0' or BG_MOSAIC_X = 0  then
					if BG_MODE /= "111" then
						N1 := not (("0"&GET_PIXEL_X(2 downto 0)) + ("0"&unsigned(BG_HOFS(BG1)(2 downto 0))));
						BG1_PIX_DATA <= BG_TILES(to_integer(N1(3 downto 3))).ATR(BG1) &
											 BG_TILES(to_integer(N1(3 downto 3))).PLANES(7)(to_integer(N1(2 downto 0))) &
											 BG_TILES(to_integer(N1(3 downto 3))).PLANES(6)(to_integer(N1(2 downto 0))) &
											 BG_TILES(to_integer(N1(3 downto 3))).PLANES(5)(to_integer(N1(2 downto 0))) &
											 BG_TILES(to_integer(N1(3 downto 3))).PLANES(4)(to_integer(N1(2 downto 0))) &
											 BG_TILES(to_integer(N1(3 downto 3))).PLANES(3)(to_integer(N1(2 downto 0))) &
											 BG_TILES(to_integer(N1(3 downto 3))).PLANES(2)(to_integer(N1(2 downto 0))) &
											 BG_TILES(to_integer(N1(3 downto 3))).PLANES(1)(to_integer(N1(2 downto 0))) &
											 BG_TILES(to_integer(N1(3 downto 3))).PLANES(0)(to_integer(N1(2 downto 0)));
					else
						BG1_PIX_DATA <= "0000" & M7_PIX_DATA;
					end if;
				end if;
				
				if BG_MOSAIC_EN(BG2) = '0' or BG_MOSAIC_X = 0  then
					if BG_MODE /= "111" then
						N2 := not (("0"&GET_PIXEL_X(2 downto 0)) + ("0"&unsigned(BG_HOFS(BG2)(2 downto 0))));
						BG2_PIX_DATA <= BG_TILES(to_integer(N2(3 downto 3))).ATR(BG2) &
											 BG_TILES(to_integer(N2(3 downto 3))).PLANES(11)(to_integer(N2(2 downto 0))) &
											 BG_TILES(to_integer(N2(3 downto 3))).PLANES(10)(to_integer(N2(2 downto 0))) &
											 BG_TILES(to_integer(N2(3 downto 3))).PLANES( 9)(to_integer(N2(2 downto 0))) &
											 BG_TILES(to_integer(N2(3 downto 3))).PLANES( 8)(to_integer(N2(2 downto 0)));
					else
						BG2_PIX_DATA <= M7_PIX_DATA;
					end if;
				end if;
				
				if BG_MOSAIC_EN(BG3) = '0' or BG_MOSAIC_X = 0  then
					N3 := not (("0"&GET_PIXEL_X(2 downto 0)) + ("0"&unsigned(BG_HOFS(BG3)(2 downto 0))));
					BG3_PIX_DATA <= BG_TILES(to_integer(N3(3 downto 3))).ATR(BG3) &
										 BG_TILES(to_integer(N3(3 downto 3))).PLANES(5)(to_integer(N3(2 downto 0))) &
										 BG_TILES(to_integer(N3(3 downto 3))).PLANES(4)(to_integer(N3(2 downto 0)));
				end if;
				
				if BG_MOSAIC_EN(BG4) = '0' or BG_MOSAIC_X = 0  then				 
					N4 := not (("0"&GET_PIXEL_X(2 downto 0)) + ("0"&unsigned(BG_HOFS(BG4)(2 downto 0))));
					BG4_PIX_DATA <= BG_TILES(to_integer(N4(3 downto 3))).ATR(BG4) &
										 BG_TILES(to_integer(N4(3 downto 3))).PLANES(7)(to_integer(N4(2 downto 0))) &
										 BG_TILES(to_integer(N4(3 downto 3))).PLANES(6)(to_integer(N4(2 downto 0)));
				end if;
				
				GET_PIXEL_X <= GET_PIXEL_X + 1;
				
				
				if BG_MOSAIC_X = unsigned(MOSAIC_SIZE) then
					BG_MOSAIC_X <= (others => '0');
				else
					BG_MOSAIC_X <= BG_MOSAIC_X + 1;
				end if;
				
				SPR_PIX_DATA <= SPR_PIX_DATA_BUF;
			end if;
		end if;
	end if;
end process;


process( RST_N, CLK, WH0, WH1, WH2, WH3, W12SEL, W34SEL, WOBJSEL, WBGLOG, WOBJLOG, CGWSEL, CGADSUB, TMW, TSW, TM, TS, BG_MODE, BG3PRIO, M7EXTBG,
			WINDOW_X, SPR_PIX_DATA, BG1_PIX_DATA, BG2_PIX_DATA, BG3_PIX_DATA, BG4_PIX_DATA, DOT_CLK, BG_EN)
variable PAL1,PAL2,PAL3,PAL4,OBJ_PAL : std_logic_vector(7 downto 0);
variable PRIO1,PRIO2,PRIO3,PRIO4 : std_logic;
variable BGPR0EN, BGPR1EN : std_logic_vector(3 downto 0);
variable OBJPR0EN,OBJPR1EN,OBJPR2EN,OBJPR3EN : std_logic;
variable OBJ_PRIO : std_logic_vector(1 downto 0);
variable win1, win2, win1en, win2en, bglog0, bglog1, winres : std_logic_vector(5 downto 0);
variable main_dis, sub_dis : std_logic_vector(4 downto 0);
variable MAIN_EN, SUB_EN, SUB_MATH_EN, MATH_EN : std_logic;
variable DCM, BD, MATH : std_logic;
variable COLOR	: std_logic_vector(14 downto 0);
variable COLOR_MASK : std_logic_vector(4 downto 0);
variable MATH_R, MATH_G, MATH_B	: unsigned(4 downto 0);
variable HALF : std_logic;
begin
	if WINDOW_X >= unsigned(WH0) and WINDOW_X <= unsigned(WH1) then
		win1 := not (WOBJSEL(4)&WOBJSEL(0)&W34SEL(4)&W34SEL(0)&W12SEL(4)&W12SEL(0));
	else
		win1 := WOBJSEL(4)&WOBJSEL(0)&W34SEL(4)&W34SEL(0)&W12SEL(4)&W12SEL(0);
	end if;
	if WINDOW_X >= unsigned(WH2) and WINDOW_X <= unsigned(WH3) then
		win2 := not (WOBJSEL(6)&WOBJSEL(2)&W34SEL(6)&W34SEL(2)&W12SEL(6)&W12SEL(2));
	else
		win2 := WOBJSEL(6)&WOBJSEL(2)&W34SEL(6)&W34SEL(2)&W12SEL(6)&W12SEL(2);
	end if;
	win1en := WOBJSEL(5)&WOBJSEL(1)&W34SEL(5)&W34SEL(1)&W12SEL(5)&W12SEL(1);
	win2en := WOBJSEL(7)&WOBJSEL(3)&W34SEL(7)&W34SEL(3)&W12SEL(7)&W12SEL(3);
	bglog0 := WOBJLOG(2)&WOBJLOG(0)&WBGLOG(6)&WBGLOG(4)&WBGLOG(2)&WBGLOG(0);
	bglog1 := WOBJLOG(3)&WOBJLOG(1)&WBGLOG(7)&WBGLOG(5)&WBGLOG(3)&WBGLOG(1);
	
	for i in 0 to 5 loop
		if win1en(i) = '0' and win2en(i) = '0' then
			winres(i) := '0';
		elsif win1en(i) = '1' and win2en(i) = '0' then
			winres(i) := win1(i);
		elsif win1en(i) = '0' and win2en(i) = '1' then
			winres(i) := win2(i);
		else
			if bglog1(i) = '0' and bglog0(i) = '0' then
				winres(i) := win1(i) or win2(i);
			elsif bglog1(i) = '0' and bglog0(i) = '1' then
				winres(i) := win1(i) and win2(i);
			elsif bglog1(i) = '1' and bglog0(i) = '0' then
				winres(i) := win1(i) xor win2(i);
			else
				winres(i) := not(win1(i) xor win2(i));
			end if;
		end if;
		
	end loop;
	for i in 0 to 4 loop
		main_dis(i) := winres(i) and TMW(i);
		sub_dis(i) := winres(i) and TSW(i);
	end loop;
	
	case CGWSEL(7 downto 6) is
		when "00" => MAIN_EN := '1';
		when "01" => MAIN_EN := winres(5);
		when "10" => MAIN_EN := not winres(5);
		when "11" => MAIN_EN := '0';
		when others => null;
	end case;
	case CGWSEL(5 downto 4) is
		when "00" => SUB_EN := '1';
		when "01" => SUB_EN := winres(5);
		when "10" => SUB_EN := not winres(5);
		when "11" => SUB_EN := '0';
		when others => null;
	end case;
	
	BD := '0';
	DCM := '0';
	MATH := '0';
	
	OBJ_PRIO := SPR_PIX_DATA(8 downto 7);

	PRIO1 := BG1_PIX_DATA(11);
	PRIO2 := BG2_PIX_DATA(7);
	PRIO3 := BG3_PIX_DATA(5);
	PRIO4 := BG4_PIX_DATA(5);
	
	if DOT_CLK = '1' then
		BGPR0EN(0) := TS(0) and (not sub_dis(0)) and (not PRIO1) and BG_EN(0);
		BGPR0EN(1) := TS(1) and (not sub_dis(1)) and (not PRIO2) and BG_EN(1);
		BGPR0EN(2) := TS(2) and (not sub_dis(2)) and (not PRIO3) and BG_EN(2);
		BGPR0EN(3) := TS(3) and (not sub_dis(3)) and (not PRIO4) and BG_EN(3);
		BGPR1EN(0) := TS(0) and (not sub_dis(0)) and (    PRIO1) and BG_EN(0);
		BGPR1EN(1) := TS(1) and (not sub_dis(1)) and (    PRIO2) and BG_EN(1);
		BGPR1EN(2) := TS(2) and (not sub_dis(2)) and (    PRIO3) and BG_EN(2);
		BGPR1EN(3) := TS(3) and (not sub_dis(3)) and (    PRIO4) and BG_EN(3);
		OBJPR0EN := TS(4) and (not sub_dis(4)) and (not OBJ_PRIO(0)) and (not OBJ_PRIO(1)) and BG_EN(4);
		OBJPR1EN := TS(4) and (not sub_dis(4)) and (    OBJ_PRIO(0)) and (not OBJ_PRIO(1)) and BG_EN(4);
		OBJPR2EN := TS(4) and (not sub_dis(4)) and (not OBJ_PRIO(0)) and (    OBJ_PRIO(1)) and BG_EN(4);
		OBJPR3EN := TS(4) and (not sub_dis(4)) and (    OBJ_PRIO(0)) and (    OBJ_PRIO(1)) and BG_EN(4);
	else
		BGPR0EN(0) := TM(0) and (not main_dis(0)) and (not PRIO1) and BG_EN(0);
		BGPR0EN(1) := TM(1) and (not main_dis(1)) and (not PRIO2) and BG_EN(1);
		BGPR0EN(2) := TM(2) and (not main_dis(2)) and (not PRIO3) and BG_EN(2);
		BGPR0EN(3) := TM(3) and (not main_dis(3)) and (not PRIO4) and BG_EN(3);
		BGPR1EN(0) := TM(0) and (not main_dis(0)) and (    PRIO1) and BG_EN(0);
		BGPR1EN(1) := TM(1) and (not main_dis(1)) and (    PRIO2) and BG_EN(1);
		BGPR1EN(2) := TM(2) and (not main_dis(2)) and (    PRIO3) and BG_EN(2);
		BGPR1EN(3) := TM(3) and (not main_dis(3)) and (    PRIO4) and BG_EN(3);
		OBJPR0EN := TM(4) and (not main_dis(4)) and (not OBJ_PRIO(0)) and (not OBJ_PRIO(1)) and BG_EN(4);
		OBJPR1EN := TM(4) and (not main_dis(4)) and (    OBJ_PRIO(0)) and (not OBJ_PRIO(1)) and BG_EN(4);
		OBJPR2EN := TM(4) and (not main_dis(4)) and (not OBJ_PRIO(0)) and (    OBJ_PRIO(1)) and BG_EN(4);
		OBJPR3EN := TM(4) and (not main_dis(4)) and (    OBJ_PRIO(0)) and (    OBJ_PRIO(1)) and BG_EN(4);
	end if;
	
	if BG_MODE = "000" then	-- MODE0
		if SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR3EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(1 downto 0) /= "00" and BGPR1EN(0) = '1' then
			CGRAM_FETCH_ADDR <= "000" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(1 downto 0);
			MATH := CGADSUB(0);
		elsif BG2_PIX_DATA(1 downto 0) /= "00" and BGPR1EN(1) = '1' then
			CGRAM_FETCH_ADDR <= "001" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(1 downto 0);
			MATH := CGADSUB(1);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR2EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(1 downto 0) /= "00" and BGPR0EN(0) = '1' then
			CGRAM_FETCH_ADDR <= "000" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(1 downto 0);
			MATH := CGADSUB(0);
		elsif BG2_PIX_DATA(1 downto 0) /= "00" and BGPR0EN(1) = '1' then
			CGRAM_FETCH_ADDR <= "001" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(1 downto 0);
			MATH := CGADSUB(1);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR1EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG3_PIX_DATA(1 downto 0) /= "00" and BGPR1EN(2) = '1' then
			CGRAM_FETCH_ADDR <= "010" & BG3_PIX_DATA(4 downto 2) & BG3_PIX_DATA(1 downto 0);
			MATH := CGADSUB(2);
		elsif BG4_PIX_DATA(1 downto 0) /= "00" and BGPR1EN(3) = '1' then
			CGRAM_FETCH_ADDR <= "011" & BG4_PIX_DATA(4 downto 2) & BG4_PIX_DATA(1 downto 0);
			MATH := CGADSUB(3);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR0EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG3_PIX_DATA(1 downto 0) /= "00" and BGPR0EN(2) = '1' then
			CGRAM_FETCH_ADDR <= "010" & BG3_PIX_DATA(4 downto 2) & BG3_PIX_DATA(1 downto 0);
			MATH := CGADSUB(2);
		elsif BG4_PIX_DATA(1 downto 0) /= "00" and BGPR0EN(3) = '1' then
			CGRAM_FETCH_ADDR <= "011" & BG4_PIX_DATA(4 downto 2) & BG4_PIX_DATA(1 downto 0);
			MATH := CGADSUB(3);
		else
			CGRAM_FETCH_ADDR <= (others => '0');
			MATH := CGADSUB(5);
			BD := '1';
		end if;
		
	elsif BG_MODE = "001" then	-- MODE1
		if BG3_PIX_DATA(1 downto 0) /= "00" and BGPR1EN(2) = '1' and BG3PRIO = '1' then
			CGRAM_FETCH_ADDR <= "000" & BG3_PIX_DATA(4 downto 2) & BG3_PIX_DATA(1 downto 0);
			MATH := CGADSUB(2);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR3EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(3 downto 0) /= "0000" and BGPR1EN(0) = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(3 downto 0);
			MATH := CGADSUB(0);
		elsif BG2_PIX_DATA(3 downto 0) /= "0000" and BGPR1EN(1) = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(3 downto 0);
			MATH := CGADSUB(1);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR2EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(3 downto 0) /= "0000" and BGPR0EN(0) = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(3 downto 0);
			MATH := CGADSUB(0);
		elsif BG2_PIX_DATA(3 downto 0) /= "0000" and BGPR0EN(1) = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(3 downto 0);
			MATH := CGADSUB(1);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR1EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG3_PIX_DATA(1 downto 0) /= "00" and BGPR1EN(2) = '1' and BG3PRIO = '0' then
			CGRAM_FETCH_ADDR <= "000" & BG3_PIX_DATA(4 downto 2) & BG3_PIX_DATA(1 downto 0);
			MATH := CGADSUB(2);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR0EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG3_PIX_DATA(1 downto 0) /= "00" and BGPR0EN(2) = '1' then
			CGRAM_FETCH_ADDR <= "000" & BG3_PIX_DATA(4 downto 2) & BG3_PIX_DATA(1 downto 0);
			MATH := CGADSUB(2);
		else
			CGRAM_FETCH_ADDR <= (others => '0');
			MATH := CGADSUB(5);
			BD := '1';
		end if;
		
	elsif BG_MODE = "010" then	-- MODE2
		if SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR3EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(3 downto 0) /= "0000" and BGPR1EN(0) = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(3 downto 0);
			MATH := CGADSUB(0);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR2EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG2_PIX_DATA(3 downto 0) /= "0000" and BGPR1EN(1) = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(3 downto 0);
			MATH := CGADSUB(1);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR1EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(3 downto 0) /= "0000" and BGPR0EN(0) = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(3 downto 0);
			MATH := CGADSUB(0);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR0EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG2_PIX_DATA(3 downto 0) /= "0000" and BGPR0EN(1) = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(3 downto 0);
			MATH := CGADSUB(1);
		else
			CGRAM_FETCH_ADDR <= (others => '0');
			MATH := CGADSUB(5);
			BD := '1';
		end if;
		
	elsif BG_MODE = "011" then	-- MODE3
		if SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR3EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(7 downto 0) /= "00000000" and BGPR1EN(0) = '1' then
			CGRAM_FETCH_ADDR <= BG1_PIX_DATA(7 downto 0); 
			DCM := CGWSEL(0);
			MATH := CGADSUB(0);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR2EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG2_PIX_DATA(3 downto 0) /= "0000" and BGPR1EN(1) = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(3 downto 0);
			MATH := CGADSUB(1);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR1EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(7 downto 0) /= "00000000" and BGPR0EN(0) = '1' then
			CGRAM_FETCH_ADDR <= BG1_PIX_DATA(7 downto 0);
			DCM := CGWSEL(0);
			MATH := CGADSUB(0);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR0EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG2_PIX_DATA(3 downto 0) /= "0000" and BGPR0EN(1) = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(3 downto 0);
			MATH := CGADSUB(1);
		else
			CGRAM_FETCH_ADDR <= (others => '0');
			MATH := CGADSUB(5);
			BD := '1';
		end if;
		
	elsif BG_MODE = "100" then	-- MODE4
		if SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR3EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(7 downto 0) /= "00000000" and BGPR1EN(0) = '1' then
			CGRAM_FETCH_ADDR <= BG1_PIX_DATA(7 downto 0); 
			DCM := CGWSEL(0);
			MATH := CGADSUB(0);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR2EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG2_PIX_DATA(1 downto 0) /= "00" and BGPR1EN(1) = '1' then
			CGRAM_FETCH_ADDR <= "000" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(1 downto 0);
			MATH := CGADSUB(1);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR1EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(7 downto 0) /= "00000000" and BGPR0EN(0) = '1' then
			CGRAM_FETCH_ADDR <= BG1_PIX_DATA(7 downto 0); 
			DCM := CGWSEL(0);
			MATH := CGADSUB(0);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR0EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG2_PIX_DATA(1 downto 0) /= "00" and BGPR0EN(1) = '1' then
			CGRAM_FETCH_ADDR <= "000" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(1 downto 0);
			MATH := CGADSUB(1);
		else
			CGRAM_FETCH_ADDR <= (others => '0');
			MATH := CGADSUB(5);
			BD := '1';
		end if;
		
	elsif BG_MODE = "101" then	-- MODE5
		if SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR3EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(3 downto 0) /= "0000" and BGPR1EN(0) = '1' and DOT_CLK = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(3 downto 0);
		elsif BG1_PIX_DATA(7 downto 4) /= "0000" and BGPR1EN(0) = '1' and DOT_CLK = '0' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(7 downto 4);
			MATH := CGADSUB(0);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR2EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG2_PIX_DATA(1 downto 0) /= "00" and BGPR1EN(1) = '1' and DOT_CLK = '1' then
			CGRAM_FETCH_ADDR <= "000" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(1 downto 0);
		elsif BG2_PIX_DATA(3 downto 2) /= "00" and BGPR1EN(1) = '1' and DOT_CLK = '0' then
			CGRAM_FETCH_ADDR <= "000" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(3 downto 2);
			MATH := CGADSUB(1);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR1EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(3 downto 0) /= "0000" and BGPR0EN(0) = '1' and DOT_CLK = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(3 downto 0);
		elsif BG1_PIX_DATA(7 downto 4) /= "0000" and BGPR0EN(0) = '1' and DOT_CLK = '0' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(7 downto 4);
			MATH := CGADSUB(0);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR0EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG2_PIX_DATA(1 downto 0) /= "00" and BGPR0EN(1) = '1' and DOT_CLK = '1' then
			CGRAM_FETCH_ADDR <= "000" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(1 downto 0);
		elsif BG2_PIX_DATA(3 downto 2) /= "00" and BGPR0EN(1) = '1' and DOT_CLK = '0' then
			CGRAM_FETCH_ADDR <= "000" & BG2_PIX_DATA(6 downto 4) & BG2_PIX_DATA(3 downto 2);
			MATH := CGADSUB(1);
		else
			CGRAM_FETCH_ADDR <= (others => '0');
			MATH := CGADSUB(5);
			BD := '1';
		end if;
		
	elsif BG_MODE = "110" then	-- MODE6
		if SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR3EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(3 downto 0) /= "0000" and BGPR1EN(0) = '1' and DOT_CLK = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(3 downto 0);
		elsif BG1_PIX_DATA(7 downto 4) /= "0000" and BGPR1EN(0) = '1' and DOT_CLK = '0' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(7 downto 4);
			MATH := CGADSUB(0);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR2EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR1EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(3 downto 0) /= "0000" and BGPR0EN(0) = '1' and DOT_CLK = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(3 downto 0);
		elsif BG1_PIX_DATA(7 downto 4) /= "0000" and BGPR0EN(0) = '1' and DOT_CLK = '0' then
			CGRAM_FETCH_ADDR <= "0" & BG1_PIX_DATA(10 downto 8) & BG1_PIX_DATA(7 downto 4);
			MATH := CGADSUB(0);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR0EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		else
			CGRAM_FETCH_ADDR <= (others => '0');
			MATH := CGADSUB(5);
			BD := '1';
		end if;
		
	else	-- MODE7
		if SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR3EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR2EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG2_PIX_DATA(6 downto 0) /= "0000000" and BGPR1EN(1) = '1' and M7EXTBG = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG2_PIX_DATA(6 downto 0);
			MATH := CGADSUB(1);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR1EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG1_PIX_DATA(7 downto 0) /= "00000000" and BGPR0EN(0) = '1' then
			CGRAM_FETCH_ADDR <= BG1_PIX_DATA(7 downto 0);
			DCM := CGWSEL(0);
			MATH := CGADSUB(0);
		elsif SPR_PIX_DATA(3 downto 0) /= "0000" and OBJPR0EN = '1' then
			CGRAM_FETCH_ADDR <= "1" & SPR_PIX_DATA(6 downto 0);
			MATH := CGADSUB(4) and SPR_PIX_DATA(6);
		elsif BG2_PIX_DATA(6 downto 0) /= "0000000" and BGPR0EN(1) = '1' and M7EXTBG = '1' then
			CGRAM_FETCH_ADDR <= "0" & BG2_PIX_DATA(6 downto 0);
			MATH := CGADSUB(1);
		else
			CGRAM_FETCH_ADDR <= (others => '0');
			MATH := CGADSUB(5);
			BD := '1';
		end if;
	end if;

	
	if RST_N = '0' then
		WINDOW_X <= (others => '0');
		SUB_R <= (others => '0');
		SUB_G <= (others => '0');
		SUB_B <= (others => '0');
		MAIN_R <= (others => '0');
		MAIN_G <= (others => '0');
		MAIN_B <= (others => '0');
		SUB_BD <= '0';
		PREV_COLOR <= (others => '0');
		SUB_MATH_R <= (others => '0');
		SUB_MATH_G <= (others => '0');
		SUB_MATH_B <= (others => '0');
	elsif rising_edge(CLK) then 
		if ENABLE = '1' then
			if BG_GET_PIXEL = '1' and DOT_CLKR_CE = '1' then
				WINDOW_X <= GET_PIXEL_X;
			end if;

			if H_CNT = LAST_DOT and DOT_CLKR_CE = '1' then
				PREV_COLOR <= (others => '0');
			end if;

			if BG_MATH = '1' then
				if DOT_CLKF_CE = '1' then
					SUB_BD <= BD;
				end if;

				if DOT_CLKR_CE = '1' then
					MATH_EN := MATH;
					HALF := CGADSUB(6) and MAIN_EN and not (SUB_BD and CGWSEL(1));
					SUB_MATH_EN := CGWSEL(1) and not SUB_BD;

					if MAIN_EN = '0' then
						COLOR_MASK := "00000";
					else
						COLOR_MASK := "11111";
					end if;
				end if;

				if DOT_CLKF_CE = '1' or DOT_CLKR_CE = '1' then

					if DCM = '1' then
						COLOR := GetDCM(BG1_PIX_DATA(10 downto 0));
					else
						COLOR := CGRAM_Q;
					end if;
					PREV_COLOR <= COLOR;

					if FORCE_BLANK = '1' then
						MATH_R := (others => '0');
						MATH_G := (others => '0');
						MATH_B := (others => '0');
					elsif PSEUDOHIRES = '1' and BLEND = '1' then
						MATH_R := AddSub(unsigned(COLOR(4 downto 0) and COLOR_MASK), unsigned(PREV_COLOR(4 downto 0) and COLOR_MASK),  '1', '1');
						MATH_G := AddSub(unsigned(COLOR(9 downto 5) and COLOR_MASK), unsigned(PREV_COLOR(9 downto 5) and COLOR_MASK), '1', '1');
						MATH_B := AddSub(unsigned(COLOR(14 downto 10) and COLOR_MASK), unsigned(PREV_COLOR(14 downto 10) and COLOR_MASK), '1', '1');
					elsif MATH_EN = '1' and SUB_EN = '1' then
						if SUB_MATH_EN = '1' then
							MATH_R := AddSub(unsigned(COLOR(4 downto 0) and COLOR_MASK), unsigned(PREV_COLOR(4 downto 0)), not CGADSUB(7), HALF);
							MATH_G := AddSub(unsigned(COLOR(9 downto 5) and COLOR_MASK), unsigned(PREV_COLOR(9 downto 5)), not CGADSUB(7), HALF);
							MATH_B := AddSub(unsigned(COLOR(14 downto 10) and COLOR_MASK), unsigned(PREV_COLOR(14 downto 10)), not CGADSUB(7), HALF);
						else
							MATH_R := AddSub(unsigned(COLOR(4 downto 0) and COLOR_MASK), unsigned(SUBCOLBD(4 downto 0)), not CGADSUB(7), HALF);
							MATH_G := AddSub(unsigned(COLOR(9 downto 5) and COLOR_MASK), unsigned(SUBCOLBD(9 downto 5)), not CGADSUB(7), HALF);
							MATH_B := AddSub(unsigned(COLOR(14 downto 10) and COLOR_MASK), unsigned(SUBCOLBD(14 downto 10)), not CGADSUB(7), HALF);
						end if;
					else
						MATH_R := unsigned(COLOR(4 downto 0) and COLOR_MASK);
						MATH_G := unsigned(COLOR(9 downto 5) and COLOR_MASK);
						MATH_B := unsigned(COLOR(14 downto 10) and COLOR_MASK);
					end if;

					if DOT_CLKF_CE = '1' then
						SUB_MATH_R <= MATH_R;
						SUB_MATH_G <= MATH_G;
						SUB_MATH_B <= MATH_B;
					end if;

					if DOT_CLKR_CE = '1' then
						MAIN_R <= MATH_R;
						MAIN_G <= MATH_G;
						MAIN_B <= MATH_B;

						if HIRES = '1' or (PSEUDOHIRES = '1' and BLEND = '0') then
							SUB_R <= SUB_MATH_R;
							SUB_G <= SUB_MATH_G;
							SUB_B <= SUB_MATH_B;
						else 
							SUB_R <= MATH_R;
							SUB_G <= MATH_G;
							SUB_B <= MATH_B;
						end if;
					end if; 
				end if;
			end if;
		end if;
	end if;
end process;

process( RST_N, CLK)
begin
	if RST_N = '0' then
		OUT_Y <= (others => '0');
		OUT_X <= (others => '0');
	elsif rising_edge(CLK) then 
		if ENABLE = '1' and DOT_CLKR_CE = '1' then
			if H_CNT = LAST_DOT and V_CNT >= 1 and V_CNT <= LAST_VIS_LINE then
				OUT_Y <= OUT_Y + 1;
			end if;
			
			if H_CNT = LAST_DOT and V_CNT = LAST_LINE then
				OUT_Y <= (others => '0');
			end if;
			
			if BG_MATH = '1' then
				OUT_X <= WINDOW_X;
			end if;
		end if;
	end if;
end process;

COLOR_OUT <= Bright(MB, SUB_B) & Bright(MB, SUB_G) & Bright(MB, SUB_R) when DOT_CLK = '1' else
				 Bright(MB, MAIN_B) & Bright(MB, MAIN_G) & Bright(MB, MAIN_R);


DOTCLK <= DOT_CLK;
HBLANK <= IN_HBL;
VBLANK <= IN_VBL;
HIGH_RES <= HIRES or (PSEUDOHIRES and not BLEND);

FRAME_OUT <= BG_OUT;
X_OUT <= std_logic_vector(OUT_X & DOT_CLK);
Y_OUT <= std_logic_vector(FIELD & OUT_Y);
V224 <= not OVERSCAN;

FIELD_OUT <= FIELD;
INTERLACE <= BGINTERLACE;

end rtl;
