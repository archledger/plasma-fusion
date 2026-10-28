#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Read failures must not turn a live monitor into a clean teardown result."""
import errno
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('monitor_pids', Path(__file__).with_name('monitor-pids.py'))
scanner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scanner)


class MonitorReadTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.proc = self.root / '123'
        self.proc.mkdir()
        (self.proc / 'cmdline').write_bytes(b'/usr/bin/gdbus\0monitor\0--system\0')
        (self.proc / 'environ').write_bytes(b'DBUS_SESSION_BUS_ADDRESS=private\0OTHER=value\0')

    def test_live_monitor(self):
        self.assertEqual(scanner.monitor_pids('private', self.root), [123])

    def test_other_or_missing_bus(self):
        self.assertEqual(scanner.monitor_pids('other', self.root), [])
        (self.proc / 'environ').write_bytes(b'OTHER=value\0')
        self.assertEqual(scanner.monitor_pids('private', self.root), [])

    def test_command_arguments_do_not_make_a_monitor(self):
        (self.proc / 'cmdline').write_bytes(b'/usr/bin/echo\0gdbus monitor\0')
        self.assertEqual(scanner.monitor_pids('private', self.root), [])

    def test_cmdline_read_error_is_fatal(self):
        self.assert_read_error('cmdline')

    def test_environment_read_error_is_fatal(self):
        self.assert_read_error('environ')

    def test_process_metadata_error_is_fatal(self):
        real_stat = Path.stat

        def stat(path, *args, **kwargs):
            if path == self.proc:
                raise PermissionError(errno.EACCES, 'injected metadata failure')
            return real_stat(path, *args, **kwargs)

        with patch.object(Path, 'stat', stat), self.assertRaises(PermissionError):
            scanner.monitor_pids('private', self.root)

    def assert_read_error(self, name):
        real_read = Path.read_bytes

        def read(path):
            if path == self.proc / name:
                raise OSError(errno.EIO, 'injected read failure')
            return real_read(path)

        with patch.object(Path, 'read_bytes', read), self.assertRaises(OSError):
            scanner.monitor_pids('private', self.root)

    def test_process_ending_during_scan_is_not_a_read_failure(self):
        def read(path):
            shutil.rmtree(self.proc)
            raise FileNotFoundError(path)

        with patch.object(Path, 'read_bytes', read):
            self.assertEqual(scanner.monitor_pids('private', self.root), [])


if __name__ == '__main__':
    unittest.main()
