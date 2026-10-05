"""Mock-installation/harness checks only; no compiler runs or RTL evidence."""
import ast
import contextlib
import io
import os
from pathlib import Path
import resource
import shutil
import sys
import tempfile
import unittest
from unittest import mock

import tool_environment

ROOT = Path(__file__).resolve().parents[1]


class ToolEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.cloud = self.base / 'cloud'
        self.installed = self.base / 'installed/bin'
        self.installed.mkdir(parents=True)

    def executable(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('#!/bin/sh\nexit 99 # Fixture must never be executed\n')
        path.chmod(0o755)
        return path

    def fallback(self):
        self.executable(self.cloud / 'bin/verilator')
        root = self.cloud / 'root/usr/share/verilator'
        root.mkdir(parents=True)
        return root

    def environment(self, original):
        return tool_environment.tool_environment(original, cloud_tools=self.cloud)

    def test_explicit_root_is_preserved_including_empty(self):
        self.fallback()
        for root in ('/user/chosen/verilator', ''):
            with self.subTest(root=root):
                original = {'PATH': str(self.installed), 'VERILATOR_ROOT': root}
                before = original.copy()
                self.assertEqual(self.environment(original)['VERILATOR_ROOT'], root)
                self.assertEqual(original, before)

    def test_installed_verilator_wins_even_if_fallback_exists(self):
        installed = self.executable(self.installed / 'verilator')
        self.fallback()
        env = self.environment({'PATH': str(self.installed)})
        self.assertEqual(shutil.which('verilator', path=env['PATH']), str(installed))
        self.assertNotIn('VERILATOR_ROOT', env)

    def test_absent_fallback_leaves_normal_environment_unchanged(self):
        self.executable(self.installed / 'verilator')
        original = {'PATH': str(self.installed), 'OTHER': 'preserved'}
        self.assertEqual(self.environment(original), original)

    def test_existing_fallback_gets_matching_root_and_is_idempotent(self):
        root = self.fallback()
        env = self.environment({'PATH': str(self.installed)})
        self.assertEqual(shutil.which('verilator', path=env['PATH']), str(self.cloud / 'bin/verilator'))
        self.assertEqual(env['VERILATOR_ROOT'], str(root))
        self.assertEqual(self.environment(env), env)

    def test_missing_fallback_root_is_not_invented(self):
        self.executable(self.cloud / 'bin/verilator')
        self.assertNotIn('VERILATOR_ROOT', self.environment({'PATH': str(self.installed)}))

    def test_missing_path_is_supported(self):
        self.assertEqual(self.environment({}), {})

    def runner_setup(self, relative, env, arguments=()):
        """Run the actual argument/environment prefix; never enter any test job."""
        script = ROOT / relative
        nodes = []
        for node in ast.parse(script.read_text()).body:
            if isinstance(node, (ast.FunctionDef, ast.With)):
                break
            nodes.append(node)
        namespace = {'__file__': str(script), '__name__': '__runner_setup_test__'}
        argv = [str(script), '--out', str(self.base / 'output'), *map(str, arguments)]
        with mock.patch.dict(os.environ, env, clear=True), \
             mock.patch.object(tool_environment, 'CLOUD_TOOLS', self.cloud), \
             mock.patch.object(sys, 'argv', argv), \
             mock.patch.object(sys, 'path', sys.path.copy()), \
             mock.patch.object(resource, 'setrlimit'), \
             mock.patch('subprocess.run', side_effect=AssertionError('No external job allowed')), \
             mock.patch('subprocess.check_output', side_effect=AssertionError('No external job allowed')):
            exec(compile(ast.Module(body=nodes, type_ignores=[]), str(script), 'exec'), namespace)
        return namespace

    def test_both_main_runners_use_installed_explicit_and_fallback_environments(self):
        fallback_root = self.fallback()
        installed = self.executable(self.installed / 'verilator')
        empty_bin = self.base / 'empty-bin'
        empty_bin.mkdir()
        cases = [({'PATH': str(self.installed)}, None, installed),
                 ({'PATH': str(empty_bin)}, str(fallback_root), self.cloud / 'bin/verilator'),
                 ({'PATH': str(empty_bin), 'VERILATOR_ROOT': '/explicit/root'}, '/explicit/root', self.cloud / 'bin/verilator')]
        for script in ('tests/wram_timing/run.py', 'tests/aram_timing/run.py'):
            for original, root, selected in cases:
                with self.subTest(script=script, original=original):
                    env = self.runner_setup(script, original)['env']
                    self.assertEqual(env.get('VERILATOR_ROOT'), root)
                    self.assertEqual(shutil.which('verilator', path=env['PATH']), str(selected))

    def test_vendor_models_environment_and_cli_are_respected(self):
        models = ('220pack.vhd', '220model.vhd', 'altera_mf_components.vhd', 'altera_mf.vhd')
        for name in ('from-env', 'from-cli'):
            folder = self.base / name
            folder.mkdir()
            for model in models:
                (folder / model).write_text('-- Mock path fixture; not a licensed vendor model\n')
        env = {'PATH': str(self.installed), 'QUARTUS_SIM_LIB': str(self.base / 'from-env')}
        for script in ('tests/wram_timing/run.py', 'tests/wram_timing/check_spc_half_edge.py'):
            for args, expected in (((), 'from-env'), (('--vendor-sim-dir', self.base / 'from-cli'), 'from-cli')):
                with self.subTest(script=script, args=args):
                    ns = self.runner_setup(script, env, args)
                    parsed = ns.get('args', ns.get('a'))
                    self.assertEqual(parsed.vendor_sim_dir, self.base / expected)
                    if script.endswith('/run.py'):
                        # Execute only the real nested-call statement with a mock runner.
                        calls = [node for node in ast.walk(ast.parse((ROOT / script).read_text()))
                                 if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call)
                                 and node.value.args and isinstance(node.value.args[0], ast.Constant)
                                 and node.value.args[0].value == 'spc_half_edge']
                        self.assertEqual(len(calls), 1)
                        ns['run'] = mock.Mock()
                        exec(compile(ast.Module(body=calls, type_ignores=[]), script, 'exec'), ns)
                        command = ns['run'].call_args.args[1]
                        self.assertEqual(command[-2:], ['--vendor-sim-dir', self.base / expected])
        with contextlib.redirect_stderr(io.StringIO()) as stderr, self.assertRaises(SystemExit):
            self.runner_setup('tests/wram_timing/check_spc_half_edge.py', env, ('--vendor-sim-dir', self.base / 'absent'))
        self.assertIn('NOT RUN: approved Quartus vendor models absent', stderr.getvalue())


if __name__ == '__main__':
    unittest.main()
