#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the real Plasma calendar adapter and the bar's layout state on an offscreen, private
session bus."""

from pathlib import Path
import collections
import hashlib
import json
import re
import sys
import time

from PySide6.QtCore import (Q_ARG, SLOT, ClassInfo, QCoreApplication, QDate, QDateTime, QEvent, QLocale, QMetaObject,
                            QObject, QTime, QUrl, Slot, qInstallMessageHandler, Q_RETURN_ARG, Qt)
from PySide6.QtDBus import QDBusConnection, QDBusConnectionInterface
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

# The bar's layout state (contents/ui/LayoutState.qml), the clock's side of the workspace layout
# transport, against stand-ins on this private bus: KWin's name and the provider lifetimes'
# identity names, held on this connection or a second one, and kglobalaccel's component, which
# records the wakes. Its checks go on after a failure, so that one run shows them all.
WAKE = "Plasma Fusion: Refresh Layout Controls"
PREFIX = "org.plasmafusion.LayoutProvider.p"
E1, E2, E3, E4 = (hashlib.md5(name.encode()).hexdigest() for name in ("one", "two", "three", "four"))
VIEW = {"desktopId": "desktop-1", "activityId": "activity-1", "outputName": "Virtual-0"}
failures = []
events = []
MISSING = object()  # a field the frame leaves out


def expect(condition, message):
    global checks
    checks += 1
    print(("PASS " if condition else "FAIL ") + message)
    if not condition:
        failures.append(message)


def until(test, ms=2000):
    for _ in range(ms // 10):
        if test():
            return True
        QTest.qWait(10)
    return test()


def prop(item, name):
    result = item.property(name)
    return result.toVariant() if hasattr(result, "toVariant") else result


@ClassInfo({"D-Bus Interface": "org.kde.kglobalaccel.Component"})
class Shortcuts(QObject):
    """kglobalaccel's component for KWin's shortcuts, recording each one invoked."""

    @Slot(str)
    def invokeShortcut(self, name):
        events.append(("wake", name))


bus = QDBusConnection.sessionBus()
second = QDBusConnection.connectToBus(QDBusConnection.SessionBus, "layout-state-second")
shortcuts = Shortcuts()
check(bus.registerService("org.kde.kglobalaccel")
      and bus.registerObject("/component/kwin", shortcuts, QDBusConnection.ExportAllSlots),
      "layout state: kglobalaccel's stand-in is on the bus")
check(bus.registerService("org.kde.KWin") and bus.registerService(PREFIX + E1)
      and bus.registerService(PREFIX + E2) and bus.registerService(PREFIX + E1.upper())
      and bus.registerService(PREFIX + E1[:31]) and second.isConnected() and second.registerService(PREFIX + E4),
      "layout state: KWin's name and the identity names are held here, one elsewhere")
owner, stranger = bus.baseService(), second.baseService()
layout_component = QQmlComponent(engine, QUrl.fromLocalFile(
    str(Path(__file__).resolve().parent.parent / "contents/ui/LayoutState.qml")))


def create(**initial):
    item = layout_component.createWithInitialProperties(initial)
    check(item is not None, "layout state: LayoutState.qml loads ("
          + "; ".join(e.toString() for e in layout_component.errors()) + ")")
    log = {"requests": [], "history": []}

    def requested(text):
        log["requests"].append(json.loads(text))
        events.append(("request", text))

    def snapshot():
        log["history"].append((prop(item, "revision"), prop(item, "mode"), prop(item, "outcome"),
                               prop(item, "epoch")))

    item.requested.connect(requested)
    for signal in (item.revisionChanged, item.modeChanged, item.outcomeChanged, item.epochChanged):
        signal.connect(snapshot)
    return item, log


def frame(log, revision, epoch=E1, status="online", backend=None, **fields):
    """A frame answering the item's last request, as the provider writes one."""
    request = log["requests"][-1]
    result = {"version": 1, "consumer": request["consumer"], "request": request["request"], "epoch": epoch,
              "identityName": PREFIX + epoch, "backendOwner": backend or owner, "revision": revision,
              "status": status}
    if status == "offline":
        result.update(capable=False, view=None, tiled=False)
    elif "refused" not in fields:
        result.update(capable=True, view=dict(VIEW, outputName=request["outputName"]), tiled=False)
    result.update(fields)
    return result


def deliver(item, value):
    item.setProperty("response", value if isinstance(value, str) else json.dumps(value))


state, log = create(outputName="")
QTest.qWait(50)
expect(prop(state, "mode") == "unknown" and prop(state, "outcome") == "idle" and not log["requests"]
       and not events, "layout state: with no output it asks nothing and is unknown")
state.setProperty("outputName", "Virtual-0")
until(lambda: len(events) == 2)
first = log["requests"][0] if log["requests"] else {}
expect(sorted(first) == ["consumer", "intent", "outputName", "request", "version"]
       and first["version"] == 1 and first["intent"] == "query" and first["request"] == 1
       and first["outputName"] == "Virtual-0" and isinstance(first["consumer"], str)
       and 0 < len(first["consumer"]) <= 128, "layout state: an output asks a version-1 query for it (%s)" % first)
expect([kind for kind, _ in events] == ["request", "wake"] and events[1][1] == WAKE,
       "layout state: the provider is woken after the request is saved (%s)" % events)
expect(prop(state, "mode") == "unknown" and prop(state, "outcome") == "pending",
       "layout state: unknown while the request is out")

# A clock that starts with the answer an earlier instance was given, as after a shell restart: it
# names that instance's consumer and request, so it never counts, and the new instance's own
# answer does.
earlier, earlier_log = create(outputName="Virtual-0")
until(lambda: earlier_log["requests"])
retained = frame(earlier_log, 9, tiled=True)
earlier.deleteLater()
QTest.qWait(50)
fresh, fresh_log = create(outputName="Virtual-0", response=json.dumps(retained))
until(lambda: fresh_log["requests"])
deliver(fresh, dict(retained, revision=10))
deliver(fresh, frame(fresh_log, 11))
expect(until(lambda: prop(fresh, "revision") == 11) and prop(fresh, "mode") == "floating"
       and fresh_log["requests"][0]["consumer"] != retained["consumer"]
       and not [h for h in fresh_log["history"] if h[0] in (9, 10)],
       "layout state: the answer an earlier instance was given never counts, the new instance's own does")
fresh.deleteLater()
QTest.qWait(50)

# What comes after the component is gone touches nothing of it: a reply, an answer or a failed
# lookup, to a check that was out, and a request queued just before. Each instance is destroyed
# before the bus answers or the queued call runs.
warnings = []
qInstallMessageHandler(lambda mode, context, message: warnings.append(message))
queued, queued_log = create(outputName="")
QTest.qWait(50)
queued.setProperty("outputName", "Virtual-0")
queued.deleteLater()
QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
QTest.qWait(300)
expect(not queued_log["requests"], "layout state: a request queued as the component goes is not sent")
for kwin_held in (True, False):
    if not kwin_held:
        bus.unregisterService("org.kde.KWin")
    gone, gone_log = create(outputName="Virtual-0")
    until(lambda: gone_log["requests"])
    deliver(gone, frame(gone_log, 1))
    gone.deleteLater()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
    QTest.qWait(300)
    if not kwin_held:
        check(bus.registerService("org.kde.KWin"), "layout state: KWin's name is held here again")
qInstallMessageHandler(None)
expect(not [w for w in warnings if "Error" in w],
       "layout state: what comes after the component is gone - an answer, a failed lookup, a queued request -"
       " touches nothing of it (%s)" % warnings)
events.clear()

deliver(state, frame(log, 3))
expect(until(lambda: prop(state, "revision") == 3) and prop(state, "mode") == "floating"
       and prop(state, "outcome") == "answered" and prop(state, "capable") and not prop(state, "tiled")
       and prop(state, "epoch") == E1 and prop(state, "view") == VIEW,
       "layout state: a verified answer gives the bar's view, floating")
deliver(state, frame(log, 4, tiled=True))
expect(until(lambda: prop(state, "revision") == 4) and prop(state, "mode") == "tiled",
       "layout state: a frame pushed at a newer revision, with no request of its own, is taken")
mark = len(log["history"])
deliver(state, frame(log, 5, tiled=True))
deliver(state, frame(log, 7, tiled=True))
deliver(state, frame(log, 6, tiled=True))
expect(until(lambda: prop(state, "revision") == 7) and not [h for h in log["history"][mark:] if h[0] == 6],
       "layout state: of frames that come while one is checked, only the newest waits")

barrier = [100]


def rejected(why, value, bad):
    """Deliver what must not count, then a valid frame at the next revision; the first was never
    taken if the history since shows no entry `bad` accepts. Checks are serialized, so a frame
    taken would show before the valid one. No check is out when the first arrives - the last
    barrier's wait ends only once its accept() and verified() have run, in one callback - so the
    valid frame cannot push it out of the waiting slot unchecked."""
    mark = len(log["history"])
    deliver(state, value)
    barrier[0] += 2
    deliver(state, frame(log, barrier[0], tiled=True))
    taken = until(lambda: prop(state, "revision") == barrier[0])
    expect(taken and not [h for h in log["history"][mark:] if bad(h)], "layout state: rejects " + why)


rejected("an older revision", frame(log, 3), lambda h: h[0] == 3)
rejected("the same revision again", frame(log, prop(state, "revision"), tiled=False), lambda h: h[1] == "floating")
malformed = [
    ("another version", dict(version=2)), ("no version", dict(version=MISSING)),
    ("another consumer", dict(consumer="another-bar")), ("another request", dict(request=2)),
    ("an epoch not in lower-case hex", dict(epoch=E1.upper(), identityName=PREFIX + E1.upper())),
    ("an epoch of 31 digits", dict(epoch=E1[:31], identityName=PREFIX + E1[:31])),
    ("an identity name not the epoch's", dict(identityName=PREFIX + E2)),
    ("a backend owner that is no unique name", dict(backendOwner="org.kde.KWin")),
    ("a status neither online nor offline", dict(status="busy")),
    ("capable that is no boolean", dict(capable="true")), ("tiled that is no boolean", dict(tiled="yes")),
    ("tiled while not capable", dict(capable=False, tiled=True)),
    ("tiled with no view", dict(view=None, tiled=True)),
    ("a view of another output", dict(view=dict(VIEW, outputName="Virtual-1"))),
    ("a view with no desktop", dict(view=dict(VIEW, desktopId=""))),
    ("a view with an overlong desktop", dict(view=dict(VIEW, desktopId="d" * 129))),
    ("a view with an overlong activity", dict(view=dict(VIEW, activityId="a" * 129))),
    ("a view that is a list", dict(view=[VIEW])), ("a view that is text", dict(view="Virtual-0")),
    ("no view", dict(view=MISSING)), ("no capable", dict(capable=MISSING)), ("no tiled", dict(tiled=MISSING)),
    ("an empty refusal", dict(refused="")), ("an overlong refusal", dict(refused="r" * 65)),
]
for why, fields in malformed:
    marker = barrier[0] + 1
    value = frame(log, marker, tiled=True)
    value.update(fields)
    value = {key: item for key, item in value.items() if item is not MISSING}
    rejected(why, value, lambda h, marker=marker: h[0] == marker)
for why, fields in [("offline that says capable", dict(capable=True)),
                    ("offline with a view", dict(view=VIEW)), ("offline that says tiled", dict(tiled=True)),
                    ("offline with a refusal", dict(refused="output"))]:
    marker = barrier[0] + 1
    value = frame(log, marker, status="offline")
    value.update(fields)
    rejected(why, value, lambda h, marker=marker: h[0] == marker or h[2] == "pending")
for why, revision in [("revision 0", 0), ("a revision past the bound", 2147483647),
                      ("a revision with a fraction", 100000.5), ("a revision as text", "100001")]:
    rejected(why, frame(log, revision, tiled=True), lambda h: h[0] in (0, 2147483647, 100000, 100001))
for why, text in [("text that is no JSON", "{"), ("a JSON list", "[]"), ("JSON null", "null"),
                  ("a JSON number", "7"), ("an answer over 4096 characters",
                                         json.dumps(dict(frame(log, 99999, tiled=True), pad="p" * 4096)))]:
    rejected(why, text, lambda h: h[0] == 99999)
for why, fields in [("KWin's name not on the backend owner's connection",
                     dict(epoch=E4, identityName=PREFIX + E4, backendOwner=stranger)),
                    ("an identity name no connection holds", dict(epoch=E3, identityName=PREFIX + E3)),
                    ("an identity name another connection holds", dict(epoch=E4, identityName=PREFIX + E4))]:
    marker = barrier[0] + 1
    value = frame(log, marker, tiled=True)
    value.update(fields)
    rejected(why, value, lambda h, marker=marker: h[0] == marker)

# KWin's name changing hands. Released by the connection the bar's lifetime answered from, it makes
# the bar unknown and ask again (more of that below, the provider lost). Unowned, a frame that names
# no owner - an empty owner, and an identity nobody holds - is no answer: a failed lookup confirms
# nothing. Then held by another connection, KWin's name makes no offline frame of the lifetime the
# bar was bound to count from that connection.
events.clear()
bus.unregisterService("org.kde.KWin")
expect(until(lambda: len(events) == 2) and [kind for kind, _ in events] == ["request", "wake"]
       and prop(state, "outcome") == "pending" and prop(state, "epoch") == "",
       "layout state: KWin's name released by the bound lifetime's connection makes the bar unknown and ask again")
asked = len(log["requests"])
mark = len(log["history"])
deliver(state, dict(frame(log, barrier[0] + 1, epoch=E3, tiled=True), backendOwner=""))
until(lambda: len(log["history"]) > mark, ms=500)
check(second.registerService("org.kde.KWin"), "layout state: KWin's name is held by the second connection")
deliver(state, frame(log, barrier[0] + 2, status="offline", backend=stranger))
until(lambda: len(log["history"]) > mark, ms=500)
second.unregisterService("org.kde.KWin")
check(bus.registerService("org.kde.KWin"), "layout state: KWin's name is held here again")
barrier[0] += 3
deliver(state, frame(log, barrier[0], tiled=True))
expect(until(lambda: prop(state, "revision") == barrier[0]) and len(events) == 2 and len(log["requests"]) == asked
       and not [h for h in log["history"][mark:] if h[0] == barrier[0] - 2 or h[3] == E3],
       "layout state: with KWin's name unowned, a frame naming no owner is no answer, nor, with KWin's name on"
       " another connection, an offline frame of the lifetime the bar was bound to")

barrier[0] += 1
deliver(state, frame(log, barrier[0], view=None))
expect(until(lambda: prop(state, "revision") == barrier[0]) and prop(state, "mode") == "unavailable"
       and prop(state, "view") is None, "layout state: an output KWin does not have is unavailable")
barrier[0] += 1
deliver(state, frame(log, barrier[0], capable=False))
expect(until(lambda: prop(state, "revision") == barrier[0]) and prop(state, "mode") == "unavailable",
       "layout state: a provider that cannot tile is unavailable")
barrier[0] += 1
deliver(state, frame(log, barrier[0], view=dict(VIEW, activityId="")))
expect(until(lambda: prop(state, "revision") == barrier[0]) and prop(state, "mode") == "floating",
       "layout state: a view with no activity is the bar's view")

# A new output is a new request: unknown at once, its answer may come at an unchanged revision,
# and the old request's frames no longer count. The bar has asked twice so far: at its start, and
# when KWin's name left its lifetime's connection.
last = barrier[0]
events.clear()
mark = len(log["history"])
deliver(state, frame(log, last + 3, tiled=True))
state.setProperty("outputName", "Virtual-1")
expect(prop(state, "mode") == "unknown" and prop(state, "outcome") == "pending" and prop(state, "revision") == 0
       and prop(state, "view") is None and not prop(state, "capable") and not prop(state, "tiled"),
       "layout state: another output is unknown at once")
until(lambda: len(events) == 2)
expect(len(log["requests"]) == 3 and log["requests"][-1]["request"] == 3
       and log["requests"][-1]["outputName"] == "Virtual-1" and [kind for kind, _ in events] == ["request", "wake"],
       "layout state: another output asks again, and wakes the provider")
old = dict(frame(log, last + 1), request=2, view=VIEW)
mark = len(log["history"])
deliver(state, old)
deliver(state, frame(log, last))
expect(until(lambda: prop(state, "revision") == last) and prop(state, "mode") == "floating"
       and not [h for h in log["history"][mark:] if h[0] in (last + 1, last + 3)],
       "layout state: the old request's frames, one checked as it moved on among them, no longer count,"
       " and the new one's answer may keep the revision")

events.clear()
state.setProperty("outputName", "Virtual-2")
until(lambda: len(events) == 2)
deliver(state, frame(log, last + 30, refused="output"))
expect(until(lambda: prop(state, "outcome") == "refused") and prop(state, "refusal") == "output"
       and prop(state, "mode") == "unknown" and not prop(state, "capable") and prop(state, "view") is None
       and prop(state, "epoch") == E1, "layout state: a refused request is an outcome, and gives no state")

# Another provider lifetime answering is no continuation: the bar asks that lifetime afresh, and
# its answer counts whatever its revision. An offline frame from the lifetime the bar is bound to
# makes it unknown and ask again; one from any other lifetime does not count.
events.clear()
state.setProperty("outputName", "Virtual-0")
until(lambda: len(events) == 2)
deliver(state, frame(log, last + 35))
until(lambda: prop(state, "revision") == last + 35)
events.clear()
deliver(state, frame(log, last + 36, epoch=E2))
expect(until(lambda: len(events) == 2) and log["requests"][-1]["request"] == 6
       and prop(state, "mode") == "unknown" and prop(state, "outcome") == "pending" and prop(state, "epoch") == "",
       "layout state: another lifetime's answer makes the bar unknown and ask again")
# The same output asked again: only the request number tells the old request's frames apart, and
# one of them, newer, must not take the place of the current request's answer while that waits.
mark = len(log["history"])
deliver(state, frame(log, 1, epoch=E2))
deliver(state, dict(frame(log, 20, epoch=E2), request=5))
deliver(state, frame(log, 2, epoch=E2))
expect(until(lambda: prop(state, "revision") == 2) and prop(state, "epoch") == E2 and prop(state, "mode") == "floating"
       and not [h for h in log["history"][mark:] if h[0] == 20],
       "layout state: the new lifetime's answer counts from its own first revision, and the request it replaced"
       " no longer counts, nor takes the place of that answer")
events.clear()
mark = len(log["history"])
deliver(state, frame(log, 3, epoch=E1, status="offline"))
deliver(state, frame(log, 4, epoch=E2))
expect(until(lambda: prop(state, "revision") == 4) and not events and prop(state, "epoch") == E2
       and not [h for h in log["history"][mark:] if h[2] == "pending"],
       "layout state: while the bar is bound, another lifetime's offline frame does not count")
events.clear()
deliver(state, frame(log, 5, epoch=E2, status="offline"))
expect(until(lambda: len(events) == 2) and log["requests"][-1]["request"] == 7 and prop(state, "mode") == "unknown"
       and prop(state, "epoch") == "", "layout state: the bound lifetime's offline frame makes the bar unknown and ask again")
events.clear()
mark = len(log["history"])
deliver(state, frame(log, 3, epoch=E1, status="offline"))
deliver(state, frame(log, 4, epoch=E1))
expect(until(lambda: prop(state, "revision") == 4) and not events and log["requests"][-1]["request"] == 7
       and not [h for h in log["history"][mark:] if h[0] == 3],
       "layout state: an offline frame from a lifetime the bar is not bound to does not count")
# Going idle retires the request: neither an answer to it being checked as the bar goes idle, nor
# a late one, counts.
events.clear()
mark = len(log["history"])
current = prop(state, "revision")
deliver(state, frame(log, current + 1, view=None))
state.setProperty("outputName", "")
deliver(state, frame(log, current + 2, refused="output"))
expect(not until(lambda: prop(state, "outcome") != "idle", ms=500) and not events
       and not [h for h in log["history"][mark:] if h[0] in (current + 1, current + 2)],
       "layout state: going idle retires the request: neither an answer being checked nor a late one counts")
events.clear()
state.setProperty("outputName", "o" * 129)
QTest.qWait(50)
expect(prop(state, "outcome") == "idle" and prop(state, "mode") == "unknown" and not events,
       "layout state: an output name longer than a request may carry asks nothing")

# The provider lost with no frame. The bar watches the bus's NameOwnerChanged, with no polling: the
# lifetime it is bound to is gone once that lifetime's connection releases its identity name or
# KWin's name, or hands KWin's name straight to another connection - one signal naming both owners,
# which a watch of whether a name is held would miss. The bar is then unknown and asks again. A name
# taken, an unrelated name or another lifetime's changing hands, or a loss while the bar is bound to
# nothing, changes nothing; nor does a name changing hands after the component is gone.
E5, E6, E7, E8, E9 = (hashlib.md5(name.encode()).hexdigest() for name in ("five", "six", "seven", "eight", "nine"))
QUEUE, REPLACE = QDBusConnectionInterface.ServiceQueueOptions, QDBusConnectionInterface.ServiceReplacementOptions
REGISTERED = QDBusConnectionInterface.RegisterServiceReply.ServiceRegistered.value
changes = []


class Changes(QObject):
    """Records each NameOwnerChanged the bus sends for KWin's name."""

    @Slot(str, str, str)
    def changed(self, name, previous, current):
        if name == "org.kde.KWin":
            changes.append((previous, current))


recorder = Changes()
check(bus.connect("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                  recorder, SLOT("changed(QString,QString,QString)"))
      and all(bus.registerService(PREFIX + epoch) for epoch in (E5, E6, E7, E8)),
      "layout state: KWin's name changes are recorded, and four more identity names are held here")
events.clear()
watched, watched_log = create(outputName="Virtual-0")
until(lambda: len(events) == 2)


def bind(epoch):
    events.clear()
    deliver(watched, frame(watched_log, 1, epoch=epoch))
    return until(lambda: prop(watched, "epoch") == epoch and prop(watched, "outcome") == "answered")


def lose(why, action):
    """Act on the bus while the bar is bound: it must become unknown and ask again, once. The waits
    run whatever came before, so that a failing run leaves the bus settled for the next step."""
    events.clear()
    was_bound = prop(watched, "outcome") == "answered"
    action()
    asked = until(lambda: len(events) == 2)
    quiet = not until(lambda: len(events) > 2, ms=300)
    expect(was_bound and asked and quiet and [kind for kind, _ in events] == ["request", "wake"]
           and prop(watched, "outcome") == "pending" and prop(watched, "mode") == "unknown"
           and prop(watched, "epoch") == "" and prop(watched, "revision") == 0,
           "layout state: " + why + " makes the bar unknown and ask again")


def unchanged(why, epoch, action):
    """Act on the bus while the bar is bound to `epoch` (pending when empty): nothing may change.
    The wait runs whatever came before, as in lose()."""
    events.clear()
    outcome = "answered" if epoch else "pending"
    was = prop(watched, "outcome") == outcome and prop(watched, "epoch") == epoch
    action()
    quiet = not until(lambda: events or prop(watched, "outcome") != outcome, ms=500)
    if not quiet:
        QTest.qWait(500)
    expect(was and quiet and prop(watched, "epoch") == epoch, "layout state: " + why + " changes nothing")


def hand_over():
    del changes[:]
    reply = second.interface().registerService("org.kde.KWin", QUEUE.ReplaceExistingService,
                                               REPLACE.DontAllowReplacement)
    check(reply.value() == REGISTERED and until(lambda: changes) and changes == [(owner, stranger)],
          "layout state: the second connection took KWin's name straight from this one, in one change (%s)"
          % changes)


expect(bind(E5), "layout state: the watched bar is bound")
unchanged("while the bar is bound, a name taken, and an unrelated name or another lifetime's released,", E5,
          lambda: check(bus.registerService("org.plasmafusion.LayoutTest.one")
                        and second.registerService("org.plasmafusion.LayoutTest.two")
                        and bus.unregisterService("org.plasmafusion.LayoutTest.one")
                        and second.unregisterService("org.plasmafusion.LayoutTest.two")
                        and bus.unregisterService(PREFIX + E6) and second.unregisterService(PREFIX + E4),
                        "layout state: unrelated names come and go, and two other lifetimes' identity names go"))
lose("the bound lifetime's identity name released", lambda: bus.unregisterService(PREFIX + E5))
expect(bind(E7), "layout state: the watched bar is bound again")
lose("KWin's name released by the bound lifetime's connection", lambda: bus.unregisterService("org.kde.KWin"))
unchanged("while the bar is bound to nothing, KWin's name taken", "",
          lambda: check(bus.interface().registerService("org.kde.KWin", QUEUE.DontQueueService,
                                                        REPLACE.AllowReplacement).value() == REGISTERED,
                        "layout state: KWin's name is held here again, to be handed on"))
expect(bind(E7), "layout state: the watched bar is bound again")
lose("KWin's name handed straight to another connection", hand_over)
unchanged("while the bar is bound to nothing, KWin's name released and taken again", "",
          lambda: check(second.unregisterService("org.kde.KWin") and bus.registerService("org.kde.KWin"),
                        "layout state: KWin's name is released by the second connection and held here again"))

# A check looks up KWin's owner first and the identity's last, so KWin's name moving from the owner
# of the frame being checked makes the bar ask again too: between the two lookups it would let the
# check take a lifetime KWin no longer has. Handed on in the same turn as the frame arrives, KWin's
# name moves either before the check's first lookup or between its two - the test cannot tell
# which - and in both the bar must ask again, unbound. A move from another owner, or one after the
# check is over, changes nothing.
del changes[:]
check(bus.unregisterService("org.kde.KWin")
      and bus.interface().registerService("org.kde.KWin", QUEUE.DontQueueService,
                                          REPLACE.AllowReplacement).value() == REGISTERED
      and second.registerService(PREFIX + E9), "layout state: KWin's name is held here, to be handed on,"
      " and another identity name on the second connection")
# Those two changes arrive first, so that the handover is the only one recorded below. The bus sends
# changes in order, so once these two are the last recorded, nothing older is still on its way.
check(until(lambda: changes[-2:] == [(owner, ""), ("", owner)]),
      "layout state: KWin's name released and held here again, recorded (%s)" % changes)
events.clear()
mark = len(watched_log["history"])
deliver(watched, frame(watched_log, 1, epoch=E7))
hand_over()
asked_again = until(lambda: len(events) == 2)
quiet = not until(lambda: len(events) > 2, ms=300)
expect(asked_again and quiet and [kind for kind, _ in events] == ["request", "wake"] and prop(watched, "outcome") == "pending"
       and prop(watched, "epoch") == "" and not [h for h in watched_log["history"][mark:] if h[2] == "answered"],
       "layout state: KWin's name handed on from the owner of the frame being checked makes the bar ask again,"
       " and the check takes nothing")
del changes[:]
check(second.unregisterService("org.kde.KWin") and bus.registerService("org.kde.KWin"),
      "layout state: KWin's name is held here again")
# Those changes arrive before the next frame is checked: the first comes from the second connection,
# which that frame names as its owner, and would otherwise reach the bar during its check.
check(until(lambda: changes[-2:] == [(stranger, ""), ("", owner)]),
      "layout state: KWin's name released by the second connection and held here again, recorded (%s)" % changes)


def mid_check(why, epoch, backend, action):
    """Deliver a frame for the current request and act in the same turn, while it is checked. The
    wait settles the bus whatever the outcome, as in unchanged()."""
    events.clear()
    deliver(watched, frame(watched_log, 1, epoch=epoch, backend=backend))
    action()
    quiet = not until(lambda: events or prop(watched, "outcome") != "pending", ms=500)
    if not quiet:
        QTest.qWait(500)
    expect(quiet and prop(watched, "epoch") == "", "layout state: " + why + " changes nothing")


mid_check("KWin's name released, during the check, by another connection than the frame's owner", E9, stranger,
          lambda: bus.unregisterService("org.kde.KWin"))
check(bus.registerService("org.kde.KWin"), "layout state: KWin's name is held here again")
unchanged("once its check is over, KWin's name moving from that frame's owner", "",
          lambda: check(bus.unregisterService("org.kde.KWin") and second.registerService("org.kde.KWin")
                        and second.unregisterService("org.kde.KWin") and bus.registerService("org.kde.KWin"),
                        "layout state: KWin's name goes to the second connection and back"))
warnings = []
qInstallMessageHandler(lambda mode, context, message: warnings.append(message))
left, left_log = create(outputName="Virtual-0")
until(lambda: left_log["requests"])
deliver(left, frame(left_log, 1, epoch=E8))
left_bound = until(lambda: prop(left, "epoch") == E8)
left.deleteLater()
QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
bus.unregisterService(PREFIX + E8)
QTest.qWait(300)
qInstallMessageHandler(None)
expect(left_bound and len(left_log["requests"]) == 1 and not [w for w in warnings if "Error" in w],
       "layout state: the bound lifetime's name released after the component is gone touches nothing of it (%s)"
       % warnings)

# An answer that never comes. Each request has its own deadline (P0's receipt, item 9): past it with
# no answer the outcome is unconfirmed and the mode unknown, as under a Kiosk policy that refuses the
# shell's scripting or with no provider at all, and the request stays out - a late answer still
# counts - with nothing asked again. A new request starts its own deadline, an answer or going idle
# ends the wait, a check that fails leaves the request to it, and a request keeps the deadline it was
# made with. Each wait is timed from just before the step that asks to the outcome's own signal,
# with 150 ms of slack for the timer's resolution, as a loaded machine only makes a timer later.
DEADLINE = 1000
asked_at, outcomes = [], []
created_at = time.monotonic()
waiting, waiting_log = create(outputName="Virtual-0", deadlineMs=DEADLINE)
waiting.requested.connect(lambda text: asked_at.append(time.monotonic()))
waiting.outcomeChanged.connect(lambda: outcomes.append((prop(waiting, "outcome"), time.monotonic())))


def timer_of(item):
    """The component's deadline timer, read from outside to check the interval it was given."""
    found = [child for child in item.findChildren(QObject) if child.inherits("QQmlTimer")]
    return found[0] if len(found) == 1 else None


def ask_waiting(output):
    """Ask again through an output change; the time just before it, once the request is out."""
    start, count = time.monotonic(), len(asked_at)
    waiting.setProperty("outputName", output)
    return start if until(lambda: len(asked_at) == count + 1) else None


def unconfirmed_after(start, deadline=DEADLINE):
    """Whether the outcome turned unconfirmed, and no sooner than a deadline after `start`."""
    if start is None or not until(lambda: prop(waiting, "outcome") == "unconfirmed", ms=deadline * 5):
        return False
    when = [moment for outcome, moment in outcomes if outcome == "unconfirmed"][-1]
    return when - start >= (deadline - 150) / 1000


events.clear()
first = created_at if until(lambda: len(asked_at) == 1) else None
timer = timer_of(waiting)
expect(timer is not None and timer.property("interval") == DEADLINE and unconfirmed_after(first)
       and prop(waiting, "mode") == "unknown" and prop(waiting, "epoch") == ""
       and not until(lambda: len(waiting_log["requests"]) > 1, ms=300)
       and [kind for kind, _ in events] == ["request", "wake"],
       "layout state: a request with no answer is unconfirmed at its deadline, its mode unknown, and nothing is"
       " asked again")
deliver(waiting, frame(waiting_log, 1))
expect(until(lambda: prop(waiting, "outcome") == "answered") and prop(waiting, "mode") == "floating",
       "layout state: a late answer to the unconfirmed request still counts")
timely = len(outcomes)
ask_waiting("Virtual-1")
deliver(waiting, frame(waiting_log, 1))
# Answered before its deadline and never unconfirmed first: an answer taken after the deadline would
# pass the wait below as well, and the late-answer case above is that one.
expect(until(lambda: prop(waiting, "outcome") == "answered")
       and not until(lambda: prop(waiting, "outcome") != "answered", ms=DEADLINE + 300)
       and [outcome for outcome, _ in outcomes[timely:]] == ["pending", "answered"],
       "layout state: an answer before the deadline keeps the bar answered past it (%s)"
       % [outcome for outcome, _ in outcomes[timely:]])
ask_waiting("Virtual-2")
QTest.qWait(DEADLINE // 2)
replacing = ask_waiting("Virtual-0")
expect(prop(waiting, "outcome") == "pending" and unconfirmed_after(replacing),
       "layout state: a new request starts its own deadline, and the one it replaced ends no sooner")
failing = ask_waiting("Virtual-1")
deliver(waiting, frame(waiting_log, 1, epoch=E3))
expect(unconfirmed_after(failing) and prop(waiting, "epoch") == "" and len(asked_at) == 5,
       "layout state: a check that fails - an identity name nobody holds - leaves the request to its deadline,"
       " and nothing is asked again")
changed = ask_waiting("Virtual-0")
QTest.qWait(DEADLINE // 3)
waiting.setProperty("deadlineMs", 5000)
# Within unconfirmed_after()'s wait of five deadlines, so a wait restarted at 5 s would not end in it.
expect(unconfirmed_after(changed),
       "layout state: a request keeps the deadline it was made with when the owner changes it")
ask_waiting("Virtual-2")
expect(timer is not None and timer.property("interval") == 5000,
       "layout state: the owner's new deadline applies from the next request")
waiting.setProperty("deadlineMs", DEADLINE)
ask_waiting("Virtual-1")
waiting.setProperty("outputName", "")
expect(prop(waiting, "outcome") == "idle"
       and not until(lambda: prop(waiting, "outcome") != "idle" or len(asked_at) > 8, ms=DEADLINE + 300),
       "layout state: going idle ends the wait: the bar stays idle past the deadline")
warnings = []
qInstallMessageHandler(lambda mode, context, message: warnings.append(message))
check(bus.unregisterService("org.kde.kglobalaccel"), "layout state: kglobalaccel's stand-in leaves the bus")
failed_wake = unconfirmed_after(ask_waiting("Virtual-0"))
check(bus.registerService("org.kde.kglobalaccel"), "layout state: kglobalaccel's stand-in is on the bus again")
qInstallMessageHandler(None)
expect(failed_wake and len(asked_at) == 9
       and [w for w in warnings if "the wake failed" in w and "ServiceUnknown" in w],
       "layout state: a wake that fails is said, the request still ends unconfirmed at its deadline, and"
       " nothing is asked again (%s)" % warnings)
intervals = []
for value in (50, 99, 100, 10001, 20000):
    strict, strict_log = create(outputName="Virtual-0", deadlineMs=value)
    until(lambda: strict_log["requests"])
    strict_timer = timer_of(strict)
    intervals.append(strict_timer.property("interval") if strict_timer is not None else None)
    strict.deleteLater()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
expect(intervals == [10000, 10000, 100, 10000, 10000],
       "layout state: 100 ms is a deadline, and one outside 100 to 10000 ms gives the 10 s one (%s)" % intervals)
warnings = []
qInstallMessageHandler(lambda mode, context, message: warnings.append(message))
going, going_log = create(outputName="Virtual-0", deadlineMs=DEADLINE // 2)
gone = []
going.destroyed.connect(lambda: gone.append(True))
until(lambda: going_log["requests"])
going.deleteLater()
QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
QTest.qWait(DEADLINE)
qInstallMessageHandler(None)
expect(gone and not [w for w in warnings if "Error" in w],
       "layout state: a deadline that would end after the component is gone touches nothing of it (%s)" % warnings)
waiting.deleteLater()
watched.deleteLater()
state.deleteLater()
QTest.qWait(50)

# The bar's layout action (P6; docs/parts/shell-topbar.md, "The layout action", whose table names
# the rows T1 to T36 that the messages cite): the menu's choices as the layout state's open(),
# input(), choose() and close(), sent to the provider as a prepare and a set. Each case has a bar
# of its own, answered by one provider lifetime and floating unless it says otherwise, and records
# each outcome the bar presents (actionOutcome) with what its handler sees then. The frames carry
# what the provider adds to an intent's (kwin.md, "The layout provider's state"): a prepare's
# completion and preparation, and a set's completion once it has one.
E10 = hashlib.md5(b"ten").hexdigest()
HANDLE = E1 + ":1:1"
ELSEWHERE = dict(VIEW, desktopId="desktop-2")
DONE = {"completion": {"intent": "set", "result": "done"}}
action_messages = []
qInstallMessageHandler(lambda mode, context, message: action_messages.append(message))


def invoke(item, name, *args, returns=None):
    """One of the component's functions, called directly as main.qml calls it; None when the
    component has no such function, so that each case fails on its own."""
    try:
        if returns is None:
            return QMetaObject.invokeMethod(item, name, Qt.DirectConnection, *args) or None
        return QMetaObject.invokeMethod(item, name, Qt.DirectConnection, Q_RETURN_ARG(returns), *args)
    except RuntimeError:
        return None


def ready(handle=HANDLE, target=True, why="no-target"):
    """A done prepare's fields, its preparation ready."""
    completion = {"intent": "prepare", "result": "done", "handle": handle, "target": target}
    if not target:
        completion["reason"] = why
    return {"completion": completion, "prepared": {"handle": handle, "ready": True}}


def ended(why, handle=HANDLE):
    """A done prepare's fields once its preparation has ended for `why`."""
    return {"completion": {"intent": "prepare", "result": "done", "handle": handle, "target": True},
            "prepared": {"handle": handle, "ready": False, "reason": why}}


def refusal(intent, why):
    return {"completion": {"intent": intent, "result": "refused", "reason": why}}


# A deadline with room for what a case does before it: the steps and the reads of the state that
# must come first, which a short deadline could overtake on a loaded machine. A case that only
# waits for a deadline to pass keeps a short one.
ROOMY_DEADLINE = 1000


class Bar:
    """A layout state answered by one lifetime, and the outcomes it presents: each reason and
    mode, with the action's state, reason and pending flag as the handler sees them."""

    def __init__(self, deadline=10000, epoch=E1, revision=1, **fields):
        self.item, self.log = create(outputName="Virtual-0", deadlineMs=deadline)
        self.epoch = epoch
        self.said = []
        outcome = getattr(self.item, "actionOutcome", None)
        if outcome is not None:
            outcome.connect(lambda reason, mode: self.said.append(
                (reason, mode, self.get("actionState"), self.get("actionReason"), self.get("actionPending"))))
        until(lambda: self.log["requests"])
        self.deliver(self.frame(revision, **fields))
        until(lambda: self.get("outcome") == "answered")

    def get(self, name):
        return prop(self.item, name)

    def state(self):
        return self.get("actionState")

    def presented(self):
        return [entry[:3] for entry in self.said]

    def open(self):
        return invoke(self.item, "open", returns=bool)

    def input(self):
        invoke(self.item, "input")

    def choose(self, mode):
        invoke(self.item, "choose", Q_ARG(str, mode))

    def close(self, dismissed):
        invoke(self.item, "close", Q_ARG(bool, dismissed))

    def count(self):
        return len(self.log["requests"])

    def last(self):
        return self.log["requests"][-1] if self.log["requests"] else {}

    def sent(self, count):
        """Whether one request more than `count` went out: it is saved a turn after it is made."""
        return until(lambda: self.count() > count) and self.count() == count + 1

    def quiet(self, count, ms=100):
        """Whether no request beyond `count` goes out."""
        return not until(lambda: self.count() > count, ms=ms)

    def frame(self, revision, **fields):
        """A frame of the bar's last request, from its lifetime unless `fields` name another."""
        fields.setdefault("epoch", self.epoch)
        return frame(self.log, revision, **fields)

    def deliver(self, value):
        deliver(self.item, value)

    def take(self, value, test, ms=2000):
        """Deliver a frame and wait for what it should do."""
        self.deliver(value)
        return until(test, ms=ms)

    def barrier(self, revision, **fields):
        """Deliver a newer frame of the last request and wait for it: what was delivered before it
        has been checked by then, as the checks run in order (see rejected() above)."""
        return self.take(self.frame(revision, **fields), lambda: self.get("revision") == revision)

    def to_open(self):
        return self.open() is True and self.state() == "open"

    def to_preparing(self, choice=None):
        count = self.count()
        if not self.to_open():
            return False
        if choice is None:
            self.input()
        else:
            self.choose(choice)
        return self.state() == "preparing" and self.sent(count)

    def to_prepared(self, choice=None, tiled=False, **completion):
        return self.to_preparing(choice) and self.take(self.frame(1, tiled=tiled, **ready(**completion)),
                                                       lambda: self.state() == "prepared")

    def to_setting(self, mode="floating", deadline=None, **options):
        if not self.to_prepared(**options):
            return False
        if deadline is not None:
            self.item.setProperty("deadlineMs", deadline)
        count = self.count()
        self.choose(mode)
        return self.state() == "setting" and self.sent(count)

    def to_awaiting(self, dismissed, **options):
        if not self.to_setting(**options):
            return False
        self.close(dismissed)
        return self.state() == "awaiting"

    def done(self):
        self.item.deleteLater()
        QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)


# What a bar presents and says while it runs: the shell's log gets one line when a provider
# lifetime is left without actions, naming the side that failed, and nothing else.
def lifetime_line(failure, epoch=E1):
    return ("plasmafusion-clockpill: layout state: the provider %s; the layout actions are off for its lifetime %s"
            % (failure, epoch))


def refused_line(kind, why):
    return lifetime_line("refused the bar's %s at frame level with %s" % (kind, why))


def lacked_line(kind):
    return lifetime_line("sent a frame for the bar's %s that lacked the intent's fields" % kind)


expected_lines = []


def logged(mark, lines):
    """Whether exactly `lines` were logged since `mark`; they are expected in the final check too."""
    expected_lines.extend(lines)
    return action_messages[mark:] == lines


# Each property of the action changes at most once in one input, frame or deadline: a binding to
# it never sees a value the event does not leave. Counted from reset() on, with the mode and the
# outcome, which the action's events change too.
WATCHED = ("actionsAvailable", "actionOpen", "actionState", "actionChoice", "actionPending", "actionHandle",
           "actionTarget", "tiledBlocked", "actionReason", "mode", "outcome")


class ChangeCounts:
    def __init__(self, bar):
        self.counts, self.missing = {}, []
        for name in WATCHED:
            signal = getattr(bar.item, name + "Changed", None)
            if signal is None:
                self.missing.append(name)
                continue
            self.counts[name] = 0
            signal.connect(lambda name=name: self.counts.__setitem__(name, self.counts[name] + 1))

    def reset(self):
        for name in self.counts:
            self.counts[name] = 0

    def once(self, **exactly):
        """No property changed twice or more, and those named as many times as given."""
        return (not self.missing and all(count <= 1 for count in self.counts.values())
                and all(self.counts.get(name) == count for name, count in exactly.items()))


def wire(bar):
    """main.qml's two closes as its wiring will make them, from inside the layout state's own
    change: the menu's hide as the action stops being open, and the control's as the mode stops
    showing tiled or floating. Each says that it ran."""
    calls = []

    def menu_hidden():
        if bar.get("actionOpen") is False:
            calls.append("menu")
            bar.close(False)

    def control_hidden():
        if bar.get("mode") not in ("tiled", "floating"):
            calls.append("control")
            bar.close(False)

    for name, handler in (("actionOpenChanged", menu_hidden), ("modeChanged", control_hidden)):
        signal = getattr(bar.item, name, None)
        if signal is not None:
            signal.connect(handler)
    return calls


# T1, T2: open() opens only an idle action with something to act on, and sends nothing.
bar = Bar()
count = bar.count()
expect(bar.open() is True and bar.state() == "open" and bar.get("actionOpen") is True and bar.get("actionsAvailable") is True
       and bar.quiet(count) and not bar.said,
       "layout action: T1 open() in idle, with actions available, opens the action and sends nothing")
bar.done()
for name, reach in (("open", Bar.to_open), ("preparing", Bar.to_preparing), ("prepared", Bar.to_prepared),
                    ("setting", Bar.to_setting)):
    bar = Bar()
    reached = reach(bar)
    count = bar.count()
    expect(reached and bar.open() is False and bar.state() == name and bar.quiet(count),
           "layout action: T2 open() in %s is refused and changes nothing" % name)
    bar.done()
bar = Bar()
reached = bar.to_awaiting(True)
count = bar.count()
expect(reached and bar.open() is False and bar.state() == "awaiting" and bar.get("actionPending") is True
       and bar.get("actionOpen") is False and bar.quiet(count),
       "layout action: T2 open() while a set is awaited is refused: the control's activation is ignored")
bar.done()
unknown, unknown_log = create(outputName="Virtual-0")
until(lambda: unknown_log["requests"])
expect(prop(unknown, "mode") == "unknown" and prop(unknown, "actionsAvailable") is False
       and invoke(unknown, "open", returns=bool) is False and prop(unknown, "actionState") == "idle",
       "layout action: T2 open() with the mode unknown is refused")
unknown.deleteLater()
bar = Bar(capable=False)
expect(bar.get("mode") == "unavailable" and bar.get("actionsAvailable") is False and bar.open() is False
       and bar.state() == "idle", "layout action: T2 open() with the mode unavailable is refused")
bar.done()

# T3, T4, T6: the first input prepares; a choice made in open queues and prepares, one made while
# the prepare is out queues; neither sends a set.
bar = Bar()
count = bar.count()
reached = bar.to_open()
bar.input()
expect(reached and bar.state() == "preparing" and bar.sent(count) and bar.last().get("intent") == "prepare"
       and bar.get("actionPending") is False and bar.get("actionChoice") == "" and not bar.said,
       "layout action: T3 an input in open sends a prepare (%s)" % bar.last())
bar.done()
bar = Bar()
count = bar.count()
reached = bar.to_open()
bar.choose("tiled")
expect(reached and bar.state() == "preparing" and bar.sent(count) and bar.last().get("intent") == "prepare"
       and bar.get("actionChoice") == "tiled" and bar.get("actionPending") is True and not bar.said,
       "layout action: T4 a choice in open is queued and sends a prepare, not a set (%s)" % bar.last())
bar.done()
bar = Bar()
reached = bar.to_preparing()
count = bar.count()
bar.choose("floating")
expect(reached and bar.state() == "preparing" and bar.get("actionChoice") == "floating" and bar.get("actionPending") is True
       and bar.quiet(count) and not bar.said,
       "layout action: T6 a choice while the prepare is out is queued, and nothing is sent")
bar.done()

# The requests carry exactly the keys the provider's reader copies, numbered on from the query,
# each saved before its wake.
bar = Bar()
query = bar.last()
events.clear()
reached = bar.to_preparing()
prepare = bar.last()
woke = until(lambda: len(events) >= 2)
prepare_events = [kind for kind, _ in events]
reached = reached and bar.take(bar.frame(1, **ready()), lambda: bar.state() == "prepared")
events.clear()
count = bar.count()
bar.choose("floating")
chosen_sent = bar.sent(count)
chosen = bar.last()
chosen_woke = until(lambda: len(events) >= 2)
chosen_events = [kind for kind, _ in events]
expect(reached and sorted(prepare) == ["consumer", "epoch", "intent", "outputName", "request", "version", "view"]
       and prepare["version"] == 1 and prepare["intent"] == "prepare" and prepare["consumer"] == query["consumer"]
       and prepare["request"] == query["request"] + 1 and prepare["outputName"] == "Virtual-0" and prepare["epoch"] == E1
       and prepare["view"] == {"desktopId": "desktop-1", "activityId": "activity-1"} and woke
       and prepare_events == ["request", "wake"],
       "layout action: a prepare names the frozen context and the next request number, saved before the wake (%s)" % prepare)
expect(reached and chosen_sent and sorted(chosen) == ["consumer", "handle", "intent", "mode", "outputName", "request", "version"]
       and chosen["version"] == 1 and chosen["intent"] == "set" and chosen["consumer"] == query["consumer"]
       and chosen["request"] == prepare["request"] + 1 and chosen["outputName"] == "Virtual-0"
       and chosen["mode"] == "floating" and chosen["handle"] == HANDLE and chosen_woke and chosen_events == ["request", "wake"],
       "layout action: a set names the mode and the prepared handle, with the next request number (%s)" % chosen)
bar.done()

# While an intent waits for its first frame the bar keeps showing the mode it was sent from; a
# done prepare moves no revision, so the first frame comes at the revision shown and is taken, and
# a frame of that request at that revision again, as one the shell did not confirm is written
# again, is not.
bar = Bar()
reached = bar.to_preparing()
expect(reached and bar.get("outcome") == "pending" and bar.get("mode") == "floating" and bar.get("epoch") == E1
       and bar.get("revision") == 1 and bar.get("capable") is True and bar.get("view") == VIEW
       and bar.get("actionsAvailable") is True,
       "layout action: the mode is kept while an intent waits for its first frame")
mark = len(bar.log["history"])
first_taken = reached and bar.take(bar.frame(1, **refusal("prepare", "busy")), lambda: bar.state() == "open")
bar.deliver("")
bar.deliver(bar.frame(1, tiled=True, **refusal("prepare", "busy")))
taken = first_taken and bar.barrier(2, **refusal("prepare", "busy"))
expect(taken and bar.get("outcome") == "answered" and len(bar.said) == 1
       and not [h for h in bar.log["history"][mark:] if h[1] == "tiled"],
       "layout action: an intent's first frame is taken at the revision shown, and only once (%s)" % bar.said)
bar.done()
# A new intent clears the frame waiting for its check, as a query does: one of the request it
# replaces, still waiting behind a check, would otherwise keep out the intent's first frame at the
# same revision, as only the newest frame of a lifetime waits. All of it happens in one turn.
bar = Bar()
reached = bar.to_open()
query = bar.last()
bar.deliver(bar.frame(2))
bar.deliver(bar.frame(3))
bar.input()
bar.deliver(dict(bar.frame(3, **ready()), request=query.get("request", 0) + 1))
expect(reached and until(lambda: bar.state() == "prepared") and bar.get("actionHandle") == HANDLE,
       "layout action: a new intent clears the frame waiting for its check, so its first frame is not kept out")
bar.done()

# T5: an open action whose view, as the provider's frames name it, is no longer the frozen one
# ends: on the frame that moved the action into open, on the newest frame when a deadline did, and
# on a frame that gives the mode only. A reason the moving frame presented is presented once.
for row, why in (("T26", "stale-context"), ("T28", "unavailable")):
    bar = Bar()
    reached = bar.to_setting()
    taken = reached and bar.take(bar.frame(1, view=ELSEWHERE, **refusal("set", why)), lambda: bar.state() == "idle")
    expect(taken and bar.presented() == [(why, "floating", "idle")],
           "layout action: T5 a frame that moves the action into open (%s) naming another view ends it, its reason"
           " presented once (%s)" % (row, bar.said))
    bar.done()
bar = Bar()
reached = bar.to_setting(deadline=ROOMY_DEADLINE)
read = reached and bar.take(bar.frame(2, view=ELSEWHERE), lambda: bar.get("revision") == 2)
expired = read and bar.state() == "setting" and until(lambda: bar.state() != "setting", ms=3000)
expect(expired and bar.state() == "idle" and bar.presented() == [("unconfirmed", "floating", "idle")],
       "layout action: T5 entering open at a set's deadline (T31) checks the newest frame's view (%s)" % bar.said)
bar.done()
bar = Bar()
reached = bar.to_open()
taken = reached and bar.take(bar.frame(2, view=ELSEWHERE), lambda: bar.state() == "idle")
expect(taken and not bar.said, "layout action: T5 a query's frame naming another view ends an open action, silently")
bar.done()
bar = Bar()
reached = bar.to_open()
taken = reached and bar.take(bar.frame(2, view=dict(VIEW, activityId="activity-2")), lambda: bar.state() == "idle")
expect(taken and not bar.said, "layout action: T5 so does a frame naming another activity")
bar.done()

# T7: a choice queued before the prepare is done is sent with its handle on the prepare's ready
# frame, if it can be sent: Floating, or Tiled with a target or on a tiled view.
for why, tiled, mode, target in (("Floating with no target", False, "floating", False),
                                 ("Tiled with a target", False, "tiled", True),
                                 ("Tiled on a tiled view with no target", True, "tiled", False)):
    bar = Bar(tiled=tiled)
    reached = bar.to_preparing(mode)
    count = bar.count()
    taken = reached and bar.take(bar.frame(1, tiled=tiled, **ready(target=target)), lambda: bar.state() == "setting")
    expect(taken and bar.sent(count) and bar.last().get("intent") == "set" and bar.last().get("mode") == mode
           and bar.last().get("handle") == HANDLE and bar.get("actionHandle") == "" and bar.get("actionChoice") == mode
           and bar.get("actionPending") is True and bar.get("tiledBlocked") is False and not bar.said,
           "layout action: T7 a queued choice, %s, is sent on the prepare's ready frame (%s)" % (why, bar.last()))
    bar.done()

# T8, T9: with no choice queued the action is prepared with the prepare's handle and target;
# Tiled is blocked, and the prepare's reason presented, only with no target on a floating view. A
# queued Tiled that is blocked is dropped.
bar = Bar()
reached = bar.to_prepared(target=True)
expect(reached and bar.get("actionHandle") == HANDLE and bar.get("actionTarget") is True and bar.get("tiledBlocked") is False
       and not bar.said, "layout action: T8 a ready prepare with a target is prepared, and presents nothing")
bar.done()
bar = Bar()
reached = bar.to_prepared(target=False)
expect(reached and bar.get("actionHandle") == HANDLE and bar.get("actionTarget") is False and bar.get("tiledBlocked") is True
       and bar.presented() == [("no-target", "", "prepared")] and bar.get("actionReason") == "no-target",
       "layout action: T8 a ready prepare with no target on a floating view blocks Tiled and presents its reason (%s)"
       % bar.said)
bar.done()
bar = Bar(tiled=True)
reached = bar.to_prepared(target=False, tiled=True)
expect(reached and bar.get("tiledBlocked") is False and not bar.said,
       "layout action: T8 on a tiled view Tiled needs no target: nothing is blocked or presented")
bar.done()
bar = Bar()
reached = bar.to_preparing("tiled")
count = bar.count()
taken = reached and bar.take(bar.frame(1, **ready(target=False, why="focus-changed")), lambda: bar.state() == "prepared")
expect(taken and bar.get("actionPending") is False and bar.get("actionChoice") == "tiled" and bar.get("tiledBlocked") is True
       and bar.presented() == [("focus-changed", "tiled", "prepared")] and bar.quiet(count),
       "layout action: T9 a queued Tiled that is blocked is dropped and no set sent; the prepare's reason is presented (%s)"
       % bar.said)
bar.done()

# T10, T11, T19, T19a: a done prepare whose preparation has ended - already in its first frame,
# or in a later one while prepared - leaves the action open for the next input, or ends it when
# the view or the shell changed. Nothing is presented, and a queued choice is dropped unsent.
for why in ("focus-changed", "target-departed"):
    bar = Bar()
    reached = bar.to_preparing("floating")
    count = bar.count()
    taken = reached and bar.take(bar.frame(1, **ended(why)), lambda: bar.state() == "open")
    expect(taken and bar.get("actionPending") is False and bar.get("actionHandle") == "" and bar.quiet(count)
           and not bar.said,
           "layout action: T10 a done prepare already not ready (%s) leaves the action open, its queued choice dropped and"
           " no set sent" % why)
    bar.done()
bar = Bar()
reached = bar.to_preparing("floating")
count = bar.count()
taken = reached and bar.take(bar.frame(1, **ended("view-changed")), lambda: bar.state() == "idle")
expect(taken and bar.get("actionOpen") is False and bar.get("actionPending") is False and bar.quiet(count) and not bar.said,
       "layout action: T11 a prepare's first frame not ready for view-changed ends the action, silently")
bar.done()
bar = Bar()
reached = bar.to_prepared()
count = bar.count()
taken = reached and bar.take(bar.frame(2, **ended("shell-replaced")), lambda: bar.state() == "idle")
expect(taken and bar.get("actionHandle") == "" and bar.quiet(count) and not bar.said,
       "layout action: T11 a prepared action's later frame not ready for shell-replaced ends the action, silently")
bar.done()
for why in ("focus-changed", "target-departed"):
    bar = Bar()
    reached = bar.to_prepared()
    count = bar.count()
    taken = reached and bar.take(bar.frame(2, **ended(why)), lambda: bar.state() == "open")
    expect(taken and bar.get("actionHandle") == "" and bar.quiet(count) and not bar.said,
           "layout action: T19 a prepared action whose preparation ended (%s) is open again, silently" % why)
    bar.done()
bar = Bar()
reached = bar.to_preparing("tiled")
count = bar.count()
taken = reached and bar.take(bar.frame(1, **ended("consumer-retired")), lambda: bar.state() == "open")
expect(taken and bar.get("actionPending") is False and bar.quiet(count) and not bar.said,
       "layout action: T19a a prepare's first frame not ready for another reason leaves the action open, its queued"
       " choice dropped")
bar.done()
bar = Bar()
reached = bar.to_prepared()
taken = reached and bar.take(bar.frame(2, **ended("consumer-retired")), lambda: bar.state() == "open")
expect(taken and bar.get("actionHandle") == "" and not bar.said,
       "layout action: T19a a prepared action's later frame not ready for another reason leaves it open, silently")
bar.done()

# T12, T12a, T13, T14: a refused prepare leaves the action open for the next input, its queued
# choice dropped, and presents the reason, except a silent popup-focus-unconfirmed; stale-context
# ends it.
for row, why, shown in (("T12", "busy", True), ("T12", "unavailable", True), ("T12", "conflicting-request", True),
                        ("T12", "stale-request", True), ("T12a", "tree-refused", True),
                        ("T13", "popup-focus-unconfirmed", False)):
    bar = Bar()
    reached = bar.to_preparing("tiled")
    count = bar.count()
    taken = reached and bar.take(bar.frame(1, **refusal("prepare", why)), lambda: bar.state() == "open")
    expect(taken and bar.get("actionPending") is False and bar.quiet(count)
           and bar.said == ([(why, "tiled", "open", why, False)] if shown else []),
           "layout action: %s a prepare refused %s leaves the action open, its queued choice dropped, %s (%s)"
           % (row, why, "the reason presented once the state is final" if shown else "silently", bar.said))
    bar.done()
bar = Bar()
reached = bar.to_preparing()
taken = reached and bar.take(bar.frame(1, **refusal("prepare", "stale-context")), lambda: bar.state() == "idle")
expect(taken and bar.presented() == [("stale-context", "", "idle")],
       "layout action: T14 a prepare refused stale-context ends the action and presents the reason (%s)" % bar.said)
bar.done()


# T15: an own frame without the intent's fields as the provider adds them - a prepare's
# completion, a done prepare's preparation with its handle, a set's completion when it has one and
# no preparation, each with its reasons - ends the action, asks again with a query and presents
# "malformed"; the lifetime is offered no actions, though its answer shows the mode.
def amend(fields, part, key, value=MISSING):
    """A copy of an intent's frame fields with one key of one part set, or left out."""
    result = json.loads(json.dumps(fields))
    if value is MISSING:
        del result[part][key]
    else:
        result[part][key] = value
    return result


PREPARE_FIELDS = [
    ("no completion", {}),
    ("a completion that is null", dict(ready(), completion=None)),
    ("a completion that is no object", dict(ready(), completion="done")),
    ("a set's completion", dict(ready(), completion={"intent": "set", "result": "done"})),
    ("a result neither done nor refused", amend(ready(), "completion", "result", "maybe")),
    ("a refusal without a reason", amend(refusal("prepare", "busy"), "completion", "reason")),
    ("a refusal with an empty reason", refusal("prepare", "")),
    ("a refusal with a reason over 64 characters", refusal("prepare", "r" * 65)),
    ("a refusal with a malformed preparation", dict(refusal("prepare", "busy"), prepared={"ready": "no"})),
    ("a done prepare without a handle", amend(ready(), "completion", "handle")),
    ("an empty handle", ready(handle="")),
    ("a handle over 128 characters", ready(handle=E1 + ":" + "1" * 96)),
    ("a handle not of the frame's lifetime", ready(handle=E2 + ":1:1")),
    ("a target that is no boolean", amend(ready(), "completion", "target", "yes")),
    ("no target", amend(ready(), "completion", "target")),
    ("no target and no reason", amend(ready(target=False), "completion", "reason")),
    ("no preparation", {"completion": ready()["completion"]}),
    ("a preparation that is null", dict(ready(), prepared=None)),
    ("a preparation of another handle", amend(ready(), "prepared", "handle", E1 + ":1:2")),
    ("a readiness that is no boolean", amend(ready(), "prepared", "ready", "true")),
    ("a preparation not ready without a reason", amend(ended("focus-changed"), "prepared", "reason")),
]
PREPARED_FIELDS = [("no completion", {}), ("no preparation", {"completion": ready()["completion"]}),
                   ("a preparation not ready without a reason", amend(ended("focus-changed"), "prepared", "reason"))]
SET_FIELDS = [
    ("a prepare's completion", {"completion": ready()["completion"]}),
    ("a result neither done nor refused", {"completion": {"intent": "set", "result": "maybe"}}),
    ("a refusal without a reason", {"completion": {"intent": "set", "result": "refused"}}),
    ("a preparation", {"prepared": {"handle": HANDLE, "ready": True}}),
    ("a done set with a preparation", dict(DONE, prepared={"handle": HANDLE, "ready": True})),
]
malformed_cases = ([("preparing", "prepare", Bar.to_preparing, 1) + case for case in PREPARE_FIELDS]
                   + [("prepared", "prepare", Bar.to_prepared, 2) + case for case in PREPARED_FIELDS]
                   + [("setting", "set", Bar.to_setting, 1) + case for case in SET_FIELDS]
                   + [("awaiting", "set", lambda b: b.to_awaiting(True), 1) + case for case in SET_FIELDS])
for name, kind, reach, revision, why, fields in malformed_cases:
    bar = Bar()
    reached = reach(bar)
    count = bar.count()
    mark = len(action_messages)
    taken = reached and bar.take(bar.frame(revision, **fields), lambda: bar.state() == "idle")
    asked = taken and bar.sent(count) and bar.last().get("intent") == "query"
    answered = asked and bar.take(bar.frame(5), lambda: bar.get("outcome") == "answered")
    expect(logged(mark, [lacked_line(kind)]) and answered and bar.presented() == [("malformed", "", "idle")]
           and bar.get("mode") == "floating" and bar.get("actionsAvailable") is False and bar.open() is False,
           "layout action: T15 in %s, an own frame with %s ends the action, asks again and presents malformed; the"
           " lifetime is offered no actions, and the log says the provider's frame lacked the fields (%s)"
           % (name, why, bar.said))
    bar.done()

# T16: an own frame refused at frame level ends the action with the reason and asks again;
# intent, version and malformed leave that lifetime without actions, with a line in the log, and
# output does not. Another lifetime's answer brings them back.
for name, kind, why, marks, reach in (("preparing", "prepare", "output", False, Bar.to_preparing),
                                      ("preparing", "prepare", "intent", True, Bar.to_preparing),
                                      ("setting", "set", "version", True, Bar.to_setting),
                                      ("awaiting", "set", "malformed", True, lambda b: b.to_awaiting(True))):
    bar = Bar()
    reached = reach(bar)
    count = bar.count()
    mark = len(action_messages)
    taken = reached and bar.take(bar.frame(2, refused=why), lambda: bar.state() == "idle")
    asked = taken and bar.sent(count) and bar.last().get("intent") == "query"
    answered = asked and bar.take(bar.frame(5), lambda: bar.get("outcome") == "answered")
    expect(logged(mark, [refused_line(kind, why)] if marks else []) and answered
           and bar.presented() == [(why, "", "idle")] and bar.get("actionsAvailable") is (not marks),
           "layout action: T16 in %s, an own frame refused %s ends the action and asks again; the lifetime %s (%s)"
           % (name, why, "is offered no actions, said once in the log" if marks else "keeps its actions", bar.said))
    if why == "intent":
        count = bar.count()
        bar.deliver(frame(bar.log, 6, epoch=E2))
        back = answered and bar.sent(count) and bar.take(frame(bar.log, 1, epoch=E2), lambda: bar.get("epoch") == E2)
        expect(back and bar.get("actionsAvailable") is True and bar.open() is True,
               "layout action: actions come back once another lifetime answers")
    bar.done()
bar = Bar()
reached = bar.to_prepared()
count = bar.count()
taken = reached and bar.take(bar.frame(2, refused="output"), lambda: bar.state() == "idle")
expect(taken and bar.get("mode") == "unknown" and bar.get("actionHandle") == "" and bar.quiet(count) and not bar.said,
       "layout action: T16 is not for a prepared action: a frame refused at frame level then gives the mode only, and the"
       " action ends with nothing left to act on (T34)")
bar.done()


# T16a: a frame refused at frame level for the current intent, once its action has ended, asks
# again with a query and presents nothing; intent, version and malformed leave the lifetime without
# actions as T15 does, with the line in the log, and output does not. An action opened since then
# ends, as nothing is left to act on (T34). So does an open action's own intent after its decision,
# which the provider never refuses so. An open action's own set still undecided past its deadline
# is neither T16 nor T16a; its case is with T31's below.
def escaped(bar):
    """Escape while the prepare is out (T20): the action has ended, its prepare the current request."""
    reached = bar.to_preparing()
    bar.close(True)
    return reached and bar.state() == "idle"


def expired_after_escape(bar):
    """Escape while the prepare is out, then the prepare's deadline with no frame (T17b)."""
    reached = bar.to_open()
    bar.item.setProperty("deadlineMs", ROOMY_DEADLINE)
    count = bar.count()
    bar.input()
    sent = reached and bar.sent(count)
    bar.close(True)
    return sent and bar.state() == "idle" and until(lambda: bar.get("outcome") == "unconfirmed", ms=3000)


def reopened(bar):
    """Escape while the prepare is out, then the menu opened again (T1) with that prepare current."""
    return escaped(bar) and bar.open() is True and bar.state() == "open"


for name, reach, why, marks in (("in idle after Escape (T20)", escaped, "intent", True),
                                ("in idle after Escape (T20)", escaped, "output", False),
                                ("in idle past the prepare's deadline (T17b)", expired_after_escape, "version", True),
                                ("in idle past the prepare's deadline (T17b)", expired_after_escape, "output", False),
                                ("with the menu opened again (T1)", reopened, "malformed", True),
                                ("with the menu opened again (T1)", reopened, "output", False)):
    bar = Bar()
    reached = reach(bar)
    count = bar.count()
    mark = len(action_messages)
    taken = reached and bar.take(bar.frame(2, refused=why), lambda: bar.count() > count)
    asked = taken and bar.sent(count) and bar.last().get("intent") == "query" and bar.state() == "idle"
    answered = asked and bar.take(bar.frame(5), lambda: bar.get("outcome") == "answered")
    expect(logged(mark, [refused_line("prepare", why)] if marks else []) and answered and not bar.said
           and bar.get("mode") == "floating" and bar.get("actionsAvailable") is (not marks),
           "layout action: T16a %s, the prepare refused %s at frame level asks again, presents nothing, ends any action"
           " open and %s (%s)" % (name, why, "leaves the lifetime without actions" if marks else "keeps the actions",
                                  bar.said))
    bar.done()
for why, marks in (("intent", True), ("output", False)):
    bar = Bar()
    reached = bar.to_preparing()
    refused = reached and bar.take(bar.frame(1, **refusal("prepare", "busy")), lambda: bar.state() == "open")
    count = bar.count()
    mark = len(action_messages)
    taken = refused and bar.take(bar.frame(2, refused=why), lambda: bar.count() > count)
    asked = taken and bar.sent(count) and bar.last().get("intent") == "query" and bar.state() == "idle"
    answered = asked and bar.take(bar.frame(5), lambda: bar.get("outcome") == "answered")
    expect(logged(mark, [refused_line("prepare", why)] if marks else []) and answered
           and bar.presented() == [("busy", "", "open")] and bar.get("mode") == "floating"
           and bar.get("actionsAvailable") is (not marks),
           "layout action: T16a takes an open action's own prepare after its decision (T12), refused %s at frame level:"
           " the bar asks again, presents nothing, ends the action and %s (%s)"
           % (why, "leaves the lifetime without actions" if marks else "keeps the actions", bar.said))
    bar.done()


# The action ends before the actions go: a frame that leaves the lifetime without actions ends an
# open action first (T15, T16, T16a), so that actionOpen is false already as actionsAvailable turns
# false, and a close made then - the menu's, as the actions go - meets the ended action.
def notified(bar):
    """The changes of actionOpen and actionsAvailable from now on, in turn, each with the other's
    value as the change is notified."""
    seen = []
    for name, other in (("actionOpen", "actionsAvailable"), ("actionsAvailable", "actionOpen")):
        signal = getattr(bar.item, name + "Changed", None)
        if signal is not None:
            signal.connect(lambda name=name, other=other, item=bar.item: seen.append((name, prop(item, name), prop(item, other))))
    return seen


for row, reach, revision, fields, line in (
        ("T15 in preparing, an own frame with no completion,", Bar.to_preparing, 1, {}, lacked_line("prepare")),
        ("T16 in preparing, an own frame refused intent,", Bar.to_preparing, 2, {"refused": "intent"},
         refused_line("prepare", "intent")),
        ("T16a with the menu opened again (T1), the prepare refused malformed,", reopened, 2, {"refused": "malformed"},
         refused_line("prepare", "malformed")),
        ("T16a after the open action's own prepare was refused busy (T12), then refused version,",
         lambda b: b.to_preparing() and b.take(b.frame(1, **refusal("prepare", "busy")), lambda: b.state() == "open"), 2,
         {"refused": "version"}, refused_line("prepare", "version"))):
    bar = Bar()
    reached = reach(bar)
    count = bar.count()
    mark = len(action_messages)
    seen = notified(bar)
    taken = reached and bar.take(bar.frame(revision, **fields), lambda: bar.count() > count)
    asked = taken and bar.sent(count) and bar.last().get("intent") == "query" and bar.state() == "idle"
    answered = asked and bar.take(bar.frame(5), lambda: bar.get("outcome") == "answered")
    expect(logged(mark, [line]) and answered and bar.get("actionsAvailable") is False
           and seen == [("actionOpen", False, True), ("actionsAvailable", False, False)],
           "layout action: %s ends the open action before the actions go: actionOpen is false already as"
           " actionsAvailable turns false (%s)" % (row, seen))
    bar.done()

# T17, T17a: a prepare with no frame by its deadline drops the kept mode, ends the action and
# presents unconfirmed, a queued choice dropped. T17b: so does the deadline of a prepare whose
# action has ended, leaving the bar idle, or ending, as nothing is left to act on (T34), an action
# opened again meanwhile; it presents nothing.
for row, choice in (("T17", None), ("T17a", "tiled")):
    bar = Bar()
    reached = bar.to_open()
    bar.item.setProperty("deadlineMs", 300)
    count = bar.count()
    if choice is None:
        bar.input()
    else:
        bar.choose(choice)
    expired = reached and bar.sent(count) and until(lambda: bar.state() == "idle", ms=3000)
    expect(expired and bar.get("mode") == "unknown" and bar.get("outcome") == "unconfirmed"
           and bar.get("actionPending") is False and bar.presented() == [("unconfirmed", choice or "", "idle")]
           and bar.quiet(count + 1),
           "layout action: %s a prepare with no frame by its deadline ends the action, the mode unknown, and presents"
           " unconfirmed%s (%s)" % (row, ", its queued choice dropped" if choice else "", bar.said))
    bar.done()
bar = Bar()
reached = bar.to_open()
bar.item.setProperty("deadlineMs", ROOMY_DEADLINE)
count = bar.count()
bar.input()
sent = reached and bar.sent(count)
bar.close(True)
expired = sent and bar.state() == "idle" and until(lambda: bar.get("outcome") == "unconfirmed", ms=3000)
expect(expired and bar.get("mode") == "unknown" and bar.state() == "idle" and not bar.said and bar.quiet(count + 1),
       "layout action: T17b after Escape with the prepare unread, its deadline leaves the bar idle with the mode unknown")
bar.done()
bar = Bar()
reached = bar.to_open()
bar.item.setProperty("deadlineMs", ROOMY_DEADLINE)
count = bar.count()
bar.input()
sent = reached and bar.sent(count)
bar.close(True)
again = sent and bar.open() is True and bar.state() == "open"
expired = again and until(lambda: bar.get("outcome") == "unconfirmed", ms=3000)
expect(expired and bar.state() == "idle" and bar.get("mode") == "unknown" and not bar.said and bar.quiet(count + 1),
       "layout action: T17b the menu opened again before an unread prepare's deadline is ended by it, as nothing is left"
       " to act on (T34)")
bar.done()

# T18: a choice that can be sent, while prepared, sends a set with the handle.
for why, tiled, mode, target in (("Floating with no target", False, "floating", False),
                                 ("Tiled with a target", False, "tiled", True),
                                 ("Tiled on a tiled view with no target", True, "tiled", False)):
    bar = Bar(tiled=tiled)
    reached = bar.to_prepared(tiled=tiled, target=target)
    count = bar.count()
    bar.choose(mode)
    expect(reached and bar.state() == "setting" and bar.sent(count) and bar.last().get("intent") == "set"
           and bar.last().get("mode") == mode and bar.last().get("handle") == HANDLE and bar.get("actionHandle") == ""
           and bar.get("actionChoice") == mode and bar.get("actionPending") is True and bar.get("actionOpen") is True,
           "layout action: T18 %s, chosen while prepared, sends a set with the handle (%s)" % (why, bar.last()))
    bar.done()

# T20, T21: a close ends the action and sends nothing; while a set is out, the set stays awaited.
for name, reach, dismissed in (("open", Bar.to_open, True), ("preparing", Bar.to_preparing, True),
                               ("prepared", Bar.to_prepared, False)):
    bar = Bar()
    reached = reach(bar)
    count = bar.count()
    bar.close(dismissed)
    expect(reached and bar.state() == "idle" and bar.get("actionOpen") is False and bar.get("actionHandle") == ""
           and bar.quiet(count) and not bar.said,
           "layout action: T20 close(%s) in %s ends the action, and nothing is sent after it" % (str(dismissed).lower(), name))
    bar.done()
bar = Bar()
reached = bar.to_setting()
count = bar.count()
bar.close(True)
expect(reached and bar.state() == "awaiting" and bar.get("actionOpen") is False and bar.get("actionPending") is True
       and bar.quiet(count) and not bar.said,
       "layout action: T21 a close while setting ends the action, its set still awaited")
bar.done()

# T22, T22a: once the action has ended, a close changes how the menu closed only to the user's, and
# only while its set is awaited or unread; the close(false) the menu's hide makes after every end,
# also from inside the call that ended the action, changes nothing.
bar = Bar()
reached = bar.to_awaiting(False)
bar.close(True)
taken = reached and bar.state() == "awaiting" and bar.take(bar.frame(2, **refusal("set", "stale-context")),
                                                           lambda: bar.state() == "idle")
expect(taken and not bar.said,
       "layout action: T22 a press on the control after the menu closed by itself makes the close the user's: a"
       " stale-context refusal read after it stays silent (%s)" % bar.said)
bar.done()
bar = Bar()
reached = bar.to_setting(deadline=ROOMY_DEADLINE)
expired = reached and until(lambda: bar.state() == "idle", ms=3000)
bar.close(True)
taken = expired and bar.take(bar.frame(2, **refusal("set", "stale-context")), lambda: bar.get("revision") == 2)
expect(taken and bar.state() == "idle" and bar.presented() == [("unconfirmed", "floating", "idle")],
       "layout action: T22 past a set's deadline with the set unread, a press on the control makes the close the user's:"
       " its late stale-context refusal stays silent (%s)" % bar.said)
bar.done()
bar = Bar()
reached = bar.to_awaiting(True)
bar.close(False)
taken = reached and bar.state() == "awaiting" and bar.take(bar.frame(2, **refusal("set", "stale-context")),
                                                           lambda: bar.state() == "idle")
expect(taken and not bar.said,
       "layout action: T22a the close(false) after the user's close changes nothing: a stale-context refusal read after"
       " it stays silent (%s)" % bar.said)
bar.done()
bar = Bar()
reached = bar.to_setting()
taken = reached and bar.take(bar.frame(1, **DONE), lambda: bar.state() == "idle")
count = bar.count()
bar.close(False)
bar.close(True)
expect(taken and bar.state() == "idle" and bar.presented() == [("", "floating", "idle")] and bar.quiet(count),
       "layout action: T22a a close after a done set has ended the action changes nothing (%s)" % bar.said)
bar.done()
bar = Bar()
inside = []


def hidden(bar=bar):
    """The menu's hide as main.qml's wiring makes it: close(false) from inside the change that says
    the action is no longer open."""
    if bar.get("actionOpen") is False:
        inside.append("hidden")
        bar.close(False)


notify = getattr(bar.item, "actionOpenChanged", None)
if notify is not None:
    notify.connect(hidden)
reached = bar.to_setting()
bar.close(True)
awaited = bar.state() == "awaiting" and bar.get("actionPending") is True
taken = reached and awaited and bar.take(bar.frame(2, **refusal("set", "stale-context")), lambda: bar.state() == "idle")
expect(taken and inside == ["hidden"] and not bar.said,
       "layout action: the menu's hide calling close(false) from inside the user's close meets the ended action, and a"
       " stale-context refusal read after it stays silent (%s, %s)" % (inside, bar.said))
bar.done()

# T23 to T29: a set's frames. One without a completion reads the set and gives the mode; a done
# set ends the action and clears the notice; a refusal leaves the menu open with its reason, or
# ends the action, silently after the user's close where the set was refused because the menu had
# closed before it was read.
bar = Bar()
reached = bar.to_setting()
taken = reached and bar.take(bar.frame(1, tiled=True), lambda: bar.get("outcome") == "answered")
expect(taken and bar.state() == "setting" and bar.get("mode") == "tiled" and not bar.said,
       "layout action: T23 a set's frame without a completion changes nothing but the mode it gives")
bar.done()
bar = Bar()
reached = bar.to_awaiting(False)
taken = reached and bar.take(bar.frame(1), lambda: bar.get("outcome") == "answered")
refused = taken and bar.take(bar.frame(2, **refusal("set", "stale-context")), lambda: bar.state() == "idle")
expect(refused and bar.presented() == [("stale-context", "floating", "idle")],
       "layout action: T23 a set read in a frame without a completion is no longer unread: a later stale-context refusal"
       " is its reason (T29), not an interruption (%s)" % bar.said)
bar.done()
bar = Bar()
reached = bar.to_setting()
taken = reached and bar.take(bar.frame(1, **DONE), lambda: bar.state() == "idle")
expect(taken and bar.get("actionOpen") is False and bar.said == [("", "floating", "idle", "", False)],
       "layout action: T24 a done set while setting ends the action and clears the notice (%s)" % bar.said)
bar.done()
bar = Bar()
reached = bar.to_awaiting(True)
taken = reached and bar.take(bar.frame(1, **DONE), lambda: bar.state() == "idle")
expect(taken and bar.presented() == [("", "floating", "idle")] and bar.get("actionPending") is False,
       "layout action: T24 a done set while awaited ends it and clears the notice (%s)" % bar.said)
bar.done()
for why in ("stale-context", "focus-changed"):
    for dismissed in (True, False):
        bar = Bar()
        reached = bar.to_awaiting(dismissed, mode="tiled")
        taken = reached and bar.take(bar.frame(1, **refusal("set", why)), lambda: bar.state() == "idle")
        expect(taken and bar.presented() == ([] if dismissed else [("interrupted", "tiled", "idle")]),
               "layout action: T25 a set refused %s in its first frame after close(%s) %s (%s)"
               % (why, str(dismissed).lower(), "stays silent" if dismissed else "presents interrupted", bar.said))
        bar.done()
for why in ("stale-context", "focus-changed", "target-departed"):
    bar = Bar()
    reached = bar.to_setting("tiled")
    taken = reached and bar.take(bar.frame(1, **refusal("set", why)), lambda: bar.state() == "open")
    expect(taken and bar.said == [(why, "tiled", "open", why, False)] and bar.get("actionChoice") == "tiled",
           "layout action: T26 a set refused %s with the menu open leaves the action open and presents the reason (%s)"
           % (why, bar.said))
    bar.done()
bar = Bar()
reached = bar.to_setting()
taken = reached and bar.take(bar.frame(1, **refusal("set", "view-changed")), lambda: bar.state() == "idle")
expect(taken and bar.presented() == [("view-changed", "floating", "idle")],
       "layout action: T27 a set refused view-changed while setting ends the action and presents the reason (%s)" % bar.said)
bar.done()
bar = Bar()
reached = bar.to_awaiting(False)
taken = reached and bar.take(bar.frame(1, **refusal("set", "shell-replaced")), lambda: bar.state() == "idle")
expect(taken and bar.presented() == [("shell-replaced", "floating", "idle")],
       "layout action: T27 a set refused shell-replaced while awaited ends it and presents the reason (%s)" % bar.said)
bar.done()
for mode, why in (("floating", "unavailable"), ("tiled", "no-target")):
    bar = Bar()
    reached = bar.to_setting(mode)
    taken = reached and bar.take(bar.frame(1, **refusal("set", why)), lambda: bar.state() == "open")
    expect(taken and bar.said == [(why, mode, "open", why, False)] and bar.get("actionChoice") == mode,
           "layout action: T28 a %s set refused %s with the menu open leaves it open and presents the reason with that"
           " mode, once the state is final (%s)" % (mode, why, bar.said))
    bar.done()
bar = Bar()
reached = bar.to_awaiting(True, mode="tiled")
taken = reached and bar.take(bar.frame(1, **refusal("set", "target-departed")), lambda: bar.state() == "idle")
expect(taken and bar.presented() == [("target-departed", "tiled", "idle")],
       "layout action: T29 a set refused target-departed while awaited ends it and presents the reason (%s)" % bar.said)
bar.done()


# T30, T31: a set with no frame by its deadline drops the kept mode and ends the action; one with
# frames but no completion keeps the mode, and leaves the menu open, or ends an awaited set.
# Either presents unconfirmed. T32: the set's first completion after that, while it is still the
# current request, clears the notice or presents its refusal, as it would have while awaited.
def late_set(dismissed=None, frames=False):
    """A bar whose set's deadline has passed: with no frame (T30), or after a frame without a
    completion (T31); closed by the user first when `dismissed`."""
    bar = Bar()
    if dismissed is None:
        reached = bar.to_setting(deadline=ROOMY_DEADLINE)
    else:
        reached = bar.to_awaiting(dismissed, deadline=ROOMY_DEADLINE)
    if frames:
        reached = reached and bar.take(bar.frame(1), lambda: bar.get("outcome") == "answered")
    waiting = bar.state()
    return bar, reached and waiting in ("setting", "awaiting") and until(lambda: bar.state() != waiting, ms=3000)


bar, late = late_set()
expect(late and bar.state() == "idle" and bar.get("mode") == "unknown" and bar.get("outcome") == "unconfirmed"
       and bar.get("actionPending") is False and bar.presented() == [("unconfirmed", "floating", "idle")],
       "layout action: T30 a set with no frame by its deadline ends the action, the mode unknown, and presents"
       " unconfirmed (%s)" % bar.said)
taken = late and bar.take(bar.frame(2, **DONE), lambda: len(bar.said) == 2)
expect(taken and bar.state() == "idle" and bar.presented()[1:] == [("", "floating", "idle")] and bar.get("mode") == "floating",
       "layout action: T32 a set's late done in idle clears the notice, and its frame shows the mode again (%s)" % bar.said)
bar.done()
bar, late = late_set(frames=True)
expect(late and bar.state() == "open" and bar.get("mode") == "floating" and bar.get("actionPending") is False
       and bar.presented() == [("unconfirmed", "floating", "open")],
       "layout action: T31 a set with frames but no completion by its deadline leaves the menu open, the mode kept, and"
       " presents unconfirmed (%s)" % bar.said)
taken = late and bar.take(bar.frame(2, **DONE), lambda: len(bar.said) == 2)
expect(taken and bar.state() == "idle" and bar.presented()[1:] == [("", "floating", "idle")],
       "layout action: T32 a set's late done in open ends the action and clears the notice (%s)" % bar.said)
bar.done()
bar, late = late_set(dismissed=True, frames=True)
expect(late and bar.state() == "idle" and bar.get("mode") == "floating" and bar.presented() == [("unconfirmed", "floating", "idle")],
       "layout action: T31 an awaited set with frames but no completion by its deadline ends unconfirmed (%s)" % bar.said)
bar.done()
bar, late = late_set()
taken = late and bar.take(bar.frame(2, **refusal("set", "unavailable")), lambda: len(bar.said) == 2)
expect(taken and bar.state() == "idle" and bar.presented()[1:] == [("unavailable", "floating", "idle")],
       "layout action: T32 a set's late refusal in idle presents the reason (%s)" % bar.said)
again = taken and bar.barrier(3, view=ELSEWHERE, **refusal("set", "unavailable"))
expect(again and len(bar.said) == 2,
       "layout action: after a late refusal (T32) a newer frame with the same completion presents nothing again (%s)"
       % bar.said)
bar.done()
bar, late = late_set(frames=True)
taken = late and bar.state() == "open" and bar.take(bar.frame(2, **refusal("set", "unavailable")), lambda: len(bar.said) == 2)
expect(taken and bar.state() == "open" and bar.presented()[1:] == [("unavailable", "floating", "open")],
       "layout action: T32 a set's late refusal in open leaves the action open and presents the reason (%s)" % bar.said)
bar.done()
# T16a takes an open action's own intent only after its decision: a set still undecided past its
# deadline (T31) is neither T16 nor T16a, so its frame refused at frame level gives the mode only
# and the action ends with nothing left to act on (T35a, then T34), with no query.
bar, late = late_set(frames=True)
opened = late and bar.state() == "open"
count = bar.count()
mark = len(action_messages)
taken = opened and bar.take(bar.frame(2, refused="intent"), lambda: bar.state() == "idle")
quiet = taken and bar.quiet(count) and bar.get("mode") == "unknown"
back = quiet and bar.barrier(3)
expect(logged(mark, []) and back and bar.get("actionsAvailable") is True
       and bar.presented() == [("unconfirmed", "floating", "open")],
       "layout action: T16a takes an open action's own intent after its decision only: its set still undecided past the"
       " deadline (T31), refused at frame level, gives the mode only and ends the action (T35a, then T34), with no query"
       " and the lifetime left its actions (%s)" % bar.said)
bar.done()
bar, late = late_set()
taken = late and bar.take(bar.frame(2, **refusal("set", "stale-context")), lambda: len(bar.said) == 2)
expect(taken and bar.presented()[1:] == [("interrupted", "floating", "idle")],
       "layout action: T32 a set's late first frame refused stale-context, the menu having closed by itself, presents"
       " interrupted (%s)" % bar.said)
bar.done()
bar, late = late_set(dismissed=True)
taken = late and bar.take(bar.frame(2, **refusal("set", "stale-context")), lambda: bar.get("revision") == 2)
expect(taken and bar.presented() == [("unconfirmed", "floating", "idle")],
       "layout action: T32 the user's close recorded at T21 survives the move from awaiting to idle at T30: the set's late"
       " stale-context refusal stays silent (%s)" % bar.said)
bar.done()
bar, late = late_set(frames=True)
opened = late and bar.state() == "open"
bar.item.setProperty("deadlineMs", 300)
count = bar.count()
bar.input()
expired = opened and bar.sent(count) and until(lambda: bar.state() == "idle", ms=3000)
shown = list(bar.said)
taken = expired and bar.take(bar.frame(2, **ready()), lambda: bar.get("outcome") == "answered")
expect(taken and bar.said == shown and len(shown) == 2,
       "layout action: a new request is no late set: a prepare sent after a set's deadline, past its own deadline too, gives"
       " the mode only when its frame comes (T35a, not T32) (%s)" % bar.said)
bar.done()
# T32 counts in idle, or in the action that sent the set: a late completion reaching an action
# opened after the set's deadline gives the mode only (T35), and that menu stays open. Once that
# menu has closed in turn, the bar is idle again and the late completion counts.
for why, fields in (("done", DONE), ("refused unavailable", refusal("set", "unavailable"))):
    bar, late = late_set(dismissed=True, frames=True)
    again = late and bar.state() == "idle" and bar.open() is True
    taken = again and bar.barrier(2, **fields)
    expect(taken and bar.state() == "open" and bar.get("actionOpen") is True
           and bar.presented() == [("unconfirmed", "floating", "idle")],
           "layout action: T35 a set's late completion (%s) reaching an action opened after its deadline gives the mode"
           " only, and the new menu stays open (%s)" % (why, bar.said))
    bar.done()
bar, late = late_set(dismissed=True, frames=True)
again = late and bar.open() is True
bar.close(True)
taken = again and bar.state() == "idle" and bar.take(bar.frame(2, **DONE), lambda: len(bar.said) == 2)
expect(taken and bar.presented() == [("unconfirmed", "floating", "idle"), ("", "floating", "idle")],
       "layout action: T32 counts in idle whichever action ended last: a late done set clears the notice once the menu"
       " opened since has closed (%s)" % bar.said)
bar.done()

# T33: asking again - another lifetime, the bound lifetime's offline frame or its name gone, going
# idle - ends the action, with a query unless the bar goes idle, and presents unconfirmed when a
# set was out.
bar = Bar()
reached = bar.to_setting()
count = bar.count()
bar.deliver(bar.frame(2, epoch=E2))
asked = reached and until(lambda: bar.state() == "idle") and bar.sent(count)
expect(asked and bar.last().get("intent") == "query" and bar.get("mode") == "unknown"
       and bar.presented() == [("unconfirmed", "", "idle")],
       "layout action: T33 another lifetime answering while a set is out ends the action, asks again with a query and"
       " presents unconfirmed (%s)" % bar.said)
bar.done()
bar = Bar()
reached = bar.to_prepared()
count = bar.count()
bar.deliver(bar.frame(2, status="offline"))
asked = reached and until(lambda: bar.state() == "idle") and bar.sent(count)
expect(asked and bar.last().get("intent") == "query" and not bar.said,
       "layout action: T33 the bound lifetime's offline frame ends a prepared action and asks again, silently")
bar.done()
check(bus.registerService(PREFIX + E10), "layout action: another identity name is held here")
bar = Bar(epoch=E10)
reached = bar.to_open()
count = bar.count()
bus.unregisterService(PREFIX + E10)
asked = reached and until(lambda: bar.state() == "idle") and bar.sent(count)
expect(asked and bar.last().get("intent") == "query" and not bar.said,
       "layout action: T33 the bound lifetime's identity name released ends an open action and asks again, silently")
bar.done()
bar = Bar()
reached = bar.to_awaiting(True)
count = bar.count()
bar.item.setProperty("outputName", "")
expect(reached and bar.state() == "idle" and bar.get("outcome") == "idle" and bar.quiet(count)
       and bar.presented() == [("unconfirmed", "floating", "idle")],
       "layout action: T33 going idle while a set is awaited sends no query, and presents unconfirmed (%s)" % bar.said)
bar.done()

# T34: actions becoming unavailable end the action; a set already sent stays awaited, its close
# recorded as not the user's.
bar = Bar()
reached = bar.to_open()
taken = reached and bar.take(bar.frame(2, capable=False), lambda: bar.state() == "idle")
expect(taken and bar.get("mode") == "unavailable" and not bar.said,
       "layout action: T34 an open action ends when actions become unavailable, silently")
bar.done()
bar = Bar()
reached = bar.to_preparing("floating")
count = bar.count()
taken = reached and bar.take(bar.frame(1, capable=False, **ready()), lambda: bar.state() == "idle")
expect(taken and bar.get("actionPending") is False and bar.quiet(count) and not bar.said,
       "layout action: T34 a preparing action ends when its prepare's frame leaves nothing to act on, and its queued choice"
       " is not sent")
bar.done()
bar = Bar()
reached = bar.to_prepared()
taken = reached and bar.take(bar.frame(2, view=None, **ready()), lambda: bar.state() == "idle")
expect(taken and bar.get("actionHandle") == "" and not bar.said, "layout action: T34 a prepared action ends when its output goes")
bar.done()
bar = Bar()
reached = bar.to_setting()
taken = reached and bar.take(bar.frame(1, capable=False), lambda: bar.state() == "awaiting")
expect(taken and bar.get("actionOpen") is False and bar.get("actionPending") is True and not bar.said,
       "layout action: T34 a setting action whose actions become unavailable still awaits its set")
bar.done()
bar = Bar()
reached = bar.to_setting()
taken = reached and bar.take(bar.frame(1, capable=False, **refusal("set", "stale-context")), lambda: bar.state() == "idle")
expect(taken and bar.presented() == [("interrupted", "floating", "idle")],
       "layout action: T34 records a close that is not the user's: a stale-context refusal in the same first frame presents"
       " interrupted (%s)" % bar.said)
bar.done()

# T35, T35a: a frame of a request the action did not send, or one whose completion has been taken,
# gives the mode only. A prepare sent before Escape and read after the menu opened again gives the
# new action no handle, and a choice queued before Escape is not sent when the handle comes.
bar = Bar()
reached = bar.to_open()
taken = reached and bar.take(bar.frame(2, tiled=True), lambda: bar.get("revision") == 2)
expect(taken and bar.state() == "open" and bar.get("mode") == "tiled" and not bar.said,
       "layout action: T35 a query's frame while open gives the mode only")
bar.done()
bar = Bar()
reached = bar.to_preparing()
prepare = bar.last()
bar.close(True)
again = reached and bar.open() is True
taken = again and bar.take(bar.frame(1, **ready()), lambda: bar.get("outcome") == "answered")
still = taken and bar.state() == "open" and bar.get("actionHandle") == ""
count = bar.count()
bar.input()
expect(still and bar.state() == "preparing" and bar.sent(count) and bar.last().get("intent") == "prepare"
       and bar.last().get("request") == prepare.get("request", 0) + 1 and not bar.said,
       "layout action: T35 a prepare sent before Escape and read after the menu opened again gives the new action no"
       " handle; its first input prepares afresh (%s)" % bar.last())
bar.done()
bar = Bar()
reached = bar.to_preparing()
refused = reached and bar.take(bar.frame(1, **refusal("prepare", "busy")), lambda: bar.state() == "open")
taken = refused and bar.barrier(2, tiled=True, **refusal("prepare", "busy"))
expect(taken and bar.state() == "open" and bar.get("mode") == "tiled" and bar.presented() == [("busy", "", "open")],
       "layout action: T35a a later frame of a refused prepare gives the mode only (%s)" % bar.said)
bar.done()
bar = Bar()
reached = bar.to_preparing("tiled")
bar.close(True)
count = bar.count()
taken = reached and bar.take(bar.frame(1, tiled=True, **ready()), lambda: bar.get("outcome") == "answered")
expect(taken and bar.state() == "idle" and bar.get("mode") == "tiled" and bar.get("actionPending") is False
       and bar.get("actionHandle") == "" and bar.quiet(count) and not bar.said,
       "layout action: T35a a choice queued, Escape, then the prepare's ready frame: the mode only, and no set sent")
bar.done()
bar = Bar()
reached = bar.to_prepared()
taken = reached and bar.barrier(2, tiled=True, **ready())
expect(taken and bar.state() == "prepared" and bar.get("mode") == "tiled" and bar.get("actionHandle") == HANDLE
       and not bar.said, "layout action: T35a a prepared action's later ready frame gives the mode only")
bar.done()

# T36: an input outside open, and a choice in idle, with one queued, while a set is out or for a
# blocked Tiled, are ignored; so is a choice that names no mode.
for name, reach in (("idle", lambda b: True), ("preparing", Bar.to_preparing), ("prepared", Bar.to_prepared),
                    ("setting", Bar.to_setting), ("awaiting", lambda b: b.to_awaiting(True))):
    bar = Bar()
    reached = reach(bar)
    count = bar.count()
    bar.input()
    expect(reached and bar.state() == name and bar.quiet(count), "layout action: T36 an input in %s is ignored" % name)
    bar.done()
for name, reach, mode in (("idle", lambda b: True, "floating"),
                          ("preparing with a choice queued", lambda b: b.to_preparing("tiled"), "floating"),
                          ("setting", Bar.to_setting, "tiled"), ("awaiting", lambda b: b.to_awaiting(True), "tiled"),
                          ("prepared, for a blocked Tiled", lambda b: b.to_prepared(target=False), "tiled"),
                          ("open, naming no mode", Bar.to_open, "sideways")):
    bar = Bar()
    reached = reach(bar)
    count = bar.count()
    before = (bar.state(), bar.get("actionChoice"), bar.get("actionPending"))
    bar.choose(mode)
    expect(reached and before[0] is not None and (bar.state(), bar.get("actionChoice"), bar.get("actionPending")) == before
           and bar.quiet(count), "layout action: T36 a choice in %s is ignored" % name)
    bar.done()

# A completion counts once: a newer frame of the request with the same completion, as a desktop
# switch publishes one, presents nothing again; nor does a prepared action's later frame repeat
# the prepare's reason.
for row, reach, why in (("T28", Bar.to_setting, "unavailable"), ("T25", lambda b: b.to_awaiting(True), "stale-context"),
                        ("T27", Bar.to_setting, "view-changed"), ("T29", lambda b: b.to_awaiting(True), "target-departed")):
    bar = Bar()
    reached = reach(bar)
    taken = reached and bar.take(bar.frame(1, **refusal("set", why)), lambda: bar.get("outcome") == "answered")
    shown = list(bar.said)
    again = taken and bar.barrier(2, view=ELSEWHERE, **refusal("set", why))
    expect(again and bar.said == shown and len(shown) == (0 if row == "T25" else 1),
           "layout action: after %s a newer frame of the set with the same refusal presents nothing again (%s)" % (row, bar.said))
    bar.done()
bar = Bar()
reached = bar.to_prepared(target=False)
taken = reached and bar.barrier(2, **ready(target=False))
expect(taken and bar.state() == "prepared" and bar.presented() == [("no-target", "", "prepared")],
       "layout action: in prepared after T8 a later frame does not present the prepare's reason again (%s)" % bar.said)
bar.done()

# The handle is the prepared action's alone, and emptied whenever it leaves prepared; the choice
# and the reason last until the next request, which clears them, so that an outcome is worded for
# its mode; the mode comes from the frames, never from a completion.
exits = []
for name, step in (("for a set", lambda b: b.choose("floating")),
                   ("for an ended preparation", lambda b: b.take(b.frame(2, **ended("focus-changed")),
                                                                 lambda: b.state() == "open")),
                   ("for a close", lambda b: b.close(True))):
    bar = Bar()
    reached = bar.to_prepared()
    held = bar.get("actionHandle")
    step(bar)
    exits.append((name, reached and held == HANDLE and bar.state() != "prepared" and bar.get("actionHandle") == ""
                  and bar.get("actionTarget") is False))
    bar.done()
expect(all(left for _, left in exits),
       "layout action: the handle is held only while prepared, and emptied as the action leaves (%s)" % exits)
bar = Bar()
reached = bar.to_setting("tiled")
refused = reached and bar.take(bar.frame(1, **refusal("set", "busy")), lambda: bar.state() == "open")
kept = refused and bar.get("actionChoice") == "tiled" and bar.get("actionReason") == "busy"
count = bar.count()
bar.input()
expect(kept and bar.sent(count) and bar.get("actionChoice") == "" and bar.get("actionReason") == "",
       "layout action: the choice and the reason are kept until the next request, which clears them")
bar.done()
bar = Bar()
reached = bar.to_awaiting(True, mode="tiled")
taken = reached and bar.take(bar.frame(1, **refusal("set", "target-departed")), lambda: bar.state() == "idle")
kept = taken and bar.get("actionChoice") == "tiled" and bar.get("actionReason") == "target-departed"
count = bar.count()
bar.item.setProperty("outputName", "Virtual-1")
expect(kept and bar.sent(count) and bar.last().get("intent") == "query" and bar.state() == "idle"
       and bar.get("actionChoice") == "" and bar.get("actionReason") == "" and len(bar.said) == 1,
       "layout action: a query clears the choice and the reason too, with the state left idle")
bar.done()
bar = Bar()
reached = bar.to_preparing()
refused = reached and bar.take(bar.frame(1, **refusal("prepare", "busy")), lambda: bar.state() == "open")
shown = refused and bar.get("actionReason") == "busy"
count = bar.count()
bar.close(True)
expect(shown and bar.state() == "idle" and bar.get("actionReason") == "" and bar.quiet(count) and len(bar.said) == 1,
       "layout action: a change of state that presents nothing clears the reason shown")
bar.done()
bar = Bar()
reached = bar.to_setting("floating")
taken = reached and bar.take(bar.frame(1, **DONE), lambda: bar.state() == "idle")
expect(taken and bar.open() is True and bar.get("actionChoice") == "floating",
       "layout action: an action opened again keeps the last choice, as no request has been sent since")
bar.done()
bar = Bar()
reached = bar.to_setting("tiled")
taken = reached and bar.take(bar.frame(1, **DONE), lambda: bar.state() == "idle")
expect(taken and bar.get("mode") == "floating",
       "layout action: a done Tiled set whose frame says floating leaves the mode floating: the mode comes from the frames")
bar.done()


# Each property changes at most once in one input, frame or deadline, counted from just before it:
# T3, T4, T7, T8 on a frame that also turns the view tiled, T18, a frame that both leaves the menu
# open and ends the action (T26, then T5), T15 from prepared with a reason shown, and a deadline
# that leaves the menu open and ends the action (T31, then T5).
def counted(bar, act, test, ms=2000, **exactly):
    """Act on the bar from its state now and wait for `test`: whether every property changed at most
    once, and those named exactly as often, with the counts."""
    counter = ChangeCounts(bar)
    act()
    return until(test, ms=ms) and counter.once(**exactly), dict(counter.counts)


bar = Bar()
reached = bar.to_open()
ok, counts = counted(bar, bar.input, lambda: bar.state() == "preparing", actionState=1, outcome=1, actionReason=0)
expect(reached and ok, "layout action: T3 changes each property at most once (%s)" % counts)
bar.done()
bar = Bar()
reached = bar.to_open()
ok, counts = counted(bar, lambda: bar.choose("tiled"), lambda: bar.state() == "preparing",
                     actionState=1, actionChoice=1, actionPending=1, outcome=1)
expect(reached and ok, "layout action: T4 changes each property at most once (%s)" % counts)
bar.done()
bar = Bar()
reached = bar.to_preparing("floating")
ok, counts = counted(bar, lambda: bar.deliver(bar.frame(1, **ready(target=False))), lambda: bar.state() == "setting",
                     actionState=1, actionHandle=0, actionTarget=0, actionChoice=0, actionPending=0, outcome=0)
expect(reached and ok, "layout action: T7 sends the set with the prepare's handle, never held, and changes each property at"
       " most once: the choice, the pending flag and the outcome not at all (%s)" % counts)
bar.done()
bar = Bar()
reached = bar.to_preparing()
ok, counts = counted(bar, lambda: bar.deliver(bar.frame(1, tiled=True, **ready(target=False))),
                     lambda: bar.state() == "prepared", actionState=1, mode=1, tiledBlocked=0, actionHandle=1)
expect(reached and ok, "layout action: T8 on a frame that turns the view tiled takes the mode before the state, so Tiled is"
       " never blocked on the way (%s)" % counts)
bar.done()
bar = Bar()
reached = bar.to_preparing()
ok, counts = counted(bar, lambda: bar.deliver(bar.frame(1, **ready(target=True))), lambda: bar.state() == "prepared",
                     actionState=1, actionTarget=1, tiledBlocked=0, actionHandle=1)
expect(reached and ok, "layout action: T8 with an app to tile holds the target before the state, so Tiled is never blocked"
       " on the way (%s)" % counts)
bar.done()
bar = Bar()
reached = bar.to_preparing("tiled") and bar.take(bar.frame(1, **ready(target=False, why="focus-changed")),
                                                 lambda: bar.state() == "prepared")
ok, counts = counted(bar, lambda: bar.choose("floating"), lambda: bar.state() == "setting", actionState=1, actionChoice=1,
                     actionHandle=1, tiledBlocked=1, actionPending=1, actionReason=1, outcome=1)
expect(reached and ok, "layout action: T18 after T9 changes each property at most once (%s)" % counts)
bar.done()
bar = Bar()
reached = bar.to_setting()
ok, counts = counted(bar, lambda: bar.deliver(bar.frame(1, view=ELSEWHERE, **refusal("set", "stale-context"))),
                     lambda: bar.state() == "idle", actionState=1, actionOpen=1, actionPending=1, actionReason=1)
expect(reached and ok, "layout action: a frame that leaves the menu open and ends the action (T26, then T5) moves the state"
       " once (%s)" % counts)
bar.done()
bar = Bar()
reached = bar.to_prepared(target=False)
mark = len(action_messages)
ok, counts = counted(bar, lambda: bar.deliver(bar.frame(2)), lambda: bar.state() == "idle",
                     actionState=1, actionReason=1, actionsAvailable=1, mode=1, outcome=1, actionHandle=1)
expect(logged(mark, [lacked_line("prepare")]) and reached and ok,
       "layout action: T15 from prepared, a reason shown, changes the reason, the mode and the outcome once: the frame's"
       " state is not held before the bar asks again (%s)" % counts)
bar.done()
bar = Bar()
reached = bar.to_setting(deadline=ROOMY_DEADLINE)
read = reached and bar.take(bar.frame(2, view=ELSEWHERE), lambda: bar.get("revision") == 2)
ok, counts = counted(bar, lambda: None, lambda: bar.state() == "idle", ms=3000, actionState=1, actionReason=1)
expect(read and ok, "layout action: a deadline that leaves the menu open and ends the action (T31, then T5) moves the"
       " state once (%s)" % counts)
bar.done()

# The revision floor: an intent's first frame below the revision shown is not taken, nor a fresh
# query's first frame at revision 0, which offers no actions.
bar = Bar(revision=2)
reached = bar.to_preparing()
bar.deliver(bar.frame(1, **refusal("prepare", "busy")))
taken = reached and bar.take(bar.frame(2, **ready()), lambda: bar.state() == "prepared")
expect(taken and not bar.said and bar.get("actionHandle") == HANDLE,
       "layout action: an intent's first frame below the revision shown is not taken (%s)" % bar.said)
bar.done()
floor_bar, floor_log = create(outputName="Virtual-0")
until(lambda: floor_log["requests"])
mark = len(floor_log["history"])
deliver(floor_bar, frame(floor_log, 0, tiled=True))
deliver(floor_bar, frame(floor_log, 1))
taken = until(lambda: prop(floor_bar, "revision") == 1)
expect(taken and prop(floor_bar, "mode") == "floating" and prop(floor_bar, "actionsAvailable") is True
       and not [h for h in floor_log["history"][mark:] if h[1] == "tiled"],
       "layout action: a fresh query's first frame at revision 0 is not taken, and the actions come only with an answer"
       " taken (%s)" % floor_log["history"][mark:])
floor_bar.deleteLater()

# The closes main.qml's wiring will make from inside the layout state's own change - the menu's
# hide, and the control's as the mode goes - meet an action already ended, whether a frame (T24;
# T34 with the set's first refusal in that frame), a deadline (T30), a refusal at frame level (T16)
# or another lifetime (T33) ends it: the state moves once and the row presents its own outcome.
bar = Bar()
calls = wire(bar)
reached = bar.to_setting()
del calls[:]
ok, counts = counted(bar, lambda: bar.deliver(bar.frame(1, **DONE)), lambda: bar.state() == "idle", actionState=1)
expect(reached and ok and calls == ["menu"] and bar.said == [("", "floating", "idle", "", False)],
       "layout action: the menu's close(false) from inside a done set's end (T24) changes nothing (%s, %s, %s)"
       % (calls, bar.said, counts))
bar.done()
bar = Bar()
calls = wire(bar)
user = bar.to_open()
bar.close(True)
reached = user and bar.state() == "idle" and bar.to_setting()
del calls[:]
ok, counts = counted(bar, lambda: bar.deliver(bar.frame(1, capable=False, **refusal("set", "stale-context"))),
                     lambda: bar.state() == "idle", actionState=1, mode=1)
expect(reached and ok and calls == ["menu", "control"] and bar.presented() == [("interrupted", "floating", "idle")],
       "layout action: a frame whose mode ends a setting action (T34) with the set refused stale-context presents"
       " interrupted, an earlier action's close by the user notwithstanding, and the closes from inside meet the action"
       " ended (%s, %s, %s)" % (calls, bar.said, counts))
bar.done()
bar = Bar()
calls = wire(bar)
reached = bar.to_setting(deadline=ROOMY_DEADLINE)
del calls[:]
ok, counts = counted(bar, lambda: None, lambda: bar.state() == "idle", ms=3000, actionState=1, mode=1)
late_refusal = reached and ok and bar.take(bar.frame(2, **refusal("set", "stale-context")), lambda: len(bar.said) == 2)
expect(late_refusal and calls == ["menu", "control"]
       and bar.presented() == [("unconfirmed", "floating", "idle"), ("interrupted", "floating", "idle")],
       "layout action: the closes from inside a set's deadline (T30) meet the ended action, and its late stale-context"
       " refusal presents interrupted (%s, %s, %s)" % (calls, bar.said, counts))
bar.done()
bar = Bar()
calls = wire(bar)
reached = bar.to_setting()
del calls[:]
mark = len(action_messages)
ok, counts = counted(bar, lambda: bar.deliver(bar.frame(2, refused="version")), lambda: bar.state() == "idle",
                     actionState=1, mode=1, actionsAvailable=1)
expect(logged(mark, [refused_line("set", "version")]) and reached and ok and calls == ["menu", "control"]
       and bar.presented() == [("version", "", "idle")],
       "layout action: a set refused at frame level (T16) ends the action before the mode goes, so the closes from inside"
       " meet it ended (%s, %s, %s)" % (calls, bar.said, counts))
bar.done()
bar = Bar()
calls = wire(bar)
reached = bar.to_setting()
del calls[:]
ok, counts = counted(bar, lambda: bar.deliver(bar.frame(2, epoch=E2)), lambda: bar.state() == "idle",
                     actionState=1, mode=1)
expect(reached and ok and calls == ["menu", "control"] and bar.presented() == [("unconfirmed", "", "idle")],
       "layout action: another lifetime's frame while a set is out (T33) ends the action before the mode goes (%s, %s, %s)"
       % (calls, bar.said, counts))
bar.done()
QTest.qWait(50)
qInstallMessageHandler(None)
# Compared as a sequence; the message counts each line, as several cases log the same one.
logged_counts, expected_counts = collections.Counter(action_messages), collections.Counter(expected_lines)
expect(action_messages == expected_lines,
       "layout action: the cases log one line for each lifetime left without actions, as expected, and nothing else"
       " (%d logged, %d expected; logged more often than expected: %s; expected more often than logged: %s%s)"
       % (len(action_messages), len(expected_lines), dict(logged_counts - expected_counts),
          dict(expected_counts - logged_counts),
          "; the same lines in another order" if logged_counts == expected_counts and action_messages != expected_lines
          else ""))

# The clock's wiring: main.qml's block between "BEGIN layout state" and "END layout state" runs
# unchanged in a fixture, as the launcher's opening test runs main.qml's blocks, but for the two
# outside objects it names, the widget's configuration (Plasmoid.configuration) and its window's
# screen (Screen.name). The clock asks for its screen's output and saves each request before the
# wake, as desktop scripting reads the saved configuration; the answer comes through the
# configuration's layoutResponse; a hidden control leaves the layout state idle and withdraws the
# saved request.
WIRED = hashlib.md5(b"wired").hexdigest()
UNANSWERED = "clockpill: no layout answer was taken in time"
check(bus.registerService(PREFIX + WIRED) and bus.interface().serviceOwner("org.kde.KWin").value() == owner,
      "the clock's wiring: KWin's name and a new lifetime's identity name are held here")
source = (Path(__file__).resolve().parent.parent / "contents/ui/main.qml").read_text()
BEGIN, END = "    // BEGIN layout state\n", "    // END layout state\n"
block = source.split(BEGIN, 1)[1].split(END, 1)[0] if BEGIN in source and END in source else ""
expect(block != "" and "Plasmoid.configuration" in block and "Screen.name" in block,
       "the clock's wiring: main.qml marks its layout state block, which uses the configuration and the screen")
# runDebugAction lies outside the block: its branch for the hook is checked as text.
expect('parts[0] === "dump-layout"' in source and 'root.dumpLayout(parts.slice(1).join(":"))' in source,
       "the clock's wiring: runDebugAction hands dump-layout:TAG to dumpLayout")
# So do the pill's control and the budget's saving, which a real session checks in the bar; the
# block's parts they use are checked below.
expect("return saving + layoutSaving(level);" in source,
       "the clock's wiring: the pill's budgetSaving adds the layout control's saving")
expect("                mode: layoutState.mode\n                level: root.layoutLevel\n" in source,
       "the clock's wiring: the pill's layout control takes the state's mode and the budget's level")
expect('parts[0] === "dump-pill"' in source and 'root.dumpPill(parts.slice(1).join(":"))' in source,
       "the clock's wiring: runDebugAction hands dump-pill:TAG to dumpPill")
# The configuration's start values are literals, as the real configuration's are already there when
# the clock is created: a binding to them would change as the fixture completes.
FIXTURE = ("import QtQuick\nItem {\n    id: root\n    property string screenName: \"Virtual-0\"\n"
           "    property bool inPanel: INPANEL\n    property bool vertical: VERTICAL\n"
           "    property QtObject tabletState: QtObject {\n        property bool tablet: TABLET\n    }\n"
           "    property int budgetLevel: 0\n    property real pillPadding: 12\n"
           "    property var announcements: []\n"
           "    function announceLayout(text) { root.announcements = root.announcements.concat([text]); }\n"
           "    property QtObject layoutControl: QtObject {\n        property bool available: true\n"
           "        property bool visible: true\n        property var notices: []\n"
           "        property real fullWidth: 80\n        property real compactWidth: 13\n"
           "        function notify(reason, mode) { root.layoutControl.notices = root.layoutControl.notices.concat([[reason, mode]]); }\n"
           "        function outcomeText(reason, mode, inMenu) { return reason + \"|\" + mode + \"|\" + inMenu; }\n    }\n"
           "    signal saved(string request)\n    property var saves: []\n    property QtObject config: QtObject {\n"
           "        property bool showLayoutControl: SHOWN\n        property string layoutRequest: REQUEST\n"
           "        property string layoutResponse: \"\"\n        function writeConfig(): void {\n"
           "            root.saves = root.saves.concat([layoutRequest]);\n            root.saved(layoutRequest);\n"
           "        }\n    }\n"
           + block.replace("Plasmoid.configuration", "root.config").replace("Screen.name", "root.screenName")
           + "    readonly property QtObject layout: layoutState\n}\n")
wiring_components = []


def parsed_json(text):
    try:
        return json.loads(text)
    except (TypeError, ValueError):
        return {}


def wired(shown=True, request="", tablet=False, vertical=False, in_panel=True):
    """A fixture whose configuration and bar start with these values, and what it saves, recorded
    beside the wakes (saves made as it completes are in its saves property)."""
    component = QQmlComponent(engine)
    wiring_components.append(component)
    literal = {True: "true", False: "false"}
    text = (FIXTURE.replace("SHOWN", literal[shown]).replace("REQUEST", json.dumps(request))
            .replace("TABLET", literal[tablet]).replace("VERTICAL", literal[vertical]).replace("INPANEL", literal[in_panel]))
    # A URL in the package's contents/ui, so that LayoutState resolves as it does for main.qml;
    # nothing is written there.
    component.setData(text.encode(),
                      QUrl.fromLocalFile(str(Path(__file__).resolve().parent.parent / "contents/ui/LayoutWiringFixture.qml")))
    item = component.create() if block else None
    if item is None:
        print("the clock's wiring: the fixture did not load: " + "; ".join(e.toString() for e in component.errors()))
    found = []
    if item is not None:
        item.saved.connect(lambda text: (found.append(text), events.append(("saved", text))))
    return item, found


messages = []
qInstallMessageHandler(lambda mode, context, message: messages.append(message))
events.clear()
wiring, saved = wired()
expect(wiring is not None, "the clock's wiring: the block runs with the configuration and the screen supplied")
if wiring is not None:
    config, layout = wiring.property("config"), wiring.property("layout")
    until(lambda: len(events) == 2)
    request = parsed_json(saved[0]) if saved else {}
    expect([kind for kind, _ in events] == ["saved", "wake"] and events[1][1] == WAKE
           and request.get("intent") == "query" and request.get("outputName") == "Virtual-0"
           and prop(config, "layoutRequest") == saved[0],
           "the clock's wiring: the clock asks for its screen's output and saves the request before the wake (%s)" % events)
    answer = {"version": 1, "consumer": request.get("consumer"), "request": request.get("request"), "epoch": WIRED,
              "identityName": PREFIX + WIRED, "backendOwner": owner, "revision": 1, "status": "online",
              "capable": True, "tiled": True, "view": dict(VIEW, outputName="Virtual-0")}
    config.setProperty("layoutResponse", json.dumps(answer))
    expect(until(lambda: prop(layout, "mode") == "tiled") and prop(layout, "epoch") == WIRED,
           "the clock's wiring: the provider's answer in the configuration reaches the layout state")
    QMetaObject.invokeMethod(wiring, "dumpLayout", Q_ARG(str, "wired"))
    lines = [m.split("clockpill: layout dump wired ", 1)[1] for m in messages if "clockpill: layout dump wired " in m]
    dumped = parsed_json(lines[0]) if lines else {}
    expect(dumped == {"output": "Virtual-0", "outcome": "answered", "mode": "tiled", "epoch": WIRED, "revision": 1, "refusal": "",
                      "state": "idle", "choice": "", "pending": False, "reason": "", "available": True},
           "the clock's wiring: the testing hook dump-layout says the layout state and the action's fields (%s)" % lines)
    events.clear()
    saved.clear()
    config.setProperty("showLayoutControl", False)
    expect(until(lambda: prop(layout, "outcome") == "idle") and prop(layout, "mode") == "unknown"
           and until(lambda: len(events) == 2) and not until(lambda: len(events) > 2, ms=300)
           and [kind for kind, _ in events] == ["saved", "wake"] and events[1][1] == WAKE and saved == [""]
           and prop(config, "layoutRequest") == "",
           "the clock's wiring: a hidden control leaves the layout state idle and withdraws the saved request, with one"
           " save and then a wake, so the provider forgets it at once (%s)" % events)
    events.clear()
    saved.clear()
    config.setProperty("showLayoutControl", True)
    until(lambda: len(events) == 2)
    again = parsed_json(saved[0]) if saved else {}
    expect([kind for kind, _ in events] == ["saved", "wake"] and again.get("request", 0) > request.get("request", 0)
           and again.get("outputName") == "Virtual-0" and prop(layout, "outcome") == "pending",
           "the clock's wiring: shown again, the clock asks again (%s)" % events)
    events.clear()
    saved.clear()
    wiring.setProperty("screenName", "Virtual-1")
    until(lambda: len(events) == 2)
    expect([kind for kind, _ in events] == ["saved", "wake"] and saved and parsed_json(saved[0]).get("outputName") == "Virtual-1",
           "the clock's wiring: on another screen the clock asks for that output (%s)" % events)
    layout.setProperty("deadlineMs", 300)
    wiring.setProperty("screenName", "Virtual-2")
    unanswered = until(lambda: prop(layout, "outcome") == "unconfirmed", ms=1500)
    QTest.qWait(100)
    said = [m for m in messages if UNANSWERED in m]
    expect(unanswered and len(said) == 1 and prop(layout, "mode") == "unknown",
           "the clock's wiring: of all its outcomes, only a request with no answer taken by its deadline is said, once (%s)"
           % said)
    wiring.deleteLater()
# Started hidden: a request saved earlier is withdrawn with one save, as the fixture completes (its
# saves property records it, before any connection could), and the provider woken once; an empty
# field is left as it is, with no save and no wake. Neither asks.
EARLIER = '{"version":1,"intent":"query","consumer":"earlier","request":4,"outputName":"Virtual-0"}'
events.clear()
hidden, _ = wired(shown=False, request=EARLIER)
until(lambda: events)
expect(hidden is not None and not until(lambda: len(events) > 1, ms=300) and events == [("wake", WAKE)]
       and prop(hidden, "saves") == [""] and prop(hidden.property("config"), "layoutRequest") == ""
       and prop(hidden.property("layout"), "outcome") == "idle",
       "the clock's wiring: started hidden, the clock withdraws the request saved earlier, with one save and one wake,"
       " and asks nothing (%s, %s)" % (prop(hidden, "saves") if hidden is not None else None, events))
events.clear()
bare, _ = wired(shown=False)
expect(bare is not None and not until(lambda: events, ms=300) and prop(bare, "saves") == [],
       "the clock's wiring: started hidden with no request saved, the clock saves nothing (%s)" % events)
# Started shown with a request saved earlier, as after a restart: nothing is withdrawn, and the
# clock's own request is its one save.
events.clear()
shown, _ = wired(request=EARLIER)
until(lambda: len(events) == 2)
first_saves = prop(shown, "saves") if shown is not None else None
expect(shown is not None and [kind for kind, _ in events] == ["saved", "wake"] and len(first_saves) == 1
       and parsed_json(first_saves[0]).get("consumer") not in (None, "earlier"),
       "the clock's wiring: started shown with a request saved earlier, the clock withdraws nothing and saves its own"
       " request once (%s)" % first_saves)
# Hidden through the settings dialog: Apply copies the page's values back in main.xml's order, the
# visibility before the request, whose copy the page refreshed to the saved one, and then saves
# (AppletConfiguration.qml's saveConfig()). The withdrawal must come after that write, not inside it.
events.clear()
applied, _ = wired()
until(lambda: len(events) == 2)
applied_config = applied.property("config") if applied is not None else None
if applied_config is not None:
    copy = prop(applied_config, "layoutRequest")
    applied_config.setProperty("showLayoutControl", False)
    applied_config.setProperty("layoutRequest", copy)
    QMetaObject.invokeMethod(applied_config, "writeConfig")
    until(lambda: prop(applied_config, "layoutRequest") == "", ms=500)
    QTest.qWait(50)
applied_saves = prop(applied, "saves") if applied is not None else None
expect(applied_config is not None and prop(applied_config, "layoutRequest") == "" and applied_saves and applied_saves[-1] == "",
       "the clock's wiring: hidden through the settings dialog's Apply, which writes the request back after the"
       " setting, the request is still withdrawn (%s)" % applied_saves)
# The bar's own layout shows the control only in a horizontal panel outside tablet posture. Started in
# tablet posture, on a vertical panel or outside a panel, the clock asks nothing and withdraws a
# request saved earlier, with one save and one wake.
gated = []
for name, options in (("in tablet posture", {"tablet": True}), ("on a vertical panel", {"vertical": True}),
                      ("outside a panel", {"in_panel": False})):
    events.clear()
    item, _ = wired(request=EARLIER, **options)
    gated.append(item)
    until(lambda: events)
    expect(item is not None and not until(lambda: len(events) > 1, ms=300) and events == [("wake", WAKE)]
           and prop(item, "saves") == [""] and prop(item.property("layout"), "outcome") == "idle",
           "the clock's wiring: started %s, the clock asks nothing and withdraws the request saved earlier, with one save"
           " and one wake (%s, %s)" % (name, prop(item, "saves") if item is not None else None, events))
# Shown, then tablet posture comes: the state goes idle and the request is withdrawn, then the
# provider woken; tablet posture ends and the clock asks again.
events.clear()
posture, posture_saved = wired()
until(lambda: len(events) == 2)
posture_layout = posture.property("layout") if posture is not None else None
first = parsed_json(posture_saved[0]) if posture_saved else {}
events.clear()
posture_saved.clear()
if posture is not None:
    posture.property("tabletState").setProperty("tablet", True)
expect(posture is not None and until(lambda: prop(posture_layout, "outcome") == "idle") and until(lambda: len(events) == 2)
       and not until(lambda: len(events) > 2, ms=300) and [kind for kind, _ in events] == ["saved", "wake"]
       and posture_saved == [""],
       "the clock's wiring: tablet posture coming, the clock goes idle and withdraws its request, then wakes the provider"
       " (%s)" % events)
events.clear()
posture_saved.clear()
if posture is not None:
    posture.property("tabletState").setProperty("tablet", False)
until(lambda: len(events) == 2)
back = parsed_json(posture_saved[0]) if posture_saved else {}
expect([kind for kind, _ in events] == ["saved", "wake"] and back.get("request", 0) > first.get("request", 0)
       and prop(posture_layout, "outcome") == "pending",
       "the clock's wiring: tablet posture over, the clock asks again (%s)" % events)
# Shown, then the bar's output name empty (Screen.name, the control still wanted):
# the state goes idle and the request is withdrawn, then the provider woken, as when the control is
# hidden; the screen back, the clock asks again.
events.clear()
screenless, screenless_saved = wired()
until(lambda: len(events) == 2)
screenless_layout = screenless.property("layout") if screenless is not None else None
events.clear()
screenless_saved.clear()
if screenless is not None:
    screenless.setProperty("screenName", "")
expect(screenless is not None and until(lambda: prop(screenless_layout, "outcome") == "idle")
       and until(lambda: len(events) == 2) and not until(lambda: len(events) > 2, ms=300)
       and [kind for kind, _ in events] == ["saved", "wake"] and screenless_saved == [""]
       and prop(screenless.property("config"), "layoutRequest") == "",
       "the clock's wiring: with no screen the clock goes idle and withdraws its request, then wakes the provider"
       " (%s)" % events)
events.clear()
screenless_saved.clear()
if screenless is not None:
    screenless.setProperty("screenName", "Virtual-0")
until(lambda: len(events) == 2)
expect([kind for kind, _ in events] == ["saved", "wake"] and screenless_saved
       and parsed_json(screenless_saved[0]).get("outputName") == "Virtual-0",
       "the clock's wiring: the screen back, the clock asks again (%s)" % events)


def wired_frame(wiring, revision, **fields):
    """A frame answering the wiring fixture's last saved request, from the wired lifetime."""
    request = parsed_json(prop(wiring.property("config"), "layoutRequest"))
    result = {"version": 1, "consumer": request.get("consumer"), "request": request.get("request"),
              "epoch": WIRED, "identityName": PREFIX + WIRED, "backendOwner": owner, "revision": revision,
              "status": "online", "capable": True, "view": dict(VIEW, outputName="Virtual-0"), "tiled": False}
    result.update(fields)
    return result


# The layout menu's wiring (P6, slice 3): the control asks for the menu, the block opens the action
# and keeps the way it was opened; the pop-up's visibility follows the action and the control; the
# pop-up's own hide ends the action at once, with the sync keeping the press-then-click toggle; the
# control hiding ends it at once (S11); Escape after a choice, then the pop-up hiding, then a
# stale-context refusal stays silent (B3); a presented reason is announced once, worded for the
# menu while it is open, and an empty one is not announced.
events.clear()
menu, _ = wired()
until(lambda: len(events) == 2)
menu_layout = menu.property("layout") if menu is not None else None
menu_control = menu.property("layoutControl") if menu is not None else None
menu_config = menu.property("config") if menu is not None else None
if menu is not None:
    menu_config.setProperty("layoutResponse", json.dumps(wired_frame(menu, 1, tiled=True)))
    until(lambda: prop(menu_layout, "mode") == "tiled")
    invoke(menu, "openLayoutMenu", Q_ARG(str, "keys"))
expect(menu is not None and prop(menu, "layoutMenuBy") == "keys" and prop(menu, "layoutMenuShown") is True
       and prop(menu_layout, "actionOpen") is True,
       "the clock's wiring: the control's request opens the action and keeps the way it was opened")
if menu is not None:
    invoke(menu, "layoutMenuHidden")
expect(menu is not None and prop(menu_layout, "actionOpen") is False and prop(menu, "layoutMenuRecent") is True,
       "the clock's wiring: the pop-up hiding itself ends the action at once, and the sync keeps the toggle")
QTest.qWait(200)
expect(menu is not None and prop(menu, "layoutMenuRecent") is False,
       "the clock's wiring: the sync over, the toggle is free again")
if menu is not None:
    invoke(menu, "openLayoutMenu", Q_ARG(str, "pointer"))
    invoke(menu_layout, "close", Q_ARG(bool, True))
expect(menu is not None and prop(menu_layout, "actionOpen") is False,
       "the clock's wiring: Escape closes the action")
if menu is not None:
    invoke(menu, "openLayoutMenu", Q_ARG(str, "keys"))
    menu_control.setProperty("visible", False)
expect(menu is not None and prop(menu_layout, "actionOpen") is False,
       "the clock's wiring: the control hiding ends the action at once (S11)")
if menu is not None:
    menu_control.setProperty("visible", True)
    invoke(menu, "openLayoutMenu", Q_ARG(str, "keys"))
    invoke(menu_layout, "input")
    menu_config.setProperty("layoutResponse", json.dumps(wired_frame(
        menu, 2, completion={"intent": "prepare", "result": "done", "handle": WIRED + ":1:1", "target": True},
        prepared={"handle": WIRED + ":1:1", "ready": True})))
    until(lambda: prop(menu_layout, "actionState") == "prepared")
    invoke(menu_layout, "choose", Q_ARG(str, "tiled"))
    invoke(menu_layout, "close", Q_ARG(bool, True))
    invoke(menu, "layoutMenuHidden")
    menu_config.setProperty("layoutResponse", json.dumps(wired_frame(
        menu, 3, completion={"intent": "set", "result": "refused", "reason": "stale-context"})))
    QTest.qWait(50)
expect(menu is not None and prop(menu_layout, "actionReason") == "" and prop(menu, "announcements") == [],
       "the clock's wiring: Escape after a choice, then the pop-up hiding, then a stale-context refusal, stays silent (B3)")
if menu is not None:
    invoke(menu, "openLayoutMenu", Q_ARG(str, "keys"))
    invoke(menu_layout, "input")
    QTest.qWait(20)
    menu_config.setProperty("layoutResponse", json.dumps(wired_frame(
        menu, 4, completion={"intent": "prepare", "result": "refused", "reason": "busy"})))
    QTest.qWait(50)
expect(menu is not None and prop(menu, "announcements") == ["busy||true"],
       "the clock's wiring: a presented reason is announced once, worded for the menu while it is open")
expect('visible: root.layoutMenuShown && layoutMenuLoader.status === Loader.Ready' in source
       and 'root.layoutMenuHidden()' in source,
       "the clock's wiring: the menu's pop-up shows while the action is open and the control shows, and its hide ends the action")
expect('interactive: layoutState.actionsAvailable' in source
       and 'menuOpen: root.layoutMenuRecent' in source
       and 'pending: layoutState.actionPending && !layoutState.actionOpen' in source,
       "the clock's wiring: the control is interactive only while the actions are available, and takes the action's state")
expect('onActiveChanged: {\n            if (active) {\n                const menu = layoutMenuLoader.item;' in source
       and 'menu.focusConfirmed(root.layoutMenuBy !== "pointer")' in source,
       "the clock's wiring: the pop-up's activation applies the focus reason again, so a keyboard opening keeps its ring (D12)")
expect('status: layoutControl.outcomeText(layoutState.actionReason, layoutState.actionChoice, true)' in source
       and 'onInputReported: layoutState.input()' in source
       and 'onChosen: mode => layoutState.choose(mode)' in source
       and 'onCloseRequested: layoutState.close(true)' in source,
       "the clock's wiring: the menu binds to the action and forwards its input, choice and Escape")
expect('parts[0] === "dump-layout-menu"' in source and 'root.dumpLayoutMenu(parts.slice(1).join(":"))' in source,
       "the clock's wiring: runDebugAction hands dump-layout-menu:TAG to dumpLayoutMenu")
# The control's place in the width budget: its label goes at step 4, with the short date, and the
# control at step 7, with the dots, giving up its width and one pill padding; a control that shows
# no mode gives up nothing.
budget = posture


def layout_saving(item, step):
    """main.qml's layoutSaving(step), or None where the fixture has none."""
    try:
        return QMetaObject.invokeMethod(item, "layoutSaving", Qt.DirectConnection, Q_RETURN_ARG(float), Q_ARG(int, step))
    except RuntimeError:
        return None


levels, savings = [], []
events.clear()
for step in range(8):
    if budget is not None:
        budget.setProperty("budgetLevel", step)
    levels.append(prop(budget, "layoutLevel"))
    savings.append(layout_saving(budget, step) if budget is not None else None)
# Hidden by the budget at step 7, the control keeps its state asking: idling it would free the room
# the budget counts, and the budget would step back and show it again, in a loop.
expect(budget is not None and not until(lambda: events, ms=300) and prop(budget.property("layout"), "outcome") != "idle"
       and prop(budget.property("config"), "layoutRequest") != "",
       "the clock's wiring: at step 7, where the budget hides the control, the state keeps its request, with no save"
       " and no wake (%s)" % events)
expect(levels == [0, 0, 0, 0, 1, 1, 1, 2],
       "the clock's wiring: the control shows its label to step 3, its glyph alone from step 4 and nothing from step 7"
       " (%s)" % levels)
expect(savings == [0, 0, 0, 0, 67, 67, 67, 92],
       "the clock's wiring: the control gives up its label's room from step 4 and its width and one pill padding from"
       " step 7 (%s)" % savings)
if budget is not None:
    budget.property("layoutControl").setProperty("available", False)
none_saved = [layout_saving(budget, step) for step in range(8)] if budget is not None else None
expect(none_saved == [0] * 8, "the clock's wiring: a control that shows no mode gives up nothing (%s)" % none_saved)
# The pill's short date at the width budget's step 4: main.qml's shortDateText binding, as main.qml
# has it, in a fixture beside it, for each region on 21 November 2026. The year goes with the
# separator that joined it to the day or the month ("11/21", not "11/21/" or "/11/21"); a dot
# right after a number stays where the region writes one (de_DE "21.11.", ko_KR "11. 21.").
binding = re.search(r"\n    readonly property string shortDateText: (.*?)\n    (?=\S)", source, re.S)
expect(binding is not None and "clock.dateTime" in binding.group(1) and "Qt.locale()" in binding.group(1),
       "the clock's wiring: main.qml's short date is one binding on the clock's time and the region")
SHORT_DATES = {"en_US": "M/d", "en_GB": "dd/MM", "fr_FR": "dd/MM", "es_ES": "d/M", "ja_JP": "MM/dd",
               "ar_EG": "d\u200f/M", "de_DE": "dd.MM.", "ko_KR": "M. d."}
for region, wanted in SHORT_DATES.items():
    got = None
    if binding is not None:
        expression = (binding.group(1).replace("Qt.locale()", "Qt.locale(%s)" % json.dumps(region))
                      .replace("clock.dateTime", "new Date(2026, 10, 21)"))
        date_component = QQmlComponent(engine)
        wiring_components.append(date_component)
        date_component.setData(('import QtQuick\nimport "../code/formats.js" as Formats\nQtObject {\n'
                                "    readonly property string text: %s\n}\n" % expression).encode(),
                               QUrl.fromLocalFile(str(Path(__file__).resolve().parent.parent / "contents/ui/ShortDateFixture.qml")))
        date_fixture = date_component.create()
        if date_fixture is None:
            print("the clock's wiring: the short date fixture did not load: "
                  + "; ".join(e.toString() for e in date_component.errors()))
        got = date_fixture.property("text") if date_fixture is not None else None
    expected = QLocale(region).toString(QDate(2026, 11, 21), wanted)
    expect(got == expected, "the clock's wiring: at step 4 the date in %s reads %r (%r)" % (region, expected, got))
others = [m for m in messages if "clockpill: layout dump " not in m and UNANSWERED not in m]
expect(not others, "the clock's wiring: the fixtures say nothing else (%s)" % others)
qInstallMessageHandler(None)
for item in (hidden, bare, shown, applied, posture, screenless, *gated):
    if item is not None:
        item.deleteLater()
QTest.qWait(50)
print(f"Layout state and calendar adapter: {checks} checks, {len(failures)} failures")
if failures:
    raise SystemExit("layout state: " + "; ".join(failures))
