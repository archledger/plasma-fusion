#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""refresh.sh against a stand-in vm.sh: a failed update fails the refresh (and the VM is stopped),
a good one passes with the versions it printed, a VM that does not exist fails, and every VM named
is refreshed."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
BOUNDARY = r'''#!/bin/bash
cmd=$1; name=$2; shift 2
echo "$cmd $name" >>"$PF_VM_HOME/calls"
case "$cmd" in
  start | stop) exit 0 ;;
  wait) echo "$name: ssh up" ;;
  ssh) cat >/dev/null
       case " $FAILING " in *" $name "*) echo "E: Packages were downgraded and -y was used without --allow-downgrades."; exit 1 ;; esac
       echo "plasma-workspace 6.8.0" ;;
esac
'''


class RefreshTest(unittest.TestCase):
    def refresh(self, names, failing="", vms=("neon", "arch")):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / "release-vm"
            root.mkdir()
            shutil.copy2(HERE / "refresh.sh", root / "refresh.sh")
            (root / "vm.sh").write_text(BOUNDARY)
            for vm in vms:
                (home / "vms" / vm).mkdir(parents=True)
            result = subprocess.run(["bash", str(root / "refresh.sh"), *names], capture_output=True, text=True,
                                    env={**os.environ, "PF_VM_HOME": directory, "FAILING": failing})
            calls = (home / "calls").read_text().splitlines() if (home / "calls").exists() else []
            return result, calls

    def test_good_refresh(self):
        result, calls = self.refresh(["neon"])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("neon: rc=0 plasma-workspace 6.8.0", result.stdout)
        self.assertEqual(calls, ["start neon", "wait neon", "ssh neon", "stop neon"])

    def test_failed_update_fails_and_stops_the_vm(self):
        result, calls = self.refresh(["neon", "arch"], failing="neon")
        self.assertEqual(result.returncode, 1)
        self.assertIn("neon: rc=1 E: Packages were downgraded", result.stdout)
        self.assertIn("arch: rc=0", result.stdout)
        self.assertIn("stop neon", calls)

    def test_missing_vm_fails(self):
        result, _ = self.refresh(["fedora44"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("fedora44: no VM", result.stderr)


if __name__ == "__main__":
    unittest.main()
