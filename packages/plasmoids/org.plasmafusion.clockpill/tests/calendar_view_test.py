#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise calendar selection/keyboard/touch layout in the staged real QML.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 calendar_view_test.py STAGE_HOME
"""

import os
from pathlib import Path
import sys

os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PySide6.QtCore import Property, QDate, QDateTime, QObject, QPoint, QPointF, QRectF, QTime, QTimeZone, Qt, QUrl, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickItem, QQuickView
from PySide6.QtTest import QTest


class Context(QObject):
    @Slot(str, result=str)
    def i18n(self, text):
        return text

    @Slot(str, str, result=str)
    def i18nc(self, context, text):
        return text

    @Slot(str, str, str, int, result=str)
    def i18ncp(self, context, singular, plural, count):
        return (singular if count == 1 else plural).replace("%1", str(count))


class PlasmoidContext(QObject):
    @Property("QVariant", constant=True)
    def containment(self):
        return {"availableScreenRect": QRectF(0, 0, 1440, 900)}


app = QGuiApplication(sys.argv[:1])
view = QQuickView()
context, plasmoid = Context(), PlasmoidContext()
view.rootContext().setContextObject(context)
view.rootContext().setContextProperty("Plasmoid", plasmoid)
now = QDateTime(QDate(2026, 10, 8), QTime(12, 0))
view.setInitialProperties({"now": now, "firstDayOfWeek": 1, "dark": False, "open": False})
source = Path(sys.argv[1]).resolve() / ".local/share/plasma/plasmoids/org.plasmafusion.clockpill/contents/ui/CalendarView.qml"
view.setSource(QUrl.fromLocalFile(str(source)))
if view.status() == QQuickView.Error:
    raise SystemExit("Calendar view failed to load: " + "; ".join(e.toString() for e in view.errors()))
root = view.rootObject()
view.resize(round(root.implicitWidth()), round(root.implicitHeight()))
view.show()
root.forceActiveFocus()
QTest.qWait(100)
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


check(root.property("selectedDate").date() == now.date(), "opens on today's selected day")
QTest.keyClick(view, Qt.Key_Right)
check(root.property("selectedDate").date() == now.date().addDays(1), "Right moves the selected day, not an entire month")
QTest.keyClick(view, Qt.Key_Down)
check(root.property("selectedDate").date() == now.date().addDays(8), "Down moves one week")
QTest.keyClick(view, Qt.Key_Home)
check(root.property("selectedDate").date() == now.date(), "Home returns selection to today")
root.setProperty("shown", QDateTime(QDate(2028, 1, 1), QTime(12, 0)))
root.setProperty("selectedDate", QDateTime(QDate(2028, 1, 31), QTime(12, 0)))
QTest.keyClick(view, Qt.Key_PageDown)
check(root.property("selectedDate").date() == QDate(2028, 2, 29), "month navigation clamps the selected day at leap February")
QTest.keyClick(view, Qt.Key_Home)
QTest.qWait(50)
def visual_items(item: QQuickItem):
    yield item
    for child in item.childItems():
        yield from visual_items(child)


cells = [item for item in visual_items(root) if item.property("eventCount") is not None]
check(len(cells) == 42, "all day cells are interactive")
target = next(item for item in cells if item.property("day").date() == QDate(2026, 10, 12))
point = target.mapToScene(QPointF(target.width() / 2, target.height() / 2))
QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(round(point.x()), round(point.y())))
check(root.property("selectedDate").date() == QDate(2026, 10, 12), "clicking a date selects that day's agenda")
root.setProperty("touch", True)
QTest.qWait(50)
check(all(item.height() >= 44 for item in cells), "touch day targets reach 44 pixels")
root.setProperty("open", True)
QTest.qWait(500)
check(root.property("backend") is not None, "optional native calendar adapter loads when opened")
root.setProperty("selectedTimeZones", ["America/New_York", "Europe/London", "Asia/Tokyo"])
QTest.qWait(200)
zones = [item for item in visual_items(root) if item.property("zoneId") is not None]
check(len(zones) == 3, "selected world clocks are created")
for item in zones:
    zone = item.property("zoneId")
    expected = QDateTime.currentDateTimeUtc().toTimeZone(QTimeZone(zone.encode()))
    got = item.property("currentTime")
    check(got.date() == expected.date() and got.time().hour() == expected.time().hour(),
          f"native {zone} clock respects offset, DST and date boundary")
print(f"Calendar view: {checks} checks, 0 failures")
