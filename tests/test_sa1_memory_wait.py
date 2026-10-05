"""Actual-source SA1/65C816 variable-latency and legacy-equivalence regression.

No commercial ROM, behavioral CPU, global ENABLE freeze or Quartus build.
Set SA1_TEST_ARTIFACTS to retain VCDs, stdout and machine-readable timing data.
"""
import collections
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SA1 = ROOT / 'rtl/upstream/chip/SA1'
BENCH = ROOT / 'tests/sa1'
BASE = 'b63f800'
CPU_PARTS = ['P65816_pkg', 'AddrGen', 'BCDAdder', 'AddSubBCD', 'ALU', 'MCode', 'P65C816']


def snapshots(path):
    """Rising-edge pre-update VCD samples, i.e. values actually sampled by RTL."""
    names, scope, state, changes = {}, [], {}, {}
    timestamp = 0
    with path.open() as stream:
        for line in stream:
            fields = line.split()
            if not fields:
                continue
            if fields[0] == '$scope':
                scope.append(fields[2])
            elif fields[0] == '$upscope':
                scope.pop()
            elif fields[0] == '$var':
                names['.'.join(scope + [fields[4].split('[')[0]])] = fields[3]
            elif fields[0] == '$enddefinitions':
                break
        clock = names['tb_sa1_actual_wait.clk']
        def sample():
            if changes.get(clock) == '1' and state.get(clock) == '0':
                result = {}
                for name, code in names.items():
                    value = state.get(code, 'x')
                    result[name.removeprefix('tb_sa1_actual_wait.')] = int(value, 2) if set(value) <= {'0', '1'} else None
                result['sys'] = timestamp / 10_000_000
                return result
        for line in stream:
            line = line.strip()
            if not line:
                continue
            if line[0] == '#':
                found = sample()
                if found is not None:
                    yield found
                state.update(changes)
                changes = {}
                timestamp = int(line[1:])
            elif line[0] in 'bB':
                value, code = line[1:].split()
                changes[code] = value
            elif line[0] in '01xXzZuUwWlLhH-':
                changes[line[1:]] = line[0]
        found = sample()
        if found is not None:
            yield found


def cpu_trace(samples):
    result = []
    for s in samples:
        if s['reset_n'] != 1 or s['dut.p65_rst_n'] != 1:
            continue
        if s['prd'] == 0 or s['pwr'] == 0:
            writing = s['pwr'] == 0
            result.append((s['sys'], s['pa'], 'W' if writing else 'R', s['pdo'] if writing else s['dut.p65_di']))
            if writing and s['pa'] == 0x13F:
                break
    return result


def metrics(samples):
    accepted, returned = {}, {}
    latency, retire_latency = collections.defaultdict(list), collections.defaultdict(list)
    iram_dma_pulses = 0
    timer_ticks_pending = 0
    nmi_sampled_while_rdy_low = False
    prior = None
    for s in samples:
        if s['qv'] == s['qr'] == 1:
            accepted[s['qo']] = s['sys']
        if s['pv'] == s['rsp_ready'] == 1:
            latency[s['po']].append(s['sys'] - accepted[s['po']])
            returned[s['po']] = accepted[s['po']]
        for owner in range(4):
            if s['dut.rom_retire'] is not None and s['dut.rom_retire'] & (1 << owner):
                if owner in returned:
                    retire_latency[owner].append(s['sys'] - returned.pop(owner))
        if s['dut.iram_we'] == 1 and 0x108 <= (s['dut.iram_a'] or 0) <= 0x10E:
            iram_dma_pulses += 1
        if prior and s['busy'] == prior['busy'] == 1 and s['pv'] == 0 and s['ss'] == 0:
            if s['dut.h_cnt'] != prior['dut.h_cnt']:
                timer_ticks_pending += 1
        if s['dut.p65c816.nmi_sync'] == 1 and s['dut.p65_en'] == 0:
            nmi_sampled_while_rdy_low = True
        prior = s
    def summarize(d):
        return {str(k): {'count': len(v), 'min_sys': min(v), 'max_sys': max(v), 'mean_sys': round(sum(v)/len(v), 4)}
                for k, v in d.items() if v}
    trace = cpu_trace(samples)
    return {'program_completion_sys': trace[-1][0], 'cpu_bus_events': len(trace),
            'iram_dma_write_pulses': iram_dma_pulses, 'timer_ticks_with_physical_read_pending': timer_ticks_pending,
            'nmi_sampled_while_rdy_low': nmi_sampled_while_rdy_low,
            'accepted_to_response': summarize(latency), 'accepted_to_retirement': summarize(retire_latency)}


class Sa1MemoryWaitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ghdl = shutil.which('ghdl')
        if not cls.ghdl:
            raise unittest.SkipTest('GHDL unavailable: real SA1/65C816 tests NOT RUN')
        cls.temporary = tempfile.TemporaryDirectory(prefix='sa1-waits-')
        cls.workspace = Path(cls.temporary.name)
        cls.work = cls.workspace / 'work'
        cls.work.mkdir()
        cls.evidence = Path(os.environ.get('SA1_TEST_ARTIFACTS', cls.workspace / 'evidence'))
        cls.evidence.mkdir(parents=True, exist_ok=True)
        cls.results = {}
        cls.flags = ['--std=08', '-fsynopsys', '--workdir=' + str(cls.work)]
        cls.analyze(*[ROOT / 'rtl/upstream/65C816' / (p+'.vhd') for p in CPU_PARTS],
                    BENCH/'sa1_primitives.vhd', SA1/'SA1DIV.vhd', SA1/'SA1RomBridge.vhd',
                    SA1/'SA1.vhd', SA1/'SA1Map.vhd')
        reference = subprocess.check_output(['git', 'show', BASE+':rtl/upstream/chip/SA1/SA1.vhd'], cwd=ROOT, text=True)
        reference = re.sub(r'\bSA1\b', 'SA1_REF', reference)
        cls.reference = cls.workspace/'SA1_reference.vhd'
        cls.reference.write_text(reference)
        cls.analyze(cls.reference, BENCH/'sa1_test_program.vhd', BENCH/'tb_sa1_actual_wait.vhd', BENCH/'tb_sa1_rom_bridge.vhd')

    @classmethod
    def tearDownClass(cls):
        (cls.evidence/'results.json').write_text(json.dumps(cls.results, indent=2)+'\n')
        cls.temporary.cleanup()

    @classmethod
    def run_ghdl(cls, action, *args, flags=None):
        return subprocess.run([cls.ghdl, action, *(flags or cls.flags), *map(str, args)], cwd=ROOT,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)

    @classmethod
    def analyze(cls, *sources):
        proc = cls.run_ghdl('-a', *sources)
        if proc.returncode:
            raise AssertionError(proc.stdout)

    def simulate(self, label, *generics, bench='tb_sa1_actual_wait', trace=False):
        args = [bench, *generics, '--assert-level=error', '--ieee-asserts=disable']
        if trace:
            args.append('--vcd='+str(self.evidence/(label+'.vcd')))
        proc = self.run_ghdl('-r', *args)
        (self.evidence/(label+'.log')).write_text(proc.stdout)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('PASS', proc.stdout)
        print(proc.stdout.strip(), flush=True)
        self.results[label] = {'passed': True, 'generics': generics, 'log': proc.stdout.strip()}
        if trace:
            samples = list(snapshots(self.evidence/(label+'.vcd')))
            self.results[label]['metrics'] = metrics(samples)
            return samples

    def test_01_bridge_owner_identity_drain(self):
        self.simulate('bridge', bench='tb_sa1_rom_bridge')

    def test_02_cycle_equivalence_and_effective_cycles(self):
        reference = self.simulate('legacy', '-gHANDSHAKE=false', '-gINTERRUPTS=false', trace=True)
        immediate = self.simulate('ready_zero', '-gINTERRUPTS=false', trace=True)
        slow = self.simulate('ready_variable_13', '-gLATENCY=13', '-gINTERRUPTS=false', '-gCONTROL_ACTIVITY=false', trace=True)
        plus_two = self.simulate('ready_extra_2', '-gRESPONSE_SYS=3', '-gINTERRUPTS=false', '-gCONTROL_ACTIVITY=false', trace=True)
        a, b, c, d = map(cpu_trace, [reference, immediate, slow, plus_two])
        self.assertEqual(a, b, 'new enabled zero-wait CPU/DMA/VBP trace is not cycle-identical to b63f800')
        self.assertEqual([x[1:] for x in a], [x[1:] for x in c], 'variable latency changed architectural bus trace')
        self.assertEqual([x[1:] for x in a], [x[1:] for x in d], 'extra two sys changed architectural bus trace')
        for key in ['ready_zero', 'ready_variable_13']:
            self.assertEqual(self.results[key]['metrics']['iram_dma_write_pulses'], 7)
        self.assertEqual(self.results['legacy']['metrics']['iram_dma_write_pulses'], 14)
        self.assertGreater(self.results['ready_variable_13']['metrics']['timer_ticks_with_physical_read_pending'], 0)
        self.results['effective_cycles'] = {'baseline_program_sys': a[-1][0], 'zero_wait_program_sys': b[-1][0],
                                             'variable_program_sys': c[-1][0], 'variable_added_sys': c[-1][0]-a[-1][0],
                                             'extra_two_response_program_sys': d[-1][0], 'extra_two_added_sys': d[-1][0]-a[-1][0]}
        print('Effective cycle evidence: '+json.dumps(self.results['effective_cycles']), flush=True)

    def test_03_real_competing_owners_interrupts_and_bank_write(self):
        self.simulate('competition_irq', '-gLATENCY=13', '-gCOMPETING_SNES=true', trace=True)
        m = self.results['competition_irq']['metrics']
        self.assertTrue(m['nmi_sampled_while_rdy_low'])
        self.assertGreater(m['timer_ticks_with_physical_read_pending'], 0)

    def test_04_real_reset_drain_each_owner(self):
        for owner in range(4):
            with self.subTest(owner=owner):
                self.simulate('reset_owner_'+str(owner), '-gLATENCY=37', '-gRESET_OWNER='+str(owner))

    def test_05_real_mount_flush_drain(self):
        for owner in range(1, 4):
            with self.subTest(owner=owner):
                self.simulate('flush_owner_'+str(owner), '-gLATENCY=37', '-gFLUSH_OWNER='+str(owner))

    def test_06_bridge_synthesizable_without_latches(self):
        proc = self.run_ghdl('--synth', 'SA1RomBridge')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.results['bridge_synthesis'] = {'passed': True, 'netlist_lines': len(proc.stdout.splitlines())}

    def test_07_negative_controls_detect_real_faults(self):
        changes = [
            ('cpu_early_retire', 'SA1.vhd', 'CPU_ROM_WAIT <= ROM_NEED(1) and not ROM_READY(1);', "CPU_ROM_WAIT <= '0';", 'actual'),
            ('dma_early_write', 'SA1.vhd', 'NDMA_EN and ROM_READY(2);', 'NDMA_EN;', 'actual'),
            ('vbp_early_refill', 'SA1.vhd', 'VBP_RUN and not SNES_ROM_SEL and ROM_READY(3);', 'VBP_RUN and not SNES_ROM_SEL;', 'actual'),
            ('snes_early_retire', 'SA1.vhd', 'ROM_SNES_WAIT <= ROM_NEED(0) and not ROM_READY(0);', "ROM_SNES_WAIT <= '0';", 'actual'),
            ('lost_byte_lane', 'SA1.vhd', 'CPU_ROM_BYTE <= ROM_BYTES(1);', "CPU_ROM_BYTE <= '0';", 'actual'),
            ('duplicate_dma_write', 'SA1.vhd', 'ROM_DMA_WRITE <= DMA_EN and EN when', 'ROM_DMA_WRITE <= DMA_EN when', 'actual'),
            ('retarget_blocked_offer', 'SA1RomBridge.vhd', 'offer_addr <= held_addr;', 'offer_addr <= ADDRS(pick*23+22 downto pick*23);', 'bridge'),
            ('accept_wrong_identity', 'SA1RomBridge.vhd', 'RSP_TAG=held_tag and RSP_EPOCH=held_epoch', "RSP_EPOCH=held_epoch", 'bridge'),
            ('reset_before_drain', 'SA1RomBridge.vhd', "if phase=OFFER then phase<=IDLE; end if;", 'phase<=IDLE;', 'bridge'),
        ]
        for name, filename, before, after, kind in changes:
            with self.subTest(mutation=name):
                text = (SA1/filename).read_text()
                self.assertEqual(text.count(before), 1)
                mutation = self.workspace/(name+'.vhd')
                mutation.write_text(text.replace(before, after))
                mutation_work = self.workspace/name
                shutil.copytree(self.work, mutation_work)
                flags = ['--std=08', '-fsynopsys', '--workdir='+str(mutation_work)]
                bench = 'tb_sa1_actual_wait' if kind=='actual' else 'tb_sa1_rom_bridge'
                sources = [mutation]
                if filename=='SA1RomBridge.vhd':
                    sources += [SA1/'SA1.vhd']
                sources += [BENCH/(bench+'.vhd')]
                analyze = self.run_ghdl('-a', *sources, flags=flags)
                self.assertEqual(analyze.returncode, 0, analyze.stdout)
                args = [bench]
                if kind=='actual': args += ['-gLATENCY=13']
                args += ['--assert-level=error', '--ieee-asserts=disable']
                proc = self.run_ghdl('-r', *args, flags=flags)
                self.assertNotEqual(proc.returncode, 0, 'mutation incorrectly passed: '+name)
                self.assertIn('assertion failure', proc.stdout, proc.stdout)
                self.results['negative_'+name] = {'detected': True, 'log': proc.stdout.strip()}
                (self.evidence/('negative_'+name+'.log')).write_text(proc.stdout)
                print('PASS negative control '+name+': '+next(x for x in proc.stdout.splitlines() if 'assertion failure' in x), flush=True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
