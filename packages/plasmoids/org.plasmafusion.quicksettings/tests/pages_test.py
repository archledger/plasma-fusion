#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Drive quick settings' drill-down pages in the staged real QML, with a stand-in backend.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 pages_test.py STAGE_HOME
(STAGE_HOME: the build's stage, `STAGE=... tools/build.sh quicksettings`; the pages need the shared
blocks the build copies into contents/ui/components.)
"""

import os
from pathlib import Path
import sys
import tempfile

# The backend loads Plasma's clipboard module, whose Klipper code asks the offscreen platform for
# X11 and crashes on the missing connection (clipboard_sheet_test.py does the same).
os.environ["QT_QPA_OFFSCREEN_NO_GLX"] = "1"
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PySide6.QtCore import QObject, QPoint, QPointF, Qt, QUrl, Slot  # noqa: E402
from PySide6.QtGui import QFont, QGuiApplication  # noqa: E402
from PySide6.QtQuick import QQuickItem, QQuickView  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402


class Context(QObject):
    @Slot(str, result=str)
    def i18n(self, text):
        return text

    @Slot(str, str, result=str)
    def i18nc(self, context, text):
        return text



UI = Path(sys.argv[1]).resolve() / ".local/share/plasma/plasmoids/org.plasmafusion.quicksettings/contents/ui"
if not (UI / "components/FusionMetrics.qml").exists():
    raise SystemExit("Build the quick settings package into the stage first: " + str(UI))

# The profiles the stand-in daemon offers, the active one and the inhibition, as Backend.profile
# shows them (the row logic itself is contents/code/power.js, tests/power.test.js).
PROFILES = """
import QtQuick
import "%(ui)s"
import "%(ui)s/components"
import "%(ui)s/../code/power.js" as Power

Item {
    id: root
    width: 356
    height: 560
    // What the page asked the backend for, "; "-separated.
    property string calls: ""
    property var list: ["performance", "balanced", "power-saver"]
    property string active: "balanced"
    property string reason: "lap-detected"
    property bool touch: false
    FusionPalette { id: pal; touch: root.touch }
    FusionMetrics { id: metrics }
    QtObject {
        id: backend
        property QtObject profile: QtObject {
            readonly property var list: root.list
            readonly property string active: root.active
            readonly property string inhibitionReason: root.reason
            property string failedProfile: ""
            readonly property var options: Power.options(list, active, inhibitionReason)
            readonly property string inhibitionNote: inhibitionReason ? "Performance mode has been disabled" : ""
            readonly property string note: [inhibitionNote, "Steam has requested Power saver"].filter(t => t !== "").join("\\n")
            function profileName(p: string): string { return p; }
            function setProfile(p: string) { root.calls += (root.calls ? "; " : "") + "set " + p; }
            function openSettings() { root.calls += (root.calls ? "; " : "") + "settings"; }
        }
    }
    ProfilesPage {
        id: page
        objectName: "profilesPage"
        width: root.width
        backend: backend
        pal: pal
        metrics: metrics
    }
}
"""

# Keep awake for a while (F7): the stand-in records the calls; timed or not is set by the test.
KEEPAWAKE = """
import QtQuick
import "%(ui)s"
import "%(ui)s/components"

Item {
    id: root
    width: 356
    height: 640
    property string calls: ""
    property bool active: false
    property bool timed: false
    property bool touch: false
    function log(text: string) { root.calls += (root.calls ? "; " : "") + text; }
    FusionPalette { id: pal; touch: root.touch }
    FusionMetrics { id: metrics }
    QtObject {
        id: backend
        property QtObject keepAwake: QtObject {
            readonly property bool available: true
            readonly property bool active: root.active
            readonly property bool timed: root.timed
            readonly property string untilText: "15:30"
            readonly property string leftText: "1 h 5 min"
            readonly property var inhibitors: []
            function toggle() { root.log("toggle"); }
            function forHours(h: int) { root.log("hours " + h); }
            function untilMinuteOfDay(m: int) { root.log("until " + m); }
            function untilTurnedOff() { root.log("until turned off"); }
            function setAllowed(a: string, r: string, allowed: bool) {}
        }
        property QtObject bt: QtObject {
            readonly property bool available: true
            readonly property bool enabled: true
            readonly property var devicesModel: ListModel {
                ListElement { Device: "WH-1000XM4"; Ubi: "/org/bluez/hci0/dev_1"; Connected: true }
                ListElement { Device: "MX Keys"; Ubi: "/org/bluez/hci0/dev_2"; Connected: false }
            }
            function toggleDevice(device: string, ubi: string, connected: bool) { root.log("toggle " + device); }
            function setEnabled(on: bool) { root.log("enable " + on); }
        }
    }
    BluetoothPage {
        objectName: "bluetoothPage"
        x: 400
        width: root.width
        backend: backend
        pal: pal
        metrics: metrics
    }
    PowerPage {
        width: root.width
        backend: backend
        pal: pal
        metrics: metrics
    }
}
"""

# The other sub-pages with minimal service stand-ins, for the touch sweep: each page's controls
# take their touch floor from TextButton/ListRow, so the sweep fails without those.
SUBPAGES = """
import QtQuick
import "%(ui)s"
import "%(ui)s/components"

Item {
    id: root
    width: 356
    height: 560
    property bool touch: false
    property bool hotspotOn: false
    readonly property real px44: metrics.px(44)
    FusionPalette { id: pal; touch: root.touch }
    FusionMetrics { id: metrics }
    QtObject {
        id: backend
        property QtObject audio: QtObject {
            readonly property var cardModel: ListModel {}
            readonly property var sinkModel: ListModel {
                ListElement { Name: "Built-in audio"; Description: "Built-in audio"; Index: 0 }
            }
            readonly property var sourceModel: ListModel {}
            readonly property var playbackModel: [{
                PulseObject: ({ volume: 0.5, muted: false, deviceIndex: 0 }),
                Client: ({ name: "Test application" }),
                Name: "Test application"
            }]
            readonly property var recordingModel: []
            readonly property real normal: 1
            readonly property int maximum: 100
            function setDefault() {}
            function openSettings() {}
            function toggleStreamMute() {}
            function setStreamVolume() {}
            function routeStream() {}
        }
        property QtObject devices: QtObject {
            readonly property var list: ListModel {
                ListElement { name: "Test device"; udi: "/org/test/1"; icon: ""; openPredicate: "open";
                              mounted: false; mountable: false; optical: false; busy: false;
                              message: ""; messageIsError: false }
            }
            function open() {}
            function mount() {}
            function unmount() {}
            function openSettings() {}
            function refresh() {}
        }
        property QtObject net: QtObject {
            readonly property bool wifiEnabled: true
            readonly property bool wifiHwEnabled: true
            readonly property string wifiDevice: "wlan0"
            readonly property bool airplane: false
            readonly property bool airplaneAvailable: true
            readonly property int vpnCount: 0
            readonly property var vpnModel: ListModel {}
            readonly property bool hotspotActive: root.hotspotOn
            readonly property bool hotspotStarting: false
            readonly property bool hotspotReady: true
            readonly property string hotspotError: ""
            readonly property string hotspotHint: "Share this connection with other devices"
            readonly property string hotspotName: "Fusion"
            readonly property string hotspotPassword: "12345678"
            readonly property var activeModel: ListModel {
                ListElement { Name: "Home"; Ssid: "Home"; ConnectionState: 2; SecurityType: 1;
                              Uuid: "u1"; ConnectionPath: "/c/1"; DevicePath: "/d/1"; SpecificPath: "/s/1";
                              Signal: 80; RxBytes: 1024; TxBytes: 2048; ItemUniqueName: "w0" }
            }
            readonly property var otherModel: ListModel {
                ListElement { Name: "Neighbour"; Ssid: "Neighbour"; ConnectionState: 0; SecurityType: 1;
                              Uuid: ""; ConnectionPath: "/c/2"; DevicePath: "/d/1"; SpecificPath: "/s/2";
                              Signal: 40; RxBytes: 0; TxBytes: 0; ItemUniqueName: "w1" }
            }
            function setWifiEnabled() {}
            function setAirplaneMode() {}
            function activate() {}
            function deactivate() {}
            function addAndActivate() {}
            function configureHotspot() {}
            function toggleHotspot() {}
            function openSettings() {}
            function setStatistics() {}
        }
    }
    AudioPage {
        objectName: "audioPage"
        width: root.width
        backend: backend
        pal: pal
        metrics: metrics
    }
    DevicesPage {
        objectName: "devicesPage"
        x: 400
        width: root.width
        backend: backend
        pal: pal
        metrics: metrics
    }
    WifiPage {
        objectName: "wifiPage"
        x: 800
        width: root.width
        backend: backend
        pal: pal
        metrics: metrics
    }
}
"""

checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


def items(item: QQuickItem):
    yield item
    for child in item.childItems():
        yield from items(child)


def find(root, name):
    return next((i for i in items(root) if i.objectName() == name and i.isVisible()), None)


def click(view, item):
    point = item.mapToScene(QPointF(item.width() / 2, item.height() / 2))
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(round(point.x()), round(point.y())))
    QTest.qWait(50)


# The touch minimum (ADAPTIVE 5.3): every visible enabled control reaches 44 x 44 in touch mode.
CONTROLS = ("QQuickAbstractButton", "QQuickItemDelegate", "QQuickSwitch", "QQuickSlider",
            "QQuickComboBox", "QQuickTextField", "QQuickTextArea", "QQuickTextInput")


def classes(item):
    names, mo = [], item.metaObject()
    while mo is not None:
        names.append(mo.className())
        mo = mo.superClass()
    return names


def touch_assert(root, page, what):
    """Every visible, enabled control under `page` is at least 44 x 44 with the harness's touch
    flag on (the pages' controls take the touch floor from TextButton and ListRow).

    The password field's built-in reveal action is skipped: it is
    PlasmaExtras.ActionTextField's internal (`InlineActionIcon`), which a page cannot size; the
    field itself is the target that reaches 44 (see docs/parts/shell-quicksettings.md)."""
    if page is None:
        check(False, "touch mode: %s not found" % what)
        return
    found = [i for i in items(page)
             if i.isVisible() and i.property("enabled") is not False
             and any(c in CONTROLS for c in classes(i)) and "InlineActionIcon" not in classes(i)]
    small = [(i.objectName() or str(i.property("text") or "")[:24], round(i.width(), 1), round(i.height(), 1))
             for i in found if i.width() + 0.5 < 44 or i.height() + 0.5 < 44]
    check(len(found) >= 3 and not small,
          "touch mode: %s reaches 44 x 44 (%d controls, small: %r)" % (what, len(found), small))


def load(text):
    tmp = tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False)
    tmp.write(text % {"ui": UI.as_uri()})
    tmp.close()
    view = QQuickView()
    view.rootContext().setContextObject(context)
    view.setSource(QUrl.fromLocalFile(tmp.name))
    os.unlink(tmp.name)
    if view.status() == QQuickView.Error:
        raise SystemExit("page failed to load: " + "; ".join(e.toString() for e in view.errors()))
    root = view.rootObject()
    view.resize(round(root.width()), round(root.height()))
    view.show()
    QTest.qWait(100)
    return view, root


app = QGuiApplication(sys.argv[:1])
# Pin the text scale to its minimum (FusionMetrics.ts clamps to 0.85): the touch floors are raw
# 44 px, so the sweeps must hold at the strictest scale, not the container's default.
app.setFont(QFont(app.font().family(), 8))
context = Context()

# ---- Power mode chooser (P7)
view, root = load(PROFILES)
rows = [find(root, "profile-" + p) for p in ("power-saver", "balanced", "performance")]
check(all(rows), "the chooser lists the three profiles the daemon offers")
check(rows[1].property("selected") and rows[1].property("trailingPath") and not rows[0].property("trailingPath"),
      "the active profile is marked")
check(not rows[2].isEnabled() and rows[2].property("status") == "Unavailable",
      "inhibited Performance is listed as unavailable and cannot be chosen")
note = find(root, "profile-note")
check(note is not None and "disabled" in note.property("text") and "Steam has requested" in note.property("text"),
      "the reason and the holders show under the list")
click(view, rows[2])
check(root.property("calls") == "", "a click on inhibited Performance switches nothing")
click(view, rows[0])
check(root.property("calls") == "set power-saver", "a click on Power saver chooses it directly")
root.setProperty("reason", "")
QTest.qWait(50)
rows = [find(root, "profile-" + p) for p in ("power-saver", "balanced", "performance")]
check(rows[2].isEnabled() and find(root, "profile-note").property("text") == "Steam has requested Power saver",
      "without the inhibition Performance can be chosen and only the holder is named")
click(view, rows[2])
check(root.property("calls").endswith("set performance"), "a click on Performance chooses it")
root.setProperty("list", ["balanced", "power-saver"])
QTest.qWait(50)
check(find(root, "profile-performance") is None, "a profile the daemon does not offer is not listed")
# ---- Touch mode: the Profiles page's controls reach 44 x 44 (ADAPTIVE 5.3).
root.setProperty("touch", True)
QTest.qWait(120)
touch_assert(root, find(root, "profilesPage"), "the Profiles page")
root.setProperty("touch", False)
view.close()

# ---- Keep awake for a while (F7)
view, root = load(KEEPAWAKE)
state = find(root, "keepawake-state")
check(all(find(root, "keepawake-" + c) for c in ("1h", "4h", "until", "off")), "the page offers 1 hour, 4 hours, until a time and until turned off")
check(find(root, "keepawake-time") is None, "the time chooser is folded away at first")
click(view, find(root, "keepawake-1h"))
click(view, find(root, "keepawake-4h"))
check(root.property("calls") == "hours 1; hours 4", "1 hour and 4 hours start a timed Keep awake (%s)" % root.property("calls"))
click(view, find(root, "keepawake-off"))
check(root.property("calls").endswith("; toggle"), "until turned off, while off, is the tile's own click: on until turned off")
click(view, find(root, "keepawake-until"))
spin = find(root, "keepawake-time")
check(spin is not None and find(root, "keepawake-start") is not None, "Until… shows the time chooser and Start")
start_value = spin.property("value")
check(start_value % 15 == 0 and spin.property("stepSize") == 15, "the time chooser offers quarter hours (%s)" % start_value)
spin.setProperty("value", 17 * 60 + 30)
click(view, find(root, "keepawake-start"))
check(root.property("calls").endswith("; until 1050"), "Start keeps it awake until the chosen time (%s)" % root.property("calls"))
check(find(root, "keepawake-time") is None, "and folds the chooser away")
root.setProperty("active", True)
root.setProperty("timed", True)
QTest.qWait(50)
check(state.property("text") == "On until %1 (%2 left)" and find(root, "keepawake-off").property("primary") is False,
      "timed: the page says when it ends and how long is left")
click(view, find(root, "keepawake-off"))
check(root.property("calls").endswith("; until turned off"), "until turned off, while timed, keeps it on without the end")
root.setProperty("timed", False)
QTest.qWait(50)
check(state.property("text") == "On until turned off" and find(root, "keepawake-off").property("primary"),
      "untimed: the page says until turned off and marks that choice")
# ---- Touch mode: every control on the Bluetooth page reaches 44 x 44 (ADAPTIVE 5.3).
root.setProperty("touch", True)
QTest.qWait(120)
touch_assert(root, find(root, "bluetoothPage"), "the Bluetooth page")
root.setProperty("touch", False)

# ---- Touch mode: the other sub-pages' controls reach 44 x 44 (ADAPTIVE 5.3).
view, root = load(SUBPAGES)
# The text scale pinned above is what makes the sweeps strict: 44 x 0.85 snaps to 37.
check(root.property("px44") < 40, "the suite runs at the minimum text scale (px(44) = %s)" % root.property("px44"))
root.setProperty("touch", True)
QTest.qWait(150)
touch_assert(root, find(root, "audioPage"), "the Audio page")
# The applications tab and its stream row (the routing combo) exist only when a stream plays.
audio = find(root, "audioPage")
apps = next(i for i in items(audio) if i.property("text") == "Applications")
apps.clicked.emit()
QTest.qWait(120)
touch_assert(root, find(root, "audioPage"), "the Audio page (Applications tab)")
touch_assert(root, find(root, "devicesPage"), "the Devices page")
touch_assert(root, find(root, "wifiPage"), "the Wi-Fi page")
wifi = find(root, "wifiPage")
for row in [i for i in items(wifi) if i.objectName() == "wifi-row"]:
    row.setProperty("expanded", True)
QTest.qWait(80)
field = next(i for i in items(wifi) if "QQuickTextField" in classes(i))
field.setProperty("text", "secret123")
edit = next(i for i in items(wifi) if i.property("text") == "Change name and password…")
edit.clicked.emit()
QTest.qWait(120)
touch_assert(root, find(root, "wifiPage"), "the Wi-Fi page (row expanded, hotspot editing)")
root.setProperty("hotspotOn", True)
QTest.qWait(120)
touch_assert(root, find(root, "wifiPage"), "the Wi-Fi page (hotspot on)")
rows = [i for i in items(wifi) if i.objectName() == "wifi-row"] if wifi else []
check(rows and all(r.height() + 0.5 >= 44 for r in rows),
      "touch mode: the Wi-Fi network rows reach 44 x 44 (%d rows)" % len(rows))
view.close()

print(f"Quick settings pages: {checks} checks, 0 failures")
