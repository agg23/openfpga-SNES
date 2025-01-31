library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;

package P65816_pkg is  

	type MicroInst_r is record
		stateCtrl    : std_logic_vector(2 downto 0);
		addrBus      : std_logic_vector(2 downto 0);
		addrInc      : std_logic_vector(1 downto 0);
		loadP			: std_logic_vector(2 downto 0); 
		loadT			: std_logic_vector(1 downto 0); 
		muxCtrl      : std_logic_vector(1 downto 0);
		addrCtrl     : std_logic_vector(7 downto 0);
		loadPC       : std_logic_vector(2 downto 0);
		loadSP       : std_logic_vector(2 downto 0);
		regAXY       : std_logic_vector(2 downto 0);
		loadDKB      : std_logic_vector(1 downto 0);
		busCtrl      : std_logic_vector(5 downto 0); 
		ALUCtrl      : std_logic_vector(4 downto 0); 
		byteSel      : std_logic_vector(1 downto 0);
		outBus       : std_logic_vector(2 downto 0);
		va      		 : std_logic_vector(1 downto 0);
	end record;
	
	type ALUCtrl_r is record
		fstOp        : std_logic_vector(2 downto 0);
		secOp        : std_logic_vector(2 downto 0);
		fc           : std_logic;
		w16          : std_logic;
	end record;
	
	type MCode_r is record
		ALU_CTRL 	: ALUCtrl_r;
		STATE_CTRL	: std_logic_vector(2 downto 0);
		ADDR_BUS      : std_logic_vector(2 downto 0);
		ADDR_INC      : std_logic_vector(1 downto 0);
		IND_CTRL      : std_logic_vector(1 downto 0);
		ADDR_CTRL     : std_logic_vector(7 downto 0);
		LOAD_PC       : std_logic_vector(2 downto 0);
		LOAD_SP       : std_logic_vector(2 downto 0);
		LOAD_AXY      : std_logic_vector(2 downto 0);
		LOAD_P         : std_logic_vector(2 downto 0);
		LOAD_T         : std_logic_vector(1 downto 0);
		LOAD_DKB      : std_logic_vector(1 downto 0);
		BUS_CTRL      : std_logic_vector(5 downto 0); 
		BYTE_SEL      : std_logic_vector(1 downto 0);
		OUT_BUS       : std_logic_vector(2 downto 0);
		VA      		 : std_logic_vector(1 downto 0);
	end record;
	
	type addrIncTab_t is array(0 to 3) of unsigned(15 downto 0);
	constant INC_TAB: addrIncTab_t := (x"0000", x"0001", x"0002", x"0003");
	
end P65816_pkg;

package body P65816_pkg is

	
end package body P65816_pkg;
