library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Four independent result slots and one physical request. A committed posted
-- write survives soft FLUSH even before engine admission; REQ_DRAIN identifies
-- that pre-existing obligation. Only HARD_RESET_N may discard such a token.
entity BSXMemoryBridge is
    port (
        CLK, ENABLE, FLUSH, HARD_RESET_N : in std_logic;
        EPOCH : in std_logic_vector(7 downto 0);
        NEED, RETIRE, WRITES, COMMITTED : in std_logic_vector(3 downto 0);
        ADDRS : in std_logic_vector(91 downto 0);
        WDATAS : in std_logic_vector(63 downto 0);
        WSTRBS : in std_logic_vector(7 downto 0);
        SNES_OWNER : in std_logic_vector(1 downto 0);
        READY, COMPLETED, BYTES : out std_logic_vector(3 downto 0);
        WORDS : out std_logic_vector(63 downto 0);
        FLUSH_ACK, FAULT : out std_logic;
        REQ_VALID : out std_logic;
        REQ_READY : in std_logic;
        REQ_ADDR : out std_logic_vector(22 downto 0);
        REQ_OWNER, REQ_SNES_OWNER : out std_logic_vector(1 downto 0);
        REQ_TAG, REQ_EPOCH : out std_logic_vector(7 downto 0);
        REQ_WRITE, REQ_DRAIN : out std_logic;
        REQ_WDATA : out std_logic_vector(15 downto 0);
        REQ_WSTRB : out std_logic_vector(1 downto 0);
        RSP_VALID : in std_logic;
        RSP_READY : out std_logic;
        RSP_OWNER : in std_logic_vector(1 downto 0);
        RSP_TAG, RSP_EPOCH : in std_logic_vector(7 downto 0);
        RSP_DATA : in std_logic_vector(15 downto 0);
        RSP_ERROR, RSP_WRITE : in std_logic
    );
end entity;
architecture rtl of BSXMemoryBridge is
    type addr_array is array(0 to 3) of std_logic_vector(22 downto 0);
    type word_array is array(0 to 3) of std_logic_vector(15 downto 0);
    type byte_array is array(0 to 3) of std_logic_vector(7 downto 0);
    type pair_array is array(0 to 3) of std_logic_vector(1 downto 0);
    type phase_t is (IDLE, OFFER, INFLIGHT);
    signal phase : phase_t := IDLE;
    signal have, done, dead, errors, is_write, committed_write : std_logic_vector(3 downto 0) := (others=>'0');
    signal addresses : addr_array := (others=>(others=>'0'));
    signal data, write_data : word_array := (others=>(others=>'0'));
    signal epochs : byte_array := (others=>(others=>'0'));
    signal strobes, subowners : pair_array := (others=>(others=>'0'));
    signal held_owner, rr_next : integer range 0 to 3 := 0;
    signal held_tag : std_logic_vector(7 downto 0) := (others=>'0');
    signal next_tag : unsigned(7 downto 0) := (others=>'0');
    signal matched, req_v, fault_i : std_logic;
    signal protocol_fault : std_logic := '0';
begin
    fault_i <= protocol_fault or errors(0) or errors(1) or errors(2) or errors(3);
    FAULT <= fault_i;
    req_v <= '1' when phase=OFFER and HARD_RESET_N='1' and
        (FLUSH='0' or committed_write(held_owner)='1') else '0';
    REQ_VALID <= req_v;
    REQ_ADDR <= addresses(held_owner)(22 downto 1) & '0';
    REQ_OWNER <= std_logic_vector(to_unsigned(held_owner,2));
    REQ_SNES_OWNER <= subowners(held_owner);
    REQ_TAG <= held_tag;
    REQ_EPOCH <= epochs(held_owner);
    REQ_WRITE <= is_write(held_owner);
    REQ_DRAIN <= committed_write(held_owner);
    REQ_WDATA <= write_data(held_owner);
    REQ_WSTRB <= strobes(held_owner);
    RSP_READY <= '1';
    -- Also accept a zero-latency responder on the request-accept edge. Payload
    -- is already retained in OFFER; no direct NEED/ADDRS path participates.
    matched <= '1' when (phase=INFLIGHT or
        (phase=OFFER and req_v='1' and REQ_READY='1')) and RSP_VALID='1' and
        RSP_OWNER=std_logic_vector(to_unsigned(held_owner,2)) and
        RSP_TAG=held_tag and RSP_EPOCH=epochs(held_owner) and
        RSP_WRITE=is_write(held_owner) else '0';

    -- Keep the project's existing VHDL-1993 dialect; list every combinational
    -- input explicitly instead of requiring a global VHDL-2008 mode change.
    process(addresses, data, have, committed_write, done, NEED, COMMITTED,
            dead, FLUSH, errors, matched, held_owner, RSP_ERROR, RSP_DATA, phase)
        variable pending_commit : boolean;
    begin
        READY <= (others=>'0'); COMPLETED <= (others=>'0');
        pending_commit := false;
        for i in 0 to 3 loop
            BYTES(i) <= addresses(i)(0);
            WORDS(i*16+15 downto i*16) <= data(i);
            if (have(i)='1' and committed_write(i)='1' and done(i)='0') or
               (NEED(i)='1' and COMMITTED(i)='1' and have(i)='0') then
                pending_commit := true;
            end if;
            if have(i)='1' and dead(i)='0' and
                ((NEED(i)='1' and FLUSH='0') or committed_write(i)='1') then
                COMPLETED(i) <= done(i);
                if FLUSH='0' then READY(i) <= done(i) and not errors(i); end if;
                if matched='1' and held_owner=i then
                    COMPLETED(i) <= '1';
                    if FLUSH='0' then READY(i) <= not RSP_ERROR; end if;
                    WORDS(i*16+15 downto i*16) <= RSP_DATA;
                end if;
            end if;
        end loop;
        FLUSH_ACK <= '0';
        if phase/=INFLIGHT and not pending_commit and
            not (phase=OFFER and committed_write(held_owner)='1') then FLUSH_ACK <= '1'; end if;
    end process;

    process(CLK,HARD_RESET_N)
        variable found : boolean;
        variable pick : integer range 0 to 3;
    begin
        if HARD_RESET_N='0' then
            phase<=IDLE; have<=(others=>'0'); done<=(others=>'0');
            dead<=(others=>'0'); errors<=(others=>'0');
            is_write<=(others=>'0'); committed_write<=(others=>'0');
            addresses<=(others=>(others=>'0')); data<=(others=>(others=>'0'));
            write_data<=(others=>(others=>'0')); epochs<=(others=>(others=>'0'));
            strobes<=(others=>(others=>'0')); subowners<=(others=>(others=>'0'));
            held_owner<=0; rr_next<=0; held_tag<=(others=>'0'); next_tag<=(others=>'0');
            protocol_fault<='0';
        elsif rising_edge(CLK) then
            for i in 0 to 3 loop
                if (FLUSH='1' or NEED(i)='0') and committed_write(i)='0' and not (NEED(i)='1' and COMMITTED(i)='1') then
                    dead(i)<='1'; done(i)<='0'; errors(i)<='0';
                    if phase/=INFLIGHT or held_owner/=i then have(i)<='0'; end if;
                elsif RETIRE(i)='1' and (ENABLE='1' or committed_write(i)='1') and
                    (done(i)='1' or (matched='1' and held_owner=i)) then
                    have(i)<='0'; done(i)<='0'; committed_write(i)<='0';
                elsif FLUSH='1' and done(i)='1' then
                    -- Outcome already reached; the posted queue sees COMPLETED
                    -- on this same edge. Error is not a successful write.
                    have(i)<='0'; done(i)<='0'; committed_write(i)<='0';
                elsif ((ENABLE='1' and FLUSH='0') or (COMMITTED(i)='1' and WRITES(i)='1')) and NEED(i)='1' and have(i)='0' and
                    not (phase/=IDLE and held_owner=i) and
                    (fault_i='0' or (COMMITTED(i)='1' and WRITES(i)='1')) then
                    have(i)<='1'; done(i)<='0'; dead(i)<='0'; errors(i)<='0';
                    addresses(i)<=ADDRS(i*23+22 downto i*23);
                    write_data(i)<=WDATAS(i*16+15 downto i*16);
                    strobes(i)<=WSTRBS(i*2+1 downto i*2);
                    is_write(i)<=WRITES(i);
                    committed_write(i)<=COMMITTED(i) and WRITES(i);
                    epochs(i)<=EPOCH; subowners(i)<=SNES_OWNER;
                end if;
            end loop;
            -- A consumed error remains fatal even if its slot is retired or
            -- NEED disappears. Only an explicit, physically drained flush may
            -- recover this fault; committed writes still drain while faulted.
            if FLUSH='1' and phase=IDLE then
                protocol_fault<='0'; errors<=(others=>'0');
            end if;
            case phase is
                when IDLE =>
                    found := false; pick := rr_next;
                    for offset in 0 to 3 loop
                        if not found and have((rr_next+offset) mod 4)='1' and
                            done((rr_next+offset) mod 4)='0' and dead((rr_next+offset) mod 4)='0' and
                            (committed_write((rr_next+offset) mod 4)='1' or
                             (FLUSH='0' and NEED((rr_next+offset) mod 4)='1' and ENABLE='1' and fault_i='0')) then
                            pick := (rr_next+offset) mod 4; found := true;
                        end if;
                    end loop;
                    if found then held_owner<=pick; held_tag<=std_logic_vector(next_tag); phase<=OFFER; end if;
                when OFFER =>
                    if FLUSH='1' and committed_write(held_owner)='0' then phase<=IDLE;
                    elsif req_v='1' and REQ_READY='1' then
                        phase<=INFLIGHT; next_tag<=next_tag+1; rr_next<=(held_owner+1) mod 4;
                    end if;
                when INFLIGHT => null;
            end case;
            if RSP_VALID='1' then
                if matched='1' then
                    phase<=IDLE;
                    if RSP_ERROR='1' then protocol_fault<='1'; end if;
                    if committed_write(held_owner)='1' or
                        (FLUSH='0' and NEED(held_owner)='1' and dead(held_owner)='0') then
                        data(held_owner)<=RSP_DATA;
                        errors(held_owner)<=RSP_ERROR;
                        if RETIRE(held_owner)='0' or
                            (ENABLE='0' and committed_write(held_owner)='0') then
                            done(held_owner)<='1';
                        end if;
                    else have(held_owner)<='0'; done(held_owner)<='0'; end if;
                else protocol_fault<='1'; end if;
            end if;
        end if;
    end process;
end architecture;
