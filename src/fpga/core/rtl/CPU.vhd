library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;


entity SCPU is
	port(
		CLK				: in std_logic;
		RST_N				: in std_logic;
		ENABLE			: in std_logic;
		
		CA       		: out std_logic_vector(23 downto 0);
		CPURD_N			: out std_logic;
		CPUWR_N			: out std_logic;
		
		PA					: out std_logic_vector(7 downto 0);
		PARD_N			: out std_logic;
		PAWR_N			: out std_logic;
		DI					: in std_logic_vector(7 downto 0);
		DO					: out std_logic_vector(7 downto 0);
		
		RAMSEL_N			: out std_logic;
		ROMSEL_N			: out std_logic;
		
		JPIO67			: out std_logic_vector(7 downto 6);
		REFRESH			: out std_logic;
		
		SYSCLK			: out std_logic;
		SYSCLKF_CE		: out std_logic;
		SYSCLKR_CE		: out std_logic;

		HBLANK			: in std_logic;
		VBLANK			: in std_logic;
		
		IRQ_N				: in std_logic;
		
		JOY1_DI			: in std_logic_vector(1 downto 0);
		JOY2_DI			: in std_logic_vector(1 downto 0);
		JOY_STRB			: out std_logic;
		JOY1_CLK			: out std_logic;
		JOY2_CLK			: out std_logic;

		TURBO				: in std_logic;
		
		DBG_CPU_EN		: in std_logic
	);
end SCPU;

architecture rtl of SCPU is

	--clocks
	signal EN : std_logic;
	signal CLK4_CE_F, CLK4_CE_R, CLK8_CE_F, CLK8_CE_R : std_logic;
	signal INT_CLK : std_logic;
	signal INT_CLKR_CE, INT_CLKF_CE : std_logic;
	signal P65_CLK_CNT : unsigned(3 downto 0);
	signal DMA_CLK_CNT : unsigned(2 downto 0);
	constant DMA_LAST_CLOCK : unsigned(2 downto 0) := "111";
	constant DMA_MID_CLOCK : unsigned(2 downto 0) := "011";
	signal CPU_LAST_CLOCK : unsigned(3 downto 0);
	signal CPU_MID_CLOCK : unsigned(3 downto 0);
	signal CPU_ACTIVEr, DMA_ACTIVEr : std_logic;
	signal P65_RST_CNT : unsigned(7 downto 0);
	signal H_CNT : unsigned(8 downto 0);
	signal V_CNT : unsigned(8 downto 0);

	--65C816
	signal P65_R_WN : std_logic;
	signal P65_A : std_logic_vector(23 downto 0);
	signal P65_DO : std_logic_vector(7 downto 0);
	signal P65_DI : std_logic_vector(7 downto 0);
	signal P65_NMI_N, P65_IRQ_N : std_logic;
	signal P65_RST_N : std_logic;
	signal P65_EN : std_logic;
	signal P65_VPA, P65_VDA : std_logic;

	type speed_t is (
		XSLOW,
		SLOW,
		FAST,
		SLOWFAST
	);
	signal SPEED : speed_t; 

	--CPU BUS
	signal INT_A : std_logic_vector(23 downto 0);
	signal INT_CPUWR_N, INT_CPURD_N : std_logic;
	signal INT_RAMSEL_N, INT_ROMSEL_N : std_logic;
	signal IO_SEL : std_logic;
	signal CPU_WR, CPU_RD : std_logic;
	signal R40XX_41XX : std_logic;

	--DMA BUS
	signal DMA_A : std_logic_vector(23 downto 0);
	signal DMA_B : std_logic_vector(7 downto 0);
	signal DMA_DIR : std_logic;
	signal DMA_A_WR, HDMA_A_WR, DMA_A_RD, HDMA_A_RD : std_logic;
	signal DMA_B_WR, DMA_B_RD, HDMA_B_WR, HDMA_B_RD	: std_logic;

	-- CPU IO Registers
	signal MDR : std_logic_vector(7 downto 0);
	signal NMI_EN : std_logic;
	signal HVIRQ_EN : std_logic_vector(1 downto 0);
	signal AUTO_JOY_EN : std_logic;
	signal WRIO	: std_logic_vector(7 downto 0);
	signal WRMPYA : std_logic_vector(7 downto 0);
--	signal WRMPYB : std_logic_vector(7 downto 0);
	signal WRDIVA : std_logic_vector(15 downto 0);
--	signal WRDIVB : std_logic_vector(7 downto 0);
	signal HTIME : std_logic_vector(8 downto 0);
	signal VTIME : std_logic_vector(8 downto 0);
	signal MDMAEN : std_logic_vector(7 downto 0);
	signal HDMAEN : std_logic_vector(7 downto 0);
	signal MEMSEL : std_logic;
	signal RDDIV, RDMPY : std_logic_vector(15 downto 0);

	signal NMI_FLAG, IRQ_FLAG : std_logic;
	signal MUL_REQ, DIV_REQ : std_logic;
	signal MATH_CLK_CNT	: unsigned(3 downto 0);
	signal MATH_TEMP	: std_logic_vector(22 downto 0);
	signal HBLANK_FF, VBLANK_FF : std_logic_vector(1 downto 0);
	signal H6_VBLANK_FF : std_logic;
	signal FALLING_VBLANK, LONG_FALLING_VBLANK : std_logic;
	signal IRQ_TIME_FF : std_logic_vector(1 downto 0);
	signal IRQ_TIME_FF2 : std_logic;
	
	signal REFRESH_EN, REFRESH_EN2, REFRESH_EN3 : std_logic;
	signal REFRESHED : std_logic;

	-- DMA registers
	type DmaReg8 is array (0 to 7) of std_logic_vector(7 downto 0);
	type DmaReg16 is array (0 to 7) of std_logic_vector(15 downto 0);
	signal DMAP	: DmaReg8;
	signal BBAD	: DmaReg8;
	signal A1T	: DmaReg16;
	signal A1B	: DmaReg8;
	signal DAS	: DmaReg16;
	signal DASB	: DmaReg8;
	signal A2A	: DmaReg16;
	signal NTLR	: DmaReg8;
	signal UNUSED	: DmaReg8;

	signal DMA_CH, DMA_CH_IND, DMA_CH_LATCH: integer range 0 to 7;
	signal DMA_RUN, HDMA_RUN, DMA_PATTERN_END : std_logic;
	signal DMA_ACTIVE : std_logic;
	signal HDMA_CH_WORK, HDMA_CH_RUN, HDMA_CH_DO: std_logic_vector(7 downto 0);
	signal HDMA_CH_EN: std_logic_vector(7 downto 0);
	signal HDMA_EN, HDMA_START, HDMA_INIT_START : std_logic;
	signal DMA_CH_EN: std_logic_vector(7 downto 0);
	signal DMA_TRANSFER, HDMA_TRANSFER, FETCH_SCANLINE_COUNTER, FETCH_IND_ADDR, HDMA_BUS_ACTIVE : std_logic;
	signal HDMA_CH_LAST, HDMA_CH_LAST_IND : std_logic;
	signal LONG_FALLING_VBLANK_FF : std_logic;
	signal HDMA_HBLANK_EDGE, HDMA_VBLANK_EDGE : std_logic_vector(1 downto 0);

	type ds_t is (
		DS_IDLE,
		DS_INIT,
		DS_TRANSFER,
		DS_NEXT
	);
	signal DS : ds_t; 

	type hds_t is (
		HDS_IDLE,
		HDS_INIT,
		HDS_INIT_IND,
		HDS_INIT_END,
		HDS_TRANSFER
	);
	signal HDS	: hds_t; 

	signal HDMA_INIT_STEP: std_logic;
	signal DMA_TRMODE_STEP, HDMA_TRMODE_STEP: unsigned(1 downto 0);
	type DmaTransMode is array (0 to 7, 0 to 3) of unsigned(1 downto 0);
	constant DMA_TRMODE_TAB	: DmaTransMode := (
	("00","00","00","00"),
	("00","01","00","01"),
	("00","00","00","00"),
	("00","00","01","01"),
	("00","01","10","11"),
	("00","01","00","01"),
	("00","00","00","00"),
	("00","00","01","01")
	);
	type DmaTransLenth is array (0 to 7) of unsigned(1 downto 0);
	constant DMA_TRMODE_LEN	: DmaTransLenth := ("00","01","01","11","11","11","01","11");

	impure function GetDMACh(data: std_logic_vector(7 downto 0)) return integer is
		variable res: integer range 0 to 7; 
		variable b1,b2,b3,b4,b5,b6,b7: std_logic;
		variable v: unsigned(2 downto 0);
	begin
		b1 := not data(0) and data(1);
		b2 := not data(0) and not data(1) and data(2);
		b3 := not data(0) and not data(1) and not data(2) and data(3);
		b4 := not data(0) and not data(1) and not data(2) and not data(3) and data(4);
		b5 := not data(0) and not data(1) and not data(2) and not data(3) and not data(4) and data(5);
		b6 := not data(0) and not data(1) and not data(2) and not data(3) and not data(4) and not data(5) and data(6);
		b7 := not data(0) and not data(1) and not data(2) and not data(3) and not data(4) and not data(5) and not data(6) and data(7);
		
		v(0) := b1 or       b3 or       b5 or       b7;
		v(1) :=       b2 or b3 or             b6 or b7;
		v(2) :=                   b4 or b5 or b6 or b7;
		
		res := to_integer(v);
		return res;
	end function;

	impure function IsLastHDMACh(data: std_logic_vector(7 downto 0); ch: integer range 0 to 7) return std_logic is
		variable res: std_logic; 
		variable temp: unsigned(7 downto 0); 
	begin
		temp := unsigned(data) srl (ch+1);
		if temp = x"00" then
			res := '1';
		else
			res := '0';
		end if;
		return res;
	end function;

	-- JOY
	signal JOY1_DATA, JOY2_DATA, JOY3_DATA, JOY4_DATA : std_logic_vector(15 downto 0);
	signal AUTO_JOY_CLK: std_logic;
	signal OLD_JOY_STRB, AUTO_JOY_STRB: std_logic;
	signal OLD_JOY1_CLK, OLD_JOY2_CLK : std_logic;
	signal JOY_POLL_CLK : unsigned(5 downto 0);
	signal JOY_POLL_CNT : unsigned(4 downto 0);
	signal JOY_POLL_STRB : std_logic;
	signal JOYRD_BUSY : std_logic;
	signal JOY_POLL_RUN: std_logic;
	signal JOY_VBLANK_OLD: std_logic;

begin

	DMA_ACTIVE <= DMA_RUN or HDMA_RUN;
	
	process( SPEED, MEMSEL, REFRESHED, CPU_ACTIVEr, TURBO, INT_RAMSEL_N, INT_ROMSEL_N )	
	begin		
		-- Turbo should only occur when the cpu is ONLY accessing ram/rom, in otherwords during the main game loop	
		if TURBO = '1' and INT_RAMSEL_N = '0' and REFRESHED = '0' then
			CPU_MID_CLOCK <= x"1";
			CPU_LAST_CLOCK <= x"5";	
		elsif TURBO = '1' and INT_ROMSEL_N = '0' and REFRESHED = '0' then
			CPU_MID_CLOCK <= x"1";
			CPU_LAST_CLOCK <= x"3";
		elsif REFRESHED = '1' and CPU_ACTIVEr = '1' then	
			CPU_MID_CLOCK <= x"2";
			CPU_LAST_CLOCK <= x"7";	
		elsif SPEED = FAST or (SPEED = SLOWFAST and MEMSEL = '1') then	
			CPU_MID_CLOCK <= x"2";
			CPU_LAST_CLOCK <= x"5";	
		elsif SPEED = SLOW or (SPEED = SLOWFAST and MEMSEL = '0') then	
			CPU_MID_CLOCK <= x"2";
			CPU_LAST_CLOCK <= x"7";	
		else	
			CPU_MID_CLOCK <= x"2";
			CPU_LAST_CLOCK <= x"B";	
		end if;	
	end process;

	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			P65_CLK_CNT <= (others => '0');
			DMA_CLK_CNT <= (others => '0');
			CPU_ACTIVEr <= '1';
			DMA_ACTIVEr <= '0';
			P65_RST_CNT <= (others => '0');
			P65_RST_N <= '0';
		elsif rising_edge(CLK) then
			DMA_CLK_CNT <= DMA_CLK_CNT + 1;
			if DMA_CLK_CNT = DMA_LAST_CLOCK  then
				DMA_CLK_CNT <= (others => '0');
			end if;

			P65_CLK_CNT <= P65_CLK_CNT + 1;
			if P65_CLK_CNT >= CPU_LAST_CLOCK  then
				P65_CLK_CNT <= (others => '0');
			end if;

			if DMA_ACTIVEr = '0' and DMA_ACTIVE = '1' and DMA_CLK_CNT = DMA_LAST_CLOCK and REFRESHED = '0' then
				DMA_ACTIVEr <= '1';
			elsif DMA_ACTIVEr = '1' and DMA_ACTIVE = '0' and REFRESHED = '0' then
				DMA_ACTIVEr <= '0';
			end if;
			
			if CPU_ACTIVEr = '1' and DMA_ACTIVE = '1' and DMA_ACTIVEr = '0' and REFRESHED = '0' then
				CPU_ACTIVEr <= '0';
			elsif CPU_ACTIVEr = '0' and DMA_ACTIVE = '0' and P65_CLK_CNT >= CPU_LAST_CLOCK and REFRESHED = '0' then
				CPU_ACTIVEr <= '1';
			end if;
			
			if P65_RST_CNT = 150 - 1 then
				P65_RST_N <= '1';
			else
				P65_RST_CNT <= P65_RST_CNT + 1;
			end if;
		end if;
	end process;
	CLK4_CE_F <= '1' when DMA_CLK_CNT(1 downto 0) = "01" else '0';
	CLK4_CE_R <= '1' when DMA_CLK_CNT(1 downto 0) = "11" else '0';
	CLK8_CE_F <= '1' when DMA_CLK_CNT(2 downto 0) = "011" else '0';
	CLK8_CE_R <= '1' when DMA_CLK_CNT(2 downto 0) = "111" else '0';
	
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			INT_CLKF_CE <= '0';
			INT_CLKR_CE <= '0';
			INT_CLK <= '1';
		elsif rising_edge(CLK) then
			INT_CLKF_CE <= '0';
			INT_CLKR_CE <= '0';
			if DMA_ACTIVEr = '1' or ENABLE = '0' then
				if DMA_CLK_CNT = DMA_MID_CLOCK then
					INT_CLKR_CE <= '1';
				elsif DMA_CLK_CNT = DMA_LAST_CLOCK then
					INT_CLKF_CE <= '1';
				end if;
			elsif CPU_ACTIVEr = '1' then
				if P65_CLK_CNT = CPU_MID_CLOCK then
					INT_CLKR_CE <= '1';
				elsif P65_CLK_CNT >= CPU_LAST_CLOCK  then
					INT_CLKF_CE <= '1';
				end if;
			end if;
			
			if INT_CLKR_CE = '1' then
				INT_CLK <= '1';
			elsif INT_CLKF_CE = '1' then
				INT_CLK <= '0';
			end if;
		end if;
	end process;

	EN <= ENABLE and (not REFRESHED);
	P65_EN <= not DMA_ACTIVE and ENABLE;

	SYSCLK <= INT_CLK; 
	SYSCLKF_CE <= INT_CLKF_CE;
	SYSCLKR_CE <= INT_CLKR_CE;


	-- 65C816
	P65C816: entity work.P65C816 
	port map (
		CLK         => CLK,
		RST_N       => P65_RST_N,
		CE       	=> (not REFRESHED) and INT_CLKF_CE and DBG_CPU_EN,
		
		WE          => P65_R_WN,
		D_IN     	=> P65_DI,
		D_OUT    	=> P65_DO,
		A_OUT			=> P65_A,
		RDY_IN      => P65_EN,
		NMI_N       => P65_NMI_N,    
		IRQ_N       => P65_IRQ_N,
		ABORT_N     => '1',
		VPA      	=> P65_VPA,
		VDA      	=> P65_VDA
	); 

	process(P65_A, P65_VPA, P65_VDA)
	begin
		SPEED <= SLOW;
		R40XX_41XX <= '0';
		
		if P65_VPA = '0' and P65_VDA = '0' then 
			SPEED <= FAST;
		elsif P65_A(22) = '0' then 						--$00-$3F, $80-$BF | System Area 
			if P65_A(15 downto 9) = "0100000" then 	--$4000-$41FF | XSlow
				SPEED <= XSLOW;
				R40XX_41XX <= '1';
			elsif P65_A(15 downto 13) = "000" or 		--$0000-$1FFF | Slow
					P65_A(15 downto 13) = "011" then 	--$6000-$7FFF | Slow
				SPEED <= SLOW;
			elsif P65_A(15) = '1' then 					--$8000-$FFFF | Fast,Slow
				if P65_A(23) = '0' then
					SPEED <= SLOW;
				else
					SPEED <= SLOWFAST;
				end if;
			else
				SPEED <= FAST;
			end if;
		elsif P65_A(23 downto 22) = "01" then			--$40-$7D | $0000-$FFFF | Slow
			SPEED <= SLOW;										--$7E-$7F | $0000-$FFFF | Slow
		elsif P65_A(23 downto 22) = "11" then			--$C0-$FF | $0000-$FFFF | Fast,Slow
			SPEED <= SLOWFAST;
		end if;
	end process;


	INT_A <= DMA_A when HDMA_RUN = '1' or DMA_RUN = '1' else
				P65_A;
			
	process(INT_A)
	begin
		INT_RAMSEL_N <= '1';
		INT_ROMSEL_N <= '1';
		
		CA <= INT_A;

		if INT_A(22) = '0' then 							--$00-$3F, $80-$BF
			if INT_A(15 downto 13) = "000" then			--$0000-$1FFF | Slow  | Address Bus A + /WRAM (mirror $7E:0000-$1FFF)
				CA(23 downto 13) <= x"7E" & "000";
				INT_RAMSEL_N <= '0';
			elsif INT_A(15) = '1' then	 					--$8000-$FFFF | Slow  | Address Bus A + /CART
				INT_ROMSEL_N <= '0';
			end if;
		else														--$40-$7F, $C0-$FF
			if INT_A(23 downto 17) = "0111111" then	--$7E-$7F | $0000-$FFFF | Slow  | Address Bus A + /WRAM
				INT_RAMSEL_N <= '0';
			elsif INT_A(23 downto 22) = "01" or			--$40-$7D | $0000-$FFFF | Slow  | Address Bus A + /CART
				  INT_A(23 downto 22) = "11" then		--$C0-$FF | $0000-$FFFF | Fast,Slow | Address Bus A + /CART
				INT_ROMSEL_N <= '0';
			end if;
		end if;
	end process;
	RAMSEL_N <= INT_RAMSEL_N;
	ROMSEL_N <= INT_ROMSEL_N;

	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			CPU_WR <= '0';
			CPU_RD <= '0';
		elsif rising_edge(CLK) then
			if EN = '1' then
				if P65_EN = '1' and (P65_VPA = '1' or P65_VDA = '1') and INT_CLKR_CE = '1' then
					CPU_WR <= not P65_R_WN;
					CPU_RD <= P65_R_WN;
				elsif INT_CLKF_CE = '1' then
					CPU_WR <= '0';
					CPU_RD <= '0';
				end if;
			end if;
		end if;
	end process;
	
	process(P65_A, EN, CPU_RD, CPU_WR, DMA_B, DMA_B_RD, DMA_B_WR, DMA_A_RD, DMA_A_WR, 
			  HDMA_A_RD, HDMA_A_WR, HDMA_B_RD, HDMA_B_WR, DMA_TRANSFER, HDMA_BUS_ACTIVE, P65_EN)
	begin
		if HDMA_BUS_ACTIVE = '1' and EN = '1' then
			PA <= DMA_B;
			PARD_N <= not HDMA_B_RD;
			PAWR_N <= not HDMA_B_WR;
		elsif DMA_TRANSFER = '1' and EN = '1' then
			PA <= DMA_B;
			PARD_N <= not DMA_B_RD;
			PAWR_N <= not DMA_B_WR;
		elsif P65_A(22) = '0' and P65_A(15 downto 8) = x"21" and P65_EN = '1' then
			PA <= P65_A(7 downto 0);
			PARD_N <= not CPU_RD;
			PAWR_N <= not CPU_WR;
		else
			PA <= x"FF";
			PARD_N <= '1';
			PAWR_N <= '1';
		end if;
		
		if HDMA_BUS_ACTIVE = '1' and EN = '1' then
			INT_CPURD_N <= not HDMA_A_RD;
			INT_CPUWR_N <= not HDMA_A_WR; 
		elsif DMA_TRANSFER = '1' and EN = '1' then
			INT_CPURD_N <= not DMA_A_RD;
			INT_CPUWR_N <= not DMA_A_WR;
		elsif P65_EN = '1' then
			INT_CPURD_N <= not CPU_RD;
			INT_CPUWR_N <= not CPU_WR; 
		else
			INT_CPURD_N <= '1';
			INT_CPUWR_N <= '1'; 
		end if;
	end process;
	
	CPURD_N <= INT_CPURD_N;
	CPUWR_N <= INT_CPUWR_N; 

	
	--IO Registers
	IO_SEL <= '1' when EN = '1' and P65_EN = '1' and P65_A(22) = '0' and P65_A(15 downto 10) = "010000" and (P65_VPA = '1' or P65_VDA = '1') else '0';	--$00-$3F/$80-$BF:$4000-$43FF

	--H/V counters,NMI,IRQ
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			AUTO_JOY_EN <= '0';
			HVIRQ_EN <= (others => '0');
			NMI_EN <= '0';
			HTIME <= (others => '1');
			VTIME <= (others => '1');
			WRIO <= (others => '1');
			MEMSEL <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' and INT_CLKF_CE = '1' then
				if P65_A(15 downto 8) = x"42" and P65_R_WN = '0' and IO_SEL = '1' then
					case P65_A(7 downto 0) is
						when x"00" =>
							AUTO_JOY_EN <= P65_DO(0);
							HVIRQ_EN <= P65_DO(5 downto 4);
							NMI_EN <= P65_DO(7);
						when x"01" =>
							WRIO <= P65_DO;
						when x"07" =>
							HTIME(7 downto 0) <= P65_DO;
						when x"08" =>
							HTIME(8) <= P65_DO(0);
						when x"09" =>
							VTIME(7 downto 0) <= P65_DO;
						when x"0A" =>
							VTIME(8) <= P65_DO(0);
						when x"0D" =>
							MEMSEL <= P65_DO(0);
						when others => null;
					end case;
				end if;
			end if;
		end if;
	end process;

	process( RST_N, CLK )
		variable RDNMI_READ : std_logic;
		variable TIMEUP_READ : std_logic;
		variable H_TIME, V_TIME, IRQ_TIME : std_logic;
	begin
		if RST_N = '0' then
			HBLANK_FF <= (others => '0');
			VBLANK_FF <= (others => '0');
			H6_VBLANK_FF <= '0';
			IRQ_TIME_FF <= (others => '0');
			IRQ_TIME_FF2 <= '0';
			H_CNT <= (others => '0');
			V_CNT <= (others => '0');
			NMI_FLAG <= '0'; 
			IRQ_FLAG <= '0';
		elsif rising_edge(CLK) then
			if P65_R_WN = '1' and P65_A(15 downto 0) = x"4210" and IO_SEL = '1' then
				RDNMI_READ := '1';
			else
				RDNMI_READ := '0'; 
			end if;
			if P65_R_WN = '1' and P65_A(15 downto 0) = x"4211" and IO_SEL = '1' then
				TIMEUP_READ := '1';
			else
				TIMEUP_READ := '0'; 
			end if;
			
			if H_CNT = unsigned(HTIME) then
				H_TIME := '1';
			else
				H_TIME := '0'; 
			end if;
			
			if V_CNT = unsigned(VTIME) then
				V_TIME := '1';
			else
				V_TIME := '0'; 
			end if;
			
			case HVIRQ_EN is
				when "00" => IRQ_TIME := '0';
				when "01" => IRQ_TIME := H_TIME;					--H-IRQ:  every scanline, H=HTIME+~3.5
				when "10" => IRQ_TIME := V_TIME;					--V-IRQ:  V=VTIME, H=~2.5
				when "11" => IRQ_TIME := H_TIME and V_TIME;	--HV-IRQ: V=VTIME, H=HTIME+~3.5
			end case;
			
			if ENABLE = '1' then
				if CLK4_CE_R = '1' then
					HBLANK_FF <= HBLANK_FF(0)&HBLANK;
					VBLANK_FF <= VBLANK_FF(0)&VBLANK;
					if H_CNT(6 downto 0) = "0111111" then
						H6_VBLANK_FF <= VBLANK_FF(0);
					end if;
				end if;
				
				--H/V counters
				--H_CNT reset during DOT_CLK
				if HBLANK_FF = "10" then-- and CLK4_CE_R = '0'
					H_CNT <= (others => '0');
				elsif CLK4_CE_R = '1' then
					H_CNT <= H_CNT + 1;
				end if;
				
				--V_CNT reset during DOT_CLK
				if VBLANK_FF = "10" and CLK4_CE_R = '0' then
					V_CNT <= (others => '0');
				--V_CNT increment immediately
				elsif HBLANK = '0' and HBLANK_FF(0) = '1' and CLK4_CE_R = '1' then
					V_CNT <= V_CNT + 1;	
				end if;
				
				--NMI
				if VBLANK = '0' then
					NMI_FLAG <= '0'; 
				elsif VBLANK_FF = "01" then
					NMI_FLAG <= '1'; 
				elsif RDNMI_READ = '1' and INT_CLKF_CE = '1' then
					NMI_FLAG <= '0'; 
				end if;
				
				--HV IRQ
				if CLK4_CE_R = '1' then
					IRQ_TIME_FF <= IRQ_TIME_FF(0)&IRQ_TIME;
				end if;
				if IRQ_TIME_FF = "01" then
					IRQ_TIME_FF2 <= '1'; 
				else
					IRQ_TIME_FF2 <= '0'; 
				end if;
					
				if HVIRQ_EN = "00" then
					IRQ_FLAG <= '0'; 
				elsif IRQ_TIME_FF2 = '1' then
					IRQ_FLAG <= '1'; 
				elsif TIMEUP_READ = '1' and INT_CLKF_CE = '1' then
					IRQ_FLAG <= '0'; 
				end if;
			end if;
			
			P65_NMI_N <= not (NMI_FLAG and NMI_EN);
			P65_IRQ_N <= (not IRQ_FLAG) and IRQ_N; 
		end if;
	end process;

	FALLING_VBLANK <= '1' when VBLANK_FF = "10" else '0';
	LONG_FALLING_VBLANK <= '1' when VBLANK_FF(0) = '0' and H6_VBLANK_FF = '1' else '0';

	--WRAM refresh
	process( RST_N, CLK )
		variable H128_135, H10_11 : std_logic;
	begin
		if RST_N = '0' then
			REFRESH_EN <= '0';
			REFRESH_EN2 <= '0';
			REFRESH_EN3 <= '0';
			REFRESHED <= '0';
		elsif rising_edge(CLK) then
			H128_135 := not H_CNT(8) and H_CNT(7) and not H_CNT(6) and not H_CNT(5) and not H_CNT(4) and not H_CNT(3);
			H10_11 := H_CNT(3) and H_CNT(1) and (H_CNT(0) or not R40XX_41XX);
			if CLK4_CE_F = '1' then
				if H10_11 = '1' then
					REFRESH_EN <= '0';
				elsif H128_135 = '1' then
					REFRESH_EN <= '1';
				end if;
			end if;
			if CLK8_CE_F = '1' then
				REFRESH_EN2 <= REFRESH_EN;
			end if;
			if CLK4_CE_F = '1' then
				REFRESH_EN3 <= REFRESH_EN2;
			end if;
			
			if ENABLE = '1' and INT_CLKF_CE = '1' then
				REFRESHED <= REFRESH_EN3;
			end if; 
		end if;
	end process;

	REFRESH <= REFRESHED;
	
	--MATH
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			WRMPYA <= (others => '1');
--			WRMPYB <= (others => '0');
			WRDIVA <= (others => '1');
--			WRDIVB <= (others => '0');
			RDDIV <= (others => '0');
			RDMPY <= (others => '0');
			MUL_REQ <= '0';
			DIV_REQ <= '0';
			MATH_CLK_CNT <= (others => '0');
			MATH_TEMP <= (others => '0');
		elsif rising_edge(CLK) then
			if ENABLE = '1' and INT_CLKF_CE = '1' then
				if MUL_REQ = '1' then
					if RDDIV(0) = '1' then
						RDMPY <= std_logic_vector(unsigned(RDMPY) + unsigned(MATH_TEMP(15 downto 0)));
					end if;
					RDDIV <= "0" & RDDIV(15 downto 1);
					MATH_TEMP <= MATH_TEMP(21 downto 0) & "0";
					MATH_CLK_CNT <= MATH_CLK_CNT + 1;
					if MATH_CLK_CNT = 7 then
						MUL_REQ <= '0';
					end if;
				end if;
				
				if DIV_REQ = '1' then
					if unsigned(RDMPY) >= unsigned(MATH_TEMP) then
						RDMPY <= std_logic_vector(unsigned(RDMPY) - unsigned(MATH_TEMP(15 downto 0)));
						RDDIV <= RDDIV(14 downto 0) & "1";
					else
						RDDIV <= RDDIV(14 downto 0) & "0";
					end if;
					MATH_TEMP <= "0" & MATH_TEMP(22 downto 1);
					MATH_CLK_CNT <= MATH_CLK_CNT + 1;
					if MATH_CLK_CNT = 15 then
						DIV_REQ <= '0';
					end if;
				end if;
		
				if P65_A(15 downto 8) = x"42" and P65_R_WN = '0' and IO_SEL = '1' then
					case P65_A(7 downto 0) is
						when x"02" =>
							WRMPYA <= P65_DO;
						when x"03" =>
--							WRMPYB <= P65_DO;
							RDMPY <= (others => '0');
							if MUL_REQ = '0' and DIV_REQ = '0' then
								RDDIV <= P65_DO & WRMPYA;
								MATH_TEMP <= "000000000000000" & P65_DO;
								MATH_CLK_CNT <= (others => '0');
								MUL_REQ <= '1';
							end if;
						when x"04" =>
							WRDIVA(7 downto 0) <= P65_DO;
						when x"05" =>
							WRDIVA(15 downto 8) <= P65_DO;
						when x"06" =>
--							WRDIVB <= P65_DO;
							RDMPY <= WRDIVA;
							if DIV_REQ = '0' and MUL_REQ = '0' then
								MATH_TEMP <= P65_DO & "000000000000000";
								MATH_CLK_CNT <= (others => '0');
								DIV_REQ <= '1';
							end if;
						when others => null;
					end case;
				end if;
			end if;
		end if;
	end process;
	
	
	process( P65_A, IO_SEL, DI, NMI_FLAG, IRQ_FLAG, MDR, VBLANK, HBLANK, 
				RDDIV, RDMPY, JOYRD_BUSY, JOY1_DATA, JOY2_DATA, JOY3_DATA, JOY4_DATA, JOY1_DI, JOY2_DI,
				DMAP, BBAD, A1T, A1B, DAS, DASB, A2A, NTLR, UNUSED, AUTO_JOY_EN)
	variable i : integer range 0 to 7;
	begin
		P65_DI <= DI;
		if IO_SEL = '1' then
			P65_DI <= MDR;
			if P65_A(15 downto 8) = x"42" then
				case P65_A(7 downto 0) is
					when x"10" =>
						P65_DI <= NMI_FLAG & MDR(6 downto 4) & "0010";					--RDNMI
					when x"11" =>
						P65_DI <= IRQ_FLAG & MDR(6 downto 0);								--TIMEUP
					when x"12" =>
						P65_DI <= VBLANK & HBLANK & MDR(5 downto 1) & JOYRD_BUSY;	--HVBJOY
					when x"13" =>
						P65_DI <= x"00";															--RDIO
					when x"14" =>
						P65_DI <= RDDIV(7 downto 0);											--RDDIVL
					when x"15" =>
						P65_DI <= RDDIV(15 downto 8);											--RDDIVH
					when x"16" =>
						P65_DI <= RDMPY(7 downto 0);											--RDMPYL
					when x"17" =>
						P65_DI <= RDMPY(15 downto 8);											--RDMPYH
					when x"18" =>
						P65_DI <= JOY1_DATA(7 downto 0);										--JOY1L
					when x"19" =>
						P65_DI <= JOY1_DATA(15 downto 8);									--JOY1H
					when x"1A" =>
						P65_DI <= JOY2_DATA(7 downto 0);										--JOY2L
					when x"1B" =>
						P65_DI <= JOY2_DATA(15 downto 8);									--JOY2H
					when x"1C" =>
						P65_DI <= JOY3_DATA(7 downto 0);										--JOY3L
					when x"1D" =>
						P65_DI <= JOY3_DATA(15 downto 8);									--JOY3H
					when x"1E" =>
						P65_DI <= JOY4_DATA(7 downto 0);										--JOY4L
					when x"1F" =>
						P65_DI <= JOY4_DATA(15 downto 8);									--JOY4H
					when others => 
						P65_DI <= MDR;
				end case;
			elsif P65_A(15 downto 7) = x"43"&"0" then
				i := to_integer(unsigned(P65_A(6 downto 4)));
				case P65_A(3 downto 0) is
					when x"0" =>
						P65_DI <= DMAP(i);														--DMAPx
					when x"1" =>
						P65_DI <= BBAD(i);														--BBADx
					when x"2" =>
						P65_DI <= A1T(i)(7 downto 0);											--A1TxL
					when x"3" =>
						P65_DI <= A1T(i)(15 downto 8);										--A1TxH
					when x"4" =>
						P65_DI <= A1B(i);															--A1Bx
					when x"5" =>
						P65_DI <= DAS(i)(7 downto 0);											--DASxL
					when x"6" =>
						P65_DI <= DAS(i)(15 downto 8);										--DASxH
					when x"7" =>
						P65_DI <= DASB(i);														--DASBx
					when x"8" =>
						P65_DI <= A2A(i)(7 downto 0);											--A2AxL
					when x"9" =>
						P65_DI <= A2A(i)(15 downto 8);										--A2AxH
					when x"A" =>
						P65_DI <= NTLR(i);														--NTLRx
					when x"B" | x"F" =>
						P65_DI <= UNUSED(i);														--UNUSEDx
					when others => 
						P65_DI <= MDR;
				end case;
			elsif P65_A(15 downto 8) = x"40" then
				case P65_A(7 downto 0) is
					when x"16" =>
						P65_DI <= MDR(7 downto 2) & (not JOY1_DI(1)) & ((not JOY1_DI(0)));
					when x"17" =>
						P65_DI <= MDR(7 downto 5) & "111" & (not JOY2_DI(1)) & ((not JOY2_DI(0)));
					when others => 
						P65_DI <= MDR;
				end case;
			end if;
		end if;
	end process;

	JPIO67 <= WRIO(7 downto 6);

	--MDR
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			MDR <= (others => '1');
		elsif rising_edge(CLK) then
			if INT_CLKR_CE = '1' then
				if EN = '1' and P65_EN = '1' and (P65_VPA = '1' or P65_VDA = '1') and P65_R_WN = '0' then
					MDR <= P65_DO;
				end if;
			elsif INT_CLKF_CE = '1' then
				if EN = '1' and P65_EN = '1' and (P65_VPA = '1' or P65_VDA = '1') and P65_R_WN = '1' then
					MDR <= P65_DI;
				elsif DMA_ACTIVE = '1' and EN = '1' then
					MDR <= DI;
				end if;
			end if;
		end if;
	end process; 
 
	DO <= MDR;

	--DMA/HDMA
	HDMA_CH_EN <= HDMAEN and HDMA_CH_RUN and HDMA_CH_DO;
	HDMA_CH_LAST <= IsLastHDMACh(HDMA_CH_EN and HDMA_CH_WORK, DMA_CH);
	HDMA_EN <= '1' when (HDMAEN and HDMA_CH_RUN) /= x"00" else '0';
				
	process( RST_N, CLK )
		variable i : integer range 0 to 7;
		variable NEXT_DAS : std_logic_vector(15 downto 0);
		variable NEXT_NTLR : std_logic_vector(7 downto 0);
	begin
		if RST_N = '0' then
			MDMAEN <= (others => '0');
			HDMAEN <= (others => '0');
			
			DMAP <= (others => (others => '1'));
			BBAD <= (others => (others => '1'));
			A1T <= (others => (others => '1'));
			A1B <= (others => (others => '1'));
			DAS <= (others => (others => '1'));
			DASB <= (others => (others => '1'));
			A2A <= (others => (others => '1'));
			NTLR <= (others => (others => '1'));
			UNUSED <= (others => (others => '1'));
			
			DMA_RUN <= '0';
			DMA_PATTERN_END <= '0';
			HDMA_RUN <= '0';
			HDMA_CH_RUN <= (others => '0');
			HDMA_CH_DO <= (others => '0');
			HDMA_CH_WORK <= (others => '0');
			DMA_TRMODE_STEP <= (others => '0');
			HDMA_TRMODE_STEP <= (others => '0');
			HDMA_INIT_STEP <= '0';
			DS <= DS_IDLE;
			HDS <= HDS_IDLE;
		elsif rising_edge(CLK) then
			if P65_R_WN = '0' and IO_SEL = '1' and INT_CLKF_CE = '1' then
				if P65_A(15 downto 8) = x"42" then
					case P65_A(7 downto 0) is
						when x"0B" =>
							MDMAEN <= P65_DO;
						when x"0C" =>
							HDMAEN <= P65_DO;
						when others => null;
					end case;
				elsif P65_A(15 downto 7) = x"43"&"0" then
					i := to_integer(unsigned(P65_A(6 downto 4)));
					case P65_A(3 downto 0) is
						when x"0" =>
							DMAP(i) <= P65_DO;
						when x"1" =>
							BBAD(i) <= P65_DO;
						when x"2" =>
							A1T(i)(7 downto 0) <= P65_DO;
						when x"3" =>
							A1T(i)(15 downto 8) <= P65_DO;
						when x"4" =>
							A1B(i) <= P65_DO;
						when x"5" =>
							DAS(i)(7 downto 0) <= P65_DO;
						when x"6" =>
							DAS(i)(15 downto 8) <= P65_DO;
						when x"7" =>
							DASB(i) <= P65_DO;
						when x"8" =>
							A2A(i)(7 downto 0) <= P65_DO;
						when x"9" =>
							A2A(i)(15 downto 8) <= P65_DO;
						when x"A" =>
							NTLR(i) <= P65_DO;
						when x"B" | x"F" =>
							UNUSED(i) <= P65_DO;
						when others => null;
					end case;
				end if;
			end if;
				
			if CLK8_CE_F = '1' then
				LONG_FALLING_VBLANK_FF <= LONG_FALLING_VBLANK;
			end if;
			if INT_CLKR_CE = '1' then
				HDMA_VBLANK_EDGE <= HDMA_VBLANK_EDGE(0)&LONG_FALLING_VBLANK_FF;
				HDMA_HBLANK_EDGE <= HDMA_HBLANK_EDGE(0)&HBLANK;
			end if;
			
			if INT_CLKF_CE = '1' then
				if HDMA_EN = '1' and HDMA_VBLANK_EDGE = "01" then
					HDMA_INIT_START <= '1';
				end if;
				if HDMA_EN = '1' and HDMA_HBLANK_EDGE = "01" and VBLANK = '0' then
					HDMA_START <= '1';
				end if;
			end if;
			if FALLING_VBLANK = '1' then
				HDMA_CH_RUN <= (others => '1');
				HDMA_CH_DO <= (others => '0');
			end if;
			
			if EN = '1' and INT_CLKF_CE = '1' then
				DMA_A <= (others => '1');
				DMA_B <= (others => '1');
				DMA_DIR <= '0';
				
				--DMA
				DMA_TRANSFER <= '0';
				DMA_PATTERN_END <= '0';
				if HDMA_RUN = '0' then
					case DS is
						when DS_IDLE =>
							if MDMAEN /= x"00" then
								DMA_RUN <= '1';
								DMA_TRMODE_STEP <= (others => '0');
								DS <= DS_TRANSFER;
							end if;
							
						when DS_TRANSFER =>
							NEXT_DAS := std_logic_vector(unsigned(DAS(DMA_CH)) - 1);
							if MDMAEN(DMA_CH) = '1' then
								case DMAP(DMA_CH)(4 downto 3) is
									when "00" => A1T(DMA_CH) <= std_logic_vector(unsigned(A1T(DMA_CH)) + 1);
									when "10" => A1T(DMA_CH) <= std_logic_vector(unsigned(A1T(DMA_CH)) - 1);
									when others => null;
								end case;
								
								DAS(DMA_CH) <= NEXT_DAS;
								if NEXT_DAS = x"0000" then
									MDMAEN(DMA_CH) <= '0';
									DS <= DS_NEXT;
								end if;
								
								if DMA_TRMODE_STEP = DMA_TRMODE_LEN(to_integer(unsigned(DMAP(DMA_CH)(2 downto 0)))) then
									DMA_TRMODE_STEP <= (others => '0');
									DMA_PATTERN_END <= '1';
								else
									DMA_TRMODE_STEP <= DMA_TRMODE_STEP + 1;
								end if;
								DMA_TRANSFER <= '1';
								DMA_CH_LATCH <= DMA_CH;
								DMA_A <= A1B(DMA_CH) & A1T(DMA_CH);
								DMA_B <= std_logic_vector( unsigned(BBAD(DMA_CH)) + DMA_TRMODE_TAB(to_integer(unsigned(DMAP(DMA_CH)(2 downto 0))),to_integer(DMA_TRMODE_STEP)) );
								DMA_DIR <= DMAP(DMA_CH)(7);
							else
								DS <= DS_NEXT;
							end if;
							
						when DS_NEXT =>
							if MDMAEN /= x"00" then
								DMA_TRMODE_STEP <= (others => '0');
								DS <= DS_TRANSFER;
							else
								DMA_RUN <= '0';
								DS <= DS_IDLE;
							end if;
							
						when others => null;
					end case;
				end if;
				
				--HDMA
				FETCH_SCANLINE_COUNTER <= '0';
				FETCH_IND_ADDR <= '0';
				HDMA_TRANSFER <= '0';
				HDMA_BUS_ACTIVE <= '0';
				case HDS is
					when HDS_IDLE =>
						if HDMA_INIT_START = '1' and (DMA_PATTERN_END = '1' or DMA_RUN = '0') then
							HDMA_INIT_START <= '0';
							if (HDMA_CH_RUN and HDMAEN) /= x"00" then
								HDMA_CH_DO <= (others => '1'); 
								HDMA_CH_WORK <= HDMAEN;--(others => '1');
								HDMA_RUN <= '1';
								HDS <= HDS_INIT;
							end if;
						end if;
						
						if HDMA_START = '1' and (DMA_PATTERN_END = '1' or DMA_RUN = '0') then
							HDMA_START <= '0';
							if HDMA_CH_EN /= x"00" then
								HDMA_CH_WORK <= HDMAEN;--(others => '1'); 
								HDMA_RUN <= '1';
								HDMA_TRMODE_STEP <= (others => '0');
								HDS <= HDS_TRANSFER;
							elsif (HDMA_CH_RUN and HDMAEN) /= x"00" then
								HDMA_CH_DO <= (others => '1');
								HDMA_CH_WORK <= HDMAEN;--(others => '1'); 
								HDMA_RUN <= '1';
								HDS <= HDS_INIT;
							end if;
						end if;
						
					when HDS_INIT =>
						MDMAEN(DMA_CH) <= '0';
						
						NEXT_NTLR := std_logic_vector(unsigned(NTLR(DMA_CH)) - 1); 
						if NEXT_NTLR(6 downto 0) = "0000000" or LONG_FALLING_VBLANK = '1' then
							FETCH_SCANLINE_COUNTER <= '1';
							
							if DMAP(DMA_CH)(6) = '0' then
								HDMA_CH_WORK(DMA_CH) <= '0';
								if HDMA_CH_LAST = '1' then
									HDS <= HDS_INIT_END;
								end if;
							else
								DAS(DMA_CH) <= (others => '0'); 
								HDMA_INIT_STEP <= '0';
								DMA_CH_IND <= DMA_CH;
								HDMA_CH_LAST_IND <= HDMA_CH_LAST;
								HDS <= HDS_INIT_IND;
							end if;
							if LONG_FALLING_VBLANK = '1' then
								A2A(DMA_CH) <= std_logic_vector(unsigned(A1T(DMA_CH)) + 1);
							else
								A2A(DMA_CH) <= std_logic_vector(unsigned(A2A(DMA_CH)) + 1);
							end if;
						else
							NTLR(DMA_CH) <= NEXT_NTLR; 
							if NEXT_NTLR(7) = '0' then
								HDMA_CH_DO(DMA_CH) <= '0'; 
							end if;
							
							HDMA_CH_WORK(DMA_CH) <= '0';
							if HDMA_CH_LAST = '1' then
								HDS <= HDS_INIT_END;
							end if;
						end if;
						HDMA_BUS_ACTIVE <= '1';
						DMA_CH_LATCH <= DMA_CH;
						if LONG_FALLING_VBLANK = '1' then
							DMA_A <= A1B(DMA_CH) & A1T(DMA_CH);
						else
							DMA_A <= A1B(DMA_CH) & A2A(DMA_CH);
						end if;
				
					when HDS_INIT_IND =>
						if HDMA_INIT_STEP = '0' and HDMA_CH_LAST_IND = '1' and HDMA_CH_RUN(DMA_CH_IND) = '0' then--
							HDMA_CH_WORK(DMA_CH_IND) <= '0';
							HDS <= HDS_INIT_END;
						elsif HDMA_INIT_STEP = '1' then
							HDMA_CH_WORK(DMA_CH_IND) <= '0';
							if HDMA_CH_LAST_IND = '1' then
								HDS <= HDS_INIT_END;
							else
								HDS <= HDS_INIT;
							end if;
						end if;
						HDMA_INIT_STEP <= not HDMA_INIT_STEP;
						
						HDMA_BUS_ACTIVE <= '1';
						FETCH_IND_ADDR <= '1';
						A2A(DMA_CH_IND) <= std_logic_vector(unsigned(A2A(DMA_CH_IND)) + 1);
						DMA_CH_LATCH <= DMA_CH_IND;
						DMA_A <= A1B(DMA_CH_IND) & A2A(DMA_CH_IND);
						
					when HDS_INIT_END =>
						HDMA_RUN <= '0';
						HDS <= HDS_IDLE;
								
					when HDS_TRANSFER =>
						MDMAEN(DMA_CH) <= '0';
							
						if HDMA_TRMODE_STEP = DMA_TRMODE_LEN(to_integer(unsigned(DMAP(DMA_CH)(2 downto 0)))) then
							HDMA_CH_WORK(DMA_CH) <= '0';
							if HDMA_CH_LAST = '1' then
								HDMA_CH_DO <= (others => '1');
								HDMA_CH_WORK <= HDMAEN;--(others => '1'); 
								HDS <= HDS_INIT;
							else
								HDMA_TRMODE_STEP <= (others => '0');
								HDS <= HDS_TRANSFER;
							end if;
						else
							HDMA_TRMODE_STEP <= HDMA_TRMODE_STEP + 1;
						end if;
						
						HDMA_BUS_ACTIVE <= '1';
						HDMA_TRANSFER <= '1';
						if DMAP(DMA_CH)(6) = '0' then
							A2A(DMA_CH) <= std_logic_vector(unsigned(A2A(DMA_CH)) + 1);
						else
							DAS(DMA_CH) <= std_logic_vector(unsigned(DAS(DMA_CH)) + 1);
						end if;
						DMA_CH_LATCH <= DMA_CH;
						if DMAP(DMA_CH)(6) = '0' then
							DMA_A <= A1B(DMA_CH) & A2A(DMA_CH);
						else
							DMA_A <= DASB(DMA_CH) & DAS(DMA_CH);
						end if;
						DMA_B <= std_logic_vector( unsigned(BBAD(DMA_CH)) + DMA_TRMODE_TAB(to_integer(unsigned(DMAP(DMA_CH)(2 downto 0))),to_integer(HDMA_TRMODE_STEP)) );
						DMA_DIR <= DMAP(DMA_CH)(7);
						
					when others => null;
				end case;
				
				if FETCH_SCANLINE_COUNTER = '1' then
					NTLR(DMA_CH_LATCH) <= DI;
					
					if DI = x"00" then
						HDMA_CH_RUN(DMA_CH_LATCH) <= '0';
					end if;
				end if;
				
				if FETCH_IND_ADDR = '1' then
					DAS(DMA_CH_LATCH) <= DI & DAS(DMA_CH_LATCH)(15 downto 8);
				end if;
				
				if HDMA_TRANSFER = '1' then
					
				end if;
			end if;
		end if;
	end process;

	DMA_CH_EN <= HDMA_CH_EN and HDMA_CH_WORK when HDMA_RUN = '1' else MDMAEN;
	DMA_CH <= GetDMACh(DMA_CH_EN);

	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			DMA_A_WR <= '0';
			DMA_A_RD <= '0';
			DMA_B_WR <= '0';
			DMA_B_RD <= '0';
			HDMA_A_WR <= '0';
			HDMA_A_RD <= '0';
			HDMA_B_WR <= '0';
			HDMA_B_RD <= '0';	
		elsif rising_edge(CLK) then
			if EN = '1' then
				if DMA_TRANSFER = '1' and INT_CLKR_CE = '1' then
					DMA_A_WR <= DMA_DIR;
					DMA_A_RD <= not DMA_DIR;
					DMA_B_WR <= not DMA_DIR;
					DMA_B_RD <= DMA_DIR;
				elsif INT_CLKF_CE = '1' then
					DMA_A_WR <= '0';
					DMA_A_RD <= '0';
					DMA_B_WR <= '0';
					DMA_B_RD <= '0';
				end if;
				
				if HDMA_TRANSFER = '1' and INT_CLKR_CE = '1' then
					HDMA_A_WR <= DMA_DIR;
					HDMA_A_RD <= not DMA_DIR;
					HDMA_B_WR <= not DMA_DIR;
					HDMA_B_RD <= DMA_DIR;
				elsif (FETCH_SCANLINE_COUNTER = '1' or FETCH_IND_ADDR = '1') and INT_CLKR_CE = '1' then
					HDMA_A_WR <= '0';
					HDMA_A_RD <= '1';
					HDMA_B_WR <= '0';
					HDMA_B_RD <= '0';
				elsif INT_CLKF_CE = '1' then
					HDMA_A_WR <= '0';
					HDMA_A_RD <= '0';
					HDMA_B_WR <= '0';
					HDMA_B_RD <= '0';
				end if;
			end if;
		end if;
	end process;
	
	
	--Joy old
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			OLD_JOY_STRB <= '0';
			OLD_JOY1_CLK <= '0';
			OLD_JOY2_CLK <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' and INT_CLKF_CE = '1' then
				OLD_JOY1_CLK <= '0';
				OLD_JOY2_CLK <= '0';
				if P65_A(15 downto 8) = x"40" and IO_SEL = '1' then
					if P65_R_WN = '0' then
						case P65_A(7 downto 0) is
							when x"16" =>
								OLD_JOY_STRB <= P65_DO(0);
							when others => null;
						end case;
					else
						case P65_A(7 downto 0) is
							when x"16" =>
								OLD_JOY1_CLK <= '1';
							when x"17" =>
								OLD_JOY2_CLK <= '1';
							when others => null;
						end case;
					end if;
				end if;
			end if;
		end if;
	end process;

	-- Joy auto 
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			JOY1_DATA <= (others => '0');
			JOY2_DATA <= (others => '0');
			JOY3_DATA <= (others => '0');
			JOY4_DATA <= (others => '0');
			JOY_POLL_CLK <= (others => '0');
			JOY_POLL_CNT <= (others => '0');
			JOY_POLL_RUN <= '0';
			JOYRD_BUSY <= '0';
			AUTO_JOY_STRB <= '0';
			AUTO_JOY_CLK <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' and CLK4_CE_R = '1' then
				JOY_POLL_CLK <= JOY_POLL_CLK + 1;
				if JOY_POLL_CLK(4 downto 0) = 31 then
					if JOY_POLL_CLK(5) = '1' and VBLANK = '1' and JOY_POLL_RUN = '0' and AUTO_JOY_EN = '1' then
						JOY_POLL_RUN <= '1';
						JOY_POLL_CNT <= (others => '0');
					elsif JOY_POLL_CLK(5) = '1' and VBLANK = '0' and JOY_POLL_RUN = '1' and JOY_POLL_CNT = 16 then
						JOY_POLL_RUN <= '0';
					elsif JOY_POLL_RUN = '1' and JOY_POLL_CNT <= 15 then
						if JOY_POLL_STRB = '0' then
							if JOY_POLL_CLK(5) = '0' then
								AUTO_JOY_STRB <= '1';
								JOYRD_BUSY <= '1';
							else
								AUTO_JOY_STRB <= '0';
								JOY_POLL_STRB <= '1';
							end if;
						else
							if JOY_POLL_CLK(5) = '0' then
								JOY1_DATA(15 downto 0) <= JOY1_DATA(14 downto 0) & not JOY1_DI(0);
								JOY2_DATA(15 downto 0) <= JOY2_DATA(14 downto 0) & not JOY2_DI(0);
								JOY3_DATA(15 downto 0) <= JOY3_DATA(14 downto 0) & not JOY1_DI(1);
								JOY4_DATA(15 downto 0) <= JOY4_DATA(14 downto 0) & not JOY2_DI(1);
								AUTO_JOY_CLK <= '1';
							else
								AUTO_JOY_CLK <= '0';
								JOY_POLL_CNT <= JOY_POLL_CNT + 1;
								if JOY_POLL_CNT = 15 then
									JOYRD_BUSY <= '0';
									JOY_POLL_STRB <= '0';
								end if;
							end if;
						end if;
					end if;
				end if;
			end if;
		end if;
	end process; 

	JOY_STRB <= OLD_JOY_STRB or AUTO_JOY_STRB;
	JOY1_CLK <= OLD_JOY1_CLK or AUTO_JOY_CLK;
	JOY2_CLK <= OLD_JOY2_CLK or AUTO_JOY_CLK;
	
end rtl;