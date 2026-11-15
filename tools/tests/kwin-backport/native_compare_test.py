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


def log(cls, results, complete=True, renderer=True, debug=None):
    """QtTest text output: results is [(function, tag, outcome), ...]; debug maps (function, tag) to
    kwin_core debug messages that row prints before its result."""
    lines = [f"********* Start testing of {cls} *********"]
    if renderer:
        lines.append(f"QDEBUG : {cls}::initTestCase() kwin_core: OpenGL compositing has been successfully initialized")
    for function, tag, outcome in results:
        for message in (debug or {}).get((function, tag), []):
            lines.append(f"QDEBUG : {cls}::{function}({tag}) kwin_core: {message}")
        label = {"pass": "PASS   ", "fail": "FAIL!  ", "skip": "SKIP   ", "xfail": "XFAIL  ", "xpass": "XPASS  ",
                 "fatal": "QFATAL "}[outcome]
        lines.append(f"{label}: {cls}::{function}({tag})" + (" Compared values are not the same" if outcome == "fail" else ""))
    if complete:
        failed = sum(o in ("fail", "xpass") for _, _, o in results)
        lines.append(f"Totals: {len(results) - failed} passed, {failed} failed, 0 skipped, 0 blacklisted, 10ms")
        lines.append(f"********* Finished testing of {cls} *********")
    return "\n".join(lines) + "\n"


OK = [("initTestCase", "", "pass"), ("testA", "normal", "pass"), ("testA", "scaled2x", "pass"), ("testB", "", "pass")]

# KWin's raise decision for an X11 window (Workspace::allowFullClientRaising, kwin_core debug): the
# request's time, the active window's user time, and whether a full raise is granted (time >= user
# time). A tie is upstream's timestamp race (#188): the test's windows got the same millisecond.
TIE = "Raising, compared: 1058756 : 1058756 : true"
NEWER = "Raising, compared: 1058755 : 1058756 : false"

# testX11Window's two stacking tests that the race makes fail, as in #188's runs.
X11 = "X11WindowTest"
TOP_IF = "testStackTopIfFromApplication"
ABOVE = "testStackAboveFromApplication"
X11_OK = [("initTestCase", "", "pass"), (TOP_IF, "normal", "pass"), (TOP_IF, "scaled2x", "pass"),
          (ABOVE, "normal", "pass"), (ABOVE, "scaled2x", "pass"), ("testMinimize", "", "pass")]
RACE_NOTE = "each on KWin's timestamp race (a full raise granted on equal user timestamps)"


def created(*times):
    """KWin's user time for each window the row creates (kwin_core "User timestamp, final")."""
    return [f'User timestamp, final: KWin::X11Window(0x{n + 1:x}, caption="") : {t}' for n, t in enumerate(times)]


# The race as #188's logs show it: window2 and window3 created in the same millisecond, then the
# raise granted on that time (43570629043, backport attempt 2).
RACED = created(1058755, 1058756, 1058756) + [TIE]


def raced(row="normal", messages=RACED, function=TOP_IF, cls=X11, base=X11_OK):
    """FUNCTION failing in ROW after the given raise decisions, every other row passing."""
    results = [r if r[:2] != (function, row) else (function, row, "fail") for r in base]
    return log(cls, results, debug={(function, row): list(messages)})


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

    def test_missing_renderer_evidence_fails(self):
        self.suite(self.stock, "testX", [log("T", OK)])
        self.suite(self.backport, "testX", [log("T", OK, renderer=False)])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn("backport attempt 1: no successful compositor initialization", rows["testX"]["failed"])

    def test_missing_stock_renderer_evidence_fails(self):
        self.suite(self.stock, "testX", [log("T", OK, renderer=False)])
        self.suite(self.backport, "testX", [log("T", OK)])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn("stock attempt 1: no successful compositor initialization", rows["testX"]["failed"])

    def test_renderer_failure_is_not_a_tolerated_baseline_failure(self):
        failed = log("T", OK) + "QCRITICAL: T::initTestCase() kwin_core: The used windowing system requires compositing\n"
        self.suite(self.stock, "testX", [failed])
        self.suite(self.backport, "testX", [failed])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn("backport attempt 1: compositor initialization failed", rows["testX"]["failed"])
        self.assertIn("stock attempt 1: compositor initialization failed", rows["testX"]["failed"])

    def test_legacy_qpainter_initialization_is_valid(self):
        painter = log("T", OK).replace("OpenGL compositing", "QPainter compositing")
        self.suite(self.stock, "testX", [painter])
        self.suite(self.backport, "testX", [painter])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)

    def test_healthy_retry_does_not_erase_an_unhealthy_attempt(self):
        attempts = [log("T", OK, renderer=False), log("T", OK)]
        self.suite(self.stock, "testX", attempts)
        self.suite(self.backport, "testX", attempts)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        for side in ("stock", "backport"):
            self.assertIn(f"{side} attempt 1: no successful compositor initialization",
                          rows["testX"]["failed"])

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

    def test_timestamp_race_passes(self):
        # #188's runs: testStackTopIfFromApplication failed in every backport attempt on a fast
        # runner, each time after a full raise granted on equal user timestamps; stock ran on
        # another runner and passed.
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced(), raced("scaled2x"), raced()])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)
        self.assertEqual(rows["testX11Window"]["tolerated"],
                         [f"{X11}::{TOP_IF}: failed in 3 of 3 attempts, {RACE_NOTE}"])

    def test_the_other_stacking_test_is_covered(self):
        # Run 43665657830: testStackAboveFromApplication failed in one of three attempts on a tie.
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced("scaled2x", function=ABOVE), log(X11, X11_OK), log(X11, X11_OK)])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)
        self.assertEqual(rows["testX11Window"]["tolerated"], [f"{X11}::{ABOVE}: failed in 1 of 3 attempts, {RACE_NOTE}"])

    def test_a_tie_in_another_test_is_no_race(self):
        # Another test can log a tied raise and then fail for its own reason: only the two stacking
        # tests whose failure the race explains get the allowance.
        self.suite(self.stock, "testX", [log("T", OK)] * 10)
        self.suite(self.backport, "testX", [raced(function="testA", cls="T", base=OK)] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn("T::testA: failed in 3 of 3 attempts, passed in every stock attempt (10)", rows["testX"]["failed"])

    def test_a_tie_in_another_x11_test_is_no_race(self):
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced("", function="testMinimize")] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn(f"{X11}::testMinimize: failed in 3 of 3 attempts, passed in every stock attempt (10)",
                      rows["testX11Window"]["failed"])

    def test_a_raise_on_a_newer_user_time_is_no_race(self):
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced(messages=[NEWER])] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn(f"{X11}::{TOP_IF}: failed in 3 of 3 attempts, passed in every stock attempt (10)",
                      rows["testX11Window"]["failed"])

    def test_a_raise_granted_to_a_newer_request_is_no_race(self):
        # A full raise because the request was newer than the active window's user time: not a tie,
        # so something else (the activation order) decided it.
        granted = created(1058755, 1058757, 1058757) + ["Raising, compared: 1058757 : 1058756 : true"]
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced(messages=granted)] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)

    def test_only_a_failed_assertion_can_be_the_race(self):
        results = X11_OK[:1] + [(TOP_IF, "normal", "fatal")]
        fatal = log(X11, results, complete=False, debug={(TOP_IF, "normal"): RACED})
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [fatal] * 3, exit_status=134)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertTrue(any(f"{X11}::{TOP_IF}: failed in 3 of 3 attempts, passed in every stock attempt" in line
                            for line in rows["testX11Window"]["failed"]), rows)

    def test_the_failure_qtest_adds_after_a_fatal_message_is_no_race(self):
        # After a fatal message QtTest reports the row once more, as FAIL! "Received a fatal error.":
        # that FAIL! has no raise decision of its own, so it is not the race either.
        results = X11_OK[:1] + [(TOP_IF, "normal", "fatal")]
        fatal = log(X11, results, complete=False, debug={(TOP_IF, "normal"): RACED})
        fatal += f"FAIL!  : {X11}::{TOP_IF}(normal) Received a fatal error.\n"
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [fatal] * 3, exit_status=134)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertTrue(any(f"{X11}::{TOP_IF}: failed in 3 of 3 attempts, passed in every stock attempt" in line
                            for line in rows["testX11Window"]["failed"]), rows)

    def test_a_refused_raise_on_a_tie_is_no_race(self):
        refused = created(1058755, 1058756, 1058756) + ["Raising, compared: 1058756 : 1058756 : false"]
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced(messages=refused)] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)

    def test_only_the_last_raise_before_the_failure_counts(self):
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced(messages=RACED + [NEWER])] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)

    def test_a_failure_without_a_raise_is_no_race(self):
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced(messages=[])] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)

    def test_a_tie_in_another_row_does_not_count(self):
        # The race in the normal row, which passed; the scaled2x row failed without one.
        results = X11_OK[:2] + [(TOP_IF, "scaled2x", "fail")] + X11_OK[3:]
        bad = log(X11, results, debug={(TOP_IF, "normal"): RACED})
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [bad] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)

    def test_an_attempt_with_another_failed_row_is_no_race(self):
        # Both rows failed in each attempt, only one of them on a tie.
        results = X11_OK[:1] + [(TOP_IF, "normal", "fail"), (TOP_IF, "scaled2x", "fail")] + X11_OK[3:]
        bad = log(X11, results, debug={(TOP_IF, "normal"): RACED, (TOP_IF, "scaled2x"): [NEWER]})
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [bad] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn(f"{X11}::{TOP_IF}: failed in 3 of 3 attempts, passed in every stock attempt (10)",
                      rows["testX11Window"]["failed"])

    def test_race_does_not_hide_a_failure_in_the_other_attempts(self):
        # Two attempts on the race, the third failed otherwise: judged on the one the race did not
        # decide, where it failed and stock never did.
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced(), raced(), raced(messages=[NEWER])])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn(f"{X11}::{TOP_IF}: failed in 3 of 3 attempts (2 on KWin's timestamp race), passed in every stock attempt (10)",
                      rows["testX11Window"]["failed"])

    def test_race_and_a_passing_attempt(self):
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced(), raced(messages=[NEWER]), log(X11, X11_OK)])
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)
        self.assertEqual(rows["testX11Window"]["tolerated"],
                         [f"{X11}::{TOP_IF}: failed in 2 of 3 attempts (1 on KWin's timestamp race), passed in the others"])

    def test_backported_test_gets_no_race_tolerance(self):
        new = X11_OK + [("requestedGeometryNew", "", "fail")]
        bad = log(X11, new, debug={("requestedGeometryNew", ""): RACED})
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)])
        self.suite(self.backport, "testX11Window", [bad] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn(f"{X11}::requestedGeometryNew: a backported test, failed in 3 of 3 attempts",
                      rows["testX11Window"]["failed"])

    def test_a_tie_on_no_time_is_no_race(self):
        # readUserCreationTime() gives 2^32 - 1 when a window lacks its creation time: windows that
        # all lost it tie on every runner, which is a regression, not the race.
        none = created(4294967295, 4294967295, 4294967295) + ["Raising, compared: 4294967295 : 4294967295 : true"]
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced(messages=none)] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn(f"{X11}::{TOP_IF}: failed in 3 of 3 attempts, passed in every stock attempt (10)",
                      rows["testX11Window"]["failed"])

    def test_a_tie_on_time_zero_is_no_race(self):
        zero = created(0, 0, 0) + ["Raising, compared: 0 : 0 : true"]
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced(messages=zero)] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)

    def test_a_tie_needs_two_windows_created_on_its_time(self):
        # The race is two of the row's windows created in one millisecond; a tied time KWin gave no
        # two of them is something else.
        apart = created(1058754, 1058755, 1058756) + [TIE]
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [raced(messages=apart)] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)

    def test_the_race_on_stock_does_not_excuse_a_backport_failure(self):
        # The backport fails the test in every attempt without the race; stock failed it once, on
        # the race (run 43590522888 had one). That stock failure says nothing about the backport.
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 9 + [raced("scaled2x")])
        self.suite(self.backport, "testX11Window", [raced(messages=[NEWER])] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)
        self.assertIn(f"{X11}::{TOP_IF}: failed in 3 of 3 attempts; on stock only on KWin's timestamp race (1 of 10)",
                      rows["testX11Window"]["failed"])

    def test_a_failure_on_stock_besides_the_race_still_counts(self):
        stock = [log(X11, X11_OK)] * 8 + [raced("scaled2x"), raced(messages=[NEWER])]
        self.suite(self.stock, "testX11Window", stock)
        self.suite(self.backport, "testX11Window", [raced(messages=[NEWER])] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 0, out)
        self.assertEqual(rows["testX11Window"]["tolerated"], [f"{X11}::{TOP_IF}: failed in 3 of 3 attempts; also on stock (1 of 10)"])

    def test_a_second_failure_of_the_raced_row_is_no_race(self):
        # A row that failed on the race and then failed again (in cleanup(), reported under the same
        # row): the second failure has no raise decision of its own.
        bad = raced() + f"FAIL!  : {X11}::{TOP_IF}(normal) Compared values are not the same\n"
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [bad] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)

    def test_a_race_logged_after_its_row_ended_does_not_carry_over(self):
        # The normal row passed, then lines of it came after its result; the next row failed
        # without a decision of its own.
        results = X11_OK[:2] + [(TOP_IF, "scaled2x", "fail")] + X11_OK[3:]
        text = log(X11, results)
        late = "".join(f"QDEBUG : {X11}::{TOP_IF}(normal) kwin_core: {m}\n" for m in RACED)
        passed = f"PASS   : {X11}::{TOP_IF}(normal)\n"
        self.assertEqual(text.count(passed), 1)
        bad = text.replace(passed, passed + late)
        self.suite(self.stock, "testX11Window", [log(X11, X11_OK)] * 10)
        self.suite(self.backport, "testX11Window", [bad] * 3)
        rc, rows, out = self.compare()
        self.assertEqual(rc, 1, out)

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
