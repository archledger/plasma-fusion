#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""A failing real vmtest entrypoint must release its mocked VM resource and preserve evidence."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
BOUNDARY = r'''#!/bin/bash
set -eu
cmd=$1; name=$2; shift 2
echo "$cmd" >>"$PF_VM_HOME/calls"
case "$cmd" in
  start) printf overlay >"$PF_VM_HOME/vms/$name/run.qcow2" ;;
  wait) [ "$FAULT" != wait ] ;;
  stop|shot) exit 0 ;;
  ssh)
    case "$*" in
      *tty1_session*) n=$(cat "$PF_VM_HOME/session" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$PF_VM_HOME/session"; echo "$n" ;;
      'python3 -')
        n=$(cat "$PF_VM_HOME/counts" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$PF_VM_HOME/counts"
        if { [ "$FAULT" = first ] && [ "$n" = 1 ]; } || { [ "$FAULT" = final ] && [ "$n" = 2 ]; }; then exit 9; fi
        echo 0 ;;
    esac ;;
esac
'''


class VMCleanupTest(unittest.TestCase):
    def run_vm(self, fault):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for filename in ["vmtest.sh", "crash-count.py"]:
                shutil.copy2(HERE / filename, root / filename)
            (root / "vm.sh").write_text(BOUNDARY)
            (root / "vms/test").mkdir(parents=True)
            (root / "bin").mkdir()
            sleep = root / "bin/sleep"
            sleep.write_text("#!/bin/sh\nexit 0\n")
            sleep.chmod(0o755)
            result = subprocess.run(["bash", str(root / "vmtest.sh"), "test", "nix"], capture_output=True, text=True,
                env={**os.environ, "PF_VM_HOME": directory, "PF_PUBLIC": "1", "FAULT": fault,
                     "PATH": str(root / "bin") + ":" + os.environ["PATH"]})
            calls = (root / "calls").read_text().splitlines()
            return result, calls, (root / "vms/test/run.qcow2").exists(), list((root / "vms/test").glob("failed-run-*.qcow2"))

    def test_initial_crash_gate_releases_vm(self):
        result, calls, locked, preserved = self.run_vm("first")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stop", calls)
        self.assertFalse(locked)
        self.assertEqual(len(preserved), 1)

    def test_final_crash_gate_releases_vm(self):
        result, calls, locked, preserved = self.run_vm("final")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stop", calls)
        self.assertFalse(locked)
        self.assertEqual(len(preserved), 1)

    def test_wait_failure_releases_started_vm(self):
        result, calls, locked, preserved = self.run_vm("wait")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stop", calls)
        self.assertFalse(locked)
        self.assertEqual(len(preserved), 1)

    def test_success_releases_vm_and_removes_overlay(self):
        result, calls, locked, preserved = self.run_vm("none")
        self.assertEqual(result.returncode, 0)
        self.assertIn("stop", calls)
        self.assertFalse(locked)
        self.assertFalse(preserved)


if __name__ == "__main__":
    unittest.main()
