#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the real Plasma calendar adapter and the bar's layout state on an offscreen, private
session bus."""

from pathlib import Path
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
DEADLINE = 600
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
           "    property QtObject layoutControl: QtObject {\n        property bool available: true\n"
           "        property real fullWidth: 80\n        property real compactWidth: 13\n    }\n"
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
    expect(dumped == {"output": "Virtual-0", "outcome": "answered", "mode": "tiled", "epoch": WIRED, "revision": 1, "refusal": ""},
           "the clock's wiring: the testing hook dump-layout says the layout state (%s)" % lines)
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
