#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Quick settings' notification service (contents/ui/services/Notifications.qml) on Plasma's own
notification server, on a private D-Bus bus.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 tests/notifications_service_test.py
Requires PySide6, python3-dbus and Plasma's org.kde.notificationmanager QML module.

Plasma's notification model registers the notification server (org.freedesktop.Notifications)
when it is created, so notifications sent on the bus land in the service's history like in the
session: Do Not Disturb's "Until" text and the applications that hold it are checked here. The stock
Notifications applet's Globals (plasma-workspace, its plugin loaded as plasmashell loads it) runs
beside the service as in the session, where it stays loaded and hidden: it inhibits the server for
the end the service writes and ends a timed Do Not Disturb on its wall-clock minute. Waits for two
whole minutes of the clock, so the run takes one to two minutes.
"""

import ctypes
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

# The notification settings (Do Not Disturb's end) go to a throw-away HOME.
for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
    os.environ.pop(key, None)
os.environ["HOME"] = tempfile.mkdtemp(prefix="pf-notifications-")

import dbus  # noqa: E402
from PySide6.QtCore import QDateTime, QLibraryInfo, QObject, QUrl, Slot  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlComponent, QQmlEngine  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

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


# The stock applet's plugin holds its QML module (plasma.applet.org.kde.plasma.notifications) and
# registers it when loaded.
STOCK = Path(QLibraryInfo.path(QLibraryInfo.LibraryPath.PluginsPath), "plasma/applets/org.kde.plasma.notifications.so")
ctypes.CDLL(str(STOCK), mode=ctypes.RTLD_GLOBAL)
app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
context = Context()
engine.rootContext().setContextObject(context)
checks = 0

HARNESS = """
import QtQuick
import org.kde.notificationmanager as NotificationManager
import plasma.applet.org.kde.plasma.notifications as Stock
import "file://%s" as Services
Item {
    Services.Notifications { id: service; objectName: "service" }
    // Reading it makes the stock applet's singleton, as its applet does in the session.
    readonly property bool stockInhibited: Stock.Globals.inhibited
    function inhibit(on: bool) {
        NotificationManager.Server.inhibited = on;
    }
    function untilAt(ms: double) {
        service.dndUntil(new Date(ms));
    }
    function untilMs(): double {
        const until = service.inhibitedUntil;
        return until && !isNaN(until.getTime()) ? until.getTime() : -1;
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


def client(*args):
    """The notification client in its own process: this one runs the server and must keep turning
    its event loop while a call waits for the answer."""
    return subprocess.Popen([sys.executable, "-B", str(here / "notify_client.py"), *args],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)


def call(obj, name, *args):
    from PySide6.QtCore import QMetaObject, Q_ARG
    QMetaObject.invokeMethod(obj, name, *[Q_ARG(type(a), a) for a in args])


def call_ms():
    """The end the notification settings keep, in ms (-1: none)."""
    from PySide6.QtCore import QMetaObject, Q_RETURN_ARG
    return QMetaObject.invokeMethod(root, "untilMs", Q_RETURN_ARG(float))


component = QQmlComponent(engine)
component.setData(HARNESS.encode(), QUrl.fromLocalFile(str(here / "harness.qml")))
root = component.create()
if root is None:
    raise SystemExit("Notification service did not load: " + "; ".join(e.toString() for e in component.errors()))
service = root.findChild(QObject, "service")
wait_for(lambda: service.property("serverValid"), "Plasma's notification server did not register on the bus")
check(bus.name_has_owner("org.freedesktop.Notifications"), "the service's model runs the notification server")

# ---- Do Not Disturb: an end that has passed (choices read long ago) is refused; written, nothing
# would end it.
call(root, "untilAt", float(int(time.time() * 1000) - 60 * 1000))
QTest.qWait(500)
check(not service.property("dndActive") and call_ms() < time.time() * 1000 - 60 * 1000 - 1000,
      "an end that has passed is refused: Do Not Disturb stays off")

# ---- Do Not Disturb: the "Until" text follows the wall clock's minutes, and the stock applet ends it.
def next_minute(margin=3.0):
    """The next whole minute of the wall clock in ms, at least `margin` seconds ahead."""
    now = time.time()
    if 60 - now % 60 < margin:
        time.sleep(60 - now % 60 + 0.1)
        now = time.time()
    return (now // 60 + 1) * 60 * 1000.0


minute = next_minute()
call(root, "untilAt", minute + 24 * 3600 * 1000.0)
wait_for(lambda: service.property("dndActive"), "Do Not Disturb did not turn on")
check(root.property("stockInhibited"), "the stock applet inhibits the server for the end the service wrote")
end = service.property("inhibitedUntil")
end = end.toPython() if isinstance(end, QDateTime) else end
text = service.property("dndUntilText")
check(text.startswith(end.strftime("%a ")), "a day ahead: the end shows its day (%r)" % text)
wait_for(lambda: service.property("dndUntilText") != text, "the text did not change when the end came within 24 h",
         seconds=minute / 1000 - time.time() + 5)
check(":" in service.property("dndUntilText") and time.time() >= minute / 1000,
      "within 24 hours, from that minute of the clock: the time alone (%r)" % service.property("dndUntilText"))
# An end between two minutes (another program's, or the stock applet's own choices, which keep the
# milliseconds): the stock applet ends it on the first minute past it, and the service leaves it.
minute = next_minute(margin=4.0)
short = float(int(time.time() * 1000) + 1500)
call(root, "untilAt", short)
wait_for(lambda: service.property("dndUntilText") != "" and call_ms() == short, "a short Do Not Disturb did not show its end")
wait_for(lambda: not service.property("dndActive"), "Do Not Disturb did not end", seconds=minute / 1000 - time.time() + 5)
check(time.time() >= minute / 1000 and service.property("dndUntilText") == "",
      "it ends on the first minute past its end, by the stock applet")
check(call_ms() == short, "the service left the end to the stock applet (it wrote nothing when it passed)")

# ---- Do Not Disturb held by an application: its name and reason, the stock applet's wording.
call(root, "inhibit", True)
holder = client("inhibit", "org.kde.kdenlive", "Rendering")
wait_for(lambda: prop(service, "dndReasons"), "the inhibiting application was not listed")
reasons = list(prop(service, "dndReasons"))
check(reasons == ["While Kdenlive is active (Rendering)"] or reasons == ["While org.kde.kdenlive is active (Rendering)"],
      "an app that holds it is named with its reason: %r" % reasons)
holder.stdin.close()
wait_for(lambda: holder.poll() is not None, "the inhibiting client did not finish")
wait_for(lambda: not service.property("inhibitedByApp"), "the application's inhibition was not released")
check(list(prop(service, "dndReasons")) == [], "released: no reason left")
call(root, "inhibit", False)

print(f"Notification service: {checks} checks, 0 failures")
