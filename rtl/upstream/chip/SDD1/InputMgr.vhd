library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity InputMgr is
	generic (ROM_HANDSHAKE : boolean := false);
	port(
        ROM_NEED : out std_logic;
        ROM_READY : in std_logic := '0';
        ROM_RETIRE : out std_logic;
        DATA_READY : out std_logic;

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
    legacy_input: if not ROM_HANDSHAKE generate
    ROM_NEED <= '0';
    ROM_RETIRE <= '0';
    DATA_READY <= '1';

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

    end generate;

    -- The queue includes the two-byte decoder window. A pop is legal only
    -- when a third byte exists; that byte becomes the new low window byte.
    -- Refill runs on CLK independently of CPU phases and decoder ENABLE.
    handshake_input: if ROM_HANDSHAKE generate
        type byte_queue_t is array(0 to 11) of std_logic_vector(7 downto 0);
        signal bytes : byte_queue_t := (others => (others => '0'));
        signal count : integer range 0 to 12 := 0;
        signal address : std_logic_vector(23 downto 0) := (others => '0');
        signal active, first_word, need : std_logic := '0';
    begin
        need <= '1' when active='1' and INIT='0' and count<=10 else '0';
        ROM_NEED <= need;
        ROM_RETIRE <= need and ROM_READY;
        ROM_ADDR <= address;
        OUT_DATA <= bytes(0) & bytes(1);
        DATA_READY <= '1' when count>=3 else '0';
        INIT_DONE <= '1' when active='1' and count>=2 else '0';
        process(CLK, RST_N)
            variable q : byte_queue_t;
            variable n : integer range 0 to 12;
        begin
            if RST_N='0' then
                bytes <= (others => (others => '0'));
                count <= 0; address <= (others => '0');
                active <= '0'; first_word <= '1'; HEADER <= (others => '0');
            elsif rising_edge(CLK) then
                if INIT='1' and ENABLE='1' then
                    count <= 0; address <= INIT_ADDR;
                    active <= '1'; first_word <= '1';
                else
                    q := bytes; n := count;
                    if ENABLE='1' and DATA_REQ='1' then
                        assert count>=3 report "SDD1 input pop without a replacement byte" severity failure;
                        if count>=3 then
                            for i in 0 to 10 loop q(i) := q(i+1); end loop;
                            n := n-1;
                        end if;
                    end if;
                    if need='1' and ROM_READY='1' then
                        if first_word='1' and address(0)='1' then
                            q(n) := ROM_DATA(15 downto 8); n := n+1;
                            HEADER <= ROM_DATA(15 downto 12);
                            address <= address+1;
                        else
                            q(n) := ROM_DATA(7 downto 0);
                            q(n+1) := ROM_DATA(15 downto 8); n := n+2;
                            if first_word='1' then HEADER <= ROM_DATA(7 downto 4); end if;
                            address <= address+2;
                        end if;
                        first_word <= '0';
                    end if;
                    bytes <= q; count <= n;
                end if;
            end if;
        end process;
    end generate;
end rtl;
