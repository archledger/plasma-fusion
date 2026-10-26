#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""verdict.py's rules, on made-up session results: python3 tools/tests/kwin-backport/verdict_test.py"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

VERDICT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "verdict.py")
WANT = "kwin-6.7.5-1.fc44.pf1.x86_64"
STOCK = "kwin-6.7.5-1.fc44.x86_64"
RUNS = ["stock:pending:property", "backport:pending:property", "stock:placement", "backport:placement"]


class VerdictTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.res = self.tmp.name
        self.write("images.txt", f"stock {STOCK}\nbackport {WANT}\n")
        for lane, package, value in (("stock", STOCK, "false"), ("backport", WANT, "true")):
            self.session(f"{lane}-pending", f"INFO KWin has Window.requestedGeometry: {value} ({package})\n")
            self.session(f"{lane}-placement")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, text):
        path = os.path.join(self.res, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)

    def session(self, run, extra=""):
        self.write(f"{run}/checks.txt", "INFO fusion-config rc=0\nPASS one\n" + extra + "PASS two\n")
        self.write(f"{run}/scenario.log", "+ true\nscenario rc=0\nsession rc=0\n")
        self.write(f"{run}/kwin.log", "kwin_core: a line\njs: plasmafusion-placement: restored x\n")

    def verdict(self, *runs, want=WANT):
        p = subprocess.run(
            [sys.executable, "-I", VERDICT, self.res, want, *(runs or RUNS)], capture_output=True, text=True
        )
        return p.returncode, p.stdout + p.stderr

    def summary(self):
        with open(os.path.join(self.res, "summary.json")) as f:
            return {r["run"]: r for r in json.load(f)["runs"]}

    def assertFails(self, run, words):
        rc, out = self.verdict()
        self.assertEqual(rc, 1, out)
        row = self.summary()[run]
        self.assertEqual(row["result"], "FAIL", row)
        self.assertTrue(any(words in line for line in row["failed"]), row)
        others = [r for name, r in self.summary().items() if name != run]
        self.assertTrue(all(r["result"] == "PASS" for r in others), others)

    def test_all_pass(self):
        rc, out = self.verdict()
        self.assertEqual(rc, 0, out)
        self.assertTrue(all(r["result"] == "PASS" for r in self.summary().values()))
        with open(os.path.join(self.res, "summary.md")) as f:
            self.assertIn("| backport-pending | PASS | 2 | 0 |", f.read())

    def test_failed_check(self):
        self.write("backport-placement/checks.txt", "PASS one\nFAIL 2. the memory moved\n")
        self.assertFails("backport-placement", "FAIL 2. the memory moved")

    def test_no_checks(self):
        self.write("stock-placement/checks.txt", "INFO only\n")
        rc, out = self.verdict()
        self.assertEqual(rc, 1, out)
        self.assertEqual(self.summary()["stock-placement"]["result"], "NO CHECKS")

    def test_missing_run(self):
        rc, out = self.verdict("stock:pending:property", "backport:missing")
        self.assertEqual(rc, 1, out)
        self.assertIn("no status in scenario.log", " ".join(self.summary()["backport-missing"]["failed"]))

    def test_time_limit(self):
        self.write("stock-pending/scenario.log", "session rc=124\ntime limit of 240 s reached\n")
        self.assertFails("stock-pending", "did not run to the end (session rc=124)")

    def test_scenario_failed(self):
        self.write("backport-pending/scenario.log", "scenario rc=1\nsession rc=0\n")
        self.assertFails("backport-pending", "scenario rc=1")

    def test_session_failed_after_the_scenario(self):
        self.write("stock-pending/scenario.log", "scenario rc=0\nsession rc=1\n")
        self.assertFails("stock-pending", "session rc=1")

    def test_runner_failed(self):
        self.write("stock-placement/runner-failed", "125\n")
        self.assertFails("stock-placement", "the session runner failed (status 125)")

    def test_crash_in_a_log(self):
        self.write("backport-placement/plasmashell.log", "KCrash: Application 'plasmashell' crashing... crashRecursionCounter = 2\n")
        self.assertFails("backport-placement", "plasmashell.log names a crash")

    def test_segfault_in_held_client_errors(self):
        self.write("backport-pending/held-first.err", "bash: line 1: 77 Segmentation fault (core dumped) python3\n")
        self.assertFails("backport-pending", "held-first.err names a crash")

    def test_crash_word_in_other_files_ignored(self):
        self.write("stock-placement/memory-final.rc", "KCrash: not a log\n")
        rc, out = self.verdict()
        self.assertEqual(rc, 0, out)

    def test_script_error(self):
        self.write(
            "stock-placement/kwin.log",
            "js: file:///x/plasmafusion-placement/contents/ui/main.qml:120: TypeError: Cannot read property\n",
        )
        self.assertFails("stock-placement", "1 placement script error(s)")

    def test_backport_lane_ran_stock(self):
        self.write("backport-pending/checks.txt", f"PASS one\nINFO KWin has Window.requestedGeometry: false ({STOCK})\n")
        self.assertFails("backport-pending", "did not run the backport")

    def test_backport_lane_other_build(self):
        other = "kwin-6.7.5-2.fc44.pf1.x86_64"
        self.write("backport-pending/checks.txt", f"PASS one\nINFO KWin has Window.requestedGeometry: true ({other})\n")
        self.assertFails("backport-pending", "did not run the backport")

    def test_stock_lane_ran_backport(self):
        self.write("stock-pending/checks.txt", f"PASS one\nINFO KWin has Window.requestedGeometry: true ({WANT})\n")
        self.assertFails("stock-pending", "did not run stock KWin")

    def test_stock_lane_patched_without_property(self):
        self.write("stock-pending/checks.txt", f"PASS one\nINFO KWin has Window.requestedGeometry: false ({WANT})\n")
        self.assertFails("stock-pending", "did not run stock KWin")

    def test_property_line_required(self):
        self.write("backport-pending/checks.txt", "PASS one\n")
        self.assertFails("backport-pending", "property None")

    def test_property_line_not_required(self):
        self.write("backport-placement/checks.txt", "PASS one\n")
        rc, out = self.verdict()
        self.assertEqual(rc, 0, out)

    def test_backport_image_wrong(self):
        self.write("images.txt", f"stock {STOCK}\nbackport {STOCK}\n")
        rc, out = self.verdict()
        self.assertEqual(rc, 1, out)
        rows = self.summary()
        self.assertEqual([r for r in rows if rows[r]["result"] != "PASS"], ["backport-pending", "backport-placement"])
        self.assertIn(f"the backport image holds {STOCK}, not {WANT}", rows["backport-placement"]["failed"][0])

    def test_stock_image_other_release(self):
        self.write("images.txt", f"stock kwin-6.7.5-2.fc44.x86_64\nbackport {WANT}\n")
        rc, out = self.verdict()
        self.assertEqual(rc, 1, out)
        self.assertIn(f"not {STOCK}", self.summary()["stock-placement"]["failed"][0])

    def test_no_images_record(self):
        os.remove(os.path.join(self.res, "images.txt"))
        rc, out = self.verdict()
        self.assertEqual(rc, 1, out)
        self.assertTrue(all("holds nothing" in " ".join(r["failed"]) for r in self.summary().values()))

    def dumps(self, text):
        if text is not None:
            self.write("coredumps.json", text)
        p = subprocess.run(
            [sys.executable, "-I", VERDICT, "--coredumps", self.res, WANT, *RUNS], capture_output=True, text=True
        )
        return p.returncode, self.summary().get("core dumps")

    def test_coredumps_none(self):
        rc, row = self.dumps("[]\n")
        self.assertEqual((rc, row["result"]), (0, "PASS"), row)

    def test_coredumps_one(self):
        rc, row = self.dumps('[{"time": 1, "pid": 9, "sig": 11, "exe": "/usr/bin/kwin_wayland"}]')
        self.assertEqual((rc, row["result"]), (1, "FAIL"), row)
        self.assertIn("FAIL core dump: /usr/bin/kwin_wayland (signal 11)", row["failed"])
        self.assertTrue(all(r["result"] == "PASS" for name, r in self.summary().items() if name != "core dumps"))

    def test_coredumps_many(self):
        rc, row = self.dumps(json.dumps([{"exe": "/usr/bin/plasmashell", "sig": 6}] * 12))
        self.assertEqual((rc, row["fail"]), (1, 11), row)
        self.assertEqual(row["failed"][-1], "FAIL 2 more core dump(s)")

    def test_coredumps_report_missing_or_bad(self):
        for text in (None, "No coredumps found.\n", '{"exe": "x"}'):
            with self.subTest(text=text):
                if os.path.exists(os.path.join(self.res, "coredumps.json")):
                    os.remove(os.path.join(self.res, "coredumps.json"))
                rc, row = self.dumps(text)
                self.assertEqual((rc, row["result"]), (1, "FAIL"), row)
                self.assertIn("no readable core dump report", row["failed"][0])

    def test_coredumps_not_asked(self):
        self.write("coredumps.json", '[{"exe": "/usr/bin/kwin_wayland", "sig": 11}]')
        rc, out = self.verdict()
        self.assertEqual(rc, 0, out)
        self.assertNotIn("core dumps", self.summary())

    def test_usage(self):
        for args in (
            [],
            [self.res, WANT],
            [self.res, STOCK, "stock:pending"],
            [self.res, WANT, "other:pending"],
            [self.res, WANT, "stock:"],
            [self.res, WANT, "stock:pending:prop"],
            [self.res, WANT, "stock:pending:property:x"],
            ["--coredumps", self.res, WANT],
        ):
            p = subprocess.run([sys.executable, "-I", VERDICT, *args], capture_output=True, text=True)
            self.assertEqual(p.returncode, 2, (args, p.stdout, p.stderr))
        self.assertFalse(os.path.exists(os.path.join(self.res, "summary.json")))


if __name__ == "__main__":
    unittest.main()
