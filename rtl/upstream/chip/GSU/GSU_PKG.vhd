library IEEE;
use IEEE.Std_Logic_1164.all;
library STD;
use ieee.numeric_std.all;

package GSU_PKG is  

	constant FLAG_GO : integer range 0 to 15 := 5;
	constant FLAG_R : integer range 0 to 15 := 6;
	constant FLAG_IL : integer range 0 to 15 := 10;
	constant FLAG_IH : integer range 0 to 15 := 11;
	constant FLAG_IRQ : integer range 0 to 15 := 15;
	
	constant NUM_MCODES : integer := 25;
	
	type Opcode_t is (
		OP_NOP, OP_STOP, OP_CACHE,
		OP_MOVE,	OP_MOVES,
		OP_IBT, OP_IWT,
		OP_GETB,	OP_GETBH, OP_GETBL, OP_GETBS, OP_LDB, OP_LDW, OP_LM, OP_LMS, 
		OP_STB, OP_STW, OP_SM, OP_SMS, OP_SBK, OP_RAMB, OP_ROMB,
		OP_CMODE, OP_COLOR, OP_GETC, OP_PLOT, OP_RPIX,
		OP_ADD, OP_SUB, OP_CMP, OP_AND, OP_OR, OP_XOR, OP_NOT,
		OP_LSR, OP_ASR, OP_ROL, OP_ROR, OP_DIV2,
		OP_INC, OP_DEC,
		OP_SWAP, OP_SEX, OP_LOB, OP_HIB, OP_MERGE,
		OP_MULT, OP_UMULT, OP_FMULT, OP_LMULT,
		OP_BRA, OP_JMP, OP_LJMP, OP_LOOP, OP_LINK,
		OP_ALT1, OP_ALT2, OP_ALT3,
		OP_TO, OP_WITH, OP_FROM
	);
	
	type Opcode_r is record
		OP				: Opcode_t;
		MC				: integer range 0 to NUM_MCODES-1;
	end record;
	
	type OpcodeAlt_r is record
		OP				: Opcode_r;
		OP_ALT1		: Opcode_r;
		OP_ALT2		: Opcode_r;
		OP_ALT3		: Opcode_r;
	end record;
	
	type Microcode_r is record
		LAST_CYCLE	: std_logic; 
		INCPC			: std_logic;
		FSET			: std_logic; 						  --1: update ALU flags
		DREG			: std_logic_vector(2 downto 0); --[2] - dest reg 0 = Rd, 1 = Rn; [1] - MSB; [0] - LSB;
		ROMWAIT		: std_logic;
		RAMWAIT		: std_logic;
		RAMLD			: std_logic_vector(1 downto 0);
		RAMST			: std_logic_vector(2 downto 0); --[2] - source reg 0 = Rs, 1 = Rn; [1] - MSB; [0] - LSB;
		RAMADDR		: std_logic_vector(2 downto 0); --[2:0] 0 = none, 1 = RAMADDR.LSB = DATA, 2 = RAMADDR.MSB = DATA, 3 = RAMADDR = Rn, 4 = RAMADDR = DATA*2, 5 = RAMADDR no change 
	end record;
	
	type MicrocodeTbl_t is array(0 to NUM_MCODES-1, 0 to 3) of Microcode_r;
	constant MC_TBL: MicrocodeTbl_t := (
	-- 0 STOP
	(('1','1','0',"000",'1','1',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 1 NOP
	(('1','1','0',"000",'0','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 2 CACHE
	(('1','1','0',"000",'0','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 3 BRA
	(('0','1','0',"000",'0','0',"00","000","000"),
	 ('1','1','0',"000",'0','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 4 MOVE
	(('1','1','0',"111",'0','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 5 ALU
	(('1','1','1',"011",'0','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 6 CMP
	(('1','1','1',"000",'0','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 7 IBT
	(('0','1','0',"000",'0','0',"00","000","000"),
	 ('1','1','0',"111",'0','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 8 IWT
	(('0','1','0',"000",'0','0',"00","000","000"),
	 ('0','1','0',"101",'0','0',"00","000","000"),
	 ('1','1','0',"110",'0','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 9 LDB
	(('0','0','0',"000",'0','1',"01","000","011"),
	 ('1','1','0',"001",'0','1',"01","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 10 LDW
	(('0','0','0',"000",'0','1',"10","000","011"),
	 ('1','1','0',"011",'0','1',"10","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 11 GETB/GETC
	(('1','1','0',"011",'1','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 12 STB
	(('0','0','0',"000",'0','1',"00","001","011"),
	 ('1','1','0',"000",'0','1',"00","001","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 13 STW
	(('0','0','0',"000",'0','1',"00","010","011"),
	 ('1','1','0',"000",'0','1',"00","010","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 14 INC/DEC
	(('1','1','1',"111",'0','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 15 SM
	(('0','1','0',"000",'0','1',"00","000","000"),
	 ('0','1','0',"000",'0','1',"00","000","001"),
	 ('0','0','0',"000",'0','1',"00","110","010"),
	 ('1','1','0',"000",'0','1',"00","110","000")),
	-- 16 ROMB
	(('1','1','0',"000",'1','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 17 RAMB
	(('1','1','0',"000",'0','1',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 18 LM
	(('0','1','0',"000",'0','1',"00","000","000"),
	 ('0','1','0',"000",'0','1',"00","000","001"),
	 ('0','0','0',"000",'0','1',"10","000","010"),
	 ('1','1','0',"111",'0','1',"10","000","000")),
	-- 19 LMS
	(('0','1','0',"000",'0','1',"00","000","000"),
	 ('0','0','0',"000",'0','1',"10","000","100"),
	 ('1','1','0',"111",'0','1',"10","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 20 SMS
	(('0','1','0',"000",'0','1',"00","000","000"),
	 ('0','0','0',"000",'0','1',"00","110","100"),
	 ('1','1','0',"000",'0','1',"00","110","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 21 SBK
	(('0','0','0',"000",'0','1',"00","010","101"),
	 ('1','1','0',"000",'0','1',"00","010","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 22 RPIX
	(('0','0','0',"000",'0','1',"00","000","000"),
	 ('1','1','1',"001",'0','1',"01","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 23 PLOT
	(('1','1','0',"000",'0','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX")),
	-- 24 LMULT
	(('0','0','0',"000",'0','0',"00","000","000"),
	 ('0','0','0',"000",'0','0',"00","000","000"),
	 ('1','1','1',"011",'0','0',"00","000","000"),
	 ('X','X','X',"XXX",'X','X',"XX","XXX","XXX"))
	);
	
	type OpcodeTbl_t is array(0 to 255) of OpcodeAlt_r;
	constant OP_TBL: OpcodeTbl_t := (
	((OP_STOP,   0), (OP_STOP,    0), (OP_STOP,    0), (OP_STOP,    0)), --STOP
	((OP_NOP,    1), (OP_NOP,     1), (OP_NOP,     1), (OP_NOP,     1)), --NOP
	((OP_CACHE,  2), (OP_CACHE,   2), (OP_CACHE,   2), (OP_CACHE,   2)), --CACHE
	((OP_LSR,    5), (OP_LSR,     5), (OP_LSR,     5), (OP_LSR,     5)), --LSR
	((OP_ROL,    5), (OP_ROL,     5), (OP_ROL,     5), (OP_ROL,     5)), --ROL
	((OP_BRA,    3), (OP_BRA,     3), (OP_BRA,     3), (OP_BRA,     3)), --BRA
	((OP_BRA,    3), (OP_BRA,     3), (OP_BRA,     3), (OP_BRA,     3)), --BGE
	((OP_BRA,    3), (OP_BRA,     3), (OP_BRA,     3), (OP_BRA,     3)), --BLT
	((OP_BRA,    3), (OP_BRA,     3), (OP_BRA,     3), (OP_BRA,     3)), --BNE
	((OP_BRA,    3), (OP_BRA,     3), (OP_BRA,     3), (OP_BRA,     3)), --BEQ
	((OP_BRA,    3), (OP_BRA,     3), (OP_BRA,     3), (OP_BRA,     3)), --BPL
	((OP_BRA,    3), (OP_BRA,     3), (OP_BRA,     3), (OP_BRA,     3)), --BMI
	((OP_BRA,    3), (OP_BRA,     3), (OP_BRA,     3), (OP_BRA,     3)), --BCC
	((OP_BRA,    3), (OP_BRA,     3), (OP_BRA,     3), (OP_BRA,     3)), --BCS
	((OP_BRA,    3), (OP_BRA,     3), (OP_BRA,     3), (OP_BRA,     3)), --BVC
	((OP_BRA,    3), (OP_BRA,     3), (OP_BRA,     3), (OP_BRA,     3)), --BVS
	--10
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R0 / MOVE R0,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R1 / MOVE R1,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R2 / MOVE R2,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R3 / MOVE R3,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R4 / MOVE R4,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R5 / MOVE R5,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R6 / MOVE R6,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R7 / MOVE R7,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R8 / MOVE R8,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R9 / MOVE R9,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R10 / MOVE R10,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R11 / MOVE R11,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R12 / MOVE R12,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R13 / MOVE R13,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R14 / MOVE R14,Rs
	((OP_TO,     1), (OP_TO,      1), (OP_TO,      1), (OP_TO,      1)), --TO R15 / MOVE R15,Rs
	--20
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R0
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R1
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R2
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R3
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R4
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R5
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R6
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R7
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R8
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R9
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R10
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R11
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R12
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R13
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R14
	((OP_WITH,   1), (OP_WITH,    1), (OP_WITH,    1), (OP_WITH,    1)), --WITH R15
	 --30
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R0)
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R1)
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R2)
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R3)
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R4)
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R5)
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R6)
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R7)
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R8)
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R9)
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R10)
	((OP_STW,   13), (OP_STB,    12), (OP_STW,    13), (OP_STW,    13)), --STB/STW (R11)
	((OP_LOOP,   5), (OP_LOOP,    5), (OP_LOOP,    5), (OP_LOOP,    5)), --LOOP
	((OP_ALT1,   1), (OP_ALT1,    1), (OP_ALT1,    1), (OP_ALT1,    1)), --ALT1
	((OP_ALT2,   1), (OP_ALT2,    1), (OP_ALT2,    1), (OP_ALT2,    1)), --ALT2
	((OP_ALT3,   1), (OP_ALT3,    1), (OP_ALT3,    1), (OP_ALT3,    1)), --ALT3
	--40
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R0)
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R1)
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R2)
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R3)
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R4)
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R5)
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R6)
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R7)
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R8)
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R9)
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R10)
	((OP_LDW,   10), (OP_LDB,     9), (OP_LDW,    10), (OP_LDW,    10)), --LDB/LDW (R11)
	((OP_PLOT,  23), (OP_RPIX,   22), (OP_PLOT,   23), (OP_PLOT,   23)), --PLOT / RPIX
	((OP_SWAP,   5), (OP_SWAP,    5), (OP_SWAP,    5), (OP_SWAP,    5)), --SWAP
	((OP_COLOR,  1), (OP_CMODE,   1), (OP_COLOR,   1), (OP_COLOR,   1)), --COLOR / CMODE
	((OP_NOT,    5), (OP_NOT,     5), (OP_NOT,     5), (OP_NOT,     5)), --NOT
	--50
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R0 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R1 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R2 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R3 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R4 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R5 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R6 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R7 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R8 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R6 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R10 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R11 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R12 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R13 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R14 
	((OP_ADD,    5), (OP_ADD,     5), (OP_ADD,     5), (OP_ADD,     5)), --ADD R15 
	--60
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R0 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R1 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R2 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R3 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R4 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R5 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R6 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R7 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R8 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R9 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R10 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R11 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R12 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R13 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R14 
	((OP_SUB,    5), (OP_SUB,     5), (OP_SUB,     5), (OP_CMP,     6)), --SUB/CMP R15 
	--70
	((OP_MERGE,  5), (OP_MERGE,   5), (OP_MERGE,   5), (OP_MERGE,   5)), --MERGE
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R1 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R2 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R3 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R4 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R5 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R6 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R7 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R8 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R9 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R10 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R11 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R12 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R13 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R14 
	((OP_AND,    5), (OP_AND,     5), (OP_AND,     5), (OP_AND,     5)), --AND R15 
	--80
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R0
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R1 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R2 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R3 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R4 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R5 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R6 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R7 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R8 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R9 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R10 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R11 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R12 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R13 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R14 
	((OP_MULT,   5), (OP_UMULT,   5), (OP_MULT,    5), (OP_UMULT,   5)), --MULT/UMULT R15 
	--90
	((OP_SBK,   21), (OP_SBK,    21), (OP_SBK,    21), (OP_SBK,    21)), --SBK
	((OP_LINK,   1), (OP_LINK,    1), (OP_LINK,    1), (OP_LINK,    1)), --LINK #1
	((OP_LINK,   1), (OP_LINK,    1), (OP_LINK,    1), (OP_LINK,    1)), --LINK #2 
	((OP_LINK,   1), (OP_LINK,    1), (OP_LINK,    1), (OP_LINK,    1)), --LINK #3 
	((OP_LINK,   1), (OP_LINK,    1), (OP_LINK,    1), (OP_LINK,    1)), --LINK #4 
	((OP_SEX,    5), (OP_SEX,     5), (OP_SEX,     5), (OP_SEX,     5)), --SEX
	((OP_ASR,    5), (OP_DIV2,    5), (OP_ASR,     5), (OP_ASR,     5)), --ASR / DIV2
	((OP_ROR,    5), (OP_ROR,     5), (OP_ROR,     5), (OP_ROR,     5)), --ROR
	((OP_JMP,    1), (OP_LJMP,    1), (OP_JMP,     1), (OP_JMP,     1)), --JMP R8 / LJMP R8 
	((OP_JMP,    1), (OP_LJMP,    1), (OP_JMP,     1), (OP_JMP,     1)), --JMP R9 / LJMP R9 
	((OP_JMP,    1), (OP_LJMP,    1), (OP_JMP,     1), (OP_JMP,     1)), --JMP R10 / LJMP R10 
	((OP_JMP,    1), (OP_LJMP,    1), (OP_JMP,     1), (OP_JMP,     1)), --JMP R11 / LJMP R11 
	((OP_JMP,    1), (OP_LJMP,    1), (OP_JMP,     1), (OP_JMP,     1)), --JMP R12 / LJMP R12 
	((OP_JMP,    1), (OP_LJMP,    1), (OP_JMP,     1), (OP_JMP,     1)), --JMP R13 / LJMP R13 
	((OP_LOB,    5), (OP_LOB,     5), (OP_LOB,     5), (OP_LOB,     5)), --LOB
	((OP_FMULT, 24), (OP_LMULT,  24), (OP_FMULT,  24), (OP_FMULT,  24)), --FMULT / LMULT
	--A0
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R0,#pp / LMS R0,(yy) / SMS (yy),R0
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R1,#pp / LMS R1,(yy) / SMS (yy),R1
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R2,#pp / LMS R2,(yy) / SMS (yy),R2
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R3,#pp / LMS R3,(yy) / SMS (yy),R3
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R4,#pp / LMS R4,(yy) / SMS (yy),R4
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R5,#pp / LMS R5,(yy) / SMS (yy),R5 
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R6,#pp / LMS R6,(yy) / SMS (yy),R6
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R7,#pp / LMS R7,(yy) / SMS (yy),R7
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R8,#pp / LMS R8,(yy) / SMS (yy),R8
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R9,#pp / LMS R9,(yy) / SMS (yy),R9
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R10,#pp / LMS R10,(yy) / SMS (yy),R10
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R11,#pp / LMS R11,(yy) / SMS (yy),R11
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R12,#pp / LMS R12,(yy) / SMS (yy),R12
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R13,#pp / LMS R13,(yy) / SMS (yy),R13
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R14,#pp / LMS R14,(yy) / SMS (yy),R14
	((OP_IBT,    7), (OP_LMS,    19), (OP_SMS,    20), (OP_IBT,     7)), --IBT R15,#pp / LMS R15,(yy) / SMS (yy),R15
	--B0
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R0 / MOVES Rd,R0
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R1 / MOVES Rd,R1
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R2 / MOVES Rd,R2
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R3 / MOVES Rd,R3
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R4 / MOVES Rd,R4
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R5 / MOVES Rd,R5
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R6 / MOVES Rd,R6
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R7 / MOVES Rd,R7
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R8 / MOVES Rd,R8
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R9 / MOVES Rd,R9
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R10 / MOVES Rd,R10
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R11 / MOVES Rd,R11
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R12 / MOVES Rd,R12
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R13 / MOVES Rd,R13
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R14 / MOVES Rd,R14
	((OP_FROM,   1), (OP_FROM,    1), (OP_FROM,    1), (OP_FROM,    1)), --FROM R15 / MOVES Rd,R15
	--C0
	((OP_HIB,    5), (OP_HIB,     5), (OP_HIB,     5), (OP_HIB,     5)), --HIB
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R1 / XOR R1
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R2 / XOR R2
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R3 / XOR R3
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R4 / XOR R4
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R5 / XOR R5
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R6 / XOR R6
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R7 / XOR R7
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R8 / XOR R8
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R9 / XOR R9
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R10 / XOR R10
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R11 / XOR R11
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R12 / XOR R12
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R13 / XOR R13
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R14 / XOR R14
	((OP_OR,     5), (OP_XOR,     5), (OP_OR,      5), (OP_XOR,     5)), --OR R15 / XOR R15
	--D0
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R0
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R1 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R2 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R3 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R4 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R5 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R6 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R7 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R8 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R9 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R10 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R11 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R12 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R13 
	((OP_INC,   14), (OP_INC,    14), (OP_INC,    14), (OP_INC,    14)), --INC R14 
	((OP_GETC,  11), (OP_GETC,   11), (OP_RAMB,   17), (OP_ROMB,   16)), --GETC / RAMB / ROMB
	--E 0
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R0
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R1 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R2 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R3 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R4 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R5 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R6 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R7 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R8 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R9 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R10 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R11 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R12 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R13 
	((OP_DEC,   14), (OP_DEC,    14), (OP_DEC,    14), (OP_DEC,    14)), --DEC R14 
	((OP_GETB,  11), (OP_GETBH,  11), (OP_GETBL,  11), (OP_GETBS,  11)), --GETB / GETBH / GETBL / GETBS
	--F0
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R0,#yyxx / LM R0,(hilo) / SM (hilo),R0
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R1,#yyxx / LM R1,(hilo) / SM (hilo),R1
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R2,#yyxx / LM R2,(hilo) / SM (hilo),R2
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R3,#yyxx / LM R3,(hilo) / SM (hilo),R3
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R4,#yyxx / LM R4,(hilo) / SM (hilo),R4
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R5,#yyxx / LM R5,(hilo) / SM (hilo),R5
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R6,#yyxx / LM R6,(hilo) / SM (hilo),R6
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R7,#yyxx / LM R7,(hilo) / SM (hilo),R7
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R8,#yyxx / LM R8,(hilo) / SM (hilo),R8
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R9,#yyxx / LM R9,(hilo) / SM (hilo),R9
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R10,#yyxx / LM R10,(hilo) / SM (hilo),R10
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R11,#yyxx / LM R11,(hilo) / SM (hilo),R11
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R12,#yyxx / LM R12,(hilo) / SM (hilo),R12
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R13,#yyxx / LM R13,(hilo) / SM (hilo),R13
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8)), --IWT R14,#yyxx / LM R14,(hilo) / SM (hilo),R14
	((OP_IWT,    8), (OP_LM,     18), (OP_SM,     15), (OP_IWT,     8))  --IWT R15,#yyxx / LM R15,(hilo) / SM (hilo),R15
	);
	
	type Reg_t is array (0 to 15) of std_logic_vector(15 downto 0);
	
	type PixCacheData_t is array (0 to 7) of std_logic_vector(7 downto 0);
	type PixCache_r is record
		DATA		: PixCacheData_t;
		OFFSET	: unsigned(12 downto 0);
		VALID		: std_logic_vector(7 downto 0);
	end record;
	type PixCaches_t is array (0 to 1) of PixCache_r;
	
	--type ROMState_t is (
	--	ROMST_IDLE, 
	--	ROMST_FETCH, 
	--	ROMST_FETCH_DONE,
	--	ROMST_CACHE, 
	--	ROMST_CACHE_DONE,
	--	ROMST_CACHE_END,
	--	ROMST_LOAD
	--);
	
	constant ROMST_IDLE:		std_logic_vector(2 downto 0) := "000";
	constant ROMST_FETCH:		std_logic_vector(2 downto 0) := "001";
	constant ROMST_FETCH_DONE:	std_logic_vector(2 downto 0) := "010";
	constant ROMST_CACHE:		std_logic_vector(2 downto 0) := "011";
	constant ROMST_CACHE_DONE:	std_logic_vector(2 downto 0) := "100";
	constant ROMST_CACHE_END:	std_logic_vector(2 downto 0) := "101";
	constant ROMST_LOAD:		std_logic_vector(2 downto 0) := "110";

	--type RAMState_t is (
	--	RAMST_IDLE, 
	--	RAMST_FETCH, 
	--	RAMST_FETCH_DONE,
	--	RAMST_CACHE, 
	--	RAMST_CACHE_DONE,
	--	RAMST_CACHE_END,
	--	RAMST_LOAD, 
	--	RAMST_SAVE, 
	--	RAMST_PCF, 
	--	RAMST_PCF_END,
	--	RAMST_RPIX
	--);

	constant RAMST_IDLE:		std_logic_vector(3 downto 0) := "0000";
	constant RAMST_FETCH:		std_logic_vector(3 downto 0) := "0001";
	constant RAMST_FETCH_DONE:	std_logic_vector(3 downto 0) := "0010";
	constant RAMST_CACHE:		std_logic_vector(3 downto 0) := "0011";
	constant RAMST_CACHE_DONE:	std_logic_vector(3 downto 0) := "0100";
	constant RAMST_CACHE_END:	std_logic_vector(3 downto 0) := "0101";
	constant RAMST_LOAD:		std_logic_vector(3 downto 0) := "0110";
	constant RAMST_SAVE:		std_logic_vector(3 downto 0) := "0111";
	constant RAMST_PCF:			std_logic_vector(3 downto 0) := "1000";
	constant RAMST_PCF_END:		std_logic_vector(3 downto 0) := "1001";
	constant RAMST_RPIX:		std_logic_vector(3 downto 0) := "1010";

	--type MULTState_t is (
	--	MULTST_IDLE, 
	--	MULTST_EXEC
	--);

	constant MULTST_IDLE: std_logic := '0';
	constant MULTST_EXEC: std_logic := '1';
	
	function GetLastBPP(md: std_logic_vector(1 downto 0)) return unsigned;
	function GetCharOffset(offs: unsigned(12 downto 0); ht: std_logic_vector(1 downto 0); md: std_logic_vector(1 downto 0); 
								  bpp: unsigned(2 downto 0); scbr: std_logic_vector(7 downto 0)) return std_logic_vector;
	function GetPCData(pc: PixCache_r; p: unsigned(2 downto 0)) return std_logic_vector;

end GSU_PKG;

package body GSU_PKG is

	function GetLastBPP(md: std_logic_vector(1 downto 0)) return unsigned is
		variable res: unsigned(2 downto 0); 
	begin
		case md is
			when "00" =>   res := "001";
			when "01" =>   res := "011";
			when "11" =>   res := "111";
			when others => res := "011";
		end case; 

		return res;
	end function;
	
	function GetCharOffset(offs: unsigned(12 downto 0); 
								  ht: std_logic_vector(1 downto 0); 
								  md: std_logic_vector(1 downto 0); 
								  bpp: unsigned(2 downto 0);
								  scbr: std_logic_vector(7 downto 0)) return std_logic_vector is
		variable temp: unsigned(9 downto 0); 
		variable temp2: unsigned(16 downto 0);
		variable res: std_logic_vector(16 downto 0); 
	begin
		case ht is
			when "00" =>   temp := ("0" & offs(4 downto 0) & "0000") + ("00000" & offs(12 downto 8));
			when "01" =>   temp := ("0" & offs(4 downto 0) & "0000") + ("000" & offs(4 downto 0) & "00") + ("00000" & offs(12 downto 8));
			when "10" =>   temp := ("0" & offs(4 downto 0) & "0000") + ("00" & offs(4 downto 0) & "000") + ("00000" & offs(12 downto 8));
			when others => temp := offs(12) & offs(4) & offs(11 downto 8) & offs(3 downto 0);
		end case; 

		case md is
			when "00" =>   temp2 := "000" & temp & "0000";
			when "01" =>   temp2 := "00" & temp & "00000";
			when "11" =>   temp2 := "0" & temp & "000000";
			when others => temp2 := "00" & temp & "00000";
		end case; 
		
		res := std_logic_vector( temp2 + (unsigned(scbr(6 downto 0)) & "0000" & bpp(2 downto 1) & offs(7 downto 5) & bpp(0)) );
		
		return res;
	end function;
	
	function GetPCData(pc: PixCache_r; p: unsigned(2 downto 0)) return std_logic_vector is
		variable res: std_logic_vector(7 downto 0); 
	begin
		res := pc.DATA(7)(to_integer(p)) &
				 pc.DATA(6)(to_integer(p)) &
				 pc.DATA(5)(to_integer(p)) &
				 pc.DATA(4)(to_integer(p)) &
				 pc.DATA(3)(to_integer(p)) &
				 pc.DATA(2)(to_integer(p)) &
				 pc.DATA(1)(to_integer(p)) &
				 pc.DATA(0)(to_integer(p));

		return res;
	end function;

end package body GSU_PKG;
