#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Rubber-band measurement (BACKLOG S5): table of the scen-band.sh runs.
#
#   band.py RUN_DIR...
#
# Per icon count (20, 60, 100) and run: plasmashell, KWin and session CPU (% of one core) during the
# 3 s band sweep, KWin's composited frames, their render p95 and the late frames (render end after
# the target page flip). Budget (BACKLOG 7): with 100 icons at most 15 % plasmashell CPU and 0 late
# frames. Exit status: 0 the budget holds (median over the runs), 1 it does not, 2 no usable run.
import json, os, statistics as st, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import analyze_ab  # noqa: E402

BUDGET_CPU, BUDGET_LATE = 15.0, 0


def main(runs):
    rows, per = [], {}
    for run in runs:
        try:
            _, S, M, F, _ = analyze_ab.load(run)
        except (OSError, ValueError, IndexError, KeyError) as e:
            print("run %s unusable: %s" % (os.path.basename(run), e), file=sys.stderr)
            continue
        for n in (20, 60, 100):
            a, b = S.get("band-%d-0" % n), S.get("band-%d-1" % n)
            if not a or not b:
                continue
            fr = analyze_ab.frames_in(F, M["band-%d-0" % n]["mono"], M["band-%d-1" % n]["mono"]) if F else None
            r = {"run": os.path.basename(run), "icons": n, "secs": round(b["mono"] - a["mono"], 2),
                 "cpu_plasmashell": analyze_ab.cpu_pct(a, b, "plasmashell"), "cpu_kwin": analyze_ab.cpu_pct(a, b, "kwin_wayland"),
                 "cpu_session": analyze_ab.cpu_pct(a, b, session=True), "frames": fr and fr["n"], "fps": fr and fr["fps"],
                 "render_p95": fr and fr["p95"], "late": fr and fr["late"], "others": sorted(set(a.get("others", []) + b.get("others", [])))}
            per.setdefault(n, []).append(r)
            rows.append(r)
    if not rows:
        print("no usable run")
        return 2
    f = lambda v, d=1: "-" if v is None else "%.*f" % (d, v)
    print("| icons | run | window s | plasmashell CPU % | KWin CPU % | session CPU % | frames (per s) | render p95 ms | late frames | other sessions |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        print("| %d | %s | %s | %s | %s | %s | %s (%s) | %s | %s | %s |" % (
            r["icons"], r["run"], r["secs"], f(r["cpu_plasmashell"]), f(r["cpu_kwin"]), f(r["cpu_session"]),
            r["frames"] if r["frames"] is not None else "-", f(r["fps"], 0), f(r["render_p95"], 2),
            r["late"] if r["late"] is not None else "-", ", ".join(r["others"]) or "none"))
    ok = True
    print()
    for n in sorted(per):
        cpu = st.median(x["cpu_plasmashell"] for x in per[n])
        late = [x["late"] for x in per[n] if x["late"] is not None]
        latem = st.median(late) if late else None
        line = "%d icons: plasmashell %.1f %% (median of %d), late frames %s" % (n, cpu, len(per[n]), f(latem, 0))
        if n == 100:
            passed = cpu <= BUDGET_CPU and latem is not None and latem <= BUDGET_LATE
            ok = ok and passed
            line += " -> budget (<= %g %%, %d late) %s" % (BUDGET_CPU, BUDGET_LATE, "PASS" if passed else "FAIL")
        print(line)
    json.dump(rows, open(os.path.join(os.path.dirname(os.path.abspath(runs[0])), "band.json"), "w"), indent=1)
    return 0 if ok and 100 in per else 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: band.py RUN_DIR...")
    sys.exit(main(sys.argv[1:]))
