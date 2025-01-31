library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;
library work;

entity SPC7110 is
	port(
		RST_N				: in std_logic;
		CLK				: in std_logic;
		ENABLE			: in std_logic;
		
		CA   				: in std_logic_vector(23 downto 0);
		DO					: out std_logic_vector(7 downto 0);
		DI					: in std_logic_vector(7 downto 0);
		CPURD_N			: in std_logic;
		CPUWR_N			: in std_logic;
		
		SYSCLKF_CE		: in std_logic;
		SYSCLKR_CE		: in std_logic;
		
		DROM_A  			: out std_logic_vector(22 downto 0);
		DROM_DO			: in std_logic_vector(7 downto 0);
		DROM_OE_N		: out std_logic;
		DROM_RDY			: in std_logic;
		
		SNES_DROM_A		: out std_logic_vector(22 downto 0);
		SNES_DROM_OE_N	: out std_logic;
		
		PROM_OE_N		: out std_logic;
		SRAM_CE_N		: out std_logic;
		
		RTC_DO			: out std_logic_vector(3 downto 0);
		RTC_DI			: in std_logic_vector(3 downto 0);
		RTC_CE			: out std_logic;
		RTC_CK			: out std_logic
	);
end SPC7110;

architecture rtl of SPC7110 is

	--IO Registers
	type DecRegs_r is record
		POINTER		: std_logic_vector(23 downto 0);
		INDEX			: std_logic_vector(7 downto 0);
		OFFSET		: std_logic_vector(15 downto 0);
		COUNTER		: std_logic_vector(15 downto 0);
		MODE			: std_logic_vector(1 downto 0);
	end record;
	
	type DataRomRegs_r is record
		POINTER		: std_logic_vector(23 downto 0);
		ADJUST		: std_logic_vector(15 downto 0);
		INCREMENT	: std_logic_vector(15 downto 0);
		MODE			: std_logic_vector(6 downto 0);
	end record;

	signal DECREGS				: DecRegs_r;
	signal DATREGS				: DataRomRegs_r;
	signal BANKD  				: std_logic_vector(3 downto 0);
	signal BANKE  				: std_logic_vector(3 downto 0);
	signal BANKF  				: std_logic_vector(3 downto 0);
	signal SRAM_EN 			: std_logic;
	signal MULTIPLICAND  	: std_logic_vector(15 downto 0);
	signal MULTIPLIER  		: std_logic_vector(15 downto 0);
	signal DIVIDEND  			: std_logic_vector(31 downto 0);
	signal DIVISOR  			: std_logic_vector(15 downto 0);
	signal SIGN 				: std_logic;

	type DecStates_t is (
		DS_IDLE,
		DS_PRELOAD,
		DS_INIT,
		DS_DECODING
	);
	signal DS 					: DecStates_t; 
	
	type WorkStates_t is (
		WS_IDLE,
		WS_LOAD_ADDR1,
		WS_LOAD_ADDR2,
		WS_LOAD_ADDR3,
		WS_LOAD_FIFO1,
		WS_LOAD_FIFO2,
		WS_LOAD_FIFO3,
		WS_DP_READ1,
		WS_DP_READ2
	);
	signal WS 					: WorkStates_t; 
	
	--Decompressor
	signal DEC_ADDR			: std_logic_vector(23 downto 0);
	signal DEC_MODE			: std_logic_vector(1 downto 0);
	signal DEC_START 			: std_logic;
	signal DEC_IN_RD 			: std_logic;
	signal DEC_DAT_OUT 		: std_logic_vector(31 downto 0);
	signal DEC_OUT_WR 		: std_logic;
	signal DEC_RUN 			: std_logic;
	signal DEC_RUN_OLD 		: std_logic;
	signal DEC_INIT 			: std_logic;
	signal DEC_DONE 			: std_logic;
	type DecBuf_t is array(0 to 63) of std_logic_vector(7 downto 0);
	signal DEC_BUF 			: DecBuf_t;
	signal DEC_BUF_WR_ADDR 	: unsigned(5 downto 0);
	signal DEC_BUF_RD_ADDR 	: unsigned(5 downto 0);
	signal DEC_BUF_OUT 		: std_logic_vector(7 downto 0);
	signal LOAD_RUN 			: std_logic;
	signal LOAD_ADDR_POS 	: unsigned(1 downto 0);
	signal FIFO_D 				: std_logic_vector(7 downto 0);
	signal FIFO_Q 				: std_logic_vector(7 downto 0);
	signal FIFO_RD 			: std_logic;
	signal FIFO_WR 			: std_logic;
	signal FIFO_CLR 			: std_logic;
	signal FIFO_FULL 			: std_logic;
	
	--DATA ROM PORT
	signal DP_READ 			: std_logic;
	signal DP_DATA_OUT 		: std_logic_vector(7 downto 0);
	
	--MUL/DIV
	signal UMUL_RES 			: std_logic_vector(31 downto 0);
	signal SMUL_RES 			: std_logic_vector(31 downto 0);
	signal UDIV_QUOT 			: std_logic_vector(31 downto 0);
	signal UDIV_REM 			: std_logic_vector(15 downto 0);
	signal SDIV_QUOT 			: std_logic_vector(31 downto 0);
	signal SDIV_REM 			: std_logic_vector(15 downto 0);
	signal MULDIV_RES 		: std_logic_vector(31 downto 0);
	signal REM_RES 			: std_logic_vector(15 downto 0);
	signal MUL_RUN 			: std_logic;
	signal DIV_RUN 			: std_logic;
	signal ALU_CNT 			: unsigned(5 downto 0);
	signal ALU_BUSY 			: std_logic;
	
	--DATA ROM
	signal DROM_ADDR 			: std_logic_vector(23 downto 0);
	signal DROM_DATA 			: std_logic_vector(7 downto 0);
	signal DROM_READ 			: std_logic;
	signal MAP_ROM_A 			: std_logic_vector(23 downto 0);

begin

	process( RST_N, CLK)
	variable INC : std_logic_vector(23 downto 0);
	begin
		if RST_N = '0' then
			DECREGS <= ((others => '0'),(others => '0'),(others => '0'),(others => '0'),(others => '0'));
			DATREGS <= ((others => '0'),(others => '0'),(others => '0'),(others => '0'));
			BANKD <= x"0";
			BANKE <= x"1";
			BANKF <= x"2";
			SRAM_EN <= '0';
			MULTIPLICAND <= (others => '0');
			MULTIPLIER <= (others => '0');
			DIVIDEND <= (others => '0');
			DIVISOR <= (others => '0');
			SIGN <= '0';
			LOAD_RUN <= '0';
			DEC_START <= '0';
			DP_READ <= '0';
			DEC_BUF_RD_ADDR <= (others => '0');
			DEC_DONE <= '0';
			MULDIV_RES <= (others => '0');
			REM_RES <= (others => '0');
			MUL_RUN <= '0';
			DIV_RUN <= '0';
			ALU_CNT <= (others => '0');
			RTC_CK <= '0';
			DEC_RUN_OLD <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				if LOAD_RUN = '1' and WS = WS_LOAD_ADDR1 then
					LOAD_RUN <= '0';
				end if;
				
				if DEC_START = '1' and DS = DS_PRELOAD then
					DEC_START <= '0';
				end if;
				
				if DP_READ = '1' and WS = WS_DP_READ1 then
					DP_READ <= '0';
				end if;
				
				DEC_RUN_OLD <= DEC_RUN;
				if DEC_RUN = '0' and DEC_RUN_OLD = '1' and DEC_DONE = '0' then
					DEC_DONE <= '1';
				end if;
				
				RTC_CK <= '0';
				
				if CA(22) = '0' and CA(15 downto 8) = x"48" and CA(7) = '0' then 
					if CPUWR_N = '0' and SYSCLKF_CE = '1' then	--IO write
						case CA(6 downto 0) is
							when "0000000" =>						--4800 (read only)
							when "0000001" =>						--4801
								DECREGS.POINTER(7 downto 0) <= DI;
							when "0000010" =>						--4802
								DECREGS.POINTER(15 downto 8) <= DI;
							when "0000011" =>						--4803
								DECREGS.POINTER(23 downto 16) <= DI;
							when "0000100" =>						--4804
								DECREGS.INDEX <= DI;
								LOAD_RUN <= '1';
							when "0000101" =>						--4805
								DECREGS.OFFSET(7 downto 0) <= DI;
							when "0000110" =>						--4806
								DECREGS.OFFSET(15 downto 8) <= DI;
								DEC_BUF_RD_ADDR <= (others => '0');
								DEC_START <= '1';
								DEC_DONE <= '0';
							when "0000111" =>						--4807
							when "0001000" =>						--4808
							when "0001001" =>						--4809
								DECREGS.COUNTER(7 downto 0) <= DI;
								DEC_DONE <= '0';
							when "0001010" =>						--480A
								DECREGS.COUNTER(15 downto 8) <= DI;
								DEC_DONE <= '0';
							when "0001011" =>						--480B
								DECREGS.MODE <= DI(1 downto 0);
							when "0001100" =>						--480C (read only)
							
							when "0010001" =>						--4811
								DATREGS.POINTER(7 downto 0) <= DI;
							when "0010010" =>						--4812
								DATREGS.POINTER(15 downto 8) <= DI;
							when "0010011" =>						--4813
								DATREGS.POINTER(23 downto 16) <= DI;
								DP_READ <= '1';
							when "0010100" =>						--4814
								DATREGS.ADJUST(7 downto 0) <= DI;
								if DATREGS.MODE(6 downto 5) = "01" then
									DATREGS.POINTER <= std_logic_vector( unsigned(DATREGS.POINTER) + ((7 downto 0 => DATREGS.ADJUST(15) and DATREGS.MODE(3)) & unsigned(DATREGS.ADJUST(15 downto 8)) & unsigned(DI)) );
									DP_READ <= '1';
								end if;
							when "0010101" =>						--4815
								DATREGS.ADJUST(15 downto 8) <= DI;
								if DATREGS.MODE(1) = '1' then
									DP_READ <= '1';
								end if;
								if DATREGS.MODE(6 downto 5) = "10" then
									DATREGS.POINTER <= std_logic_vector( unsigned(DATREGS.POINTER) + ((7 downto 0 => DI(7) and DATREGS.MODE(3)) & unsigned(DI) & unsigned(DATREGS.ADJUST(7 downto 0))) );
									DP_READ <= '1';
								end if;
							when "0010110" =>						--4816
								DATREGS.INCREMENT(7 downto 0) <= DI;
							when "0010111" =>						--4817
								DATREGS.INCREMENT(15 downto 8) <= DI;
							when "0011000" =>						--4818
								DATREGS.MODE <= DI(6 downto 0);
								DP_READ <= '1';
							when "0100000" =>						--4820
								MULTIPLICAND(7 downto 0) <= DI;
								DIVIDEND(7 downto 0) <= DI;
							when "0100001" =>						--4821
								MULTIPLICAND(15 downto 8) <= DI;
								DIVIDEND(15 downto 8) <= DI;
							when "0100010" =>						--4822
								DIVIDEND(23 downto 16) <= DI;
							when "0100011" =>						--4823
								DIVIDEND(31 downto 24) <= DI;
							when "0100100" =>						--4824
								MULTIPLIER(7 downto 0) <= DI;
							when "0100101" =>						--4825
								MULTIPLIER(15 downto 8) <= DI;
								MUL_RUN <= '1';
							when "0100110" =>						--4826
								DIVISOR(7 downto 0) <= DI;
							when "0100111" =>						--4827
								DIVISOR(15 downto 8) <= DI;
								DIV_RUN <= '1';
							when "0101110" =>						--482E
								SIGN <= DI(0);
								
							when "0110000" =>						--4830
								SRAM_EN <= DI(7);
							when "0110001" =>						--4831
								BANKD <= DI(3 downto 0);
							when "0110010" =>						--4832
								BANKE <= DI(3 downto 0);
							when "0110011" =>						--4833
								BANKF <= DI(3 downto 0);
							
							when "1000000" =>						--4840
								RTC_CE <= DI(0);
							when "1000001" =>						--4841
								RTC_DO <= DI(3 downto 0);
								RTC_CK <= '1';
							when "1000010" =>						--4842 (read only)
								
							when others => null;
						end case; 
					elsif CPURD_N = '0' and SYSCLKF_CE = '1' then	--IO read
						case CA(6 downto 0) is
							when "0000000" =>						--4800
								DEC_BUF_RD_ADDR <= DEC_BUF_RD_ADDR + 1;
								DECREGS.COUNTER <= std_logic_vector( unsigned(DECREGS.COUNTER) - 1 );
							
							when "0010000" =>						--4810
								if DATREGS.MODE(0) = '0' then
									INC := x"000001";
								else
									INC := (7 downto 0 => DATREGS.INCREMENT(15) and DATREGS.MODE(2)) & DATREGS.INCREMENT;
								end if;
								if DATREGS.MODE(4) = '0' then
									DATREGS.POINTER <= std_logic_vector( unsigned(DATREGS.POINTER) + unsigned(INC) );
								else
									DATREGS.ADJUST <= std_logic_vector( unsigned(DATREGS.ADJUST) + unsigned(INC(15 downto 0)) );
								end if;
								DP_READ <= '1';
								
							when "0011010" =>						--481A
								if DATREGS.MODE(6 downto 5) = "11" then
									DATREGS.POINTER <= std_logic_vector( unsigned(DATREGS.POINTER) + ((7 downto 0 => DATREGS.ADJUST(15) and DATREGS.MODE(3)) & unsigned(DATREGS.ADJUST)) );
									DP_READ <= '1';
								end if;
							
							when "1000001" =>						--4841
								RTC_CK <= '1';
								
							when others => null;
						end case; 
					
					end if;
				elsif CA(23 downto 16) = x"50" and CPURD_N = '0' and SYSCLKF_CE = '1' then	--50:0000-50:FFFF read
					DEC_BUF_RD_ADDR <= DEC_BUF_RD_ADDR + 1;
				end if;
				
				if DEC_OUT_WR = '1' then
					if DECREGS.MODE = "10" and DECREGS.OFFSET /= x"0000" then
						DEC_BUF_RD_ADDR <= DEC_BUF_RD_ADDR + 4;
						DECREGS.OFFSET <= std_logic_vector( unsigned(DECREGS.OFFSET) - 1 );
					end if;
				end if;
				
				if MUL_RUN = '1' then
					if ALU_CNT = 29 then
						ALU_CNT <= (others => '0');
						MUL_RUN <= '0';
						if SIGN = '0' then
							MULDIV_RES <= UMUL_RES;
						else
							MULDIV_RES <= SMUL_RES;
						end if;
					else
						ALU_CNT <= ALU_CNT + 1;
					end if;
				elsif DIV_RUN = '1' then
					if ALU_CNT = 39 then
						ALU_CNT <= (others => '0');
						DIV_RUN <= '0';
						if SIGN = '0' then
							MULDIV_RES <= UDIV_QUOT;
							REM_RES <= UDIV_REM;
						else
							MULDIV_RES <= SDIV_QUOT;
							REM_RES <= SDIV_REM;
						end if;
					else
						ALU_CNT <= ALU_CNT + 1;
					end if;
				end if;

			end if;
		end if;
	end process; 
	
	ALU_BUSY <= MUL_RUN or DIV_RUN;

	process( RST_N, CLK)
	begin
		if RST_N = '0' then
			DO <= (others => '0');
		elsif rising_edge(CLK) then
			if CA(22) = '0' and CA(15 downto 8) = x"48" and CA(7) = '0' then 
				case CA(6 downto 0) is
					when "0000000" =>						--4800
						DO <= DEC_BUF_OUT;
					when "0000001" =>						--4801
						DO <= DECREGS.POINTER(7 downto 0);
					when "0000010" =>						--4802
						DO <= DECREGS.POINTER(15 downto 8);
					when "0000011" =>						--4803
						DO <= DECREGS.POINTER(23 downto 16);
					when "0000100" =>						--4804
						DO <= DECREGS.INDEX;
					when "0000101" =>						--4805
						DO <= DECREGS.OFFSET(7 downto 0);
					when "0000110" =>						--4806
						DO <= DECREGS.OFFSET(15 downto 8);
					when "0000111" =>						--4807
						DO <= (others => '0');
					when "0001000" =>						--4808
						DO <= (others => '0');
					when "0001001" =>						--4809
						DO <= DECREGS.COUNTER(7 downto 0);
					when "0001010" =>						--480A
						DO <= DECREGS.COUNTER(15 downto 8);
					when "0001011" =>						--480B
						DO <= "000000" & DECREGS.MODE;
					when "0001100" =>						--480C
						DO <= DEC_DONE & "0000000";
						
					when "0010000" =>						--4810
						DO <= DP_DATA_OUT;
					when "0010001" =>						--4811
						DO <= DATREGS.POINTER(7 downto 0);
					when "0010010" =>						--4812
						DO <= DATREGS.POINTER(15 downto 8);
					when "0010011" =>						--4813
						DO <= DATREGS.POINTER(23 downto 16);
					when "0010100" =>						--4814
						DO <= DATREGS.ADJUST(7 downto 0);
					when "0010101" =>						--4815
						DO <= DATREGS.ADJUST(15 downto 8);
					when "0010110" =>						--4816
						DO <= DATREGS.INCREMENT(7 downto 0);
					when "0010111" =>						--4817
						DO <= DATREGS.INCREMENT(15 downto 8);
					when "0011000" =>						--4818
						DO <= "0" & DATREGS.MODE;
					when "0011001" =>						--4819
						DO <= x"00";	
					when "0011010" =>						--481A
						DO <= DP_DATA_OUT;
					when "0101000" =>						--4828
						DO <= MULDIV_RES(7 downto 0);
					when "0101001" =>						--4829
						DO <= MULDIV_RES(15 downto 8);
					when "0101010" =>						--482A
						DO <= MULDIV_RES(23 downto 16);
					when "0101011" =>						--482B
						DO <= MULDIV_RES(31 downto 24);
					when "0101100" =>						--482C
						DO <= REM_RES(7 downto 0);
					when "0101101" =>						--482D
						DO <= REM_RES(15 downto 8);
					when "0101110" =>						--482E
						DO <= "0000000" & SIGN;
					when "0101111" =>						--482F
						DO <= ALU_BUSY & "0000000";
					when "0110000" =>						--4830
						DO <= SRAM_EN & "0000000";
					when "0110001" =>						--4831
						DO <= "0000" & BANKD;
					when "0110010" =>						--4832
						DO <= "0000" & BANKE;
					when "0110011" =>						--4833
						DO <= "0000" & BANKF;
					
					when "1000001" =>						--4841
						DO <= "0000" & RTC_DI;
					when "1000010" =>						--4842
						DO <= x"80";
						
					when others => null;
				end case; 
			elsif CA(23 downto 16) = x"50" then
				DO <= DEC_BUF_OUT;
			end if;
		end if;
	end process;
	
	process( RST_N, CLK)
	variable OFFS : std_logic_vector(23 downto 0);
	begin
		if RST_N = '0' then
			WS <= WS_IDLE;
			DEC_ADDR <= (others => '0');
			DEC_MODE <= (others => '0');
			LOAD_ADDR_POS <= (others => '0');
			
			DROM_ADDR <= (others => '0');
			DROM_READ <= '0';
			
			FIFO_D <= (others => '0');
			FIFO_WR <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				FIFO_WR <= '0';
				case WS is
					when WS_IDLE =>
						if LOAD_RUN = '1' then
							WS <= WS_LOAD_ADDR1;
						elsif DP_READ = '1' then
							WS <= WS_DP_READ1;
						elsif FIFO_FULL = '0' and (DS = DS_DECODING or DS = DS_PRELOAD) then
							WS <= WS_LOAD_FIFO1;
						end if;
					
					when WS_LOAD_ADDR1 =>
						WS <= WS_LOAD_ADDR2;
						
					when WS_LOAD_ADDR2 =>
						DROM_ADDR <= std_logic_vector( unsigned(DECREGS.POINTER) + (unsigned(DECREGS.INDEX) & LOAD_ADDR_POS) );
						DROM_READ <= '1';
						WS <= WS_LOAD_ADDR3;
						
					when WS_LOAD_ADDR3 =>
						if DROM_RDY = '1' then
							case LOAD_ADDR_POS is
								when "00" => DEC_MODE <= DROM_DO(1 downto 0);
								when "01" => DEC_ADDR(23 downto 16) <= DROM_DO;
								when "10" => DEC_ADDR(15 downto 8) <= DROM_DO;
								when others => DEC_ADDR(7 downto 0) <= DROM_DO;
							end case;
							LOAD_ADDR_POS <= LOAD_ADDR_POS + 1;
							if LOAD_ADDR_POS = 3 then
								WS <= WS_IDLE;
							else
								WS <= WS_LOAD_ADDR2;
							end if;
							DROM_READ <= '0';
						end if;
					
					when WS_LOAD_FIFO1 =>
						DROM_ADDR <= DEC_ADDR;
						DROM_READ <= '1';
						WS <= WS_LOAD_FIFO2;
							
					when WS_LOAD_FIFO2 =>
						if DROM_RDY = '1' then
							FIFO_D <= DROM_DO;
							FIFO_WR <= '1';
							DEC_ADDR <= std_logic_vector( unsigned(DEC_ADDR) + 1 );
							DROM_READ <= '0';
							WS <= WS_LOAD_FIFO3;
						end if;
						
					when WS_LOAD_FIFO3 =>
						WS <= WS_IDLE;

					when WS_DP_READ1 =>
						if DATREGS.MODE(1) = '0' then
							OFFS := (others => '0');
						else
							OFFS := (7 downto 0 => DATREGS.ADJUST(15) and DATREGS.MODE(3)) & DATREGS.ADJUST;
						end if;
						DROM_ADDR <= std_logic_vector( unsigned(DATREGS.POINTER) + unsigned(OFFS) );
						DROM_READ <= '1';
						WS <= WS_DP_READ2;
					
					when WS_DP_READ2 =>
						if DROM_RDY = '1' then
							DP_DATA_OUT <= DROM_DO;
							DROM_READ <= '0';
							WS <= WS_IDLE;
						end if;
						
					when others => null;
				end case;
			end if;
		end if;
	end process;
	
	process( RST_N, CLK)
	begin
		if RST_N = '0' then
			DS <= DS_IDLE;
			DEC_RUN <= '0';
			DEC_INIT <= '0';
			DEC_BUF <= (others => (others => '0'));
			DEC_BUF_WR_ADDR <= (others => '0');
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				DEC_INIT <= '0';
				case DS is
					when DS_IDLE =>
						if DEC_START = '1' then
							DEC_RUN <= '0';
							DS <= DS_PRELOAD;
						end if;
				
					when DS_PRELOAD =>
						if FIFO_FULL = '1' then
							DEC_INIT <= '1';
							DS <= DS_INIT;
						end if;
					
					when DS_INIT =>
						DEC_INIT <= '0';
						DEC_RUN <= '1';
						DEC_BUF_WR_ADDR <= (others => '0');
						DS <= DS_DECODING;
					
					when DS_DECODING =>
						if LOAD_RUN = '1' or DP_READ = '1' then
							DEC_RUN <= '0';
							DS <= DS_IDLE;
						elsif DEC_OUT_WR = '1' then
							case DEC_MODE is
								when "00" =>
									DEC_BUF(to_integer(DEC_BUF_WR_ADDR)) <= DEC_DAT_OUT(7 downto 0);
									DEC_BUF_WR_ADDR <= DEC_BUF_WR_ADDR + 1;
									if DEC_BUF_WR_ADDR(4 downto 0) = 31 then
										if DECREGS.MODE = "00" or DECREGS.OFFSET = x"0000" then
											DEC_RUN <= '0';
										end if;
									end if;
								when "01" =>
									DEC_BUF(to_integer(DEC_BUF_WR_ADDR)) <= DEC_DAT_OUT(15)&DEC_DAT_OUT(13)&DEC_DAT_OUT(11)&DEC_DAT_OUT(9)&DEC_DAT_OUT(7)&DEC_DAT_OUT(5)&DEC_DAT_OUT(3)&DEC_DAT_OUT(1);
									DEC_BUF(to_integer(DEC_BUF_WR_ADDR)+1) <= DEC_DAT_OUT(14)&DEC_DAT_OUT(12)&DEC_DAT_OUT(10)&DEC_DAT_OUT(8)&DEC_DAT_OUT(6)&DEC_DAT_OUT(4)&DEC_DAT_OUT(2)&DEC_DAT_OUT(0);
									DEC_BUF_WR_ADDR <= DEC_BUF_WR_ADDR + 2;
									if DEC_BUF_WR_ADDR(4 downto 0) = 30 then
										if DECREGS.MODE = "00" or DECREGS.OFFSET = x"0000" then
											DEC_RUN <= '0';
										end if;
									end if;
								when others =>
									DEC_BUF(to_integer(DEC_BUF_WR_ADDR)) <= DEC_DAT_OUT(31)&DEC_DAT_OUT(27)&DEC_DAT_OUT(23)&DEC_DAT_OUT(19)&DEC_DAT_OUT(15)&DEC_DAT_OUT(11)&DEC_DAT_OUT(7)&DEC_DAT_OUT(3);
									DEC_BUF(to_integer(DEC_BUF_WR_ADDR)+1) <= DEC_DAT_OUT(30)&DEC_DAT_OUT(26)&DEC_DAT_OUT(22)&DEC_DAT_OUT(18)&DEC_DAT_OUT(14)&DEC_DAT_OUT(10)&DEC_DAT_OUT(6)&DEC_DAT_OUT(2);
									DEC_BUF(to_integer(DEC_BUF_WR_ADDR)+16) <= DEC_DAT_OUT(29)&DEC_DAT_OUT(25)&DEC_DAT_OUT(21)&DEC_DAT_OUT(17)&DEC_DAT_OUT(13)&DEC_DAT_OUT(9)&DEC_DAT_OUT(5)&DEC_DAT_OUT(1);
									DEC_BUF(to_integer(DEC_BUF_WR_ADDR)+17) <= DEC_DAT_OUT(28)&DEC_DAT_OUT(24)&DEC_DAT_OUT(20)&DEC_DAT_OUT(16)&DEC_DAT_OUT(12)&DEC_DAT_OUT(8)&DEC_DAT_OUT(4)&DEC_DAT_OUT(0);
									DEC_BUF_WR_ADDR <= DEC_BUF_WR_ADDR + 2;
									if DEC_BUF_WR_ADDR(3 downto 0) = 14 then
										DEC_BUF_WR_ADDR <= DEC_BUF_WR_ADDR + 2 + 16;
										if DECREGS.MODE = "00" or DECREGS.OFFSET = x"0000" then
											DEC_RUN <= '0';
										end if;
									end if;
							end case;
						elsif DEC_RUN = '0' and DEC_BUF_RD_ADDR(5) /= DEC_BUF_WR_ADDR(5) then
							DEC_RUN <= '1';
						end if;
						
					when others => null;
				end case;
			end if;
		end if;
	end process; 
	
	DEC_BUF_OUT <= DEC_BUF(to_integer(DEC_BUF_RD_ADDR));
	
	
	FIFO : entity work.SPC7110_FIFO
	PORT MAP (
		clock 	=> CLK,
		data 		=> FIFO_D,
		rdreq 	=> FIFO_RD,
		wrreq 	=> FIFO_WR,
		sclr 		=> FIFO_CLR,
		full 		=> FIFO_FULL,
		q 			=> FIFO_Q
	);
	FIFO_RD <= DEC_IN_RD;
	FIFO_CLR <= DEC_START;
	
	dec : entity work.SPC7110_DEC
	PORT MAP (
		RST_N 	=> RST_N,
		CLK 		=> CLK,
		ENABLE 	=> '1',
		
		DI 		=> FIFO_Q,
		RD 		=> DEC_IN_RD,
		
		INIT 		=> DEC_INIT,
		RUN 		=> DEC_RUN,
		MODE 		=> DEC_MODE,
		
		DAT_OUT 	=> DEC_DAT_OUT,
		WR 		=> DEC_OUT_WR
	);
	
	process( CA, BANKD, BANKE, BANKF )
	begin
		case CA(23 downto 20) is
			when x"D" =>
				MAP_ROM_A <= BANKD & CA(19 downto 0);
			when x"E" =>
				MAP_ROM_A <= BANKE & CA(19 downto 0);
			when others =>
				MAP_ROM_A <= BANKF & CA(19 downto 0);
		end case;
	end process; 
	
	SNES_DROM_A <= MAP_ROM_A(22 downto 0);
	SNES_DROM_OE_N <= '0' when CA(23 downto 20) >= x"D" else '1';
	
	DROM_A <= DROM_ADDR(22 downto 0);
	DROM_OE_N <= not DROM_READ;
	
	PROM_OE_N <= '0' when CA(22 downto 20) = "100" or (CA(22) = '0' and CA(15) = '1') else '1';
	SRAM_CE_N <= not SRAM_EN when CA(22) = '0' and CA(15 downto 13) = "011" else '1';
	
	UMULT : entity work.SPC7110_UMULT
	PORT MAP (
		dataa 	=> MULTIPLICAND,
		datab 	=> MULTIPLIER,
		result 	=> UMUL_RES
	);
	
	SMULT : entity work.SPC7110_SMULT
	PORT MAP (
		dataa 	=> MULTIPLICAND,
		datab 	=> MULTIPLIER,
		result 	=> SMUL_RES
	);
	
	UDIV : entity work.SPC7110_UDIV
	PORT MAP (
		clock 	=> CLK,
		numer 	=> DIVIDEND,
		denom 	=> DIVISOR,
		quotient => UDIV_QUOT,
		remain 	=> UDIV_REM
	);
	
	SDIV : entity work.SPC7110_SDIV
	PORT MAP (
		clock 	=> CLK,
		numer 	=> DIVIDEND,
		denom 	=> DIVISOR,
		quotient => SDIV_QUOT,
		remain 	=> SDIV_REM
	);

	
end rtl;
