#!/usr/bin/env python3
"""Reject stale/gated lifecycle wiring using read-only source substitutions."""
import pathlib
import unittest
from unittest.mock import patch
import run as audit


class SourceContract(unittest.TestCase):
    def test_current_source_is_extracted(self):
        boundary = audit.source_contract()
        self.assertIn('host_reset_guard host_reset_sync', boundary)
        self.assertIn('wire reset = core_reset | cart_download', boundary)
        self.assertIn('assign cart_core_reset=core_reset || save_busy || ram_clear_busy;', boundary)
        self.assertIn('host_reset_s', boundary)

    def test_stale_or_wait_bound_wiring_rejected(self):
        substitutions = [
            ('rtl/mister_top/SNES.sv', 'wire reset = core_reset |', 'wire reset = core_reset | CART_READ_WAIT |'),
            ('rtl/mister_top/SNES.sv', '(USE_STANDARD_SDRAM && save_busy)', "1'b0"),
            ('rtl/mister_top/SNES.sv', 'bk_loading | ram_clear_busy |', 'bk_loading | clearing_ram |'),
            ('rtl/mister_top/SNES.sv', '.soft_reset(core_reset || save_busy || ram_clear_busy)', '.soft_reset(core_reset)'),
            ('target/pocket/core_top.sv', '.save_busy(queue_save_busy), .save_write_addr', '.save_busy(other), .save_write_addr'),
            ('target/pocket/core_top.sv', '.save_data(sd_buff_dout),.save_busy(queue_save_busy)', '.save_data(sd_buff_dout),.save_busy(other)'),
            ('target/pocket/core_top.sv', '(!ioctl_config_valid || host_reset_s)', '!ioctl_config_valid'),
            ('target/pocket/core_top.sv', '.host_reset_n(reset_n)', ".host_reset_n(1'b1)"),
            ('target/pocket/core_top.sv', '.sys_clk(clk_sys_21_48),', '.sys_clk(clk_sys_21_48 && !cart_wait),'),
            ('target/pocket/core_top.sv', '.clk_audio(clk_sys_21_48)', '.clk_audio(clk_sys_21_48 && !cart_wait)'),
            ('rtl/memory_ready/sdram_cart_port.sv', 'assign client_flush=soft_reset ||', 'assign client_flush=req_ready || soft_reset ||'),
        ]
        real_read = pathlib.Path.read_text
        for relative, old, new in substitutions:
            with self.subTest(source=relative, mutation=new):
                target = audit.ROOT / relative
                original = real_read(target)
                self.assertIn(old, original)
                def substituted(path, *args, **kwargs):
                    return original.replace(old, new) if path == target else real_read(path, *args, **kwargs)
                with patch.object(pathlib.Path, 'read_text', substituted):
                    with self.assertRaises(AssertionError):
                        audit.source_contract()


if __name__ == '__main__':
    unittest.main()
