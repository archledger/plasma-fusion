#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copied unchanged from the perf-measure study (perf-measure/scripts/analyze_ab.py); gate.py imports
# analyze() and its helpers. Run directly it prints the stock/Fusion A/B table of that study.
#
# analyze_ab.py RUN_DIR... : per-run metrics from scen-perf.sh output (stats.jsonl, marks.jsonl,
# dbusmon.log, "kwin perf statistics Virtual-0.csv"), printed as JSON lines and as a table of
# per-arm means with min..max over runs.
import csv, glob, json, os, re, statistics as st, sys
from collections import defaultdict

EXCL = ("tool:", "dbus-monitor", "spectacle", "konsole", "kwrite", "python3", "sleep", "bash", "timeout",
        "qdbus-qt6", "qdbus", "inner.sh")


def load(run):
    stats = {}
    for l in open(os.path.join(run, "stats.jsonl")):
        r = json.loads(l); stats[r["label"]] = r
    marks = {}
    for l in open(os.path.join(run, "marks.jsonl")):
        m = json.loads(l); marks[m["mark"]] = m
    frames = []
    csvs = glob.glob(os.path.join(run, "kwin perf statistics*.csv"))
    if csvs:
        for r in list(csv.reader(open(csvs[0])))[1:]:
            if len(r) >= 9:
                frames.append(tuple(int(x) for x in r[:4]))
    added = []
    dm = os.path.join(run, "dbusmon.log")
    if os.path.exists(dm):
        for m in re.finditer(r'PFPERF (added|removed) (\d+) ([^"]*)', open(dm).read()):
            added.append((m.group(1), int(m.group(2)) / 1000.0, m.group(3)))
    arm = open(os.path.join(run, "arm.txt")).read().split()[0].split("=")[1]
    return arm, stats, marks, frames, added


def procs_by(s, comm):
    return [p for p in s["procs"] if p["comm"] == comm]


def cpu_pct(a, b, comm=None, session=False):
    """% of one core between snapshots a and b, for one comm or the whole session."""
    dt = b["mono"] - a["mono"]; tck = a["clk_tck"]
    pa = {p["pid"]: p for p in a["procs"]}
    tot = 0
    for p in b["procs"]:
        if comm and p["comm"] != comm:
            continue
        if session and p["comm"].startswith(EXCL):
            continue
        q = pa.get(p["pid"])
        base = q["ticks"] if q else 0  # processes born in the window count fully
        tot += p["ticks"] - base
    return 100.0 * tot / tck / dt


def gpu_pct(a, b, comm):
    pa = {p["pid"]: p for p in a["procs"]}
    dt = b["mono"] - a["mono"]; tot = 0
    for p in b["procs"]:
        if p["comm"] == comm and "gpu_ns" in p and p["pid"] in pa and "gpu_ns" in pa[p["pid"]]:
            tot += p["gpu_ns"] - pa[p["pid"]]["gpu_ns"]
    return 100.0 * tot / 1e9 / dt


def sys_noise(a, b):
    ca, cb = a["cpu"], b["cpu"]
    tot = sum(cb) - sum(ca); idle = (cb[3] + cb[4]) - (ca[3] + ca[4])
    return 100.0 * (tot - idle) / tot, float(b["load"][0])


def frames_in(frames, t0, t1):
    fr = [f for f in frames if t0 * 1e9 <= f[1] <= t1 * 1e9]
    rt = sorted((f[3] - f[2]) / 1e6 for f in fr if f[3] > f[2])
    late = sum(1 for f in fr if f[3] > f[0])
    q = lambda p: rt[min(len(rt) - 1, int(round(p * (len(rt) - 1))))] if rt else None
    # gaps between consecutive presented frames longer than 1.5 refresh intervals while animating
    gaps = [(fr[i + 1][1] - fr[i][1]) / 1e6 for i in range(len(fr) - 1)]
    return {"n": len(fr), "fps": len(fr) / (t1 - t0), "p50": q(.5), "p95": q(.95), "max": rt[-1] if rt else None,
            "late": late, "gap_max_ms": max(gaps) if gaps else None}


def mem(s, comm, key):
    v = [p.get(key) for p in procs_by(s, comm)]
    v = [x for x in v if x is not None]
    return sum(v) / 1024 if v else None


def session_pss(s):
    tot = 0
    for p in s["procs"]:
        if p["comm"].startswith(EXCL):
            continue
        tot += p.get("Pss", p.get("VmRSS", 0))
    return tot / 1024


def latency(marks, added, mark, pred):
    t0 = marks[mark]["epoch"]
    c = [t for kind, t, tag in added if kind == "added" and t >= t0 and t - t0 < 2.0 and pred(tag)]
    return (min(c) - t0) * 1000 if c else None


def analyze(run):
    arm, S, M, F, A = load(run)
    r = {"run": os.path.basename(run), "arm": arm}
    st_ = S["settled"]
    r["plasmashell_rss"] = mem(st_, "plasmashell", "VmRSS"); r["plasmashell_pss"] = mem(st_, "plasmashell", "Pss")
    r["plasmashell_anon"] = mem(st_, "plasmashell", "RssAnon")
    r["plasmashell_gem_total"] = mem(st_, "plasmashell", "gem_total_kB"); r["plasmashell_gem_res"] = mem(st_, "plasmashell", "gem_resident_kB")
    r["kwin_rss"] = mem(st_, "kwin_wayland", "VmRSS"); r["kwin_anon"] = mem(st_, "kwin_wayland", "RssAnon")
    r["kwin_shmem"] = mem(st_, "kwin_wayland", "RssShmem")
    r["session_pss"] = session_pss(st_)
    r["n_procs"] = sum(1 for p in st_["procs"] if not p["comm"].startswith(EXCL))
    r["end_plasmashell_rss"] = mem(S["end"], "plasmashell", "VmRSS"); r["end_kwin_rss"] = mem(S["end"], "kwin_wayland", "VmRSS")
    r["end_session_pss"] = session_pss(S["end"])
    i0, i1 = S["idle0"], S["idle1"]
    r["idle_cpu_plasmashell"] = cpu_pct(i0, i1, "plasmashell"); r["idle_cpu_kwin"] = cpu_pct(i0, i1, "kwin_wayland")
    r["idle_cpu_session"] = cpu_pct(i0, i1, session=True)
    r["idle_gpu_plasmashell"] = gpu_pct(i0, i1, "plasmashell")
    r["idle_frames"] = frames_in(F, i0["mono"], i1["mono"])
    r["idle_noise_syscpu"], r["idle_load1"] = sys_noise(i0, i1)
    s0, s1 = S["sweep0"], S["sweep1"]
    r["sweep_cpu_plasmashell"] = cpu_pct(s0, s1, "plasmashell"); r["sweep_cpu_kwin"] = cpu_pct(s0, s1, "kwin_wayland")
    r["sweep_cpu_session"] = cpu_pct(s0, s1, session=True); r["sweep_gpu_plasmashell"] = gpu_pct(s0, s1, "plasmashell")
    r["sweep_frames"] = frames_in(F, M["sweep0"]["mono"], M["sweep1"]["mono"])
    r["sweep_noise_syscpu"], r["sweep_load1"] = sys_noise(s0, s1)
    shell = lambda tag: tag.startswith(("plasmashell|", "org.kde.plasmashell|"))
    kwin_internal = lambda tag: tag.startswith("kwin_wayland|") or tag.startswith("|") or "tabbox" in tag.lower() or tag.startswith("org.kde.kwin")
    for name, n, pred in (("launcher", 3, shell), ("qs", 3, shell), ("alttab", 3, lambda t: not t.startswith(("plasmashell|", "org.kde.plasmashell|", "org.kde.konsole|", "org.kde.kwrite|", "spectacle")))):
        lat, cpu_s, cpu_k, fr = [], [], [], []
        for i in range(1, n + 1):
            lat.append(latency(M, A, f"{name}{i}", pred))
            a, b = S[f"{name}{i}-0"], S[f"{name}{i}-1"]
            cpu_s.append(cpu_pct(a, b, "plasmashell")); cpu_k.append(cpu_pct(a, b, "kwin_wayland"))
            m0 = M[f"{name}{i}"]["mono"]
            fr.append(frames_in(F, m0, m0 + 1.2))
        r[name + "_latency_ms"] = lat
        # visual timing from KWin's presented frames: first frame at or after the window was
        # mapped, and the end of the opening animation (last frame before a 100 ms pause)
        ff, settle = [], []
        for i in range(1, n + 1):
            m = M[f"{name}{i}"]; off = m["epoch"] - m["mono"]
            if lat[i - 1] is None:
                ff.append(None); settle.append(None); continue
            t_map = m["mono"] + lat[i - 1] / 1000.0
            ts = [f[1] / 1e9 for f in F if f[1] / 1e9 >= t_map and f[1] / 1e9 <= m["mono"] + 1.4]
            ff.append((ts[0] - m["mono"]) * 1000 if ts else None)
            end = None
            for a_, b_ in zip(ts, ts[1:] + [1e18]):
                if b_ - a_ > 0.1:
                    end = a_; break
            settle.append((end - m["mono"]) * 1000 if end else None)
        r[name + "_first_frame_ms"] = ff; r[name + "_settled_ms"] = settle
        r[name + "_cpu_plasmashell"] = st.mean(cpu_s); r[name + "_cpu_kwin"] = st.mean(cpu_k)
        r[name + "_frames"] = fr
    ov_s, ov_k, ov_fr = [], [], []
    for i in range(1, 4):
        a, b = S[f"ov{i}-0"], S[f"ov{i}-1"]
        ov_s.append(cpu_pct(a, b, "plasmashell")); ov_k.append(cpu_pct(a, b, "kwin_wayland"))
        m0 = M[f"ov{i}"]["mono"]
        ov_fr.append(frames_in(F, m0, M[f"ov{i}-close"]["mono"] + 1.0))
    r["ov_cpu_plasmashell"] = st.mean(ov_s); r["ov_cpu_kwin"] = st.mean(ov_k); r["ov_frames"] = ov_fr
    r["windows_added"] = [(round(t - M["begin"]["epoch"], 2), tag.split("|")[0]) for k, t, tag in A if k == "added"]
    return r


def fmt(v, d=1):
    return "-" if v is None else f"{v:.{d}f}"


if __name__ == "__main__":
    runs = [analyze(d) for d in sys.argv[1:]]
    with open("ab-runs.jsonl", "w") as fh:
        for r in runs:
            fh.write(json.dumps(r) + "\n")
    arms = defaultdict(list)
    for r in runs:
        arms[r["arm"]].append(r)

    def agg(arm, fn, d=1):
        v = [fn(r) for r in arms[arm]]
        v = [x for x in v if x is not None]
        if not v:
            return "-"
        return f"{st.mean(v):.{d}f} ({min(v):.{d}f}..{max(v):.{d}f})"

    def flat(key, sub=None, idx=None):
        def f(r):
            v = r[key]
            if isinstance(v, list):
                vv = [x[sub] if sub else x for x in v]
                vv = [x for x in vv if x is not None]
                if not vv:
                    return None
                return max(vv) if sub in ("max", "gap_max_ms") else st.median(vv)
            return v[sub] if sub else v
        return f

    rows = [
        ("plasmashell RSS after settle, MiB", flat("plasmashell_rss"), 0),
        ("plasmashell PSS after settle, MiB", flat("plasmashell_pss"), 0),
        ("plasmashell anon RSS, MiB", flat("plasmashell_anon"), 0),
        ("plasmashell GPU buffers total (GEM), MiB", flat("plasmashell_gem_total"), 0),
        ("plasmashell GPU buffers resident, MiB", flat("plasmashell_gem_res"), 0),
        ("kwin_wayland RSS after settle, MiB", flat("kwin_rss"), 0),
        ("kwin_wayland anon RSS, MiB", flat("kwin_anon"), 0),
        ("session PSS after settle (kwin RSS), MiB", flat("session_pss"), 0),
        ("session processes", flat("n_procs"), 0),
        ("plasmashell RSS at end, MiB", flat("end_plasmashell_rss"), 0),
        ("kwin RSS at end, MiB", flat("end_kwin_rss"), 0),
        ("idle 30 s: plasmashell CPU %", flat("idle_cpu_plasmashell"), 2),
        ("idle 30 s: kwin CPU %", flat("idle_cpu_kwin"), 2),
        ("idle 30 s: whole session CPU %", flat("idle_cpu_session"), 2),
        ("idle 30 s: plasmashell GPU %", flat("idle_gpu_plasmashell"), 3),
        ("idle 30 s: frames composited per s", flat("idle_frames", "fps"), 2),
        ("sweep 10 s: plasmashell CPU %", flat("sweep_cpu_plasmashell"), 1),
        ("sweep 10 s: kwin CPU %", flat("sweep_cpu_kwin"), 1),
        ("sweep 10 s: whole session CPU %", flat("sweep_cpu_session"), 1),
        ("sweep 10 s: plasmashell GPU %", flat("sweep_gpu_plasmashell"), 2),
        ("sweep: frames per s", flat("sweep_frames", "fps"), 1),
        ("sweep: KWin render ms p50", flat("sweep_frames", "p50"), 2),
        ("sweep: KWin render ms p95", flat("sweep_frames", "p95"), 2),
        ("sweep: KWin render ms max", flat("sweep_frames", "max"), 2),
        ("sweep: late frames", flat("sweep_frames", "late"), 0),
        ("launcher: key->window mapped ms (median of 3)", flat("launcher_latency_ms"), 0),
        ("launcher: key->first frame showing it ms", flat("launcher_first_frame_ms"), 0),
        ("launcher: key->opening animation done ms", flat("launcher_settled_ms"), 0),
        ("launcher: open+close cycle plasmashell CPU %", flat("launcher_cpu_plasmashell"), 1),
        ("launcher: open+close cycle kwin CPU %", flat("launcher_cpu_kwin"), 1),
        ("launcher: render ms p95 (first 1.2 s)", flat("launcher_frames", "p95"), 2),
        ("launcher: render ms max", flat("launcher_frames", "max"), 2),
        ("quick settings: click->window mapped ms", flat("qs_latency_ms"), 0),
        ("quick settings: click->first frame ms", flat("qs_first_frame_ms"), 0),
        ("quick settings: click->animation done ms", flat("qs_settled_ms"), 0),
        ("quick settings: cycle plasmashell CPU %", flat("qs_cpu_plasmashell"), 1),
        ("quick settings: cycle kwin CPU %", flat("qs_cpu_kwin"), 1),
        ("quick settings: render ms max", flat("qs_frames", "max"), 2),
        ("Alt+Tab: key->switcher mapped ms", flat("alttab_latency_ms"), 0),
        ("Alt+Tab: key->first frame ms", flat("alttab_first_frame_ms"), 0),
        ("Alt+Tab: key->animation done ms", flat("alttab_settled_ms"), 0),
        ("Alt+Tab: cycle kwin CPU %", flat("alttab_cpu_kwin"), 1),
        ("Alt+Tab: render ms p95", flat("alttab_frames", "p95"), 2),
        ("Alt+Tab: render ms max", flat("alttab_frames", "max"), 2),
        ("overview: cycle kwin CPU %", flat("ov_cpu_kwin"), 1),
        ("overview: cycle plasmashell CPU %", flat("ov_cpu_plasmashell"), 1),
        ("overview: render ms p50", flat("ov_frames", "p50"), 2),
        ("overview: render ms p95", flat("ov_frames", "p95"), 2),
        ("overview: render ms max", flat("ov_frames", "max"), 2),
        ("overview: late frames (median)", flat("ov_frames", "late"), 0),
        ("noise: machine CPU busy % during idle window", flat("idle_noise_syscpu"), 1),
        ("noise: load avg (1 min) during idle window", flat("idle_load1"), 2),
    ]
    names = sorted(arms)
    print("| metric | " + " | ".join(f"{a} (n={len(arms[a])}) mean (min..max)" for a in names) + " |")
    print("|---|" + "---|" * len(names))
    for label, fn, d in rows:
        print(f"| {label} | " + " | ".join(agg(a, fn, d) for a in names) + " |")
