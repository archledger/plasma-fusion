#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Adaptive test matrix (ADAPTIVE.md section 11), the part that runs inside a private test session
# (tools/vsession). Reads plasmashell's layout through desktop scripting, KWin's windows and
# outputs through tools/tests/lib/pfkwin.py, Plasma's available screen areas from its StrutManager
# and the settings the matrix changes. Test tool only.
#
#   mx.py state LABEL        write $OUT/state-LABEL.json (layout, windows, outputs, areas, settings)
#   mx.py geo                print "W H QSX QSY CLOCKX CLOCKY DOCKX DOCKY" of the first output:
#                            its logical size, the status pill, the clock pill and the dock's middle
#                            (from the live panel windows)
#   mx.py outputs            output names, one per line (KWin's order)
#   mx.py targets on|off     set the hidden debugDumpTargets key of every Plasma Fusion widget (the
#                            widgets print their touch targets as PFTARGET lines; check.py reads them)
import json, os, subprocess, sys, time

USAGE = "mx.py state LABEL | geo | outputs | targets on|off"
from gi.repository import Gio, GLib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import pfkwin  # noqa: E402

OUT = os.environ.get("OUT") or ""

LAYOUT_JS = r"""
var out = {screens: [], panels: [], desktops: []};
for (var i = 0; i < screenCount; ++i) {
    var g = screenGeometry(i);
    out.screens.push({id: i, x: g.x, y: g.y, w: g.width, h: g.height});
}
function widgets(c) {
    return c.widgets().map(function (w) {
        var g = w.geometry;
        return {id: w.id, type: w.type, x: g.x, y: g.y, w: g.width, h: g.height};
    });
}
panels().forEach(function (p) {
    out.panels.push({id: p.id, location: p.location, screen: p.screen, height: p.height, length: p.length,
                     offset: p.offset, floating: p.floating, hiding: p.hiding, lengthMode: p.lengthMode,
                     alignment: p.alignment, widgets: widgets(p)});
});
desktops().forEach(function (d) {
    out.desktops.push({id: d.id, type: d.type, screen: d.screen, wallpaper: d.wallpaperPlugin, widgets: widgets(d)});
});
print(JSON.stringify(out));
"""

TARGETS_JS = r"""
var n = 0, v = %s;
function set(w) {
    if (String(w.type).indexOf("org.plasmafusion.") !== 0) return;
    w.currentConfigGroup = ["General"];
    w.writeConfig("debugDumpTargets", v);
    n++;
}
panels().forEach(function (p) { p.widgets().forEach(set); });
desktops().forEach(function (d) { d.widgets().forEach(set); });
print(n);
"""

SETTINGS = [("kdeglobals", "General", k) for k in ("font", "menuFont", "toolBarFont", "smallestReadableFont",
                                                   "ColorScheme")] + [
    ("kdeglobals", "WM", "activeFont"), ("kdeglobals", "KDE", "LookAndFeelPackage"),
    ("kdeglobals", "KDE", "AnimationDurationFactor"), ("kcminputrc", "Mouse", "cursorTheme"),
    ("kwinrc", "org.kde.kdecoration2", "library"), ("kwinrc", "org.kde.kdecoration2", "theme"),
    ("kwinrc", "org.kde.kdecoration2", "ButtonsOnLeft"), ("kwinrc", "org.kde.kdecoration2", "ButtonsOnRight"),
    ("kwinrc", "Input", "TabletMode"), ("plasmafusionrc", "Decoration", "ButtonStyle")]


def bus():
    return Gio.bus_get_sync(Gio.BusType.SESSION, None)


def plasma_eval(js):
    r = bus().call_sync("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript",
                        GLib.Variant("(s)", (js,)), GLib.VariantType("(s)"), Gio.DBusCallFlags.NONE, 10000, None)
    return r.unpack()[0]


def kwin_prop(iface, prop):
    try:
        r = bus().call_sync("org.kde.KWin", "/org/kde/KWin", "org.freedesktop.DBus.Properties", "Get",
                            GLib.Variant("(ss)", (iface, prop)), None, Gio.DBusCallFlags.NONE, 3000, None)
        return r.unpack()[0]
    except GLib.Error:
        return None


def avail(outputs, screen_ids):
    res = {}
    for o in outputs:
        sid = screen_ids.get(o["name"], -1)
        for sig, arg in (("(s)", o["name"]), ("(i)", sid)):
            try:
                r = bus().call_sync("org.kde.plasmashell", "/StrutManager", "org.kde.PlasmaShell.StrutManager",
                                    "availableScreenRect", GLib.Variant(sig, (arg,)), None,
                                    Gio.DBusCallFlags.NONE, 5000, None)
                x, y, w, h = r.unpack()[0]
                res[o["name"]] = {"x": x, "y": y, "w": w, "h": h}
                break
            except (GLib.Error, TypeError, ValueError):
                continue
    return res


def settings():
    out = {}
    for f, g, k in SETTINGS:
        try:
            out["%s/%s/%s" % (f, g, k)] = subprocess.run(
                ["kreadconfig6", "--file", f, "--group", g, "--key", k], capture_output=True, text=True,
                timeout=10).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            out["%s/%s/%s" % (f, g, k)] = None
    return out


def state(label):
    s = {"label": label, "time": time.time()}
    try:
        s["plasma"] = json.loads(plasma_eval(LAYOUT_JS))
    except (GLib.Error, ValueError) as e:
        s["plasma"] = {"screens": [], "panels": [], "desktops": [], "error": str(e)}
    try:
        s["kwin"] = pfkwin.run(pfkwin.WINDOWS)
    except SystemExit as e:
        s["kwin"] = {"windows": [], "outputs": [], "error": str(e)}
    names = [o["name"] for o in s["kwin"].get("outputs", [])]
    try:
        s["screen_ids"] = json.loads(plasma_eval(
            "var m = {}; var n = %s; for (var i = 0; i < n.length; ++i) m[n[i]] = screenForConnector(n[i]); "
            "print(JSON.stringify(m));" % json.dumps(names)))
    except (GLib.Error, ValueError):
        s["screen_ids"] = {}
    s["avail"] = avail(s["kwin"].get("outputs", []), s["screen_ids"])
    s["tablet_mode"] = kwin_prop("org.kde.KWin.TabletModeManager", "tabletMode")
    s["settings"] = settings()
    with open(os.path.join(OUT, "state-%s.json" % label), "w") as f:
        json.dump(s, f, indent=1, sort_keys=True)
    return s


def geo():
    k = pfkwin.run(pfkwin.WINDOWS)
    o = k["outputs"][0]["geo"]
    inside = lambda g: o["x"] <= g["x"] < o["x"] + o["w"] and o["y"] <= g["y"] < o["y"] + o["h"]
    docks = [w["geo"] for w in k["windows"] if w["dock"] and inside(w["geo"])]
    top = min(docks, key=lambda g: g["y"]) if docks else {"x": o["x"], "y": o["y"], "w": o["w"], "h": 34}
    bottom = max(docks, key=lambda g: g["y"]) if len(docks) > 1 else {"x": o["x"] + o["w"] / 4, "y": o["y"] + o["h"] - 104,
                                                                     "w": o["w"] / 2, "h": 104}
    print(int(o["w"]), int(o["h"]), int(top["x"] + top["w"] - 88), int(top["y"] + top["h"] / 2),
          int(top["x"] + top["w"] / 2), int(top["y"] + top["h"] / 2),
          int(bottom["x"] + bottom["w"] / 2), int(bottom["y"] + bottom["h"] / 2))


def main(argv):
    if len(argv) < 2:
        raise SystemExit(USAGE)
    cmd = argv[1]
    if cmd in ("state",) and not os.path.isdir(OUT):
        raise SystemExit("mx.py: OUT (the session's output directory) is not set")
    if cmd == "state":
        state(argv[2])
    elif cmd == "geo":
        geo()
    elif cmd == "outputs":
        for o in pfkwin.run(pfkwin.WINDOWS)["outputs"]:
            print(o["name"])
    elif cmd == "targets":
        print(plasma_eval(TARGETS_JS % ("true" if argv[2] == "on" else "false")))
    else:
        raise SystemExit("unknown command %s" % cmd)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
