LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY mlab IS
	generic (
		addr_width    : integer := 8;
		data_width    : integer := 8
	);
	PORT
	(
		clock   		: in  STD_LOGIC;
		rdaddress 	: in  STD_LOGIC_VECTOR (addr_width-1 DOWNTO 0);
		wraddress 	: in  STD_LOGIC_VECTOR (addr_width-1 DOWNTO 0);
		data			: in  STD_LOGIC_VECTOR (data_width-1 DOWNTO 0) := (others => '0');
		wren    		: in  STD_LOGIC := '0';
		q       		: out STD_LOGIC_VECTOR (data_width-1 DOWNTO 0);
		cs      		: in  std_logic := '1'
	);
END ENTITY;

ARCHITECTURE SYN OF mlab IS
	signal q0 : std_logic_vector((data_width - 1) downto 0);
BEGIN
	q<= q0 when cs = '1' else (others => '1');

	altdpram_component : altdpram
	GENERIC MAP (
		indata_aclr => "OFF",
		indata_reg => "INCLOCK",
		intended_device_family => "Cyclone V",
		lpm_type => "altdpram",
		outdata_aclr => "OFF",
		outdata_reg => "UNREGISTERED",
		ram_block_type => "MLAB",
		rdaddress_aclr => "OFF",
		rdaddress_reg => "UNREGISTERED",
		rdcontrol_aclr => "OFF",
		rdcontrol_reg => "UNREGISTERED",
		read_during_write_mode_mixed_ports => "CONSTRAINED_DONT_CARE",
		width => data_width,
		widthad => addr_width,
		width_byteena => 1,
		wraddress_aclr => "OFF",
		wraddress_reg => "INCLOCK",
		wrcontrol_aclr => "OFF",
		wrcontrol_reg => "INCLOCK"
	)
	PORT MAP (
		data 			=> data,
		outclock 	=> clock,
		rdaddress 	=> rdaddress,
		wren 			=> wren,
		inclock 		=> clock,
		wraddress 	=> wraddress,
		q 				=> q0
	);

END SYN;