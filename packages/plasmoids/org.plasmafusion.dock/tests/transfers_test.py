#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The dock's file-transfer progress (contents/ui/TransferJobs.qml) on Plasma's real job server.

QT_QPA_PLATFORM=offscreen dbus-run-session --config-file=packages/kwin/tests/offscreen/session-bus.conf \
    -- python3 packages/plasmoids/org.plasmafusion.dock/tests/transfers_test.py
Requires PySide6, python3-dbus and Plasma's notificationmanager QML module (plasma-workspace).

TransferJobs.qml's notification model starts libnotificationmanager's job server on the private bus,
the one KIO reports file copies to. Jobs are started on it the way KIO's job tracker does
(org.kde.JobViewServerV2.requestView with the app's desktop entry, then JobViewV3 updates), and the
progress per app must follow: one copy, a second one of the same app (their mean), a suspended job,
another app, and none once the jobs end.
"""

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

here = Path(__file__).resolve().parent
ui = here.parent / "contents/ui"

home = Path(tempfile.mkdtemp(prefix="pf-dock-transfers-"))
for key, sub in (("XDG_DATA_HOME", ".local/share"), ("XDG_CONFIG_HOME", ".config"), ("XDG_CACHE_HOME", ".cache")):
    os.environ[key] = str(home / sub)
    (home / sub).mkdir(parents=True)
os.environ["HOME"] = str(home)
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import dbus  # noqa: E402
from PySide6.QtCore import Q_RETURN_ARG, QMetaObject, QUrl  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlComponent, QQmlEngine  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


def wait_for(predicate, message, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        QTest.qWait(50)
        if predicate():
            return
    raise AssertionError(message)


def pumped(fn, *args):
    """Run a blocking D-Bus call in a thread while Qt runs: the job server answering it lives in
    this process (in the notification model the harness loads)."""
    future = calls.submit(fn, *args)
    while not future.done():
        QTest.qWait(10)
    return future.result()


calls = ThreadPoolExecutor(max_workers=1)
HARNESS = b"""
import QtQuick
Item {
    TransferJobs {
        id: transfers
    }
    function progress() { return JSON.stringify(transfers.progress); }
}
"""

app = QGuiApplication(sys.argv[:1])
bus = dbus.SessionBus()
if bus.name_has_owner("org.kde.plasmashell"):
    raise SystemExit("Run on a fresh private bus; refusing a live desktop bus")
try:
    engine = QQmlEngine()
    component = QQmlComponent(engine)
    # The harness sits next to TransferJobs.qml, so the type resolves from the folder as in the dock.
    component.setData(HARNESS, QUrl.fromLocalFile(str(ui / "TransfersHarness.qml")))
    item = component.create()
    if item is None:
        raise AssertionError("harness did not load: " + "; ".join(e.toString() for e in component.errors()))

    def progress():
        return json.loads(QMetaObject.invokeMethod(item, "progress", Q_RETURN_ARG("QVariant")))

    wait_for(lambda: bus.name_has_owner("org.kde.JobViewServer"), "the job server did not start")
    server = dbus.Interface(pumped(bus.get_object, "org.kde.JobViewServer", "/JobViewServer"), "org.kde.JobViewServerV2")

    def start(desktop_entry):
        path = pumped(server.requestView, desktop_entry, dbus.Int32(0), dbus.Dictionary({}, signature="sv"))
        return dbus.Interface(pumped(bus.get_object, "org.kde.JobViewServer", path), "org.kde.JobViewV3")

    def update(view, **props):
        pumped(view.update, dbus.Dictionary(props, signature="sv"))

    check(progress() == {}, "no jobs: no progress")
    copy = start("org.kde.dolphin")
    update(copy, percent=dbus.UInt32(37), infoMessage="Copying")
    wait_for(lambda: progress().get("org.kde.dolphin", {}).get("progress") == 0.37, "Dolphin's copy did not show 37 %")
    check(progress() == {"org.kde.dolphin": {"count": 1, "progress": 0.37}}, "a Dolphin copy at 37 % shows on Dolphin")
    update(copy, percent=dbus.UInt32(60))
    wait_for(lambda: progress().get("org.kde.dolphin", {}).get("progress") == 0.6, "the progress did not follow")
    check(True, "the progress follows the copy (60 %)")

    second = start("org.kde.dolphin")
    update(second, percent=dbus.UInt32(21))
    wait_for(lambda: progress().get("org.kde.dolphin", {}).get("count") == 2, "the second job did not count")
    check(progress()["org.kde.dolphin"]["progress"] == 0.4, "two Dolphin jobs: their mean (60 and 21: 40 %)")
    update(second, suspended=True)
    QTest.qWait(400)
    check(progress()["org.kde.dolphin"]["count"] == 2, "a paused job still counts")

    other = start("org.kde.ark")
    update(other, percent=dbus.UInt32(5))
    wait_for(lambda: "org.kde.ark" in progress(), "another app's job did not show")
    check(progress()["org.kde.ark"] == {"count": 1, "progress": 0.05}, "another app's job shows on that app only")

    for view in (copy, second, other):
        pumped(view.terminate, dbus.UInt32(0), "", dbus.Dictionary({}, signature="sv"))
    wait_for(lambda: progress() == {}, "finished jobs still show progress")
    check(True, "finished jobs show no progress")
    print(f"transfers: {checks} checks passed")
finally:
    calls.shutdown(wait=False)
    shutil.rmtree(home, ignore_errors=True)
