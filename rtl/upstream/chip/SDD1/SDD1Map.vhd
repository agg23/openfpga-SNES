library STD;
use STD.TEXTIO.ALL;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;

entity SDD1Map is
	generic (ROM_HANDSHAKE : boolean := false);
	port(

        ROM_HARD_RESET_N : in std_logic := '1';
        ROM_EPOCH : in std_logic_vector(7 downto 0) := (others=>'0');
        ROM_FLUSH : in std_logic := '0';
        ROM_FLUSH_ACK, ROM_FAULT : out std_logic;
        ROM_SNES_READ_INTENT : in std_logic := '0';
        ROM_SNES_OWNER : in std_logic_vector(1 downto 0) := "00";
        ROM_SNES_RETIRE : in std_logic := '0';
        ROM_SNES_WAIT : out std_logic;
        ROM_REQ_VALID : out std_logic;
        ROM_REQ_READY : in std_logic := '0';
        ROM_REQ_ADDR : out std_logic_vector(22 downto 0);
        ROM_REQ_OWNER, ROM_REQ_SNES_OWNER : out std_logic_vector(1 downto 0);
        ROM_REQ_TAG, ROM_REQ_EPOCH : out std_logic_vector(7 downto 0);
        ROM_RSP_VALID : in std_logic := '0';
        ROM_RSP_READY : out std_logic;
        ROM_RSP_DATA : in std_logic_vector(15 downto 0) := (others=>'0');
        ROM_RSP_OWNER : in std_logic_vector(1 downto 0) := "00";
        ROM_RSP_TAG, ROM_RSP_EPOCH : in std_logic_vector(7 downto 0) := (others=>'0');
        ROM_RSP_ERROR : in std_logic := '0';
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

		ROM_ADDR		: out std_logic_vector(22 downto 0);
		ROM_Q			: in  std_logic_vector(15 downto 0);
		ROM_CE_N		: out std_logic;
		ROM_OE_N		: out std_logic;
		ROM_WORD		: out std_logic;
		
		BSRAM_ADDR	: out std_logic_vector(19 downto 0);
		BSRAM_D		: out std_logic_vector(7 downto 0);
		BSRAM_Q		: in  std_logic_vector(7 downto 0);
		BSRAM_CE_N	: out std_logic;
		BSRAM_OE_N	: out std_logic;
		BSRAM_WE_N	: out std_logic;

		MAP_ACTIVE  : out std_logic;
		MAP_CTRL		: in std_logic_vector(7 downto 0);
		ROM_MASK		: in std_logic_vector(23 downto 0);
		BSRAM_MASK	: in std_logic_vector(23 downto 0)
	);
end SDD1Map;

architecture rtl of SDD1Map is

	signal SDD1_ROM_A : std_logic_vector(23 downto 0);
	signal BSRAM_CS_N	: std_logic;
	signal SDD1_DO	: std_logic_vector(7 downto 0);
	signal MAP_SEL : std_logic;
    signal CORE_RESET_N, LOCAL_FLUSH, DATA_WAIT, DECOMP_READ : std_logic;
    signal DEC_NEED, DEC_RETIRE : std_logic;
    signal SNES_A, DEC_A : std_logic_vector(23 downto 0);
    signal SNES_DATA : std_logic_vector(7 downto 0);
    signal DEC_DATA : std_logic_vector(15 downto 0);
    signal MEM_NEED, MEM_RETIRE, MEM_READY, MEM_LANE : std_logic_vector(3 downto 0);
    signal MEM_ADDRS : std_logic_vector(91 downto 0);
    signal MEM_WORDS : std_logic_vector(63 downto 0);
begin
	
	MAP_SEL <= '1' when MAP_CTRL(7 downto 4) = X"5" else '0';
	MAP_ACTIVE <= MAP_SEL;

    CORE_RESET_N <= RST_N and MAP_SEL and ROM_HARD_RESET_N and not ROM_FLUSH
        when ROM_HANDSHAKE else RST_N and MAP_SEL;
	-- SDD1
	SDD1 : entity work.SDD1
    generic map (ROM_HANDSHAKE => ROM_HANDSHAKE)
	port map(
        SNES_READ_INTENT => ROM_SNES_READ_INTENT,
        SNES_RETIRE => ROM_SNES_RETIRE,
        SNES_ROM_DATA => SNES_DATA,
        SNES_ROM_ADDR => SNES_A, DEC_ROM_ADDR => DEC_A,
        DEC_ROM_NEED => DEC_NEED, DEC_ROM_RETIRE => DEC_RETIRE,
        DEC_ROM_READY => MEM_READY(1), DATA_WAIT => DATA_WAIT,
        DECOMP_READ => DECOMP_READ,
		RST_N			=> CORE_RESET_N,
		CLK			=> MCLK,
		ENABLE		=> ENABLE,

		CA				=> CA,
		CPURD_N		=> CPURD_N,
		CPUWR_N		=> CPUWR_N,
		DO				=> SDD1_DO,
		DI				=> DI,
		ROMSEL_N		=> ROMSEL_N,
		
		SYSCLKF_CE	=> SYSCLKF_CE,
		SYSCLKR_CE	=> SYSCLKR_CE,

		ROM_A			=> SDD1_ROM_A,
		ROM_DO		=> DEC_DATA,
		ROM_RD_N		=> ROM_OE_N
	);

    transactions: if ROM_HANDSHAKE generate
        LOCAL_FLUSH <= ROM_FLUSH or not RST_N or not MAP_SEL;
        MEM_NEED(0) <= ROM_SNES_READ_INTENT and MAP_SEL and not DECOMP_READ and
            not ROMSEL_N and BSRAM_CS_N;
        MEM_NEED(1) <= DEC_NEED and MAP_SEL;
        MEM_NEED(3 downto 2) <= "00";
        MEM_RETIRE <= "00" & DEC_RETIRE & (ROM_SNES_RETIRE and MEM_NEED(0) and MEM_READY(0));
        MEM_ADDRS <= (91 downto 46=>'0') &
            (DEC_A(22 downto 0) and ROM_MASK(22 downto 0)) &
            (SNES_A(22 downto 0) and ROM_MASK(22 downto 0));
        DEC_DATA <= MEM_WORDS(31 downto 16);
        SNES_DATA <= MEM_WORDS(7 downto 0) when MEM_LANE(0)='0' else MEM_WORDS(15 downto 8);
        ROM_SNES_WAIT <= DATA_WAIT or (MEM_NEED(0) and not MEM_READY(0));
        bridge: entity work.SA1RomBridge
        generic map(P1=>1, P2=>2, P3=>3)
        port map(CLK=>MCLK, ENABLE=>'1', FLUSH=>LOCAL_FLUSH,
            HARD_RESET_N=>ROM_HARD_RESET_N, EPOCH=>ROM_EPOCH,
            FLUSH_ACK=>ROM_FLUSH_ACK, NEED=>MEM_NEED, RETIRE=>MEM_RETIRE,
            ADDRS=>MEM_ADDRS, SNES_OWNER=>ROM_SNES_OWNER,
            READY=>MEM_READY, BYTES=>MEM_LANE, WORDS=>MEM_WORDS,
            REQ_VALID=>ROM_REQ_VALID, REQ_READY=>ROM_REQ_READY,
            REQ_ADDR=>ROM_REQ_ADDR, REQ_OWNER=>ROM_REQ_OWNER,
            REQ_SNES_OWNER=>ROM_REQ_SNES_OWNER, REQ_TAG=>ROM_REQ_TAG, REQ_EPOCH=>ROM_REQ_EPOCH,
            RSP_VALID=>ROM_RSP_VALID, RSP_READY=>ROM_RSP_READY,
            RSP_OWNER=>ROM_RSP_OWNER, RSP_TAG=>ROM_RSP_TAG, RSP_EPOCH=>ROM_RSP_EPOCH,
            RSP_DATA=>ROM_RSP_DATA, RSP_ERROR=>ROM_RSP_ERROR, FAULT=>ROM_FAULT);
    end generate;
    legacy: if not ROM_HANDSHAKE generate
        DEC_DATA<=ROM_Q; SNES_DATA<=(others=>'0'); MEM_READY<=(others=>'0');
        ROM_SNES_WAIT<='0'; ROM_REQ_VALID<='0'; ROM_REQ_ADDR<=(others=>'0');
        ROM_REQ_OWNER<="00"; ROM_REQ_SNES_OWNER<="00";
        ROM_REQ_TAG<=(others=>'0'); ROM_REQ_EPOCH<=(others=>'0');
        ROM_RSP_READY<='1'; ROM_FLUSH_ACK<='1'; ROM_FAULT<='0';
    end generate;

	ROM_ADDR <= SDD1_ROM_A(22 downto 0) and ROM_MASK(22 downto 0);
	ROM_CE_N <= '0';
	ROM_WORD <= '1';

	BSRAM_CS_N <= '0' when CA(23 downto 18) = x"7" & "00" or (CA(22) = '0' and CA(15 downto 13) = "011") else '1';
	BSRAM_ADDR <= ("0" & CA(19 downto 16) & CA(14 downto 0)) and BSRAM_MASK(19 downto 0);
	BSRAM_CE_N <= BSRAM_CS_N;
	BSRAM_OE_N <= CPURD_N;
	BSRAM_WE_N <= CPUWR_N;
	BSRAM_D    <= DI;

	DO <= BSRAM_Q when BSRAM_CS_N = '0' else SDD1_DO;

	IRQ_N <= '1';

end rtl;
