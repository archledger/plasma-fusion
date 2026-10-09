#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the real Plasma calendar adapter on an offscreen, private session bus."""

from pathlib import Path
import sys

from PySide6.QtCore import Q_ARG, QDate, QDateTime, QMetaObject, QTime, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
path = Path(__file__).resolve().parent.parent / "contents/ui/CalendarBackend.qml"
component = QQmlComponent(engine, QUrl.fromLocalFile(str(path)))
date = QDateTime(QDate(2026, 10, 8), QTime(12, 0))
backend = component.createWithInitialProperties({"displayedDate": date, "selectedDate": date,
                                               "today": date, "firstDayOfWeek": 1, "enabledPlugins": []})
if backend is None:
    raise SystemExit("Calendar backend did not load: " + "; ".join(e.toString() for e in component.errors()))
QTest.qWait(150)
checks = 0


def value(name):
    result = backend.property(name)
    return result.toVariant() if hasattr(result, "toVariant") else result


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


days = value("days")
check(len(days) == 42, "native calendar supplies all six weeks")
check((days[0]["year"], days[0]["month"], days[0]["day"]) == (2026, 9, 28), "grid follows regional week start")
check(not value("configured") and not value("events"), "no enabled provider is a setup state, not a configured empty day")
check(all(d["eventCount"] == 0 for d in days), "disabled providers supply no event markers")

backend.setProperty("enabledPlugins", ["org.example.MissingCalendarPlugin"])
QTest.qWait(100)
check(not value("configured"), "a missing provider is not reported as configured")
backend.setProperty("enabledPlugins", [])
backend.setProperty("displayedDate", QDateTime(QDate(2027, 1, 1), QTime(12, 0)))
backend.setProperty("selectedDate", QDateTime(QDate(2027, 1, 3), QTime(12, 0)))
QTest.qWait(100)
days = value("days")
check((days[0]["year"], days[0]["month"], days[0]["day"]) == (2026, 12, 28), "year rollover uses native day dates")
backend.setProperty("displayedDate", QDateTime(QDate(2028, 2, 1), QTime(12, 0)))
QTest.qWait(100)
check(any(d["year"] == 2028 and d["month"] == 2 and d["day"] == 29 for d in value("days")), "leap-day calendar preserved")
# Add event with KOrganizer reported but not reachable (the private bus has none): the failed call
# ends busy and leaves its error, so the buttons work again.
backend.setProperty("korganizerAvailable", True)
QMetaObject.invokeMethod(backend, "openCalendar", Q_ARG(bool, True))
for _ in range(60):
    QTest.qWait(50)
    if not value("busy"):
        break
check(not value("busy") and value("actionError") != "", "a failed calendar call ends busy and reports (%s)" % value("actionError"))
backend.setProperty("korganizerAvailable", False)
print(f"Calendar adapter: {checks} checks, 0 failures; providers {value('providerIds')}")
