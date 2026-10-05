#!/usr/bin/env python3
"""Summarize the actual query TSV files, retaining exact worst path endpoints."""
import argparse,csv,json,pathlib
p=argparse.ArgumentParser();p.add_argument('review',type=pathlib.Path);a=p.parse_args()
root=a.review.resolve();d={'provenance':json.loads((root/'review-provenance.json').read_text()),'corners':{},'register_locations':{},'limits':['No added timing exceptions; existing project constraints used','External SDRAM I/O delays remain unverified','Negative endpoint queries are limited to worst path per endpoint, max 1000; not an enumeration of every combinational path','No hardware validation']}
for file in sorted(root.glob('*.tsv')):
 if file.name.startswith('nodes-'):
  d['register_locations'][file.stem[6:]]=list(csv.DictReader(file.open(),delimiter='\t'))
 elif file.stem.split('-')[0] in ('slow85','slow0','fast85','fast0'):
  corner,rest=file.stem.split('-',1);label,analysis=rest.rsplit('-',1)
  rows=list(csv.DictReader(file.open(),delimiter='\t'))
  for row in rows:
   for k in ('slack','relationship','skew','data_delay','logic_levels','launch','latch'):
    if row[k]:row[k]=float(row[k])
  rows.sort(key=lambda r:r['slack'])
  d['corners'].setdefault(corner,{})[label+'-'+analysis]={'count':len(rows),'negative_count':sum(x['slack']<0 for x in rows),'worst':rows[0] if rows else None,'first12':rows[:12],'query_limit_reached':label=='negative-endpoints' and len(rows)>=1000}
(root/'summary.json').write_text(json.dumps(d,indent=2)+'\n')
for corner,queries in d['corners'].items():
 print(corner)
 for name in ('global-setup','global-hold','global-recovery','global-removal','from-msu-setup','to-msu-setup','within-msu-setup','p65-to-wram-setup','dma-to-wram-setup','to-capture-hold','to-volume-setup'):
  value=queries.get(name,{}).get('worst')
  print(name, 'NO_PATHS' if not value else f"{value['slack']:+.3f}: {value['from']} -> {value['to']}")
