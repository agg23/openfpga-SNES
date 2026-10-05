#!/usr/bin/env python3
"""CL3 external boundary requirements; deliberately no invented PCB/route delays.

A numeric result is conditional on a supplied JSON measurement/extraction record.
This tool never creates clocks, applies SDC exceptions or declares board signoff.
See docs/standard-sdram-clocks.md for the routed-boundary definitions.
"""
import argparse
import json
import math
from pathlib import Path

FREQUENCIES={'ntsc':107.386350,'pal':106.406850}
DEVICE={'cl3_period_min_ns':6.0,'read_access_max_ns':5.5,'read_hold_min_ns':2.5,
        'input_setup_ns':2.0,'input_hold_ns':1.0}
SOURCE='https://www.alliancememory.com/wp-content/uploads/20180115_AllianceMemory_512M_LPSDRAM_AS4C32M16MSA-6BINTR_rev1.0_Dec2017.pdf'

def finite(value,name):
    if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value):
        raise ValueError(name+' must be a finite number')
    return float(value)

def calculate(region,device=None,routed=None):
    specs={**DEVICE,**(device or {})}
    if set(specs)!=set(DEVICE):raise ValueError('Unknown device timing key')
    for key,value in specs.items():
        if finite(value,key)<0:raise ValueError(key+' cannot be negative')
    period=1000/FREQUENCIES[region]
    out={'region':region,'frequency_mhz':FREQUENCIES[region],'period_ns':period,
         'device_timing_ns':specs,'default_device_source':SOURCE,
         'cl3_period_requirement_met':period>=specs['cl3_period_min_ns'],
         'edge_contract':'command launch at engine posedge; SDRAM rising at next engine falling; CL3 capture at READ launch plus 4 engine cycles',
         'read_R_min_required_before_ff_hold_and_uncertainty_ns':period/2-specs['read_hold_min_ns'],
         'read_R_max_allowed_before_ff_setup_and_uncertainty_ns':1.5*period-specs['read_access_max_ns'],
         'command_or_write_W_min_required_before_uncertainty_ns':specs['input_hold_ns']-period/2,
         'command_or_write_W_max_allowed_before_uncertainty_ns':period/2-specs['input_setup_ns'],
         'read_R_definition':'forwarded FPGA clock path + PCB clock flight + PCB DQ return + FPGA DQ input path - capture clock insertion',
         'output_W_definition':'launch clock insertion + FF clock-to-Q + FPGA output path + PCB command/write flight - forwarded FPGA clock path - PCB clock flight',
         'unmeasured_requirements':['Real routed clock/input/output extrema at all PVT corners',
             'PCB flight-time extrema and skew', 'Capture FF setup and hold requirements',
             'Clock uncertainty and reference-clock tolerance', 'DQ output-enable/disable and device tHZ bus-turnaround margins',
             'Forwarded-clock pulse width, duty, jitter and device min-period checks'],
         'board_assumptions':'NONE; numeric PCB, routing and FF requirements have no defaults',
         'status':'NOT_BOARD_SIGNOFF'}
    if routed is None:return out
    if not isinstance(routed.get('evidence'),str) or not routed['evidence'].strip():raise ValueError('A route/board evidence description is required')
    if set(routed)-{'evidence','setup_uncertainty_ns','hold_uncertainty_ns','read','command','write'}:raise ValueError('Unknown routed-budget field')
    us=finite(routed['setup_uncertainty_ns'],'setup uncertainty'); uh=finite(routed['hold_uncertainty_ns'],'hold uncertainty')
    if us<0 or uh<0:raise ValueError('Uncertainty cannot be negative')
    evaluations={}
    if 'read' in routed:
        read=routed['read']
        if set(read)!={'R_min_ns','R_max_ns','capture_ff_setup_ns','capture_ff_hold_ns'}:raise ValueError('Incomplete or unknown read boundary fields')
        v={k:finite(x,k) for k,x in read.items()}
        if v['R_min_ns']>v['R_max_ns']:raise ValueError('R_min exceeds R_max')
        evaluations['read']={'conditional_setup_slack_ns':1.5*period-specs['read_access_max_ns']-v['R_max_ns']-v['capture_ff_setup_ns']-us,
                             'conditional_hold_slack_ns':v['R_min_ns']+specs['read_hold_min_ns']-period/2-v['capture_ff_hold_ns']-uh}
    for group in ['command','write']:
        if group not in routed:continue
        if set(routed[group])!={'W_min_ns','W_max_ns'}:raise ValueError('Incomplete or unknown '+group+' fields')
        lo=finite(routed[group]['W_min_ns'],group+' W_min'); hi=finite(routed[group]['W_max_ns'],group+' W_max')
        if lo>hi:raise ValueError('W_min exceeds W_max')
        evaluations[group]={'conditional_setup_slack_ns':period/2-specs['input_setup_ns']-hi-us,
                            'conditional_hold_slack_ns':period/2+lo-specs['input_hold_ns']-uh}
    if not evaluations:raise ValueError('No measured read, command or write boundary supplied')
    out['conditional_evaluations']=evaluations;out['supplied_evidence']=routed['evidence']
    out['supplied_route_budget']=routed
    # Even positive arithmetic margins omit separately listed boundary checks.
    out['status']='CONDITIONAL_ARITHMETIC_ONLY_NOT_BOARD_SIGNOFF'
    return out

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--region',choices=FREQUENCIES,default='ntsc')
    p.add_argument('--device-timing-json',type=Path,help='Explicit override of published device timing assumptions')
    p.add_argument('--routed-budget-json',type=Path,help='Measured/extracted R/W extrema with provenance; no example values are assumed')
    a=p.parse_args()
    try:
        result=calculate(a.region,json.loads(a.device_timing_json.read_text()) if a.device_timing_json else None,
                         json.loads(a.routed_budget_json.read_text()) if a.routed_budget_json else None)
    except (ValueError,KeyError,TypeError) as e:p.error(str(e))
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
