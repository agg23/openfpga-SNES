from pathlib import Path
import sys,subprocess,json,re,os
root=Path(__file__).resolve().parents[2];sys.path.insert(0,str(root/'tests'))
out=Path(os.environ.get('OWNER_LIVENESS_OUTPUT',root/'build/owner-liveness')).resolve();out.mkdir(parents=True,exist_ok=True)
import test_sa1_memory_wait as t
C=t.Sa1MemoryWaitTests;C.setUpClass()
results=[]
try:
 s=(root/'rtl/upstream/chip/SA1/SA1.vhd').read_text()
 s=re.sub(r'\bSA1\b','SA1_LIVE',s)
 s=s.replace('    generic','    generic',1)
 # Add read-only probes; the production datapath/state/NEED generation is unchanged.
 s=s.replace('\tport (','\tport (\n        LIVE_NEED,LIVE_READY,LIVE_RETIRE : out std_logic_vector(3 downto 0);',1)
 if 'LIVE_NEED' not in s:
  s=s.replace('\tport(','\tport(\n        LIVE_NEED,LIVE_READY,LIVE_RETIRE : out std_logic_vector(3 downto 0);',1)
 s=s.replace('\nbegin\n\nprocess( RST_N, CLK )','\nbegin\nLIVE_NEED<=ROM_NEED; LIVE_READY<=ROM_READY; LIVE_RETIRE<=ROM_RETIRE;\n\nprocess( RST_N, CLK )',1)
 probe=out/'SA1_LIVE.vhd';probe.write_text(s)
 bench=(root/'tests/sa1/tb_sa1_actual_wait.vhd').read_text().replace('tb_sa1_actual_wait','tb_sa1_liveness')
 bench=bench.replace('    signal clk :','    signal live_need,live_ready,live_retire : std_logic_vector(3 downto 0);\n    signal clk :',1)
 bench=bench.replace('dut: entity work.SA1 generic map','dut: entity work.SA1_LIVE generic map')
 bench=bench.replace('        RST_N=>reset_n,CLK=>clk,ENABLE=>enable,','        LIVE_NEED=>live_need,LIVE_READY=>live_ready,LIVE_RETIRE=>live_retire,\n        RST_N=>reset_n,CLK=>clk,ENABLE=>enable,',1)
 old='''        boot;
        if HANDSHAKE and RESET_OWNER>=0 then'''
 new='''        boot;
        -- Sustained legal SCPU read pressure: each ROM result is retained through
        -- distinct ready -> R -> F phases before its own retirement.
        if COMPETING_SNES then
            while not complete loop
                read_snes_rom(16#D003FF#,rom_byte(16#1003FF#),"00");
            end loop;
            sa<=x"000000";
        end if;
        if HANDSHAKE and RESET_OWNER>=0 then'''
 assert old in bench;bench=bench.replace(old,new)
 a=bench.index('        if HANDSHAKE and COMPETING_SNES then')
 b=bench.index('        wait until complete;',a)
 bench=bench[:a]+bench[b:]
 bench=bench.replace('        wait until complete;','        if not complete then wait until complete; end if;')
 monitor='''    process(clk)
        type ints is array(0 to 3) of natural;
        variable age,peak,grants,waiting_grants : ints := (others=>0);
        variable reported : boolean := false;
    begin
        if rising_edge(clk) and reset_n='1' then
            for i in 0 to 3 loop
                if live_need(i)='1' and live_ready(i)='0' then
                    age(i):=age(i)+1;
                    if age(i)>peak(i) then peak(i):=age(i); end if;
                else age(i):=0; end if;
                if qv='1' and qr='1' and to_integer(unsigned(qo))=i then grants(i):=grants(i)+1; end if;
                assert age(i)<10000 report "SA1_LIVE excessive service wait owner " & integer'image(i) severity failure;
            end loop;
            if complete and not reported then
                for i in 0 to 3 loop
                    assert grants(i)>0 report "SA1_LIVE owner not exercised" severity failure;
                    report "SA1_LIVE owner=" & integer'image(i) & " grants=" & integer'image(grants(i)) & " max_need_to_ready_sys=" & integer'image(peak(i));
                end loop;
                reported:=true;
            end if;
        end if;
    end process;
'''
 bench=bench.replace('    process begin wait for 2 ms;',monitor+'    process begin wait for 2 ms;')
 bp=out/'tb_sa1_liveness.vhd';bp.write_text(bench)
 C.analyze(probe,bp)
 for response in (1,3,7,31,127):
  p=C.run_ghdl('-r','tb_sa1_liveness','-gCOMPETING_SNES=true','-gCONTROL_ACTIVITY=false','-gINTERRUPTS=false',f'-gRESPONSE_SYS={response}','--assert-level=error','--ieee-asserts=disable')
  (out/f'sa1-{response}.log').write_text(p.stdout)
  assert p.returncode==0,p.stdout
  lines=[l for l in p.stdout.splitlines() if 'SA1_LIVE owner=' in l or 'PASS real SA1' in l]
  assert len(lines)==5,lines
  print('PASS SA1 liveness response',response,*lines,sep='\n',flush=True)
  results.append({'response_sys':response,'lines':lines,'passed':True})
 (out/'sa1-summary.json').write_text(json.dumps(results,indent=2)+'\n')
finally:C.tearDownClass()
