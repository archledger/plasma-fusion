#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""native_compare.py's rules, on made-up QtTest logs: python3 tools/tests/kwin-backport/native_compare_test.py"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

COMPARE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "native_compare.py")


def log(cls, results, complete=True):
    """QtTest text output: results is [(function, tag, outcome), ...]."""
    lines = [f"********* Start testing of {cls} *********"]
    for function, tag, outcome in results:
        label = {"pass": "PASS   ", "fail": "FAIL!  ", "skip": "SKIP   ", "xfail": "XFAIL  ", "xpass": "XPASS  ",
                 "fatal": "QFATAL "}[outcome]
        lines.append(f"{label}: {cls}::{function}({tag})" + (" Compared values are not the same" if outcome == "fail" else ""))
    if complete:
        failed = sum(o in ("fail", "xpass") for _, _, o in results)
        lines.append(f"Totals: {len(results) - failed} passed, {failed} failed, 0 skipped, 0 blacklisted, 10ms")
        lines.append(f"********* Finished testing of {cls} *********")
    return "\n".join(lines) + "\n"


OK = [("initTestCase", "", "pass"), ("testA", "normal", "pass"), ("testA", "scaled2x", "pass"), ("testB", "", "pass")]


class CompareTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.stock = os.path.join(self.tmp.name, "stock")
        self.backport = os.path.join(self.tmp.name, "backport")
        self.out = os.path.join(self.tmp.name, "out")
        for d, variant in ((self.stock, "stock"), (self.backport, "backport")):
            os.makedirs(d)
            with open(os.path.join(d, "variant"), "w") as f:
                f.write(variant + "\n")

    def tearDown(self):
        self.tmp.cleanup()

    def suite(self, d, name, attempts, exit_status=None):
        """attempts: a list of log texts, one per attempt."""
        for n, text in enumerate(attempts, 1):
            with open(os.path.join(d, f"{name}.{n}.log"), "w") as f:
                f.write(text)
        if exit_status is None:
            exit_status = 0 if "FAIL!" not in attempts[-1] and "Totals:" in attempts[-1] else 1
        with open(os.path.join(d, f"{name}.exit"), "w") as f:
            f.write(f"{exit_status}\n")
        with open(os.path.join(d, f"{name}.attempts"), "w") as f:
            f.write(f"{len(attempts)}\n")

    def compare(self):
        p = subprocess.run([sys.executable, "-I", COMPARE, self.stock, self.backport, self.out], capture_output=True,
                           text=True)
        rows = {}
        if os.path.exists(os.path.join(self.out, "native-summary.json")):
            with open(os.path.join(self.out, "native-summary.json")) as f:
                rows = {r["suite"]: r for r in json.load(f)["suites"]}
        return p.returncode, rows, p.stdout + p.stderr

    def test_both_pass(self):
        self.suite(self.stock, "testX", [log("T", OK)])
        self.suite(self.backport, "testX", [log("T", OK)])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)
        self.assertEqual(rows["testX"]["result"], "PASS")
        with open(os.path.join(self.out, "native-summary.md")) as f:
            self.assertIn("| testX | PASS | 1 |", f.read())

    def test_regression_fails(self):
        bad = log("T", OK[:2] + [("testA", "scaled2x", "fail")] + OK[3:])
        self.suite(self.stock, "testX", [log("T", OK)])
        self.suite(self.backport, "testX", [bad, bad, bad])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn("T::testA: failed in 3 of 3 attempts, passed in every stock attempt (1)", rows["testX"]["failed"])

    def test_failure_also_on_stock_passes(self):
        # The 2026-10-26 case: testStackTopIfFromApplication fails on both builds, other rows each time.
        b = [log("T", OK[:2] + [("testA", "scaled2x", "fail")] + OK[3:]) for _ in range(3)]
        s = [log("T", OK[:1] + [("testA", "normal", "fail")] + OK[2:]) for _ in range(3)]
        self.suite(self.stock, "testX", s)
        self.suite(self.backport, "testX", b)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)
        self.assertEqual(rows["testX"]["tolerated"], ["T::testA: failed in 3 of 3 attempts; also on stock (3 of 3)"])

    def test_ten_stock_attempts_are_all_read(self):
        # Only the tenth stock run shows the failure: still a failure on stock too.
        b = [log("T", OK[:3] + [("testB", "", "fail")])] * 3
        s = [log("T", OK)] * 9 + [log("T", OK[:3] + [("testB", "", "fail")])]
        self.suite(self.stock, "testX", s)
        self.suite(self.backport, "testX", b)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)
        self.assertEqual(rows["testX"]["tolerated"], ["T::testB: failed in 3 of 3 attempts; also on stock (1 of 10)"])

    def test_flaky_passes(self):
        bad = log("T", OK[:3] + [("testB", "", "fail")])
        self.suite(self.stock, "testX", [log("T", OK)])
        self.suite(self.backport, "testX", [bad, log("T", OK)])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)
        self.assertEqual(rows["testX"]["tolerated"], ["T::testB: failed in 1 of 2 attempts, passed in the others"])

    def test_flaky_in_a_failed_suite_passes(self):
        fail_b = log("T", OK[:3] + [("testB", "", "fail")])
        fail_a = log("T", OK[:2] + [("testA", "scaled2x", "fail")] + OK[3:])
        self.suite(self.stock, "testX", [log("T", OK)])
        self.suite(self.backport, "testX", [fail_b, fail_a, fail_b])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)
        self.assertEqual(len(rows["testX"]["tolerated"]), 2)

    def test_backported_test_must_be_stable(self):
        new_fail = log("T", OK + [("requestedGeometryNew", "", "fail")])
        new_pass = log("T", OK + [("requestedGeometryNew", "", "pass")])
        self.suite(self.stock, "testX", [log("T", OK)])
        self.suite(self.backport, "testX", [new_fail, new_pass])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn("T::requestedGeometryNew: a backported test, failed in 1 of 2 attempts", rows["testX"]["failed"])

    def test_backported_test_passing_is_fine(self):
        self.suite(self.stock, "testX", [log("T", OK)])
        self.suite(self.backport, "testX", [log("T", OK + [("requestedGeometryNew", "", "pass")])])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)

    def test_missing_function_fails(self):
        self.suite(self.stock, "testX", [log("T", OK)])
        self.suite(self.backport, "testX", [log("T", OK[:3])])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn("T::testB ran on stock but in no backport attempt", rows["testX"]["failed"])

    def test_crash_in_every_attempt_fails(self):
        crashed = log("T", OK[:2], complete=False)
        self.suite(self.stock, "testX", [log("T", OK)])
        self.suite(self.backport, "testX", [crashed, crashed, crashed], exit_status=139)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn("every attempt crashed or timed out (3), not on stock", rows["testX"]["failed"])

    def test_crash_on_stock_too_passes(self):
        crashed = log("T", OK[:2], complete=False)
        self.suite(self.stock, "testX", [crashed, crashed, crashed], exit_status=139)
        self.suite(self.backport, "testX", [crashed, crashed, crashed], exit_status=139)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)
        self.assertIn("on stock too", rows["testX"]["tolerated"][0])

    def test_backport_crashing_earlier_than_stock_fails(self):
        self.suite(self.stock, "testX", [log("T", OK[:3], complete=False)] * 3, exit_status=139)
        self.suite(self.backport, "testX", [log("T", OK[:1], complete=False)] * 3, exit_status=139)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn("T::testA ran on stock but in no backport attempt", rows["testX"]["failed"])

    def test_unexpected_pass_counts_as_failure(self):
        self.suite(self.stock, "testX", [log("T", OK[:3] + [("testB", "", "xfail")])])
        self.suite(self.backport, "testX", [log("T", OK[:3] + [("testB", "", "xpass")])] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn("T::testB: failed in 3 of 3 attempts, passed in every stock attempt (1)", rows["testX"]["failed"])

    def test_fatal_counts_as_failure(self):
        fatal = log("T", OK[:3] + [("testB", "", "fatal")], complete=False)
        self.suite(self.stock, "testX", [log("T", OK)])
        self.suite(self.backport, "testX", [fatal, fatal, fatal], exit_status=134)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertTrue(any("T::testB: failed in 3 of 3" in line for line in rows["testX"]["failed"]), rows)

    def test_exit_without_failed_function_fails(self):
        self.suite(self.stock, "testX", [log("T", OK)])
        self.suite(self.backport, "testX", [log("T", OK)], exit_status=124)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertEqual(rows["testX"]["failed"], ["exit 124 with no failed function"])

    def test_suite_missing_on_either_side(self):
        self.suite(self.stock, "testOnlyStock", [log("T", OK)])
        self.suite(self.backport, "testOnlyBackport", [log("T", OK)])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertEqual(rows["testOnlyStock"]["failed"], ["did not run on the backport"])
        self.assertEqual(rows["testOnlyBackport"]["failed"], ["no stock run to compare with"])

    def test_nothing_ran(self):
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertEqual(rows["(none)"]["failed"], ["no suite ran"])

    def test_wrong_variant_is_a_usage_error(self):
        with open(os.path.join(self.stock, "variant"), "w") as f:
            f.write("backport\n")
        rc, rows, out = self.compare()
        self.assertEqual(rc, 2, out)
        self.assertEqual(rows, {})

    def test_usage(self):
        p = subprocess.run([sys.executable, "-I", COMPARE, self.stock], capture_output=True, text=True)
        self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main()
