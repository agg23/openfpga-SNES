#!/usr/bin/env python3
"""Require complete individual decoder state/position sets across real runs."""
import json
import sys
required = {'state':range(33),'context2[4:0]':range(32),'bit_cnt[2:0]':range(8),
            'bitplane_cnt[2:0]':range(8),'code_size[2:0]':range(8),
            'curr_bp':range(8),'out_cnt[3:0]':range(16),
            'starved_bit_counts':range(8),'starved_code_sizes':range(8)}
observed = {k:set() for k in required}
for path in sys.argv[1:]:
    data=json.load(open(path))
    for key in required: observed[key].update(data['observed_values'].get(key,[]))
for key,need in required.items():
    assert set(need)<=observed[key], f'missing {key}: {sorted(set(need)-observed[key])}'
print(json.dumps({key:sorted(v for v in values if v>=0) for key,values in observed.items()},indent=2))
