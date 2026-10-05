library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Four logical ROM consumers and one physical transaction. This transport
-- deliberately does NOT reset with chip RST_N: FLUSH cancels delivery, while
-- an accepted transaction and its identity survive until its reply drains.
entity SA1RomBridge is
    generic (P1 : integer range 0 to 3 := 3;
             P2 : integer range 0 to 3 := 2;
             P3 : integer range 0 to 3 := 1);
    port (
        CLK, ENABLE, FLUSH : in std_logic;
        HARD_RESET_N : in std_logic := '1';
        EPOCH : in std_logic_vector(7 downto 0);
        FLUSH_ACK : out std_logic;
        NEED, RETIRE : in std_logic_vector(3 downto 0);
        ADDRS : in std_logic_vector(91 downto 0);
        SNES_OWNER : in std_logic_vector(1 downto 0);
        READY, BYTES : out std_logic_vector(3 downto 0);
        WORDS : out std_logic_vector(63 downto 0);
        REQ_VALID : out std_logic;
        REQ_READY : in std_logic;
        REQ_ADDR : out std_logic_vector(22 downto 0);
        REQ_OWNER, REQ_SNES_OWNER : out std_logic_vector(1 downto 0);
        REQ_TAG, REQ_EPOCH : out std_logic_vector(7 downto 0);
        RSP_VALID : in std_logic;
        RSP_READY : out std_logic;
        RSP_OWNER : in std_logic_vector(1 downto 0);
        RSP_TAG, RSP_EPOCH : in std_logic_vector(7 downto 0);
        RSP_DATA : in std_logic_vector(15 downto 0);
        RSP_ERROR : in std_logic;
        FAULT : out std_logic
    );
end entity;

architecture rtl of SA1RomBridge is
    type addr_array is array (0 to 3) of std_logic_vector(22 downto 0);
    type data_array is array (0 to 3) of std_logic_vector(15 downto 0);
    type epoch_array is array (0 to 3) of std_logic_vector(7 downto 0);
    type priority_array is array (0 to 3) of integer range 0 to 3;
    constant PRIORITY : priority_array := (0, P1, P2, P3);
    type phase_type is (IDLE, OFFER, INFLIGHT);
    signal phase : phase_type := IDLE;
    signal have, done, dead, errors : std_logic_vector(3 downto 0) := (others=>'0');
    signal addresses : addr_array := (others=>(others=>'0'));
    signal data : data_array := (others=>(others=>'1'));
    signal epochs : epoch_array := (others=>(others=>'0'));
    signal snes_subowner : std_logic_vector(1 downto 0) := "00";
    signal held_owner : integer range 0 to 3 := 0;
    signal held_addr : std_logic_vector(22 downto 0) := (others=>'0');
    signal held_subowner : std_logic_vector(1 downto 0) := "00";
    signal held_tag, held_epoch : std_logic_vector(7 downto 0) := (others=>'0');
    signal next_tag : unsigned(7 downto 0) := (others=>'0');
    signal selected : integer range 0 to 3 := 0;
    signal offered : std_logic;
    signal offer_addr : std_logic_vector(22 downto 0);
    signal offer_epoch : std_logic_vector(7 downto 0);
    signal offer_subowner : std_logic_vector(1 downto 0);
    signal matched : std_logic;
    signal protocol_fault : std_logic := '0';
begin
    assert P1/=0 and P2/=0 and P3/=0 and P1/=P2 and P1/=P3 and P2/=P3
        report "SA1RomBridge priority must be a permutation of owners 1,2,3" severity failure;
    -- The first offer bypasses the slot register. At the first sampling edge it
    -- is either accepted or locked, including mapping/byte/subowner/epoch.
    -- This saves a sys-clock bubble without weakening valid/ready stability.
    process(phase, held_owner, NEED, dead, have, done, ENABLE, FLUSH,
            held_addr, held_epoch, held_subowner, addresses, epochs,
            snes_subowner, ADDRS, EPOCH, SNES_OWNER, HARD_RESET_N)
        variable pick : integer range 0 to 3;
        variable found : boolean;
    begin
        pick := held_owner;
        found := false;
        if phase=OFFER then
            found := true; -- An offered token stays valid until acceptance or global flush.
        elsif phase=IDLE then
            for p in 0 to 3 loop
                if not found and NEED(PRIORITY(p))='1' and
                    (have(PRIORITY(p))='0' or
                     (done(PRIORITY(p))='0' and dead(PRIORITY(p))='0')) then
                    pick := PRIORITY(p);
                    found := true;
                end if;
            end loop;
        end if;
        selected <= pick;
        offered <= '0';
        if found and FLUSH='0' and HARD_RESET_N='1' and (ENABLE='1' or phase=OFFER) then offered <= '1'; end if;
        if phase=OFFER then
            offer_addr <= held_addr;
            offer_epoch <= held_epoch;
            offer_subowner <= held_subowner;
        elsif have(pick)='1' then
            offer_addr <= addresses(pick);
            offer_epoch <= epochs(pick);
            offer_subowner <= snes_subowner;
        else
            -- Fixed slices preserve the same combinational first-offer bypass.
            -- A variable bit index here infers a multiply/barrel mux in Quartus,
            -- despite pick having only four legal owner values.
            case pick is
                when 0 => offer_addr <= ADDRS(22 downto 0);
                when 1 => offer_addr <= ADDRS(45 downto 23);
                when 2 => offer_addr <= ADDRS(68 downto 46);
                when 3 => offer_addr <= ADDRS(91 downto 69);
            end case;
            offer_epoch <= EPOCH;
            offer_subowner <= SNES_OWNER;
        end if;
    end process;
    REQ_VALID <= offered;
    REQ_ADDR <= offer_addr(22 downto 1) & '0';
    REQ_OWNER <= std_logic_vector(to_unsigned(selected, 2));
    REQ_SNES_OWNER <= offer_subowner;
    REQ_TAG <= held_tag when phase=OFFER else std_logic_vector(next_tag);
    REQ_EPOCH <= offer_epoch;
    matched <= '1' when phase=INFLIGHT and RSP_VALID='1' and
        RSP_OWNER=std_logic_vector(to_unsigned(held_owner, 2)) and
        RSP_TAG=held_tag and RSP_EPOCH=held_epoch else '0';
    -- Drain even cancelled replies. Identity mismatches never release a slot.
    RSP_READY <= '1';
    FLUSH_ACK <= '0' when phase=INFLIGHT else '1';
    FAULT <= protocol_fault or errors(0) or errors(1) or errors(2) or errors(3);

    process(have, dead, NEED, FLUSH, done, errors, addresses, data,
            matched, held_owner, RSP_ERROR, RSP_DATA)
    begin
        READY <= (others=>'0');
        for i in 0 to 3 loop
            BYTES(i) <= addresses(i)(0);
            WORDS(i*16+15 downto i*16) <= data(i);
            if have(i)='1' and dead(i)='0' and NEED(i)='1' and FLUSH='0' then
                READY(i) <= done(i) and not errors(i);
                -- Completion forwarding permits retirement on the first
                -- original EN edge for which a matching response is valid.
                if matched='1' and held_owner=i then
                    READY(i) <= not RSP_ERROR;
                    WORDS(i*16+15 downto i*16) <= RSP_DATA;
                end if;
            end if;
        end loop;
    end process;

    process(CLK, HARD_RESET_N)
    begin
        if HARD_RESET_N='0' then
            -- Only the coordinated physical-engine reset may discard a live
            -- token. Mount/CPU resets use FLUSH and must await its reply.
            phase<=IDLE; have<=(others=>'0'); done<=(others=>'0');
            dead<=(others=>'0'); errors<=(others=>'0');
            addresses<=(others=>(others=>'0')); data<=(others=>(others=>'1'));
            epochs<=(others=>(others=>'0')); snes_subowner<="00";
            held_owner<=0; held_addr<=(others=>'0'); held_subowner<="00";
            held_tag<=(others=>'0'); held_epoch<=(others=>'0');
            next_tag<=(others=>'0'); protocol_fault<='0';
        elsif rising_edge(CLK) then
            for i in 0 to 3 loop
                if FLUSH='1' or NEED(i)='0' then
                    dead(i) <= '1';
                    done(i) <= '0';
                    errors(i) <= '0';
                    if phase=IDLE or held_owner/=i or (FLUSH='1' and phase=OFFER) then have(i)<='0'; end if;
                elsif RETIRE(i)='1' then
                    have(i) <= '0';
                    done(i) <= '0';
                elsif ENABLE='1' and have(i)='0' and
                    not (phase/=IDLE and held_owner=i) then
                    have(i) <= '1';
                    done(i) <= '0';
                    dead(i) <= '0';
                    errors(i) <= '0';
                    addresses(i) <= ADDRS(i*23+22 downto i*23);
                    epochs(i) <= EPOCH;
                    if i=0 then snes_subowner<=SNES_OWNER; end if;
                end if;
            end loop;
            if FLUSH='1' then
                protocol_fault <= '0';
                if phase=OFFER then phase<=IDLE; end if;
            end if;
            if offered='1' then
                held_owner <= selected;
                held_addr <= offer_addr;
                held_epoch <= offer_epoch;
                held_subowner <= offer_subowner;
                if phase=IDLE then held_tag<=std_logic_vector(next_tag); end if;
                if REQ_READY='1' then
                    phase <= INFLIGHT;
                    next_tag <= next_tag + 1;
                else
                    phase <= OFFER;
                end if;
            end if;
            if RSP_VALID='1' then
                if matched='1' then
                    phase <= IDLE;
                    if FLUSH='0' and dead(held_owner)='0' and NEED(held_owner)='1' then
                        data(held_owner) <= RSP_DATA;
                        errors(held_owner) <= RSP_ERROR;
                        if RETIRE(held_owner)='0' then done(held_owner)<='1'; end if;
                    else
                        have(held_owner) <= '0';
                        done(held_owner) <= '0';
                    end if;
                else
                    protocol_fault <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;
