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
Writes OUT_DIR/native-summary.md and native-summary.json. Exit 0 no failure, 1 a failure, 2 usage.
"""

import json
import os
import re
import sys

LINE = re.compile(r"^(PASS|FAIL!|XPASS|XFAIL|SKIP|BPASS|BFAIL|BXPASS|BXFAIL|QFATAL)\s*:\s+([A-Za-z_][\w:]*::\w+)")
FAILED = {"FAIL!", "XPASS", "QFATAL"}


def read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return None


def attempt(text):
    """The functions an attempt ran and those that failed, and whether it ran to its totals."""
    ran, failed = set(), set()
    for line in text.splitlines():
        m = LINE.match(line)
        if m:
            ran.add(m.group(2))
            if m.group(1) in FAILED:
                failed.add(m.group(2))
    return {"ran": ran, "failed": failed, "complete": any(line.startswith("Totals:") for line in text.splitlines())}


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
    stock_ran = set().union(*(a["ran"] for a in s))
    stock_failed = {}
    for a in s:
        for f in a["failed"]:
            stock_failed[f] = stock_failed.get(f, 0) + 1
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
        where = f"{fails} of {len(runs)} attempts"
        if f not in stock_ran:
            failed.append(f"{f}: a backported test, failed in {where}")
        elif fails == len(runs) and f not in stock_failed:
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
