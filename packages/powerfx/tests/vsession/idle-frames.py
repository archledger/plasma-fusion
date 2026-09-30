#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# idle-frames.py OUT_DIR...: per phase of scen-idle.sh, composited frames per second (rows of KWin's
# "kwin perf statistics *.csv" whose page-flip time falls between the phase's marks, CLOCK_MONOTONIC),
# the longest burst (frames less than 100 ms apart), and plasmashell and KWin CPU (% of one core,
# from pfstat.py's stats.jsonl). Prints a Markdown table; with several runs, one table per run.
import csv
import glob
import json
import os
import sys

LIMITS = {"critical-covered": 0.10, "critical-visible": 0.15, "critical-nocard": 0.10}


def load(run):
    marks = {}
    for line in open(os.path.join(run, "marks.jsonl")):
        m = json.loads(line)
        marks[m["mark"]] = m["mono"]
    stats = {}
    p = os.path.join(run, "stats.jsonl")
    if os.path.exists(p):
        for line in open(p):
            s = json.loads(line)
            stats[s["label"]] = s
    frames = []
    for f in glob.glob(os.path.join(run, "kwin perf statistics*.csv")):
        for r in list(csv.reader(open(f)))[1:]:
            if len(r) >= 4:
                frames.append(int(r[1]))
    return marks, stats, sorted(frames)


def cpu(stats, a, b, comm):
    if a not in stats or b not in stats:
        return None
    sa, sb = stats[a], stats[b]
    pa = {p["pid"]: p for p in sa["procs"]}
    ticks = sum(p["ticks"] - pa[p["pid"]]["ticks"] for p in sb["procs"] if p["comm"] == comm and p["pid"] in pa)
    return 100.0 * ticks / sa["clk_tck"] / (sb["mono"] - sa["mono"])


def main():
    bad = 0
    for run in sys.argv[1:]:
        marks, stats, frames = load(run)
        print(f"### {os.path.basename(run.rstrip('/'))}\n")
        print("| phase | seconds | frames | frames/s | longest burst | plasmashell CPU % | KWin CPU % | limit |")
        print("|---|---|---|---|---|---|---|---|")
        for name in [m[:-2] for m in marks if m.endswith("-0")]:
            t0, t1 = marks[name + "-0"], marks.get(name + "-1")
            if t1 is None:
                continue
            fr = [f for f in frames if t0 * 1e9 <= f <= t1 * 1e9]
            burst = best = 0
            for i, f in enumerate(fr):
                burst = burst + 1 if i and f - fr[i - 1] < 100e6 else 1
                best = max(best, burst)
            fps = len(fr) / (t1 - t0)
            ps, kw = cpu(stats, name + "-0", name + "-1", "plasmashell"), cpu(stats, name + "-0", name + "-1", "kwin_wayland")
            lim = LIMITS.get(name)
            verdict = "" if lim is None else ("pass" if fps <= lim else "FAIL") + f" (<= {lim})"
            bad += verdict.startswith("FAIL")
            fmt = lambda v: "-" if v is None else f"{v:.2f}"
            print(f"| {name} | {t1 - t0:.1f} | {len(fr)} | {fps:.3f} | {best} | {fmt(ps)} | {fmt(kw)} | {verdict} |")
        print()
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
