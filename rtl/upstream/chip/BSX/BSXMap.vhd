library STD;
use STD.TEXTIO.ALL;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;

entity BSXMap is
    generic (ROM_TRANSACTIONAL : boolean := false);
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

        ROM_HARD_RESET_N : in std_logic := '1';
        ROM_EPOCH : in std_logic_vector(7 downto 0) := (others=>'0');
        ROM_FLUSH : in std_logic := '0';
        ROM_FLUSH_ACK, ROM_FAULT : out std_logic;
        ROM_SNES_READ_INTENT, ROM_SNES_WRITE_INTENT : in std_logic := '0';
        ROM_SNES_OWNER : in std_logic_vector(1 downto 0) := (others=>'0');
        ROM_SNES_RETIRE : in std_logic := '0';
        ROM_SNES_WRITE_DATA : in std_logic_vector(7 downto 0) := (others=>'0');
        ROM_SNES_WAIT, ROM_SNES_WRITE_WAIT : out std_logic;
        ROM_REQ_VALID : out std_logic;
        ROM_REQ_READY : in std_logic := '0';
        ROM_REQ_ADDR : out std_logic_vector(22 downto 0);
        ROM_REQ_OWNER, ROM_REQ_SNES_OWNER : out std_logic_vector(1 downto 0);
        ROM_REQ_TAG, ROM_REQ_EPOCH : out std_logic_vector(7 downto 0);
        ROM_REQ_WRITE, ROM_REQ_DRAIN : out std_logic;
        ROM_REQ_WDATA : out std_logic_vector(15 downto 0);
        ROM_REQ_WSTRB : out std_logic_vector(1 downto 0);
        ROM_RSP_VALID : in std_logic := '0';
        ROM_RSP_READY : out std_logic;
        ROM_RSP_OWNER : in std_logic_vector(1 downto 0) := (others=>'0');
        ROM_RSP_TAG, ROM_RSP_EPOCH : in std_logic_vector(7 downto 0) := (others=>'0');
        ROM_RSP_DATA : in std_logic_vector(15 downto 0) := (others=>'0');
        ROM_RSP_ERROR, ROM_RSP_WRITE : in std_logic := '0';

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
	
    signal dp_mem_data, snes_mem_data : std_logic_vector(7 downto 0);
    signal dp_ready, dp_uses_memory, dp_credit, dp_busy : std_logic;
    signal mem_need, mem_retire, mem_writes, mem_committed : std_logic_vector(3 downto 0);
    signal mem_ready, mem_completed, mem_bytes : std_logic_vector(3 downto 0);
    signal mem_addrs : std_logic_vector(91 downto 0);
    signal mem_wdatas, mem_words : std_logic_vector(63 downto 0);
    signal mem_wstrbs : std_logic_vector(7 downto 0);
    signal flush_i, read_memory, post_pending : std_logic;
    signal post_addr : std_logic_vector(22 downto 0);
    signal post_data : std_logic_vector(7 downto 0);
    signal snes_addr : std_logic_vector(22 downto 0);
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
    generic map (MEM_TRANSACTIONAL => ROM_TRANSACTIONAL)
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
		MEM_DI		=> dp_mem_data,
        MEM_READY => dp_ready, SNES_DATA => snes_mem_data,
        READ_USES_MEMORY => dp_uses_memory, WRITE_CREDIT => dp_credit,
        DP_CREDIT_DATA => ROM_SNES_WRITE_DATA, WRITE_BUSY => dp_busy,
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
			snes_mem_data           when PSRAM_CE_N = '0' or BIOS_CE_N = '0' else
			OPENBUS;

    legacy_transport : if not ROM_TRANSACTIONAL generate
        dp_mem_data <= ROM_Q(7 downto 0); snes_mem_data <= ROM_Q(7 downto 0);
        dp_ready <= '1';
        ROM_FLUSH_ACK <= '1'; ROM_FAULT <= '0'; ROM_SNES_WAIT <= '0'; ROM_SNES_WRITE_WAIT <= '0';
        ROM_REQ_VALID <= '0'; ROM_REQ_ADDR <= (others=>'0');
        ROM_REQ_OWNER <= (others=>'0'); ROM_REQ_SNES_OWNER <= (others=>'0');
        ROM_REQ_TAG <= (others=>'0'); ROM_REQ_EPOCH <= (others=>'0');
        ROM_REQ_WRITE <= '0'; ROM_REQ_DRAIN <= '0'; ROM_REQ_WDATA <= (others=>'0'); ROM_REQ_WSTRB <= "00";
        ROM_RSP_READY <= '1';
    end generate;

    transactional_transport : if ROM_TRANSACTIONAL generate
        flush_i <= ROM_FLUSH or not RST_N or not MAP_SEL;
        read_memory <= '1' when MAP_SEL='1' and IOPORT_CE_N='1' and SRAM_CE_N='1' and
            (BIOS_CE_N='0' or PSRAM_CE_N='0' or (DPAK_CE_N='0' and dp_uses_memory='1')) else '0';
        snes_addr <= "001" & ADDR & CA(14 downto 0) when DPAK_CE_N='0' else
                     "0100" & ADDR(18 downto 15) & CA(14 downto 0) when PSRAM_CE_N='0' else
                     "000" & CA(20 downto 16) & CA(14 downto 0);
        mem_need(0) <= ROM_SNES_READ_INTENT and read_memory and not post_pending and not flush_i;
        mem_need(1) <= (DPAK_MEM_RD or DPAK_MEM_WR) and not flush_i;
        mem_need(2) <= post_pending;
        mem_need(3) <= '0';
        mem_retire(0) <= ROM_SNES_RETIRE and ENABLE;
        mem_retire(1) <= mem_ready(1) and ENABLE;
        mem_retire(2) <= mem_completed(2);
        mem_retire(3) <= '0';
        mem_writes <= '0' & '1' & DPAK_MEM_WR & '0';
        mem_committed <= "0100";
        mem_addrs <= (22 downto 0=>'0') & post_addr & ("001" & DPAK_MEM_ADDR) & snes_addr;
        mem_wdatas <= x"0000" & post_data & post_data & DPAK_MEM_DO & DPAK_MEM_DO & x"0000";
        mem_wstrbs(1 downto 0) <= "00";
        mem_wstrbs(3 downto 2) <= "10" when DPAK_MEM_ADDR(0)='1' else "01";
        mem_wstrbs(5 downto 4) <= "10" when post_addr(0)='1' else "01";
        mem_wstrbs(7 downto 6) <= "00";
        dp_ready <= mem_ready(1);
        dp_mem_data <= mem_words(31 downto 24) when mem_bytes(1)='1' else mem_words(23 downto 16);
        snes_mem_data <= mem_words(15 downto 8) when mem_bytes(0)='1' else mem_words(7 downto 0);
        ROM_SNES_WAIT <= ROM_SNES_READ_INTENT and read_memory and (post_pending or not mem_ready(0));
        ROM_SNES_WRITE_WAIT <= '1' when MAP_SEL='1' and ROM_SNES_WRITE_INTENT='1' and
            ((PSRAM_CE_N='0' and post_pending='1') or (DPAK_CE_N='0' and (dp_credit='0' or (ROM_SNES_OWNER/="00" and dp_busy='1')))) else '0';
        -- One credit is reserved by the only producer (SCPU) before its rising
        -- phase. Capturing at F makes this write irrevocable across soft reset.
        process(MCLK, ROM_HARD_RESET_N)
        begin
            if ROM_HARD_RESET_N='0' then
                post_pending<='0'; post_addr<=(others=>'0'); post_data<=(others=>'0');
            elsif rising_edge(MCLK) then
                if mem_completed(2)='1' then post_pending<='0'; end if;
                if ENABLE='1' and flush_i='0' and SYSCLKF_CE='1' and PSRAM_CE_N='0' and CPUWR_N='0' then
                    assert post_pending='0' report "BSX PSRAM posted write without credit" severity failure;
                    post_pending<='1'; post_addr<="0100" & ADDR(18 downto 15) & CA(14 downto 0); post_data<=DI;
                end if;
            end if;
        end process;
        memory_transport : entity work.BSXMemoryBridge port map (
            CLK=>MCLK, ENABLE=>ENABLE, FLUSH=>flush_i, HARD_RESET_N=>ROM_HARD_RESET_N, EPOCH=>ROM_EPOCH,
            NEED=>mem_need, RETIRE=>mem_retire, WRITES=>mem_writes, COMMITTED=>mem_committed,
            ADDRS=>mem_addrs, WDATAS=>mem_wdatas, WSTRBS=>mem_wstrbs, SNES_OWNER=>ROM_SNES_OWNER,
            READY=>mem_ready, COMPLETED=>mem_completed, BYTES=>mem_bytes, WORDS=>mem_words,
            FLUSH_ACK=>ROM_FLUSH_ACK, FAULT=>ROM_FAULT,
            REQ_VALID=>ROM_REQ_VALID, REQ_READY=>ROM_REQ_READY, REQ_ADDR=>ROM_REQ_ADDR,
            REQ_OWNER=>ROM_REQ_OWNER, REQ_SNES_OWNER=>ROM_REQ_SNES_OWNER, REQ_TAG=>ROM_REQ_TAG, REQ_EPOCH=>ROM_REQ_EPOCH,
            REQ_WRITE=>ROM_REQ_WRITE, REQ_DRAIN=>ROM_REQ_DRAIN, REQ_WDATA=>ROM_REQ_WDATA, REQ_WSTRB=>ROM_REQ_WSTRB,
            RSP_VALID=>ROM_RSP_VALID, RSP_READY=>ROM_RSP_READY, RSP_OWNER=>ROM_RSP_OWNER,
            RSP_TAG=>ROM_RSP_TAG, RSP_EPOCH=>ROM_RSP_EPOCH, RSP_DATA=>ROM_RSP_DATA, RSP_ERROR=>ROM_RSP_ERROR, RSP_WRITE=>ROM_RSP_WRITE);
    end generate;

	IRQ_N <= '1';
	
end rtl;
