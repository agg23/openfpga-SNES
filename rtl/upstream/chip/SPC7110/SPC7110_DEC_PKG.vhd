library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;

package SPC7110_DEC_PKG is  
	
	type Evol_r is record
		PROB	: unsigned(7 downto 0);
		NEXT_MPS	: integer;
		NEXT_LPS	: integer;
	end record;
	
	type EvolTbl_t is array(0 to 52) of Evol_r;
	constant EVOL_TBL	: EvolTbl_t := (
	(x"5a",  1,  1), 
	(x"25",  2,  6), 
	(x"11",  3,  8),
	(x"08",  4, 10), 
	(x"03",  5, 12), 
	(x"01",  5, 15),
	(x"5a",  7,  7), 
	(x"3f",  8, 19), 
	(x"2c",  9, 21),
	(x"20", 10, 22), 
	(x"17", 11, 23), 
	(x"11", 12, 25),
	(x"0c", 13, 26), 
	(x"09", 14, 28), 
	(x"07", 15, 29),
	(x"05", 16, 31), 
	(x"04", 17, 32), 
	(x"03", 18, 34),
	(x"02",  5, 35),
	(x"5a", 20, 20), 
	(x"48", 21, 39), 
	(x"3a", 22, 40),
	(x"2e", 23, 42), 
	(x"26", 24, 44), 
	(x"1f", 25, 45),
	(x"19", 26, 46), 
	(x"15", 27, 25), 
	(x"11", 28, 26),
	(x"0e", 29, 26), 
	(x"0b", 30, 27), 
	(x"09", 31, 28),
	(x"08", 32, 29), 
	(x"07", 33, 30), 
	(x"05", 34, 31),
	(x"04", 35, 33), 
	(x"04", 36, 33), 
	(x"03", 37, 34),
	(x"02", 38, 35), 
	(x"02",  5, 36),
	(x"58", 40, 39), 
	(x"4d", 41, 47), 
	(x"43", 42, 48),
	(x"3b", 43, 49), 
	(x"34", 44, 50), 
	(x"2e", 45, 51),
	(x"29", 46, 44), 
	(x"25", 24, 45),
	(x"56", 48, 47), 
	(x"4f", 49, 47), 
	(x"47", 50, 48),
	(x"41", 51, 49), 
	(x"3c", 52, 50), 
	(x"37", 43, 51)
	);
	
	type Mode2Context_r is record
		NEXT0	: unsigned(4 downto 0);
		NEXT1	: unsigned(4 downto 0);
	end record;
	type Mode2ContextTbl_t is array(0 to 31) of Mode2Context_r;
	constant M2C_TBL	: Mode2ContextTbl_t := (
	("00001", "00010"), 
	("00011", "01000"), 
	("01101", "01110"),
	("01111", "10000"), 
	("10001", "10010"), 
	("10011", "10100"),
	("10101", "10110"), 
	("10111", "11000"), 
	("11001", "11010"),
	("11001", "11010"), 
	("11001", "11010"), 
	("11001", "11010"),
	("11001", "11010"), 
	("11011", "11100"), 
	("11101", "11110"),
	("11111", "11111"), 
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111"),
	("11111", "11111")
	);
	
	type Context_r is record
		INDEX	: integer;
		INV	: std_logic;
	end record;
	type ContextTbl_t is array(0 to 31) of Context_r;
	
	type PixelOrder_t is array(0 to 15) of unsigned(3 downto 0);

	function GetProb(con: unsigned(4 downto 0); conTbl: ContextTbl_t ) return unsigned;
	function GetNextLPS(con: unsigned(4 downto 0); conTbl: ContextTbl_t ) return integer;
	function GetNextMPS(con: unsigned(4 downto 0); conTbl: ContextTbl_t ) return integer;
	function GetBitMask(mode: std_logic_vector(1 downto 0) ) return unsigned;
	function GetZeroBitCnt(top: unsigned(7 downto 0) ) return unsigned;
	function GetDiff(a: unsigned(3 downto 0); b: unsigned(3 downto 0); c: unsigned(3 downto 0) ) return unsigned;
	function Reorder(o: PixelOrder_t; p: unsigned(3 downto 0) ) return PixelOrder_t;

	
end SPC7110_DEC_PKG;

package body SPC7110_DEC_PKG is

	function GetProb(con: unsigned(4 downto 0); conTbl: ContextTbl_t ) return unsigned is
		variable evol : integer;
		variable res: unsigned(7 downto 0); 
	begin
		evol := conTbl(to_integer(con)).INDEX;
		res := EVOL_TBL(EVOL).PROB;
		return res;
	end function;
	
	function GetNextLPS(con: unsigned(4 downto 0); conTbl: ContextTbl_t ) return integer is
		variable evol : integer;
		variable res: integer; 
	begin
		evol := conTbl(to_integer(con)).INDEX;
		res := EVOL_TBL(EVOL).NEXT_LPS;
		return res;
	end function;
	
	function GetNextMPS(con: unsigned(4 downto 0); conTbl: ContextTbl_t ) return integer is
		variable evol : integer;
		variable res: integer; 
	begin
		evol := conTbl(to_integer(con)).INDEX;
		res := EVOL_TBL(EVOL).NEXT_MPS;
		return res;
	end function;
	
	function GetBitMask(mode: std_logic_vector(1 downto 0) ) return unsigned is
		variable res: unsigned(1 downto 0); 
	begin
		if mode = "01" then
			res := "01";
		elsif mode = "10" then
			res := "11";
		else
			res := "00";
		end if;
		return res;
	end function;
	
	function GetZeroBitCnt(top: unsigned(7 downto 0) ) return unsigned is
		variable res: unsigned(2 downto 0); 
	begin
		if top(7) = '1' then
			res := "000";
		elsif top(6) = '1' then
			res := "001";
		elsif top(5) = '1' then
			res := "010";
		elsif top(4) = '1' then
			res := "011";
		elsif top(3) = '1' then
			res := "100";
		elsif top(2) = '1' then
			res := "101";
		elsif top(1) = '1' then
			res := "110";
		else
			res := "111";
		end if;
		return res;
	end function;
	
	function GetDiff(a: unsigned(3 downto 0); b: unsigned(3 downto 0); c: unsigned(3 downto 0) ) return unsigned is
		variable res: unsigned(2 downto 0); 
	begin
		if a = b and b = c then
			res := "000";
		elsif a = b and b /= c then
			res := "001";
		elsif a /= b and b = c then
			res := "010";
		elsif a = c and b /= c then
			res := "011";
		else
			res := "100";
		end if;
		return res;
	end function;
	
	function Reorder(o: PixelOrder_t; p: unsigned(3 downto 0) ) return PixelOrder_t is
		variable res: PixelOrder_t; 
		variable n: integer; 
	begin
		n := 0;
		for i in 1 to 15 loop
			if o(i) = p then
				n := i;
			end if;
		end loop;
		
		for i in 1 to 15 loop
			if n >= i then
				res(i) := o(i-1);
			else
				res(i) := o(i);
			end if;
		end loop;
		res(0) := o(n);
		
		return res;
	end function;

	
end package body SPC7110_DEC_PKG;
