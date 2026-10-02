#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Shell start-up times from scen-perf.sh runs: the scenario starts a fresh plasmashell (mark
# "shell-start") after loading nothing, and winmon.js (loaded half a second after plasmashell is on
# the bus, before its windows exist) logs every window added and every panel geometry change with
# the epoch time. Per run:
#   first window  - the first plasmashell window added (desktop or panel)
#   all windows   - the last plasmashell window added in the first 15 s
#   settled       - the last panel geometry change in the first 15 s (the layout stops moving)
# all in ms after shell-start, then per arm the mean (min..max).
#
#   startup.py RUN_DIR...
import json
import os
import re
import statistics
import sys
from collections import defaultdict


def run_times(run):
    arm = open(os.path.join(run, "arm.txt")).read().split()[0].split("=")[1]
    marks = {}
    for line in open(os.path.join(run, "marks.jsonl")):
        d = json.loads(line)
        marks.setdefault(d["mark"], d["epoch"])
    t0 = marks["shell-start"] * 1000
    added, geometry = [], []
    for m in re.finditer(r'PFPERF (added|geometry) (\d+) (?:\S+ )?(\S*)', open(os.path.join(run, "dbusmon.log")).read()):
        kind, ts, tag = m.group(1), int(m.group(2)), m.group(3)
        if not tag.startswith("plasmashell") or ts - t0 > 15000:
            continue
        (added if kind == "added" else geometry).append(ts - t0)
    if not added:
        return arm, None
    return arm, {"first window": min(added), "all windows": max(added), "settled": max(geometry + added)}


def main(runs):
    arms = defaultdict(list)
    for r in runs:
        arm, t = run_times(r)
        if t:
            arms[arm].append(t)
            print(f"{os.path.basename(r):24} {arm:7} " + "  ".join(f"{k} {v:.0f} ms" for k, v in t.items()))
    print()
    print("| shell start-up, ms after start | " + " | ".join(f"{a} (n={len(v)})" for a, v in sorted(arms.items())) + " |")
    print("|---|" + "---|" * len(arms))
    for k in ("first window", "all windows", "settled"):
        cells = []
        for a, v in sorted(arms.items()):
            xs = [x[k] for x in v]
            cells.append(f"{statistics.mean(xs):.0f} ({min(xs):.0f}..{max(xs):.0f})")
        print(f"| {k} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main(sys.argv[1:])
