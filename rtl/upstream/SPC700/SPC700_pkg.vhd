library IEEE;
use IEEE.Std_Logic_1164.all;

package SPC700_pkg is  

	type MicroInst_r is record
		stateCtrl	: std_logic_vector(1 downto 0);
		addrBus		: std_logic_vector(1 downto 0);
		addrCtrl		: std_logic_vector(5 downto 0);
		regMode		: std_logic_vector(4 downto 0);
		regAXY		: std_logic_vector(1 downto 0);
		busCtrl		: std_logic_vector(5 downto 0); 
		ALUCtrl		: std_logic_vector(5 downto 0);
		outBus		: std_logic_vector(2 downto 0);
	end record;
	
	type ALUCtrl_r is record
		fstOp			: std_logic_vector(2 downto 0);
		secOp			: std_logic_vector(3 downto 0);
		chgVO			: std_logic;
		chgHO			: std_logic;
		intC			: std_logic;
		chgCO			: std_logic;
		w        	: std_logic;
	end record;
	
	type RegCtrl_r is record
		loadPC		: std_logic_vector(2 downto 0);
		loadSP		: std_logic_vector(1 downto 0);
		loadP			: std_logic_vector(2 downto 0);
		loadT			: std_logic_vector(1 downto 0);
	end record;
	
	type MCode_r is record
		ALU_CTRL		: ALUCtrl_r;
		STATE_CTRL	: std_logic_vector(1 downto 0);
		ADDR_BUS		: std_logic_vector(1 downto 0);
		ADDR_CTRL	: std_logic_vector(5 downto 0);
		LOAD_PC		: std_logic_vector(2 downto 0);
		LOAD_SP		: std_logic_vector(1 downto 0);
		LOAD_AXY		: std_logic_vector(1 downto 0);
		LOAD_P		: std_logic_vector(2 downto 0);
		LOAD_T		: std_logic_vector(1 downto 0);
		BUS_CTRL		: std_logic_vector(5 downto 0); 
		OUT_BUS		: std_logic_vector(2 downto 0);
	end record;
	
end SPC700_pkg;

package body SPC700_pkg is

	
end package body SPC700_pkg;
