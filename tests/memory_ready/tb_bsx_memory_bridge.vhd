library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_bsx_memory_bridge is end;
architecture test of tb_bsx_memory_bridge is
    signal clk : std_logic := '0';
    signal en, flush, reset_n : std_logic := '0';
    signal epoch : std_logic_vector(7 downto 0) := x"11";
    signal need, retire, writes, committed : std_logic_vector(3 downto 0) := (others=>'0');
    signal addrs : std_logic_vector(91 downto 0) := (others=>'0');
    signal wdatas, words : std_logic_vector(63 downto 0) := (others=>'0');
    signal wstrbs : std_logic_vector(7 downto 0) := (others=>'0');
    signal subowner : std_logic_vector(1 downto 0) := "10";
    signal ready, completed, bytes : std_logic_vector(3 downto 0);
    signal ack, fault, qv, qr, qw, drain, rv, rr, re, rw : std_logic := '0';
    signal qa : std_logic_vector(22 downto 0);
    signal qo, qs, ro : std_logic_vector(1 downto 0) := "00";
    signal qt, qe, rt, ep : std_logic_vector(7 downto 0) := x"00";
    signal qd, rd : std_logic_vector(15 downto 0) := x"0000";
    signal qb : std_logic_vector(1 downto 0);
    signal accepts : integer := 0;
begin
    clk <= not clk after 5 ns;
    dut: entity work.BSXMemoryBridge port map(
        CLK=>clk, ENABLE=>en, FLUSH=>flush, HARD_RESET_N=>reset_n, EPOCH=>epoch,
        NEED=>need, RETIRE=>retire, WRITES=>writes, COMMITTED=>committed,
        ADDRS=>addrs, WDATAS=>wdatas, WSTRBS=>wstrbs, SNES_OWNER=>subowner,
        READY=>ready, COMPLETED=>completed, BYTES=>bytes, WORDS=>words, FLUSH_ACK=>ack, FAULT=>fault,
        REQ_VALID=>qv, REQ_READY=>qr, REQ_ADDR=>qa, REQ_OWNER=>qo, REQ_SNES_OWNER=>qs,
        REQ_TAG=>qt, REQ_EPOCH=>qe, REQ_WRITE=>qw, REQ_DRAIN=>drain, REQ_WDATA=>qd, REQ_WSTRB=>qb,
        RSP_VALID=>rv, RSP_READY=>rr, RSP_OWNER=>ro, RSP_TAG=>rt, RSP_EPOCH=>ep,
        RSP_DATA=>rd, RSP_ERROR=>re, RSP_WRITE=>rw);
    process(clk)
    begin
        if rising_edge(clk) then
            if reset_n='0' then accepts<=0;
            elsif qv='1' and qr='1' then accepts<=accepts+1;end if;
        end if;
    end process;
    process
        procedure tick is begin wait until rising_edge(clk);wait for 1 ns;end;
        procedure ticks(n : natural) is begin for i in 1 to n loop tick;end loop;end;
        procedure reset_epoch is
        begin
            reset_n<='0';need<="0000";retire<="0000";writes<="0000";committed<="0000";
            qr<='0';rv<='0';re<='0';flush<='0';en<='1';epoch<=x"11";subowner<="10";
            ticks(2);reset_n<='1';tick;
        end;
        procedure set_slot(i : natural; a : natural; d : natural; b : std_logic_vector(1 downto 0);
                           wr : std_logic; commit : std_logic) is
        begin
            addrs(i*23+22 downto i*23)<=std_logic_vector(to_unsigned(a,23));
            wdatas(i*16+15 downto i*16)<=std_logic_vector(to_unsigned(d,16));
            wstrbs(i*2+1 downto i*2)<=b;writes(i)<=wr;committed(i)<=commit;need(i)<='1';
        end;
        procedure wait_offer(owner : natural) is
            variable n : natural := 0;
        begin
            wait for 1 ns;
            while qv/='1' and n<30 loop tick;n:=n+1;end loop;
            assert qv='1' and to_integer(unsigned(qo))=owner
                report "ARBITRATION expected offered owner "&integer'image(owner) severity failure;
        end;
        procedure accept_request is
        begin
            qr<='1';tick;qr<='0';wait for 1 ns;
            assert ack='0' report "DRAIN_ACK accepted request released early" severity failure;
        end;
        procedure drive_response(value : natural; err : std_logic := '0') is
        begin
            ro<=qo;rt<=qt;ep<=qe;rw<=qw;rd<=std_logic_vector(to_unsigned(value,16));re<=err;rv<='1';
            wait for 1 ns;
            assert rr='1' report "response channel blocked" severity failure;
        end;
        procedure finish_response is begin tick;rv<='0';re<='0';wait for 1 ns;end;
        procedure retire_slot(i : natural) is
        begin retire(i)<='1';tick;retire(i)<='0';need(i)<='0';tick;end;
        variable saved_a : std_logic_vector(22 downto 0);
        variable saved_t, saved_e : std_logic_vector(7 downto 0);
        variable old_count : integer;
    begin
        reset_epoch;
        set_slot(0,16#123#,16#cafe#,"10",'0','0');wait_offer(0);
        saved_a:=qa;saved_t:=qt;saved_e:=qe;
        assert qa=std_logic_vector(to_unsigned(16#122#,23)) and bytes(0)='1' and qs="10"
            and qd=x"cafe" and qb="10" report "PAYLOAD capture/lane failure" severity failure;
        -- ENABLE gates logical retirement, not a previously asserted offer.
        en<='0';subowner<="01";epoch<=x"99";addrs(22 downto 0)<=(others=>'1');
        wdatas(15 downto 0)<=x"dead";wstrbs(1 downto 0)<="01";writes(0)<='1';committed(0)<='1';
        ticks(4);
        assert qv='1' and qa=saved_a and qt=saved_t and qe=saved_e and qs="10" and qd=x"cafe" and qb="10" and qw='0' and drain='0'
            report "HELD_PAYLOAD changed under stall/ENABLE0" severity failure;
        accept_request;retire(0)<='1';drive_response(16#1357#);finish_response;
        retire(0)<='0';ticks(3);
        assert ready(0)='1' and words(15 downto 0)=x"1357"
            report "ENABLE_DISABLED incorrectly retired result" severity failure;
        en<='1';retire_slot(0);

        -- NEED withdrawal cannot revoke a held valid offer. It marks the token
        -- dead; neither late NEED reassertion nor same address resurrects it.
        reset_epoch;set_slot(0,16#200#,0,"00",'0','0');wait_offer(0);saved_t:=qt;
        need(0)<='0';en<='0';ticks(2);
        assert qv='1' and qa=std_logic_vector(to_unsigned(16#200#,23))
            report "HELD_VALID was revoked by NEED/ENABLE" severity failure;
        accept_request;need(0)<='1';en<='1';ticks(2);
        drive_response(16#bad0#);
        assert ready(0)='0' and completed(0)='0' report "DEAD_TOKEN resurrected by NEED" severity failure;
        finish_response;wait_offer(0);
        assert unsigned(qt)=unsigned(saved_t)+1 report "TAG_SEQUENCE same-address reuse did not advance" severity failure;
        accept_request;drive_response(16#2468#);
        assert ready(0)='1' and words(15 downto 0)=x"2468" report "matching response not forwarded" severity failure;
        finish_response;retire_slot(0);

        -- Cancellation after acceptance also remains dead if NEED comes back.
        reset_epoch;set_slot(0,16#222#,0,"00",'0','0');wait_offer(0);accept_request;
        need(0)<='0';tick;need(0)<='1';ticks(2);drive_response(16#bad1#);
        assert ready(0)='0' and completed(0)='0' report "DEAD_INFLIGHT token resurrected" severity failure;
        finish_response;wait_offer(0);accept_request;drive_response(16#5aa5#);finish_response;retire_slot(0);

        -- FLUSH explicitly cancels an ordinary unaccepted offer.
        reset_epoch;set_slot(0,16#400#,0,"00",'0','0');wait_offer(0);old_count:=accepts;
        flush<='1';qr<='1';wait for 1 ns;
        assert qv='0' and ack='1' report "FLUSH_CANCEL offered read was not canceled" severity failure;
        tick;need<="0000";qr<='0';ticks(2);
        assert accepts=old_count and fault='0' report "FLUSH_CANCEL read accepted during cancellation" severity failure;
        flush<='0';tick;

        -- Accepted transactions drain; every identity component is mandatory.
        reset_epoch;set_slot(1,16#600#,16#c0de#,"01",'1','0');wait_offer(1);accept_request;
        saved_t:=qt;saved_e:=qe;retire(1)<='1';
        drive_response(1);ro<="00";wait for 1 ns;
        assert ready="0000" and completed="0000" report "IDENTITY_OWNER retired wrong owner" severity failure;
        finish_response;
        drive_response(2);rt<=std_logic_vector(unsigned(saved_t)+1);wait for 1 ns;
        assert ready="0000" and completed="0000" report "IDENTITY_TAG retired wrong tag" severity failure;
        finish_response;
        drive_response(3);ep<=x"77";wait for 1 ns;
        assert ready="0000" and completed="0000" report "IDENTITY_EPOCH retired wrong epoch" severity failure;
        finish_response;
        drive_response(4);rw<='0';wait for 1 ns;
        assert ready="0000" and completed="0000" report "IDENTITY_OPERATION retired read as write" severity failure;
        finish_response;
        assert fault='1' and ack='0' report "IDENTITY wrong response lost accepted token" severity failure;
        flush<='1';epoch<=x"22";need(1)<='0';retire(1)<='0';tick;
        assert ack='0' report "EPOCH_DRAIN acknowledged before old response" severity failure;
        drive_response(16#aaaa#);
        assert ready="0000" and completed="0000" report "FLUSH_DRAIN exposed canceled result" severity failure;
        finish_response;
        assert ack='1' report "EPOCH_DRAIN failed to drain old identity" severity failure;
        tick;assert fault='0' report "controlled drained flush did not recover protocol fault" severity failure;
        flush<='0';tick;

        -- Committed owner2 can arrive before the bridge captures it, even when
        -- disabled and already flushing. It blocks ACK immediately and drains.
        reset_epoch;en<='0';flush<='1';epoch<=x"55";
        set_slot(2,16#801#,16#aaaa#,"10",'1','1');wait for 1 ns;
        assert ack='0' report "COMMITTED pending-before-capture released flush" severity failure;
        wait_offer(2);saved_t:=qt;
        assert drain='1' and qw='1' and qa=std_logic_vector(to_unsigned(16#800#,23)) and qe=x"55"
            report "COMMITTED lost drain identity" severity failure;
        need(2)<='0';committed(2)<='0';epoch<=x"66";ticks(3);
        assert qv='1' and drain='1' and qe=x"55" and qt=saved_t and ack='0'
            report "COMMITTED canceled before CDC admission" severity failure;
        accept_request;drive_response(16#bbbb#);
        assert completed(2)='1' and ready(2)='0' report "COMMITTED flush completion semantics" severity failure;
        retire(2)<='1';finish_response;retire(2)<='0';tick;
        assert ack='1' and fault='0' report "COMMITTED failed to drain/retire" severity failure;

        -- A new committed write takes over after FLUSH cancels an ordinary OFFER.
        reset_epoch;set_slot(0,16#100#,0,"00",'0','0');wait_offer(0);
        flush<='1';en<='0';need(0)<='0';set_slot(2,16#903#,16#ddcc#,"10",'1','1');
        wait for 1 ns;assert qv='0' and ack='0' report "COMMITTED handover barrier" severity failure;
        tick;wait_offer(2);accept_request;drive_response(0);retire(2)<='1';finish_response;
        need(2)<='0';retire(2)<='0';ticks(2);
        assert accepts=1 and ack='1' report "COMMITTED flush handover accepted canceled read" severity failure;

        -- Errors cannot silently turn into success when the slot is recycled.
        -- Irrevocable posted work still drains while another error holds FAULT.
        reset_epoch;set_slot(1,16#1000#,16#eeee#,"11",'1','0');wait_offer(1);accept_request;
        drive_response(0,'1');
        assert completed(1)='1' and ready(1)='0' report "WRITE_ERROR presented success" severity failure;
        finish_response;retire_slot(1);ticks(3);
        assert fault='1' report "ERROR_STICKY disappeared after NEED/RETIRE" severity failure;
        en<='0';set_slot(2,16#1002#,16#ffff#,"11",'1','1');wait_offer(2);
        assert drain='1' report "COMMITTED blocked behind existing error" severity failure;
        accept_request;drive_response(0);retire(2)<='1';finish_response;retire(2)<='0';need(2)<='0';ticks(2);
        assert fault='1' report "ERROR_STICKY cleared by unrelated successful drain" severity failure;
        flush<='1';ticks(2);assert fault='0' and ack='1' report "ERROR_STICKY controlled recovery failed" severity failure;

        -- Posted-write COMPLETED reports an outcome, never successful READY
        -- for an error. Recycling that irrevocable slot must retain FAULT.
        reset_epoch;set_slot(2,16#1110#,16#abab#,"11",'1','1');wait_offer(2);accept_request;
        retire(2)<='1';drive_response(0,'1');
        assert completed(2)='1' and ready(2)='0' report "POSTED_ERROR presented success" severity failure;
        finish_response;need(2)<='0';retire(2)<='0';ticks(3);
        assert fault='1' and ack='1' report "POSTED_ERROR disappeared after completion" severity failure;
        flush<='1';ticks(2);assert fault='0' report "POSTED_ERROR controlled recovery failed" severity failure;

        -- All four slots arbitrate round-robin and accept same-edge responses.
        reset_epoch;
        for i in 0 to 3 loop set_slot(i,16#2000#+i,16#5500#+i,"11",'0','0');end loop;
        writes<="0110";committed<="0100";
        for i in 0 to 3 loop
            wait_offer(i);assert to_integer(unsigned(qt))=i report "TAG_SEQUENCE arbitration" severity failure;
            qr<='1';drive_response(16#6000#+i);retire(i)<='1';wait for 1 ns;
            assert ready(i)='1' and completed(i)='1' and words(i*16+15 downto i*16)=std_logic_vector(to_unsigned(16#6000#+i,16))
                report "IMMEDIATE response on accept edge lost" severity failure;
            finish_response;qr<='0';retire(i)<='0';need(i)<='0';tick;
            assert fault='0' report "IMMEDIATE response faulted" severity failure;
        end loop;
        assert accepts=4 report "round-robin duplicate/lost acceptance" severity failure;

        -- Unretired results occupy independent slots without blocking the
        -- other owners; their payloads remain intact while new responses arrive.
        reset_epoch;
        for i in 0 to 3 loop set_slot(i,16#2200#+i,0,"00",'0','0');end loop;
        for i in 0 to 3 loop
            wait_offer(i);accept_request;ticks(3);drive_response(16#7000#+i);finish_response;
            for j in 0 to i loop
                assert ready(j)='1' and words(j*16+15 downto j*16)=std_logic_vector(to_unsigned(16#7000#+j,16))
                    report "RESULT_SLOTS overwritten unretired owner" severity failure;
            end loop;
        end loop;
        ticks(4);assert ready="1111" and qv='0' and accepts=4
            report "RESULT_SLOTS duplicate request or missing retained result" severity failure;
        retire<="1111";tick;retire<="0000";need<="0000";tick;

        -- Same address is always a new operation, through tag wrap and epochs.
        reset_epoch;
        for i in 0 to 259 loop
            epoch<=std_logic_vector(to_unsigned(i/64,8));
            set_slot(0,16#3333#,0,"00",'0','0');wait_offer(0);
            assert to_integer(unsigned(qt))=(i mod 256) and to_integer(unsigned(qe))=i/64
                report "TAG_WRAP or epoch capture alias" severity failure;
            qr<='1';drive_response(i);retire(0)<='1';wait for 1 ns;
            assert words(15 downto 0)=std_logic_vector(to_unsigned(i,16)) and ready(0)='1'
                report "TAG_WRAP same address returned stale result" severity failure;
            finish_response;qr<='0';retire(0)<='0';need(0)<='0';tick;
        end loop;
        assert accepts=260 and fault='0' report "TAG_WRAP count/fault" severity failure;

        -- Only hard reset may discard a committed accepted operation.
        reset_epoch;set_slot(2,16#4000#,16#ab12#,"11",'1','1');wait_offer(2);accept_request;
        flush<='1';en<='0';ticks(3);assert ack='0' report "HARD_RESET committed drained without response" severity failure;
        reset_n<='0';need<="0000";committed<="0000";wait for 1 ns;
        assert qv='0' and ready="0000" and completed="0000" and ack='1' and fault='0'
            report "HARD_RESET failed to invalidate transport" severity failure;
        tick;reset_n<='1';ticks(3);assert qv='0' report "HARD_RESET replayed old committed write" severity failure;
        report "PASS BSXMemoryBridge: held offers, cancellation/drain, ENABLE, four owners, identity/operation, immediate responses, committed flush/error, tag wrap, epochs, hard reset" severity note;
        finish;
    end process;
    process begin wait for 100 us;assert false report "timeout" severity failure;end process;
end architecture;
