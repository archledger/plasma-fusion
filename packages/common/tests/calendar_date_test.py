#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Today's date over a calendar app's tile (FusionIconTile, calendarDate).

  QT_QPA_PLATFORM=offscreen python3 packages/common/tests/calendar_date_test.py

The calendar tile art carries a fixed "SEP" / "28". The launcher's AppTile and the dock's TaskItem
paint today's month and day over it; every other app tile (the tablet launcher sheet, the tablet
home screen, the window cards, the launch zoom) turns on the shared block's own overlay
(calendarDate: true; tools/checks/calendar-tile.py asks for it). This checks the block: the
overlay is drawn for a calendar app with calendarDate on, shows today's day and month, follows
a new day when the tile is shown again (a resume from suspend), and stays off for another app
or with calendarDate off. Needs PySide6 (Qt Quick, offscreen) and Kirigami's QML module.
"""
import datetime
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PySide6.QtCore import QDate, QLocale, QMetaObject, QObject, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[3]
COMMON = ROOT / "packages" / "common"
checks = 0
failures = []


def check(ok, message):
    global checks
    checks += 1
    print(("PASS " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)


ui = Path(tempfile.mkdtemp(prefix="pf-calendar-date-"))
shutil.copy(COMMON / "FusionIconTile.qml", ui / "FusionIconTile.qml")
subprocess.run(["bash", str(ROOT / "tools/build-lib/shared-qml.sh"), "names", str(ui / "FusionIconNames.js")],
               check=True, timeout=60)
(ui / "Harness.qml").write_text("""import QtQuick
Item {
    width: 300
    height: 100
    FusionIconTile { objectName: "calendar"; size: 64; source: "korganizer"; iconName: "korganizer"; calendarDate: true }
    FusionIconTile { objectName: "plain"; x: 70; size: 64; source: "korganizer"; iconName: "korganizer" }
    FusionIconTile { objectName: "other"; x: 140; size: 64; source: "kate"; iconName: "org.kde.kate"; calendarDate: true }
    // The day before, as the tile shows it after a night in suspend (set from JavaScript: a
    // Python datetime does not reach a var property as a Date).
    function setBack(): void {
        const t = children[0];
        t.today = new Date(t.today.getFullYear(), t.today.getMonth(), t.today.getDate() - 1, 12);
    }
}
""")

app = QGuiApplication(sys.argv[:1])
view = QQuickView()
view.setSource(QUrl.fromLocalFile(str(ui / "Harness.qml")))
if view.status() == QQuickView.Status.Error:
    print("FAIL the harness did not load: " + "; ".join(e.toString() for e in view.errors()))
    sys.exit(1)
view.show()
QTest.qWait(200)
root = view.rootObject()


def tile(name):
    return root.findChild(QObject, name)


now = datetime.datetime.now()
cal = tile("calendar")
shown, day, month = cal.property("calendarTile"), cal.property("dayText"), cal.property("monthText")
check(shown is True, "a calendar app's tile with calendarDate draws today's date (calendarTile %r)" % shown)
check(day == str(now.day), "the day is today's (%r)" % day)
expected_month = QLocale().toString(QDate.currentDate(), "MMM").upper().replace(".", "")
check(month == expected_month, "the month is today's, short and upper case (%r, want %r)" % (month, expected_month))
check(tile("plain").property("calendarTile") is False, "with calendarDate off (the default) the block draws nothing")
check(tile("other").property("calendarTile") is False, "another app's tile gets no date")

# A tile shown again after the date changed (a resume from suspend, a new day) shows the new day.
cal.setProperty("visible", False)
QTest.qWait(50)
yesterday = now - datetime.timedelta(days=1)
QMetaObject.invokeMethod(root, "setBack")
check(cal.property("dayText") == str(yesterday.day), "the tile can be set back a day (%r)" % cal.property("dayText"))
cal.setProperty("visible", True)
QTest.qWait(200)
check(cal.property("dayText") == str(datetime.datetime.now().day), "shown again, it rechecks the date (%r)" % cal.property("dayText"))

print(f"Calendar date: {checks} checks, {len(failures)} failures")
sys.exit(1 if failures else 0)
