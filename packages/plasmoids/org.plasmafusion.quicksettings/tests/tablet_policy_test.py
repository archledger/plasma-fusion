#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The on-screen keyboard's D-Bus replies in TabletPolicy.qml, on a private bus with a stand-in
KWin.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 tests/tablet_policy_test.py

Plasma's D-Bus QML module (plasma-workspace 6.7.5 DBusConnection::asyncCall) calls a reply
handler whenever the reply comes, also after the widget that asked is gone (a panel removed while
the call was out), and logs what the handler throws. The stand-in KWin answers /VirtualKeyboard
and /Effects after 400 ms: the state reaches the policy while it is there, and a reply after it
was destroyed logs no TypeError (2026-10-16 settings-file session: two from quick settings while
an import removed the bars). Requires PySide6, python3-dbus, python3-gobject and Plasma's D-Bus
QML module.
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import dbus
from PySide6.QtCore import QMetaObject, QUrl, Q_ARG, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

here = Path(__file__).resolve().parent
bus = dbus.SessionBus()
if bus.name_has_owner("org.kde.KWin") or bus.name_has_owner("org.kde.plasmashell"):
    raise SystemExit("Run on a fresh private bus; refusing a live desktop bus")
# The policy reads kwinrc and plasmafusionrc when it starts: a scratch configuration.
scratch = tempfile.TemporaryDirectory(prefix="pf-tablet-policy-")
os.environ["XDG_CONFIG_HOME"] = scratch.name

KWIN = r'''
import sys
import dbus, dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
DELAY = 400
class Keyboard(dbus.service.Object):
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s",
                         out_signature="a{sv}", async_callbacks=("ok", "err"))
    def GetAll(self, iface, ok, err):
        state = {"available": True, "visible": False, "active": False, "enabled": True}
        GLib.timeout_add(DELAY, lambda: ok(state) and False)
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv",
                         async_callbacks=("ok", "err"))
    def Set(self, iface, name, value, ok, err):
        GLib.timeout_add(DELAY, lambda: ok() and False)
    @dbus.service.method("org.kde.kwin.VirtualKeyboard", async_callbacks=("ok", "err"))
    def forceActivate(self, ok, err):
        GLib.timeout_add(DELAY, lambda: ok() and False)
class Effects(dbus.service.Object):
    @dbus.service.method("org.kde.kwin.Effects", in_signature="s", out_signature="b",
                         async_callbacks=("ok", "err"))
    def isEffectLoaded(self, name, ok, err):
        GLib.timeout_add(DELAY, lambda: ok(True) and False)
    @dbus.service.method("org.kde.kwin.Effects", in_signature="s", out_signature="b")
    def unloadEffect(self, name):
        return True
name = dbus.service.BusName("org.kde.KWin", bus)
Keyboard(bus, "/VirtualKeyboard")
Effects(bus, "/Effects")
print("ready", flush=True)
GLib.MainLoop().run()
'''

messages = []


def handler(mode, context, text):
    messages.append(text)
    sys.stderr.write(text + "\n")


qInstallMessageHandler(handler)
app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
kwin = subprocess.Popen([sys.executable, "-c", KWIN], stdout=subprocess.PIPE, text=True)
checks = 0


def wait_for(predicate, message, seconds=5):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        QTest.qWait(20)
        if predicate():
            return
    raise AssertionError(message)


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


def type_errors():
    return [m for m in messages if "TypeError" in m or "ReferenceError" in m]


def gone_before_reply(call, *args):
    """A policy asks KWin and is destroyed before the reply comes."""
    policy = component.createWithInitialProperties({"leader": False})
    if policy is None:
        raise AssertionError("TabletPolicy did not load: "
                             + "; ".join(e.toString() for e in component.errors()))
    QTest.qWait(100)
    before = len(type_errors())
    QMetaObject.invokeMethod(policy, call, *args)
    policy.deleteLater()
    QTest.qWait(1000)  # the reply comes after 400 ms
    return type_errors()[before:]


try:
    assert kwin.stdout.readline().strip() == "ready", "the stand-in KWin did not start"
    source = here.parent / "contents/ui/services/TabletPolicy.qml"
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(source)))
    policy = component.createWithInitialProperties({"leader": False})
    if policy is None:
        raise AssertionError("TabletPolicy did not load: "
                             + "; ".join(e.toString() for e in component.errors()))
    QMetaObject.invokeMethod(policy, "refreshOsk")
    wait_for(lambda: policy.property("oskAvailable"), "the keyboard's state did not arrive")
    check(policy.property("oskAvailable") and not policy.property("oskVisible"),
          "the stand-in KWin's keyboard state reaches the policy (available, not visible)")
    check(not type_errors(), "and nothing is thrown")
    policy.deleteLater()
    QTest.qWait(100)

    errors = gone_before_reply("refreshOsk")
    check(not errors,
          "the state's reply after the policy was destroyed throws nothing (%s)" % errors)
    errors = gone_before_reply("toggleOsk")
    check(not errors, "the keyboard shown, its reply after the policy was destroyed throws"
          " nothing (%s)" % errors)
    errors = gone_before_reply("setOskProperty", Q_ARG(str, "active"), Q_ARG(bool, False))
    check(not errors,
          "a property set, its reply after the policy was destroyed throws nothing (%s)" % errors)
    errors = gone_before_reply("applyOverview", Q_ARG(bool, True))
    check(not errors, "KWin's Overview asked about in tablet posture, the reply after the policy"
          " was destroyed throws nothing (%s)" % errors)
finally:
    kwin.terminate()
    kwin.wait(5)
    scratch.cleanup()

print(f"tablet policy: {checks} checks passed")
