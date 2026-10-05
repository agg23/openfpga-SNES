"""Test-only tool discovery; respect installed tools and caller configuration."""
import os
from pathlib import Path
import shutil

CLOUD_TOOLS = Path('/tmp/msu1-tools')


def tool_environment(environ=None, *, cloud_tools=None):
    """Copy the caller's environment, with an optional existing local fallback.

    A normal PATH installation wins. Never override an explicit VERILATOR_ROOT,
    and only infer the extracted package's root when that Verilator was selected.
    No tools are downloaded, installed, or executed here.
    """
    env = dict(os.environ if environ is None else environ)
    cloud = Path(CLOUD_TOOLS if cloud_tools is None else cloud_tools)
    fallback_bin = cloud / 'bin'
    path = env.get('PATH', os.defpath)
    if fallback_bin.is_dir() and str(fallback_bin) not in path.split(os.pathsep):
        path += os.pathsep + str(fallback_bin)
        env['PATH'] = path
    selected = shutil.which('verilator', path=path)
    fallback_root = cloud / 'root/usr/share/verilator'
    if 'VERILATOR_ROOT' not in env and selected and fallback_root.is_dir():
        if Path(selected).resolve() == (fallback_bin / 'verilator').resolve():
            env['VERILATOR_ROOT'] = str(fallback_root)
    return env
