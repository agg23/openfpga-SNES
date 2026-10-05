#!/usr/bin/env python3
"""Symbolic CL2 read and command/write constraints, no guessed board numbers.
Optional measured/extracted effective R extrema include FPGA and PCB as defined
in SDRAM-IO-RESEARCH.md. Reporting slacks does not override CL2 frequency limits.
"""
import argparse,json,math
p=argparse.ArgumentParser();p.add_argument('--frequency-mhz',type=float,default=85.909080)
p.add_argument('--read-r-min-ns',type=float);p.add_argument('--read-r-max-ns',type=float)
p.add_argument('--ff-setup-ns',type=float);p.add_argument('--ff-hold-ns',type=float)
p.add_argument('--setup-uncertainty-ns',type=float);p.add_argument('--hold-uncertainty-ns',type=float)
a=p.parse_args()
if not math.isfinite(a.frequency_mhz) or a.frequency_mhz<=0:p.error("frequency must be finite and positive")
for key,value in vars(a).items():
 if value is not None and not math.isfinite(value):p.error(f"{key} must be finite")
T=1000/a.frequency_mhz
r={'frequency_mhz':a.frequency_mhz,'period_ns':T,'published_cl2_table_limit_mhz':83,'published_cl2_period_min_ns':12,
 'cl2_frequency_in_published_range':a.frequency_mhz<=83 and T>=12,
 'read_lower_R_before_FF_hold_and_uncertainty_ns':T/2-2.5,
 'read_upper_R_before_FF_setup_and_uncertainty_ns':1.5*T-6,
 'command_lower_relative_delay_before_uncertainty_ns':1-T/2,
 'command_upper_relative_delay_before_uncertainty_ns':T/2-2,
 'board_assumptions':'NONE: no numerical board delay chosen; these are requirements, not observed margins',
 'status':'NOT_BOARD_SIGNOFF'}
inputs=[a.read_r_min_ns,a.read_r_max_ns,a.ff_setup_ns,a.ff_hold_ns,a.setup_uncertainty_ns,a.hold_uncertainty_ns]
if all(v is not None for v in inputs):
 if a.read_r_min_ns>a.read_r_max_ns:p.error('R min exceeds R max')
 if a.setup_uncertainty_ns<0 or a.hold_uncertainty_ns<0:p.error('uncertainties cannot be negative')
 r['conditional_setup_slack_ns']=1.5*T-6-a.read_r_max_ns-a.ff_setup_ns-a.setup_uncertainty_ns
 r['conditional_hold_slack_ns']=a.read_r_min_ns+2.5-T/2-a.ff_hold_ns-a.hold_uncertainty_ns
elif any(v is not None for v in inputs):p.error('Provide all six measured/extracted budget arguments, or none')
print(json.dumps(r,indent=2))
