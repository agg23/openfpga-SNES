library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;
library work;

entity DATAPAK is
	port(
		CLK			: in std_logic;
		RST_N			: in std_logic;
		ENABLE		: in std_logic;
		
		A   			: in std_logic_vector(19 downto 0);
		DI				: in std_logic_vector(7 downto 0);
		DO				: out std_logic_vector(7 downto 0);
		CE_N			: in std_logic;
		RD_N			: in std_logic;
		WR_N			: in std_logic;
		SYSCLKF_CE	: in std_logic;
		SYSCLKR_CE	: in std_logic;
		
		MEM_ADDR   	: out std_logic_vector(19 downto 0);
		MEM_DI		: in std_logic_vector(7 downto 0);
		MEM_DO		: out std_logic_vector(7 downto 0);
		MEM_RD		: out std_logic;
		MEM_WR		: out std_logic
	);
end DATAPAK;

architecture rtl of DATAPAK is
	
	signal IO_REG				: std_logic_vector(13 downto 0);
	signal PREV_COM			: std_logic_vector(7 downto 0);
	signal CSR					: std_logic;
	signal ESR					: std_logic;
	signal VEN					: std_logic;
	signal BYTE_WRITE			: std_logic;
	
	type FlashStates_t is (
		FS_IDLE,
		FS_READ,
		FS_WRITE,
		FS_ERASE
	);
	signal FS 					: FlashStates_t; 
	signal WRITE_ADDR			: std_logic_vector(19 downto 0);
	signal WRITE_DATA			: std_logic_vector(7 downto 0);
	signal READ_DATA			: std_logic_vector(7 downto 0);
	signal WRITE_PEND			: std_logic;
	signal PAGE_ERASE_PEND	: std_logic;
	signal CHIP_ERASE_PEND	: std_logic;
	
begin
	
	process( RST_N, CLK)
	begin
		if RST_N = '0' then
			CSR <= '0';
			ESR <= '0';
			VEN <= '0';
			BYTE_WRITE <= '0';
			PREV_COM <= (others => '0');
			FS <= FS_IDLE;
			WRITE_PEND <= '0';
			PAGE_ERASE_PEND <= '0';
			CHIP_ERASE_PEND <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				if CE_N = '0' and WR_N = '0' and SYSCLKF_CE = '1' then 
					if BYTE_WRITE = '1' then		--Data write
						if WRITE_PEND = '0' then
							WRITE_ADDR <= A;
							WRITE_DATA <= DI;
							WRITE_PEND <= '1';
							BYTE_WRITE <= '0';
						end if;
					else									--Command write
						PREV_COM <= DI;
						case DI is
							when x"00" | x"FF" =>	--Reset
								CSR <= '0';
								ESR <= '0';
								VEN <= '0';
							when x"10" | x"40" =>	--Byte write
								BYTE_WRITE <= '1';
							when x"70" =>				--CSR enable
								CSR <= '1';
							when x"71" =>				--ESR enable
								ESR <= '1';
							when x"75" =>				--Vendor Info enable
								VEN <= '1';
							when x"D0" =>				--Double Byte Commands 
								case PREV_COM is
									when x"20" =>		--Page erase 
										if PAGE_ERASE_PEND = '0' then
											WRITE_ADDR <= A(19 downto 16)&x"0000";
											WRITE_DATA <= x"FF";
											PAGE_ERASE_PEND <= '1';
										end if;
									when x"A7" =>		--Chip erase 
										if CHIP_ERASE_PEND = '0' then
											WRITE_ADDR <= (others => '0');
											WRITE_DATA <= x"FF";
											CHIP_ERASE_PEND <= '1';
										end if;
									when others => null;
								end case;
							when others => null;
						end case; 
					end if;
				elsif CE_N = '0' and RD_N = '0' and SYSCLKF_CE = '1' then 
					if ESR = '1' and (A(15 downto 0) = x"0002" or A(15 downto 0) = x"0004") then 
						
					elsif CSR = '1' then 
						CSR <= '0';
					end if;
				end if;
				
				if SYSCLKR_CE = '1' then
					READ_DATA <= MEM_DI;
				end if;
				
				if SYSCLKF_CE = '1' then
					case FS is
						when FS_IDLE =>
							if WRITE_PEND = '1' then
								FS <= FS_READ;
							elsif PAGE_ERASE_PEND = '1' or CHIP_ERASE_PEND = '1' then
								FS <= FS_ERASE;
							end if;
							
						when FS_READ =>
							WRITE_DATA <= WRITE_DATA and READ_DATA;
							FS <= FS_WRITE;
							
						when FS_WRITE =>
							WRITE_PEND <= '0';
							FS <= FS_IDLE;
							
						when FS_ERASE =>
							WRITE_ADDR <= std_logic_vector( unsigned(WRITE_ADDR) + 1 );
							if WRITE_ADDR(15 downto 0) = x"FFFF" and (WRITE_ADDR(19 downto 16) = x"F" or CHIP_ERASE_PEND = '0') then
								PAGE_ERASE_PEND <= '0';
								CHIP_ERASE_PEND <= '0';
								FS <= FS_IDLE;
							end if;
							
						when others => null;
					end case; 
				end if;
			end if;
		end if;
	end process;
	
	MEM_ADDR <= WRITE_ADDR;
	MEM_DO <= WRITE_DATA;
	MEM_RD <= '1' when FS = FS_READ else '0';
	MEM_WR <= '1' when FS = FS_WRITE or FS = FS_ERASE else '0';
	
	
	process( RST_N, CLK)
	begin
		if RST_N = '0' then
			DO <= (others => '0');
		elsif rising_edge(CLK) then
			if ESR = '1' and A(15 downto 0) = x"0002" then 
				DO <= x"C0";
			elsif ESR = '1' and A(15 downto 0) = x"0004" then 
				DO <= not CHIP_ERASE_PEND & "0000010";
			elsif CSR = '1' then 
				DO <= not (WRITE_PEND or PAGE_ERASE_PEND) & "0000000";
			elsif VEN = '1' and A(14 downto 8) = "1111111" then 
				case A(7 downto 0) is
					when x"00" => DO <= x"4D";
					when x"01" => DO <= x"00";
					when x"02" => DO <= x"50";
					when x"03" => DO <= x"00";
					when x"04" => DO <= x"00";
					when x"05" => DO <= x"00";
					when x"06" => DO <= x"1A";
					when x"07" => DO <= x"00";
					when others =>DO <= x"00";
				end case;
			else
				DO <= MEM_DI;
			end if;
		end if;
	end process;
	
end rtl;