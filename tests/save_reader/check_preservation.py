#!/usr/bin/env python3
"""Native map proof that reader reset stages do not merge with datatable controls."""
import argparse, hashlib, json, pathlib, re, subprocess
R=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--quartus-bin',type=pathlib.Path,required=True);p.add_argument('--out',type=pathlib.Path,required=True);a=p.parse_args();O=a.out.resolve();O.mkdir(parents=True,exist_ok=False);Q=a.quartus_bin.resolve()
source=R/'target/pocket/data_unloader.sv'; top=R/'target/pocket/core_top.sv'
text=source.read_text();assert text.count('preserve, dont_merge,')==1
paths=[source,top,R/'platform/pocket/mf_datatable.v',pathlib.Path(__file__)]
before={str(x.relative_to(R)):hashlib.sha256(x.read_bytes()).hexdigest() for x in paths}
baseline=subprocess.check_output(['git','show','982f103:target/pocket/data_unloader.sv'],cwd=R,text=True)
def functional_tokens(value):
 value=re.sub(r'/\*.*?\*/','',value,flags=re.S)
 value=re.sub(r'//[^\n]*','',value)
 value=re.sub(r'\(\*.*?\*\)','',value,flags=re.S)
 return re.sub(r'\s+','',value)
assert functional_tokens(text)==functional_tokens(baseline),'Functional RTL changed beyond comments/attributes'

block=re.search(r'  always @\(posedge clk_74a or negedge pll_core_locked\) begin\n    if \(~pll_core_locked\) begin\n      datatable_addr <= 0;.*?\n  end',top.read_text(),re.S).group(0)
wrapper='''module reader_release_unit(input clk_74a,clk_memory,pll_core_locked,
 input bridge_rd,bridge_endian_little,input [31:0] bridge_addr,
 output [31:0] bridge_rd_data,output read_en,output [16:0] read_addr,
 input [15:0] read_data,input [3:0] sram_size,
 input [7:0] host_table_addr,input [31:0] host_table_data,input host_table_we,
 output [31:0] datatable_q,host_table_q);
 reg [9:0] datatable_addr; reg datatable_wren; reg [31:0] datatable_data;
 mf_datatable idt(.address_a(datatable_addr[7:0]),.address_b(host_table_addr),
 .clock_a(clk_74a),.clock_b(clk_74a),.data_a(datatable_data),.data_b(host_table_data),
 .wren_a(datatable_wren),.wren_b(host_table_we),.q_a(datatable_q),.q_b(host_table_q));
 data_unloader #(.ADDRESS_MASK_UPPER_4(4'h2),.ADDRESS_SIZE(17),.INPUT_WORD_SIZE(2),
 .READ_MEM_CLOCK_DELAY(2),.SAFE_RESPONSE_HANDSHAKE(1)) reader(
 .clk_74a(clk_74a),.clk_memory(clk_memory),.reset_n(pll_core_locked),
 .bridge_rd(bridge_rd),.bridge_endian_little(bridge_endian_little),
 .bridge_addr(bridge_addr),.bridge_rd_data(bridge_rd_data),
 .read_en(read_en),.read_addr(read_addr),.read_data(read_data));
'''+block+'\nendmodule\n'
records=[]
for name,protected in [('historical_unprotected',False),('protected',True)]:
 d=O/name;d.mkdir();(d/'reader.sv').write_text(text if protected else text.replace('preserve, dont_merge, ',''));(d/'top.sv').write_text(wrapper)
 (d/'unit.qpf').write_text('QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n')
 (d/'unit.qsf').write_text(f'''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY reader_release_unit
set_global_assignment -name SYSTEMVERILOG_FILE "{d/'reader.sv'}"
set_global_assignment -name SYSTEMVERILOG_FILE "{d/'top.sv'}"
set_global_assignment -name VERILOG_FILE "{R/'platform/pocket/mf_datatable.v'}"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE AREA"
set_instance_assignment -name VIRTUAL_PIN ON -to *
''')
 (d/'map.tcl').write_text('load_package flow\nproject_open unit\nexecute_module -tool map\nproject_close\n')
 result=subprocess.run([str(Q/'quartus_sh'),'-t','map.tcl'],cwd=d,capture_output=True,text=True,timeout=240);(d/'map.log').write_text(result.stdout+result.stderr)
 assert result.returncode==0,(name,result.stdout[-1000:],result.stderr[-1000:])
 report=(d/'output_files/unit.map.rpt').read_text()
 merges=[line.strip() for line in report.splitlines() if 'Merged with' in line and 'source_release' in line and 'datatable' in line]
 protected_attrs=[line.strip() for line in report.splitlines() if ('PRESERVE_REGISTER' in line or 'DONT_MERGE_REGISTER' in line) and ('source_release' in line or 'memory_release' in line)]
 if protected:
  assert not merges,merges
  for attr in ['PRESERVE_REGISTER','DONT_MERGE_REGISTER']:
   for reg in ['source_release','memory_release']:
    for bit in ['0','1']:assert any(attr in line and f'{reg}[{bit}]' in line for line in protected_attrs),(attr,reg,bit,protected_attrs)
 else:assert any('datatable_wren' in line for line in merges) and any('datatable_addr' in line for line in merges),merges
 record={'name':name,'passed':True,'negative_control':not protected,'functional_reset_merge_rows':merges,'preservation_assignment_rows':protected_attrs,'native_map_sha256':hashlib.sha256(report.encode()).hexdigest()};records.append(record);print('PASS',name,flush=True)
after={str(x.relative_to(R)):hashlib.sha256(x.read_bytes()).hexdigest() for x in paths}
assert before==after,'Source changed during native run'
summary={'passed':True,'source_stable':True,'functional_tokens_equal_to_982f103':True,'checks':records,'source_sha256':{str(x.relative_to(R)):hashlib.sha256(x.read_bytes()).hexdigest() for x in [source,top,R/'platform/pocket/mf_datatable.v',pathlib.Path(__file__)]},'limits':['Actual data_unloader RTL and exact source-extracted datatable sequential block; actual Intel datatable RAM consumes the write controls','Native synthesis proves preservation is recognized and the historical cross-function merge is removed','Not full-core fitting, post-fit fanout, settling, recovery/removal or MTBF signoff; repeat those on the final full fit']}
(O/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
