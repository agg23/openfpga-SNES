library STD;
use STD.TEXTIO.ALL;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;

entity GSUMap is
    generic (ROM_HANDSHAKE : boolean := false);
	port(
        -- Standard-refresh transaction transport. Soft reset cancels, hard reset
        -- alone discards accepted tokens when the physical engine also resets.
        ROM_HARD_RESET_N : in std_logic := '1';
        ROM_EPOCH : in std_logic_vector(7 downto 0) := (others => '0');
        ROM_FLUSH : in std_logic := '0';
        ROM_FLUSH_ACK : out std_logic;
        ROM_FAULT : out std_logic;
        ROM_SNES_READ_INTENT : in std_logic := '0';
        ROM_SNES_OWNER : in std_logic_vector(1 downto 0) := "00";
        ROM_SNES_RETIRE : in std_logic := '0';
        ROM_SNES_WAIT : out std_logic;
        ROM_REQ_VALID : out std_logic;
        ROM_REQ_READY : in std_logic := '0';
        ROM_REQ_ADDR : out std_logic_vector(22 downto 0);
        ROM_REQ_OWNER : out std_logic_vector(1 downto 0);
        ROM_REQ_SNES_OWNER : out std_logic_vector(1 downto 0);
        ROM_REQ_TAG, ROM_REQ_EPOCH : out std_logic_vector(7 downto 0);
        ROM_RSP_VALID : in std_logic := '0';
        ROM_RSP_READY : out std_logic;
        ROM_RSP_DATA : in std_logic_vector(15 downto 0) := (others => '0');
        ROM_RSP_OWNER : in std_logic_vector(1 downto 0) := "00";
        ROM_RSP_TAG, ROM_RSP_EPOCH : in std_logic_vector(7 downto 0) := (others => '0');
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
		BSRAM_MASK	: in std_logic_vector(23 downto 0);

		TURBO		   : in std_logic;
		FASTROM   	: in std_logic;

		SS_BUSY			: in std_logic;
		SS_WR			: in std_logic;
		SS_DO			: out std_logic_vector(7 downto 0)
	);
end GSUMap;

architecture rtl of GSUMap is

	signal ROM_A 		: std_logic_vector(20 downto 0);
	signal RAM_A 		: std_logic_vector(16 downto 0);
	signal RAM_WE_N 	: std_logic;
	signal MAP_SEL	  	: std_logic;
	
begin

	MAP_SEL <= '1' when MAP_CTRL(7 downto 4) = X"7" else '0';
	MAP_ACTIVE <= MAP_SEL;
	
	GSU : entity work.GSU
    generic map (ROM_HANDSHAKE => ROM_HANDSHAKE)
	port map(
        ROM_MASK => ROM_MASK(22 downto 0),
        ROM_HARD_RESET_N => ROM_HARD_RESET_N,
        ROM_EPOCH => ROM_EPOCH,
        ROM_FLUSH => ROM_FLUSH,
        ROM_FLUSH_ACK => ROM_FLUSH_ACK,
        ROM_FAULT => ROM_FAULT,
        ROM_SNES_READ_INTENT => ROM_SNES_READ_INTENT,
        ROM_SNES_OWNER => ROM_SNES_OWNER,
        ROM_SNES_RETIRE => ROM_SNES_RETIRE,
        ROM_SNES_WAIT => ROM_SNES_WAIT,
        ROM_REQ_VALID => ROM_REQ_VALID,
        ROM_REQ_READY => ROM_REQ_READY,
        ROM_REQ_ADDR => ROM_REQ_ADDR,
        ROM_REQ_OWNER => ROM_REQ_OWNER,
        ROM_REQ_SNES_OWNER => ROM_REQ_SNES_OWNER,
        ROM_REQ_TAG => ROM_REQ_TAG,
        ROM_REQ_EPOCH => ROM_REQ_EPOCH,
        ROM_RSP_VALID => ROM_RSP_VALID,
        ROM_RSP_READY => ROM_RSP_READY,
        ROM_RSP_DATA => ROM_RSP_DATA,
        ROM_RSP_OWNER => ROM_RSP_OWNER,
        ROM_RSP_TAG => ROM_RSP_TAG,
        ROM_RSP_EPOCH => ROM_RSP_EPOCH,
        ROM_RSP_ERROR => ROM_RSP_ERROR,

		CLK			=> MCLK,
		RST_N			=> RST_N and MAP_SEL,
		ENABLE		=> ENABLE,

		ADDR			=> CA,
		DO				=> DO,
		DI				=> DI,
		RD_N			=> CPURD_N,
		WR_N			=> CPUWR_N,
		
		SYSCLKF_CE	=> SYSCLKF_CE,
		SYSCLKR_CE	=> SYSCLKR_CE,
		
		IRQ_N			=> IRQ_N,
		
		ROM_A			=> ROM_A,
		ROM_DI		=> ROM_Q(7 downto 0),
		ROM_RD_N		=> ROM_OE_N,
		
		RAM_A			=> RAM_A,
		RAM_DI		=> BSRAM_Q,
		RAM_DO		=> BSRAM_D,
		RAM_WE_N		=> RAM_WE_N,
		RAM_CE_N		=> BSRAM_CE_N,
				
		TURBO			=> TURBO,
		FASTROM		=> FASTROM,

		SS_BUSY			=> SS_BUSY,
		SS_WR			=> SS_WR,
		SS_DO			=> SS_DO
	);
	
	ROM_ADDR 	<= ("00" & ROM_A) and ROM_MASK(22 downto 0);
	ROM_CE_N 	<= '0';
	ROM_WORD		<= '0';
	
	BSRAM_ADDR 	<= "0000" & RAM_A(15 downto 0);
	BSRAM_OE_N 	<= not RAM_WE_N;
	BSRAM_WE_N 	<= RAM_WE_N;
	
end rtl;