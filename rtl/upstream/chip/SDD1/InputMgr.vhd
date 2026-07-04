library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity InputMgr is
	port(
		RST_N			: in std_logic;
		CLK			: in std_logic;
		ENABLE		: in std_logic;
		
		INIT_ADDR	: in std_logic_vector(23 downto 0);
		
		INIT			: in std_logic;
		DATA_REQ		: in std_logic;

		ROM_ADDR		: out std_logic_vector(23 downto 0);
		ROM_DATA		: in std_logic_vector(15 downto 0);
		
		ROM_RD		: in  std_logic;
		
		OUT_DATA    : out std_logic_vector(15 downto 0);
		HEADER      : out std_logic_vector(3 downto 0);
		
		INIT_DONE	: out std_logic
	);
end InputMgr;

architecture rtl of InputMgr is

	signal LOAD_ADDR	: std_logic_vector(23 downto 0);
	signal CURR_DATA, NEXT_DATA : std_logic_vector(15 downto 0);
	signal BYTE_LOAD	: std_logic;
	signal INIT_CNT 	: std_logic_vector(1 downto 0);
	signal WAIT_ACCESS: std_logic_vector(1 downto 0);
	signal TINIT_DONE	: std_logic;
	
	type DataBuf_t is array(0 to 3) of std_logic_vector(15 downto 0);
	signal DATA_BUF: DataBuf_t;
	attribute ramstyle : string;
	attribute ramstyle of DATA_BUF : signal is "logic";	
	signal WR_POS 	: std_logic_vector(1 downto 0);
	signal RD_POS 	: std_logic_vector(1 downto 0);
begin

	process( RST_N, CLK)
		variable READ_REQ  : std_logic;
		variable WRITE_REQ : std_logic;
	begin
		if RST_N = '0' then
			HEADER <= (others => '0');
			CURR_DATA <= (others => '0');
			NEXT_DATA <= (others => '0');
			LOAD_ADDR <= (others => '0');
			INIT_CNT <= (others => '0');
			BYTE_LOAD <= '0';
			TINIT_DONE <= '0';
			WAIT_ACCESS <= (others => '1');
			WR_POS <= (others => '0');
			RD_POS <= (others => '0');
		elsif rising_edge(CLK) then
			if ENABLE = '1' then
				if DATA_REQ = '1' and BYTE_LOAD = '1' then
					READ_REQ := '1';
				else
					READ_REQ := '0';
				end if;
				
				if ROM_RD = '1' and (WR_POS + 1 /= RD_POS) then
					WAIT_ACCESS <= (others => '0');
				elsif WAIT_ACCESS < 3 then
					WAIT_ACCESS <= WAIT_ACCESS + 1;
				end if;

				if WAIT_ACCESS = 1 then
					WRITE_REQ := '1';
				else
					WRITE_REQ := '0';
				end if;

				if INIT = '1' then
					LOAD_ADDR <= INIT_ADDR;
					INIT_CNT <= (others => '0');
					TINIT_DONE <= '0';
					WAIT_ACCESS <= (others => '1');
					WR_POS <= (others => '0');
					RD_POS <= (others => '0');
				else
					if TINIT_DONE = '0' and (WR_POS + 1 = RD_POS) then
						TINIT_DONE <= '1';
					end if;
						
					if INIT_CNT < 3 and WRITE_REQ = '1' then
						if INIT_CNT = 0 then
							if LOAD_ADDR(0) = '0' then
								CURR_DATA <= ROM_DATA(7 downto 0) & ROM_DATA(15 downto 8);
								HEADER <= ROM_DATA(7 downto 4);
								LOAD_ADDR <= LOAD_ADDR + 2;
							else
								CURR_DATA(15 downto 8) <= ROM_DATA(15 downto 8);
								HEADER <= ROM_DATA(15 downto 12);
								LOAD_ADDR <= LOAD_ADDR + 1;
							end if;
							BYTE_LOAD <= LOAD_ADDR(0);
						elsif INIT_CNT = 1 then
							if BYTE_LOAD = '1' then
								CURR_DATA(7 downto 0) <= ROM_DATA(7 downto 0);
							end if;
							NEXT_DATA <= ROM_DATA;
							LOAD_ADDR <= LOAD_ADDR + 2;
						end if;
						INIT_CNT <= INIT_CNT + 1;
						
					else
						if DATA_REQ = '1' then
							BYTE_LOAD <= not BYTE_LOAD;
							if BYTE_LOAD = '0' then
								CURR_DATA <= CURR_DATA(7 downto 0) & NEXT_DATA(7 downto 0);
							else
								CURR_DATA <= CURR_DATA(7 downto 0) & NEXT_DATA(15 downto 8);
							end if;
						end if;
						
						if READ_REQ = '1' then
							NEXT_DATA <= DATA_BUF(conv_integer(RD_POS));
							if RD_POS /= WR_POS then
								RD_POS <= RD_POS + 1;
							end if;
						end if;
						
						if WRITE_REQ = '1' then
							DATA_BUF(conv_integer(WR_POS)) <= ROM_DATA;
							LOAD_ADDR <= LOAD_ADDR + 2;
							WR_POS <= WR_POS + 1;
						end if;

					end if;
				end if;
			end if;
		end if;
	end process;
	
	ROM_ADDR <= LOAD_ADDR;
	OUT_DATA <= CURR_DATA;
	INIT_DONE <= TINIT_DONE;

end rtl;
