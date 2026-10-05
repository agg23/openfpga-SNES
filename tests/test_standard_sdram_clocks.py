"""Portable fail-closed guards; native mapping is tested by probe_standard_sdram_clocks."""
from pathlib import Path
import re
import unittest
import test_pocket_clock_model as legacy
CORE=legacy.CORE

ROOT = Path(__file__).resolve().parents[1]
STANDARD = r'''
set sdram_selection {sdram}
set master [string map {mf_pllbase_inst mf_pllbase_sdram_inst} $master]
foreach clock {memory system vco} {
    foreach attribute {name master_clock master_clock_pin} {
        if {[dict exists $clocks $clock $attribute]} {
            dict set clocks $clock $attribute [string map \
                {mf_pllbase_inst mf_pllbase_sdram_inst} [dict get $clocks $clock $attribute]]
        }
    }
}
dict for {node name} $nodes {
    dict set nodes $node [string map {mf_pllbase_inst mf_pllbase_sdram_inst} $name]
}
dict set clocks memory divide_by 10
dict set clocks system divide_by 40
set name [string map {general[0] general[4]} [dict get $clocks memory name]]
dict set clocks sdram [dict replace [dict get $clocks memory] \
    name $name divide_by 8 targets target_sdram \
    master_clock_pin [string range $name 0 end-6]vco0ph\[0\]]
dict set nodes target_sdram $name
'''

class ClockEvaluation:
    evaluate=legacy.PocketClockModelTests.evaluate
    assert_rejected=legacy.PocketClockModelTests.assert_rejected

class StandardClockModelTests(ClockEvaluation, unittest.TestCase):
    def test_three_counter_edges(self):
        status, message, calls, count = self.evaluate(STANDARD)
        self.assertEqual(status, '0', message)
        self.assertEqual([c[3] for c in calls], ['1,11,21','1,41,81','1,9,17'])
        self.assertTrue(all(c[1] == 'source_vco' for c in calls))
        self.assertEqual(count, '0')

    def test_standard_counter_missing_ambiguous_and_bad_ratio(self):
        for change in ['set sdram_selection {}', 'set sdram_selection {sdram memory}']:
            self.assert_rejected(STANDARD+change, 'expected one standard SDRAM')
        for value in ['0', '-8', '8.0', 'eight', '9']:
            self.assert_rejected(STANDARD+f'dict set clocks sdram divide_by {value}',
                                 'unsupported SDRAM/system')

    def test_new_counter_gets_all_phase_source_and_duty_guards(self):
        for attribute, value in {'type':'base','phase':'1','offset':'0.001',
                'duty_cycle':'49','multiply_by':'2','is_inverted':'1',
                'edges':'{1 9 17}','edge_shifts':'{0 0 0}',
                'master_clock':'other'}.items():
            self.assert_rejected(STANDARD+f'dict set clocks sdram {attribute} {value}',
                                 'unsupported derived PLL phase/duty/master')
        self.assert_rejected(STANDARD+'dict set clocks sdram targets {}',
                             'expected one output counter target')
        self.assert_rejected(STANDARD+'dict set nodes target_sdram other',
                             'unsupported output counter/source pin identity')
        self.assert_rejected(STANDARD+'dict set clocks sdram master_clock_pin $master',
                             'unsupported output counter/source pin identity')

    def test_fifth_clock_in_legacy_wrapper_fails(self):
        self.assert_rejected('set sdram_selection {sdram}', 'unexpected fifth counter')

    def test_standard_pal_name(self):
        mutation = STANDARD + r'''
set master [string map {mf_pllbase_sdram_inst mf_pllbase_pal_sdram_inst} $master]
foreach clock {memory system sdram vco} {
    foreach attr {name master_clock master_clock_pin} {
        if {[dict exists $clocks $clock $attr]} {
            dict set clocks $clock $attr [string map {mf_pllbase_sdram_inst mf_pllbase_pal_sdram_inst} [dict get $clocks $clock $attr]]
        }
    }
}
dict for {node name} $nodes {
    dict set nodes $node [string map {mf_pllbase_sdram_inst mf_pllbase_pal_sdram_inst} $name]
}
'''
        status,message,calls,_=self.evaluate(mutation)
        self.assertEqual(status,'0',message)
        self.assertTrue(all('mf_pllbase_pal_sdram_inst' in c[0] for c in calls))

class StandardSources(unittest.TestCase):
    def test_original_four_parameter_sets_unchanged(self):
        for old,new in [('mf_pllbase','mf_pllbase_sdram'),('mf_pllbase_pal','mf_pllbase_pal_sdram')]:
            old_text=(ROOT/'target/pocket'/old/f'{old}_0002.v').read_text()
            new_text=(ROOT/'target/pocket'/new/f'{new}_0002.v').read_text()
            for key in ['fractional_vco_multiplier','reference_clock_frequency','operation_mode'] + [f'{p}{i}' for i in range(4) for p in ['output_clock_frequency','phase_shift','duty_cycle']]:
                pattern=rf'\.{key}\(([^)]+)\)'
                self.assertEqual(re.search(pattern,old_text)[1],re.search(pattern,new_text)[1],key)
            self.assertIn('.number_of_clocks(5)',new_text)

    def test_real_memory_clocks_share_one_group(self):
        text=CORE.read_text()
        groups=re.findall(r'-group\s+(?:\[get_clocks -nowarn )?\{([^}]+)\}',text)
        group=next(g for g in groups if '*[0].*|divclk' in g and 'mf_pllbase' in g)
        self.assertIn('*[1].*|divclk',group)
        self.assertIn('*[4].*|divclk',group)
        active='\n'.join(s for s in text.splitlines() if not s.lstrip().startswith('#'))
        self.assertNotIn('ic|nes',active)
        self.assertNotIn('set_false_path',active)
        self.assertNotIn('set_multicycle_path',active)


# Behavioral synthesis has no physical VCO route yet; never use this branch in STA.
PREMAP = r'''
set ::quartus(nameofexecutable) quartus_map
rename get_clock_info original_get_clock_info
proc get_clock_info {attr collection} {original_get_clock_info $attr [lindex $collection 0]}
set memory_selection {};set system_selection {};set sdram_selection {}
set behavioral_names {}
for {set i 0} {$i < 5} {incr i} {
    set name [format {ic|mp1|mf_pllbase_sdram_inst|altera_pll_i|outclk_wire[%s]} $i]
    lappend behavioral_names $name
    dict set clocks $name [dict create type generated name $name master_clock clk_74a \
        master_clock_pin [format {ic|mp1|mf_pllbase_sdram_inst|altera_pll_i|general[%s].gpll~PLL_OUTPUT_COUNTER|refclk} $i] \
        phase [expr {$i == 3 ? 89 : 0}] offset 0 duty_cycle 50 is_inverted 0 \
        period [expr {10.0+$i}] edges {} edge_shifts {}]
}
rename get_clocks get_physical_clocks
proc get_clocks {args} {
    global behavioral_names
    set query [lindex $args end]
    if {$query eq {ic|mp1|mf_pllbase*_inst|altera_pll_i|outclk_wire[0]}} {return [list [lindex $behavioral_names 0]]}
    if {$query eq {ic|mp1|mf_pllbase*_inst|altera_pll_i|outclk_wire*}} {return $behavioral_names}
    if {[lsearch -exact $behavioral_names $query] >= 0} {return [list $query]}
    return [get_physical_clocks {*}$args]
}
'''

class PremapClockGuardTests(ClockEvaluation, unittest.TestCase):
    def test_behavioral_map_preserves_native_clocks_without_replacements(self):
        status,message,calls,count=self.evaluate(PREMAP)
        self.assertEqual(status,'0',message)
        self.assertEqual(calls,[])
        self.assertEqual(count,'0')
    def test_behavioral_stage_never_used_by_postmap_sta(self):
        self.assert_rejected(PREMAP+'set ::quartus(nameofexecutable) quartus_sta',
                             'expected one memory/system PLL clock pair')
    def test_missing_behavioral_clock_fails(self):
        self.assert_rejected(PREMAP+'set behavioral_names [lrange $behavioral_names 0 3]',
                             'wrong behavioral synthesis clock count')
    def test_behavioral_phase_duty_source_guards(self):
        for attr,value in {'type':'base','master_clock':'wrong','master_clock_pin':'wrong',
                           'duty_cycle':'49','offset':'1','is_inverted':'1','phase':'1',
                           'period':'0','edges':'{1 2 3}','edge_shifts':'{0 0 0}'}.items():
            self.assert_rejected(PREMAP+f'dict set clocks [lindex $behavioral_names 4] {attr} {value}',
                                 'unsupported behavioral synthesis clock')

if __name__=='__main__':unittest.main()
