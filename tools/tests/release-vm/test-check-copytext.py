#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""check-copytext.sh, the release test's check of copy text's own selection, against stand-ins for
busctl, journalctl, sudo and kwin_wayland: the overlay shown passes and is ended; KWin's refusal, no
answer to Start() and nothing shown fail; the lines in the system journal only (Debian) pass; a
pass whose overlay is not found or cannot be ended fails."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SHOWN = "copytext-overlay: pictures in 40 ms\ncopytext-overlay: shown in 52 ms at 1792300000000\n"
REFUSED = "copytext-overlay: no picture of DP-1 - The process is not authorized to take a screenshot\n"


class CheckCopyTextTest(unittest.TestCase):
    def run_check(self, user_journal="", system_journal="", start_rc=0, pid=None):
        with tempfile.TemporaryDirectory() as directory:
            bin_dir = Path(directory)
            # The overlay's stand-in: a real process the check must end by the PID the bus gives.
            overlay = subprocess.Popen(["sleep", "60"])
            named = overlay.pid if pid is None else pid
            stubs = {
                "busctl": f"""case "$*" in
  *" Start"*) exit {start_rc} ;;
  *GetConnectionUnixProcessID*) [ -n "{named}" ] && echo "u {named}" || exit 1 ;;
esac""",
                "journalctl": f"""case " $* " in
  *" --user "*) printf '%s' {user_journal!r} ;;
  *) printf '%s' {system_journal!r} ;;
esac""",
                "sudo": '[ "$1" = -n ] && shift; exec "$@"',
                "kwin_wayland": "echo 'kwin 6.8.0'",
                "sleep": "exit 0",
            }
            for name, body in stubs.items():
                path = bin_dir / name
                path.write_text("#!/bin/sh\n" + body + "\n")
                path.chmod(0o755)
            result = subprocess.run(["bash", str(HERE / "check-copytext.sh")], capture_output=True, text=True,
                                    env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"})
            try:
                ended = overlay.wait(timeout=5) is not None
            except subprocess.TimeoutExpired:
                overlay.kill()
                ended = False
            return result, ended

    def test_shown_passes_and_ends_the_overlay(self):
        result, ended = self.run_check(user_journal=SHOWN)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout.splitlines()[-1], "overlay shown on kwin 6.8.0: shown in 52 ms")
        self.assertTrue(ended)

    def test_system_journal_only_passes(self):
        result, ended = self.run_check(system_journal=SHOWN)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(ended)

    def test_kwin_refusal_fails(self):
        result, ended = self.run_check(user_journal=REFUSED)
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL: KWin gave the overlay no pictures (kwin 6.8.0)", result.stdout)
        self.assertTrue(ended)

    def test_no_answer_to_start_fails(self):
        result, _ = self.run_check(user_journal=SHOWN, start_rc=1)
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL: Start() not answered", result.stdout)

    def test_overlay_not_found_fails(self):
        result, ended = self.run_check(user_journal=SHOWN, pid="")
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL: the overlay's process was not found to end it (kwin 6.8.0)", result.stdout)

    def test_overlay_not_ended_fails(self):
        # A PID of no process: kill fails.
        result, ended = self.run_check(user_journal=SHOWN, pid="2147483646")
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL: the overlay (pid 2147483646) could not be ended (kwin 6.8.0)", result.stdout)

    def test_nothing_shown_fails(self):
        result, ended = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL: the overlay did not show", result.stdout)
        self.assertTrue(ended)


if __name__ == "__main__":
    unittest.main()
