#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

"""Exercise the watcher with real pidfds and private stand-ins for systemd and D-Bus."""

import os
import signal
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GATE = Path(sys.argv.pop(1)).resolve()
INVOCATION = "03b0232a571d44a97434beaf35728d52"
ENGINE = Path(__file__).resolve().parents[3] / "tools/device/gate/plasma-fusion-gate.sh"


class WatcherTest(unittest.TestCase):
    def test_only_failed_mapped_current_invocation_is_restarted(self):
        for case in ("broken", "no-applet", "healthy", "foreign", "replaced", "stopping", "unwritable"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                self.check_case(case, Path(tmp))

    def check_case(self, case, base):
        bin_dir = base / "bin"
        bin_dir.mkdir()
        conf = base / "home/.config"
        conf.mkdir(parents=True)
        (conf / "kdeglobals").write_text("[KDE]\nLookAndFeelPackage=org.plasmafusion.dark.desktop\n")
        db = base / "sys/usr/lib/sysimage/rpm/rpmdb.sqlite"
        db.parent.mkdir(parents=True)
        db.write_text("db fixture")
        payload = base / "org.kde.plasma.notifications.so"
        payload.write_text("payload fixture")
        record = base / "record"
        record.write_text("source-plasma-workspace=6.8.3\nplasma-workspace=6.8.3\n")
        systemctl = bin_dir / "systemctl"
        systemctl.write_text(
            "#!/bin/bash\n"
            "printf 'ActiveState=active\\nSubState=running\\nMainPID=%s\\nRestart=on-failure\\n"
            "InvocationID=%s\\nJob=%s\\n' \"$FIXTURE_PID\" \"$UNIT_INVOCATION\" \"$UNIT_JOB\"\n"
        )
        busctl = bin_dir / "busctl"
        busctl.write_text(
            "#!/bin/bash\n"
            "case \"$*\" in\n"
            "  *'GetConnectionUnixProcessID s org.kde.plasmashell') echo \"u $FIXTURE_PID\" ;;\n"
            "  *'GetConnectionUnixProcessID s org.freedesktop.Notifications') echo \"u $NOTIFY_PID\" ;;\n"
            "  *'NameHasOwner s org.freedesktop.Notifications') echo \"b $NOTIFY_OWNED\" ;;\n"
            "  *) exit 9 ;;\n"
            "esac\n"
        )
        rpm = bin_dir / "rpm"
        rpm.write_text("#!/bin/bash\nprintf 'plasma-workspace=6.8.3\\n'\n")
        for shim in (systemctl, busctl, rpm):
            shim.chmod(0o755)

        env = {
            "PATH": f"{bin_dir}:/usr/bin:/bin",
            "HOME": str(conf.parent),
            "XDG_CONFIG_DIRS": str(base / "xdg"),
            "XDG_STATE_HOME": str(base / "state"),
            "PF_GATE_ROOT": str(base / "sys"),
            "PF_GATE_RPM": str(rpm),
            "PF_NOTIFICATIONS_CHECK": "/usr/bin/true",
            "PF_NOTIFICATIONS_PLUGIN": str(payload),
            "PF_NOTIFICATIONS_RECORD": str(record),
            "PF_NOTIFICATIONS_THEME_ENGINE": str(ENGINE),
            "PF_NOTIFICATIONS_WATCH_SECONDS": ".2",
            "INVOCATION_ID": INVOCATION,
        }
        launch = [GATE / "plasma-fusion-notifications-select"]
        watcher = GATE / "plasma-fusion-notifications-watch"
        internal = base / "state/plasma-fusion/notifications"
        with subprocess.Popen(
            [sys.executable, "-c",
             "import mmap, sys; "
             "f = open(sys.argv[1], 'rb'); m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ); "
             "print('ready', flush=True); sys.stdin.buffer.read()",
             str(payload if case != "no-applet" else db)],
            env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        ) as shell:
            try:
                self.assertEqual(shell.stdout.readline(), "ready\n")
                admitted = subprocess.run(launch, env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual(admitted.returncode, 0, admitted.stderr)
                if case == "unwritable":
                    (internal / "qml-failed").mkdir()
                watcher_env = dict(env, FIXTURE_PID=str(shell.pid),
                                   UNIT_INVOCATION=INVOCATION if case != "replaced" else "a" * 32,
                                   UNIT_JOB="44" if case == "stopping" else "0",
                                   NOTIFY_OWNED="true" if case in ("healthy", "foreign") else "false",
                                   NOTIFY_PID=str(shell.pid if case == "healthy" else os.getpid()))
                try:
                    result = subprocess.run([watcher, INVOCATION], env=watcher_env, capture_output=True, text=True,
                                            timeout=5)
                except FileNotFoundError:
                    self.fail("missing watcher executable")
                self.assertEqual(result.returncode, 0, result.stderr)
                if case != "broken":
                    self.assertIsNone(shell.poll(), f"{case}: watcher stopped the shell")
                    self.assertFalse((internal / "qml-failed").is_file())
                    return

                self.assertEqual(shell.wait(timeout=3), -signal.SIGUSR2)
                self.assertTrue((internal / "qml-failed").is_file())
                blocked = subprocess.run(launch, env=env, capture_output=True, text=True, timeout=5)
                self.assertNotEqual(blocked.returncode, 0)
                self.assertEqual(blocked.stdout, "")
                db.write_text("different transaction")
                restored = subprocess.run(launch, env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual(restored.returncode, 0, restored.stderr)
            finally:
                if shell.poll() is None:
                    shell.terminate()
                    shell.wait(timeout=3)


if __name__ == "__main__":
    unittest.main()
