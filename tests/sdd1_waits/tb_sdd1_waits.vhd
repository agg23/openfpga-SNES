library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_sdd1_waits is
    generic (CASES : positive := 64; OUTPUT_BYTES : positive := 256; MAX_DELAY : natural := 257;
        ADDRESS_MASK : natural := 16#7FFFFF#; BANK_C : natural := 0; BANK_D : natural := 1; STREAM_KIND : natural := 0);
end;
architecture test of tb_sdd1_waits is
    signal clk : std_logic := '0';
    signal rst, hard, en : std_logic := '0';
    signal ca : std_logic_vector(23 downto 0) := (others=>'0');
    signal di, dout : std_logic_vector(7 downto 0) := (others=>'0');
    signal rd, wr, romsel : std_logic := '1';
    signal ce_r, ce_f, intent, retire, waiting : std_logic := '0';
    signal flush, flush_ack, fault : std_logic := '0';
    signal epoch : std_logic_vector(7 downto 0) := x"31";
    signal req_v, req_r, rsp_v, rsp_r, rsp_error : std_logic := '0';
    signal req_a : std_logic_vector(22 downto 0);
    signal req_o, req_so, rsp_o : std_logic_vector(1 downto 0) := "00";
    signal req_t, req_e, rsp_t, rsp_e : std_logic_vector(7 downto 0) := (others=>'0');
    signal rsp_d : std_logic_vector(15 downto 0) := (others=>'0');
    signal fixture : natural := 0;
    signal start_addr : natural := 16#C00FFF#;
    signal cycles, responses, snes_responses, dec_responses : natural := 0;
    signal force_delay, inject_error : std_logic := '0';
    signal inject_bad : natural range 0 to 3 := 0;
    signal bad_reply : std_logic := '0';
    signal accepted, in_flight : std_logic := '0';
    signal brst, brun, binit, breq, bplane, bdone : std_logic := '0';
    signal bdo, bdata : std_logic_vector(15 downto 0);
    signal bheader : std_logic_vector(3 downto 0);
    signal bindex : natural := 0;
    function physical(a : natural) return natural is
        variable bank, mapped : natural;
    begin
        case (a/16#100000#) mod 4 is
            when 0 => bank:=BANK_C;
            when 1 => bank:=BANK_D;
            when 2 => bank:=2;
            when others => bank:=3;
        end case;
        mapped := (bank*16#100000#+(a mod 16#100000#)) mod 16#800000#;
        return to_integer(to_unsigned(mapped,23) and to_unsigned(ADDRESS_MASK,23));
    end;
    function mem(a : natural; f : natural; start : natural) return std_logic_vector is
        variable v : natural;
    begin
        v := (a*73 + (a/11)*19 + (a/257)*7 + 37*f) mod 256;
        if STREAM_KIND=1 then v:=0; end if;
        if a=physical(start) then v := (f mod 16)*16 + v mod 16; end if;
        return std_logic_vector(to_unsigned(v,8));
    end;
begin
    clk <= not clk after 5 ns;
    bheader <= std_logic_vector(to_unsigned(fixture mod 16,4));
    bdata <= mem(physical(start_addr+bindex),fixture,start_addr) &
             mem(physical(start_addr+bindex+1),fixture,start_addr);
    baseline: entity work.SDD1_Decoder_Baseline
        port map(RST_N=>brst, CLK=>clk, ENABLE=>'1', INIT_SIZE=>std_logic_vector(to_unsigned(OUTPUT_BYTES,16)),
            IN_DATA=>bdata, HEADER=>bheader, INIT=>binit, RUN=>brun, DATA_REQ=>breq,
            DO=>bdo, PLANE_DONE=>bplane, DONE=>bdone);
    process(clk,brst)
    begin
        if brst='0' then bindex<=0;
        elsif rising_edge(clk) then
            if binit='1' then bindex<=0;
            elsif breq='1' then bindex<=bindex+1; end if;
        end if;
    end process;
    dut: entity work.SDD1Map
        generic map(ROM_HANDSHAKE=>true)
        port map(MCLK=>clk,RST_N=>rst,ENABLE=>en,CA=>ca,DI=>di,DO=>dout,
            CPURD_N=>rd,CPUWR_N=>wr,PA=>x"00",PARD_N=>'1',PAWR_N=>'1',ROMSEL_N=>romsel,RAMSEL_N=>'1',
            SYSCLKF_CE=>ce_f,SYSCLKR_CE=>ce_r,REFRESH=>'0',IRQ_N=>open,
            ROM_ADDR=>open,ROM_Q=>x"DEAD",ROM_CE_N=>open,ROM_OE_N=>open,ROM_WORD=>open,
            BSRAM_ADDR=>open,BSRAM_D=>open,BSRAM_Q=>x"00",BSRAM_CE_N=>open,BSRAM_OE_N=>open,BSRAM_WE_N=>open,
            MAP_ACTIVE=>open,MAP_CTRL=>x"50",ROM_MASK=>std_logic_vector(to_unsigned(ADDRESS_MASK,24)),BSRAM_MASK=>x"000000",
            ROM_HARD_RESET_N=>hard,ROM_EPOCH=>epoch,ROM_FLUSH=>flush,ROM_FLUSH_ACK=>flush_ack,ROM_FAULT=>fault,
            ROM_SNES_READ_INTENT=>intent,ROM_SNES_OWNER=>"01",ROM_SNES_RETIRE=>retire,ROM_SNES_WAIT=>waiting,
            ROM_REQ_VALID=>req_v,ROM_REQ_READY=>req_r,ROM_REQ_ADDR=>req_a,ROM_REQ_OWNER=>req_o,
            ROM_REQ_SNES_OWNER=>req_so,ROM_REQ_TAG=>req_t,ROM_REQ_EPOCH=>req_e,
            ROM_RSP_VALID=>rsp_v,ROM_RSP_READY=>rsp_r,ROM_RSP_DATA=>rsp_d,ROM_RSP_OWNER=>rsp_o,
            ROM_RSP_TAG=>rsp_t,ROM_RSP_EPOCH=>rsp_e,ROM_RSP_ERROR=>rsp_error);
    -- Registered response model with request backpressure, long starvation,
    -- and optional corrupt token before the matching reply.
    process(clk,hard)
        variable delay : natural := 0;
        variable a : natural := 0;
        variable owner : std_logic_vector(1 downto 0);
        variable tag, ep : std_logic_vector(7 downto 0);
        variable bad_sent : boolean := false;
        variable held : boolean := false;
        variable held_payload : std_logic_vector(42 downto 0);
    begin
        if hard='0' then
            req_r<='0'; rsp_v<='0'; in_flight<='0'; accepted<='0'; delay:=0; held:=false;
        elsif rising_edge(clk) then
            accepted<='0'; req_r<='0';
            if held and flush='0' and rst='1' then
                assert req_v='1' and (req_a & req_o & req_so & req_t & req_e)=held_payload
                    report "offered ROM token changed under backpressure" severity failure;
            end if;
            held := req_v='1' and req_r='0' and flush='0' and rst='1';
            held_payload := req_a & req_o & req_so & req_t & req_e;
            if in_flight='0' and rsp_v='0' and cycles mod 7/=1 and cycles mod 7/=2 then req_r<='1'; end if;
            if req_v='1' and req_r='1' then
                assert in_flight='0' report "overlapping physical transactions" severity failure;
                a:=to_integer(unsigned(req_a)); owner:=req_o; tag:=req_t; ep:=req_e;
                assert req_a(0)='0' report "unaligned physical request" severity failure;
                if req_o="00" then assert req_so="01" report "SNES DMA subowner lost" severity failure; end if;
                if force_delay='1' then delay:=701;
                elsif MAX_DELAY=0 then delay:=0;
                else delay:=(a/2+cycles*13) mod MAX_DELAY; end if;
                in_flight<='1'; accepted<='1'; req_r<='0'; bad_sent:=false;
            end if;
            if rsp_v='1' and rsp_r='1' then
                rsp_v<='0';
                if bad_reply='0' then
                    in_flight<='0'; responses<=responses+1;
                    if owner="00" then snes_responses<=snes_responses+1; else dec_responses<=dec_responses+1; end if;
                end if;
            elsif in_flight='1' then
                if delay/=0 then delay:=delay-1;
                else
                    rsp_v<='1'; rsp_o<=owner; rsp_e<=ep; rsp_t<=tag; rsp_error<='0'; bad_reply<='0';
                    rsp_d<=mem(a+1,fixture,start_addr) & mem(a,fixture,start_addr);
                    if inject_bad/=0 and not bad_sent then
                        bad_reply<='1'; bad_sent:=true;
                        case inject_bad is
                            when 1 => rsp_t<=std_logic_vector(unsigned(tag)+1);
                            when 2 => rsp_o<=std_logic_vector(unsigned(owner)+1);
                            when others => rsp_e<=std_logic_vector(unsigned(ep)+1);
                        end case;
                    else rsp_error<=inject_error; end if;
                end if;
            end if;
        end if;
    end process;
    process(clk)
    begin
        if rising_edge(clk) then cycles<=cycles+1; end if;
        if falling_edge(clk) then
            -- Exercise a pending RUN2 across both single and extended pauses.
            if cycles mod 37=9 or (cycles mod 89>=42 and cycles mod 89<=48) then en<='0'; else en<='1'; end if;
        end if;
    end process;
    process
        type pairs_t is array(0 to (OUTPUT_BYTES+1)/2-1) of std_logic_vector(15 downto 0);
        variable expected : pairs_t;
        variable waits, total_waits, cpu_reads : natural := 0;
        variable sample : std_logic_vector(7 downto 0);
        variable prev_responses : natural;
        procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure enabled_tick is begin loop tick; exit when en='1'; end loop; end;
        procedure mmio(a,v:natural) is
        begin
            wait until falling_edge(clk); wait for 1 ns;
            while en='0' loop wait until falling_edge(clk); wait for 1 ns; end loop;
            ca<=std_logic_vector(to_unsigned(a,24)); di<=std_logic_vector(to_unsigned(v,8));
            romsel<='1'; wr<='0'; ce_f<='1'; tick;
            wr<='1'; ce_f<='0'; enabled_tick;
        end;
        procedure setup_stream is
        begin
            mmio(16#4804#,BANK_C); mmio(16#4805#,BANK_D);
            mmio(16#4302#,start_addr mod 256); mmio(16#4303#,(start_addr/256) mod 256);
            mmio(16#4304#,start_addr/65536); mmio(16#4305#,OUTPUT_BYTES mod 256);
            mmio(16#4306#,OUTPUT_BYTES/256); mmio(16#4800#,1); mmio(16#4801#,1);
        end;
        procedure read_byte(a:natural; variable v:out std_logic_vector(7 downto 0); variable w:out natural) is
        begin
            ca<=std_logic_vector(to_unsigned(a,24)); intent<='1'; romsel<='0'; w:=0;
            tick;
            while waiting='1' or en='0' loop
                w:=w+1; assert w<100000 report "CPU read deadlocked" severity failure; tick;
            end loop;
            -- No CPU CE runs during this wait, so progress proves autonomous refill.
            v:=dout;
            wait until falling_edge(clk); wait for 1 ns;
            while en='0' loop wait until falling_edge(clk); wait for 1 ns; end loop;
            rd<='0'; ce_r<='1'; tick; ce_r<='0';
            wait until falling_edge(clk); wait for 1 ns;
            while en='0' loop wait until falling_edge(clk); wait for 1 ns; end loop;
            retire<='1'; ce_f<='1'; tick;
            retire<='0'; ce_f<='0'; rd<='1'; intent<='0'; romsel<='1'; tick;
        end;
    begin
        hard<='0'; rst<='0'; tick; tick; hard<='1';
        for f in 0 to CASES-1 loop
            fixture<=f; rst<='0'; brst<='0'; brun<='0';
            if (f/32) mod 2=0 then start_addr<=16#C00FFE#+((f/16) mod 2);
            else start_addr<=16#CFFFFE#+((f/16) mod 2); end if;
            tick; tick;
            -- Immutable b63f800 arithmetic decoder, legal unbounded byte stream.
            brst<='1'; binit<='1'; tick; binit<='0'; brun<='1';
            for p in expected'range loop
                loop tick; exit when bplane='1'; end loop;
                expected(p):=bdo;
            end loop;
            brun<='0'; brst<='0'; rst<='1'; enabled_tick;
            setup_stream;
            -- Register reads remain live during initial input starvation.
            ca<=x"004800"; intent<='1'; romsel<='1'; rd<='0'; tick;
            assert waiting='0' and dout=x"01" report "MMIO blocked by decoder starvation" severity failure;
            rd<='1'; intent<='0';
            for b in 0 to OUTPUT_BYTES-1 loop
                read_byte(start_addr,sample,waits); total_waits:=total_waits+waits;
                if b mod 2=0 then
                    assert sample=expected(b/2)(7 downto 0)
                        report "low-byte mismatch fixture "&integer'image(f)&" byte "&integer'image(b)&
                        " got "&to_hstring(sample)&" expected "&to_hstring(expected(b/2)(7 downto 0)) severity failure;
                else
                    assert sample=expected(b/2)(15 downto 8)
                        report "high-byte mismatch fixture "&integer'image(f)&" byte "&integer'image(b)&
                        " got "&to_hstring(sample)&" expected "&to_hstring(expected(b/2)(15 downto 8)) severity failure;
                end if;
                cpu_reads:=cpu_reads+1;
                if b mod 13=7 then
                    read_byte(16#E01235#,sample,waits); total_waits:=total_waits+waits;
                    assert sample=mem(physical(16#E01235#),fixture,start_addr) report "contending SNES lane/data mismatch" severity failure;
                end if;
            end loop;
            assert fault='0' report "unexpected bridge fault" severity failure;
            report "fixture "&integer'image(f)&" compared "&integer'image(OUTPUT_BYTES)&" bytes; cumulative CPU wait clocks "&integer'image(total_waits);
            rst<='0';
            loop tick; exit when flush_ack='1'; end loop;
        end loop;
        -- Wrong tag, local owner, or epoch is drained but must not satisfy
        -- the initial compressed-input wait. Error responses also fail closed.
        for kind in 1 to 3 loop
            rst<='1'; force_delay<='1'; inject_bad<=kind; setup_stream;
            ca<=std_logic_vector(to_unsigned(start_addr,24)); intent<='1'; romsel<='0';
            loop tick; exit when bad_reply='1' and rsp_v='1'; end loop;
            assert waiting='1' and flush_ack='0' report "mismatched token released decoder" severity failure;
            tick;
            assert fault='1' and waiting='1' report "mismatched token not rejected" severity failure;
            intent<='0'; romsel<='1'; inject_bad<=0;
            -- Now cancel the accepted matching reply before it can retire.
            rst<='0';
            loop tick; exit when flush_ack='1'; end loop;
            epoch<=std_logic_vector(unsigned(epoch)+1); tick;
        end loop;
        rst<='1'; inject_error<='1'; setup_stream;
        ca<=std_logic_vector(to_unsigned(start_addr,24)); intent<='1'; romsel<='0';
        loop tick; exit when fault='1'; end loop;
        for j in 1 to 30 loop tick; assert waiting='1' report "error response released decoder" severity failure; end loop;
        rst<='0'; intent<='0'; romsel<='1'; inject_error<='0';
        loop tick; exit when flush_ack='1'; end loop;

        -- Soft reset and remount both preserve an accepted physical command
        -- until its old reply drains; only coordinated PLL/hard reset discards.
        for cancellation in 0 to 2 loop
            rst<='1'; flush<='0'; force_delay<='1'; setup_stream;
            loop tick; exit when accepted='1' and req_o="01"; end loop;
            prev_responses:=responses;
            if cancellation=0 then rst<='0';
            elsif cancellation=1 then flush<='1';
            else hard<='0'; end if;
            tick;
            if cancellation<2 then
                assert flush_ack='0' report "flush ACK before accepted command drained" severity failure;
                while responses=prev_responses loop
                    assert req_v='0' report "new request during flush" severity failure;
                    assert rsp_r='1' report "canceled reply cannot drain" severity failure;
                    tick;
                end loop;
                tick; assert flush_ack='1' report "flush ACK missing after drain" severity failure;
                assert responses=prev_responses+1 report "canceled command completed more than once" severity failure;
            else
                assert in_flight='0' and flush_ack='1' report "PLL reset did not clear coordinated transport" severity failure;
                hard<='1'; rst<='0'; tick;
            end if;
            epoch<=std_logic_vector(unsigned(epoch)+1); rst<='1'; flush<='0'; force_delay<='0'; tick;
            setup_stream;
            for b in 0 to OUTPUT_BYTES-1 loop
                read_byte(start_addr,sample,waits);
                if b mod 2=0 then assert sample=expected(b/2)(7 downto 0) report "post-cancellation low byte" severity failure;
                else assert sample=expected(b/2)(15 downto 8) report "post-cancellation high byte" severity failure; end if;
            end loop;
            rst<='0'; loop tick; exit when flush_ack='1'; end loop;
        end loop;
        if OUTPUT_BYTES>=3 then
            -- Two selected channels restart independently, including odd size
            -- and a repeated fixed source address. No extra 4801 write occurs.
            rst<='1'; tick;
            mmio(16#4804#,BANK_C); mmio(16#4805#,BANK_D);
            for channel in 0 to 1 loop
                mmio(16#4302#+channel*16,start_addr mod 256);
                mmio(16#4303#+channel*16,(start_addr/256) mod 256);
                mmio(16#4304#+channel*16,start_addr/65536);
                mmio(16#4305#+channel*16,3); mmio(16#4306#+channel*16,0);
            end loop;
            mmio(16#4800#,3); mmio(16#4801#,3);
            for b in 0 to 5 loop
                read_byte(start_addr,sample,waits);
                if b mod 3=0 then assert sample=expected(0)(7 downto 0) report "channel restart first byte" severity failure;
                elsif b mod 3=1 then assert sample=expected(0)(15 downto 8) report "channel restart second byte" severity failure;
                else assert sample=expected(1)(7 downto 0) report "channel restart odd final byte" severity failure; end if;
            end loop;
            ca<=x"004801"; romsel<='1'; intent<='1'; tick;
            assert waiting='0' and dout=x"00" report "two-channel DMARUN completion" severity failure;
            intent<='0'; rst<='0'; loop tick; exit when flush_ack='1'; end loop;
            report "PASS two selected DMA channels with odd lengths and fixed source";
        end if;
        rst<='1'; tick;
        mmio(16#4804#,BANK_C); mmio(16#4805#,BANK_D);
        mmio(16#4302#,start_addr mod 256); mmio(16#4303#,(start_addr/256) mod 256);
        mmio(16#4304#,start_addr/65536); mmio(16#4800#,0); mmio(16#4801#,1);
        read_byte(start_addr,sample,waits);
        assert sample=mem(physical(start_addr),fixture,start_addr)
            report "disabled DMA channel intercepted a normal ROM read" severity failure;
        rst<='0'; loop tick; exit when flush_ack='1'; end loop;
        report "PASS nonzero DMARUN with no enabled channel remains a normal ROM read";
        report "PASS wrong-tag/owner/epoch, error response, soft-reset drain, remount drain, PLL reset and restart";
        report "PASS SDD1 immutable-baseline bytes="&integer'image(cpu_reads)&
            " wait_clocks="&integer'image(total_waits)&" physical_responses="&integer'image(responses)&
            " snes="&integer'image(snes_responses)&" decoder="&integer'image(dec_responses);
        stop;
    end process;
    process begin wait for 500 ms; assert false report "SDD1 watchdog" severity failure; end process;
end;
