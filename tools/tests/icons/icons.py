#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Desktop icon positions test (BACKLOG M2), the part that runs inside a private test session
# (tools/vsession). Reads plasmashell's live configuration through desktop scripting, KWin's windows
# through tools/tests/lib/pfkwin.py and this session's core dumps from the journal.
#
#   icons.py desktop-id                 id and plugin of the desktop containment on screen 0
#   icons.py upgrade BEFORE AFTER       compare two states around an upgrade: every panel with its
#                                       widgets, the dock's pinned apps and the desktop cards kept
#                                       (checks.jsonl step 00-upgrade; exit 1 if not)
#   icons.py state LABEL                write $OUT/state-LABEL.json
#   icons.py plan                       pfinput drag commands for the target pattern (one per line)
#   icons.py pattern                    check that the target pattern is in place (exit 1 if not)
#   icons.py base                       save the current state as the baseline ($ICONS_BASE)
#   icons.py check STEP                 compare the current state with the baseline; append the
#                                       result to $OUT/checks.jsonl, print it; exit 1 on failure
#
# Environment: OUT, XDG_RUNTIME_DIR (the session), ICONS_BASE (default ~/pf-icons-base.json),
# ICONS_RES (the original resolution key, default taken from the baseline), PFV_T0 (session start,
# epoch seconds; core dumps are counted from there).
import json, os, subprocess, sys, time
from gi.repository import Gio, GLib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import pfkwin  # noqa: E402

OUT = os.environ.get("OUT")
if not OUT or not os.path.isdir(OUT):
    raise SystemExit("icons.py: OUT (the session's output directory) is not set")
BASE = os.environ.get("ICONS_BASE", os.path.expanduser("~/pf-icons-base.json"))
LAST = os.path.join(os.path.dirname(BASE), "pf-icons-last.json")  # previous check, across sessions
FILES = ["file%02d.txt" % i for i in range(1, 13)]
# Target cells, 0-based (column, row) of the grid: file01 at column 5, row 4 (1-based), the others
# scattered so that the pattern cannot be the automatic one. All inside the first 12 columns, clear
# of the desktop cards on the right.
TARGETS = {"file01.txt": (4, 3), "file02.txt": (2, 1), "file03.txt": (7, 0),
           "file04.txt": (1, 5), "file05.txt": (9, 6), "file06.txt": (5, 0)}
CELL_BASE = 96          # Folder View's minimum cell width at iconSize 2 (48 px) and labelWidth 1
ICON_Y = 30             # from the top of a cell to the middle of its 48 px icon (4 px padding)
COREDUMP_ID = "fc2e22bc6ee647b6b90729ab34a250b1"

STATE_JS = r"""
var out = {desktops: [], panels: []};
var ds = desktops();
for (var i = 0; i < ds.length; ++i) {
    var d = ds[i];
    var rec = {id: d.id, type: d.type, screen: d.screen, top: {}, general: {}, widgets: []};
    d.currentConfigGroup = [];
    var tkeys = d.configKeys;
    for (var t = 0; t < tkeys.length; ++t) {
        rec.top[tkeys[t]] = String(d.readConfig(tkeys[t], ""));
    }
    d.currentConfigGroup = ["General"];
    var keys = d.configKeys;
    for (var k = 0; k < keys.length; ++k) {
        rec.general[keys[k]] = String(d.readConfig(keys[k], ""));
    }
    d.currentConfigGroup = [];
    var ws = d.widgets();
    for (var w = 0; w < ws.length; ++w) {
        var g = ws[w].geometry;
        rec.widgets.push({id: ws[w].id, type: ws[w].type, x: g.x, y: g.y, w: g.width, h: g.height});
    }
    out.desktops.push(rec);
}
var ps = panels();
for (var p = 0; p < ps.length; ++p) {
    var pw = ps[p].widgets(), types = [], pins = null;
    for (var q = 0; q < pw.length; ++q) {
        types.push(pw[q].type);
        if (pw[q].type === "org.plasmafusion.dock") {
            pw[q].currentConfigGroup = ["General"];
            pins = String(pw[q].readConfig("launchers", ""));
        }
    }
    out.panels.push({id: ps[p].id, location: ps[p].location, hiding: ps[p].hiding, height: ps[p].height,
                     screen: ps[p].screen, floating: ps[p].floating, widgets: types, pins: pins});
}
print(JSON.stringify(out));
"""


def bus():
    return Gio.bus_get_sync(Gio.BusType.SESSION, None)


def plasma_eval(js):
    r = bus().call_sync("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript",
                        GLib.Variant("(s)", (js,)), GLib.VariantType("(s)"), Gio.DBusCallFlags.NONE, 10000, None)
    return r.unpack()[0]


def avail_rect(state, screen_id):
    """Plasma's available rect of a screen: from plasmashell's StrutManager when it answers, else
    the output minus the panels that are not auto-hide (their KWin windows include the floating
    margin, as Plasma's totalThickness does)."""
    outs = state["kwin"].get("outputs", [])
    ids = state.get("screen_ids", {})
    named = [o for o in outs if ids.get(o["name"]) == screen_id]
    if named:  # Plasma's screen ids do not follow KWin's output order
        outs = named + [o for o in outs if o not in named]
        screen_id = 0
    for sig, arg in (("(s)", outs[screen_id]["name"] if screen_id < len(outs) else ""), ("(i)", screen_id)):
        try:
            r = bus().call_sync("org.kde.plasmashell", "/StrutManager", "org.kde.PlasmaShell.StrutManager",
                                "availableScreenRect", GLib.Variant(sig, (arg,)), None,
                                Gio.DBusCallFlags.NONE, 5000, None)
            x, y, w, h = r.unpack()[0]
            return {"x": x, "y": y, "w": w, "h": h, "from": "StrutManager" + sig}
        except (GLib.Error, TypeError, ValueError):
            pass
    if screen_id >= len(outs):
        return {"error": "no output %d" % screen_id}
    o = outs[screen_id]["geo"]
    x, y, w, h = o["x"], o["y"], o["w"], o["h"]
    hiding = {p["location"]: p["hiding"] for p in state["plasma"].get("panels", []) if p["screen"] == screen_id}
    for win in state["kwin"].get("windows", []):
        g = win["geo"]
        if not win["dock"] or not (o["x"] <= g["x"] < o["x"] + o["w"] and o["y"] <= g["y"] < o["y"] + o["h"]):
            continue
        if g["y"] == o["y"] and g["h"] < o["h"] / 2 and hiding.get("top") != "autohide":
            y, h = o["y"] + g["h"], h - (o["y"] + g["h"] - y)
        elif g["y"] + g["h"] == o["y"] + o["h"] and hiding.get("bottom") != "autohide":
            h = min(h, g["y"] - y)
    return {"x": int(x), "y": int(y), "w": int(w), "h": int(h), "from": "panels"}


def coredumps(since):
    """Core dumps since `since` (epoch s): (ours, others); ours = environ has this session's runtime dir."""
    run = "XDG_RUNTIME_DIR=" + os.environ.get("XDG_RUNTIME_DIR", "?")
    try:
        text = subprocess.run(["journalctl", "-o", "json", "MESSAGE_ID=" + COREDUMP_ID, "--since", "@%d" % int(since),
                               "--no-pager"], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.TimeoutExpired):
        return [], []
    ours, others = [], []
    for line in text.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        env = e.get("COREDUMP_ENVIRON") or ""
        if isinstance(env, list):  # journalctl gives binary fields as byte lists
            env = bytes(env).decode("utf-8", "replace")
        rec = {"exe": e.get("COREDUMP_EXE"), "pid": e.get("COREDUMP_PID"), "signal": e.get("COREDUMP_SIGNAL_NAME"),
               "time": int(e.get("__REALTIME_TIMESTAMP", "0")) / 1e6}
        (ours if run in env.split("\n") else others).append(rec)
    return ours, others


def icon_desktop(state):
    """The desktop containment that shows the icons: Folder View with the test files, else screen 0."""
    best = None
    for d in state["plasma"]["desktops"]:
        if d["type"] in ("org.kde.plasma.folder", "org.plasmafusion.desktop") and "positions" in d["general"]:
            return d
        if d["screen"] == 0 and best is None:
            best = d
    return best


def positions(d):
    raw = (d or {}).get("general", {}).get("positions", "").replace("\\,", ",")
    try:
        return raw, json.loads(raw) if raw else {}
    except ValueError:
        return raw, {}


def raw_entry(raw, res):
    """The bytes of one resolution's entry inside the positions JSON, exactly as stored."""
    key = json.dumps(res) + ":"
    i = raw.find(key)
    if i < 0:
        return None
    j = i + len(key)
    _, end = json.JSONDecoder().raw_decode(raw, j)
    return raw[j:end]


def cells(entry):
    """{name: (stripe, pos)} and the header (numStripes, perStripe) of one positions entry."""
    if not entry or len(entry) < 2:
        return None, {}
    head = (entry[0], entry[1])
    body = entry[2:]
    return head, {body[i]: (int(body[i + 1]), int(body[i + 2])) for i in range(0, len(body) - 2, 3)}


def capture(label):
    s = {"label": label, "time": time.time()}
    try:
        s["plasma"] = json.loads(plasma_eval(STATE_JS))
    except (GLib.Error, ValueError) as e:
        s["plasma"] = {"desktops": [], "panels": [], "error": str(e)}
    try:
        s["kwin"] = pfkwin.run(pfkwin.WINDOWS)
    except SystemExit as e:
        s["kwin"] = {"windows": [], "outputs": [], "error": str(e)}
    names = [o["name"] for o in s["kwin"].get("outputs", [])]
    try:
        s["screen_ids"] = json.loads(plasma_eval("var m = {}; var n = %s; for (var i = 0; i < n.length; ++i) "
                                                 "m[n[i]] = screenForConnector(n[i]); print(JSON.stringify(m));"
                                                 % json.dumps(names)))
    except (GLib.Error, ValueError):
        s["screen_ids"] = {}
    n = max(1, len(names))
    s["avail"] = [avail_rect(s, i) for i in range(n)]
    ours, others = coredumps(float(os.environ.get("PFV_T0", s["time"] - 600)))
    s["coredumps"], s["coredumps_other"] = ours, others
    with open(os.path.join(OUT, "state-%s.json" % label), "w") as f:
        json.dump(s, f, indent=1, sort_keys=True)
    return s


def grid(state):
    d = icon_desktop(state)
    g = d["general"]
    raw, pos = positions(d)
    res = g.get("lastResolution") or next(iter(pos), None)
    head, cl = cells(pos.get(res)) if res else (None, {})
    screen = max(0, d["screen"])
    r = state["avail"][screen] if screen < len(state["avail"]) else state["avail"][0]
    ncol = max(1, r["w"] // CELL_BASE)
    per_fit = max(1, r["h"] // CELL_BASE)
    per = int(head[1]) if head else per_fit
    arrangement = int(g.get("arrangement", "0") or 0)
    guessed = False
    if cl and arrangement == 1 and per > per_fit:
        # Positions saved while the area was taller (the layout's Folder View writes them before the
        # dock has taken its room): Folder View shows the same order in columns of per_fit, so the
        # cells are re-flowed the same way.
        cl = {u: divmod(stripe * per + pos, per_fit) for u, (stripe, pos) in cl.items()}
        per = per_fit
    if not cl:
        # No positions saved yet (Plasma writes them on the first move): the files are listed in
        # creation order (the order readdir gives on this file system; the test creates them in
        # name order), one stripe after the other.
        guessed = True
        cl = {"desktop:/" + f: (i // per, i % per) for i, f in enumerate(FILES)} if arrangement == 1 else \
             {"desktop:/" + f: (i // ncol, i % ncol) for i, f in enumerate(FILES)}
        res = res or "%dx%d" % (state["kwin"]["outputs"][screen]["geo"]["w"], state["kwin"]["outputs"][screen]["geo"]["h"])
    return {"x": r["x"], "y": r["y"], "cw": r["w"] // ncol, "ch": r["h"] // per, "per": per, "ncol": ncol,
            "arrangement": arrangement, "cells": cl, "res": res, "guessed": guessed, "avail": r}


def centre(gr, col, row):
    return gr["x"] + col * gr["cw"] + gr["cw"] // 2, gr["y"] + row * gr["ch"] + ICON_Y


def col_row(gr, stripe, pos):
    # arrangement 1 (top to bottom) fills columns: a stripe is a column
    return (stripe, pos) if gr["arrangement"] == 1 else (pos, stripe)


def plan():
    st = capture("plan")
    gr = grid(st)
    occupied = {col_row(gr, *v): k for k, v in gr["cells"].items()}
    lines = []
    for name, (col, row) in TARGETS.items():
        url = "desktop:/" + name
        if url not in gr["cells"]:
            print("# %s has no position yet" % name, file=sys.stderr)
            continue
        c0 = col_row(gr, *gr["cells"][url])
        if c0 == (col, row):
            continue
        if (col, row) in occupied:
            print("# target of %s is taken by %s" % (name, occupied[(col, row)]), file=sys.stderr)
        x1, y1 = centre(gr, *c0)
        x2, y2 = centre(gr, col, row)
        # slow drag: hold 0.4 s after the press, 24 steps 30 ms apart, 0.4 s before the release
        lines.append("drag %d %d %d %d 24 0.03 0.4 0.4" % (x1, y1, x2, y2))
        occupied.pop(c0, None)
        occupied[(col, row)] = url
    json.dump(gr, open(os.path.join(OUT, "grid.json"), "w"), indent=1, default=str)
    print("\n".join(lines))


def pattern_ok(st):
    gr = grid(st)
    bad = []
    for name, want in TARGETS.items():
        got = gr["cells"].get("desktop:/" + name)
        got = col_row(gr, *got) if got else None
        if got != want:
            bad.append({"file": name, "want": want, "got": got})
    return bad


def summary(st, res):
    d = icon_desktop(st)
    raw, pos = positions(d)
    widgets = sorted([w["type"], w["id"], round(w["x"], 1), round(w["y"], 1), round(w["w"], 1), round(w["h"], 1)]
                     for w in (d or {}).get("widgets", []))
    g = (d or {}).get("general", {})
    top = (d or {}).get("top", {})
    return {"containment": (d or {}).get("id"), "type": (d or {}).get("type"), "screen": (d or {}).get("screen"),
            "entry_raw": raw_entry(raw, res) if res else None, "entry": pos.get(res), "resolutions": sorted(pos),
            "lastResolution": g.get("lastResolution"), "itemgeom": top.get("ItemGeometries-" + res) if res else None,
            "itemgeom_keys": sorted(k for k in top if k.startswith("ItemGeometries")), "widgets": widgets}


def popups(st):
    out = []
    for w in st["kwin"].get("windows", []):
        shell = w["cls"] in ("plasmashell", "org.kde.plasmashell")
        if w["popup"] or w["tooltip"] or w["osd"] or w["dialog"] or (shell and not w["dock"] and not w["desktop"]
                                                                     and not w["notification"]):
            out.append({"cls": w["cls"], "caption": w["caption"], "geo": w["geo"], "hidden": w["hidden"]})
    notes = [{"cls": w["cls"], "caption": w["caption"]} for w in st["kwin"].get("windows", []) if w["notification"]]
    return out, notes


def check(step):
    base = json.load(open(BASE))
    res = os.environ.get("ICONS_RES") or base["res"]
    st = capture(step)
    cur = summary(st, res)
    b = base["summary"]
    _, bcells = cells(b["entry"])
    bhead = (b["entry"] or [None, None])[:2]
    chead, ccells = cells(cur["entry"])
    moved = sorted(k for k in set(bcells) | set(ccells) if bcells.get(k) != ccells.get(k))
    pop, notes = popups(st)
    try:
        last = json.load(open(LAST))
    except (OSError, ValueError):
        last = {"step": "base", "entry_raw": b["entry_raw"]}
    json.dump({"step": step, "entry_raw": cur["entry_raw"]}, open(LAST, "w"))
    on = [n for n, i in st.get("screen_ids", {}).items() if i == cur["screen"]]
    t0 = float(os.environ.get("PFV_T0", "0"))
    dumps = [c for c in st["coredumps"] if c["time"] >= t0]
    r = {
        "step": step,
        "positions_bytes_equal": cur["entry_raw"] is not None and cur["entry_raw"] == b["entry_raw"],
        "positions_same_cells": cur["entry"] is not None and not moved,
        "header_equal": list(chead or []) == list(bhead),
        "moved": [{"file": k, "base": bcells.get(k), "now": ccells.get(k)} for k in moved],
        "header": {"base": bhead, "now": list(chead) if chead else None},
        "resolutions": cur["resolutions"], "lastResolution": cur["lastResolution"],
        "cards_equal": cur["widgets"] == b["widgets"],
        "itemgeom_equal": cur["itemgeom"] == b["itemgeom"],
        "cards": cur["widgets"] if cur["widgets"] != b["widgets"] else "same",
        "popups": pop, "notifications": notes, "coredumps": dumps,
        "containment": cur["containment"], "screen": cur["screen"], "icons_on": on[0] if on else None,
        "rewritten": cur["entry_raw"] != last["entry_raw"], "previous_step": last["step"],
        "outputs": [(o["name"], o["geo"], o["scale"]) for o in st["kwin"].get("outputs", [])],
        "avail": st["avail"],
    }
    others_ok = r["cards_equal"] and r["itemgeom_equal"] and not pop and not dumps
    # Per event: PASS the stored entry is byte-identical to the one before this step and every file
    # keeps its baseline cell; REWRITTEN Plasma saved the entry again during this step (another hash
    # order or grid header) but every file keeps its cell; FAIL anything else. positions_bytes_equal
    # compares with the baseline itself (the M2 acceptance wording).
    r["result"] = ("FAIL" if not (others_ok and r["positions_same_cells"])
                   else "REWRITTEN" if r["rewritten"] else "PASS")
    r["pass"] = r["result"] != "FAIL"
    with open(os.path.join(OUT, "checks.jsonl"), "a") as f:
        f.write(json.dumps(r, sort_keys=True) + "\n")
    print(json.dumps({k: r[k] for k in ("step", "result", "positions_bytes_equal", "positions_same_cells",
                                        "header_equal", "rewritten", "icons_on", "cards_equal", "itemgeom_equal")},
                     sort_keys=True))
    return r["pass"]


def upgrade(before, after):
    """An upgrade keeps every panel (location) with the widgets it had, the dock's pinned apps and
    the desktop cards (type and geometry); new widgets are allowed."""
    a = json.load(open(os.path.join(OUT, "state-%s.json" % before)))
    b = json.load(open(os.path.join(OUT, "state-%s.json" % after)))
    bad = []
    pa = {p["location"]: p for p in a["plasma"].get("panels", [])}
    pb = {p["location"]: p for p in b["plasma"].get("panels", [])}
    for loc, p in sorted(pa.items()):
        if loc not in pb:
            bad.append("the %s panel is gone" % loc)
            continue
        lost = [w for w in p.get("widgets", []) if w not in pb[loc].get("widgets", [])]
        if lost:
            bad.append("the %s panel lost %s" % (loc, ", ".join(lost)))
        if p.get("pins") is not None and p.get("pins") != pb[loc].get("pins"):
            bad.append("dock pins changed: %s -> %s" % (p.get("pins"), pb[loc].get("pins")))
    cards = lambda st: sorted((w["type"], round(w["x"]), round(w["y"]), round(w["w"]), round(w["h"]))
                              for d in st["plasma"].get("desktops", []) for w in d["widgets"])
    if cards(a) != cards(b):
        bad.append("desktop cards changed: %s -> %s" % (cards(a), cards(b)))
    plug = lambda st: sorted((d["screen"], d["type"]) for d in st["plasma"].get("desktops", []))
    r = {"step": "00-upgrade", "result": "FAIL" if bad else "PASS", "pass": not bad, "problems": bad,
         "desktop_before": plug(a), "desktop_after": plug(b),
         "panels_before": {k: v.get("widgets") for k, v in pa.items()},
         "panels_after": {k: v.get("widgets") for k, v in pb.items()},
         "coredumps": [c for c in b.get("coredumps", []) if c["time"] >= float(os.environ.get("PFV_T0", "0"))]}
    if r["coredumps"]:
        r["result"], r["pass"] = "FAIL", False
    with open(os.path.join(OUT, "upgrade.json"), "w") as f:
        json.dump(r, f, indent=1)
    print(json.dumps({k: r[k] for k in ("step", "result", "problems", "desktop_before", "desktop_after")}))
    return r["pass"]


def main(argv):
    cmd = argv[0] if argv else ""
    if cmd == "desktop-id":
        st = json.loads(plasma_eval(STATE_JS))
        ds = [d for d in st["desktops"] if d["screen"] == 0] or st["desktops"]
        print(ds[0]["id"], ds[0]["type"])
    elif cmd == "upgrade":
        return 0 if upgrade(argv[1], argv[2]) else 1
    elif cmd == "state":
        capture(argv[1])
    elif cmd == "plan":
        plan()
    elif cmd == "pattern":
        bad = pattern_ok(capture("pattern"))
        print(json.dumps(bad))
        return 1 if bad else 0
    elif cmd == "base":
        st = capture("base")
        gr = grid(st)
        if os.path.exists(LAST):
            os.unlink(LAST)
        json.dump({"res": gr["res"], "grid": {k: v for k, v in gr.items() if k != "cells"},
                   "summary": summary(st, gr["res"]), "time": st["time"]}, open(BASE, "w"), indent=1)
        print(gr["res"])
    elif cmd == "check":
        return 0 if check(argv[1]) else 1
    else:
        print("usage: icons.py desktop-id|state LABEL|plan|pattern|base|check STEP|upgrade BEFORE AFTER", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
