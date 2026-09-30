#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test stand-in for KWin's effects interface and plasmashell's scripting on a private session bus
# (never the user's): org.kde.KWin /Effects (loadEffect, unloadEffect, isEffectLoaded; each call is
# logged) and org.kde.plasmashell /PlasmaShell evaluateScript, which runs the script with
# fake-shell.js against a layout JSON file. org.plasmafusion.MockSession on /MockSession plays a
# plasmashell restart: ReleaseShell drops the name, OwnShell takes it again.
#
#   mock-session.py --address ADDRESS --layout LAYOUT.json --log CALLS.log [--node PATH] [--no-shell]
#                   [--no-kwin]
import argparse
import os
import subprocess
import sys

from gi.repository import Gio, GLib

XML = """
<node>
  <interface name="org.kde.kwin.Effects">
    <method name="loadEffect"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
    <method name="unloadEffect"><arg type="s" direction="in"/></method>
    <method name="isEffectLoaded"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
  </interface>
  <interface name="org.kde.PlasmaShell">
    <method name="evaluateScript"><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
  </interface>
  <interface name="org.plasmafusion.MockSession">
    <method name="ReleaseShell"/>
    <method name="OwnShell"/>
  </interface>
</node>
"""
HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--address", required=True)
    ap.add_argument("--layout", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--node", default="node")
    ap.add_argument("--no-shell", action="store_true")
    ap.add_argument("--no-kwin", action="store_true")
    a = ap.parse_args()
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    iface = {i.name: i for i in node.interfaces}
    loaded = {"blur": True}

    def log(text):
        with open(a.log, "a") as f:
            f.write(text + "\n")

    def dbus(method, *args):
        return c.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", method,
                           GLib.Variant("(" + "".join(t for t, _ in args) + ")", tuple(v for _, v in args)),
                           None, Gio.DBusCallFlags.NONE, -1, None)

    def call(_c, _s, _path, name, method, params, inv):
        if name == "org.kde.kwin.Effects":
            (effect,) = params.unpack()
            if method == "isEffectLoaded":
                inv.return_value(GLib.Variant("(b)", (loaded.get(effect, False),)))
                return
            log(f"kwin {method} {effect}")
            if method == "loadEffect":
                loaded[effect] = True
                inv.return_value(GLib.Variant("(b)", (True,)))
            else:
                loaded[effect] = False
                inv.return_value(None)
        elif name == "org.kde.PlasmaShell":
            (script,) = params.unpack()
            r = subprocess.run([a.node, os.path.join(HERE, "fake-shell.js"), a.layout, a.log + ".writes"],
                               input=script, capture_output=True, text=True)
            if r.returncode != 0:
                inv.return_dbus_error("org.freedesktop.DBus.Error.Failed", r.stderr.strip()[-300:])
                return
            apply = "apply: true" in script.splitlines()[0]
            log(f"shell evaluateScript {'apply' if apply else 'plan'} -> {r.stdout}")
            inv.return_value(GLib.Variant("(s)", (r.stdout,)))
        else:
            if method == "ReleaseShell":
                dbus("ReleaseName", ("s", "org.kde.plasmashell"))
            else:
                dbus("RequestName", ("s", "org.kde.plasmashell"), ("u", 4))
            log(f"mock {method}")
            inv.return_value(None)

    c = Gio.DBusConnection.new_for_address_sync(
        a.address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
        None, None)
    c.register_object("/Effects", iface["org.kde.kwin.Effects"], call, None, None)
    c.register_object("/PlasmaShell", iface["org.kde.PlasmaShell"], call, None, None)
    c.register_object("/MockSession", iface["org.plasmafusion.MockSession"], call, None, None)
    names = ["org.plasmafusion.MockSession"]
    if not a.no_kwin:
        names.append("org.kde.KWin")
    if not a.no_shell:
        names.append("org.kde.plasmashell")
    for n in names:
        if dbus("RequestName", ("s", n), ("u", 4)).unpack()[0] != 1:
            sys.exit("could not own " + n)
    print("mock-session ready", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
