#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test stand-in for UPower and the power-profiles daemon on a private bus (never the real system
# bus): the properties plasma-fusion-powerfx reads, writable through org.freedesktop.DBus.Properties.Set
# so a test can play a power change, each Set emitting PropertiesChanged like the real daemons.
#
#   mock-power.py --address ADDRESS [--on-battery] [--percentage P] [--warning-level N]
#                 [--profile NAME] [--no-profiles]
#
# Change a value with, for example:
#   busctl --address=ADDRESS set-property org.freedesktop.UPower \
#     /org/freedesktop/UPower/devices/DisplayDevice org.freedesktop.UPower.Device Percentage d 9
# A set of the same object and interface within one call to org.plasmafusion.Mock.SetMany emits one
# PropertiesChanged with every value (UPower sends several values at once).
import argparse
import sys

from gi.repository import Gio, GLib

XML = """
<node>
  <interface name="org.freedesktop.UPower">
    <property name="OnBattery" type="b" access="readwrite"/>
    <property name="DaemonVersion" type="s" access="read"/>
  </interface>
  <interface name="org.freedesktop.UPower.Device">
    <property name="Percentage" type="d" access="readwrite"/>
    <property name="WarningLevel" type="u" access="readwrite"/>
    <property name="EnergyRate" type="d" access="readwrite"/>
    <property name="IsPresent" type="b" access="read"/>
  </interface>
  <interface name="net.hadess.PowerProfiles">
    <property name="ActiveProfile" type="s" access="readwrite"/>
  </interface>
  <interface name="org.plasmafusion.Mock">
    <method name="SetMany">
      <arg name="path" type="o" direction="in"/>
      <arg name="interface" type="s" direction="in"/>
      <arg name="values" type="a{sv}" direction="in"/>
    </method>
  </interface>
</node>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--address", required=True)
    ap.add_argument("--on-battery", action="store_true")
    ap.add_argument("--percentage", type=float, default=84.0)
    ap.add_argument("--warning-level", type=int, default=1)
    ap.add_argument("--profile", default="balanced")
    ap.add_argument("--no-profiles", action="store_true")
    a = ap.parse_args()

    node = Gio.DBusNodeInfo.new_for_xml(XML)
    iface = {i.name: i for i in node.interfaces}
    state = {
        ("/org/freedesktop/UPower", "org.freedesktop.UPower"): {
            "OnBattery": GLib.Variant("b", a.on_battery), "DaemonVersion": GLib.Variant("s", "mock")},
        ("/org/freedesktop/UPower/devices/DisplayDevice", "org.freedesktop.UPower.Device"): {
            "Percentage": GLib.Variant("d", a.percentage), "WarningLevel": GLib.Variant("u", a.warning_level),
            "EnergyRate": GLib.Variant("d", 7.5), "IsPresent": GLib.Variant("b", True)},
        ("/net/hadess/PowerProfiles", "net.hadess.PowerProfiles"): {
            "ActiveProfile": GLib.Variant("s", a.profile)},
    }
    conn = Gio.DBusConnection.new_for_address_sync(
        a.address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
        None, None)

    def changed(path, name, values):
        state[(path, name)].update(values)
        conn.emit_signal(None, path, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                         GLib.Variant("(sa{sv}as)", (name, values, [])))

    def get_property(_c, _s, path, name, prop):
        return state.get((path, name), {}).get(prop)

    def set_property(_c, _s, path, name, prop, value):
        if (path, name) not in state:
            return False
        changed(path, name, {prop: value})
        return True

    def method_call(_c, _s, _path, _name, method, params, invocation):
        if method == "SetMany":
            path, name, values = params.unpack()
            if (path, name) not in state:
                invocation.return_dbus_error("org.freedesktop.DBus.Error.InvalidArgs", "unknown object")
                return
            typed = {k: GLib.Variant(state[(path, name)][k].get_type_string(), v) for k, v in values.items()}
            changed(path, name, typed)
        invocation.return_value(None)

    objects = [("/org/freedesktop/UPower", ["org.freedesktop.UPower", "org.plasmafusion.Mock"]),
               ("/org/freedesktop/UPower/devices/DisplayDevice", ["org.freedesktop.UPower.Device"])]
    if not a.no_profiles:
        objects.append(("/net/hadess/PowerProfiles", ["net.hadess.PowerProfiles"]))
    for path, names in objects:
        for n in names:
            conn.register_object(path, iface[n], method_call, get_property, set_property)

    def own(name):
        r = conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                           GLib.Variant("(su)", (name, 4)), None, Gio.DBusCallFlags.NONE, -1, None)
        if r.unpack()[0] != 1:
            sys.exit("could not own " + name)

    own("org.freedesktop.UPower")
    if not a.no_profiles:
        own("net.hadess.PowerProfiles")
    print("mock-power ready", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
