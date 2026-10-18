#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""refresh.sh against a stand-in vm.sh: a failed update fails the refresh (and the VM is stopped),
a good one passes with the versions it printed, a VM that does not exist or cannot be stopped fails,
and every VM named is refreshed. Fedora's own update runs against stand-ins for rpm, rpmdb and dnf:
the RPM database is checked, and rebuilt if it fails, before the upgrade and after it. The apt
systems' update runs against stand-ins for apt-get and dpkg-query: an index that failed to download
fails the refresh before the upgrade. Both scripts run in strict mode."""
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
  start) exit 0 ;;
  stop) case " $FAILSTOP " in *" $name "*) exit 1 ;; esac ;;
  wait) echo "$name: ssh up" ;;
  ssh) case $name in fedora*) id=fedora ;; apt-*) id=${name#apt-} ;; *) id= ;; esac
       if [ -n "$id" ]; then
         sed -e "s#^\. /etc/os-release\$#ID=$id#" -e "s#/tmp/refresh.log#$PF_VM_HOME/dnf.log#g" |
           PATH=$PF_VM_HOME/bin:$PATH bash -s
         exit
       fi
       cat >/dev/null
       case " $FAILING " in *" $name "*) echo "E: Packages were downgraded and -y was used without --allow-downgrades."; exit 1 ;; esac
       echo "plasma-workspace 6.8.0" ;;
esac
'''
# Fedora's tools in the VM: the database is broken while rpmdb-broken exists, a rebuild repairs it
# unless rpmdb-unfixable exists, and the upgrade breaks it with RPMDB=after.
TOOLS = {
    "rpm": '''echo "rpm $*" >>"$PF_VM_HOME/fedora-calls"
case "$1" in
  -qa) [ ! -e "$PF_VM_HOME/rpmdb-broken" ] ;;
  --rebuilddb) [ -e "$PF_VM_HOME/rpmdb-unfixable" ] || rm -f "$PF_VM_HOME/rpmdb-broken" ;;
  -q) shift; for p; do echo "$p-6.8.0-1.fc44"; done ;;
esac''',
    "rpmdb": '''echo "rpmdb $*" >>"$PF_VM_HOME/fedora-calls"; [ ! -e "$PF_VM_HOME/rpmdb-broken" ]''',
    "dnf": '''echo "dnf $*" >>"$PF_VM_HOME/fedora-calls"; [ "$RPMDB" != after ] || touch "$PF_VM_HOME/rpmdb-broken"''',
    # apt-get as apt 2.8 and 3.3 do it (checked in KDE neon, Debian testing and Ubuntu 26.10 with a
    # source that cannot be reached): a failed index is a warning and exit 0, an error and exit 100
    # with --error-on=any.
    "apt-get": '''echo "apt-get $*" >>"$PF_VM_HOME/apt-calls"
case " $* " in
  *" update "*) [ -n "$APT_PARTIAL" ] || exit 0
    case " $* " in
      *" --error-on=any "*) echo "E: Some index files failed to download. They have been ignored, or old ones used instead."; exit 100 ;;
      *) echo "W: Some index files failed to download. They have been ignored, or old ones used instead." ;;
    esac ;;
esac''',
    "dpkg-query": '''shift; for p; do printf '%s\t4:6.8.0\n' "$p"; done''',
}
CHECK = ["rpm -qa", "rpmdb --verifydb"]
REBUILD = ["rpm -qa", "rpm --rebuilddb", "rpm -qa", "rpmdb --verifydb"]
UPGRADE = ["dnf -y upgrade --refresh"]
VERSIONS = ["rpm -q plasma-workspace kwin kscreenlocker qt6-qtbase"]


class RefreshTest(unittest.TestCase):
    def refresh(self, names, failing="", vms=("neon", "arch"), failstop="", rpmdb="", apt_partial=""):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / "release-vm"
            root.mkdir()
            shutil.copy2(HERE / "refresh.sh", root / "refresh.sh")
            (root / "vm.sh").write_text(BOUNDARY)
            for vm in vms:
                (home / "vms" / vm).mkdir(parents=True)
            (home / "bin").mkdir()
            for tool, body in TOOLS.items():
                (home / "bin" / tool).write_text("#!/bin/sh\n" + body + "\n")
                (home / "bin" / tool).chmod(0o755)
            for state in ["broken", "unfixable"]:
                if state in rpmdb:
                    (home / f"rpmdb-{state}").touch()
            result = subprocess.run(["bash", str(root / "refresh.sh"), *names], capture_output=True, text=True,
                                    env={**os.environ, "PF_VM_HOME": directory, "FAILING": failing,
                                         "FAILSTOP": failstop, "RPMDB": rpmdb, "APT_PARTIAL": apt_partial})
            calls = (home / "calls").read_text().splitlines() if (home / "calls").exists() else []
            self.fedora = (home / "fedora-calls").read_text().splitlines() if (home / "fedora-calls").exists() else []
            self.dnf_log = (home / "dnf.log").exists()
            self.apt = (home / "apt-calls").read_text().splitlines() if (home / "apt-calls").exists() else []
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

    def test_stop_failure_fails(self):
        result, calls = self.refresh(["neon", "arch"], failstop="neon")
        self.assertEqual(result.returncode, 1)
        self.assertIn("neon: rc=1 plasma-workspace 6.8.0 refresh: could not stop neon", result.stdout)
        self.assertIn("arch: rc=0", result.stdout)

    def test_fedora_good_database(self):
        result, _ = self.refresh(["fedora44"], vms=("fedora44",))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.fedora, CHECK + UPGRADE + CHECK + VERSIONS)
        self.assertIn("fedora44: rc=0 plasma-workspace-6.8.0-1.fc44", result.stdout)
        self.assertTrue(self.dnf_log)

    def test_fedora_database_rebuilt_before_the_upgrade(self):
        result, _ = self.refresh(["fedora44"], vms=("fedora44",), rpmdb="broken")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.fedora, REBUILD + UPGRADE + CHECK + VERSIONS)
        self.assertIn("rpm database (before the upgrade): rebuilt", result.stdout)

    def test_fedora_database_rebuilt_after_the_upgrade(self):
        result, _ = self.refresh(["fedora44"], vms=("fedora44",), rpmdb="after")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.fedora, CHECK + UPGRADE + REBUILD + VERSIONS)
        self.assertIn("rpm database (after the upgrade): rebuilt", result.stdout)

    def test_fedora_unrepairable_database_fails_before_the_upgrade(self):
        result, _ = self.refresh(["fedora44"], vms=("fedora44",), rpmdb="broken unfixable")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.fedora, ["rpm -qa", "rpm --rebuilddb", "rpm -qa"])
        self.assertIn("rpm database (before the upgrade): broken", result.stdout)

    def test_apt_update_and_upgrade(self):
        for system, upgrade in [("neon", "apt-get -y -q --allow-downgrades full-upgrade"),
                                ("debian", "apt-get -y -q full-upgrade"), ("ubuntu", "apt-get -y -q full-upgrade")]:
            with self.subTest(system=system):
                result, _ = self.refresh([f"apt-{system}"], vms=(f"apt-{system}",))
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.apt, ["apt-get update -q --error-on=any", upgrade])
                self.assertIn(f"apt-{system}: rc=0 plasma-workspace\t4:6.8.0", result.stdout)

    def test_apt_index_that_failed_to_download_fails(self):
        for system in ["neon", "debian", "ubuntu"]:
            with self.subTest(system=system):
                result, _ = self.refresh([f"apt-{system}"], vms=(f"apt-{system}",), apt_partial="1")
                self.assertEqual(result.returncode, 1)
                self.assertIn(f"apt-{system}: rc=1 E: Some index files failed to download", result.stdout)
                self.assertEqual(self.apt, ["apt-get update -q --error-on=any"])

    def test_strict_mode(self):
        # The script and the update it sends to each VM (AGENTS.md: bash with set -euo pipefail).
        script = (HERE / "refresh.sh").read_text()
        self.assertIn("\nset -euo pipefail\nHERE=", script)
        self.assertIn("\nUPDATE='set -euo pipefail\n", script)

    def test_missing_vm_fails(self):
        result, _ = self.refresh(["fedora44"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("fedora44: no VM", result.stderr)


if __name__ == "__main__":
    unittest.main()
