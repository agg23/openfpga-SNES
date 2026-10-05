library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;


entity SDD1 is
	generic (ROM_HANDSHAKE : boolean := false);
	port(
        SNES_READ_INTENT, SNES_RETIRE : in std_logic := '0';
        SNES_ROM_DATA : in std_logic_vector(7 downto 0) := (others=>'0');
        SNES_ROM_ADDR, DEC_ROM_ADDR : out std_logic_vector(23 downto 0);
        DEC_ROM_NEED, DEC_ROM_RETIRE : out std_logic;
        DEC_ROM_READY : in std_logic := '0';
        DATA_WAIT, DECOMP_READ : out std_logic;

		RST_N			: in  std_logic;
		CLK			: in  std_logic;
		ENABLE		: in  std_logic;

		CA   			: in  std_logic_vector(23 downto 0);
		DO				: out std_logic_vector(7 downto 0);
		DI				: in  std_logic_vector(7 downto 0);
		CPURD_N		: in  std_logic;
		CPUWR_N		: in  std_logic;
		ROMSEL_N		: in std_logic;

		SYSCLKF_CE	: in  std_logic;
		SYSCLKR_CE	: in  std_logic;

		ROM_A       : out std_logic_vector(23 downto 0);
		ROM_DO		: in  std_logic_vector(15 downto 0);
		ROM_RD_N		: out std_logic
	);
end SDD1;

architecture rtl of SDD1 is

	-- IO Registers
	signal DMAEN	: std_logic_vector(7 downto 0);
	signal DMARUN	: std_logic_vector(7 downto 0);
	signal ROMBANKC	: std_logic_vector(3 downto 0);
	signal ROMBANKD	: std_logic_vector(3 downto 0);
	signal ROMBANKE	: std_logic_vector(3 downto 0);
	signal ROMBANKF	: std_logic_vector(3 downto 0);

	type DmaReg16 is array (0 to 7) of std_logic_vector(15 downto 0);
	type DmaReg24 is array (0 to 7) of std_logic_vector(23 downto 0);
	signal DMAA	: DmaReg24;
	signal DMAS	: DmaReg16;

	impure function GetDMACh(data: std_logic_vector(7 downto 0)) return integer is
	variable res: integer range 0 to 7; 
	begin
		if data(0) = '1' then
			res := 0;
		elsif data(1) = '1' then
			res := 1;
		elsif data(2) = '1' then
			res := 2;
		elsif data(3) = '1' then
			res := 3;
		elsif data(4) = '1' then
			res := 4;
		elsif data(5) = '1' then
			res := 5;
		elsif data(6) = '1' then
			res := 6;
		elsif data(7) = '1' then
			res := 7;
		else
			res := 0;
		end if;
		return res;
	end function; 
	
	--Decoder
	signal DEC_A	: std_logic_vector(23 downto 0);
	signal DEC_DO	: std_logic_vector(15 downto 0);
	signal DEC_INIT, DEC_RUN	: std_logic;
	signal DEC_CUR_ADDR	: std_logic_vector(23 downto 0);
	signal DEC_CUR_SIZE	: std_logic_vector(15 downto 0);
	signal DEC_PLANE_DONE, DEC_DONE, DEC_INIT_DONE	: std_logic;
	signal DEC_OUT_DATA0, DEC_OUT_DATA1: std_logic_vector(7 downto 0);
	
	signal SNES_A	   : std_logic_vector(23 downto 0);
	signal MAP_ROM_A	: std_logic_vector(23 downto 0);
	signal WORK_ADDR	: std_logic_vector(23 downto 0);
	signal ROM_DATA	: std_logic_vector(7 downto 0);
	
	type ds_t is (
		DS_IDLE,
		DS_INIT,
		DS_WAIT_INIT,
		DS_PREDECODING,
		DS_DECODING
	);
	signal DS : ds_t;  
	
	signal DMA_CH : integer range 0 to 7; 
	signal DMA_EXEC : std_logic;
	signal DEC_START : std_logic;
	signal SNES_ACCESS : std_logic;
	signal OUT_DATA_SEL : std_logic;
	signal DEC_EN : std_logic;
	signal TRANSFERING : std_logic;

	signal HEADER : std_logic_vector(3 downto 0);
	signal DEC_IN_DATA : std_logic_vector(15 downto 0);
	signal IM_DATA_REQ : std_logic;
	signal CPUWR_N_OLD : std_logic;
	signal RD_PULSE : std_logic;
	signal PULSE_CNT : unsigned(1 downto 0);
    signal IM_READY, OUT_VALID, OUT_READY, BYTE_RETIRE : std_logic;
    function MapAddress(a : std_logic_vector(23 downto 0);
        bc, bd, be, bf : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        if a(22)='0' and a(15)='1' then
            return "0" & a(23 downto 16) & a(14 downto 0);
        elsif a(23 downto 22)="11" then
            case a(21 downto 20) is
                when "00" => return bc & a(19 downto 0);
                when "01" => return bd & a(19 downto 0);
                when "10" => return be & a(19 downto 0);
                when others => return bf & a(19 downto 0);
            end case;
        else return x"FFFFFF";
        end if;
    end function;
	
begin

	DMA_CH <= GetDMACh(DMAEN and DMARUN);
	
	DEC_CUR_ADDR <= DMAA(DMA_CH);
	DEC_CUR_SIZE <= DMAS(DMA_CH);
	
	SNES_ACCESS <= not (CPUWR_N and CPURD_N) and not ROMSEL_N;

	process( RST_N, CLK)
		variable i : integer range 0 to 7; 
	begin
		if RST_N = '0' then
			DMAA <= (others => (others => '0'));
			DMAS <= (others => (others => '0'));
			DMAEN <= (others => '0');
			DMARUN <= (others => '0');
			ROMBANKC <= x"0";
			ROMBANKD <= x"1";
			ROMBANKE <= x"2";
			ROMBANKF <= x"3";
			OUT_DATA_SEL <= '0';
			DEC_START <= '0';
            CPUWR_N_OLD <= '1';
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				DEC_START <= '0';
				
				if CPUWR_N = '0' and SYSCLKF_CE = '1' then
					if CA(22) = '0' and CA(15 downto 8) = x"43" and CA(7) = '0' then 
						i := to_integer(unsigned(CA(6 downto 4))); 
						case CA(3 downto 0) is
							when x"2" =>
								DMAA(i)(7 downto 0) <= DI;
							when x"3" =>
								DMAA(i)(15 downto 8) <= DI;
							when x"4" =>
								DMAA(i)(23 downto 16) <= DI;
							when x"5" =>
								DMAS(i)(7 downto 0) <= DI;
							when x"6" =>
								DMAS(i)(15 downto 8) <= DI;
							when others => null;
						end case; 
					elsif CA(22) = '0' and CA(15 downto 4) = x"480" then 
						case CA(3 downto 0) is
							when x"0" =>
								DMAEN <= DI;
							when x"1" =>
--								DMARUN <= DI;
--								if (DI and DMAEN) /= x"00" then
--									DEC_START <= '1';
--									OUT_DATA_SEL <= '0';
--								end if;
							when x"4" =>
								ROMBANKC <= DI(3 downto 0);
							when x"5" =>
								ROMBANKD <= DI(3 downto 0);
							when x"6" =>
								ROMBANKE <= DI(3 downto 0);
							when x"7" =>
								ROMBANKF <= DI(3 downto 0);
							when others => null;
						end case; 
					end if;
				elsif BYTE_RETIRE = '1' then
					if CA = DEC_CUR_ADDR then
						OUT_DATA_SEL <= not OUT_DATA_SEL;
						DMAS(DMA_CH) <= std_logic_vector(unsigned(DMAS(DMA_CH)) - 1);
						if DMAS(DMA_CH) = x"0001" then
							DMARUN(DMA_CH) <= '0';
                            if ROM_HANDSHAKE then OUT_DATA_SEL <= '0'; end if;
						end if;
					end if;
				end if;
				
				CPUWR_N_OLD <= CPUWR_N;
				if CA(22) = '0' and CA(15 downto 0) = x"4801" and CPUWR_N = '0' and CPUWR_N_OLD = '1' then
					DMARUN <= DI;
					if (DI and DMAEN) /= x"00" then
						DEC_START <= '1';
						OUT_DATA_SEL <= '0';
					end if;
				end if;
			end if;
		end if;
	end process; 
	
    legacy_control: if not ROM_HANDSHAKE generate

	process( RST_N, CLK)
	begin
		if RST_N = '0' then
			DS <= DS_IDLE;
			DEC_RUN <= '0';
			DMA_EXEC <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				case DS is
					when DS_IDLE =>
						DEC_RUN <= '0';
						if DEC_START = '1' then
							DMA_EXEC <= '0';
							DS <= DS_INIT;
						end if;
						
					when DS_INIT =>
						DS <= DS_WAIT_INIT;
						
					when DS_WAIT_INIT =>	
						if DEC_INIT_DONE = '1' then
							DEC_RUN <= '1';
							DS <= DS_PREDECODING;
						end if;
						
					when DS_PREDECODING =>
						if DEC_PLANE_DONE = '1' then
							DEC_RUN <= '0';
							DS <= DS_DECODING;
						end if;
					
					when DS_DECODING =>
						if DEC_DONE = '1' then
							DS <= DS_IDLE;
						end if;
						
						if DEC_PLANE_DONE = '1' then
							DEC_RUN <= '0';
						end if;

						if CA = DEC_CUR_ADDR and OUT_DATA_SEL = '1' and CPURD_N = '0' and SYSCLKF_CE = '1' then
							DEC_RUN <= '1';
						end if;

					when others => null;
				end case; 
				
				if DS /= DS_IDLE and CA = DEC_CUR_ADDR and DMA_EXEC = '0' then
					DMA_EXEC <= '1';
				end if;
			end if;
		end if;
	end process; 
	
    end generate;

    transaction_control: if ROM_HANDSHAKE generate
        process(CLK, RST_N)
        begin
            if RST_N='0' then
                DS<=DS_IDLE; DEC_RUN<='0'; DMA_EXEC<='0';
            elsif rising_edge(CLK) then
                if ENABLE='1' then
                    if DEC_START='1' then
                        DS<=DS_INIT; DEC_RUN<='0'; DMA_EXEC<='1';
                    else
                        case DS is
                            when DS_INIT => DS<=DS_WAIT_INIT;
                            when DS_WAIT_INIT =>
                                if DEC_INIT_DONE='1' then
                                    DS<=DS_DECODING; DEC_RUN<='1';
                                end if;
                            when DS_DECODING =>
                                if DEC_DONE='1' then DEC_RUN<='0'; end if;
                                if DMARUN=x"00" then DS<=DS_IDLE; DEC_RUN<='0'; end if;
                                if BYTE_RETIRE='1' and DEC_CUR_SIZE=x"0001" then
                                    DEC_RUN<='0';
                                    if (DMAEN and DMARUN)/=std_logic_vector(shift_left(to_unsigned(1,8),DMA_CH)) then
                                        -- The selected channel changes after this edge.
                                        -- INIT observes its own source, size and lane.
                                        DS<=DS_INIT;
                                    else DS<=DS_IDLE;
                                    end if;
                                end if;
                            when others => null;
                        end case;
                    end if;
                end if;
            end if;
        end process;
    end generate;

	DEC_EN <= '1' when (DS = DS_WAIT_INIT) and SNES_ACCESS = '0' else
				 '1' when (DS = DS_DECODING or DS = DS_PREDECODING) and DMA_EXEC = '1' else 
				 '0';
	
	DEC_INIT <= '1' when DS = DS_INIT else '0';
	
	IM: entity work.InputMgr
    generic map (ROM_HANDSHAKE => ROM_HANDSHAKE)
	port map (
		CLK			=> CLK,
		RST_N			=> RST_N,
		ENABLE		=> ENABLE,
		
        ROM_NEED => DEC_ROM_NEED, ROM_READY => DEC_ROM_READY,
        ROM_RETIRE => DEC_ROM_RETIRE, DATA_READY => IM_READY,
		INIT_ADDR	=> DEC_CUR_ADDR,
		
		INIT			=> DEC_INIT,
		DATA_REQ		=> IM_DATA_REQ,

		ROM_ADDR   	=> DEC_A,
		ROM_DATA 	=> ROM_DO,
		
		ROM_RD   	=> RD_PULSE and DEC_EN,
		
		OUT_DATA   	=> DEC_IN_DATA,
		HEADER		=> HEADER,
		
		INIT_DONE	=> DEC_INIT_DONE
	); 
	
	DEC: entity work.SDD1_Decoder
    generic map (ROM_HANDSHAKE => ROM_HANDSHAKE)
	port map (
		CLK			=> CLK,
		RST_N			=> RST_N,
		ENABLE		=> ENABLE,
		
        INPUT_READY => IM_READY, OUTPUT_READY => OUT_READY,
		INIT_SIZE	=> DEC_CUR_SIZE,
		IN_DATA		=> DEC_IN_DATA,
		HEADER		=> HEADER,
		
		INIT			=> DEC_INIT,
		RUN			=> DEC_RUN,
		DATA_REQ		=> IM_DATA_REQ,

		DO   			=> DEC_DO,
		
		PLANE_DONE	=> DEC_PLANE_DONE,
		DONE 			=> DEC_DONE
	); 
	
    legacy_output: if not ROM_HANDSHAKE generate
        OUT_VALID <= '1'; OUT_READY <= '1';
        process(CLK, RST_N)
        begin
            if RST_N='0' then
                DEC_OUT_DATA0 <= (others=>'0'); DEC_OUT_DATA1 <= (others=>'0');
            elsif rising_edge(CLK) then
                if DEC_PLANE_DONE='1' and DEC_RUN='1' then
                    DEC_OUT_DATA0 <= DEC_DO(7 downto 0);
                    DEC_OUT_DATA1 <= DEC_DO(15 downto 8);
                end if;
            end if;
        end process;
    end generate;
    transaction_output: if ROM_HANDSHAKE generate
        OUT_READY <= '1' when OUT_VALID='0' or
            (BYTE_RETIRE='1' and (OUT_DATA_SEL='1' or DEC_CUR_SIZE=x"0001")) else '0';
        process(CLK, RST_N)
        begin
            if RST_N='0' then
                OUT_VALID<='0'; DEC_OUT_DATA0<=(others=>'0'); DEC_OUT_DATA1<=(others=>'0');
            elsif rising_edge(CLK) then
                if ENABLE='1' then
                    if DEC_INIT='1' then OUT_VALID<='0';
                    else
                        if BYTE_RETIRE='1' and (OUT_DATA_SEL='1' or DEC_CUR_SIZE=x"0001") then
                            OUT_VALID<='0';
                        end if;
                        if DEC_PLANE_DONE='1' and OUT_READY='1' then
                            DEC_OUT_DATA0<=DEC_DO(7 downto 0);
                            DEC_OUT_DATA1<=DEC_DO(15 downto 8);
                            OUT_VALID<='1';
                        end if;
                    end if;
                end if;
            end if;
        end process;
    end generate;
    BYTE_RETIRE <= SNES_RETIRE and TRANSFERING and OUT_VALID when ROM_HANDSHAKE
        else not CPURD_N and SYSCLKF_CE;
    DATA_WAIT <= SNES_READ_INTENT and TRANSFERING and not OUT_VALID when ROM_HANDSHAKE else '0';
    DECOMP_READ <= TRANSFERING;

	TRANSFERING <= '1' when CA=DEC_CUR_ADDR and
        ((ROM_HANDSHAKE and (DMAEN and DMARUN)/=x"00") or
         (not ROM_HANDSHAKE and DMARUN/=x"00")) else '0';
	
	process(CLK)
	begin
		if rising_edge(CLK) then
			if SYSCLKR_CE = '1' then
				SNES_A <= CA;
			end if;
		end if;
	end process;
	WORK_ADDR <= SNES_A when DEC_EN = '0' else DEC_A;
	
    MAP_ROM_A <= MapAddress(WORK_ADDR, ROMBANKC, ROMBANKD, ROMBANKE, ROMBANKF);
    SNES_ROM_ADDR <= MapAddress(CA, ROMBANKC, ROMBANKD, ROMBANKE, ROMBANKF);
    DEC_ROM_ADDR <= MapAddress(DEC_A, ROMBANKC, ROMBANKD, ROMBANKE, ROMBANKF);

	process( TRANSFERING, CA, DMAEN, DMARUN, ROMBANKC, ROMBANKD, ROMBANKE, ROMBANKF, 
			   ROM_DATA, OUT_DATA_SEL, DEC_OUT_DATA0, DEC_OUT_DATA1 )
	begin
		if TRANSFERING = '0' then
			if CA(22) = '0' and CA(15 downto 4) = x"480" then 
				case CA(3 downto 0) is
					when x"0" =>
						DO <= DMAEN;
					when x"1" =>
						DO <= DMARUN;
					when x"4" =>
						DO <= x"0" & ROMBANKC;
					when x"5" =>
						DO <= x"0" & ROMBANKD;
					when x"6" =>
						DO <= x"0" & ROMBANKE;
					when x"7" =>
						DO <= x"0" & ROMBANKF;
					when others =>
						DO <= x"00";
				end case;
			else
				DO <= ROM_DATA;
			end if;
		else
			if OUT_DATA_SEL = '0' then
				DO <= DEC_OUT_DATA0;
			else
				DO <= DEC_OUT_DATA1;
			end if;
		end if;
	end process;
	
	ROM_A <= MAP_ROM_A;
	ROM_DATA <= SNES_ROM_DATA when ROM_HANDSHAKE else
                ROM_DO(7 downto 0) when MAP_ROM_A(0) = '0' else ROM_DO(15 downto 8);

	RD_PULSE <= SYSCLKF_CE or SYSCLKR_CE when rising_edge(CLK);
	ROM_RD_N <= not RD_PULSE;
	
end rtl;
