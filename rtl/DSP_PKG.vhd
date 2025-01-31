library IEEE;
use IEEE.Std_Logic_1164.all;
library STD;
use ieee.numeric_std.all;

package DSP_PKG is  

	constant MCLK_NTSC_FREQ : integer := 2147727;
	constant MCLK_PAL_FREQ  : integer := 2128137;
	constant ACLK_FREQ      : integer :=  409600;
	
	constant V0VOLL: std_logic_vector(7 downto 0) := x"00"; 
	constant V1VOLL: std_logic_vector(7 downto 0) := x"10"; 
	constant V2VOLL: std_logic_vector(7 downto 0) := x"20"; 
	constant V3VOLL: std_logic_vector(7 downto 0) := x"30"; 
	constant V4VOLL: std_logic_vector(7 downto 0) := x"40"; 
	constant V5VOLL: std_logic_vector(7 downto 0) := x"50"; 
	constant V6VOLL: std_logic_vector(7 downto 0) := x"60"; 
	constant V7VOLL: std_logic_vector(7 downto 0) := x"70"; 
	
	constant V0VOLR: std_logic_vector(7 downto 0) := x"01"; 
	constant V1VOLR: std_logic_vector(7 downto 0) := x"11"; 
	constant V2VOLR: std_logic_vector(7 downto 0) := x"21"; 
	constant V3VOLR: std_logic_vector(7 downto 0) := x"31"; 
	constant V4VOLR: std_logic_vector(7 downto 0) := x"41"; 
	constant V5VOLR: std_logic_vector(7 downto 0) := x"51"; 
	constant V6VOLR: std_logic_vector(7 downto 0) := x"61"; 
	constant V7VOLR: std_logic_vector(7 downto 0) := x"71"; 
	
	constant V0PITCHL: std_logic_vector(7 downto 0) := x"02"; 
	constant V1PITCHL: std_logic_vector(7 downto 0) := x"12"; 
	constant V2PITCHL: std_logic_vector(7 downto 0) := x"22"; 
	constant V3PITCHL: std_logic_vector(7 downto 0) := x"32"; 
	constant V4PITCHL: std_logic_vector(7 downto 0) := x"42"; 
	constant V5PITCHL: std_logic_vector(7 downto 0) := x"52"; 
	constant V6PITCHL: std_logic_vector(7 downto 0) := x"62"; 
	constant V7PITCHL: std_logic_vector(7 downto 0) := x"72"; 
	
	constant V0PITCHH: std_logic_vector(7 downto 0) := x"03"; 
	constant V1PITCHH: std_logic_vector(7 downto 0) := x"13"; 
	constant V2PITCHH: std_logic_vector(7 downto 0) := x"23"; 
	constant V3PITCHH: std_logic_vector(7 downto 0) := x"33"; 
	constant V4PITCHH: std_logic_vector(7 downto 0) := x"43"; 
	constant V5PITCHH: std_logic_vector(7 downto 0) := x"53"; 
	constant V6PITCHH: std_logic_vector(7 downto 0) := x"63"; 
	constant V7PITCHH: std_logic_vector(7 downto 0) := x"73"; 
	
	constant V0SRCN: std_logic_vector(7 downto 0) := x"04"; 
	constant V1SRCN: std_logic_vector(7 downto 0) := x"14"; 
	constant V2SRCN: std_logic_vector(7 downto 0) := x"24"; 
	constant V3SRCN: std_logic_vector(7 downto 0) := x"34"; 
	constant V4SRCN: std_logic_vector(7 downto 0) := x"44"; 
	constant V5SRCN: std_logic_vector(7 downto 0) := x"54"; 
	constant V6SRCN: std_logic_vector(7 downto 0) := x"64"; 
	constant V7SRCN: std_logic_vector(7 downto 0) := x"74"; 
	
	constant V0ADSR1: std_logic_vector(7 downto 0) := x"05"; 
	constant V1ADSR1: std_logic_vector(7 downto 0) := x"15"; 
	constant V2ADSR1: std_logic_vector(7 downto 0) := x"25"; 
	constant V3ADSR1: std_logic_vector(7 downto 0) := x"35"; 
	constant V4ADSR1: std_logic_vector(7 downto 0) := x"45"; 
	constant V5ADSR1: std_logic_vector(7 downto 0) := x"55"; 
	constant V6ADSR1: std_logic_vector(7 downto 0) := x"65"; 
	constant V7ADSR1: std_logic_vector(7 downto 0) := x"75";
	
	constant V0ADSR2: std_logic_vector(7 downto 0) := x"06"; 
	constant V1ADSR2: std_logic_vector(7 downto 0) := x"16"; 
	constant V2ADSR2: std_logic_vector(7 downto 0) := x"26"; 
	constant V3ADSR2: std_logic_vector(7 downto 0) := x"36"; 
	constant V4ADSR2: std_logic_vector(7 downto 0) := x"46"; 
	constant V5ADSR2: std_logic_vector(7 downto 0) := x"56"; 
	constant V6ADSR2: std_logic_vector(7 downto 0) := x"66"; 
	constant V7ADSR2: std_logic_vector(7 downto 0) := x"76";
	
	constant V0GAIN: std_logic_vector(7 downto 0) := x"07"; 
	constant V1GAIN: std_logic_vector(7 downto 0) := x"17"; 
	constant V2GAIN: std_logic_vector(7 downto 0) := x"27"; 
	constant V3GAIN: std_logic_vector(7 downto 0) := x"37"; 
	constant V4GAIN: std_logic_vector(7 downto 0) := x"47"; 
	constant V5GAIN: std_logic_vector(7 downto 0) := x"57"; 
	constant V6GAIN: std_logic_vector(7 downto 0) := x"67"; 
	constant V7GAIN: std_logic_vector(7 downto 0) := x"77";
	
	constant V0ENVX: std_logic_vector(7 downto 0) := x"08"; 
	constant V1ENVX: std_logic_vector(7 downto 0) := x"18"; 
	constant V2ENVX: std_logic_vector(7 downto 0) := x"28"; 
	constant V3ENVX: std_logic_vector(7 downto 0) := x"38"; 
	constant V4ENVX: std_logic_vector(7 downto 0) := x"48"; 
	constant V5ENVX: std_logic_vector(7 downto 0) := x"58"; 
	constant V6ENVX: std_logic_vector(7 downto 0) := x"68"; 
	constant V7ENVX: std_logic_vector(7 downto 0) := x"78";
	
	constant V0OUTX: std_logic_vector(7 downto 0) := x"09"; 
	constant V1OUTX: std_logic_vector(7 downto 0) := x"19"; 
	constant V2OUTX: std_logic_vector(7 downto 0) := x"29"; 
	constant V3OUTX: std_logic_vector(7 downto 0) := x"39"; 
	constant V4OUTX: std_logic_vector(7 downto 0) := x"49"; 
	constant V5OUTX: std_logic_vector(7 downto 0) := x"59"; 
	constant V6OUTX: std_logic_vector(7 downto 0) := x"69"; 
	constant V7OUTX: std_logic_vector(7 downto 0) := x"79";
	
	constant MVOLL: std_logic_vector(7 downto 0) := x"0C"; 
	constant MVOLR: std_logic_vector(7 downto 0) := x"1C"; 
	constant EVOLL: std_logic_vector(7 downto 0) := x"2C"; 
	constant EVOLR: std_logic_vector(7 downto 0) := x"3C"; 
	constant KON: std_logic_vector(7 downto 0) := x"4C"; 
	constant KOFF: std_logic_vector(7 downto 0) := x"5C"; 
	constant FLG: std_logic_vector(7 downto 0) := x"6C"; 
	constant ENDX: std_logic_vector(7 downto 0) := x"7C";
	
	constant EFB: std_logic_vector(7 downto 0) := x"0D"; 
	constant PMON: std_logic_vector(7 downto 0) := x"2D"; 
	constant NON: std_logic_vector(7 downto 0) := x"3D"; 
	constant EON: std_logic_vector(7 downto 0) := x"4D"; 
	constant DIR: std_logic_vector(7 downto 0) := x"5D"; 
	constant ESA: std_logic_vector(7 downto 0) := x"6D"; 
	constant EDL: std_logic_vector(7 downto 0) := x"7D";
	
	constant FIR0: std_logic_vector(7 downto 0) := x"0F"; 
	constant FIR1: std_logic_vector(7 downto 0) := x"1F"; 
	constant FIR2: std_logic_vector(7 downto 0) := x"2F"; 
	constant FIR3: std_logic_vector(7 downto 0) := x"3F"; 
	constant FIR4: std_logic_vector(7 downto 0) := x"4F"; 
	constant FIR5: std_logic_vector(7 downto 0) := x"5F"; 
	constant FIR6: std_logic_vector(7 downto 0) := x"6F"; 
	constant FIR7: std_logic_vector(7 downto 0) := x"7F";
	
	type RegsAccessTbl_t is array(0 to 31, 0 to 3) of std_logic_vector(7 downto 0);
	constant  RA_TBL: RegsAccessTbl_t := (
	(V0VOLR, V1PITCHL, V1ADSR1, x"7E"),
	(x"7E",  V1PITCHH, V1ADSR2, x"7E"),
	(V0OUTX, V1VOLL,   V3SRCN,  x"7E"),
	(V1VOLR, V2PITCHL, V2ADSR1, x"7E"),
	(V0ENVX, V2PITCHH, V2ADSR2, x"7E"),
	(V1OUTX, V2VOLL,   V4SRCN,  x"7E"),
	(V2VOLR, V3PITCHL, V3ADSR1, x"7E"),
	(V1ENVX, V3PITCHH, V3ADSR2, x"7E"),
	(V2OUTX, V3VOLL,   V5SRCN,  x"7E"),
	(V3VOLR, V4PITCHL, V4ADSR1, x"7E"),
	(V2ENVX, V4PITCHH, V4ADSR2, x"7E"),
	(V3OUTX, V4VOLL,   V6SRCN,  x"7E"),
	(V4VOLR, V5PITCHL, V5ADSR1, x"7E"),
	(V3ENVX, V5PITCHH, V5ADSR2, x"7E"),
	(V4OUTX, V5VOLL,   V7SRCN,  x"7E"),
	(V5VOLR, V6PITCHL, V6ADSR1, x"7E"),
	(V4ENVX, V6PITCHH, V6ADSR2, x"7E"),--
	(V5OUTX, V6VOLL,   V0SRCN,  x"7E"),
	(V6VOLR, V7PITCHL, V7ADSR1, x"7E"),
	(V5ENVX, V7PITCHH, V7ADSR2, x"7E"),
	(V6OUTX, V7VOLL,   V1SRCN,  x"7E"),
	(V7VOLR, V0PITCHL, V0ADSR1, x"7E"),
	(V6ENVX, V0PITCHH, FIR0, 	 x"7E"),
	(V7OUTX, FIR1,     FIR2,    x"7E"),
	(FIR3,   FIR4,     FIR5,    x"7E"),
	(V7ENVX, FIR6,     FIR7,    x"7E"),
	(MVOLL,  EVOLL, 	 EFB,     x"7E"),
	(MVOLR,  EVOLR, 	 PMON,    x"7E"),
	(NON,    EON,      DIR,     x"7E"),
	(EDL,    ESA,      KON,     x"7E"),
	(KOFF,   FLG,      V0ADSR2, x"7E"),
	(x"7E",  V0VOLL,   V2SRCN,  x"7E")
	);
	
	type VoiceStep_t is (
		VS_IDLE,
		VS_VOLL,
		VS_VOLR,
		VS_PITCHL,
		VS_PITCHH,
		VS_ADSR1,
		VS_ADSR2,
		VS_SRCN,
		VS_ENVX,
		VS_OUTX,
		VS_FIR0,
		VS_FIR1,
		VS_FIR2,
		VS_FIR3,
		VS_FIR4,
		VS_FIR5,
		VS_FIR6,
		VS_FIR7,
		VS_MVOLL,
		VS_MVOLR,
		VS_EVOLL,
		VS_EVOLR,
		VS_EFB,
		VS_PMON,
		VS_NON,
		VS_EON,
		VS_DIR,
		VS_EDL,
		VS_ESA,
		VS_KON,
		VS_KOFF,
		VS_FLG,
		VS_ECHO
	);
	
	type VoiceStep_r is record
		S        : VoiceStep_t;
		V        : integer range 0 to 7;
	end record;
	
	type VoiceStepTbl_t is array(0 to 31, 0 to 3) of VoiceStep_r;
	constant VS_TBL: VoiceStepTbl_t := (
	((VS_VOLR,0),  (VS_PITCHL,1), (VS_ADSR1,1), (VS_IDLE,0)),
	((VS_IDLE,0),  (VS_PITCHH,1), (VS_ADSR2,1), (VS_IDLE,0)),
	((VS_OUTX,0),  (VS_VOLL,1),   (VS_SRCN,3),  (VS_IDLE,0)),
	((VS_VOLR,1),  (VS_PITCHL,2), (VS_ADSR1,2), (VS_IDLE,0)),
	((VS_ENVX,0),  (VS_PITCHH,2), (VS_ADSR2,2), (VS_IDLE,0)),
	((VS_OUTX,1),  (VS_VOLL,2),   (VS_SRCN,4),  (VS_IDLE,0)),
	((VS_VOLR,2),  (VS_PITCHL,3), (VS_ADSR1,3), (VS_IDLE,0)),
	((VS_ENVX,1),  (VS_PITCHH,3), (VS_ADSR2,3), (VS_IDLE,0)),
	((VS_OUTX,2),  (VS_VOLL,3),   (VS_SRCN,5),  (VS_IDLE,0)),
	((VS_VOLR,3),  (VS_PITCHL,4), (VS_ADSR1,4), (VS_IDLE,0)),
	((VS_ENVX,2),  (VS_PITCHH,4), (VS_ADSR2,4), (VS_IDLE,0)),
	((VS_OUTX,3),  (VS_VOLL,4),   (VS_SRCN,6),  (VS_IDLE,0)),
	((VS_VOLR,4),  (VS_PITCHL,5), (VS_ADSR1,5), (VS_IDLE,0)),
	((VS_ENVX,3),  (VS_PITCHH,5), (VS_ADSR2,5), (VS_IDLE,0)),
	((VS_OUTX,4),  (VS_VOLL,5),   (VS_SRCN,7),  (VS_IDLE,0)),
	((VS_VOLR,5),  (VS_PITCHL,6), (VS_ADSR1,6), (VS_IDLE,0)),
	((VS_ENVX,4),  (VS_PITCHH,6), (VS_ADSR2,6), (VS_IDLE,0)),--
	((VS_OUTX,5),  (VS_VOLL,6),   (VS_SRCN,0),  (VS_IDLE,0)),
	((VS_VOLR,6),  (VS_PITCHL,7), (VS_ADSR1,7), (VS_IDLE,0)),
	((VS_ENVX,5),  (VS_PITCHH,7), (VS_ADSR2,7), (VS_IDLE,0)),
	((VS_OUTX,6),  (VS_VOLL,7),   (VS_SRCN,1),  (VS_IDLE,0)),
	((VS_VOLR,7),  (VS_PITCHL,0), (VS_ADSR1,0), (VS_IDLE,0)),
	((VS_ENVX,6),  (VS_PITCHH,0), (VS_FIR0,0),  (VS_IDLE,0)),
	((VS_OUTX,7),  (VS_FIR1,1),   (VS_FIR2,2),  (VS_IDLE,0)),
	((VS_FIR3,3),  (VS_FIR4,4),   (VS_FIR5,5),  (VS_IDLE,0)),
	((VS_ENVX,7),  (VS_FIR6,6),   (VS_FIR7,7),  (VS_IDLE,0)),
	((VS_MVOLL,0), (VS_EVOLL,0),  (VS_EFB,0),   (VS_IDLE,0)),
	((VS_MVOLR,0), (VS_EVOLR,0),  (VS_PMON,0),  (VS_IDLE,0)),
	((VS_NON,0),   (VS_EON,0),    (VS_DIR,0),   (VS_IDLE,0)),
	((VS_EDL,0),   (VS_ESA,0),    (VS_KON,0),   (VS_IDLE,0)),
	((VS_KOFF,0),  (VS_FLG,0),    (VS_ADSR2,0), (VS_IDLE,0)),
	((VS_ECHO,0),  (VS_VOLL,0),   (VS_SRCN,2),  (VS_IDLE,0))
	);

	
	--RAM Access
	type RamStep_t is (
		RS_IDLE,
		RS_BRRH,
		RS_BRR1,
		RS_BRR2,
		RS_SRCNL,
		RS_SRCNH,
		RS_ECHORDL,
		RS_ECHORDH,
		RS_ECHOWRL,
		RS_ECHOWRH,
		RS_SMP
	);
	
	type RamStepTbl_t is array(0 to 31, 0 to 3) of RamStep_t;
	constant RS_TBL: RamStepTbl_t := (
	(RS_SRCNL,    RS_SRCNH,    RS_IDLE,  RS_SMP),
	(RS_BRR1,     RS_BRRH,     RS_IDLE,  RS_SMP),
	(RS_BRR2,     RS_IDLE,     RS_IDLE,  RS_SMP),
	(RS_SRCNL,    RS_SRCNH,    RS_IDLE,  RS_SMP),
	(RS_BRR1,     RS_BRRH,     RS_IDLE,  RS_SMP),
	(RS_BRR2,     RS_IDLE,     RS_IDLE,  RS_SMP),
	(RS_SRCNL,    RS_SRCNH,    RS_IDLE,  RS_SMP),
	(RS_BRR1,     RS_BRRH,     RS_IDLE,  RS_SMP),
	(RS_BRR2,     RS_IDLE,     RS_IDLE,  RS_SMP),
	(RS_SRCNL,    RS_SRCNH,    RS_IDLE,  RS_SMP),
	(RS_BRR1,     RS_BRRH,     RS_IDLE,  RS_SMP),
	(RS_BRR2,     RS_IDLE,     RS_IDLE,  RS_SMP),
	(RS_SRCNL,    RS_SRCNH,    RS_IDLE,  RS_SMP),
	(RS_BRR1,     RS_BRRH,     RS_IDLE,  RS_SMP),
	(RS_BRR2,     RS_IDLE,     RS_IDLE,  RS_SMP),
	(RS_SRCNL,    RS_SRCNH,    RS_IDLE,  RS_SMP),
	(RS_BRR1,     RS_BRRH,     RS_IDLE,  RS_SMP),--16
	(RS_BRR2,     RS_IDLE,     RS_IDLE,  RS_SMP),
	(RS_SRCNL,    RS_SRCNH,    RS_IDLE,  RS_SMP),
	(RS_BRR1,     RS_BRRH,     RS_IDLE,  RS_SMP),
	(RS_BRR2,     RS_IDLE,     RS_IDLE,  RS_SMP),
	(RS_SRCNL,    RS_SRCNH,    RS_IDLE,  RS_SMP),
	(RS_ECHORDL,  RS_ECHORDH,  RS_IDLE,  RS_SMP),
	(RS_ECHORDL,  RS_ECHORDH,  RS_IDLE,  RS_SMP),
	(RS_IDLE,     RS_IDLE,     RS_IDLE,  RS_SMP),
	(RS_BRR1,     RS_BRRH,     RS_IDLE,  RS_SMP),
	(RS_IDLE,     RS_IDLE,     RS_IDLE,  RS_SMP),
	(RS_IDLE,     RS_IDLE,     RS_IDLE,  RS_SMP),
	(RS_IDLE,     RS_IDLE,     RS_IDLE,  RS_SMP),
	(RS_ECHOWRL,  RS_ECHOWRH,  RS_IDLE,  RS_SMP),
	(RS_ECHOWRL,  RS_ECHOWRH,  RS_IDLE,  RS_SMP),
	(RS_BRR2,     RS_IDLE,     RS_IDLE,  RS_SMP)
	);
	
	type BrrVoiceTbl_t is array(0 to 31) of integer range 0 to 7;
	constant BRR_VOICE_TBL: BrrVoiceTbl_t := (
	1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7, 
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	);
	
	--BRR Decode
	type BRRDecodeStep_t is (
		BDS_IDLE,
		BDS_SMPL0,
		BDS_SMPL1,
		BDS_SMPL2,
		BDS_SMPL3
	);
	
	type BRRDecodeStep_r is record
		S        : BRRDecodeStep_t;
		V        : integer range 0 to 7;
	end record;

	type BRRDecodeStepTbl_t is array(0 to 31, 0 to 3) of BRRDecodeStep_r;
	constant BDS_TBL: BRRDecodeStepTbl_t := (
	((BDS_SMPL2,0), (BDS_SMPL3,0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_SMPL0,1), (BDS_SMPL1,1)),
	((BDS_SMPL2,1), (BDS_SMPL3,1), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_SMPL0,2), (BDS_SMPL1,2)),
	((BDS_SMPL2,2), (BDS_SMPL3,2), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_SMPL0,3), (BDS_SMPL1,3)),
	((BDS_SMPL2,3), (BDS_SMPL3,3), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_SMPL0,4), (BDS_SMPL1,4)),
	((BDS_SMPL2,4), (BDS_SMPL3,4), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_SMPL0,5), (BDS_SMPL1,5)),
	((BDS_SMPL2,5), (BDS_SMPL3,5), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_SMPL0,6), (BDS_SMPL1,6)),
	((BDS_SMPL2,6), (BDS_SMPL3,6), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_SMPL0,7), (BDS_SMPL1,7)),
	((BDS_SMPL2,7), (BDS_SMPL3,7), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_IDLE, 0)),
	((BDS_IDLE, 0), (BDS_IDLE, 0), (BDS_SMPL0,0), (BDS_SMPL1,0))
	);
	
	--RAM Access
	type IntStep_t is (
		IS_IDLE,
		IS_ENV,
		IS_ENV2
	);
	
	type IntStep_r is record
		S        : IntStep_t;
		V        : integer range 0 to 7;
	end record;
	
	type IntStepTbl_t is array(0 to 31, 0 to 3) of IntStep_r;
	constant IS_TBL: IntStepTbl_t := (
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 1),    (IS_ENV,  1),    (IS_ENV2, 1)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 2),    (IS_ENV,  2),    (IS_ENV2, 2)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 3),    (IS_ENV,  3),    (IS_ENV2, 3)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 4),    (IS_ENV,  4),    (IS_ENV2, 4)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 5),    (IS_ENV,  5),    (IS_ENV2, 5)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 6),    (IS_ENV,  6),    (IS_ENV2, 6)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 7),    (IS_ENV,  7),    (IS_ENV2, 7)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_ENV,  0),    (IS_ENV2, 0)),
	((IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0),    (IS_IDLE, 0))
	);

	type GaussStep_t is (
		GS_IDLE,
		GS_WAIT,
		GS_BRR0,
		GS_BRR1,
		GS_BRR2,
		GS_BRR3
	);

	type BrrDecState_t is (
		BD_IDLE,
		BD_WAIT,
		BD_P0,
		BD_P1
	);

	--Envelope Modes
	type EnvMode_t is (
		EM_RELEASE,
		EM_ATTACK,
		EM_DECAY,
		EM_SUSTAIN
	);
	
	type GaussTbl_t is array(0 to 511) of signed(11 downto 0);
	constant  GTBL: GaussTbl_t := (
	x"000", x"000", x"000", x"000", x"000", x"000", x"000", x"000",
	x"000", x"000", x"000", x"000", x"000", x"000", x"000", x"000",
	x"001", x"001", x"001", x"001", x"001", x"001", x"001", x"001",
	x"001", x"001", x"001", x"002", x"002", x"002", x"002", x"002",
	x"002", x"002", x"003", x"003", x"003", x"003", x"003", x"004",
	x"004", x"004", x"004", x"004", x"005", x"005", x"005", x"005",
	x"006", x"006", x"006", x"006", x"007", x"007", x"007", x"008",
	x"008", x"008", x"009", x"009", x"009", x"00A", x"00A", x"00A",
	x"00B", x"00B", x"00B", x"00C", x"00C", x"00D", x"00D", x"00E",
	x"00E", x"00F", x"00F", x"00F", x"010", x"010", x"011", x"011",
	x"012", x"013", x"013", x"014", x"014", x"015", x"015", x"016",
	x"017", x"017", x"018", x"018", x"019", x"01A", x"01B", x"01B",
	x"01C", x"01D", x"01D", x"01E", x"01F", x"020", x"020", x"021",
	x"022", x"023", x"024", x"024", x"025", x"026", x"027", x"028",
	x"029", x"02A", x"02B", x"02C", x"02D", x"02E", x"02F", x"030",
	x"031", x"032", x"033", x"034", x"035", x"036", x"037", x"038",
	x"03A", x"03B", x"03C", x"03D", x"03E", x"040", x"041", x"042",
	x"043", x"045", x"046", x"047", x"049", x"04A", x"04C", x"04D",
	x"04E", x"050", x"051", x"053", x"054", x"056", x"057", x"059",
	x"05A", x"05C", x"05E", x"05F", x"061", x"063", x"064", x"066",
	x"068", x"06A", x"06B", x"06D", x"06F", x"071", x"073", x"075",
	x"076", x"078", x"07A", x"07C", x"07E", x"080", x"082", x"084",
	x"086", x"089", x"08B", x"08D", x"08F", x"091", x"093", x"096",
	x"098", x"09A", x"09C", x"09F", x"0A1", x"0A3", x"0A6", x"0A8",
	x"0AB", x"0AD", x"0AF", x"0B2", x"0B4", x"0B7", x"0BA", x"0BC",
	x"0BF", x"0C1", x"0C4", x"0C7", x"0C9", x"0CC", x"0CF", x"0D2",
	x"0D4", x"0D7", x"0DA", x"0DD", x"0E0", x"0E3", x"0E6", x"0E9",
	x"0EC", x"0EF", x"0F2", x"0F5", x"0F8", x"0FB", x"0FE", x"101",
	x"104", x"107", x"10B", x"10E", x"111", x"114", x"118", x"11B",
	x"11E", x"122", x"125", x"129", x"12C", x"130", x"133", x"137",
	x"13A", x"13E", x"141", x"145", x"148", x"14C", x"150", x"153",
	x"157", x"15B", x"15F", x"162", x"166", x"16A", x"16E", x"172",
	x"176", x"17A", x"17D", x"181", x"185", x"189", x"18D", x"191",--
	x"195", x"19A", x"19E", x"1A2", x"1A6", x"1AA", x"1AE", x"1B2",
	x"1B7", x"1BB", x"1BF", x"1C3", x"1C8", x"1CC", x"1D0", x"1D5",
	x"1D9", x"1DD", x"1E2", x"1E6", x"1EB", x"1EF", x"1F3", x"1F8",
	x"1FC", x"201", x"205", x"20A", x"20F", x"213", x"218", x"21C",
	x"221", x"226", x"22A", x"22F", x"233", x"238", x"23D", x"241",
	x"246", x"24B", x"250", x"254", x"259", x"25E", x"263", x"267",
	x"26C", x"271", x"276", x"27B", x"280", x"284", x"289", x"28E",
	x"293", x"298", x"29D", x"2A2", x"2A6", x"2AB", x"2B0", x"2B5",
	x"2BA", x"2BF", x"2C4", x"2C9", x"2CE", x"2D3", x"2D8", x"2DC",
	x"2E1", x"2E6", x"2EB", x"2F0", x"2F5", x"2FA", x"2FF", x"304",
	x"309", x"30E", x"313", x"318", x"31D", x"322", x"326", x"32B",
	x"330", x"335", x"33A", x"33F", x"344", x"349", x"34E", x"353",
	x"357", x"35C", x"361", x"366", x"36B", x"370", x"374", x"379",
	x"37E", x"383", x"388", x"38C", x"391", x"396", x"39B", x"39F",
	x"3A4", x"3A9", x"3AD", x"3B2", x"3B7", x"3BB", x"3C0", x"3C5",
	x"3C9", x"3CE", x"3D2", x"3D7", x"3DC", x"3E0", x"3E5", x"3E9",
	x"3ED", x"3F2", x"3F6", x"3FB", x"3FF", x"403", x"408", x"40C",
	x"410", x"415", x"419", x"41D", x"421", x"425", x"42A", x"42E",
	x"432", x"436", x"43A", x"43E", x"442", x"446", x"44A", x"44E",
	x"452", x"455", x"459", x"45D", x"461", x"465", x"468", x"46C",
	x"470", x"473", x"477", x"47A", x"47E", x"481", x"485", x"488",
	x"48C", x"48F", x"492", x"496", x"499", x"49C", x"49F", x"4A2",
	x"4A6", x"4A9", x"4AC", x"4AF", x"4B2", x"4B5", x"4B7", x"4BA",
	x"4BD", x"4C0", x"4C3", x"4C5", x"4C8", x"4CB", x"4CD", x"4D0",
	x"4D2", x"4D5", x"4D7", x"4D9", x"4DC", x"4DE", x"4E0", x"4E3",
	x"4E5", x"4E7", x"4E9", x"4EB", x"4ED", x"4EF", x"4F1", x"4F3",
	x"4F5", x"4F6", x"4F8", x"4FA", x"4FB", x"4FD", x"4FF", x"500",
	x"502", x"503", x"504", x"506", x"507", x"508", x"50A", x"50B",
	x"50C", x"50D", x"50E", x"50F", x"510", x"511", x"511", x"512",
	x"513", x"514", x"514", x"515", x"516", x"516", x"517", x"517",
	x"517", x"518", x"518", x"518", x"518", x"518", x"519", x"519" 
	);
	
	type KonCnt_t is array (0 to 7) of unsigned(2 downto 0);
	type BrrAddr_t is array (0 to 7) of std_logic_vector(15 downto 0);
	type BrrOffs_t is array (0 to 7) of unsigned(2 downto 0);
	type VoiceBrrBufAddr_t is array(0 to 7) of unsigned(3 downto 0);
	type Out_t is array (0 to 1) of signed(15 downto 0);
	type EchoBuf_t is array (0 to 7) of std_logic_vector(14 downto 0);
	type ChEchoBuf_t is array (0 to 1) of EchoBuf_t;
	type EchoFir_t is array (0 to 1) of signed(15 downto 0);
	type EchoFir17_t is array (0 to 1) of signed(15 downto 0);
	type EchoFFC_t is array (0 to 7) of signed(7 downto 0);
	type ChEnvMode_t is array (0 to 7) of EnvMode_t;
	type Env_t is array (0 to 7) of signed(11 downto 0);
	type EnvxBuf_t is array (0 to 7) of std_logic_vector(7 downto 0);
	type InterpPos_t is array (0 to 7) of unsigned(15 downto 0);
	
	function CLAMP16(a: signed(16 downto 0)) return signed; 
	
end DSP_PKG;

package body DSP_PKG is

	function CLAMP16(a: signed(16 downto 0)) return signed is
		variable res: signed(15 downto 0); 
	begin
		if a(16 downto 15) = "01" then
			res := x"7FFF";
		elsif a(16 downto 15) = "10" then
			res := x"8000";
		else
			res := a(16) & a(14 downto 0);
		end if;
		return res;
	end function;

end package body DSP_PKG;
