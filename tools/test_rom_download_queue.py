#!/usr/bin/env python3
"""Source-backed ROM transport tests, including actual Intel dcfifo simulation.

Requires an already installed Intel altera_mf.v, Icarus, and production backend
sources. Never downloads vendor software or substitutes a behavioral FIFO.
"""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--altera-mf', type=pathlib.Path, default=ROOT.parent/'toolchain/intelFPGA_lite/21.1/quartus/eda/sim_lib/altera_mf.v')
p.add_argument('--integration-root', type=pathlib.Path, default=ROOT)
p.add_argument('--engine-root', type=pathlib.Path, default=ROOT)
p.add_argument('--baseline-root', type=pathlib.Path)
p.add_argument('--out', type=pathlib.Path, default=ROOT/'build/rom-download-tests')
p.add_argument('--unit-only', action='store_true')
a = p.parse_args()
for field in ('altera_mf', 'integration_root', 'engine_root', 'baseline_root', 'out'):
    value = getattr(a, field)
    if value is not None: setattr(a, field, value.resolve())
out = a.out.resolve(); out.mkdir(parents=True, exist_ok=True)
for tool in ('iverilog', 'vvp'):
    if not shutil.which(tool): raise SystemExit(f'NOT RUN: {tool} unavailable')
if not a.altera_mf.is_file(): raise SystemExit('NOT RUN: actual Intel altera_mf.v missing; pass --altera-mf')
rtl = ROOT/'rtl/memory_ready/rom_download_queue.sv'
unit = ROOT/'tests/memory_ready/tb_rom_download_queue.sv'
unified = ROOT/'tests/memory_ready/tb_unified_download_queue.sv'
fence = ROOT/'tests/memory_ready/tb_download_read_fence.sv'
recovery = ROOT/'tests/memory_ready/tb_unified_download_fault_recovery.sv'
backend = ROOT/'tests/memory_ready/tb_rom_download_backend.sv'
checks = []
finished = False
sources = [rtl, unit, unified, fence, recovery, backend, a.altera_mf, pathlib.Path(__file__).resolve(),
           ROOT/'support/loader.asm', ROOT/'target/pocket/data_loader.sv',
           ROOT/'target/pocket/data_unloader.sv']
integration=[a.integration_root/'rtl/memory_ready/sdram_cart_port.sv',
             a.integration_root/'rtl/memory_ready/sdram_transaction_cdc.sv',
             a.engine_root/'rtl/memory_ready/sdram_single_request.sv']
if not a.unit_only:
    for file in integration:
        if not file.is_file(): raise SystemExit('NOT RUN: integration source missing: '+str(file))
    sources += [*integration, a.integration_root/'target/pocket/core_top.sv',
                a.integration_root/'rtl/mister_top/SNES.sv',
                a.integration_root/'target/pocket/data_unloader.sv',
                a.integration_root/'target/pocket/ram_clear_frontier.sv',
                a.integration_root/'target/pocket/host_reset_guard.sv']
if not a.unit_only:
    for name in ('tests/save_reader/reference_data_unloader.sv','tests/save_reader/tb_legacy_cycle.sv',
                 'tests/save_reader/legacy.py','docs/evidence/save-reader/legacy/summary.json'):
        candidate=a.integration_root/name
        if candidate.is_file(): sources.append(candidate)
source_hashes = {str(f.resolve()):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
def run(name, cmd, expected='PASS', fail=False):
    r = subprocess.run(list(map(str,cmd)), cwd=ROOT, capture_output=True, text=True, timeout=180)
    (out/(name+'.log')).write_text(r.stdout+r.stderr)
    ok = (r.returncode != 0 if fail else r.returncode == 0) and (expected is None or expected in r.stdout+r.stderr)
    checks.append(dict(name=name,passed=ok,command=list(map(str,cmd))))
    if not ok: raise RuntimeError(f'{name} failed; see {out/(name+".log")}')
    if expected: print(r.stdout.strip())
def sim(name, bench, src, top, defines=()):
    exe = out/name
    run(name+'-compile',['iverilog','-g2012','-s',top,*defines,'-o',exe,*src,bench,a.altera_mf],expected=None)
    run(name,['vvp',exe])
def baseline_equal():
    path='target/pocket/data_loader.sv'
    if a.baseline_root:
        old=(a.baseline_root/path).read_bytes()
        top=(a.baseline_root/'target/pocket/core_top.sv').read_text()
    else:
        old=subprocess.check_output(['git','show','b63f800:'+path],cwd=ROOT)
        top=subprocess.check_output(['git','show','b63f800:target/pocket/core_top.sv'],cwd=ROOT,text=True)
    current=(ROOT/path).read_bytes()
    if current != old: raise AssertionError('Legacy loader source changed')
    for label in ('data_loader','save_data_loader'):
        pattern=r'data_loader\s*#\((?:(?!data_loader\s*#).)*?\)\s+'+label+r'\s*\(.*?\n\s*\);'
        before=re.search(pattern,top,re.S)
        after=re.search(pattern,(a.integration_root/'target/pocket/core_top.sv').read_text(),re.S)
        if not before or not after or re.sub(r'\s','',before[0]) != re.sub(r'\s','',after[0]):
            raise AssertionError(f'Legacy {label} instance/configuration changed')
    checks.append(dict(name='legacy-loader-and-save-source-equality',passed=True,
                       sha256=hashlib.sha256(current).hexdigest()))
    path='target/pocket/data_unloader.sv'
    old_read=(a.baseline_root/path).read_bytes() if a.baseline_root else subprocess.check_output(['git','show','b63f800:'+path],cwd=ROOT)
    current_read=(a.integration_root/path).read_bytes()
    pattern=r'data_unloader\s*#\(.*?\)\s+data_unloader\s*\(.*?\n\s*\);'
    before=re.search(pattern,top,re.S)
    after=re.search(pattern,(a.integration_root/'target/pocket/core_top.sv').read_text(),re.S)
    if not before or not after: raise AssertionError('Host backup reader instance missing')
    if current_read==old_read:
        if re.sub(r'\s','',before[0])!=re.sub(r'\s','',after[0]):
            raise AssertionError('Original host backup reader instance changed')
        proof='original source and instance equality'
    else:
        # The repaired standard reader is opt-in. Preserve the old default and
        # every legacy parameter/connection; behavior evidence is a separately
        # recorded actual-vendor cycle comparison, not inferred from this text.
        if not re.search(r'parameter\s+SAFE_RESPONSE_HANDSHAKE\s*=\s*0\b',current_read.decode()):
            raise AssertionError('Legacy reader must default to original handshake')
        old_ports=dict(re.findall(r'\.(\w+)\(([^()]*)\)',re.sub(r'\s','',before[0])))
        new_ports=dict(re.findall(r'\.(\w+)\(([^()]*)\)',re.sub(r'\s','',after[0])))
        if new_ports.pop('SAFE_RESPONSE_HANDSHAKE',None)!='USE_STANDARD_SDRAM' or new_ports.pop('reset_n',None)!='pll_core_locked':
            raise AssertionError('Standard reader handshake/reset must be explicitly connected')
        if new_ports.get('READ_MEM_CLOCK_DELAY')!='USE_STANDARD_SDRAM?2:7':
            raise AssertionError('Reader delay must retain legacy 7, standard 2')
        new_ports['READ_MEM_CLOCK_DELAY']='7'
        if new_ports!=old_ports: raise AssertionError('Legacy reader parameters/connections changed')
        evidence_path=a.integration_root/'docs/evidence/save-reader/legacy/summary.json'
        record=json.loads(evidence_path.read_text())
        observed=record.get('checks',[])
        required={f'w{w}-d{d}-early{e}' for w in (1,2) for d in (1,2,7) for e in (0,1)}
        positive={c['name'] for c in observed if not c.get('negative')}
        negative={c['name'] for c in observed if c.get('negative')}
        if not all(record.get(k) for k in ('completed','source_stable','passed')) or not all(c['passed'] for c in observed) or not required.issubset(positive) or 'unconditional-aclr-sync-early-read' not in negative or len({c['name'] for c in observed})!=len(observed):
            raise AssertionError('Recorded legacy reader comparison lacks complete width/delay/early-read coverage or the ACLR negative control')
        reference=(a.integration_root/'tests/save_reader/reference_data_unloader.sv').read_bytes()
        if reference.replace(b'reference_data_unloader',b'data_unloader')!=old_read:
            raise AssertionError('Legacy cycle reference is not the exact baseline reader')
        for name,sha in record['source_sha256'].items():
            if hashlib.sha256((a.integration_root/name).read_bytes()).hexdigest()!=sha:
                raise AssertionError('Recorded reader cycle proof source mismatch: '+name)
        proof='recorded 12 x 30000 clk74 actual-vendor legacy cycles (all widths/delays/early-read), ACLR negative control; exact baseline reference and source hashes verified'
    checks.append(dict(name='host-backup-reader-legacy-contract',passed=True,
                       sha256=hashlib.sha256(current_read).hexdigest(),proof=proof))
    print('PASS LEGACY exact ROM/save loaders; backup reader '+proof)
def integration_contract(text):
    queue=re.search(r'rom_download_queue\s+queue\s*\((.*?)\);',text,re.S)
    snes=re.search(r'MAIN_SNES.*?\)\s+snes\s*\((.*?)\n\s*\);',text,re.S)
    guard=re.search(r'msu_init_guard\s+msu_bootstrap_guard\s*\((.*?)\);',text,re.S)
    if not queue or not snes or not guard: raise AssertionError('queue/MAIN/MSU instance missing')
    required={'clk_74a':'clk_74a','clk_memory':'clk_sys_21_48','hard_reset_n':'pll_core_locked',
              'download_active':'ioctl_download','write_valid':'ioctl_valid','write_ready':'ioctl_ready',
              'write_en':'ioctl_wr','write_addr':'ioctl_addr','write_data':'ioctl_dout',
              'image_busy':'ioctl_image_busy','image_complete':'ioctl_image_complete','fault':'ioctl_fault',
              'config_in':'{PAL,ram_size,rom_size,rom_type}',
              'config_out':'ioctl_config','config_valid':'ioctl_config_valid',
              'image_begin':'ioctl_image_begin','save_valid':'queue_save_valid',
              'save_ready':'queue_save_ready','save_en':'sd_wr','save_addr':'sd_buff_addr_in',
              'save_data':'sd_buff_dout','save_busy':'queue_save_busy',
              'source_ready':'queue_source_ready','save_read_request':'queue_save_read_request',
              'save_read_ready':'queue_save_read_ready','save_read_quiescent':'save_backup_ready'}
    compact=re.sub(r'\s','',queue[1])
    if any(f'.{port}({wire})' not in compact for port,wire in required.items()):
        raise AssertionError('queue integration port mismatch')
    if '.ioctl_download(ioctl_image_busy)' not in re.sub(r'\s','',snes[1]):
        raise AssertionError('MAIN must receive destination image_busy, not raw source download')
    if '.ioctl_download(ioctl_download)' not in re.sub(r'\s','',guard[1]):
        raise AssertionError('clk74 MSU init guard must retain source-domain download')
    snes_compact=re.sub(r'\s','',snes[1])
    for port,bits in {'rom_type':'7:0','rom_size':'11:8','ram_size':'15:12','PAL':'16'}.items():
        if f'.{port}(ioctl_config[{bits}])' not in snes_compact:
            raise AssertionError('MAIN must use ordered destination config for '+port)
    if '(USE_STANDARD_SDRAM&&(!ioctl_config_valid||host_reset_s))' not in snes_compact:
        raise AssertionError('Standard MAIN reset must guard invalid config')
    for port,wire in {'ioctl_image_begin':'ioctl_image_begin','save_busy':'queue_save_busy',
                      'save_write_addr':'sd_buff_addr_in','save_write_ready':'queue_save_ready',
                      'save_backup_ready':'save_backup_ready'}.items():
        if f'.{port}({wire})' not in snes_compact:
            raise AssertionError('MAIN unified Save/BEGIN wiring mismatch: '+port)
    legacy=re.search(r'begin:\s*g_legacy_rom_download(.*?)data_loader\s*#',text,re.S)
    legacy_compact=re.sub(r'\s','',legacy[1]) if legacy else ''
    if 'assignioctl_config={PAL,ram_size,rom_size,rom_type};' not in legacy_compact or \
       "assignioctl_config_valid=1'b1;" not in legacy_compact:
        raise AssertionError('Legacy live config/valid behavior must be preserved')
    for connection in ('ioctl_wr','ioctl_valid','ioctl_ready','ioctl_image_complete','ioctl_fault'):
        if f'.{connection}({connection})' not in re.sub(r'\s','',snes[1]):
            raise AssertionError('MAIN queue contract missing '+connection)
try:
    baseline_equal()
    if not a.unit_only:
        top=(a.integration_root/'target/pocket/core_top.sv').read_text()
        integration_contract(top)
        checks.append(dict(name='queue-MAIN-MSU-domain-wiring',passed=True))
        try: integration_contract(top.replace('.ioctl_download(ioctl_image_busy)', '.ioctl_download(ioctl_download)'))
        except AssertionError: checks.append(dict(name='raw-source-MAIN-wiring-negative-control',passed=True))
        else: raise AssertionError('raw source miswiring negative control escaped')
        for name,old,new in [
            ('raw-source-map-wiring','.rom_type(ioctl_config[7:0])','.rom_type(rom_type)'),
            ('raw-source-region-wiring','.PAL(ioctl_config[16])','.PAL(PAL)'),
            ('wrong-config-packing','.config_in({PAL,ram_size,rom_size,rom_type})',
             '.config_in({PAL,rom_size,ram_size,rom_type})'),
            ('missing-config-reset','!ioctl_config_valid',"1'b0"),
            ('missing-clear-begin','.ioctl_image_begin(ioctl_image_begin)',".ioctl_image_begin(1'b0)"),
            ('missing-read-fence','.save_read_request(queue_save_read_request)',".save_read_request(1'b0)"),
            ('unsafe-read-barrier','.save_read_quiescent(save_backup_ready)',".save_read_quiescent(1'b1)"),
            ('missing-source-eligibility','.source_ready(queue_source_ready)',".source_ready()"),
            ('missing-save-busy','.save_busy(queue_save_busy)',".save_busy(1'b0)"),
            ('save-frontier-read-mux','.save_write_addr(sd_buff_addr_in)',".save_write_addr({sd_buff_addr,1'b0})"),
        ]:
            if old not in top: raise AssertionError('integration mutation target missing: '+name)
            try: integration_contract(top.replace(old,new))
            except AssertionError: checks.append(dict(name=name+'-negative-control',passed=True))
            else: raise AssertionError(name+' negative control escaped')
        print('PASS INTEGRATION ordered config + queue/MAIN/MSU domains, legacy config, and eleven wiring negative controls')
    sim('queue-unit',unit,[rtl],'tb_rom_download_queue')
    sim('unified-queue-unit',unified,[rtl],'tb_unified_download_queue')
    sim('backup-read-fence',fence,[rtl],'tb_download_read_fence')
    mutations=[
        ('early-end','assign image_complete = complete && !fault && sink_reset_sync[1];',
         'assign image_complete = !download_active && sink_reset_sync[1];','EARLY_END'),
        ('ignore-overflow','(source_event && fifo_full)','1\'b0','FAIL_CLOSED'),
        ('wrong-endian','bridge_endian_little ? bridge_wr_data :','1\'b1 ? bridge_wr_data :','DATA_ORDER'),
        ('advance-stalled','if (write_en || save_en) begin','if (write_valid || save_en) begin','READY_VALID'),
        ('live-source-config','config_out <= pending_config;',
         'config_out <= config_in;','CONFIG_ORDER'),
        ('late-begin-config','pending_config <= fifo_out[76:60];',
         'pending_config <= config_in;','CONFIG_ORDER'),
        ('stale-remount-config','if (write_en && config_pending) begin',
         'if (write_en && config_pending && !config_adopted) begin','CONFIG_ORDER'),
        ('empty-clears-config','sink_open <= 0; config_pending <= 0;',
         'sink_open <= 0; config_pending <= 0; if (!image_has_data) config_adopted <= 0;','CONFIG_EMPTY'),
        ('boundary-packet-span',"bridge_addr[23:1] == 23'h7fffff", "1'b0",'FAIL_CLOSED'),
        ('high-address-alias',"bridge_addr[27:24] != 0", "bridge_addr[27:25] != 0",'FAIL_CLOSED'),
    ]
    for name,old,new,signature in mutations:
        text=rtl.read_text()
        if old not in text: raise AssertionError('mutation target missing: '+name)
        mutated=out/(name+'.sv');mutated.write_text(text.replace(old,new))
        exe=out/name
        run(name+'-compile',['iverilog','-g2012','-s','tb_rom_download_queue','-o',exe,mutated,unit,a.altera_mf],expected=None)
        run(name,['vvp',exe],expected=signature,fail=True)
    save_mutations=[
        ('save-config', 'if (write_en && config_pending) begin',
         'if (config_pending) begin', 'SAVE_CONFIG'),
        ('save-begin-fence', 'holding_save && !image_begin && sink_reset_sync[1]',
         'holding_save && sink_reset_sync[1]', 'BEGIN_FENCE'),
        ('save-span', "bridge_addr[16:1] == 16'hffff", "1'b0", 'FAIL_CLOSED'),
        ('save-high-alias', 'bridge_addr[27:17] != 0', 'bridge_addr[27:18] != 0', 'FAIL_CLOSED'),
        ('save-pending', '(!fifo_empty || holding || holding_fence || image_begin || fault)',
         '(sink_open || fault)', 'PENDING'),
        ('every-begin', 'sink_open <= 1; image_begin <= 1;',
         'sink_open <= 1; image_begin <= !have_image;', 'QUEUED_BEGIN'),
    ]
    for name,old,new,signature in save_mutations:
        text=rtl.read_text()
        if old not in text: raise AssertionError('mutation target missing: '+name)
        mutated=out/(name+'.sv');mutated.write_text(text.replace(old,new))
        exe=out/name
        run(name+'-compile',['iverilog','-g2012','-s','tb_unified_download_queue','-o',exe,mutated,unified,a.altera_mf],expected=None)
        run(name,['vvp',exe],expected=signature,fail=True)
    fence_mutations=[
        ('fence-source-arm', 'source_reset_sync[1] && source_armed && !source_fault',
         'source_reset_sync[1] && !source_fault', 'FENCE_ARM'),
        ('fence-empty-level', 'holding_fence && !holding && !image_begin && save_read_quiescent',
         '!holding && fifo_empty && save_read_quiescent && read_ack_toggle != read_request_toggle', 'FENCE_EARLY'),
        ('fence-physical', '&& save_read_quiescent) begin', '&& 1\'b1) begin', 'FENCE_PHYSICAL'),
        ('fence-stale-ack', 'read_ready && !read_event && source_reset_sync[1]',
         'read_ready && source_reset_sync[1]', 'FENCE_STALE'),
        ('fence-lost-ack', 'read_ack_toggle <= ~read_ack_toggle;',
         'read_ack_toggle <= read_ack_toggle;', 'FENCE_TIMEOUT'),
        ('fence-duplicate', '(read_event && read_pending)', "1'b0", 'FENCE_DUPLICATE'),
    ]
    for name,old,new,signature in fence_mutations:
        text=rtl.read_text()
        if old not in text: raise AssertionError('mutation target missing: '+name)
        mutated=out/(name+'.sv');mutated.write_text(text.replace(old,new))
        exe=out/name
        run(name+'-compile',['iverilog','-g2012','-s','tb_download_read_fence','-o',exe,mutated,fence,a.altera_mf],expected=None)
        run(name,['vvp',exe],expected=signature,fail=True)
    if not a.unit_only:
        for pal in (0,1):
            sim('queue-backend-'+('pal' if pal else 'ntsc'),backend,[rtl,*integration],
                'tb_rom_download_backend',[f'-Ptb_rom_download_backend.PAL={pal}'])
            sim('save-fault-recovery-'+('pal' if pal else 'ntsc'),recovery,[rtl,*integration],
                'tb_unified_download_fault_recovery',[f'-Ptb_unified_download_fault_recovery.PAL={pal}'])
        cart_source=integration[0].read_text()
        cart_mutations=[
            ('failed-save-head-block', 'assign host_quiescent=client_flush && client_flush_ack && all_transport_idle &&',
             'assign host_quiescent=client_flush && client_flush_ack && all_transport_idle && !fault &&', 'FAULT_SAVE_HEAD_BLOCK'),
            ('save-clears-cart-fault', 'if(soft_reset) flush_hold<=1;',
             'if(soft_reset) begin flush_hold<=1; fault<=0; end', 'SAVE_AUTHORITY'),
        ]
        for name,old,new,signature in cart_mutations:
            if old not in cart_source: raise AssertionError('cart mutation target missing: '+name)
            mutated=out/(name+'.sv');mutated.write_text(cart_source.replace(old,new))
            exe=out/name
            run(name+'-compile',['iverilog','-g2012','-s','tb_unified_download_fault_recovery','-o',exe,rtl,mutated,*integration[1:],recovery,a.altera_mf],expected=None)
            run(name,['vvp',exe],expected=signature,fail=True)
    finished = True
finally:
    stable = source_hashes == {str(f.resolve()):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
    checks.append(dict(name='source-stable-during-run',passed=stable))
    (out/'summary.json').write_text(json.dumps(dict(finished=finished,checks=checks,sources_sha256=source_hashes,
        boundaries=['Actual Intel vendor CDC FIFO simulation, production queue/cart/CDC/SDRAM engine',
                    'Independent pin address/data/count scoreboard; no full SDRAM timing model in this bench',
                    'Continuous APF contract: one 32-bit packet per >=75 clk74 cycles; bounded bursts tested',
                    'BEGIN carries immutable 17-bit config; adoption requires first nonempty accepted word',
                    'Unified 512x79 FIFO orders ROM/Save/BEGIN/END; independent Save preserves ROM/config authority',
                    'Whole 32-bit packet checked before enqueue against 16 MiB ROM / 128 KiB Save limits',
                    'Per-request source ack follows an ordered READ_FENCE and separate sink physical barrier',
                    'Save destination frontier/quiescence and actual Intel RAM validation are separate integration tests',
                    'Native unit map is separate; no full fit/STA or hardware validation']),indent=2)+'\n')

    if not stable: raise RuntimeError('Source changed during simulation: rerun required')
