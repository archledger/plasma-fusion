#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copied from pfstat.py in the perf-measure research scripts of 2026-09-30 (the maintainer's
# records); changes: records the other virtual sessions with live processes on the host ("others",
# noise); with PFSTAT_SUDO=1 it reads KWin's GPU counters (private fdinfo) with sudo -n, read-only.
#
# pfstat.py LABEL: snapshot every process of this private session (environ XDG_RUNTIME_DIR ==
# $XDG_RUNTIME_DIR, plus KWin, whose environ is unreadable because of its file capabilities) and
# append one JSON line to $OUT/stats.jsonl: CPU ticks, VmRSS/RssAnon/RssFile/RssShmem, PSS from
# smaps_rollup, DRM memory-region totals and available engine ns from fdinfo, and system counters
# (/proc/stat, loadavg, meminfo, GPU RC6 residency) for noise.
import json, os, sys, time

import drmstats

label = sys.argv[1]
run = os.environ["XDG_RUNTIME_DIR"]
kwin = int(os.environ.get("KWIN_PID", "0"))
me = os.getpid()


def rd(p, mode="r"):
    try:
        with open(p, mode) as f:
            return f.read()
    except Exception:
        return None


def kv(text, keys):
    out = {}
    for line in (text or "").splitlines():
        parts = line.replace(":", " ").split()
        if len(parts) >= 2 and parts[0] in keys:
            try:
                out[parts[0]] = int(parts[1])
            except ValueError:
                pass
    return out


def sudo_fdinfo(pid):
    """KWin's fdinfo is private (file capabilities): read it with sudo -n when PFSTAT_SUDO=1."""
    import subprocess
    try:
        text = subprocess.run(["sudo", "-n", "sh", "-c", f"grep -H '' /proc/{int(pid)}/fdinfo/*"],
                              capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return {}
    out = {}
    for line in text.splitlines():
        path, _, rest = line.partition(":")
        out.setdefault(path.rsplit("/", 1)[-1], []).append(rest)
    return {fd: "\n".join(lines) for fd, lines in out.items()}


def drm(pid):
    private = None
    try:
        fds = os.listdir(f"/proc/{pid}/fdinfo")
    except Exception:
        if pid != kwin or os.environ.get("PFSTAT_SUDO") != "1":
            return None
        private = sudo_fdinfo(pid)
        fds = list(private)
    return drmstats.summarize(private.get(fd) if private is not None else rd(f"/proc/{pid}/fdinfo/{fd}")
                              for fd in fds)


procs = []
others = set()  # other virtual sessions with live processes (noise)
for p in os.listdir("/proc"):
    if not p.isdigit() or int(p) == me:
        continue
    pid = int(p)
    env = rd(f"/proc/{p}/environ", "rb")
    if env:
        for e in env.split(b"\0"):
            if e.startswith(b"XDG_RUNTIME_DIR=/var/tmp/pfv-") and e != f"XDG_RUNTIME_DIR={run}".encode():
                others.add(e.decode(errors="replace").split("/")[3])
    ours = pid == kwin or (env is not None and f"XDG_RUNTIME_DIR={run}".encode() in env.split(b"\0"))
    if not ours:
        continue
    st = rd(f"/proc/{p}/stat")
    if not st:
        continue
    comm = st[st.index("(") + 1: st.rindex(")")]
    if comm in ("pfstat.py", "python3") and pid != kwin:
        # the measuring tools themselves (pfperf/pfstat); counted separately
        comm = "tool:" + comm
    f = st[st.rindex(")") + 2:].split()
    rec = {"pid": pid, "comm": comm, "ticks": int(f[11]) + int(f[12]), "start": int(f[19])}
    rec.update(kv(rd(f"/proc/{p}/status"), {"VmRSS", "RssAnon", "RssFile", "RssShmem", "Threads"}))
    rec.update({k: v for k, v in kv(rd(f"/proc/{p}/smaps_rollup"), {"Pss", "Pss_Anon", "Pss_File", "Pss_Shmem"}).items()})
    g = drm(pid)
    if g:
        rec.update(g)
    procs.append(rec)

g = "/sys/class/drm/card1"
out = {"label": label, "epoch": time.time(), "mono": time.monotonic(),
       "cpu": [int(x) for x in rd("/proc/stat").splitlines()[0].split()[1:]],
       "load": rd("/proc/loadavg").split()[:3],
       "others": sorted(others),
       "mem": kv(rd("/proc/meminfo"), {"MemAvailable", "Shmem"}),
       "rc6_ms": int(rd(g + "/gt/gt0/rc6_residency_ms") or 0), "clk_tck": os.sysconf("SC_CLK_TCK"),
       "procs": procs}
with open(os.path.join(os.environ["OUT"], "stats.jsonl"), "a") as fh:
    fh.write(json.dumps(out) + "\n")
