library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_sa1_rom_bridge is end;
architecture test of tb_sa1_rom_bridge is
    signal clk : std_logic := '0';
    signal enable : std_logic := '1';
    signal flush : std_logic := '1';
    signal hard_reset_n : std_logic := '1';
    signal ack, fault : std_logic;
    signal epoch : std_logic_vector(7 downto 0) := x"00";
    signal need, retire, ready, bytes : std_logic_vector(3 downto 0) := (others=>'0');
    signal addrs : std_logic_vector(91 downto 0) := (others=>'0');
    signal words : std_logic_vector(63 downto 0);
    signal subtype_in : std_logic_vector(1 downto 0) := "00";
    signal qv, qr, pv, pr, pe : std_logic := '0';
    signal qa : std_logic_vector(22 downto 0);
    signal qo, qs, po : std_logic_vector(1 downto 0) := "00";
    signal qt, qe, pt, px : std_logic_vector(7 downto 0) := x"00";
    signal pd : std_logic_vector(15 downto 0) := x"FFFF";
begin
    clk<=not clk after 5 ns;
    dut: entity work.SA1RomBridge port map(CLK=>clk,HARD_RESET_N=>hard_reset_n,ENABLE=>enable,FLUSH=>flush,EPOCH=>epoch,
        FLUSH_ACK=>ack,NEED=>need,RETIRE=>retire,ADDRS=>addrs,SNES_OWNER=>subtype_in,
        READY=>ready,BYTES=>bytes,WORDS=>words,REQ_VALID=>qv,REQ_READY=>qr,REQ_ADDR=>qa,
        REQ_OWNER=>qo,REQ_SNES_OWNER=>qs,REQ_TAG=>qt,REQ_EPOCH=>qe,
        RSP_VALID=>pv,RSP_READY=>pr,RSP_OWNER=>po,RSP_TAG=>pt,RSP_EPOCH=>px,
        RSP_DATA=>pd,RSP_ERROR=>pe,FAULT=>fault);
    process
        variable owner : std_logic_vector(1 downto 0);
        variable tag, generation : std_logic_vector(7 downto 0);
        variable address : std_logic_vector(22 downto 0);
        variable seen : std_logic_vector(3 downto 0);
        procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure accept_request(expected : integer) is
        begin
            wait for 1 ns;
            assert qv='1' and to_integer(unsigned(qo))=expected report "unexpected request owner" severity failure;
            owner:=qo; tag:=qt; generation:=qe; address:=qa;
            qr<='1'; tick; qr<='0';
            assert ack='0' report "accepted transaction did not hold drain barrier" severity failure;
        end;
        procedure response(value : std_logic_vector(15 downto 0)) is
        begin
            po<=owner; pt<=tag; px<=generation; pd<=value; pv<='1'; wait for 1 ns;
            assert pr='1' report "response cannot drain" severity failure;
            tick; pv<='0'; wait for 1 ns;
        end;
        procedure consume(i : integer) is
        begin
            assert ready(i)='1' report "missing owner completion" severity failure;
            retire(i)<='1'; tick; retire(i)<='0'; need(i)<='0'; tick;
            assert ready(i)='0' report "duplicate completion after retire" severity failure;
        end;
    begin
        tick; flush<='0'; tick;
        -- Offer locks bank-mapped address, lane, subtype and generation while
        -- arbitration backpressures acceptance. Later input changes are legal.
        need(0)<='1'; addrs(22 downto 0)<=std_logic_vector(to_unsigned(16#1FFFFF#,23)); subtype_in<="10";
        tick;
        assert qv='1' and qa=std_logic_vector(to_unsigned(16#1FFFFE#,23)) severity failure;
        addrs(22 downto 0)<=std_logic_vector(to_unsigned(16#600000#,23)); subtype_in<="01"; epoch<=x"A5";
        for n in 1 to 17 loop
            tick;
            assert qa=std_logic_vector(to_unsigned(16#1FFFFE#,23)) and qs="10" and qe=x"00"
                report "offered request retargeted by bank/subowner/epoch change" severity failure;
        end loop;
        accept_request(0);
        for n in 1 to 13 loop tick; assert ready="0000" report "early ready" severity failure; end loop;
        response(x"1234");
        assert words(15 downto 0)=x"1234" and bytes(0)='1' report "lost captured byte lane" severity failure;
        for n in 1 to 9 loop tick; assert ready(0)='1' report "response not retained" severity failure; end loop;
        consume(0);
        -- Local cancellation cannot withdraw an already offered token. It is
        -- drained without delivery even if the same owner quickly starts over.
        need(1)<='1'; addrs(45 downto 23)<=std_logic_vector(to_unsigned(16#123457#,23)); tick;
        need(1)<='0'; enable<='0'; tick;
        assert qv='1' and qa=std_logic_vector(to_unsigned(16#123456#,23))
            report "local cancel/ENABLE withdrew locked request" severity failure;
        need(1)<='1'; enable<='1'; addrs(45 downto 23)<=std_logic_vector(to_unsigned(16#234568#,23)); tick;
        accept_request(1); response(x"DEAD");
        assert ready(1)='0' report "cancelled offered token revived for a new read" severity failure;
        tick; accept_request(1);
        assert address=std_logic_vector(to_unsigned(16#234568#,23)) severity failure;
        response(x"BEEF"); consume(1);
        -- Repeated identical byte addresses are distinct transfers, including
        -- tag rollover; no low pulse of a legacy ROM_OE is needed.
        for n in 0 to 269 loop
            need(1)<='1'; addrs(45 downto 23)<=std_logic_vector(to_unsigned(16#7FFFFF#,23));
            accept_request(1);
            if n mod 3=0 then tick; end if;
            response(std_logic_vector(to_unsigned(n,16)));
            assert words(31 downto 16)=std_logic_vector(to_unsigned(n,16)) and bytes(1)='1' severity failure;
            consume(1);
        end loop;
        -- All four slots capture independently before owner arbitration. Input
        -- addresses may change afterwards without stealing a prior slot.
        need<="1111"; epoch<=x"B2";
        for i in 0 to 3 loop addrs(i*23+22 downto i*23)<=std_logic_vector(to_unsigned(i*16#100000#+16#3FF#,23)); end loop;
        tick;
        addrs<=(others=>'0'); seen:="0000";
        for n in 0 to 3 loop
            wait for 1 ns;
            owner:=qo;
            accept_request(to_integer(unsigned(owner)));
            assert address=std_logic_vector(to_unsigned(to_integer(unsigned(owner))*16#100000#+16#3FE#,23))
                report "competing owner changed captured address" severity failure;
            for d in 1 to n*5+1 loop tick; end loop;
            response(x"CAFE"); seen(to_integer(unsigned(owner))):='1';
        end loop;
        assert seen="1111" and ready="1111" report "owner starvation/lost buffered completion" severity failure;
        retire<="1111"; tick; retire<="0000"; need<="0000"; tick;
        -- Wrong owner/tag/epoch never releases the accepted token.
        need(2)<='1'; accept_request(2);
        po<=owner; pt<=std_logic_vector(unsigned(tag)+1); px<=generation; pv<='1'; tick; pv<='0';
        assert ready(2)='0' and ack='0' report "stale tag released owner" severity failure;
        po<=std_logic_vector(unsigned(owner)+1); pt<=tag; px<=generation; pv<='1'; tick; pv<='0';
        assert ready(2)='0' and ack='0' report "wrong owner released owner" severity failure;
        po<=owner; pt<=tag; px<=not generation; pv<='1'; tick; pv<='0';
        assert ready(2)='0' and ack='0' report "stale epoch released owner" severity failure;
        response(x"5678"); consume(2);
        -- Accepted work survives many short reset/mount pulses and epoch wrap.
        need(3)<='1'; accept_request(3);
        for n in 0 to 260 loop
            flush<='1'; epoch<=std_logic_vector(to_unsigned(n mod 256,8)); tick;
            assert ack='0' and qv='0' and ready="0000" report "flush did not await physical drain" severity failure;
            flush<='0'; tick;
            assert ack='0' and qv='0' and ready="0000" report "quick reset reused live transaction" severity failure;
        end loop;
        response(x"DEAD");
        assert ready(3)='0' and ack='1' report "cancelled data leaked after drain" severity failure;
        tick; accept_request(3); response(x"BEEF");
        assert words(63 downto 48)=x"BEEF" severity failure; consume(3);
        -- Cancelling an unaccepted offer is immediate and has no physical work.
        need(1)<='1'; tick; flush<='1'; tick;
        assert ack='1' and qv='0' and ready="0000" severity failure;
        need<="0000"; flush<='0'; tick;
        -- A returned memory error is fail-closed, not stale-data retirement.
        need(2)<='1'; accept_request(2); pe<='1'; response(x"BAD0"); pe<='0';
        assert ready(2)='0' and fault='1' report "error response retired" severity failure;
        for n in 1 to 5 loop tick; assert qv='0' and ready(2)='0' severity failure; end loop;
        flush<='1'; tick; need<="0000"; flush<='0'; tick;
        assert fault='0' severity failure;
        -- Coordinated PLL/physical reset is different: both transport and
        -- engine forget the old token, and no old reply is expected afterwards.
        need(2)<='1'; accept_request(2); hard_reset_n<='0'; tick;
        assert ack='1' and qv='0' and ready="0000" report "hard reset failed to clear transport" severity failure;
        hard_reset_n<='1'; tick; accept_request(2); response(x"7788"); consume(2);
        report "PASS SA1 ROM bridge: immutable slots, 270 same-address reads, four owners, identity rejection, 261 reset/epoch wraps, error fail-closed";
        stop;
    end process;
end architecture;
