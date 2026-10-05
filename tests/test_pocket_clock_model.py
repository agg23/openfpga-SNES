"""Exercise normal-flow SDC guards with Tcl doubles, not Quartus timing evidence.

These tests execute the actual include and check its selection, source-edge
arithmetic, and fail-before-replacement behavior.  Native post-map and fitted
checks must separately establish API support, physical PLL behavior and latency.
"""

from pathlib import Path
import os
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "target/pocket/pocket_clock_model.sdc"
CORE = ROOT / "target/pocket/core_constraints.sdc"

FIXTURE = r"""
set prefix {ic|mp1|mf_pllbase_inst|altera_pll_i|}
set mem_name ${prefix}general\[0\].gpll~PLL_OUTPUT_COUNTER|divclk
set sys_name ${prefix}general\[1\].gpll~PLL_OUTPUT_COUNTER|divclk
set master ${prefix}general\[0\].gpll~FRACTIONAL_PLL|vcoph\[0\]
set memory_selection {memory}
set system_selection {system}
set sdram_selection {}
set vco_selection {vco}
set source_selection {source_vco}
set created {}
foreach clock {memory system} name [list $mem_name $sys_name] divisor {7 28} {
    dict set clocks $clock [dict create type generated name $name \
        master_clock $master divide_by $divisor multiply_by 1 \
        phase 0.000 offset 0.000 duty_cycle 50.00 is_inverted 0 \
        edges {} edge_shifts {} targets target_$clock \
        master_clock_pin [string range $name 0 end-6]vco0ph\[0\]]
    dict set nodes target_$clock $name
}
dict set clocks vco [dict create type generated name $master \
    phase 0.000 offset 0.000 duty_cycle 50.00 is_inverted 0 \
    edges {} edge_shifts {} targets source_vco]
dict set nodes source_vco $master
proc get_clocks {args} {
    global memory_selection system_selection sdram_selection vco_selection master
    switch -exact -- [lindex $args end] {
        {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[0].*|divclk} {
            return $memory_selection
        }
        {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[1].*|divclk} {
            return $system_selection
        }
        {ic|mp1|mf_pllbase*_inst|altera_pll_i|*[4].*|divclk} {
            return $sdram_selection
        }
        default {
            if {[lindex $args end] ne $master} {error "Unexpected clock query: $args"}
            return $vco_selection
        }
    }
}
proc get_pins {args} {
    global master source_selection
    if {[lindex $args end] ne $master} {error "Unexpected pin query: $args"}
    return $source_selection
}
proc get_collection_size {collection} {return [llength $collection]}
proc get_clock_info {attribute clock} {
    global clocks
    return [dict get $clocks $clock [string range $attribute 1 end]]
}
proc get_node_info {attribute node} {
    global nodes
    if {$attribute ne "-name"} {error "Unexpected node attribute: $attribute"}
    return [dict get $nodes $node]
}
proc create_generated_clock {args} {
    global created
    lappend created $args
}
"""

REPORT = r"""
set code [catch {source $model} message]
puts "RESULT\t$code"
puts "MESSAGE\t$message"
foreach args $created {
    set opts [lrange $args 0 end-1]
    puts [join [list CREATE [dict get $opts -name] \
        [dict get $opts -source] [dict get $opts -master_clock] \
        [join [dict get $opts -edges] ,] [lindex $args end]] "\t"]
}
puts "PROC_COUNT\t[llength [info procs pocket_align_counter_edges]]"
"""


@unittest.skipUnless(shutil.which("tclsh"), "tclsh is required")
class PocketClockModelTests(unittest.TestCase):
    def evaluate(self, mutation=""):
        # Pass the path through the environment to avoid Tcl quoting assumptions.
        script = FIXTURE + "\n" + mutation + "\nset model $env(POCKET_CLOCK_MODEL)\n" + REPORT
        result = subprocess.run(["tclsh"], input=script, capture_output=True,
                                text=True, timeout=5, check=True,
                                env={**os.environ, "POCKET_CLOCK_MODEL": str(MODEL)})
        self.assertEqual(result.stderr, "", result.stderr)
        rows = [line.split("\t") for line in result.stdout.splitlines()]
        status = next(row[1] for row in rows if row[0] == "RESULT")
        message = next(row[1] for row in rows if row[0] == "MESSAGE")
        calls = [row[1:] for row in rows if row[0] == "CREATE"]
        proc_count = next(row[1] for row in rows if row[0] == "PROC_COUNT")
        return status, message, calls, proc_count

    def assert_rejected(self, mutation, reason):
        status, message, calls, _ = self.evaluate(mutation)
        self.assertEqual(status, "1", message)
        self.assertIn(reason, message)
        self.assertEqual(calls, [], "An unsupported model must not be partially replaced")

    def test_ntsc_edges_preserve_names_source_and_targets(self):
        status, message, calls, proc_count = self.evaluate()
        self.assertEqual(status, "0", message)
        prefix = "ic|mp1|mf_pllbase_inst|altera_pll_i|"
        master = prefix + "general[0].gpll~FRACTIONAL_PLL|vcoph[0]"
        self.assertEqual(calls, [
            [prefix + "general[0].gpll~PLL_OUTPUT_COUNTER|divclk", "source_vco",
             master, "1,8,15", "target_memory"],
            [prefix + "general[1].gpll~PLL_OUTPUT_COUNTER|divclk", "source_vco",
             master, "1,29,57", "target_system"],
        ])
        self.assertEqual(proc_count, "0", "The helper must not leak its Tcl procedure")

    def test_pal_instance_and_edges(self):
        mutation = r"""
set master [string map {mf_pllbase_inst mf_pllbase_pal_inst} $master]
foreach clock {memory system vco} {
    foreach attribute {name master_clock master_clock_pin} {
        if {[dict exists $clocks $clock $attribute]} {
            dict set clocks $clock $attribute [string map \
                {mf_pllbase_inst mf_pllbase_pal_inst} [dict get $clocks $clock $attribute]]
        }
    }
}
dict for {node name} $nodes {
    dict set nodes $node [string map {mf_pllbase_inst mf_pllbase_pal_inst} $name]
}
dict set clocks memory divide_by 8
dict set clocks system divide_by 32
"""
        status, message, calls, _ = self.evaluate(mutation)
        self.assertEqual(status, "0", message)
        self.assertEqual([call[3] for call in calls], ["1,9,17", "1,33,65"])
        self.assertTrue(all("mf_pllbase_pal_inst" in call[0] for call in calls))

    def test_divisors_are_parameters_not_region_constants(self):
        for divisor in (1, 5, 10):
            with self.subTest(divisor=divisor):
                status, message, calls, _ = self.evaluate(
                    f"dict set clocks memory divide_by {divisor}\n"
                    f"dict set clocks system divide_by {4 * divisor}")
                self.assertEqual(status, "0", message)
                self.assertEqual([call[3] for call in calls], [
                    f"1,{divisor + 1},{2 * divisor + 1}",
                    f"1,{4 * divisor + 1},{8 * divisor + 1}",
                ])

    def test_reject_missing_or_ambiguous_clock_pair(self):
        for variable in ("memory_selection", "system_selection"):
            for value in ("{}", "{memory system}"):
                with self.subTest(variable=variable, value=value):
                    self.assert_rejected(f"set {variable} {value}", "expected one memory/system")

    def test_reject_unsupported_divisors(self):
        for clock, divisor in (("memory", "0"), ("memory", "-7"),
                               ("memory", "7.0"), ("memory", "seven"),
                               ("system", "28.0"), ("system", "29")):
            with self.subTest(clock=clock, divisor=divisor):
                self.assert_rejected(f"dict set clocks {clock} divide_by {divisor}",
                                     "unsupported memory/system counter ratio")

    def test_reject_unsupported_counter_attributes_before_any_write(self):
        changes = {"type": "base", "phase": "1", "offset": "0.001",
                   "duty_cycle": "49", "multiply_by": "2", "is_inverted": "1",
                   "edges": "{1 8 15}", "edge_shifts": "{0 0 0}"}
        for clock in ("memory", "system"):
            for attribute, value in changes.items():
                with self.subTest(clock=clock, attribute=attribute):
                    self.assert_rejected(f"dict set clocks {clock} {attribute} {value}",
                                         "unsupported derived PLL phase/duty/master")
        self.assert_rejected("dict set clocks system master_clock other_master",
                             "unsupported derived PLL phase/duty/master")

    def test_reject_other_pll_master(self):
        self.assert_rejected(r"""
set master [string map {mf_pllbase_inst another_pll_inst} $master]
dict set clocks memory master_clock $master
dict set clocks system master_clock $master
""", "not in the same PLL")

    def test_reject_missing_or_multiple_counter_targets(self):
        for clock in ("memory", "system"):
            for targets in ("{}", "{target_memory target_system}"):
                with self.subTest(clock=clock, targets=targets):
                    self.assert_rejected(f"dict set clocks {clock} targets {targets}",
                                         "expected one output counter target")

    def test_reject_wrong_counter_target_or_input_pin(self):
        for clock in ("memory", "system"):
            with self.subTest(clock=clock, attribute="target"):
                self.assert_rejected(f"dict set nodes target_{clock} other_target",
                                     "unsupported output counter/source pin identity")
            with self.subTest(clock=clock, attribute="source"):
                self.assert_rejected(f"dict set clocks {clock} master_clock_pin $master",
                                     "unsupported output counter/source pin identity")

    def test_reject_missing_or_ambiguous_vco_source(self):
        for variable in ("vco_selection", "source_selection"):
            for value in ("{}", "{one two}"):
                with self.subTest(variable=variable, value=value):
                    self.assert_rejected(f"set {variable} {value}",
                                         "expected one physical common VCO source")

    def test_reject_non_vco_master(self):
        self.assert_rejected(r"""
set master ${prefix}unrelated_source
dict set clocks memory master_clock $master
dict set clocks system master_clock $master
""", "expected one physical common VCO source")

    def test_reject_unsupported_vco_waveform(self):
        for attribute, value in {"duty_cycle": "49", "phase": "1",
                                 "offset": "0.001", "is_inverted": "1"}.items():
            with self.subTest(attribute=attribute):
                self.assert_rejected(f"dict set clocks vco {attribute} {value}",
                                     "unsupported common VCO waveform")

    def test_include_precedes_existing_groups_and_uncertainty(self):
        core = CORE.read_text()
        include = "source [file join [file dirname [info script]] pocket_clock_model.sdc]"
        self.assertEqual(core.count(include), 1)
        self.assertLess(core.index(include), core.index("set_clock_groups"))
        self.assertLess(core.index(include), core.index("derive_clock_uncertainty"))
        model = MODEL.read_text()
        self.assertNotIn("\nderive_clock_uncertainty", model)
        self.assertNotIn("\nderive_pll_clocks", model)


if __name__ == "__main__":
    unittest.main()
