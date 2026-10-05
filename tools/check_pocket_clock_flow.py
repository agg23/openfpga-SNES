#!/usr/bin/env python3
"""Audit native normal-flow load logs and, optionally, compare a routed reference.

The reference is a clock-model-verified directory from review_msu1_postfit.py.
No Quartus invocation or DB changes are performed here.
"""
import argparse, json, pathlib, shutil
from review_msu1_postfit import compare_clock_experiment, require, sha, transfers, physical_clock_routes

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=pathlib.Path, required=True)
    p.add_argument('--log', type=pathlib.Path, required=True)
    p.add_argument('--stage', choices=['post_map','post_fit'], required=True)
    p.add_argument('--reference', type=pathlib.Path)
    a=p.parse_args(); log=a.log.read_text()
    require(f'POCKET_CLOCK_FLOW_PASS stage={a.stage}' in log, 'Missing normal-flow completion marker')
    require('Error (' not in log and 'Error:' not in log, 'Native timing query failed')
    require('Warning (332088)' not in log, 'Clock source lost its physical latency')
    require('Critical Warning (332199)' not in log, 'Rejected: -post_map silently selected fitted DB')
    require(log.count('POCKET_COUNTER_EDGES name=') == 2, 'Expected exactly two counter replacements')
    result={'stage':a.stage,'normal_read_sdc_passed':True,'log_sha256':sha(a.log)}
    if a.reference:
        require(a.stage=='post_fit','Physical path comparison requires post-fit results')
        shutil.copy2(a.log,a.output/'query.log')
        originals={}
        for path in a.reference.glob('original-*.rpt'):
            shutil.copy2(path,a.output/path.name); originals[path.name]=sha(path)
        result['reference_original_sha256']=originals
        result['versus_original']=compare_clock_experiment(a.output, ignore_sdc_source_lines=True)
        # It must reproduce the already-verified read-only experiment too.
        result['versus_readonly_experiment']={}
        for corner in ('slow85','slow0','fast85','fast0'):
            for analysis in ('setup','hold'):
                for kind in ('capture','global'):
                    file=f'common_vco_edges-{corner}-{kind}-{analysis}.rpt'
                    require(physical_clock_routes(a.output/file)==physical_clock_routes(a.reference/file),
                            f'Physical route drift from prior model experiment: {file}')
                file=f'common_vco_edges-{corner}-capture-{analysis}.rpt'
                from review_msu1_postfit import first_path
                require(first_path(a.output/file)==first_path(a.reference/file),
                        f'Timing drift from prior model experiment: {file}')
                result['versus_readonly_experiment'][f'{corner}-{analysis}']='same paths, clock arcs, skew and slack'
    (a.output/'normal-flow-validation.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'stage':a.stage,'result':'PASS','routed_reference_checked':bool(a.reference)}))
if __name__=='__main__':main()
