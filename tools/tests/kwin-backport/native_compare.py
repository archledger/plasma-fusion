#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The native suites of the KWin backport, judged against the stock build's.

  native_compare.py STOCK_DIR BACKPORT_DIR OUT_DIR

Each directory is an output of packaging/patches/kwin/native-tests.sh (STOCK_DIR made with
--stock): a file "variant", and per suite SUITE.N.log for each attempt N (QtTest's text output),
SUITE.exit and SUITE.attempts: up to three attempts on the backport (until one passes), ten on
stock. Upstream tests can fail in this configuration without the backport (on 2026-10-26
testX11Window's stacking tests failed in 15 and in 6 of 20 runs of either build), so the question
is only whether the backport adds a failure. A suite fails here when:
  - any attempt lacks successful compositor initialization or reports an initialization failure;
  - it did not run on the backport, or its stock comparison is missing;
  - a test function fails in every backport attempt that ran it and in no stock attempt;
  - a backported test (a function the stock build does not have) fails in any attempt: those must
    be stable;
  - a function the stock build ran is missing from every backport attempt (also when both crash:
    a backport that crashes earlier never reaches it);
  - every backport attempt crashed or timed out (no "Totals:" line) while some stock attempt did
    not, or the suite failed without a reason above (an exit status with no failed function).
Failures that also happen on stock, and functions that failed in only some backport attempts
(KWin's own CI repeats a failing test up to three times), pass and are listed as such.

KWin's timestamp race (#188) is upstream's and is judged apart. KWin gives an X11 window that sets
no user time the X server's time at its creation, in milliseconds, and grants an application's
raise request in full when the request's time is not older than the active window's user time
(Workspace::allowFullClientRaising: time >= user_time; kwin_core logs "Raising, compared: TIME :
USER_TIME : true|false"). When a test creates its windows within one millisecond the two times are
equal, the raise is granted in full instead of within the application, and testX11Window's
stacking tests fail on either build; how often depends on the runner's speed, and the two builds
run on different runners. A failed row (FAIL!) of one of those two tests (RACE_TESTS) is that race
when its last raise decision before the failure was granted on equal times, and that time is a
real one (not 0 or 2^32 - 1) which KWin gave at least two of the row's windows at their creation
(kwin_core "User timestamp, final"). An attempt in which every failed row of a function is the
race does not count against the function; the rules above judge it on its other attempts, and a
function that failed only on the race passes, listed as such. A stock attempt that failed a
function only on the race does not count as a failure on stock. A tied raise in any other test
gives no allowance, and neither do backported tests: they must be stable.
Writes OUT_DIR/native-summary.md and native-summary.json. Exit 0 no failure, 1 a failure, 2 usage.
"""

import json
import os
import re
import sys

LINE = re.compile(r"^(PASS|FAIL!|XPASS|XFAIL|SKIP|BPASS|BFAIL|BXPASS|BXFAIL|QFATAL)\s*:\s+([A-Za-z_][\w:]*::\w+)"
                  r"(?:\(([^)]*)\))?")
FAILED = {"FAIL!", "XPASS", "QFATAL"}
# KWin's raise decision for an X11 window, logged in the row (function and data tag) that caused it.
RAISE = re.compile(r"^QDEBUG\s*:\s+([A-Za-z_][\w:]*::\w+)\(([^)]*)\)\s+kwin_core: "
                   r"Raising, compared:\s*(\d+)\s*:\s*(\d+)\s*:\s*(true|false)\s*$")
# The user time KWin gives a window it manages, logged in the row that created the window; for the
# tests' windows, their creation time (X11Window::readUserTimeMapTimestamp).
CREATED = re.compile(r"^QDEBUG\s*:\s+([A-Za-z_][\w:]*::\w+)\(([^)]*)\)\s+kwin_core: User timestamp, final: .* : (\d+)\s*$")
# Values that are no time: 0 (do not activate) and 2^32 - 1 (none: readUserCreationTime() of a window
# without its creation time). Windows that tie on them tie on every runner.
NO_TIME = {"0", "4294967295"}
# The tests whose failure the race explains (#188): an application's stacking request, where a full
# raise also puts the window above another application's window. Another test that logs a tied
# raise and then fails is judged like any other failure.
RACE_TESTS = {"X11WindowTest::testStackTopIfFromApplication", "X11WindowTest::testStackAboveFromApplication"}
RENDERER_READY = re.compile(
    r"^QDEBUG\s*:\s+[\w:]+::initTestCase\(\).*"
    r"(?:OpenGL|QPainter) compositing has been successfully initialized", re.MULTILINE)
RENDERER_FAILED = re.compile(
    r"^QCRITICAL\s*:\s+[\w:]+::initTestCase\(\).*"
    r"(?:The used windowing system requires compositing|We are going to quit KWin now as it is broken)",
    re.MULTILINE)


def read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return None


def attempt(text):
    """The functions an attempt ran and those that failed, those whose every failed row was KWin's
    timestamp race (see above), and whether it ran to its totals."""
    ran, failed, on_race, otherwise = set(), set(), set(), set()
    last_raise = {}  # (function, tag) -> (time, user time, granted): the row's newest decision
    created = {}  # (function, tag) -> {time: how many of the row's windows KWin gave that time}
    for line in text.splitlines():
        r = RAISE.match(line)
        if r:
            last_raise[(r.group(1), r.group(2))] = (r.group(3), r.group(4), r.group(5) == "true")
            continue
        c = CREATED.match(line)
        if c:
            times = created.setdefault((c.group(1), c.group(2)), {})
            times[c.group(3)] = times.get(c.group(3), 0) + 1
            continue
        m = LINE.match(line)
        if m:
            function, row = m.group(2), (m.group(2), m.group(3) or "")
            ran.add(function)
            if m.group(1) in FAILED:
                failed.add(function)
                time, user_time, granted = last_raise.get(row, (None, None, False))
                # The race and nothing else: two of the row's windows created in one millisecond,
                # and the raise granted on that very time.
                race = (m.group(1) == "FAIL!" and function in RACE_TESTS and granted and time == user_time
                        and time not in NO_TIME and created.get(row, {}).get(time, 0) >= 2)
                (on_race if race else otherwise).add(function)
            last_raise.pop(row, None)
            created.pop(row, None)
    return {"ran": ran, "failed": failed, "race": on_race - otherwise,
            "complete": any(line.startswith("Totals:") for line in text.splitlines()),
            "renderer_ready": bool(RENDERER_READY.search(text)),
            "renderer_failed": bool(RENDERER_FAILED.search(text))}


def suites(directory):
    """SUITE -> {"exit": int or None, "attempts": [attempt, ...]} from one native-tests.sh output."""
    out = {}
    for name in sorted(os.listdir(directory)):
        m = re.fullmatch(r"(\w+)\.(\d+)\.log", name)
        if m:
            out.setdefault(m.group(1), {})[int(m.group(2))] = attempt(read(os.path.join(directory, name)) or "")
    result = {}
    for suite, by_number in out.items():
        exit_text = (read(os.path.join(directory, f"{suite}.exit")) or "").strip()
        result[suite] = {
            "exit": int(exit_text) if exit_text.isdigit() else None,
            "attempts": [by_number[n] for n in sorted(by_number)],
        }
    return result


def judge(suite, backport, stock):
    failed, tolerated = [], []
    if backport is None or not backport["attempts"] or backport["exit"] is None:
        return {"suite": suite, "result": "FAIL", "failed": ["did not run on the backport"], "tolerated": []}
    if stock is None or not stock["attempts"] or stock["exit"] is None:
        return {"suite": suite, "result": "FAIL", "failed": ["no stock run to compare with"], "tolerated": []}
    b, s = backport["attempts"], stock["attempts"]
    for variant, attempts in (("backport", b), ("stock", s)):
        for index, item in enumerate(attempts, 1):
            if item["renderer_failed"]:
                failed.append(f"{variant} attempt {index}: compositor initialization failed")
            elif not item["renderer_ready"]:
                failed.append(f"{variant} attempt {index}: no successful compositor initialization")
    stock_ran = set().union(*(a["ran"] for a in s))
    # A stock attempt that failed a function only on KWin's timestamp race says nothing about the
    # backport either: it does not count as that function failing on stock too.
    stock_failed, stock_raced = {}, {}
    for a in s:
        for f in a["failed"] - a["race"]:
            stock_failed[f] = stock_failed.get(f, 0) + 1
        for f in a["race"]:
            stock_raced[f] = stock_raced.get(f, 0) + 1
    complete = [a for a in b if a["complete"]]
    if not complete:
        if all(not a["complete"] for a in s):
            tolerated.append(f"every attempt crashed or timed out, on stock too ({len(b)} and {len(s)})")
        else:
            failed.append(f"every attempt crashed or timed out ({len(b)}), not on stock")
    backport_ran = set().union(*(a["ran"] for a in b))
    # Also when both crash: a backport that crashes earlier never reaches what stock ran.
    for f in sorted(stock_ran - backport_ran):
        failed.append(f"{f} ran on stock but in no backport attempt")
    for f in sorted(backport_ran):
        runs = [a for a in b if f in a["ran"]]
        fails = sum(f in a["failed"] for a in runs)
        if not fails:
            continue
        # Attempts that KWin's timestamp race decided say nothing about the backport. A function
        # that failed only on the race passes; otherwise the rules below judge it on the attempts
        # the race did not decide (failing in all of those is failing in all its attempts).
        races = sum(f in a["race"] for a in runs)
        counted = f"{fails} of {len(runs)} attempts"
        where = counted + (f" ({races} on KWin's timestamp race)" if races else "")
        if f not in stock_ran:
            failed.append(f"{f}: a backported test, failed in {where}")
        elif races == fails:
            tolerated.append(f"{f}: failed in {counted}, each on KWin's timestamp race "
                             "(a full raise granted on equal user timestamps)")
        elif fails == len(runs) and f not in stock_failed:
            if f in stock_raced:
                failed.append(f"{f}: failed in {where}; on stock only on KWin's timestamp race ({stock_raced[f]} of {len(s)})")
            else:
                failed.append(f"{f}: failed in {where}, passed in every stock attempt ({len(s)})")
        elif f in stock_failed:
            tolerated.append(f"{f}: failed in {where}; also on stock ({stock_failed[f]} of {len(s)})")
        else:
            tolerated.append(f"{f}: failed in {where}, passed in the others")
    if backport["exit"] != 0 and not failed and not tolerated:
        failed.append(f"exit {backport['exit']} with no failed function")
    result = "FAIL" if failed else "PASS"
    return {"suite": suite, "result": result, "attempts": len(b), "failed": failed, "tolerated": tolerated}


def main(argv):
    if len(argv) != 4:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    stock_dir, backport_dir, out_dir = argv[1:]
    for directory, variant in ((stock_dir, "stock"), (backport_dir, "backport")):
        found = (read(os.path.join(directory, "variant")) or "").strip()
        if found != variant:
            print(f"{directory} is not a {variant} run (variant: {found or 'missing'})", file=sys.stderr)
            return 2
    backport, stock = suites(backport_dir), suites(stock_dir)
    rows = [judge(suite, backport.get(suite), stock.get(suite)) for suite in sorted(set(backport) | set(stock))]
    if not rows:
        rows = [{"suite": "(none)", "result": "FAIL", "failed": ["no suite ran"], "tolerated": []}]
    ok = all(r["result"] == "PASS" for r in rows)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "native-summary.json"), "w") as f:
        json.dump({"suites": rows, "ok": ok}, f, indent=1)
    with open(os.path.join(out_dir, "native-summary.md"), "w") as f:
        f.write("# Backported tests against stock KWin\n\n| Suite | Result | Attempts |\n|---|---|---|\n")
        for r in rows:
            f.write("| %s | %s | %s |\n" % (r["suite"], r["result"], r.get("attempts", "-")))
        for r in rows:
            for line in r["failed"]:
                f.write(f"\n- FAIL {r['suite']}: {line}")
            for line in r["tolerated"]:
                f.write(f"\n- passed {r['suite']}: {line}")
        f.write("\n")
    for r in rows:
        print("%-20s %-4s %s" % (r["suite"], r["result"], "; ".join(r["failed"] + r["tolerated"])[:200]))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
