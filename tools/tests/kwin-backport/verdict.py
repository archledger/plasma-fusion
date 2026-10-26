#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The KWin backport session check's verdict (tools/tests/kwin-backport/run.sh).

  verdict.py [--coredumps] RESULTS WANT_KWIN RUN...

RESULTS holds images.txt ("LANE NEVR" lines: each lane image's kwin package) and one directory per
RUN, named LANE-SCENARIO (a RUN is LANE:SCENARIO, or LANE:SCENARIO:property when the scenario must
report whether KWin has Window.requestedGeometry). WANT_KWIN is the kwin package the build made
(name-version-release.arch); the stock lane must run the Fedora build it came from, the same NEVR
without the backport's ".pf1". A run passes when:
  - its session ran to the end: scenario.log says "scenario rc=0" and "session rc=0", and the
    session runner did not fail (no runner-failed file);
  - every check passed, and there was at least one (checks.txt);
  - no log of the session names a crash (KCrash, a segmentation fault, a core dump);
  - kwin.log has no error from the placement script;
  - the session saw its lane's KWin: images.txt names the expected package, and a property run's
    "INFO KWin has Window.requestedGeometry: VALUE (PACKAGE)" line says true with WANT_KWIN on the
    backport, false without the backport's release on stock.
--coredumps: RESULTS/coredumps.json is the host's list of core dumps during the sessions
(coredumpctl --json=short; [] for none), on a machine that runs nothing else; a missing or
unreadable report, or any dump, adds a failed row "core dumps".
Writes RESULTS/summary.json and summary.md. Exit 0 every run passed, 1 one did not, 2 usage error.
"""

import json
import os
import re
import sys

LANES = ("stock", "backport")
CRASH = re.compile(r"KCrash: |Segmentation fault|\(core dumped\)")
SCRIPT_ERROR = re.compile(r"plasmafusion-placement.*(TypeError|ReferenceError|Error:|error:)")
PROPERTY = re.compile(r"^INFO KWin has Window\.requestedGeometry: (\S+) \((.*)\)$")


def read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return None


def expected(lane, want):
    return want if lane == "backport" else want.replace(".pf1", "", 1)


def images(results, want):
    """The lanes whose image does not hold the expected kwin package, with what it holds."""
    text = read(os.path.join(results, "images.txt")) or ""
    found = dict(line.split(None, 1) for line in text.splitlines() if len(line.split()) == 2)
    return {lane: found.get(lane, "nothing") for lane in LANES if found.get(lane) != expected(lane, want)}


def judge(results, want, lane, scenario, needs_property, wrong_images):
    d = os.path.join(results, f"{lane}-{scenario}")
    failed = []
    checks = (read(os.path.join(d, "checks.txt")) or "").splitlines()
    passed = [line for line in checks if line.startswith("PASS")]
    failed += [line for line in checks if line.startswith("FAIL")]
    status = [
        line
        for line in (read(os.path.join(d, "scenario.log")) or "").splitlines()
        if line.startswith(("scenario rc=", "session rc="))
    ]
    runner = read(os.path.join(d, "runner-failed"))
    if runner is not None:
        failed.append(f"FAIL the session runner failed (status {runner.strip()})")
    elif not ("scenario rc=0" in status and "session rc=0" in status):
        failed.append(
            "FAIL the session did not run to the end (%s)" % (", ".join(status) or "no status in scenario.log")
        )
    if os.path.isdir(d):
        for name in sorted(os.listdir(d)):
            text = read(os.path.join(d, name)) if name.endswith((".log", ".err", ".txt")) else None
            match = CRASH.search(text or "")
            if match:
                failed.append(f"FAIL {name} names a crash: {match.group(0).strip()}")
    errors = [line for line in (read(os.path.join(d, "kwin.log")) or "").splitlines() if SCRIPT_ERROR.search(line)]
    if errors:
        failed.append(f"FAIL kwin.log has {len(errors)} placement script error(s): {errors[0][:160]}")
    if lane in wrong_images:
        failed.append(f"FAIL the {lane} image holds {wrong_images[lane]}, not {expected(lane, want)}")
    if needs_property:
        seen = [m.groups() for m in map(PROPERTY.match, checks) if m]
        value, package = seen[-1] if seen else (None, None)
        if lane == "backport" and (value != "true" or package != want):
            failed.append(f"FAIL the session did not run the backport (property {value}, {package}; want true, {want})")
        if lane == "stock" and (value != "false" or package is None or ".pf" in package):
            failed.append(f"FAIL the session did not run stock KWin (property {value}, {package})")
    result = "PASS" if passed and not failed else "FAIL" if failed else "NO CHECKS"
    return {"run": f"{lane}-{scenario}", "result": result, "pass": len(passed), "fail": len(failed), "failed": failed[:10]}


def coredumps(results):
    """The "core dumps" row: the host's report must be there and empty."""
    failed = []
    try:
        with open(os.path.join(results, "coredumps.json")) as f:
            dumps = json.load(f)
        if not isinstance(dumps, list):
            raise ValueError("not a list")
    except (OSError, ValueError) as error:
        failed.append(f"FAIL no readable core dump report ({error})")
    else:
        for d in dumps[:10]:
            exe = d.get("exe") if isinstance(d, dict) else None
            sig = d.get("sig") if isinstance(d, dict) else None
            failed.append(f"FAIL core dump: {exe} (signal {sig})")
        if len(dumps) > 10:
            failed.append(f"FAIL {len(dumps) - 10} more core dump(s)")
    return {"run": "core dumps", "result": "FAIL" if failed else "PASS", "pass": 0 if failed else 1,
            "fail": len(failed), "failed": failed[:11]}


def main(argv):
    argv = list(argv)
    want_dumps = len(argv) > 1 and argv[1] == "--coredumps"
    if want_dumps:
        del argv[1]
    if len(argv) < 4:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    results, want, runs = argv[1], argv[2], []
    if not re.fullmatch(r"kwin-[0-9][^ /]*\.pf1\.[a-z0-9_]+", want):
        print(f"not a backport kwin package: {want}", file=sys.stderr)
        return 2
    for spec in argv[3:]:
        parts = spec.split(":")
        if len(parts) not in (2, 3) or parts[0] not in LANES or not parts[1] or parts[2:] not in ([], ["property"]):
            print(f"bad run {spec} (LANE:SCENARIO[:property], LANE one of {', '.join(LANES)})", file=sys.stderr)
            return 2
        runs.append((parts[0], parts[1], len(parts) == 3))
    wrong = images(results, want)
    rows = [judge(results, want, lane, scenario, prop, wrong) for lane, scenario, prop in runs]
    if want_dumps:
        rows.append(coredumps(results))
    ok = all(r["result"] == "PASS" for r in rows)
    with open(os.path.join(results, "summary.json"), "w") as f:
        json.dump({"kwin": want, "runs": rows, "ok": ok}, f, indent=1)
    with open(os.path.join(results, "summary.md"), "w") as f:
        f.write(f"# KWin backport sessions ({want})\n\n| Run | Result | PASS | FAIL |\n|---|---|---|---|\n")
        for r in rows:
            f.write("| %s | %s | %d | %d |\n" % (r["run"], r["result"], r["pass"], r["fail"]))
        for r in rows:
            for line in r["failed"]:
                f.write(f"\n- {r['run']}: {line}")
        f.write("\n")
    for r in rows:
        print("%-28s %-9s %3d PASS %3d FAIL" % (r["run"], r["result"], r["pass"], r["fail"]))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
