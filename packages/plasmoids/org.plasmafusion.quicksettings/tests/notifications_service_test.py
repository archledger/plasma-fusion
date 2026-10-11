#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Quick settings' notification service (contents/ui/services/Notifications.qml) on Plasma's own
notification server, on a private D-Bus bus.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 tests/notifications_service_test.py
Requires PySide6, python3-dbus and Plasma's org.kde.notificationmanager QML module.

Plasma's notification model registers the notification server (org.freedesktop.Notifications)
when it is created, so notifications sent on the bus land in the service's history like in the
session: Do Not Disturb's "Until" text is checked here.
"""

from pathlib import Path
import sys
import time

import dbus
from PySide6.QtCore import QDateTime, QObject, QUrl, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

here = Path(__file__).resolve().parent
bus = dbus.SessionBus()
if bus.name_has_owner("org.freedesktop.Notifications") or bus.name_has_owner("org.kde.plasmashell"):
    raise SystemExit("Run on a fresh private bus; refusing a live desktop bus")


class Context(QObject):
    """The i18n functions Plasma provides (KLocalizedContext), without translations."""

    @staticmethod
    def fill(text, args):
        for number, arg in enumerate(args, 1):
            text = text.replace("%" + str(number), str(arg))
        return text

    @Slot(str, result=str)
    @Slot(str, str, result=str)
    @Slot(str, str, str, result=str)
    def i18n(self, text, a1=None, a2=None):
        return self.fill(text, [a for a in (a1, a2) if a is not None])

    @Slot(str, str, result=str)
    @Slot(str, str, str, result=str)
    @Slot(str, str, str, str, result=str)
    def i18nc(self, context, text, a1=None, a2=None):
        return self.fill(text, [a for a in (a1, a2) if a is not None])


app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
context = Context()
engine.rootContext().setContextObject(context)
checks = 0

HARNESS = """
import QtQuick
import org.kde.notificationmanager as NotificationManager
import "file://%s" as Services
Item {
    Services.Notifications { id: service; objectName: "service" }
    function inhibit(on: bool) {
        NotificationManager.Server.inhibited = on;
    }
    function untilIn(ms: double) {
        service.dndUntil(new Date(Date.now() + ms));
    }
}
""" % (here.parent / "contents/ui/services")


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


def prop(obj, name):
    value = obj.property(name)
    return value.toVariant() if hasattr(value, "toVariant") else value


def call(obj, name, *args):
    from PySide6.QtCore import QMetaObject, Q_ARG
    QMetaObject.invokeMethod(obj, name, *[Q_ARG(type(a), a) for a in args])


component = QQmlComponent(engine)
component.setData(HARNESS.encode(), QUrl.fromLocalFile(str(here / "harness.qml")))
root = component.create()
if root is None:
    raise SystemExit("Notification service did not load: " + "; ".join(e.toString() for e in component.errors()))
service = root.findChild(QObject, "service")
wait_for(lambda: service.property("serverValid"), "Plasma's notification server did not register on the bus")
check(bus.name_has_owner("org.freedesktop.Notifications"), "the service's model runs the notification server")

# ---- Do Not Disturb: the "Until" text follows the clock.
call(root, "untilIn", 24 * 3600 * 1000.0 + 1500)
wait_for(lambda: service.property("dndActive"), "Do Not Disturb did not turn on")
end = service.property("inhibitedUntil")
end = end.toPython() if isinstance(end, QDateTime) else end
text = service.property("dndUntilText")
check(text.startswith(end.strftime("%a ")), "a day ahead: the end shows its day (%r)" % text)
wait_for(lambda: service.property("dndUntilText") != text, "the text did not change when the end came within 24 h",
         seconds=4)
check(":" in service.property("dndUntilText") and service.property("dndUntilText") != text,
      "within 24 hours: the time alone (%r), without anything else changing" % service.property("dndUntilText"))
call(root, "untilIn", 1200.0)
wait_for(lambda: service.property("dndUntilText") != "", "a short Do Not Disturb shows no end")
wait_for(lambda: not service.property("dndActive"), "Do Not Disturb did not end on time", seconds=3)
check(not service.property("dndActive") and service.property("dndUntilText") == "", "it ends on time, by itself")

print(f"Notification service: {checks} checks, 0 failures")
