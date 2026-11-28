#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

"""Exercise the watcher with real pidfds and private stand-ins for systemd and D-Bus."""

import contextlib
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace

GATE = Path(sys.argv.pop(1)).resolve()
INVOCATION = "03b0232a571d44a97434beaf35728d52"
ENGINE = Path(__file__).resolve().parents[3] / "tools/device/gate/plasma-fusion-gate.sh"


class WatcherTest(unittest.TestCase):
    def test_only_failed_mapped_current_invocation_is_restarted(self):
        for case in ("broken", "no-applet", "healthy", "foreign", "replaced", "stopping", "unwritable",
                     "owner-after-write", "replaced-after-write", "signal-error"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                self.check_case(case, Path(tmp))

    def test_admitted_start_that_ends_before_its_service_keeps_the_copy_aside(self):
        # The ended start's SERVICE_RESULT, what the watcher saw of it first (None: it never ran),
        # the invocation that ended, and whether the next starts keep the copy aside.
        cases = {
            "crash": ("signal", None, INVOCATION, True),
            "core-dump": ("core-dump", None, INVOCATION, True),
            "exit-code": ("exit-code", None, INVOCATION, True),
            "start-timeout": ("timeout", None, INVOCATION, True),
            "stopped": ("success", None, INVOCATION, False),
            "other-start": ("signal", None, "b" * 32, False),
            "after-service": ("signal", "healthy", INVOCATION, False),
            "foreign-service": ("signal", "foreign", INVOCATION, False),
            "no-applet": ("signal", "no-applet", INVOCATION, False),
        }
        for case, (result, watched, ended, blocked) in cases.items():
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                self.check_stop(Path(tmp), result, watched, ended, blocked)

    def check_stop(self, base, result, watched, ended, blocked):
        fx = self.fixture(base)
        with self.fake_shell(fx, fx.db if watched == "no-applet" else fx.payload) as shell:
            admitted = subprocess.run(fx.launch, env=fx.env, capture_output=True, text=True, timeout=5)
            self.assertEqual(admitted.returncode, 0, admitted.stderr)
            if watched:
                watcher_env = dict(fx.env, CASE=watched, FIXTURE_PID=str(shell.pid),
                                   UNIT_INVOCATION=INVOCATION, UNIT_JOB="0",
                                   NOTIFY_OWNED="true" if watched != "no-applet" else "false",
                                   NOTIFY_PID=str(shell.pid if watched == "healthy" else os.getpid()))
                watch = subprocess.run([fx.watcher, INVOCATION], env=watcher_env, capture_output=True,
                                       text=True, timeout=5)
                self.assertEqual(watch.returncode, 0, watch.stderr)
                self.assertIsNone(shell.poll(), "the watcher stopped a shell it should leave alone")
        stop = subprocess.run([fx.watcher, "--stopped"],
                              env=dict(fx.env, INVOCATION_ID=ended, SERVICE_RESULT=result),
                              capture_output=True, text=True, timeout=5)
        self.assertEqual(stop.returncode, 0, stop.stderr)
        verdict = fx.internal / "qml-failed"
        after = subprocess.run(fx.launch, env=fx.env, capture_output=True, text=True, timeout=5)
        if not blocked:
            self.assertFalse(verdict.exists())
            self.assertEqual(after.returncode, 0, after.stderr)
            return
        self.assertEqual(verdict.read_text().splitlines()[1:], [INVOCATION])
        self.assertNotEqual(after.returncode, 0)
        self.assertEqual(after.stdout, "")
        fx.db.write_text("different transaction")
        again = subprocess.run(fx.launch, env=fx.env, capture_output=True, text=True, timeout=5)
        self.assertEqual(again.returncode, 0, again.stderr)

    def test_an_earlier_start_cannot_take_a_later_start_s_settlement(self):
        # Start A's watcher is still polling when A has ended, B was admitted and B's watcher
        # recorded B as settled; A's watcher then sees an owner and records A. B's later crash
        # must still find B settled.
        later = "b" * 32
        with tempfile.TemporaryDirectory() as tmp:
            fx = self.fixture(Path(tmp))
            owned = Path(tmp) / "owned"
            owned.write_text("false")
            with self.fake_shell(fx, fx.payload) as shell_a, \
                    self.fake_shell(fx, fx.payload, later) as shell_b:
                self.assertEqual(subprocess.run(fx.launch, env=fx.env, capture_output=True, timeout=5).returncode, 0)
                watcher_a = subprocess.Popen(
                    [fx.watcher, INVOCATION],
                    env=dict(fx.env, CASE="earlier", FIXTURE_PID=str(shell_a.pid), UNIT_INVOCATION=INVOCATION,
                             UNIT_JOB="0", NOTIFY_OWNED="false", NOTIFY_OWNED_FILE=str(owned),
                             NOTIFY_PID=str(shell_b.pid), PF_NOTIFICATIONS_WATCH_SECONDS="8"),
                    stderr=subprocess.PIPE, text=True)
                try:
                    polled = Path(f"{owned}.polled")
                    deadline = time.monotonic() + 5
                    while not polled.exists() and watcher_a.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.05)
                    self.assertTrue(polled.exists(), "start A's watcher never reached its wait for the service")
                    later_env = dict(fx.env, INVOCATION_ID=later)
                    self.assertEqual(subprocess.run(fx.launch, env=later_env, capture_output=True, timeout=5).returncode, 0)
                    watch_b = subprocess.run(
                        [fx.watcher, later],
                        env=dict(later_env, CASE="later", FIXTURE_PID=str(shell_b.pid), UNIT_INVOCATION=later,
                                 UNIT_JOB="0", NOTIFY_OWNED="true", NOTIFY_PID=str(shell_b.pid)),
                        capture_output=True, text=True, timeout=5)
                    self.assertEqual(watch_b.returncode, 0, watch_b.stderr)
                    owned.write_text("true")
                    self.assertEqual(watcher_a.wait(timeout=10), 0)
                finally:
                    if watcher_a.poll() is None:
                        watcher_a.kill()
                    _, errors_a = watcher_a.communicate()
                self.assertIn("different owner", errors_a)
            stop = subprocess.run([fx.watcher, "--stopped"],
                                  env=dict(fx.env, INVOCATION_ID=later, SERVICE_RESULT="signal"),
                                  capture_output=True, text=True, timeout=5)
            self.assertEqual(stop.returncode, 0, stop.stderr)
            self.assertFalse((fx.internal / "qml-failed").exists())
            self.assertEqual(subprocess.run(fx.launch, env=fx.env, capture_output=True, timeout=5).returncode, 0)

    def test_no_copy_without_a_recorded_admission(self):
        # Neither the watcher nor the stop step can act for a start whose admission was not
        # recorded, so such a start stays on stock.
        with tempfile.TemporaryDirectory() as tmp:
            fx = self.fixture(Path(tmp))
            (fx.internal / "admitted").mkdir(parents=True)
            (fx.internal / "admitted/occupied").write_text("")
            refused = subprocess.run(fx.launch, env=fx.env, capture_output=True, text=True, timeout=5)
            self.assertNotEqual(refused.returncode, 0)
            self.assertEqual(refused.stdout, "")

    def test_no_copy_for_a_managed_start_without_a_package_identity(self):
        # Without the RPM database's stamp the selector neither checks a verdict nor records the
        # admission, so recovery could not act for that start.
        with tempfile.TemporaryDirectory() as tmp:
            fx = self.fixture(Path(tmp))
            fx.db.unlink()
            refused = subprocess.run(fx.launch, env=fx.env, capture_output=True, text=True, timeout=5)
            self.assertNotEqual(refused.returncode, 0)
            self.assertEqual(refused.stdout, "")

    @contextlib.contextmanager
    def fake_shell(self, fx, mapped, invocation=INVOCATION):
        """A process that maps MAPPED, standing in for the shell the unit started."""
        with subprocess.Popen(
            [sys.executable, "-c",
             "import mmap, sys; "
             "f = open(sys.argv[1], 'rb'); m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ); "
             "print('ready', flush=True); sys.stdin.buffer.read()",
             str(mapped)],
            env=dict(fx.env, INVOCATION_ID=invocation), stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        ) as shell:
            try:
                self.assertEqual(shell.stdout.readline(), "ready\n")
                yield shell
            finally:
                if shell.poll() is None:
                    shell.terminate()
                    shell.wait(timeout=3)

    def fixture(self, base):
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
            "if [[ $CASE == replaced-after-write ]] && "
            "{ [[ -f $XDG_STATE_HOME/plasma-fusion/notifications/qml-failed ]] || "
            "compgen -G \"$XDG_STATE_HOME/plasma-fusion/notifications/.qml-failed.*\" >/dev/null; }; then\n"
            "  UNIT_INVOCATION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
            "fi\n"
            "printf 'ActiveState=active\\nSubState=running\\nMainPID=%s\\nRestart=on-failure\\n"
            "InvocationID=%s\\nJob=%s\\n' \"$FIXTURE_PID\" \"$UNIT_INVOCATION\" \"$UNIT_JOB\"\n"
        )
        busctl = bin_dir / "busctl"
        busctl.write_text(
            "#!/bin/bash\n"
            "if [[ $CASE == owner-after-write ]] && "
            "{ [[ -f $XDG_STATE_HOME/plasma-fusion/notifications/qml-failed ]] || "
            "compgen -G \"$XDG_STATE_HOME/plasma-fusion/notifications/.qml-failed.*\" >/dev/null; }; then\n"
            "  NOTIFY_OWNED=true\n"
            "fi\n"
            "case \"$*\" in\n"
            "  *'GetConnectionUnixProcessID s org.kde.plasmashell') echo \"u $FIXTURE_PID\" ;;\n"
            "  *'GetConnectionUnixProcessID s org.freedesktop.Notifications') echo \"u $NOTIFY_PID\" ;;\n"
            "  *'NameHasOwner s org.freedesktop.Notifications')\n"
            "    if [[ -n ${NOTIFY_OWNED_FILE:-} ]]; then\n"
            "      : >\"$NOTIFY_OWNED_FILE.polled\"\n"
            "      NOTIFY_OWNED=$(<\"$NOTIFY_OWNED_FILE\")\n"
            "    fi\n"
            "    echo \"b $NOTIFY_OWNED\" ;;\n"
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
        return SimpleNamespace(
            env=env, db=db, payload=payload,
            launch=[GATE / "plasma-fusion-notifications-select"],
            watcher=GATE / "plasma-fusion-notifications-watch",
            internal=base / "state/plasma-fusion/notifications",
        )

    def check_case(self, case, base):
        fx = self.fixture(base)
        env, db, launch, watcher, internal = fx.env, fx.db, fx.launch, fx.watcher, fx.internal
        with self.fake_shell(fx, fx.payload if case != "no-applet" else db) as shell:
            admitted = subprocess.run(launch, env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(admitted.returncode, 0, admitted.stderr)
            if case == "unwritable":
                (internal / "qml-failed").mkdir()
            watcher_env = dict(env, CASE=case, FIXTURE_PID=str(shell.pid),
                               UNIT_INVOCATION=INVOCATION if case != "replaced" else "a" * 32,
                               UNIT_JOB="44" if case == "stopping" else "0",
                               NOTIFY_OWNED="true" if case in ("healthy", "foreign") else "false",
                               NOTIFY_PID=str(shell.pid if case == "healthy" else os.getpid()))
            try:
                cmd = [watcher, INVOCATION]
                if case == "signal-error":
                    cmd = [sys.executable, "-c", """
import runpy, signal, sys
def fail(*args):
    raise PermissionError("intentional pidfd failure")
signal.pidfd_send_signal = fail
sys.argv.pop(0)
runpy.run_path(sys.argv[0], run_name="__main__")
""", *cmd]
                result = subprocess.run(cmd, env=watcher_env, capture_output=True, text=True,
                                        timeout=5)
            except FileNotFoundError:
                self.fail("missing watcher executable")
            self.assertEqual(result.returncode, 0, result.stderr)
            if case != "broken":
                self.assertIsNone(shell.poll(), f"{case}: watcher stopped the shell")
                self.assertFalse((internal / "qml-failed").is_file())
                self.assertEqual(list(internal.glob(".qml-failed.*")), [])
                return

            self.assertEqual(shell.wait(timeout=3), -signal.SIGUSR2)
            self.assertTrue((internal / "qml-failed").is_file())
            blocked = subprocess.run(launch, env=env, capture_output=True, text=True, timeout=5)
            self.assertNotEqual(blocked.returncode, 0)
            self.assertEqual(blocked.stdout, "")
            db.write_text("different transaction")
            restored = subprocess.run(launch, env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(restored.returncode, 0, restored.stderr)


if __name__ == "__main__":
    unittest.main()
