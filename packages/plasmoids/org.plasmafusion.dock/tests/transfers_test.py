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
another app, and none once the jobs end. On a dock tile (TaskItem.qml, staged with the shared blocks
as the build does) the progress ring shows next to an unread count, as in the stock task manager.
"""

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

here = Path(__file__).resolve().parent
package = here.parent
root = package.parents[2]

home = Path(tempfile.mkdtemp(prefix="pf-dock-transfers-"))
for key, sub in (("XDG_DATA_HOME", ".local/share"), ("XDG_CONFIG_HOME", ".config"), ("XDG_CACHE_HOME", ".cache")):
    os.environ[key] = str(home / sub)
    (home / sub).mkdir(parents=True)
os.environ["HOME"] = str(home)
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

# The stage of the package: contents plus the shared blocks, as tools/build.d/73-dock.sh does.
stage = home / "stage"
shutil.copytree(package / "contents", stage / "contents")
subprocess.run(["bash", str(root / "tools/build-lib/shared-qml.sh"), "install", str(package), str(stage / "contents/ui")],
               check=True, timeout=120, env=dict(os.environ, ROOT=str(root)))
ui = stage / "contents/ui"

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
import "../code/jobs.js" as Jobs
Item {
    width: 200
    height: 120
    TransferJobs {
        id: transfers
    }
    function progress() { return JSON.stringify(transfers.progress); }

    // A Dolphin tile as the dock builds it (main.qml: dockEntries = Jobs.withJobs(...)), with
    // `unread` notifications not seen yet.
    property int unread: 0
    DockPalette {
        id: palette
        dark: true
    }
    Motion {
        id: motion
    }
    TaskItem {
        id: tile
        y: 20
        height: 90
        index: 0
        model: ({ AppId: "org.kde.dolphin", AppName: "Dolphin", decoration: "system-file-manager", IsLauncher: false,
                  IsStartup: false, IsActive: false, IsDemandingAttention: false })
        pal: palette
        motion: motion
        entry: Jobs.withJobs({}, transfers.progress)["org.kde.dolphin"] ?? null
        notificationCount: unread
    }
    // The dock's tablet tile at its boundary (main.qml: minTaskTile is 44 in tablet posture when
    // the dock is crowded, with the tablet bottom padding): its icon and interactive surface must
    // reach the touch minimum there, so a regression below 44 fails tightly.
    TaskItem {
        id: tabletTile
        x: 400
        width: 44
        height: 90
        tablet: true
        iconSize: 44
        bottomPad: 12
        index: 1
        model: ({ AppId: "org.kde.dolphin", AppName: "Dolphin", decoration: "system-file-manager", IsLauncher: false,
                  IsStartup: false, IsActive: false, IsDemandingAttention: false })
        pal: palette
        motion: motion
        entry: null
        notificationCount: 0
    }
    // The tile's mouse area (its interactive surface), found by the property only it declares.
    function touchTarget(item) {
        for (const child of item.children) {
            if (child.pressPoint !== undefined) {
                return child;
            }
            const found = touchTarget(child);
            if (found) {
                return found;
            }
        }
        return null;
    }
    function tabletTarget() {
        const a = touchTarget(tabletTile);
        return a ? JSON.stringify([Math.round(a.width), Math.round(a.height),
                                   Math.round(tabletTile.iconItem.width)]) : "null";
    }
    function find(item, name) {
        if (item.objectName === name) {
            return item;
        }
        for (const child of item.children) {
            const found = find(child, name);
            if (found) {
                return found;
            }
        }
        return null;
    }
    function tileState() {
        const ring = find(tile, "progressRing");
        const badge = find(tile, "countBadge");
        const r = ring.mapToItem(tile.iconItem, 0, 0);
        const b = badge.mapToItem(tile.iconItem, 0, 0);
        return JSON.stringify({ ring: ring.visible, badge: badge.visible, progress: tile.progress,
                                ringBox: [r.x, r.y, ring.width, ring.height], badgeBox: [b.x, b.y, badge.width, badge.height],
                                icon: tile.iconItem.width });
    }
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

    def tile():
        return json.loads(QMetaObject.invokeMethod(item, "tileState", Q_RETURN_ARG("QVariant")))

    def overlap(a, b):
        return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]

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
    t = tile()
    check(t["ring"] and not t["badge"] and t["progress"] == 0.6, "the Dolphin tile shows the ring at 60 %% (%s)" % t)
    item.setProperty("unread", 2)
    QTest.qWait(100)
    t = tile()
    check(t["badge"] and t["ring"], "with two unread notifications the tile shows the count and the ring (%s)" % t)
    check(not overlap(t["ringBox"], t["badgeBox"]) and 0 <= t["ringBox"][0] and t["ringBox"][0] + t["ringBox"][2] <= t["icon"]
          and t["ringBox"][1] + t["ringBox"][3] <= t["icon"], "the ring moves inside the icon, clear of the count (%s)" % t)
    item.setProperty("unread", 0)

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
    def tablet_target():
        return json.loads(QMetaObject.invokeMethod(item, "tabletTarget", Q_RETURN_ARG("QVariant")))

    target = tablet_target()
    check(target is not None and min(target) >= 44,
          "the tablet tile's touch target and icon reach 44 px at the boundary (%r)" % (target,))

    print(f"transfers: {checks} checks passed")
finally:
    calls.shutdown(wait=False)
    shutil.rmtree(home, ignore_errors=True)
