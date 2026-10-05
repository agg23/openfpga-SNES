#!/usr/bin/env python3
"""Measure real GHDL VCD stalls and reject vanished pipeline payloads."""
import argparse
import collections
import json
p = argparse.ArgumentParser()
p.add_argument('vcd')
p.add_argument('--output')
p.add_argument('--allow-no-starvation',action='store_true')
a = p.parse_args()
scopes, names, values = [], {}, {}
counts = collections.Counter()
seen = collections.defaultdict(set)
root = 'tb_sdd1_waits.'
dec = root + 'dut.sdd1.dec.'
im = root + 'dut.sdd1.im.handshake_input.'
held_names = ['bit_cnt[2:0]', 'bitplane_cnt[2:0]', 'bit_num[6:0]', 'curr_bp',
              'context2[4:0]', 'code_size[2:0]', 'state', 'left_bytes[15:0]',
              'out_data0[7:0]', 'out_data1[7:0]', 'out_cnt[3:0]', 'run2',
              'cntxt_mps[0:31]']
clock = None
starve_run = 0
max_starve = 0

def n(v, path):
    s = v.get(names.get(path, ''), 'x')
    return int(s, 2) if s and set(s) <= {'0', '1'} else -1

def examine(before, after, timestamp):
    global starve_run, max_starve
    if before.get(clock) != '0' or after.get(clock) != '1': return
    if n(before, dec+'rst_n') != 1: return
    counts['active_clock_edges'] += 1
    for sig in ['bit_cnt[2:0]', 'bitplane_cnt[2:0]', 'code_size[2:0]', 'state',
                'out_cnt[3:0]', 'context2[4:0]', 'curr_bp']:
        seen[sig].add(n(before, dec+sig))
    en, step, run2 = (n(before,dec+x) for x in ('enable','step','run2'))
    raw, ready = (n(before,dec+x) for x in ('input_req','input_ready'))
    pending, output_ready = (n(before,dec+x) for x in ('plane_pending','output_ready'))
    seen['pipeline_run2_inputreq_pending'].add((run2,raw,pending))
    if en == 0 and run2 == 1: counts['enable_pause_with_run2'] += 1
    if raw == 1 and ready == 0 and en == 1:
        counts['input_starvation_edges'] += 1
        starve_run += 1
        max_starve = max(max_starve,starve_run)
        seen['starved_bit_counts'].add(n(before,dec+'bit_cnt[2:0]'))
        seen['starved_code_sizes'].add(n(before,dec+'code_size[2:0]'))
        if n(before,im+'count') == 2: counts['empty_replacement_fifo_edges'] += 1
    else: starve_run = 0
    if pending == 1 and output_ready == 0: counts['output_backpressure_edges'] += 1
    if n(before,dec+'data_req') == 1 and en == 1: counts['byte_pops'] += 1
    if pending == 1 and output_ready == 1 and en == 1: counts['output_pair_accepts'] += 1
    if step == 0 and n(before,dec+'init') == 0 and n(after,dec+'rst_n') == 1:
        counts['pipeline_hold_edges'] += 1
        if run2 == 1: counts['pipeline_hold_with_run2'] += 1
        for sig in held_names:
            assert n(before,dec+sig) == n(after,dec+sig), f'payload changed with STEP=0 at {timestamp}: {sig}'

with open(a.vcd) as f:
    for line in f:
        parts = line.split()
        if line.startswith('$scope'): scopes.append(parts[2])
        elif line.startswith('$upscope'): scopes.pop()
        elif line.startswith('$var'): names['.'.join(scopes+[parts[4]])] = parts[3]
        elif line.startswith('$enddefinitions'): break
    clock = names[root+'clk']
    before, timestamp = {}, 0
    for line in f:
        if line.startswith('#'):
            examine(before,values,timestamp)
            before = values.copy()
            timestamp = int(line[1:])
        elif line.startswith('b'):
            value,key = line[1:].split(); values[key] = value
        elif line and line[0] in '01xXzZ': values[line[1:].strip()] = line[0].lower()
    examine(before,values,timestamp)
assert a.allow_no_starvation or counts['empty_replacement_fifo_edges'] > 0, 'no real input starvation exercised'
assert counts['enable_pause_with_run2'] > 0, 'no pending RUN2 across ENABLE pause'
assert counts['output_backpressure_edges'] > 0, 'no retained output-pair backpressure'
counts['scalar_payload_hold_comparisons'] = counts['pipeline_hold_edges']*len(held_names)
report = {'counts':dict(counts),'max_consecutive_enabled_starvation':max_starve,
    'observed_values':{k:sorted(v) for k,v in seen.items()},
    'limits':'VCD does not expose context/BITS_CTR/PREV_BP arrays; immutable-baseline output-byte comparisons check their resulting behavior.'}
text = json.dumps(report,indent=2)
print(text)
if a.output:
    with open(a.output,'w') as f: f.write(text+'\n')
