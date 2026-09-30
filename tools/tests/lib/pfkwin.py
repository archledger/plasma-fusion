#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Run a KWin script in a private test session (tools/vsession) and print what it reports, as
# JSON. Test tool only: it talks to the session bus of the environment it runs in.
#
#   pfkwin.py windows              every window (class, caption, type flags, geometry, output),
#                                  the outputs and their work areas
#   pfkwin.py run 'JS'             any script body; it calls report(value) once
#   pfkwin.py maximize CLASS       maximize the newest window of resourceClass CLASS
#   pfkwin.py close CLASS          close every window of resourceClass CLASS
#
# The script reaches this process through callDBus() to a private object on the session bus,
# then the script is unloaded again.
import json, os, sys, time
from gi.repository import Gio, GLib

IFACE = "org.plasmafusion.TestSink"
XML = """<node><interface name="%s"><method name="Report"><arg type="s" direction="in"/></method>
</interface></node>""" % IFACE

PRELUDE = r"""
function report(v) {
    callDBus("%(me)s", "/Sink", "%(iface)s", "Report", JSON.stringify(v));
}
function rect(g) { return {x: g.x, y: g.y, w: g.width, h: g.height}; }
"""

WINDOWS = r"""
var list = workspace.windowList();
var out = {windows: [], outputs: []};
for (var i = 0; i < list.length; ++i) {
    var w = list[i];
    out.windows.push({cls: String(w.resourceClass), name: String(w.resourceName), caption: String(w.caption),
        popup: w.popupWindow, dock: w.dock, desktop: w.desktopWindow, normal: w.normalWindow,
        dialog: w.dialog, tooltip: w.tooltip, notification: w.notification, osd: w.onScreenDisplay,
        special: w.specialWindow, hidden: w.hidden, minimized: w.minimized, maximized: false,
        output: w.output ? String(w.output.name) : "", geo: rect(w.frameGeometry),
        id: String(w.internalId)});
}
var screens = workspace.screens;
for (var s = 0; s < screens.length; ++s) {
    var o = screens[s];
    out.outputs.push({name: String(o.name), geo: rect(o.geometry), scale: o.devicePixelRatio,
        work: rect(workspace.clientArea(KWin.MaximizeArea, o, workspace.currentDesktop))});
}
report(out);
"""


def run(body, timeout=6.0):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    got = []

    def on_call(conn, sender, path, iface, method, params, invocation):
        got.append(params.unpack()[0])
        invocation.return_value(None)

    node = Gio.DBusNodeInfo.new_for_xml(XML)
    reg = bus.register_object("/Sink", node.interfaces[0], on_call, None, None)
    name = "pfkwin_%d_%d" % (os.getpid(), int(time.time() * 1000) % 100000)
    tmpdir = os.environ.get("OUT") or os.environ.get("PFV") or os.environ.get("XDG_RUNTIME_DIR")
    if not tmpdir:
        raise SystemExit("pfkwin: no session directory (OUT, PFV or XDG_RUNTIME_DIR)")
    path = os.path.join(tmpdir, ".%s.js" % name)
    with open(path, "w") as f:
        f.write(PRELUDE % {"me": bus.get_unique_name(), "iface": IFACE} + body)

    def call(method, args, sig):
        return bus.call_sync("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", method,
                             GLib.Variant(sig, args) if args is not None else None, None,
                             Gio.DBusCallFlags.NONE, 5000, None)
    try:
        call("loadScript", (path, name), "(ss)")
        call("start", None, None)
        ctx = GLib.MainContext.default()
        end = time.monotonic() + timeout
        while not got and time.monotonic() < end:
            ctx.iteration(False)
            time.sleep(0.01)
    finally:
        try:
            call("unloadScript", (name,), "(s)")
        except GLib.Error:
            pass
        bus.unregister_object(reg)
        try:
            os.unlink(path)
        except OSError:
            pass
    if not got:
        raise SystemExit("pfkwin: no report from the KWin script within %.0f s" % timeout)
    return json.loads(got[0])


def main(argv):
    if not argv:
        raise SystemExit("usage: pfkwin.py windows | run JS | maximize CLASS | close CLASS")
    cmd = argv[0]
    if cmd == "windows":
        out = run(WINDOWS)
    elif cmd == "run":
        out = run(argv[1])
    elif cmd == "maximize":
        out = run(r"""
var list = workspace.windowList(), hit = null;
for (var i = 0; i < list.length; ++i) if (String(list[i].resourceClass) === %s && list[i].normalWindow) hit = list[i];
if (hit) { workspace.activeWindow = hit; hit.setMaximize(true, true); }
report({maximized: hit ? String(hit.caption) : null});
""" % json.dumps(argv[1]))
    elif cmd == "close":
        out = run(r"""
var list = workspace.windowList(), n = 0;
for (var i = 0; i < list.length; ++i) if (String(list[i].resourceClass) === %s) { list[i].closeWindow(); ++n; }
report({closed: n});
""" % json.dumps(argv[1]))
    else:
        raise SystemExit("pfkwin: unknown command " + cmd)
    print(json.dumps(out, indent=1, sort_keys=True))


if __name__ == "__main__":
    main(sys.argv[1:])
