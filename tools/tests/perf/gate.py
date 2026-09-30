#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Performance gate (BACKLOG M6): metrics of the scen-perf.sh runs, compared with the section 7
# budget and a stored baseline.
#
#   gate.py --geometry WxH@SCALE [--baseline FILE] [--budget FILE] [--save FILE] [--label TEXT]
#           [--strict-budget] [--host FILE] RUN_DIR...
#
# Per metric: the median over the runs (min..max), the budget verdict (PASS/FAIL) and the baseline
# verdict: "regression" when the median exceeds the baseline's maximum by more than the metric's
# noise margin (budget.json), "better" when it is below the baseline's minimum by more than it.
# A metric's window in a run is noisy when another virtual session had live processes at either
# end of it, or when the host spent more CPU outside this session during it than FOREIGN_ABS +
# FOREIGN_REL x this session's own CPU (% of one core; catches sessions that came and went inside
# the window, builds, the logged-in user). Per metric only its quiet runs are used when there are
# any. A metric measured only in noisy windows cannot show a regression: it is reported as
# "worse (noisy)". A metric the baseline has but this build did not produce (the launcher did not
# open, the sweep did not run) is MISSING and fails the gate. --save writes the result as a
# baseline file.
# Exit status: 0 no regression (and with --strict-budget every budget met), 1 regression, missing
# metric or budget failure, 2 internal error, 3 no usable run, 4 the baseline was measured at
# another geometry, 5 worse only in noisy runs (re-run on a quiet host).
import argparse, json, os, statistics as st, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import analyze_ab  # noqa: E402


def mib(stats, label, comm, key):
    s = stats.get(label)
    if not s:
        return None
    v = [p.get(key) for p in s["procs"] if p["comm"] == comm and p.get(key) is not None]
    return sum(v) / 1024 if v else None


# The snapshots that bound each metric's measurement window: a metric counts as noisy in a run when
# another virtual session had live processes at either end of its window.
WINDOWS = {
    "idle_": ("idle0", "idle1"), "sweep_": ("sweep0", "sweep1"), "pss_": ("settled", "settled"),
    "session_pss": ("settled", "settled"), "gem_plasmashell_settled": ("settled", "settled"),
    "gem_launcher_first_open": ("launcher1-0", "launcher1-1"), "gem_plasmashell_end": ("launcher1-0", "end"),
    "kwin_rss_end": ("windows-open", "end"), "launcher_": ("launcher1-0", "launcher3-1"),
    "qs_": ("qs1-0", "qs3-1"), "alttab_": ("alttab1-0", "alttab3-1"), "overview_": ("ov1-0", "ov3-1"),
}


# Foreign CPU above FOREIGN_ABS + FOREIGN_REL x the session's own CPU marks a window noisy. A quiet
# host measured 4-14 % (kernel work for the session's GPU and input included); runs next to another
# session 33-235 %.
FOREIGN_ABS, FOREIGN_REL = 25.0, 0.25
# The dock sweep sends ~98 motions/s for 10 s (~975); far fewer means the input did not run.
SWEEP_MIN_EVENTS = 800


def foreign_cpu(S, a, b):
    """(CPU outside this session, CPU of this session) between snapshots a and b, in % of one
    core; (None, None) for a point window or a missing snapshot."""
    A, B = S.get(a), S.get(b)
    if not A or not B or a == b or B["mono"] <= A["mono"]:
        return None, None
    busy = lambda c: sum(c[:8]) - c[3] - c[4]  # user..steal without idle and iowait (guest is in user)
    mach = 100.0 * (busy(B["cpu"]) - busy(A["cpu"])) / A["clk_tck"] / (B["mono"] - A["mono"])
    sess = analyze_ab.cpu_pct(A, B)
    return mach - sess, sess


def window(metric):
    for prefix, w in WINDOWS.items():
        if metric.startswith(prefix):
            return w
    return ("settled", "end")


def med(values):
    v = [x for x in values if x is not None]
    return st.median(v) if v else None


def metrics(run):
    arm, S, M, F, A = analyze_ab.load(run)
    r = analyze_ab.analyze(run)
    g0, g1 = mib(S, "launcher1-0", "plasmashell", "gem_total_kB"), mib(S, "launcher1-1", "plasmashell", "gem_total_kB")
    m = {
        "idle_fps": r["idle_frames"]["fps"],
        "idle_cpu_plasmashell": r["idle_cpu_plasmashell"],
        "idle_cpu_kwin": r["idle_cpu_kwin"],
        "idle_cpu_session": r["idle_cpu_session"],
        "idle_gpu_plasmashell": r["idle_gpu_plasmashell"],
        "sweep_cpu_plasmashell": r["sweep_cpu_plasmashell"],
        "sweep_cpu_kwin": r["sweep_cpu_kwin"],
        "sweep_gpu_plasmashell": r["sweep_gpu_plasmashell"],
        "pss_plasmashell_settled": r["plasmashell_pss"],
        "session_pss_settled": r["session_pss"],
        "gem_plasmashell_settled": r["plasmashell_gem_total"],
        "gem_launcher_first_open": g1 - g0 if g0 is not None and g1 is not None else None,
        "gem_plasmashell_end": mib(S, "end", "plasmashell", "gem_total_kB"),
        "kwin_rss_end": r["end_kwin_rss"],
        "launcher_first_frame_ms": med(r["launcher_first_frame_ms"]),
        "launcher_settled_ms": med(r["launcher_settled_ms"]),
        "qs_first_frame_ms": med(r["qs_first_frame_ms"]),
        "alttab_first_frame_ms": med(r["alttab_first_frame_ms"]),
        "alttab_settled_ms": med(r["alttab_settled_ms"]),
        "overview_late_frames": med([f["late"] for f in r["ov_frames"]]),
    }
    if not F:
        # no KWin frame log (KWIN_LOG_PERFORMANCE_DATA or PFV_CWD=out missing): 0 frames would read as
        # a perfect idle desktop, so every frame-based metric is unknown instead
        for k in ("idle_fps", "launcher_first_frame_ms", "launcher_settled_ms", "qs_first_frame_ms",
                  "alttab_first_frame_ms", "alttab_settled_ms", "overview_late_frames"):
            m[k] = None
    sweep_events = next((int(k.split("-")[-1]) for k in M if k.startswith("sweep-events-")), None)
    if sweep_events is None or sweep_events < SWEEP_MIN_EVENTS:
        for k in ("sweep_cpu_plasmashell", "sweep_cpu_kwin", "sweep_gpu_plasmashell"):
            m[k] = None
    others = sorted({o for s in S.values() for o in s.get("others", [])})
    foreign = {}
    for w in sorted(set(window(k) for k in m)):
        f, own = foreign_cpu(S, *w)
        if f is not None:
            foreign["%s..%s" % w] = {"foreign": round(f, 1), "session": round(own, 1),
                                     "noisy": f > FOREIGN_ABS + FOREIGN_REL * own}
    noisy = sorted(k for k in m if any(S.get(lbl, {}).get("others") for lbl in window(k))
                   or foreign.get("%s..%s" % window(k), {}).get("noisy"))
    load = [float(s["load"][0]) for s in S.values()]
    noise = {"other_sessions": others, "noisy_metrics": noisy, "load1_max": max(load) if load else None,
             "idle_machine_cpu": r["idle_noise_syscpu"], "sweep_events": sweep_events, "foreign_cpu": foreign}
    return m, noise


def fmt(v, unit):
    if v is None:
        return "-"
    d = 0 if unit in ("ms", "MiB", "") else 2 if abs(v) < 10 else 1
    return "%.*f" % (d, v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--geometry", required=True)
    ap.add_argument("--baseline", default=os.path.join(HERE, "baseline.json"))
    ap.add_argument("--budget", default=os.path.join(HERE, "budget.json"))
    ap.add_argument("--save")
    ap.add_argument("--label", default="")
    ap.add_argument("--host", help="JSON lines of the host state before and after each run")
    ap.add_argument("--packages", help="host package versions (one per line), stored and compared with the baseline's")
    ap.add_argument("--strict-budget", action="store_true")
    a = ap.parse_args()
    spec = json.load(open(a.budget))["metrics"]
    per_run = []
    for run in a.runs:
        try:
            m, noise = metrics(run)
        except Exception as e:  # a broken run must not stop the others from being judged
            print("run %s unusable: %s: %s" % (os.path.basename(run), type(e).__name__, e), file=sys.stderr)
            continue
        per_run.append({"run": os.path.basename(run), "metrics": m, "noise": noise,
                        "clean": not noise["noisy_metrics"]})
    if not per_run:
        print("no usable run")
        return 3
    clean = [r for r in per_run if r["clean"]]
    agg = {}
    for k in spec:
        # per metric: the values of the runs whose window for it was quiet; all values when none was
        allv = [r["metrics"].get(k) for r in per_run if r["metrics"].get(k) is not None]
        v = [r["metrics"].get(k) for r in per_run
             if k not in r["noise"]["noisy_metrics"] and r["metrics"].get(k) is not None]
        clean_k = bool(v)
        v = v or allv
        agg[k] = {"median": st.median(v), "min": min(v), "max": max(v), "n": len(v), "of": len(per_run),
                  "produced": len(allv), "clean": clean_k} if v else None
    base = None
    if a.baseline and not os.path.exists(a.baseline):
        print("baseline %s does not exist (pass --baseline '' to judge the budget only)" % a.baseline)
        return 2
    if a.baseline:
        base = json.load(open(a.baseline))
        if base.get("geometry") != a.geometry:
            print("baseline %s was measured at %s, this run at %s" % (a.baseline, base.get("geometry"), a.geometry))
            return 4
    rows, regressions, budget_fail, noisy_worse, missing = [], [], [], [], []
    for k, s in spec.items():
        cur = agg.get(k)
        limit = s["budget"].get(a.geometry, s["budget"]["default"])
        bv = "-" if cur is None else ("PASS" if cur["median"] <= limit else "FAIL")
        if bv == "FAIL":
            budget_fail.append(k)
        verdict, bdesc = "-", "-"
        b = (base or {}).get("metrics", {}).get(k)
        if b and not cur:
            verdict = "MISSING"
            missing.append(k)
        if cur and b:
            margin = max(s["noise"]["abs"], s["noise"]["rel"] * abs(b["median"]))
            if cur["median"] > b["max"] + margin and not cur["clean"]:
                # measured only while another session ran: not evidence of a regression
                verdict = "worse (noisy)"
                noisy_worse.append(k)
            elif cur["median"] > b["max"] + margin:
                verdict = "REGRESSION"
                regressions.append(k)
            elif cur["median"] < b["min"] - margin:
                verdict = "better"
            else:
                verdict = "same"
        if b:
            bdesc = "%s (%s..%s)" % (fmt(b["median"], s["unit"]), fmt(b["min"], s["unit"]), fmt(b["max"], s["unit"]))
        cdesc = "-" if cur is None else "%s (%s..%s) %s%s%s" % (
            fmt(cur["median"], s["unit"]), fmt(cur["min"], s["unit"]), fmt(cur["max"], s["unit"]), s["unit"],
            "" if cur["clean"] else " (noisy)",
            "" if cur["produced"] == cur["of"] else " (in %d of %d runs)" % (cur["produced"], cur["of"]))
        rows.append("| %s | %s | <= %s | %s | %s | %s |" % (s["label"], cdesc, limit, bv, bdesc, verdict))
    print("| metric | this build: median (min..max) | budget | budget | baseline median (min..max) | vs baseline |")
    print("|---|---|---|---|---|---|")
    print("\n".join(rows))
    print()
    print("runs: %d (%d quiet in every window); geometry %s; label %s; per metric only the runs whose window for it "
          "was quiet are used (no other virtual session at its ends, CPU outside the session <= %g + %g x its own; "
          "\"noisy\": no run was quiet)" % (len(per_run), len(clean), a.geometry, a.label or "-", FOREIGN_ABS,
                                              FOREIGN_REL))
    for r in per_run:
        n = r["noise"]
        print("  %s: other sessions %s (noisy: %s), load1 max %s, machine CPU busy during idle %.1f %%, "
              "sweep events %s" % (r["run"], ", ".join(n["other_sessions"]) or "none",
                                   ", ".join(n["noisy_metrics"]) or "none", n["load1_max"], n["idle_machine_cpu"],
                                   n["sweep_events"]))
        print("    CPU outside the session / of the session, %% of a core: %s" % ", ".join(
            "%s %s/%s%s" % (w, f["foreign"], f["session"], " NOISY" if f["noisy"] else "")
            for w, f in sorted(n.get("foreign_cpu", {}).items())))
    packages = [l.strip() for l in open(a.packages) if l.strip()] if a.packages and os.path.exists(a.packages) else []
    if base:
        print("baseline: %s (%s, %s runs, %s)" % (a.baseline, base.get("label"), base.get("runs"), base.get("date")))
        if packages and base.get("packages") and packages != base["packages"]:
            print("note: the host's packages differ from the baseline's (re-record the baseline after a platform "
                  "update): %s" % ", ".join(sorted(set(packages) ^ set(base["packages"]))))
    print("budget: %d of %d met; regressions against the baseline: %s" % (
        sum(1 for k in spec if agg.get(k)) - len(budget_fail), sum(1 for k in spec if agg.get(k)),
        ", ".join(regressions) or "none"))
    if missing:
        print("MISSING in this build (the baseline has them): " + ", ".join(missing))
    if noisy_worse:
        print("worse than the baseline only in runs that overlapped another session (re-run on a quiet host): "
              + ", ".join(noisy_worse))
    result = {"_spdx": "SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>; "
                       "SPDX-License-Identifier: GPL-2.0-or-later", "geometry": a.geometry, "label": a.label,
              "runs": len(per_run), "clean_runs": len(clean),
              "date": __import__("time").strftime("%Y-%m-%dT%H:%M:%S%z"), "metrics": agg, "per_run": per_run,
              "budget_fail": budget_fail, "regressions": regressions, "noisy_worse": noisy_worse,
              "missing": missing, "packages": packages}
    if a.host and os.path.exists(a.host):
        result["host"] = [json.loads(line) for line in open(a.host) if line.strip()]
    if a.save:
        json.dump(result, open(a.save, "w"), indent=1, sort_keys=True)
        print("saved %s" % a.save)
        noisy_only = sorted(k for k, v in agg.items() if v and not v["clean"])
        if noisy_only:
            print("note: in this result %s come only from noisy windows; a baseline should be measured on a quiet "
                  "host" % ", ".join(noisy_only))
    if regressions or missing or (a.strict_budget and budget_fail):
        return 1
    return 5 if noisy_worse else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # an internal error must not look like a regression (exit 1)
        print("gate.py: internal error: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        sys.exit(2)
