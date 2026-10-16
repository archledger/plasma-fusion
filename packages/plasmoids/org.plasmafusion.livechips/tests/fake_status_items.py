#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Stand-ins for the status items the live chips read, for the session tests (not installed).

Each registers an org.kde.StatusNotifierItem with the session's org.kde.StatusNotifierWatcher, with
the properties KStatusNotifierItem gives it (kstatusnotifieritem.cpp) and the values the real app
sets (xdg-desktop-portal-kde screencast.cpp and remotedesktop.cpp, Spectacle SpectacleCore.cpp):

  fake_status_items.py screen APP window|screen     the portal's "Screen casting" item, menu End
  fake_status_items.py remote APP input|view        the portal's "Remote Control" item, menu End
  fake_status_items.py recording SECONDS            Spectacle's recording item; its tooltip's time
                                                    runs on (KFormat's m:ss); Activate finishes it

It prints one line per event ("ended KIND", "activated recording") and exits when the chips end
the item (End, Activate) or after --timeout seconds (default 300). English texts only: the
session tests run in English.
"""
import argparse
import os
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

SNI = "org.kde.StatusNotifierItem"
MENU = "com.canonical.dbusmenu"
PROPS = "org.freedesktop.DBus.Properties"


def tooltip(icon, title, subtitle):
    return dbus.Struct((dbus.String(icon), dbus.Array([], signature="(iiay)"), dbus.String(title), dbus.String(subtitle)),
                       signature="sa(iiay)ss")


def base_props():
    """The properties every KStatusNotifierItem has, with their values when unset."""
    return {
        "Category": dbus.String("ApplicationStatus"), "Status": dbus.String("Active"), "WindowId": dbus.Int32(0),
        "IconPixmap": dbus.Array([], signature="(iiay)"), "OverlayIconName": dbus.String(""),
        "OverlayIconPixmap": dbus.Array([], signature="(iiay)"), "AttentionIconName": dbus.String(""),
        "AttentionIconPixmap": dbus.Array([], signature="(iiay)"), "AttentionMovieName": dbus.String(""),
        "ItemIsMenu": dbus.Boolean(False), "Menu": dbus.ObjectPath("/MenuBar"),
    }


def screen_props(app, window):
    """The portal's "Screen casting" item for APP, sharing a window or the screen."""
    return dict(base_props(), Id=dbus.String("xdg-desktop-portal-kde"), ItemIsMenu=dbus.Boolean(True),
                Title=dbus.String("Screen casting"), IconName=dbus.String("media-record"),
                OverlayIconName=dbus.String("window" if window else "monitor"),
                ToolTip=tooltip("", "Screen casting", "Sharing contents to %s" % app))


def recording_props(seconds):
    """Spectacle's recording item, SECONDS into the recording."""
    return dict(base_props(), Id=dbus.String("Spectacle"), Category=dbus.String("SystemServices"), Title=dbus.String("Spectacle"),
                IconName=dbus.String("media-record"), ToolTip=recording_tooltip(seconds))


def recording_tooltip(seconds):
    return tooltip("", "Spectacle is Recording", "Time recorded: %d:%02d\nClick to finish recording" % (seconds // 60, seconds % 60))


class Item(dbus.service.Object):
    """One status item at PATH (/StatusNotifierItem, as KStatusNotifierItem's), with its menu at
    /MenuBar."""

    def __init__(self, bus, props, on_activate=None, path="/StatusNotifierItem"):
        self.props = props
        self.on_activate = on_activate
        dbus.service.Object.__init__(self, bus, path)

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.props[name]

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return dbus.Dictionary(self.props, signature="sv") if interface == SNI else dbus.Dictionary({}, signature="sv")

    @dbus.service.method(SNI, in_signature="ii")
    def Activate(self, x, y):
        if self.on_activate:
            self.on_activate()

    @dbus.service.method(SNI, in_signature="ii")
    def SecondaryActivate(self, x, y):
        pass

    @dbus.service.method(SNI, in_signature="ii")
    def ContextMenu(self, x, y):
        pass

    @dbus.service.method(SNI, in_signature="is")
    def Scroll(self, delta, orientation):
        pass

    @dbus.service.signal(SNI)
    def NewToolTip(self):
        pass

    @dbus.service.signal(SNI)
    def NewIcon(self):
        pass


class Menu(dbus.service.Object):
    """A dbusmenu with one action, End (the portal's QMenu)."""

    def __init__(self, bus, on_end):
        self.on_end = on_end
        dbus.service.Object.__init__(self, bus, "/MenuBar")

    @dbus.service.method(MENU, in_signature="iias", out_signature="u(ia{sv}av)")
    def GetLayout(self, parent, depth, names):
        end = dbus.Struct((dbus.Int32(1), dbus.Dictionary({"label": dbus.String("End"), "icon-name": dbus.String("process-stop"),
                                                            "enabled": dbus.Boolean(True), "visible": dbus.Boolean(True)}, signature="sv"),
                           dbus.Array([], signature="v")), signature="ia{sv}av")
        root = dbus.Struct((dbus.Int32(0), dbus.Dictionary({"children-display": dbus.String("submenu")}, signature="sv"),
                            dbus.Array([end], signature="v")), signature="ia{sv}av")
        return dbus.UInt32(1), root

    @dbus.service.method(MENU, in_signature="i", out_signature="b")
    def AboutToShow(self, item):
        return False

    @dbus.service.method(MENU, in_signature="isvu")
    def Event(self, item, event, data, timestamp):
        if item == 1 and event == "clicked":
            self.on_end()

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return {"Version": dbus.UInt32(3), "Status": dbus.String("normal")}[name]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["screen", "remote", "recording"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--timeout", type=int, default=300)
    a = ap.parse_args()

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()
    name = "org.kde.StatusNotifierItem-%d-1" % os.getpid()
    held = dbus.service.BusName(name, bus)

    def done(line):
        print(line, flush=True)
        GLib.timeout_add(200, loop.quit)

    if a.kind in ("screen", "remote"):
        app = a.args[0] if a.args else "Firefox"
        if a.kind == "screen":
            props = screen_props(app, (a.args[1] if len(a.args) > 1 else "window") == "window")
        else:
            props = dict(base_props(), Id=dbus.String("xdg-desktop-portal-kde"), ItemIsMenu=dbus.Boolean(True))
            text = "%s is exercising remote control privileges:" % app
            if (a.args[1] if len(a.args) > 1 else "input") == "input":
                text += "\n - Move the pointer and type keystrokes"
            else:
                text += "\n - See what’s on the screen"
            props.update(Title=dbus.String("Remote Control"), IconName=dbus.String("krfb"),
                         ToolTip=tooltip("", "Remote Control", text))
        Item(bus, props)
        Menu(bus, lambda: done("ended " + a.kind))
    else:
        seconds = [int(a.args[0]) if a.args else 0]
        item = Item(bus, recording_props(seconds[0]), on_activate=lambda: done("activated recording"))

        def tick():
            seconds[0] += 1
            item.props["ToolTip"] = recording_tooltip(seconds[0])
            item.NewToolTip()
            return True
        GLib.timeout_add(1000, tick)

    watcher = bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
    watcher.RegisterStatusNotifierItem(name, dbus_interface="org.kde.StatusNotifierWatcher")
    print("registered %s %s" % (a.kind, name), flush=True)
    GLib.timeout_add_seconds(a.timeout, lambda: done("timeout") or False)
    loop.run()
    del held
    return 0


if __name__ == "__main__":
    sys.exit(main())
