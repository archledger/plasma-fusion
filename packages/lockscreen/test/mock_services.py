#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test services for the lock screen harness, for a private session bus only.

  mpris   an MPRIS player "Music" (paused, no track), like the Lock board's media card
  notify  a notification server that accepts org.kde.NotificationManager.RegisterWatcher and
          then sends the watcher the Lock board's notifications (Calendar x1, Mail x3)

Usage: mock_services.py [mpris] [notify]   (runs until killed)
"""
import sys
import time

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
BUS = dbus.SessionBus()
MPRIS_IF = "org.mpris.MediaPlayer2"
PLAYER_IF = "org.mpris.MediaPlayer2.Player"
PROPS_IF = "org.freedesktop.DBus.Properties"


class Player(dbus.service.Object):
    def __init__(self):
        self.name = dbus.service.BusName("org.mpris.MediaPlayer2.pfmusic", BUS)
        super().__init__(BUS, "/org/mpris/MediaPlayer2")
        self.status = "Paused"

    def _props(self, interface):
        if interface == MPRIS_IF:
            return {"Identity": "Music", "DesktopEntry": "org.kde.elisa", "CanQuit": False,
                    "CanRaise": False, "HasTrackList": False,
                    "SupportedUriSchemes": dbus.Array([], "s"), "SupportedMimeTypes": dbus.Array([], "s")}
        return {"PlaybackStatus": self.status, "LoopStatus": "None", "Rate": 1.0, "Shuffle": False,
                "Metadata": dbus.Dictionary({"mpris:trackid": dbus.ObjectPath("/org/mpris/MediaPlayer2/TrackList/NoTrack")}, "sv"),
                "Volume": 1.0, "Position": dbus.Int64(0), "MinimumRate": 1.0, "MaximumRate": 1.0,
                "CanGoNext": False, "CanGoPrevious": False, "CanPlay": True, "CanPause": True,
                "CanSeek": False, "CanControl": True}

    @dbus.service.method(PROPS_IF, in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        return self._props(interface)[prop]

    @dbus.service.method(PROPS_IF, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return self._props(interface)

    @dbus.service.method(PROPS_IF, in_signature="ssv")
    def Set(self, interface, prop, value):
        pass

    @dbus.service.signal(PROPS_IF, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    @dbus.service.method(PLAYER_IF)
    def PlayPause(self):
        self.status = "Playing" if self.status != "Playing" else "Paused"
        print("mpris: PlayPause ->", self.status, flush=True)
        self.PropertiesChanged(PLAYER_IF, {"PlaybackStatus": self.status}, [])

    @dbus.service.method(PLAYER_IF)
    def Play(self):
        self.PlayPause()

    @dbus.service.method(PLAYER_IF)
    def Pause(self):
        self.PlayPause()

    @dbus.service.method(PLAYER_IF)
    def Next(self):
        pass

    @dbus.service.method(PLAYER_IF)
    def Previous(self):
        pass

    @dbus.service.method(MPRIS_IF)
    def Raise(self):
        pass


class NotificationServer(dbus.service.Object):
    def __init__(self):
        self.name = dbus.service.BusName("org.freedesktop.Notifications", BUS)
        super().__init__(BUS, "/org/freedesktop/Notifications")
        self.next_id = 1

    @dbus.service.method("org.kde.NotificationManager", sender_keyword="sender")
    def RegisterWatcher(self, sender=None):
        print("notify: watcher registered", sender, flush=True)
        GLib.timeout_add(300, self.send, sender)

    @dbus.service.method("org.kde.NotificationManager", sender_keyword="sender")
    def UnRegisterWatcher(self, sender=None):
        pass

    @dbus.service.method("org.freedesktop.Notifications", out_signature="ssss")
    def GetServerInformation(self):
        return ("mock", "test", "1", "1.2")

    @dbus.service.signal("org.freedesktop.Notifications", signature="uu")
    def NotificationClosed(self, nid, reason):
        pass

    def send(self, watcher):
        obj = BUS.get_object(watcher, "/NotificationWatcher")
        notify = obj.get_dbus_method("Notify", "org.kde.NotificationWatcher")
        items = [("Calendar", "office-calendar", "Team sync", "Event starting in 10 min", "org.kde.merkuro.calendar")]
        items += [("Mail", "internet-mail", "Message %d" % i, "Private body text", "org.kde.kmail2") for i in range(3)]
        for app, icon, summary, body, desktop in items:
            hints = dbus.Dictionary({"desktop-entry": desktop}, "sv")
            notify(dbus.UInt32(self.next_id), app, dbus.UInt32(0), icon, summary, body,
                   dbus.Array([], "s"), hints, dbus.Int32(-1))
            self.next_id += 1
            time.sleep(0.05)
        print("notify: sent", len(items), flush=True)
        return False


services = []
if "mpris" in sys.argv[1:]:
    services.append(Player())
if "notify" in sys.argv[1:]:
    services.append(NotificationServer())
if "inhibit" in sys.argv[1:]:
    # Do Not Disturb for as long as this process runs: the session's notification server keeps
    # forwarding notifications to watchers (the lock screen) but shows no pop-ups over it.
    server = BUS.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
    cookie = server.get_dbus_method("Inhibit", "org.freedesktop.Notifications")(
        "org.kde.dolphin", "Lock screen test", dbus.Dictionary({}, "sv"))
    print("inhibit: cookie", int(cookie), flush=True)
    services.append(cookie)
print("mock services up:", [type(s).__name__ for s in services], flush=True)
GLib.MainLoop().run()
