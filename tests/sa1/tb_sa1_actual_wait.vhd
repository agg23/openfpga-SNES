library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sa1_test_program.all;
use std.env.all;
entity tb_sa1_actual_wait is
    generic (HANDSHAKE : boolean := true; LATENCY : natural := 0; INTERRUPTS : boolean := true;
             RESET_OWNER : integer := -1; FLUSH_OWNER : integer := -1;
             COMPETING_SNES : boolean := false; CONTROL_ACTIVITY : boolean := true;
             RESPONSE_SYS : natural := 0);
end;
architecture test of tb_sa1_actual_wait is
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal enable : std_logic := '1';
    signal sa : std_logic_vector(23 downto 0) := x"000000";
    signal sdi : std_logic_vector(7 downto 0) := x"00";
    signal sdo : std_logic_vector(7 downto 0);
    signal srd, swr : std_logic := '1';
    signal cr, cf : std_logic := '0';
    signal ra : std_logic_vector(22 downto 0);
    signal rd : std_logic_vector(15 downto 0);
    signal rr : std_logic;
    signal ba : std_logic_vector(17 downto 0);
    signal bdi : std_logic_vector(7 downto 0) := x"00";
    signal bdo : std_logic_vector(7 downto 0);
    signal boe, bwe, irq : std_logic;
    signal pa : std_logic_vector(23 downto 0);
    signal pdo : std_logic_vector(7 downto 0);
    signal prd, pwr : std_logic;
    signal ss : std_logic := '0';
    signal ssrom, sssns : std_logic;
    signal flush : std_logic := '0';
    signal flush_ack, fault : std_logic;
    signal epoch_in : std_logic_vector(7 downto 0) := x"33";
    signal mask_in : std_logic_vector(22 downto 0) := (others=>'1');
    signal intent : std_logic := '0';
    signal subtype_in : std_logic_vector(1 downto 0) := "00";
    signal sneswait : std_logic;
    signal qv, qr, pv, rsp_ready : std_logic := '0';
    signal qa : std_logic_vector(22 downto 0);
    signal qo, qs, po : std_logic_vector(1 downto 0) := "00";
    signal qt, qe, pt, px : std_logic_vector(7 downto 0) := x"00";
    signal pd : std_logic_vector(15 downto 0) := x"FFFF";
    signal busy : boolean := false;
    signal pending_address : natural := 0;
    signal pending_owner : natural := 0;
    signal cycles, transactions, writes, dma_writes, irq_writes, nmi_writes : natural := 0;
    signal complete : boolean := false;
    signal interrupt_sent, bank_changed : boolean := false;
    type ram_type is array (0 to 262143) of std_logic_vector(7 downto 0);
    signal bram : ram_type := (others=>(others=>'0'));
    -- Baseline outputs are wired by the Python harness for exact cycle checks.
    signal r_sdo, r_bdo, r_pdo : std_logic_vector(7 downto 0);
    signal r_ra : std_logic_vector(22 downto 0);
    signal r_ba : std_logic_vector(17 downto 0);
    signal r_pa : std_logic_vector(23 downto 0);
    signal r_rr,r_boe,r_bwe,r_irq,r_prd,r_pwr,r_ssrom,r_sssns : std_logic;
begin
    clk<=not clk after 5 ns;
    rd<=rom_word(to_integer(unsigned(ra)));
    bdi<=bram(to_integer(unsigned(ba)));
    dut: entity work.SA1 generic map(ROM_HANDSHAKE=>HANDSHAKE) port map(
        RST_N=>reset_n,CLK=>clk,ENABLE=>enable,SNES_A=>sa,SNES_DO=>sdo,SNES_DI=>sdi,
        SNES_RD_N=>srd,SNES_WR_N=>swr,SYSCLKF_CE=>cf,SYSCLKR_CE=>cr,REFRESH=>'0',PAL=>'0',
        ROM_A=>ra,ROM_DI=>rd,ROM_RD_N=>rr,BWRAM_A=>ba,BWRAM_DI=>bdi,BWRAM_DO=>bdo,
        BWRAM_OE_N=>boe,BWRAM_WE_N=>bwe,IRQ_N=>irq,
        SA1_P65_A=>pa,SA1_P65_DO=>pdo,SA1_P65_RD_N=>prd,SA1_P65_WR_N=>pwr,
        SS_BUSY=>ss,SS_SA1_ROMSEL=>ssrom,SS_SNS_ROMSEL=>sssns,
        ROM_FLUSH=>flush,ROM_FLUSH_ACK=>flush_ack,ROM_EPOCH=>epoch_in,ROM_ADDR_MASK=>mask_in,
        ROM_SNES_READ_INTENT=>intent,ROM_SNES_RETIRE=>cf,ROM_SNES_OWNER=>subtype_in,ROM_SNES_WAIT=>sneswait,
        ROM_REQ_VALID=>qv,ROM_REQ_READY=>qr,ROM_REQ_ADDR=>qa,ROM_REQ_OWNER=>qo,
        ROM_REQ_SNES_OWNER=>qs,ROM_REQ_TAG=>qt,ROM_REQ_EPOCH=>qe,
        ROM_RSP_VALID=>pv,ROM_RSP_READY=>rsp_ready,ROM_RSP_OWNER=>po,
        ROM_RSP_TAG=>pt,ROM_RSP_EPOCH=>px,ROM_RSP_DATA=>pd,ROM_RSP_ERROR=>'0',ROM_FAULT=>fault);
    legacy_check: if not HANDSHAKE generate
    reference_dut: entity work.SA1_REF port map(
        RST_N=>reset_n,CLK=>clk,ENABLE=>enable,SNES_A=>sa,SNES_DO=>r_sdo,SNES_DI=>sdi,
        SNES_RD_N=>srd,SNES_WR_N=>swr,SYSCLKF_CE=>cf,SYSCLKR_CE=>cr,REFRESH=>'0',PAL=>'0',
        ROM_A=>r_ra,ROM_DI=>rd,ROM_RD_N=>r_rr,BWRAM_A=>r_ba,BWRAM_DI=>bdi,BWRAM_DO=>r_bdo,
        BWRAM_OE_N=>r_boe,BWRAM_WE_N=>r_bwe,IRQ_N=>r_irq,
        SA1_P65_A=>r_pa,SA1_P65_DO=>r_pdo,SA1_P65_RD_N=>r_prd,SA1_P65_WR_N=>r_pwr,
        SS_BUSY=>ss,SS_SA1_ROMSEL=>r_ssrom,SS_SNS_ROMSEL=>r_sssns);
    end generate;
    -- A bounded variable-latency synthetic ROM endpoint, not a CPU replacement.
    process(clk)
        variable remaining : natural := 0;
        variable address : natural;
        variable owner : std_logic_vector(1 downto 0);
        variable tag, generation : std_logic_vector(7 downto 0);
        variable blocked : boolean := false;
        variable old_address : std_logic_vector(22 downto 0);
        variable old_owner : std_logic_vector(1 downto 0);
        variable old_tag, old_epoch : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            cycles<=cycles+1;
            if RESPONSE_SYS>0 or LATENCY=0 then qr<='1';
            elsif cycles mod 7 < 3 then qr<='0'; else qr<='1'; end if;
            if blocked then
                assert qv='1' and qa=old_address and qo=old_owner and qt=old_tag and qe=old_epoch
                    report "actual SA1 changed an unaccepted request" severity failure;
            end if;
            blocked:=qv='1' and qr='0';
            old_address:=qa; old_owner:=qo; old_tag:=qt; old_epoch:=qe;
            if qv='1' and qr='1' then
                assert not busy report "multiple physical requests outstanding" severity failure;
                busy<=true; address:=to_integer(unsigned(qa)); owner:=qo; tag:=qt; generation:=qe;
                pending_address<=address; pending_owner<=to_integer(unsigned(owner)); transactions<=transactions+1;
                if RESPONSE_SYS=1 or (RESPONSE_SYS=0 and LATENCY=0) then
                    pv<='1'; pd<=rom_word(address); po<=owner; pt<=tag; px<=generation;
                    remaining:=0;
                elsif RESPONSE_SYS>1 then remaining:=RESPONSE_SYS-2;
                else remaining:=LATENCY+(address+transactions) mod 11; end if;
            elsif busy then
                if pv='1' and rsp_ready='1' then pv<='0'; busy<=false;
                elsif remaining=0 then
                    pv<='1'; pd<=rom_word(address); po<=owner; pt<=tag; px<=generation;
                else remaining:=remaining-1; end if;
            end if;
            if bwe='0' then
                bram(to_integer(unsigned(ba)))<=bdo;
                if to_integer(unsigned(ba))>=16#20# and to_integer(unsigned(ba))<16#27# then
                    assert bdo=rom_byte(16#1FFFFD#+to_integer(unsigned(ba))-16#20#)
                        report "ROM DMA BWRAM data/address mismatch" severity failure;
                    dma_writes<=dma_writes+1;
                end if;
            end if;
            if pwr='0' then
                writes<=writes+1;
                case to_integer(unsigned(pa)) is
                    when 16#100# => assert pdo=rom_byte(16#FFFFF#) report "CPU old-bank read retargeted" severity failure;
                    when 16#101# | 16#102# => assert pdo=rom_byte(16#100000#) report "CPU repeated-address or bank read wrong" severity failure;
                    when 16#103# => assert pdo=rom_byte(16#200001#) report "CPU captured byte lane wrong" severity failure;
                    when 16#120# => assert pdo=rom_byte(16#2FFFE#) report "VBP preload low byte wrong" severity failure;
                    when 16#121# => assert pdo=rom_byte(16#2FFFF#) report "VBP preload high byte wrong" severity failure;
                    when 16#122# => assert pdo=rom_byte(16#30000#) report "VBP refill low byte wrong" severity failure;
                    when 16#123# => assert pdo=rom_byte(16#30001#) report "VBP refill high byte wrong" severity failure;
                    when 16#130# => if pdo=x"01" then irq_writes<=irq_writes+1; end if;
                    when 16#131# => if pdo=x"01" then nmi_writes<=nmi_writes+1; end if;
                    when 16#13F# => assert pdo=x"A5" severity failure; complete<=true;
                    when others=>null;
                end case;
            end if;
            if not HANDSHAKE and reset_n='1' then
                assert sdo=r_sdo and ra=r_ra and rr=r_rr and ba=r_ba and bdo=r_bdo and boe=r_boe and bwe=r_bwe
                    and irq=r_irq and pa=r_pa and pdo=r_pdo and prd=r_prd and pwr=r_pwr and ssrom=r_ssrom and sssns=r_sssns
                    report "zero-wait baseline cycle divergence" severity failure;
            end if;
        end if;
    end process;
    process
        variable value, before_timer, after_timer : std_logic_vector(7 downto 0);
        variable observed : std_logic_vector(7 downto 0);
        variable saved_transactions : natural;
        procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure write_snes(address : natural; value : std_logic_vector(7 downto 0)) is
        begin
            sa<=std_logic_vector(to_unsigned(address,24)); sdi<=value; swr<='0'; cf<='1';
            tick; cf<='0'; swr<='1'; tick;
        end;
        procedure read_saved(address : natural; variable value : out std_logic_vector(7 downto 0)) is
        begin
            ss<='1'; sa<=std_logic_vector(to_unsigned(16#2200#+address,24)); srd<='0'; tick; tick;
            value:=sdo; srd<='1'; ss<='0'; tick;
        end;
        procedure read_iram(address : natural; expected : std_logic_vector(7 downto 0)) is
        begin
            sa<=std_logic_vector(to_unsigned(16#3000#+address,24)); srd<='0'; cr<='1'; tick; cr<='0';
            tick; tick; assert sdo=expected report "IRAM DMA/CPU readback mismatch at " & integer'image(address) severity failure;
            cf<='1'; tick; cf<='0'; srd<='1'; tick;
        end;
        procedure boot is
        begin
            write_snes(16#2200#,x"20");
            write_snes(16#2203#,x"00"); write_snes(16#2204#,x"80");
            write_snes(16#2205#,x"00"); write_snes(16#2206#,x"91");
            write_snes(16#2207#,x"00"); write_snes(16#2208#,x"90");
            write_snes(16#2220#,x"00"); write_snes(16#2221#,x"01");
            write_snes(16#2222#,x"02"); write_snes(16#2223#,x"03");
            write_snes(16#2226#,x"80"); write_snes(16#2228#,x"00"); write_snes(16#2229#,x"FF");
            write_snes(16#2200#,x"00"); sa<=x"000000";
        end;
        procedure read_snes_rom(address : natural; expected : std_logic_vector(7 downto 0); owner : std_logic_vector(1 downto 0); change_mask : boolean := false) is
        begin
            sa<=std_logic_vector(to_unsigned(address,24)); srd<='0'; intent<='1'; subtype_in<=owner;
            wait for 1 ns;
            if HANDSHAKE then
                assert sneswait='1' report "SNES raw read intent did not assert wait before bus phase" severity failure;
                if change_mask then
                    wait until busy and pending_owner=0; mask_in<=std_logic_vector(to_unsigned(16#0FFFFF#,23));
                end if;
                while sneswait='1' loop tick; end loop;
            end if;
            cr<='1'; tick; cr<='0'; tick;
            assert sdo=expected report "SNES captured response/lane wrong" severity failure;
            cf<='1'; tick; cf<='0'; intent<='0'; srd<='1'; tick;
        end;
    begin
        for n in 1 to 5 loop tick; end loop; reset_n<='1';
        boot;
        if HANDSHAKE and RESET_OWNER>=0 then
            if RESET_OWNER=0 then
                sa<=x"D003FF"; srd<='0'; intent<='1';
            end if;
            wait until busy and pending_owner=RESET_OWNER;
            reset_n<='0'; intent<='0'; srd<='1'; sa<=x"000000"; tick; tick;
            assert flush_ack='0' report "chip reset dropped accepted physical token" severity failure;
            reset_n<='1'; tick;
            while busy loop
                assert qv='0' and bwe='1' report "new request/write before reset drain" severity failure;
                tick;
            end loop;
            assert flush_ack='1' report "reset drain did not finish" severity failure;
            boot;
        end if;
        if HANDSHAKE and LATENCY>0 and CONTROL_ACTIVITY then
            -- Mutate the bank register after this long read is accepted. The
            -- CPU's instruction bank uses CBMAP=0, so its own code is unchanged.
            wait until busy and pending_owner=1 and pending_address=16#FFFFE#;
            write_snes(16#2220#,x"03"); bank_changed<=true;
            wait until not busy; write_snes(16#2220#,x"00"); sa<=x"000000";
            if INTERRUPTS then
                wait until busy and pending_owner=1;
                write_snes(16#2200#,x"D5"); interrupt_sent<=true;
                read_saved(16#00#,value);
                assert value=x"D5" report "SNES interrupt/MMIO control lost during memory wait" severity failure;
                read_saved(16#16#,before_timer);
                for n in 1 to 40 loop
                    tick; assert pwr='1' and prd='1' report "CPU retired while software wait held" severity failure;
                end loop;
                read_saved(16#16#,after_timer);
                assert before_timer/=after_timer report "timer frozen during memory/software wait" severity failure;
                write_snes(16#2200#,x"00"); sa<=x"000000";
            end if;
        end if;
        if HANDSHAKE and FLUSH_OWNER>=0 then
            wait until busy and pending_owner=FLUSH_OWNER;
            flush<='1'; epoch_in<=x"34"; tick; tick;
            assert flush_ack='0' report "mount flush dropped accepted physical token" severity failure;
            flush<='0';
            while busy loop
                assert qv='0' and bwe='1' report "new request/write before mount drain" severity failure;
                tick;
            end loop;
            assert flush_ack='1' report "mount drain did not finish" severity failure;
        end if;
        if HANDSHAKE and COMPETING_SNES then
            wait until busy and pending_owner=2;
            read_snes_rom(16#D003FF#,rom_byte(16#1003FF#),"01");
            wait until busy and pending_owner=3;
            read_snes_rom(16#E00401#,rom_byte(16#200401#),"11");
            sa<=x"000000";
        end if;
        wait until complete;
        for n in 1 to 25 loop tick; end loop;
        assert fault='0' report "ROM transport protocol fault" severity failure;
        if HANDSHAKE then assert dma_writes=7 report "ROM DMA destination write duplicated/missing" severity failure; end if;
        if interrupt_sent then
            assert irq_writes=1 and nmi_writes=1 report "IRQ/NMI lost while ROM stalled" severity failure;
        end if;
        for n in 0 to 6 loop read_iram(16#108#+n,rom_byte(16#1FFFD#+n)); end loop;
        read_saved(16#38#,value); assert value=x"00" report "DMA count advanced incorrectly" severity failure;
        read_saved(16#32#,value); assert value=x"04" report "DMA source low byte wrong" severity failure;
        read_saved(16#33#,value); assert value=x"00" report "DMA source bank crossing wrong" severity failure;
        read_saved(16#34#,value); assert value=x"E0" report "DMA source bank wrong" severity failure;
        read_saved(16#59#,value); assert value=x"05" report "VBP advanced more/less than once per word" severity failure;
        read_saved(16#5A#,value); assert value=x"00" severity failure;
        read_saved(16#5B#,value); assert value=x"C3" severity failure;
        read_saved(16#16#,before_timer); for n in 1 to 80 loop tick; end loop; read_saved(16#16#,after_timer);
        assert before_timer/=after_timer report "timer stopped with CPU waiting" severity failure;
        -- Back-to-back same-address SCPU read transactions and subtype changes.
        for i in 0 to 3 loop read_snes_rom(16#D003FF#,rom_byte(16#1003FF#),std_logic_vector(to_unsigned(i,2))); end loop;
        read_snes_rom(16#D00400#,rom_byte(16#100400#),"10");
        -- Every LoROM/HiROM bank-map region, then software bank overrides.
        read_snes_rom(16#00803F#,rom_byte(16#00003F#),"00");
        read_snes_rom(16#208041#,rom_byte(16#100041#),"01");
        read_snes_rom(16#808043#,rom_byte(16#200043#),"10");
        read_snes_rom(16#A08045#,rom_byte(16#300045#),"11");
        read_snes_rom(16#C00451#,rom_byte(16#000451#),"00");
        read_snes_rom(16#F00453#,rom_byte(16#300453#),"11");
        if HANDSHAKE then
            read_snes_rom(16#D003FF#,rom_byte(16#1003FF#),"10",true);
            read_snes_rom(16#D003FF#,rom_byte(16#0003FF#),"10");
            mask_in<=(others=>'1');
        end if;
        write_snes(16#2220#,x"86");
        read_snes_rom(16#00803F#,rom_byte(16#60003F#),"00");
        read_snes_rom(16#C00451#,rom_byte(16#600451#),"01");
        write_snes(16#2221#,x"85");
        read_snes_rom(16#208041#,rom_byte(16#500041#),"10");
        write_snes(16#2222#,x"84");
        read_snes_rom(16#808043#,rom_byte(16#400043#),"11");
        write_snes(16#2223#,x"87");
        read_snes_rom(16#A08045#,rom_byte(16#700045#),"00");
        write_snes(16#220C#,x"34"); write_snes(16#220D#,x"12");
        write_snes(16#220E#,x"78"); write_snes(16#220F#,x"56");
        for n in 0 to 3 loop
            if n<2 then sa<=std_logic_vector(to_unsigned(16#FFEA#+n,24));
            else sa<=std_logic_vector(to_unsigned(16#FFEE#+n-2,24)); end if;
            intent<='1'; srd<='0'; wait for 1 ns;
            assert sneswait='0' report "local SNES vector incorrectly waited for ROM" severity failure;
            cr<='1'; tick; cr<='0'; tick;
            case n is
                when 0=>observed:=x"34"; when 1=>observed:=x"12";
                when 2=>observed:=x"78"; when others=>observed:=x"56";
            end case;
            assert sdo=observed report "SNES local vector data changed" severity failure;
            cf<='1'; tick; cf<='0'; intent<='0'; srd<='1'; tick;
        end loop;
        report "PASS real SA1/P65C816 latency=" & integer'image(LATENCY) &
            " cycles=" & integer'image(cycles) & " requests=" & integer'image(transactions) &
            " cpu_writes=" & integer'image(writes) & " dma_writes=" & integer'image(dma_writes) &
            " IRQ=" & integer'image(irq_writes) & " NMI=" & integer'image(nmi_writes);
        stop;
    end process;
    process begin wait for 2 ms; assert false report "actual SA1 bench timed out" severity failure; end process;
end architecture;
